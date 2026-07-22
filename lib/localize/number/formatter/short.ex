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
        {normalized_number, format} = choose_short_format(number, format_rules, options)

        options =
          options
          |> maybe_set_fractional_digits(normalized_number)
          |> Map.put(:format, format)

        {:ok, normalized_number, format, options}
      end
    end
  end

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

  defp compact_max_fraction(mantissa) do
    if single_integer_digit?(mantissa), do: 1, else: 0
  end

  defp single_integer_digit?(%Decimal{} = mantissa) do
    mantissa |> Decimal.abs() |> Decimal.compare(10) == :lt
  end

  defp single_integer_digit?(mantissa) when is_number(mantissa) do
    abs(mantissa) < 10
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

  @one_thousand Decimal.new(1000)

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
