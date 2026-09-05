defmodule Localize.Number.Rbnf.Processor do
  @moduledoc false

  # Runtime RBNF rule interpreter.
  #
  # Unlike ex_cldr which generates function clauses at compile time,
  # this processor interprets RBNF rules at runtime. Rules are parsed
  # on first use and cached in :persistent_term.

  alias Localize.Number.Rbnf.Rule
  alias Localize.Utils.Digits

  # # process/5
  # Processes a number through an RBNF rule set.
  #
  # ### Arguments
  # * `number` is an integer or float.
  # * `rule_set_name` is the rule set name string.
  # * `rules` is a list of rule maps from the locale data.
  # * `all_rule_sets` is the complete map of rule sets for
  #   the locale (for cross-referencing).
  # * `locale` is the locale identifier atom or string used by
  #   the public entry point. This is threaded through the
  #   processor so that `$(cardinal,…)` and `$(ordinal,…)`
  #   plural-keyed substitutions look up the correct plural
  #   form for the *requested* locale rather than always
  #   defaulting to English.
  #
  # ### Returns
  # * `{:ok, formatted_string}` or `{:error, reason}`.
  @spec process(number(), String.t(), list(), map(), atom() | String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def process(number, rule_set_name, rules, all_rule_sets, locale \\ :en) do
    case find_matching_rule(number, rules, locale) do
      nil ->
        {:error, "No matching rule for #{inspect(number)} in #{rule_set_name}"}

      rule ->
        process_matched_rule(number, rule, rule_set_name, rules, all_rule_sets, locale)
    end
  end

  defp process_matched_rule(number, rule, rule_set_name, rules, all_rule_sets, locale) do
    rule_struct =
      rule
      |> to_rule_struct()
      |> with_preceding_rule(rule, rules)

    # Synthesize a leading "-" when a negative number falls
    # through to a *special-base* rule (`0.x`, `x.x`, `x,x`,
    # `Inf`, `NaN`) that isn't itself `-x`. Without this,
    # locales whose rule set lacks a `-x` rule (e.g. ko
    # `spellout-numbering`) silently drop the sign because the
    # body's `<<` and `>>>` operate on the absolute-valued
    # digits emitted by `Digits.to_digits/1`.
    #
    # We must NOT synthesize a minus when the matched rule has
    # an integer base value: those rules typically delegate via
    # `=%cardinal=` (e.g. ja `spellout-numbering` is one rule
    # `=%spellout-cardinal=`), and the cardinal rule set has
    # its own `-x` handler that produces the locale-correct
    # word ("マイナス"/"moins"/"minus"/etc.). Stripping the
    # sign here would hide that handler.
    need_minus =
      number < 0 and special_base_other_than_minus_x?(rule_struct.base_value)

    effective_number = if need_minus, do: abs(number), else: number

    case Rule.parse(rule_struct.definition) do
      {:ok, parsed} ->
        result =
          do_rule(
            effective_number,
            rule_set_name,
            rule_struct,
            parsed,
            all_rule_sets,
            locale
          )

        case result do
          {:error, _} = error -> error
          string when is_binary(string) and need_minus -> {:ok, "-" <> string}
          string -> {:ok, string}
        end

      {:error, reason} ->
        {:error, "Failed to parse rule: #{inspect(reason)}"}
    end
  end

  # A "special-base" rule is one whose base value is a TR35-defined
  # symbolic string rather than an integer: `-x`, `0.x`, `x.x`,
  # `x,x`, `Inf`, `NaN`. We use this to decide whether to
  # synthesize a leading minus on a fall-through path (see
  # `process/4`): integer-base rules typically delegate to another
  # rule set via `=%name=` which can find `-x` itself, but
  # special-base rules apply directly and don't recurse for the
  # sign.
  defp special_base_other_than_minus_x?(base) when is_binary(base) do
    base != "-x" and base in ["0.x", "x.x", "x,x", "Inf", "NaN"]
  end

  defp special_base_other_than_minus_x?(_), do: false

  # Stash the source-order preceding rule on the matched rule
  # struct so `:modulo_preceding` (TR35 `>>>`) can apply it for
  # integer modulo without re-running rule selection. Source
  # order is the *original* `rules` list, not the descending-
  # base-value sort produced by `find_matching_integer_rule/2`.
  defp with_preceding_rule(rule_struct, original_rule, rules) do
    %{rule_struct | preceding_rule: preceding_chain(get_base_value(original_rule), rules)}
  end

  # The chain is built all the way down, not one link. `>>>` formats the
  # remainder with the rule preceding the current one in source order, and
  # that rule may use `>>>` in turn. Japanese year digits are `1000: <<>>>`
  # over `100: <<>>>` over `10: <<>>>` over `0: =%spellout-numbering=`, and
  # 1001 spells "一〇〇一" only if each level can reach its own predecessor.
  # Linking a single level left the second `>>>` with none, so it fell back to
  # ordinary rule selection and lost a digit ("一〇一").
  defp preceding_chain(base_value, rules) do
    case Enum.find_index(rules, &(get_base_value(&1) == base_value)) do
      nil ->
        nil

      0 ->
        nil

      index ->
        preceding = Enum.at(rules, index - 1)

        preceding
        |> to_rule_struct()
        |> Map.put(:preceding_rule, preceding_chain(get_base_value(preceding), rules))
    end
  end

  # ── Rule matching ──────────────────────────────────────────

  defp find_matching_rule(number, rules, locale) when is_number(number) and number < 0 do
    # Look for -x rule first
    Enum.find(rules, fn rule ->
      base = get_base_value(rule)
      base == "-x"
    end) || find_matching_rule(abs(number), rules, locale)
  end

  defp find_matching_rule(number, rules, locale) when is_float(number) do
    # Per TR35: when the integer part is zero but the value is
    # non-zero (e.g. `0.05`), prefer the `0.x` rule if the locale
    # defines one. This is currently used by `ee` and `ko`. Falls
    # back to the locale-conventional `x.x`/`x,x` rule, then to
    # integer rule selection on `trunc(number)`.
    zero_x_rule =
      if trunc(number) == 0 and number != 0.0 do
        Enum.find(rules, fn rule -> get_base_value(rule) == "0.x" end)
      end

    zero_x_rule || decimal_separator_rule(rules, locale) ||
      find_matching_integer_rule(trunc(number), rules)
  end

  defp find_matching_rule(number, rules, _locale) when is_integer(number) do
    find_matching_integer_rule(number, rules)
  end

  # A locale may define both `x.x` and `x,x` — Catalan spells 0.5 as "zero
  # punt cinc" under one and "zero coma cinc" under the other — and the one
  # to use is the one matching the locale's own decimal separator. Taking
  # whichever appeared first in the rule list meant `ca`, `es` and every
  # other comma locale that ships both was spelled with the point form.
  defp decimal_separator_rule(rules, locale) do
    preferred = if decimal_separator(locale) == ",", do: "x,x", else: "x.x"

    Enum.find(rules, &(get_base_value(&1) == preferred)) ||
      Enum.find(rules, &(get_base_value(&1) in ["x.x", "x,x"]))
  end

  defp decimal_separator(locale) do
    case Localize.Number.Symbol.number_symbols_for(locale) do
      {:ok, %{latn: %Localize.Number.Symbol{decimal: %{standard: separator}}}}
      when is_binary(separator) ->
        separator

      _no_latin_symbols ->
        "."
    end
  end

  defp find_matching_integer_rule(number, rules) do
    # Filter to integer rules sorted by base_value descending
    integer_rules =
      rules
      |> Enum.filter(fn rule ->
        base = get_base_value(rule)
        is_integer(base)
      end)
      |> Enum.sort_by(&get_base_value/1, :desc)

    # Find the first rule (highest base_value) where base <= number
    # and range allows it
    # Fallback: rule with base_value 0
    Enum.find(integer_rules, fn rule ->
      base = get_base_value(rule)
      range = get_range(rule)

      base <= number and
        (range == "undefined" or range == nil or
           (is_integer(range) and number < range))
    end)
    |> prefer_exact_multiple_rule(number, integer_rules)
    |> Kernel.||(Enum.find(integer_rules, &(get_base_value(&1) == 0)))
  end

  # RBNF's standard idiom pairs a rule for exact multiples with one for the
  # same magnitude carrying a remainder, the second numbered one higher:
  # Burmese has `100: <<ရာ;` beside `101: <<ရာ့[>>];`. Selecting purely on
  # "largest base value not above the number" always picks the second, so 200
  # was spelled "နှစ်ရာ့" with the remainder form's suffix and no remainder to
  # justify it. When the number divides exactly and the rule immediately below
  # is the same magnitude, that rule is the one meant.
  defp prefer_exact_multiple_rule(nil, _number, _rules), do: nil

  defp prefer_exact_multiple_rule(rule, number, rules) do
    base = get_base_value(rule)
    divisor = get_divisor(rule)

    # The pair is the rule immediately below by base value — `100`/`101` in
    # Burmese, `3000`/`3001` in the Hebrew numbering rules. A divisor above 1
    # keeps ordinary neighbours out (English's `1:` and `2:` divide by 1, and
    # everything is an exact multiple of 1), and `spells_the_quotient?/1` is
    # what separates a genuine pair from two unrelated rules that happen to be
    # numbered consecutively.
    with true <- is_integer(divisor) and divisor > 1,
         0 <- rem(number, divisor),
         preceding when not is_nil(preceding) <-
           Enum.find(rules, &(get_base_value(&1) == base - 1)),
         true <- spells_the_quotient?(preceding) do
      preceding
    else
      _not_an_exact_multiple_pair -> rule
    end
  end

  # The lower rule of the pair only stands in for an exact multiple if it
  # spells the quotient. Burmese's `100: <<ရာ;` does, so it covers 200 and
  # 300; Hebrew's `10: עשרת;` is a bare literal for ten alone, and pressing it
  # into service for 20 spelled "ten". Maltese pairs the same way.
  defp spells_the_quotient?(rule) do
    definition = get_definition(rule) || ""
    String.contains?(definition, "<<") or String.contains?(definition, "←←")
  end

  defp get_definition(%Rule{definition: definition}), do: definition
  defp get_definition(rule) when is_map(rule), do: rule[:definition] || rule["definition"]

  defp get_divisor(%Rule{divisor: divisor}), do: divisor
  defp get_divisor(rule) when is_map(rule), do: rule[:divisor] || rule["divisor"]

  # ── Rule execution ─────────────────────────────────────────

  defp do_rule(number, rule_set_name, rule, parsed, all_rule_sets, locale) do
    results =
      Enum.map(parsed, fn {operation, argument} ->
        do_operation(operation, number, rule_set_name, rule, argument, all_rule_sets, locale)
      end)

    if Enum.any?(results, &match?({:error, _}, &1)) do
      errors =
        results
        |> Enum.filter(&match?({:error, _}, &1))
        |> Enum.map_join(", ", fn {:error, msg} -> msg end)

      {:error, errors}
    else
      results
      |> Enum.map_join(fn
        s when is_binary(s) -> s
        other -> to_string(other)
      end)
    end
  end

  # ── Operations ─────────────────────────────────────────────

  defp do_operation(:literal, _number, _rule_set, _rule, string, _all_sets, _locale) do
    string
  end

  # Modulo for negative numbers (-x rule)
  defp do_operation(:modulo, number, rule_set, _rule, argument, all_sets, locale)
       when is_number(number) and number < 0 do
    case argument do
      {:rule, rule_name} ->
        apply_rule_set(abs(number), to_string(rule_name), all_sets, locale)

      nil ->
        apply_rule_set(abs(number), rule_set, all_sets, locale)

      {:format, format} ->
        format_with_pattern(abs(number), format, locale)
    end
  end

  # Modulo for float (fraction processing).
  #
  # The `nil` arg case is the common one: `>>` on a fraction →
  # spell each digit. The `{:rule, _}` and `{:format, _}` cases
  # are exercised by a small number of locales (e.g. ky's
  # `%spellout-cardinal x.x: ←← бүтүн →%%z-spellout-fraction→`).
  # TR35 specifies a numerator/denominator algorithm for those
  # cases; we provide non-crashing best-effort handling here and
  # leave the full algorithm as a follow-up. See plans/rbnf.md.
  defp do_operation(:modulo, number, rule_set, _rule, nil, all_sets, locale)
       when is_float(number) do
    format_fraction(number, rule_set, all_sets, " ", locale)
  end

  defp do_operation(:modulo, number, _rule_set, _rule, {:rule, rule_name}, all_sets, locale)
       when is_float(number) do
    # Full TR35 fraction-with-rule numerator/denominator
    # algorithm: rule selection runs against the denominator
    # (smallest power of the radix ≥ the fractional part's
    # reciprocal), and `<<` in the matched rule body substitutes
    # the numerator. Used by ky `%%z-spellout-fraction`
    # (`x.x: ←← бүтүн →%%z-spellout-fraction→`); produces e.g.
    # `1.5 ky → бир бүтүн ондон беш` instead of the prior
    # best-effort `бир бүтүн беш`.
    format_fraction_via_rule(number, to_string(rule_name), all_sets, locale)
  end

  defp do_operation(:modulo, number, _rule_set, _rule, {:format, format}, _all_sets, locale)
       when is_float(number) do
    # Apply the decimal-format pattern to the fractional digits
    # treated as an integer.
    {digits, exp, _sign} = Digits.to_digits(number)

    fraction =
      cond do
        exp >= length(digits) -> 0
        exp >= 0 -> digits |> Enum.drop(exp) |> Integer.undigits()
        exp < 0 -> Integer.undigits(List.duplicate(0, -exp) ++ digits)
      end

    format_with_pattern(fraction, format, locale)
  end

  # Modulo for integers
  defp do_operation(:modulo, number, rule_set, rule, argument, all_sets, locale)
       when is_integer(number) do
    mod = number - div(number, rule.divisor) * rule.divisor

    case argument do
      {:rule, rule_name} ->
        apply_rule_set(mod, to_string(rule_name), all_sets, locale)

      nil ->
        apply_rule_set(mod, rule_set, all_sets, locale)

      {:format, format} ->
        format_with_pattern(mod, format, locale)
    end
  end

  # `>>>` (modulo-preceding): per TR35, bypasses normal rule
  # selection and applies the rule preceding this one in the rule
  # list. In the fraction context (the common case — ja, ko, zh,
  # th, lo, km, ak, yue, root all use it for `x.x` rules) it also
  # signals that the per-digit results should be concatenated
  # without a separator, producing e.g. zh `三点一四` rather than
  # `三点一 四`.
  #
  # The "preceding rule" semantic for non-fraction integer modulo
  # is not exercised by any locale in current CLDR data; for that
  # case we fall back to standard rule-selection on the remainder.
  defp do_operation(:modulo_preceding, number, rule_set, _rule, nil, all_sets, locale)
       when is_float(number) do
    format_fraction(number, rule_set, all_sets, "", locale)
  end

  # `>>>` for integers: TR35 says "bypass normal rule selection
  # and apply the rule preceding this one in the rule list".
  # Compute the modulo and walk the *preceding* rule's body
  # directly. Falls through to `:modulo` (same-rule-set selection)
  # when no preceding rule is available — at-source-list-position
  # 0, or for the synthesized special-base path that has no
  # source neighbour.
  defp do_operation(
         :modulo_preceding,
         number,
         rule_set,
         %Rule{preceding_rule: preceding} = rule,
         argument,
         all_sets,
         locale
       )
       when is_integer(number) and not is_nil(preceding) do
    mod = number - div(number, rule.divisor) * rule.divisor

    apply_preceding_rule(mod, preceding, rule_set, all_sets, locale, argument)
  end

  defp do_operation(:modulo_preceding, number, rule_set, rule, argument, all_sets, locale) do
    do_operation(:modulo, number, rule_set, rule, argument, all_sets, locale)
  end

  # Quotient for float (integer part). The float case takes the
  # integer part of the number (`trunc/1`) and then applies the
  # caller-specified rule set, named rule, or decimal format. The
  # named-rule and decimal-format variants are needed because
  # locale `0.x` rules use `<%spellout-cardinal-sinokorean<` on
  # the integer side (e.g. ko); without these clauses the `0.x`
  # path crashes on a float input.
  defp do_operation(:quotient, number, rule_set, _rule, nil, all_sets, locale)
       when is_float(number) do
    apply_rule_set(trunc(number), rule_set, all_sets, locale)
  end

  defp do_operation(:quotient, number, _rule_set, _rule, {:rule, rule_name}, all_sets, locale)
       when is_float(number) do
    apply_rule_set(trunc(number), to_string(rule_name), all_sets, locale)
  end

  defp do_operation(
         :quotient,
         number,
         _rule_set,
         _rule,
         {:format, format},
         _all_sets,
         locale
       )
       when is_float(number) do
    format_with_pattern(trunc(number), format, locale)
  end

  # Quotient for integers. The TR35 syntax allows three argument
  # shapes — `<<` (no descriptor), `<%name<` (named rule), and
  # `<#,##0<` (decimal format). Real CLDR data exercises the third
  # form in private rule sets such as ky's `%%z-spellout-fraction`
  # at base 10^12. Without the `{:format, _}` clause the case
  # raises `no case clause matching: {:format, "..."}`.
  #
  # When the rule has a non-nil `:fraction_numerator` field
  # (set by `format_fraction_via_rule/4`), `<<` substitutes the
  # numerator directly rather than computing
  # `div(denominator, rule.divisor)`. This implements the TR35
  # numerator/denominator algorithm for `>%name>` substitutions
  # on a float in a parent rule's body.
  defp do_operation(:quotient, number, rule_set, rule, argument, all_sets, locale)
       when is_integer(number) do
    divisor =
      case rule do
        %{fraction_numerator: numerator} when is_integer(numerator) -> numerator
        _ -> div(number, rule.divisor)
      end

    case argument do
      {:rule, rule_name} ->
        apply_rule_set(divisor, to_string(rule_name), all_sets, locale)

      nil ->
        apply_rule_set(divisor, rule_set, all_sets, locale)

      {:format, format} ->
        format_with_pattern(divisor, format, locale)
    end
  end

  # Call another rule or format
  defp do_operation(:call, number, _rule_set, _rule, {:format, format}, _all_sets, locale) do
    format_with_pattern(number, format, locale)
  end

  defp do_operation(:call, number, _rule_set, _rule, {:rule, rule_name}, all_sets, locale) do
    apply_rule_set(number, to_string(rule_name), all_sets, locale)
  end

  # Plural operations — use the requested locale (Bug L). Without
  # this, every plural-keyed substitution looked up the form in
  # English, which is correct for `:en` only and for any locale
  # whose rule body uses the same value for every plural key.
  # Locales whose ordinal/cardinal categories differ from English
  # for the input number (notably fr where `21` is `:other` not
  # `:one`, producing `21e` not `21er`) now select the right key.
  # Per TR35/ICU (`NFRule::doFormat`), the plural category for a
  # `$(cardinal,…)$` / `$(ordinal,…)$` substitution is selected on
  # the value divided by the rule's divisor — the quotient the rule
  # body spells out — not on the full number. Russian `2_000_000`
  # with the base-1000000 rule spells the quotient `2`, so the
  # plural is `plural(2)` → `:few` → "миллиона", not
  # `plural(2_000_000)` → `:many` → "миллионов". For values below 1
  # (fraction rules) ICU selects on `round(number * divisor)`.
  defp do_operation(:ordinal, number, _rule_set, rule, plurals, _all_sets, locale) do
    plural = Localize.Number.PluralRule.Ordinal.plural_rule(plural_operand(number, rule), locale)
    Map.get(plurals, plural) || Map.get(plurals, :other, "")
  end

  defp do_operation(:cardinal, number, _rule_set, rule, plurals, _all_sets, locale) do
    plural =
      Localize.Number.PluralRule.Cardinal.plural_rule(plural_operand(number, rule), locale)

    Map.get(plurals, plural) || Map.get(plurals, :other, "")
  end

  # Conditional: only process if modulo > 0
  defp do_operation(:conditional, number, rule_set, rule, argument, all_sets, locale)
       when is_integer(number) do
    mod = number - div(number, rule.divisor) * rule.divisor

    if mod > 0 do
      do_rule(mod, rule_set, rule, argument, all_sets, locale)
    else
      ""
    end
  end

  # A fraction rule (`x.x`) brackets the integer part, and the bracket is
  # taken when that part is non-zero: Russian's
  # `x.x: [<…< $(cardinal,one{целой}other{целыми})$ ]>%%fractions…>` renders
  # 1.5 as "одной целой пятью десятыми" and 0.5 as just "пятью десятыми".
  # Returning "" for every non-integer dropped the integer part from all of
  # them.
  defp do_operation(:conditional, number, rule_set, rule, argument, all_sets, locale)
       when is_float(number) do
    if trunc(abs(number)) > 0 do
      do_rule(number, rule_set, rule, argument, all_sets, locale)
    else
      ""
    end
  end

  defp do_operation(:conditional, _number, _rule_set, _rule, _argument, _all_sets, _locale) do
    ""
  end

  # CLDR 49's `[A|B]`: A when the remainder is non-zero, B when it is zero.
  # Where the plain `[A]` form renders nothing in the zero case, this renders
  # B — which is how `twent[y->>|ieth]` yields both "twenty-first" and
  # "twentieth" from a single rule, replacing CLDR 48's `%%tieth` helper.
  defp do_operation(
         :conditional_alternate,
         number,
         rule_set,
         rule,
         {present, absent},
         all_sets,
         locale
       )
       when is_integer(number) do
    mod = number - div(number, rule.divisor) * rule.divisor
    branch = if mod > 0, do: present, else: absent

    # Both branches are evaluated against the original number, not the
    # remainder. A branch may carry a quotient substitution as well as a
    # remainder one — Russian's `200: [<%spellout-cardinal-feminine<сти >>|…]`
    # needs `<<` to see 201 so it can spell "две", and passing the remainder
    # gave it 0 and spelled "ноль". `>>` reaches the same value either way,
    # since it takes the remainder of whatever it is given.
    do_rule(number, rule_set, rule, branch, all_sets, locale)
  end

  # A non-integer has no whole remainder to test. The plain form omits its
  # content here, so the alternation renders the branch that stands for
  # omission.
  defp do_operation(
         :conditional_alternate,
         number,
         rule_set,
         rule,
         {_present, absent},
         all_sets,
         locale
       ) do
    do_rule(number, rule_set, rule, absent, all_sets, locale)
  end

  # ── Helpers ────────────────────────────────────────────────

  # The value on which `$(cardinal,…)$` / `$(ordinal,…)$` selects
  # its plural category: the number divided by the rule's divisor
  # (see the comment on `do_operation(:ordinal, …)` above).
  # In the fraction-with-rule path the rule body runs against the
  # *denominator*, with `<<` substituting the numerator (see
  # `format_fraction_via_rule/4`). The plural has to agree with the number
  # actually spelled, so it selects on the numerator too. Russian's
  # `10: <…< $(cardinal,one{десятой}other{десятыми})$` spells 0.5 as "пятью
  # десятыми": five, so `other`. Selecting on the denominator gave
  # `div(10, 10)` — one — and the singular "десятой".
  defp plural_operand(_number, %Rule{fraction_numerator: numerator})
       when is_integer(numerator) do
    numerator
  end

  defp plural_operand(number, %Rule{divisor: divisor}) when is_integer(divisor) and divisor > 0 do
    cond do
      number >= 0 and number < 1 -> round(number * divisor)
      is_integer(number) -> div(number, divisor)
      true -> trunc(number / divisor)
    end
  end

  defp plural_operand(number, _rule), do: number

  defp apply_rule_set(number, rule_set_name, all_rule_sets, locale) do
    # Normalize rule set name (CLDR uses hyphens, we may use underscores)
    normalized_name = String.replace(rule_set_name, "-", "_")

    rule_set =
      find_rule_set(all_rule_sets, rule_set_name) ||
        find_rule_set(all_rule_sets, normalized_name)

    case rule_set do
      nil ->
        {:error, "Rule set #{inspect(rule_set_name)} not found"}

      %{rules: rules} ->
        case process(number, rule_set_name, rules, all_rule_sets, locale) do
          {:ok, result} -> result
          {:error, _} = error -> error
        end
    end
  end

  @dialyzer {:nowarn_function, find_rule_set: 2}
  defp find_rule_set(all_rule_sets, name) when is_binary(name) do
    # Try direct string match, then atom match, then underscore/hyphen variations
    # Also handle the "r" prefix for rule names that start with digits
    # (ex_cldr renames "2d_year" to "r2d_year" for valid function names,
    # but in our data the key is :"2d_year")
    stripped = strip_r_prefix(name)

    Map.get(all_rule_sets, name) ||
      Map.get(all_rule_sets, String.to_atom(name)) ||
      Map.get(all_rule_sets, String.replace(name, "_", "-")) ||
      Map.get(all_rule_sets, String.to_atom(String.replace(name, "_", "-"))) ||
      (stripped != name && find_rule_set(all_rule_sets, stripped)) ||
      nil
  end

  defp find_rule_set(all_rule_sets, name) when is_atom(name) do
    Map.get(all_rule_sets, name) ||
      Map.get(all_rule_sets, Atom.to_string(name))
  end

  # Strip "r" prefix added by ex_cldr for function names that start with digits
  defp strip_r_prefix("r" <> rest = _name) do
    if String.match?(rest, ~r/^[0-9]/) do
      rest
    else
      "r" <> rest
    end
  end

  defp strip_r_prefix(name), do: name

  # Decimal-format substitutions (`=#,##0=`, `<#,##0<`, `>#,##0>`)
  # format with the RBNF rule's locale, not the process locale — the
  # grouping separator must be the locale's own (fr "1 141e",
  # de "1.141."). English's comma masked this when the locale was
  # dropped.
  defp format_with_pattern(number, format, locale) do
    case Localize.Number.to_string(number, format: format, locale: locale) do
      {:ok, result} -> result
      {:error, _} -> to_string(number)
    end
  end

  defp format_fraction(number, rule_set, all_sets, separator, locale) do
    number
    |> fractional_digit_list()
    |> Enum.map_join(separator, fn n ->
      # TR35 spells each fraction digit with the *current* rule set, so a
      # case-marked or gendered set carries into the fraction: Finnish
      # `%spellout-cardinal-allative-plural` renders 0.5 as "nollille pilkku
      # viisille", not "... viisi". Trying `spellout_numbering` first
      # inverted that and answered in the nominative for every such set.
      #
      # It stays as the fallback: a rule set need not define rules for the
      # single digits, and `spellout_numbering` always does.
      case apply_rule_set(n, rule_set, all_sets, locale) do
        {:error, _} -> apply_rule_set_or_string(n, "spellout_numbering", all_sets, locale)
        result -> result
      end
    end)
  end

  # TR35 fraction-with-rule numerator/denominator algorithm.
  #
  # When a rule body uses `>%name>` (or its arrow form `→%name→`) on
  # a fractional value, ICU and TR35 specify that:
  #
  #   1. The denominator is the smallest power of the radix
  #      (typically `10^digit_count`) that admits the fractional
  #      part as an integer numerator.
  #   2. Rule selection in the named rule set is run against the
  #      *denominator*.
  #   3. The matched rule's body executes against the denominator
  #      as the formatted number, BUT any `<<` substitution
  #      substitutes the numerator directly rather than computing
  #      `div(denominator, rule.divisor)`.
  #
  # The numerator override is carried in `Rule.fraction_numerator`
  # and read by `do_operation(:quotient, integer, ...)` below.
  #
  # Example — ky `1.5 spellout-cardinal`:
  #
  #   x.x rule body: `←← бүтүн →%%z-spellout-fraction→`
  #
  #   * `<<` on integer 1 → `бир`
  #   * Literal ` бүтүн `
  #   * `>%%z-spellout-fraction>` on fraction 0.5:
  #       numerator = 5, denominator = 10
  #       %%z-spellout-fraction base-10 rule body: `ондон ←%spellout-numbering←`
  #       Apply with denominator 10, numerator override = 5:
  #         literal `ондон `
  #         `<%spellout-numbering<` → numerator override = 5 →
  #           apply spellout-numbering(5) → `беш`
  #       Result: `ондон беш`
  #   * Final: `бир бүтүн ондон беш`
  defp format_fraction_via_rule(number, rule_set_name, all_sets, locale) do
    digits = fractional_digit_list(number)

    cond do
      digits == [] ->
        ""

      digits == [0] ->
        # Integer-valued float (e.g. 1.0). No fraction to format.
        ""

      true ->
        denominator = Integer.pow(10, length(digits))
        numerator = Integer.undigits(digits)

        case lookup_rule_set(all_sets, rule_set_name) do
          nil ->
            # Fall back to digit-by-digit through the named rule
            # set if it can't be found.
            format_fraction(number, rule_set_name, all_sets, " ", locale)

          %{rules: rules} ->
            apply_fraction_rule(
              numerator,
              denominator,
              rule_set_name,
              rules,
              all_sets,
              locale
            )
        end
    end
  end

  defp apply_fraction_rule(numerator, denominator, rule_set_name, rules, all_sets, locale) do
    case find_matching_rule(denominator, rules, locale) do
      nil ->
        Integer.to_string(numerator)

      rule ->
        apply_matched_fraction_rule(
          rule,
          numerator,
          denominator,
          rule_set_name,
          all_sets,
          locale
        )
    end
  end

  defp apply_matched_fraction_rule(
         rule,
         numerator,
         denominator,
         rule_set_name,
         all_sets,
         locale
       ) do
    rule_struct = to_rule_struct(rule)
    wrapped = %{rule_struct | fraction_numerator: numerator}

    case Rule.parse(rule_struct.definition) do
      {:ok, parsed} ->
        case do_rule(denominator, rule_set_name, wrapped, parsed, all_sets, locale) do
          {:error, _} -> Integer.to_string(numerator)
          string when is_binary(string) -> string
        end

      {:error, _} ->
        Integer.to_string(numerator)
    end
  end

  defp lookup_rule_set(all_rule_sets, rule_set_name) do
    normalized_name = String.replace(rule_set_name, "-", "_")

    find_rule_set(all_rule_sets, rule_set_name) ||
      find_rule_set(all_rule_sets, normalized_name)
  end

  # Returns the fractional digits of a number as a list, preserving
  # leading zeros that `Digits.fraction_as_integer/1` would discard.
  # `Digits.to_digits/1` returns `{digits, exp, sign}` where `exp`
  # is the position of the decimal point relative to the digit list:
  #
  #   * `exp >= length(digits)` — integer-valued float (e.g. `1.0`,
  #     `100.0`); we emit a single `[0]` so the rule still produces
  #     a "point zero" tail (preserving the prior behaviour rather
  #     than silently dropping the literal in `←← point →→`).
  #   * `exp >= 0` — slice off the integer part; the remainder may
  #     start with zeros (e.g. `3.04` → `[3, 0, 4]` exp `1` →
  #     fraction `[0, 4]`).
  #   * `exp < 0` — the fraction has `-exp` leading zeros before the
  #     first non-zero digit (e.g. `0.05` → `[5]` exp `-1` →
  #     fraction `[0, 5]`).
  defp fractional_digit_list(number) do
    case Digits.to_digits(number) do
      {digits, exp, _sign} when exp >= length(digits) -> [0]
      {digits, exp, _sign} when exp >= 0 -> Enum.drop(digits, exp)
      {digits, exp, _sign} -> List.duplicate(0, -exp) ++ digits
    end
  end

  # Apply a *specific* rule (typically the source-order preceding
  # rule, found via `with_preceding_rule/3`) to a value, bypassing
  # `find_matching_rule/2` rule selection. Used by `>>>` (TR35
  # `:modulo_preceding`) for integers. Falls back to standard
  # rule-selection on the same rule set on parse error.
  defp apply_preceding_rule(value, preceding_rule, rule_set, all_sets, locale, _argument) do
    rule_struct = to_rule_struct(preceding_rule)

    case Rule.parse(rule_struct.definition) do
      {:ok, parsed} ->
        case do_rule(value, rule_set, rule_struct, parsed, all_sets, locale) do
          {:error, _} -> apply_rule_set(value, rule_set, all_sets, locale)
          string when is_binary(string) -> string
        end

      {:error, _} ->
        apply_rule_set(value, rule_set, all_sets, locale)
    end
  end

  defp apply_rule_set_or_string(number, rule_set, all_sets, locale) do
    case apply_rule_set(number, rule_set, all_sets, locale) do
      {:error, _} -> to_string(number)
      result -> result
    end
  end

  # ── Data extraction helpers ────────────────────────────────

  defp get_base_value(%{base_value: base}) when is_integer(base), do: base
  defp get_base_value(%{base_value: base}) when is_binary(base), do: base
  defp get_base_value(%{"base_value" => base}) when is_integer(base), do: base
  defp get_base_value(%{"base_value" => base}) when is_binary(base), do: base
  defp get_base_value(_), do: 0

  defp get_range(%{range: range}), do: range
  defp get_range(%{"range" => range}), do: range
  defp get_range(_), do: "undefined"

  defp to_rule_struct(%Rule{} = rule), do: rule

  defp to_rule_struct(rule) when is_map(rule) do
    %Rule{
      base_value: rule[:base_value] || rule["base_value"],
      radix: rule[:radix] || rule["radix"] || 10,
      definition: rule[:definition] || rule["definition"],
      range: rule[:range] || rule["range"],
      divisor: rule[:divisor] || rule["divisor"] || 1
    }
  end
end
