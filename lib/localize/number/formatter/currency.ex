defmodule Localize.Number.Formatter.Currency do
  @moduledoc false

  # Formats a number in currency long form.
  #
  # This is different from standard currency formatting (which uses
  # a decimal format mask with a currency placeholder). Currency
  # long format combines the number with a localized, pluralized
  # currency display name.
  #
  # Example:
  #   Standard: "$123.00"
  #   Long:     "123.00 US dollars"

  alias Localize.Number.{Format, System}
  alias Localize.Number.Format.Options

  # # to_string/3
  # Formats a number using currency long format.
  #
  # ### Arguments
  # * `number` is an integer, float, or Decimal.
  # * `style` is `:currency_long` or `:currency_long_with_symbol`.
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
       context: "Currency long formats only support number or Decimal arguments"
     )}
  end

  def to_string(number, :currency_long, options) do
    locale = options.locale

    with {:ok, number_system} <- System.system_name_from(options.number_system, locale),
         {:ok, formats} <- Format.formats_for(locale, number_system) do
      currency_long_formats = Map.get(formats, :currency_long)

      # Believed unreachable with current CLDR data: every locale
      # inherits `:currency_long` from root (verified against en, ja,
      # ar, agq, kkj and und). Kept as a defensive guard in case a
      # future data pipeline change drops the inherited formats.
      if is_nil(currency_long_formats) do
        {:error,
         Localize.InvalidValueError.exception(
           value: :currency_long,
           expected: "a locale with currency_long formats",
           context: "Localize.Number.Formatter.Currency"
         )}
      else
        format_currency_long(number, currency_long_formats, options)
      end
    end
  end

  def to_string(number, :currency_long_with_symbol, options) do
    # The long plural pattern ("{0} US dollars") is filled with the
    # symbol-formatted number ("$123.00") instead of the bare number.
    with {:ok, number_system} <- System.system_name_from(options.number_system, options.locale),
         {:ok, formats} <- Format.formats_for(options.locale, number_system) do
      currency_long_formats = Map.get(formats, :currency_long)

      # Believed unreachable — see the note in the :currency_long
      # clause above. Kept as a defensive guard.
      if is_nil(currency_long_formats) do
        {:error,
         Localize.InvalidValueError.exception(
           value: :currency_long_with_symbol,
           expected: "a locale with currency_long formats",
           context: "Localize.Number.Formatter.Currency"
         )}
      else
        format_long_with_symbol(number, formats, currency_long_formats, options)
      end
    end
  end

  # # to_parts/3
  #
  # The parts sibling of `to_string/3`: the number decomposes through
  # `Formatter.Decimal.to_parts/3` and the pluralized currency name
  # becomes a `:currency` part, substituted into the same plural
  # pattern. The parts concatenate to the `to_string/3` result.
  @spec to_parts(number() | Decimal.t(), atom(), Options.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(number, _style, _options) when is_binary(number) do
    {:error,
     Localize.InvalidValueError.exception(
       value: number,
       expected: "a number (not a string)",
       context: "Currency long formats only support number or Decimal arguments"
     )}
  end

  def to_parts(number, :currency_long, options) do
    locale = options.locale

    with {:ok, number_system} <- System.system_name_from(options.number_system, locale),
         {:ok, formats} <- Format.formats_for(locale, number_system),
         {:ok, currency_long_formats} <- fetch_currency_long_formats(formats, :currency_long) do
      parts_currency_long(number, currency_long_formats, options)
    end
  end

  def to_parts(number, :currency_long_with_symbol, options) do
    with {:ok, number_system} <- System.system_name_from(options.number_system, options.locale),
         {:ok, formats} <- Format.formats_for(options.locale, number_system),
         {:ok, currency_long_formats} <-
           fetch_currency_long_formats(formats, :currency_long_with_symbol) do
      parts_long_with_symbol(number, formats, currency_long_formats, options)
    end
  end

  # Believed unreachable with current CLDR data — see the note in
  # `to_string/3`. Kept as a defensive guard.
  defp fetch_currency_long_formats(formats, style) do
    case Map.get(formats, :currency_long) do
      nil ->
        {:error,
         Localize.InvalidValueError.exception(
           value: style,
           expected: "a locale with currency_long formats",
           context: "Localize.Number.Formatter.Currency"
         )}

      currency_long_formats ->
        {:ok, currency_long_formats}
    end
  end

  defp parts_currency_long(number, formats, options) do
    number_options =
      options
      |> Map.put(:format, :standard)
      |> Map.put(:currency, nil)
      |> maybe_set_fractional_digits(options.currency, options.fractional_digits)

    with {:ok, standard_formats} <- Format.formats_for(options.locale, options.number_system) do
      standard_format = Map.get(standard_formats, :standard) || "#,##0.###"

      case Localize.Number.Formatter.Decimal.to_parts(number, standard_format, number_options) do
        {:ok, number_parts} ->
          display_number = display_value_for_plural(number, number_options)
          name = currency_display_name(display_number, options)
          plural_format = plural_format(display_number, formats, options)
          {:ok, substitute_as_parts([number_parts, currency_part(name)], plural_format)}

        error ->
          error
      end
    end
  end

  defp parts_long_with_symbol(number, formats, currency_long_formats, options) do
    currency_format = Map.get(formats, :currency) || "¤#,##0.00"

    case Localize.Number.Formatter.Decimal.to_parts(number, currency_format, options) do
      {:ok, currency_parts} ->
        display_number = display_value_for_plural(number, options)
        name = currency_display_name(display_number, options)
        plural_format = plural_format(display_number, currency_long_formats, options)
        {:ok, substitute_as_parts([currency_parts, currency_part(name)], plural_format)}

      error ->
        error
    end
  end

  defp currency_part(""), do: []
  defp currency_part(name), do: [%{type: :currency, value: name}]

  defp substitute_as_parts(parts_lists, format) when is_list(format) do
    Localize.Substitution.substitute_parts(parts_lists, format)
  end

  defp substitute_as_parts(_parts_lists, format) when is_binary(format) do
    [%{type: :literal, value: format}]
  end

  defp format_long_with_symbol(number, formats, currency_long_formats, options) do
    currency_format = Map.get(formats, :currency) || "¤#,##0.00"

    case Localize.Number.Formatter.Decimal.to_string(number, currency_format, options) do
      {:ok, currency_string} ->
        display_number = display_value_for_plural(number, options)
        name_string = currency_display_name(display_number, options)
        plural_format = plural_format(display_number, currency_long_formats, options)
        result = substitute([currency_string, name_string], plural_format)
        {:ok, :erlang.iolist_to_binary(result)}

      error ->
        error
    end
  end

  # ── Private helpers ──────────────────────────────────────────

  defp format_currency_long(number, formats, options) do
    # Determine the standard format for the number
    number_options =
      options
      |> Map.put(:format, :standard)
      |> Map.put(:currency, nil)
      |> maybe_set_fractional_digits(options.currency, options.fractional_digits)

    # Resolve the standard format string
    with {:ok, standard_formats} <- Format.formats_for(options.locale, options.number_system) do
      standard_format = Map.get(standard_formats, :standard) || "#,##0.###"

      case Localize.Number.Formatter.Decimal.to_string(number, standard_format, number_options) do
        {:ok, number_string} ->
          display_number = display_value_for_plural(number, number_options)
          currency_string = currency_display_name(display_number, options)
          plural_format = plural_format(display_number, formats, options)
          result = substitute([number_string, currency_string], plural_format)
          {:ok, :erlang.iolist_to_binary(result)}

        error ->
          error
      end
    end
  end

  # The `:count` field is `map() | nil` (see `t:Localize.Currency.t/0`).
  # Pluralized display names apply only when the plural-count map is
  # populated; otherwise fall back to the currency's base name. Without
  # the guard this first clause matched every `Currency` struct (the
  # field always exists), making the name fallback unreachable and
  # crashing `pluralize/3` when `count` was `nil`.
  defp currency_display_name(number, %{currency: %Localize.Currency{count: count}, locale: locale})
       when is_map(count) and map_size(count) > 0 do
    select_plural(number, locale, count)
  end

  defp currency_display_name(_number, %{currency: %Localize.Currency{name: name}})
       when is_binary(name) do
    name
  end

  defp currency_display_name(_number, _options), do: ""

  defp plural_format(number, formats, %{locale: locale}) do
    select_plural(number, locale, formats)
  end

  # Select by plural category directly rather than via
  # `Cardinal.pluralize/3`, which normalizes away trailing zeros
  # and would collapse "1.00" (operand v=2, category :other in en)
  # back to the integer 1 (category :one).
  defp select_plural(number, locale, substitutions) do
    category = Localize.Number.PluralRule.Cardinal.plural_rule(number, locale)
    Map.get(substitutions, category) || Map.get(substitutions, :other)
  end

  # Plural selection follows the value as displayed, per the CLDR
  # plural operands and matching ICU/Intl: "1.00" carries the
  # operand v=2 and selects :other ("1.00 US dollars"), while a
  # bare "1" selects :one ("1 US dollar"). Rescaling the number to
  # the displayed fraction digits makes the plural rule see the
  # same operands the reader sees.
  defp display_value_for_plural(number, %{fractional_digits: digits}) when is_integer(digits) do
    number |> to_decimal() |> Decimal.round(digits)
  end

  defp display_value_for_plural(number, _options), do: number

  defp to_decimal(%Decimal{} = decimal), do: decimal
  defp to_decimal(number) when is_integer(number), do: Decimal.new(number)
  defp to_decimal(number) when is_float(number), do: Decimal.from_float(number)

  defp maybe_set_fractional_digits(options, %Localize.Currency{}, nil) do
    Map.put(options, :fractional_digits, 0)
  end

  defp maybe_set_fractional_digits(options, _currency, _digits), do: options

  # Substitution of [number_string, currency_string] into a format
  # like [0, " ", 1] where 0 = number and 1 = currency name
  defp substitute(values, format) when is_list(format) do
    Localize.Substitution.substitute(values, format)
  end

  defp substitute(_values, format) when is_binary(format), do: [format]
end
