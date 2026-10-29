defmodule Localize.Number.Rbnf do
  @moduledoc """
  Rules-Based Number Formatting (RBNF) for algorithmic number
  systems and spellout forms.

  RBNF provides formatting for number systems that don't have
  simple digit-to-digit mappings, such as Roman numerals, Hebrew
  numerals, Chinese numerals, and spellout forms like "one hundred
  twenty-three".

  RBNF rules are loaded from locale data at runtime and interpreted
  by an internal rule processor. Parsed rule ASTs are cached in
  `:persistent_term` for performance.

  ### Where a rule set is looked for

  A rule set is looked for in the locale's own data, then in each
  parent's in turn, and last in the root locale `und`, whose rules
  write Roman, Hebrew and other numerals. A locale without a
  spellout rule set gets an `Localize.UnknownRbnfRuleError` rather
  than root's digit stubs, so a number is never spelled in another
  language's words.

  CLDR keeps some locales' rules in a parent: Norwegian's spellout
  rules are in `no`, the parent of `nb` and `nn`, and `en-GB` has
  none of its own and takes English's from `en`. A parent's rules
  are reached only when the parent is a supported locale, since
  only a supported locale's data is installed. An application
  whose `supported_locales` names `nb` or `en-GB` lists `no` or
  `en` as well to spell numbers out in them. Until it does, the
  `Localize.UnknownRbnfRuleError` names that parent in its
  `:rules_in` field and its message.

  """

  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  alias Localize.Number.Rbnf.Processor
  alias Localize.Utils.Helpers

  @doc """
  Formats a number using RBNF rules.

  ### Arguments

  * `number` is an integer or float.

  * `rule_name` is the rule set name atom or string
    (e.g., `:spellout_cardinal`, `"roman-upper"`). The atoms
    `:spellout` and `:ordinal` are interpreted specially and
    map to the best available spellout or ordinal rule for
    the locale.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `:en`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the number, rule name or options are
    not valid, or the rules are not available.

  ### Examples

      iex> Localize.Number.Rbnf.to_string(123, :spellout_cardinal, locale: :en)
      {:ok, "one hundred twenty-three"}

      iex> Localize.Number.Rbnf.to_string(1, :spellout, locale: :en)
      {:ok, "one"}

      iex> Localize.Number.Rbnf.to_string(1, :ordinal, locale: :en)
      {:ok, "1st"}

  """
  @spec to_string(number() | Decimal.t(), atom() | String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(number, rule_name, options \\ [])

  def to_string(number, rule_name, options)
      when (is_number(number) or is_struct(number, Decimal)) and
             (is_atom(rule_name) or is_binary(rule_name)) and is_keyword_list(options) do
    requested_locale = Keyword.get(options, :locale, Localize.get_locale())

    case Localize.validate_locale(requested_locale) do
      {:ok, language_tag} ->
        lookup_and_format(rbnf_value(number), rule_name, language_tag)

      {:error, _} = error ->
        error
    end
  end

  def to_string(_number, _rule_name, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  def to_string(number, rule_name, _options) when is_number(number) or is_struct(number, Decimal),
    do: {:error, Localize.Utils.Helpers.invalid_value(rule_name, "a rule name atom or string")}

  def to_string(number, _rule_name, _options),
    do: {:error, Localize.Utils.Helpers.invalid_value(number, "a number or a Decimal")}

  # Coerce Decimal inputs to a native numeric type so the
  # `Localize.Number.Rbnf.Processor` (whose dispatch is built on
  # `is_integer/1`, `is_float/1`, `trunc/1`, `abs/1`, `<`, etc.)
  # doesn't need its own Decimal-aware arithmetic. Whole-valued
  # Decimals become integers (preserving exact integer-rule
  # dispatch for very large numbers); fractional Decimals become
  # floats. This means callers passing a Decimal whose value isn't
  # representable in IEEE 754 may see floating-point rounding —
  # acceptable for spellout output, where the typical use case is
  # small or whole numbers.
  # NaN and ±Infinity have no native numeric form for the processor, so
  # they are tagged and formatted by `format_non_finite/4`.
  defp rbnf_value(%Decimal{coef: :NaN}) do
    {:non_finite, :nan}
  end

  defp rbnf_value(%Decimal{coef: :inf, sign: -1}) do
    {:non_finite, :negative_infinity}
  end

  defp rbnf_value(%Decimal{coef: :inf}) do
    {:non_finite, :infinity}
  end

  defp rbnf_value(number) do
    coerce_number(number)
  end

  defp coerce_number(%Decimal{} = decimal) do
    if Decimal.integer?(decimal) do
      Decimal.to_integer(decimal)
    else
      Decimal.to_float(decimal)
    end
  end

  defp coerce_number(number), do: number

  # Look the rule up in each CLDR locale of the locale's inheritance
  # chain, its own first and `und` last, and format with the first that
  # has it. When none does, return an `UnknownRbnfRuleError` that reports
  # the requested locale.
  defp lookup_and_format(number, rule_name, language_tag) do
    with {:ok, requested_id} <- cldr_locale_id_from(language_tag) do
      language_tag
      |> locale_chain(requested_id)
      |> Enum.find_value(&format_in(number, rule_name, &1, requested_id))
      |> Kernel.||(
        {:error,
         Localize.UnknownRbnfRuleError.exception(
           rule_name: rule_name,
           locale: requested_id,
           available: available_rule_names(requested_id),
           rules_in: unlisted_rules_locale(language_tag, requested_id)
         )}
      )
    end
  end

  # The nearest ancestor of the locale with RBNF rules of its own, where
  # that ancestor is not a supported locale and so was not read: `no` for
  # `nb`, `en` for `en-GB`. `nil` where the locale has rules of its own,
  # where the ancestor was read, or where no ancestor has rules.
  defp unlisted_rules_locale(language_tag, requested_id) do
    language_tag
    |> nearest_rules_ancestor()
    |> unlisted(requested_id)
  end

  defp unlisted(nil, _requested_id) do
    nil
  end

  defp unlisted(requested_id, requested_id) do
    nil
  end

  defp unlisted(ancestor, _requested_id) do
    if ancestor in Localize.supported_locales() do
      nil
    else
      ancestor
    end
  end

  # Each parent is named by its own subtags, not by the supported locale
  # its tag resolves to, which is what hides an unlisted parent.
  defp nearest_rules_ancestor(language_tag) do
    case Localize.Locale.parent(language_tag) do
      {:ok, parent} -> rules_locale_or_next(parent)
      {:error, _no_parent} -> nil
    end
  end

  defp rules_locale_or_next(parent) do
    rules_locale = own_rules_locale(parent)

    if is_nil(rules_locale) do
      nearest_rules_ancestor(parent)
    else
      rules_locale
    end
  end

  defp own_rules_locale(%{language: language, script: script, territory: territory} = tag) do
    name = Localize.Locale.locale_id_from(language, script, territory, tag.language_variants)
    Enum.find(Localize.SupplementalData.rbnf_locales(), &(Atom.to_string(&1) == name))
  end

  defp format_in(number, rule_name, locale_id, requested_id) do
    case rule_set_in(rule_name, locale_id, requested_id) do
      {:ok, resolved_name, rule_set, all_rule_sets} ->
        # The digits are formatted in the requested locale; the plural forms of
        # `$(cardinal,…)$` come from the locale whose rules were found, since
        # they select among that locale's own words.
        format_with_rule_set(number, resolved_name, rule_set, all_rule_sets, %{
          locale: requested_id,
          plural_locale: Localize.Locale.data_locale_id(locale_id),
          rules_locale: locale_id
        })

      {:error, _not_in_this_locale} ->
        nil
    end
  end

  defp format_with_rule_set({:non_finite, kind}, _name, rule_set, all_rule_sets, context) do
    {:ok, format_non_finite(kind, rule_set.rules, all_rule_sets, context)}
  end

  defp format_with_rule_set(number, name, rule_set, all_rule_sets, context) do
    Processor.process(
      number,
      name,
      rule_set.rules,
      all_rule_sets,
      Map.delete(context, :rules_locale)
    )
  end

  # TR35 gives a rule set `NaN:` and `Inf:` rules, and a negative number
  # takes the `-x:` rule, so -∞ is the `-x:` rule's text around the
  # formatted ∞. TR35 does not say what a rule set without those rules
  # writes; ICU writes the locale's NaN or infinity symbol, and a minus
  # sign where there is no `-x:` rule, as the processor does for a
  # negative number reaching a special rule. CLDR's `NaN:` and `Inf:`
  # rules are plain text, and its `-x:` rules substitute with `>>`,
  # another rule set or a decimal format.
  defp format_non_finite(:nan, rules, _all_rule_sets, context) do
    rule_text(rules, "NaN") || non_finite_symbol(:nan, context)
  end

  defp format_non_finite(:infinity, rules, _all_rule_sets, context) do
    rule_text(rules, "Inf") || non_finite_symbol(:infinity, context)
  end

  defp format_non_finite(:negative_infinity, rules, all_rule_sets, context) do
    rule = Enum.find(rules, &(&1.base_value == "-x"))

    if is_nil(rule) do
      "-" <> format_non_finite(:infinity, rules, all_rule_sets, context)
    else
      negative_infinity(rule, rules, all_rule_sets, context)
    end
  end

  defp negative_infinity(rule, rules, all_rule_sets, context) do
    case Localize.Number.Rbnf.Rule.parse(rule.definition) do
      {:ok, parsed} ->
        Enum.map_join(parsed, &negative_infinity_part(&1, rules, all_rule_sets, context))

      {:error, _reason} ->
        "-" <> format_non_finite(:infinity, rules, all_rule_sets, context)
    end
  end

  defp negative_infinity_part({:literal, text}, _rules, _all_rule_sets, _context) do
    text
  end

  defp negative_infinity_part({:modulo, nil}, rules, all_rule_sets, context) do
    format_non_finite(:infinity, rules, all_rule_sets, context)
  end

  defp negative_infinity_part({:modulo, {:rule, name}}, rules, all_rule_sets, context) do
    case find_rule_set(all_rule_sets, Kernel.to_string(name), context.rules_locale) do
      {:ok, rule_set} -> format_non_finite(:infinity, rule_set.rules, all_rule_sets, context)
      {:error, _unknown} -> format_non_finite(:infinity, rules, all_rule_sets, context)
    end
  end

  defp negative_infinity_part({:modulo, {:format, format}}, _rules, _all_rule_sets, context) do
    case Localize.Number.to_string(Decimal.new("Inf"), format: format, locale: context.locale) do
      {:ok, string} -> string
      {:error, _reason} -> non_finite_symbol(:infinity, context)
    end
  end

  defp negative_infinity_part(_other, rules, all_rule_sets, context) do
    format_non_finite(:infinity, rules, all_rule_sets, context)
  end

  defp rule_text(rules, base_value) do
    rule = Enum.find(rules, &(&1.base_value == base_value))

    if is_nil(rule) do
      nil
    else
      rule.definition
    end
  end

  # The locale's NaN or infinity symbol in its default number system.
  defp non_finite_symbol(kind, context) do
    case default_symbols(context.locale) do
      {:ok, symbols} -> Map.fetch!(symbols, kind)
      {:error, _no_symbols} -> fallback_symbol(kind)
    end
  end

  defp default_symbols(locale) do
    with {:ok, system} <- Localize.Number.System.system_name_from(:default, locale) do
      Localize.Number.Symbol.number_symbols_for(locale, system)
    end
  end

  defp fallback_symbol(:nan) do
    "NaN"
  end

  defp fallback_symbol(:infinity) do
    "∞"
  end

  # The rule set of this name in this locale, with the locale's whole set of
  # rules, which `$(cardinal,…)$` and `%%rule` references are resolved in.
  defp rule_set_in(rule_name, locale_id, requested_id) do
    with {:ok, rbnf_data} <- load_rbnf_data(locale_id),
         {:ok, all_rule_sets} <- extract_rule_sets(rbnf_data),
         {:ok, resolved_name} <- resolve_rule_name(rule_name, all_rule_sets, locale_id),
         :ok <- reject_und_spellout_stub(locale_id, requested_id, resolved_name),
         {:ok, rule_set} <- find_rule_set(all_rule_sets, resolved_name, locale_id) do
      {:ok, resolved_name, rule_set, all_rule_sets}
    end
  end

  # The CLDR locales a locale's rules are looked up in: its own, then each
  # parent's (`he`, then `und`, whose rules write Hebrew and Roman
  # numerals). Found once a locale, since finding a parent revalidates its
  # tag, which took tens of milliseconds a call.
  defp locale_chain(language_tag, locale_id) do
    key = {__MODULE__, :locale_chain, locale_id}

    case :persistent_term.get(key, nil) do
      nil ->
        chain = parent_chain(language_tag, [locale_id])
        Localize.LiteralMemory.cache(key, chain)
        chain

      chain ->
        chain
    end
  end

  @doc false
  # Forgets every cached locale chain. A chain names the CLDR locale each
  # parent resolves to among the supported locales, so it is stale once the
  # supported locales change; `Localize.put_supported_locales/1` calls this.
  @spec clear_locale_chains() :: :ok
  def clear_locale_chains do
    :persistent_term.get()
    |> Enum.each(fn
      {{__MODULE__, :locale_chain, _locale_id} = key, _chain} -> :persistent_term.erase(key)
      _other -> :ok
    end)
  end

  defp parent_chain(language_tag, chain) do
    case named_parent(language_tag) do
      {:ok, parent, parent_id} -> parent_chain(parent, appended(chain, parent_id))
      :none -> chain
    end
  end

  # `:none` where a locale has no parent to walk to, which only `und` has not.
  defp named_parent(language_tag) do
    case Localize.Locale.parent(language_tag) do
      {:ok, parent} -> parent_with_id(parent)
      {:error, _no_parent} -> :none
    end
  end

  defp parent_with_id(parent) do
    case cldr_locale_id_from(parent) do
      {:ok, parent_id} -> {:ok, parent, parent_id}
      {:error, _unnameable_parent} -> :none
    end
  end

  defp appended(chain, parent_id) do
    if parent_id in chain, do: chain, else: chain ++ [parent_id]
  end

  # The `und` (root) locale's spellout rule sets are digit-format
  # stubs (`=#,##0.#=`). Falling back to them for a spellout request
  # would silently format digits instead of words — e.g. `ru` has
  # only gendered spellout rule sets, so `:spellout_cardinal` used
  # to fall through to `und` and return "2 000 000". Refuse the
  # `und` fallback for spellout-family rules (unless `und` was the
  # requested locale) so the caller gets an `UnknownRbnfRuleError`
  # listing the locale's actual rule sets. Non-spellout rules
  # (roman numerals, hebrew, digit ordinals, …) genuinely live in
  # `und` and still fall back normally.
  defp reject_und_spellout_stub(locale_id, requested_id, resolved_name) do
    if und?(locale_id) and not und?(requested_id) and spellout_family?(resolved_name) do
      {:error, :und_spellout_stub}
    else
      :ok
    end
  end

  # `cldr_locale_id_from/1` always returns an atom locale id.
  defp und?(locale_id), do: locale_id == :und

  defp spellout_family?(rule_name) do
    rule_name
    |> normalize_rule_name()
    |> String.starts_with?("spellout")
  end

  # The public rule set names for a locale, used to populate the
  # `available:` field of `UnknownRbnfRuleError`. Sorted for
  # deterministic output; empty when the locale has no RBNF data.
  defp available_rule_names(locale_id) do
    case rule_names_for_locale(locale_id) do
      {:ok, names} -> Enum.sort(names)
      {:error, _} -> []
    end
  end

  @doc """
  Returns the available RBNF rule names for a locale.

  ### Arguments

  * `locale` is a locale identifier atom or string.

  ### Returns

  * `{:ok, rule_names}` where `rule_names` is a sorted list of
    strings.

  * `{:error, exception}` if RBNF data is not available.

  ### Examples

      iex> {:ok, names} = Localize.Number.Rbnf.rule_names_for_locale(:en)
      iex> "spellout_cardinal" in names
      true

      iex> {:ok, names} = Localize.Number.Rbnf.rule_names_for_locale(:en)
      iex> "digits_ordinal" in names
      true

  """
  @spec rule_names_for_locale(Localize.locale() | String.t()) ::
          {:ok, [String.t()]} | {:error, Exception.t()}
  def rule_names_for_locale(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, rbnf_data} <- load_rbnf_data(language_tag),
         {:ok, all_rule_sets} <- extract_rule_sets(rbnf_data) do
      names =
        all_rule_sets
        |> Map.keys()
        |> Enum.map(&to_string_key/1)
        |> Enum.filter(fn name ->
          rule_set = all_rule_sets[name] || all_rule_sets[String.to_atom(name)]
          rule_set && Map.get(rule_set, :access, :public) == :public
        end)
        # A map's atom keys come back in the order the atoms were created,
        # which varies from one VM to the next.
        |> Enum.sort()

      {:ok, names}
    end
  end

  # ── Private helpers ──────────────────────────────────────────

  defp load_rbnf_data(locale_id) do
    Localize.Locale.get(locale_id, [:rbnf])
  end

  defp extract_rule_sets(rbnf_data) when is_map(rbnf_data) do
    # RBNF data is organized by rule group type:
    # %{SpelloutRules: %{spellout_cardinal: %{access: "public", rules: [...]}}}
    # Flatten into a single map of rule_name => rule_set
    all_sets =
      Enum.reduce(rbnf_data, %{}, fn {_group_type, rule_sets}, acc ->
        if is_map(rule_sets) do
          Map.merge(acc, rule_sets, &resolve_name_collision/3)
        else
          acc
        end
      end)

    {:ok, all_sets}
  end

  defp extract_rule_sets(_), do: {:error, "No RBNF data available"}

  defp find_rule_set(all_rule_sets, rule_name_str, locale_id) do
    # Try various key forms: string, atom, hyphenated, underscored
    rule_set =
      Map.get(all_rule_sets, rule_name_str) ||
        Map.get(all_rule_sets, safe_to_atom(rule_name_str)) ||
        Map.get(all_rule_sets, String.replace(rule_name_str, "_", "-")) ||
        Map.get(all_rule_sets, safe_to_atom(String.replace(rule_name_str, "_", "-"))) ||
        Map.get(all_rule_sets, String.replace(rule_name_str, "-", "_")) ||
        Map.get(all_rule_sets, safe_to_atom(String.replace(rule_name_str, "-", "_")))

    if rule_set do
      {:ok, %{rules: extract_rules(rule_set), access: Map.get(rule_set, :access, :public)}}
    else
      {:error,
       Localize.UnknownRbnfRuleError.exception(
         rule_name: rule_name_str,
         locale: locale_id,
         available: all_rule_sets |> Map.keys() |> Enum.map(&to_string_key/1) |> Enum.sort()
       )}
    end
  end

  # Resolve a rule_name argument to a concrete rule name string.
  #
  # The atoms `:spellout` and `:ordinal` are special: they map to
  # the "best available" rule in the locale's public rule sets.
  # Any other atom or string is returned unchanged in string form.
  # spellout-numbering leads the preferences: TR35 has `numbering`
  # "the default used when there is no context for the number", and it
  # exists in every locale
  # with spellout rules — including locales like de and ru that have
  # only gendered spellout-cardinal variants.
  defp resolve_rule_name(:spellout, all_rule_sets, locale_id) do
    resolve_best_rule(all_rule_sets, :spellout, locale_id, [
      "spellout-numbering",
      "spellout-cardinal",
      ~r/^spellout-cardinal-/,
      ~r/^spellout-/
    ])
  end

  defp resolve_rule_name(:ordinal, all_rule_sets, locale_id) do
    resolve_best_rule(all_rule_sets, :ordinal, locale_id, [
      "digits-ordinal",
      "spellout-ordinal",
      ~r/^digits-ordinal-/,
      ~r/^spellout-ordinal-/,
      ~r/-ordinal(-|$)/
    ])
  end

  defp resolve_rule_name(name, _all_rule_sets, _locale_id) do
    {:ok, normalize_rule_name(name)}
  end

  defp resolve_best_rule(all_rule_sets, requested, locale_id, preferences) do
    public_names = public_rule_names(all_rule_sets)

    match =
      Enum.find_value(preferences, fn preference ->
        preferred_rule_name(preference, public_names)
      end)

    if match do
      {:ok, match}
    else
      {:error,
       Localize.UnknownRbnfRuleError.exception(
         rule_name: requested,
         locale: locale_id,
         available: public_names
       )}
    end
  end

  defp preferred_rule_name(name, public_names) when is_binary(name) do
    if name in public_names, do: name
  end

  defp preferred_rule_name(%Regex{} = regex, public_names) do
    Enum.find(public_names, &Regex.match?(regex, &1))
  end

  # Sorted so regex-preference matching is deterministic — map
  # iteration order varies across OTP releases, which once made
  # `:spellout` pick a different gendered rule set per OTP version.
  defp public_rule_names(all_rule_sets) do
    all_rule_sets
    |> Enum.filter(fn {_key, rule_set} ->
      is_map(rule_set) and Map.get(rule_set, :access, :public) == :public
    end)
    |> Enum.map(fn {key, _rule_set} ->
      key |> to_string_key() |> String.replace("_", "-")
    end)
    |> Enum.sort()
  end

  # A rule set name is unique only within its group, so flattening the groups
  # can collide. CLDR 49 gave `en` a private `%%digits-ordinal` helper inside
  # SpelloutRules alongside the long-standing public `%digits-ordinal` in
  # OrdinalRules; under last-writer-wins the private one landed on top, which
  # demoted the public rule set and dropped `digits_ordinal` from
  # `rule_names_for_locale/1` altogether. Public wins a collision — it is the
  # one callers can name, and it is the one that carries the full rule list
  # (the private helper here lacks the `-x` negative rule).
  defp resolve_name_collision(_name, existing, replacement) do
    if rule_set_access(existing) == :public and rule_set_access(replacement) == :private do
      existing
    else
      replacement
    end
  end

  defp rule_set_access(rule_set) when is_map(rule_set) do
    case Map.get(rule_set, :access, :public) do
      :private -> :private
      "private" -> :private
      _public -> :public
    end
  end

  defp rule_set_access(_rule_set), do: :public

  defp extract_rules(%{rules: rules}) when is_list(rules), do: rules
  defp extract_rules(%{"rules" => rules}) when is_list(rules), do: rules
  defp extract_rules(rule_set) when is_map(rule_set), do: Map.get(rule_set, :rules, [])

  defp normalize_rule_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_rule_name(name) when is_binary(name), do: name

  defp cldr_locale_id_from(locale), do: Localize.Locale.cldr_locale_id_from(locale)

  defp to_string_key(key) when is_atom(key), do: Atom.to_string(key)
  defp to_string_key(key) when is_binary(key), do: key

  defp safe_to_atom(string), do: Helpers.existing_atom(string)
end
