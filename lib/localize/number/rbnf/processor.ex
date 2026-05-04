defmodule Localize.Number.Rbnf.Processor do
  @moduledoc false

  # Runtime RBNF rule interpreter.
  #
  # Unlike ex_cldr which generates function clauses at compile time,
  # this processor interprets RBNF rules at runtime. Rules are parsed
  # on first use and cached in :persistent_term.

  alias Localize.Number.Rbnf.Rule
  alias Localize.Utils.Digits

  # # process/4
  # Processes a number through an RBNF rule set.
  #
  # ### Arguments
  # * `number` is an integer or float.
  # * `rule_set_name` is the rule set name string.
  # * `rules` is a list of rule maps from the locale data.
  # * `all_rule_sets` is the complete map of rule sets for
  #   the locale (for cross-referencing).
  #
  # ### Returns
  # * `{:ok, formatted_string}` or `{:error, reason}`.
  @spec process(number(), String.t(), list(), map()) ::
          {:ok, String.t()} | {:error, String.t()}
  def process(number, rule_set_name, rules, all_rule_sets) do
    case find_matching_rule(number, rules) do
      nil ->
        {:error, "No matching rule for #{inspect(number)} in #{rule_set_name}"}

      rule ->
        rule_struct = to_rule_struct(rule)

        case Rule.parse(rule_struct.definition) do
          {:ok, parsed} ->
            result = do_rule(number, rule_set_name, rule_struct, parsed, all_rule_sets)

            case result do
              {:error, _} = error -> error
              string -> {:ok, string}
            end

          {:error, reason} ->
            {:error, "Failed to parse rule: #{inspect(reason)}"}
        end
    end
  end

  # ── Rule matching ──────────────────────────────────────────

  defp find_matching_rule(number, rules) when is_number(number) and number < 0 do
    # Look for -x rule first
    Enum.find(rules, fn rule ->
      base = get_base_value(rule)
      base == "-x"
    end) || find_matching_rule(abs(number), rules)
  end

  defp find_matching_rule(number, rules) when is_float(number) do
    # Per TR35: when the integer part is zero but the value is
    # non-zero (e.g. `0.05`), prefer the `0.x` rule if the locale
    # defines one. This is currently used by `ee` and `ko`. Falls
    # back to the locale-conventional `x.x`/`x,x` rule, then to
    # integer rule selection on `trunc(number)`.
    zero_x_rule =
      if trunc(number) == 0 and number != 0.0 do
        Enum.find(rules, fn rule -> get_base_value(rule) == "0.x" end)
      end

    x_x_rule =
      Enum.find(rules, fn rule ->
        base = get_base_value(rule)
        base in ["x.x", "x,x"]
      end)

    zero_x_rule || x_x_rule || find_matching_integer_rule(trunc(number), rules)
  end

  defp find_matching_rule(number, rules) when is_integer(number) do
    find_matching_integer_rule(number, rules)
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
    end) ||
      Enum.find(integer_rules, fn rule ->
        get_base_value(rule) == 0
      end)
  end

  # ── Rule execution ─────────────────────────────────────────

  defp do_rule(number, rule_set_name, rule, parsed, all_rule_sets) do
    results =
      Enum.map(parsed, fn {operation, argument} ->
        do_operation(operation, number, rule_set_name, rule, argument, all_rule_sets)
      end)

    if Enum.any?(results, &match?({:error, _}, &1)) do
      errors =
        results
        |> Enum.filter(&match?({:error, _}, &1))
        |> Enum.map(fn {:error, msg} -> msg end)
        |> Enum.join(", ")

      {:error, errors}
    else
      results
      |> Enum.map(fn
        s when is_binary(s) -> s
        other -> to_string(other)
      end)
      |> Enum.join()
    end
  end

  # ── Operations ─────────────────────────────────────────────

  defp do_operation(:literal, _number, _rule_set, _rule, string, _all_sets) do
    string
  end

  # Modulo for negative numbers (-x rule)
  defp do_operation(:modulo, number, rule_set, _rule, argument, all_sets)
       when is_number(number) and number < 0 do
    case argument do
      {:rule, rule_name} ->
        apply_rule_set(abs(number), to_string(rule_name), all_sets)

      nil ->
        apply_rule_set(abs(number), rule_set, all_sets)

      {:format, format} ->
        format_with_pattern(abs(number), format)
    end
  end

  # Modulo for float (fraction processing)
  defp do_operation(:modulo, number, rule_set, _rule, nil, all_sets)
       when is_float(number) do
    format_fraction(number, rule_set, all_sets, " ")
  end

  # Modulo for integers
  defp do_operation(:modulo, number, rule_set, rule, argument, all_sets)
       when is_integer(number) do
    mod = number - div(number, rule.divisor) * rule.divisor

    case argument do
      {:rule, rule_name} ->
        apply_rule_set(mod, to_string(rule_name), all_sets)

      nil ->
        apply_rule_set(mod, rule_set, all_sets)

      {:format, format} ->
        format_with_pattern(mod, format)
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
  defp do_operation(:modulo_preceding, number, rule_set, _rule, nil, all_sets)
       when is_float(number) do
    format_fraction(number, rule_set, all_sets, "")
  end

  defp do_operation(:modulo_preceding, number, rule_set, rule, argument, all_sets) do
    do_operation(:modulo, number, rule_set, rule, argument, all_sets)
  end

  # Quotient for float (integer part). The float case takes the
  # integer part of the number (`trunc/1`) and then applies the
  # caller-specified rule set, named rule, or decimal format. The
  # named-rule and decimal-format variants are needed because
  # locale `0.x` rules use `<%spellout-cardinal-sinokorean<` on
  # the integer side (e.g. ko); without these clauses the `0.x`
  # path crashes on a float input.
  defp do_operation(:quotient, number, rule_set, _rule, nil, all_sets)
       when is_float(number) do
    apply_rule_set(trunc(number), rule_set, all_sets)
  end

  defp do_operation(:quotient, number, _rule_set, _rule, {:rule, rule_name}, all_sets)
       when is_float(number) do
    apply_rule_set(trunc(number), to_string(rule_name), all_sets)
  end

  defp do_operation(:quotient, number, _rule_set, _rule, {:format, format}, _all_sets)
       when is_float(number) do
    format_with_pattern(trunc(number), format)
  end

  # Quotient for integers
  defp do_operation(:quotient, number, rule_set, rule, argument, all_sets)
       when is_integer(number) do
    divisor = div(number, rule.divisor)

    case argument do
      {:rule, rule_name} ->
        apply_rule_set(divisor, to_string(rule_name), all_sets)

      nil ->
        apply_rule_set(divisor, rule_set, all_sets)
    end
  end

  # Call another rule or format
  defp do_operation(:call, number, _rule_set, _rule, {:format, format}, _all_sets) do
    format_with_pattern(number, format)
  end

  defp do_operation(:call, number, _rule_set, _rule, {:rule, rule_name}, all_sets) do
    apply_rule_set(number, to_string(rule_name), all_sets)
  end

  # Plural operations
  defp do_operation(:ordinal, number, _rule_set, _rule, plurals, _all_sets) do
    plural = Localize.Number.PluralRule.Ordinal.plural_rule(number, "en")
    Map.get(plurals, plural) || Map.get(plurals, :other, "")
  end

  defp do_operation(:cardinal, number, _rule_set, _rule, plurals, _all_sets) do
    plural = Localize.Number.PluralRule.Cardinal.plural_rule(number, "en")
    Map.get(plurals, plural) || Map.get(plurals, :other, "")
  end

  # Conditional: only process if modulo > 0
  defp do_operation(:conditional, number, rule_set, rule, argument, all_sets)
       when is_integer(number) do
    mod = number - div(number, rule.divisor) * rule.divisor

    if mod > 0 do
      do_rule(mod, rule_set, rule, argument, all_sets)
    else
      ""
    end
  end

  defp do_operation(:conditional, _number, _rule_set, _rule, _argument, _all_sets) do
    ""
  end

  # ── Helpers ────────────────────────────────────────────────

  defp apply_rule_set(number, rule_set_name, all_rule_sets) do
    # Normalize rule set name (CLDR uses hyphens, we may use underscores)
    normalized_name = String.replace(rule_set_name, "-", "_")

    rule_set =
      find_rule_set(all_rule_sets, rule_set_name) ||
        find_rule_set(all_rule_sets, normalized_name)

    case rule_set do
      nil ->
        {:error, "Rule set #{inspect(rule_set_name)} not found"}

      %{rules: rules} ->
        case process(number, rule_set_name, rules, all_rule_sets) do
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

  defp format_with_pattern(number, format) do
    case Localize.Number.to_string(number, format: format) do
      {:ok, result} -> result
      {:error, _} -> to_string(number)
    end
  end

  defp format_fraction(number, rule_set, all_sets, separator) do
    number
    |> fractional_digit_list()
    |> Enum.map(fn n ->
      # Try spellout_numbering first, fallback to the current rule set
      numbering_set = "spellout_numbering"

      case apply_rule_set(n, numbering_set, all_sets) do
        {:error, _} -> apply_rule_set_or_string(n, rule_set, all_sets)
        result -> result
      end
    end)
    |> Enum.join(separator)
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

  defp apply_rule_set_or_string(number, rule_set, all_sets) do
    case apply_rule_set(number, rule_set, all_sets) do
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
