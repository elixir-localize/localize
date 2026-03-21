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
  #   Long:     "123 US dollars"

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
    # First format as currency_long, then wrap in the currency format
    with {:ok, long_string} <- to_string(number, :currency_long, Map.put(options, :currency, nil)) do
      # Get the currency format and substitute
      with {:ok, number_system} <- System.system_name_from(options.number_system, options.locale),
           {:ok, formats} <- Format.formats_for(options.locale, number_system) do
        currency_format = Map.get(formats, :currency) || "¤#,##0.00"

        Localize.Number.Formatter.Decimal.to_string(
          long_string,
          currency_format,
          options
        )
      end
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
          currency_string = currency_display_name(number, options)
          plural_format = plural_format(number, formats, options)
          result = substitute([number_string, currency_string], plural_format)
          {:ok, :erlang.iolist_to_binary(result)}

        error ->
          error
      end
    end
  end

  defp currency_display_name(number, %{currency: %Localize.Currency{count: count}, locale: locale}) do
    Localize.Number.PluralRule.Cardinal.pluralize(number, locale, count)
  end

  defp currency_display_name(_number, %{currency: %Localize.Currency{name: name}}) do
    name
  end

  defp currency_display_name(_number, _options), do: ""

  defp plural_format(number, formats, %{locale: locale}) do
    Localize.Number.PluralRule.Cardinal.pluralize(number, locale, formats)
  end

  defp maybe_set_fractional_digits(options, %Localize.Currency{}, nil) do
    Map.put(options, :fractional_digits, 0)
  end

  defp maybe_set_fractional_digits(options, _currency, _digits), do: options

  # Substitution of [number_string, currency_string] into a format
  # like [0, " ", 1] where 0 = number and 1 = currency name
  defp substitute(values, format) when is_list(format) do
    Enum.map(format, fn
      index when is_integer(index) -> Enum.at(values, index, "")
      string when is_binary(string) -> string
    end)
  end

  defp substitute(_values, format) when is_binary(format), do: [format]
end
