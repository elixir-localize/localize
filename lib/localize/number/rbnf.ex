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

  """

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

  * `{:error, exception}` if the rules are not available.

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
  def to_string(number, rule_name, options \\ []) do
    requested_locale = Keyword.get(options, :locale, Localize.get_locale())

    case Localize.validate_locale(requested_locale) do
      {:ok, language_tag} ->
        lookup_and_format(coerce_number(number), rule_name, language_tag, language_tag)

      {:error, _} = error ->
        error
    end
  end

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
  defp coerce_number(%Decimal{} = decimal) do
    if Decimal.integer?(decimal) do
      Decimal.to_integer(decimal)
    else
      Decimal.to_float(decimal)
    end
  end

  defp coerce_number(number), do: number

  # Walk the locale inheritance chain looking for a matching RBNF
  # rule. If the current locale has no matching rule, fall back to
  # its parent locale via `Localize.Locale.parent/1` and retry. When
  # the chain terminates at `und`, return an `UnknownRbnfRuleError`
  # that reports the originally requested locale.
  defp lookup_and_format(number, rule_name, language_tag, requested_tag) do
    with {:ok, locale_id} <- cldr_locale_id_from(language_tag),
         {:ok, requested_id} <- cldr_locale_id_from(requested_tag),
         {:ok, rbnf_data} <- load_rbnf_data(locale_id),
         {:ok, all_rule_sets} <- extract_rule_sets(rbnf_data),
         {:ok, resolved_name} <- resolve_rule_name(rule_name, all_rule_sets, locale_id),
         :ok <- reject_und_spellout_stub(locale_id, requested_id, resolved_name),
         {:ok, rule_set} <- find_rule_set(all_rule_sets, resolved_name, locale_id) do
      Processor.process(
        number,
        resolved_name,
        rule_set.rules,
        all_rule_sets,
        requested_id
      )
    else
      {:error, %Localize.UnknownRbnfRuleError{}} ->
        fallback_to_parent(number, rule_name, language_tag, requested_tag)

      {:error, _other} ->
        fallback_to_parent(number, rule_name, language_tag, requested_tag)
    end
  end

  defp fallback_to_parent(number, rule_name, language_tag, requested_tag) do
    case Localize.Locale.parent(language_tag) do
      {:ok, parent_tag} ->
        lookup_and_format(number, rule_name, parent_tag, requested_tag)

      {:error, %Localize.NoParentError{}} ->
        with {:ok, requested_id} <- cldr_locale_id_from(requested_tag) do
          {:error,
           Localize.UnknownRbnfRuleError.exception(
             rule_name: rule_name,
             locale: requested_id,
             available: available_rule_names(requested_id)
           )}
        end
    end
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

  * `{:ok, rule_names}` where `rule_names` is a list of
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
  @spec rule_names_for_locale(atom() | String.t()) ::
          {:ok, [String.t()]} | {:error, Exception.t()}
  def rule_names_for_locale(locale) do
    with {:ok, locale_id} <- cldr_locale_id_from(locale),
         {:ok, rbnf_data} <- load_rbnf_data(locale_id),
         {:ok, all_rule_sets} <- extract_rule_sets(rbnf_data) do
      names =
        all_rule_sets
        |> Map.keys()
        |> Enum.map(&to_string_key/1)
        |> Enum.filter(fn name ->
          rule_set = all_rule_sets[name] || all_rule_sets[String.to_atom(name)]
          rule_set && Map.get(rule_set, :access, :public) == :public
        end)

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
          Map.merge(acc, rule_sets)
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
         available: all_rule_sets |> Map.keys() |> Enum.map(&to_string_key/1)
       )}
    end
  end

  # Resolve a rule_name argument to a concrete rule name string.
  #
  # The atoms `:spellout` and `:ordinal` are special: they map to
  # the "best available" rule in the locale's public rule sets.
  # Any other atom or string is returned unchanged in string form.
  # spellout-numbering leads the preferences: it is ICU's default
  # rule set for SPELLOUT formatting, and it exists in every locale
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
