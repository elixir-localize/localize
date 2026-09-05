defmodule Localize.Number.Formatter.Short do
  @moduledoc false

  # Formats a number according to locale-specific short/long formats.
  #
  # Short formats produce compact representations like "1.2K" or
  # "1.2 thousand". They use CLDR's compact decimal format rules
  # which define format patterns at each power of 10 with plural
  # variants.

  alias Localize.Number.{Format, System}
  alias Localize.Number.Format.Options
  alias Localize.Number.Formatter
  alias Localize.Utils.Math

  @one_thousand Decimal.new(1000)

  # # to_string/3
  # Formats a number using short/long format style.
  #
  # ### Arguments
  # * `number` is an integer, float, or Decimal.
  # * `style` is `:decimal_short`, `:decimal_long`,
  #   `:currency_short`, or `:currency_long`.
  # * `options` is a `Localize.Number.Format.Options.t()`.
  #
  # ### Returns
  # * `{:ok, formatted_string}` or `{:error, exception}`.
  @spec to_string(number() | Decimal.t(), atom(), Options.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(number, _style, _options) when is_binary(number) do
    {:error,
     Localize.InvalidValueError.exception(
       value: number,
       expected: "a number (not a string)",
       context: "Short formats only support number or Decimal arguments"
     )}
  end

  def to_string(number, style, options) do
    with {:ok, normalized_number, format, options} <- resolve_short_format(number, style, options) do
      Formatter.Decimal.to_string(normalized_number, format, options)
    end
  end

  # Formats a compact number into typed parts per ECMA-402
  # `formatToParts`. The compact affix is carried by the pattern's
  # literal tokens, so the decimal formatter's `:literal` parts are
  # retagged `:compact` — everything else in a compact pattern is
  # digits and separators.
  @spec to_parts(number() | Decimal.t(), atom(), Options.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(number, style, options) do
    with {:ok, normalized_number, format, options} <- resolve_short_format(number, style, options),
         {:ok, parts} <- Formatter.Decimal.to_parts(normalized_number, format, options) do
      {:ok,
       Enum.map(parts, fn
         %{type: :literal} = part -> %{part | type: :compact}
         part -> part
       end)}
    end
  end

  defp resolve_short_format(number, style, options) do
    locale = options.locale

    with {:ok, number_system} <- System.system_name_from(options.number_system, locale),
         {:ok, formats} <- Format.formats_for(locale, number_system) do
      format_rules = Map.get(formats, style)

      if is_nil(format_rules) do
        {:error,
         Localize.InvalidValueError.exception(
           value: style,
           expected: "a format style with data for this locale",
           context: "Localize.Number.Formatter.Short"
         )}
      else
        {normalized_number, format} =
          number
          |> choose_short_format(format_rules, options)
          |> promote_magnitude_on_carry(number, format_rules, options)

        options =
          options
          |> maybe_set_fractional_digits(normalized_number)
          |> maybe_set_minimum_grouping()
          |> Map.put(:format, format)

        {:ok, normalized_number, format, options}
      end
    end
  end

  # The compact rule is chosen from the value's magnitude, then the mantissa
  # is rounded — and the rounding can carry into the next magnitude, leaving
  # the value formatted against a rule it has outgrown. `999.9` matches no
  # compact rule at all (it is below 1000), rounds to 1000 and renders
  # "1,000" where ICU gives "1K"; `999999.9` takes the thousands rule and
  # renders "1000K" instead of "1M".
  #
  # ICU re-checks the carry, and so does this: the rounded mantissa is scaled
  # back into the original units and the rule chosen again. Re-selecting
  # unconditionally is both simpler and safer than testing for the carry —
  # the test has to know how the rule divided, and locales whose compact
  # pattern is a bare "0" (German's thousands, among others) do not divide at
  # all, so a mantissa-magnitude test silently skips exactly the cases that
  # need it. One pass suffices: rounding carries by at most one magnitude,
  # and where nothing carried the same rule is chosen again.
  defp promote_magnitude_on_carry({mantissa, _format} = chosen, number, format_rules, options)
       when mantissa == 0 do
    _ = {number, format_rules, options}
    chosen
  end

  defp promote_magnitude_on_carry({mantissa, _format}, number, format_rules, options) do
    number
    |> scale_back(mantissa, round_mantissa(mantissa, options))
    |> choose_short_format(format_rules, options)
  end

  defp round_mantissa(mantissa, options) do
    # `maybe_set_fractional_digits/2` leaves the options untouched when the
    # caller supplied any precision of their own, so the maximum can still be
    # nil here — a caller who set only `:min_fractional_digits`, say. Nothing
    # to round to in that case, and nothing that could carry.
    case maybe_set_fractional_digits(options, mantissa) do
      %{max_fractional_digits: nil} -> mantissa
      %{max_fractional_digits: max} -> Math.round(mantissa, max, options.rounding_mode)
    end
  end

  # `number / mantissa` is the divisor the rule applied; re-applying it to the
  # rounded mantissa gives the rounded value in the original units.
  defp scale_back(%Decimal{} = number, %Decimal{} = mantissa, rounded) do
    Decimal.mult(rounded, Decimal.div(number, mantissa))
  end

  defp scale_back(number, mantissa, rounded) when is_number(number) and is_number(mantissa) do
    rounded * (number / mantissa)
  end

  # Compact notation groups on ICU's MIN2 strategy: a separator appears only
  # where at least two digits precede it. That is one rule, and it accounts
  # for two opposite-looking mismatches — German renders a compact 5000 as
  # "5000" where the standard format would give "5.000", while Bengali
  # renders 50000 as "৫০,০০০" where a compact format carrying no grouping at
  # all would give "৫০০০০". Expressed as `minimum_grouping_digits`, MIN2 is
  # simply 2, which `minimum_group_size/2` then adds to the locale's primary
  # group size.
  defp maybe_set_minimum_grouping(%{minimum_grouping_digits: nil} = options) do
    %{options | minimum_grouping_digits: 2}
  end

  defp maybe_set_minimum_grouping(%{minimum_grouping_digits: 0} = options) do
    %{options | minimum_grouping_digits: 2}
  end

  defp maybe_set_minimum_grouping(options), do: options

  # When the caller supplies no fraction-digit options, apply the
  # ECMA-402/ICU compact default: at most two significant digits on
  # the mantissa, never clipping its integer digits and never forcing
  # a trailing zero — "1.2M", "12M", "123M" and "1M" (not "1.0M").
  # That reduces to max one fraction digit while the mantissa is a
  # single integer digit, none afterwards.
  defp maybe_set_fractional_digits(
         %{fractional_digits: nil, min_fractional_digits: nil, max_fractional_digits: nil} =
           options,
         mantissa
       ) do
    %{options | min_fractional_digits: 0, max_fractional_digits: compact_max_fraction(mantissa)}
  end

  defp maybe_set_fractional_digits(options, _mantissa), do: options

  # ICU's compact precision is `Precision.integer().withMinDigits(2)`: round
  # the mantissa to an integer, but never below two significant digits. For a
  # mantissa of 1 or more that is what "at most one fraction digit while a
  # single integer digit remains" already gives — 1.2M, 12M, 123M. Below 1 the
  # two diverge, because the significant digits start after the leading zeros:
  # a compact `0.00831765` is "0.0083", where one fraction digit rounds it away
  # to "0" entirely.
  #
  # Expressed in fraction digits, two significant digits need `1 - magnitude`
  # of them, where magnitude is the base-10 exponent — 0 for 1.5 (one fraction
  # digit), -1 for 0.15 (two), -3 for 0.0083 (four) — clamped at zero for
  # anything with two integer digits already.
  defp compact_max_fraction(mantissa) do
    case magnitude(mantissa) do
      nil -> 0
      magnitude -> max(0, 1 - magnitude)
    end
  end

  defp magnitude(%Decimal{} = mantissa) do
    absolute = Decimal.abs(mantissa)

    cond do
      Decimal.equal?(absolute, 0) -> nil
      # Enough to clamp to zero fraction digits, and avoids converting a
      # large Decimal to a float just to take its logarithm.
      Decimal.compare(absolute, 10) != :lt -> 1
      true -> absolute |> Decimal.to_float() |> float_magnitude()
    end
  end

  defp magnitude(mantissa) when is_number(mantissa) do
    if mantissa == 0, do: nil, else: mantissa |> abs() |> float_magnitude()
  end

  defp float_magnitude(absolute) do
    absolute |> :math.log10() |> Float.floor() |> trunc()
  end

  # ── Format selection ────────────────────────────────────────

  defp choose_short_format(number, format_rules, options)
       when is_number(number) and number < 0 do
    {normalized, format} = choose_short_format(abs(number), format_rules, options)
    {normalized * -1, format}
  end

  defp choose_short_format(%Decimal{sign: -1} = number, format_rules, options) do
    {normalized, format} = choose_short_format(Decimal.abs(number), format_rules, options)
    {Decimal.mult(normalized, -1), format}
  end

  defp choose_short_format(number, format_rules, options) do
    case get_short_format_rule(number, format_rules, options) do
      [range, plural_selectors] ->
        normalized_number = normalise_number(number, range, plural_selectors.other)
        plural_key = pluralization_key(normalized_number, options)

        [format, _number_of_zeros] =
          Localize.Number.PluralRule.Cardinal.pluralize(
            plural_key,
            options.locale,
            plural_selectors
          )

        {normalized_number, format}

      {number, format} ->
        {number, format}
    end
  end

  defp get_short_format_rule(number, _format_rules, options)
       when is_number(number) and number < 1000 do
    with {:ok, formats} <- Format.formats_for(options.locale, options.number_system) do
      format = Map.get(formats, standard_or_currency(options))
      {number, format}
    end
  end

  defp get_short_format_rule(number, format_rules, options) when is_number(number) do
    format_rules
    |> Enum.filter(fn [range, _rules] -> range <= number end)
    |> Enum.reverse()
    |> hd()
    |> maybe_get_default_format(number, options)
  end

  defp get_short_format_rule(%Decimal{} = number, format_rules, options) do
    rule =
      number
      |> Decimal.round(0, :floor)
      |> Decimal.to_integer()
      |> get_short_format_rule(format_rules, options)

    case rule do
      {_ignore, format} -> {number, format}
      rule -> rule
    end
  end

  defp maybe_get_default_format([_range, %{other: ["0", _]}], number, options) do
    {_, format} = get_short_format_rule(0, [], options)
    {number, format}
  end

  defp maybe_get_default_format(rule, _number, _options), do: rule

  defp standard_or_currency(options) do
    if options.currency, do: :currency, else: :standard
  end

  # ── Number normalisation ────────────────────────────────────

  defp normalise_number(%Decimal{} = number, range, number_of_zeros) do
    if Decimal.compare(number, @one_thousand) == :lt do
      number
    else
      Decimal.div(number, Decimal.new(adjustment(range, number_of_zeros)))
    end
  end

  defp normalise_number(number, _range, _number_of_zeros) when number < 1000, do: number

  defp normalise_number(number, _range, ["0", _number_of_zeros]), do: number

  defp normalise_number(number, range, [_format, number_of_zeros]) do
    number / adjustment(range, number_of_zeros)
  end

  defp adjustment(range, number_of_zeros) when is_integer(number_of_zeros) do
    trunc(range / Math.power(10, number_of_zeros - 1))
  end

  defp adjustment(range, [_, number_of_zeros]) when is_integer(number_of_zeros) do
    adjustment(range, number_of_zeros)
  end

  # ── Pluralization key ──────────────────────────────────────

  # Per TR35 (Compact Number Formats, step 8) the plural category is
  # determined from the mantissa *as it will be displayed* — after the
  # numeric precision settings are applied. Selecting on the unrounded
  # mantissa while rendering the rounded one produced grammatically
  # impossible output such as es "1 millones" for 1_050_000.
  defp pluralization_key(number, options) do
    round_to_display(number, effective_max_fraction(number, options))
  end

  defp effective_max_fraction(mantissa, options) do
    max_fraction =
      options.fractional_digits || options.max_fractional_digits ||
        compact_max_fraction(mantissa)

    # A caller-supplied negative value must not reach Float.round/2
    # (it raises); the formatter itself treats negatives as zero.
    max(max_fraction, 0)
  end

  # The rounded value must also carry the *visible fraction digits*
  # operand (v) of the displayed form: with a minimum of zero fraction
  # digits an integral mantissa displays as "2" (v = 0), so it is
  # returned as an integer / normalized Decimal, never a float `2.0`
  # whose fraction would leak into plural selection.
  defp round_to_display(%Decimal{} = number, max_fraction) do
    number
    |> Decimal.round(max_fraction, :half_even)
    |> Decimal.normalize()
  end

  defp round_to_display(number, max_fraction) when is_float(number) do
    rounded = Float.round(number, max_fraction)
    truncated = trunc(rounded)

    if truncated == rounded do
      truncated
    else
      Decimal.from_float(rounded)
    end
  end

  defp round_to_display(number, _max_fraction) when is_integer(number) do
    number
  end
end
