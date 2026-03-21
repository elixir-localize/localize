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
    locale = options.locale

    with {:ok, number_system} <- System.system_name_from(options.number_system, locale) do
      short_format_string(number, style, locale, number_system, options)
    end
  end

  defp short_format_string(number, style, locale, number_system, options) do
    with {:ok, formats} <- Format.formats_for(locale, number_system) do
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
          |> maybe_set_fractional_digits()
          |> Map.put(:format, format)

        Formatter.Decimal.to_string(normalized_number, format, options)
      end
    end
  end

  defp maybe_set_fractional_digits(%{fractional_digits: nil} = options) do
    Map.put(options, :fractional_digits, 0)
  end

  defp maybe_set_fractional_digits(options), do: options

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

  defp pluralization_key(number, _options) when is_number(number) do
    rounded = Localize.Utils.Math.round(number, 0, :half_even)

    if rounded <= number do
      number
    else
      rounded + 0.1
    end
  end

  defp pluralization_key(%Decimal{} = number, options) do
    number
    |> Decimal.to_float()
    |> pluralization_key(options)
  end
end
