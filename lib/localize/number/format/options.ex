defmodule Localize.Number.Format.Options do
  @moduledoc false

  # Options validation and transformation for number formatting.
  # This is an internal module that validates user-supplied
  # options and produces a normalized options struct for the
  # formatter pipeline.

  alias Localize.Number.{System, Symbol, Format}

  @options [
    :locale,
    :number_system,
    :currency,
    :format,
    :gender,
    :grammatical_case,
    :currency_format,
    :currency_digits,
    :currency_spacing,
    :currency_symbol,
    :symbols,
    :minimum_grouping_digits,
    :pattern,
    :rounding_mode,
    :fractional_digits,
    :min_fractional_digits,
    :max_fractional_digits,
    :maximum_integer_digits,
    :round_nearest,
    :wrapper,
    :separators
  ]

  @rounding_modes [
    :down,
    :half_up,
    :half_even,
    :ceiling,
    :floor,
    :half_down,
    :up
  ]

  @standard_formats [
    :standard,
    :accounting,
    :currency,
    :scientific,
    :percent,
    :currency_no_symbol,
    :accounting_no_symbol,
    :currency_alpha_next_to_number,
    :accounting_alpha_next_to_number
  ]

  @short_formats [
    :currency_short,
    :currency_long_with_symbol,
    :currency_long,
    :decimal_short,
    :decimal_long
  ]

  defstruct @options

  @type t :: %__MODULE__{}

  # # Returns the default options for number formatting.
  # #
  # # These serve as the base options that user-supplied
  # # options are merged on top of.
  # defp default_options do
  #   [
  #     locale: :en,
  #     number_system: :default,
  #     currency: nil,
  #     format: :standard,
  #     gender: nil,
  #     grammatical_case: :nominative,
  #     currency_format: nil,
  #     currency_digits: :accounting,
  #     currency_spacing: nil,
  #     currency_symbol: nil,
  #     symbols: nil,
  #     minimum_grouping_digits: 0,
  #     pattern: nil,
  #     rounding_mode: :half_even,
  #     fractional_digits: nil,
  #     maximum_integer_digits: nil,
  #     round_nearest: nil,
  #     wrapper: nil,
  #     separators: nil
  #   ]
  # end

  @doc false
  def validate_options(number, options) do
    options =
      [
        locale: :en,
        number_system: :default,
        format: :standard,
        rounding_mode: :half_even,
        currency_digits: :accounting
      ]
      |> Keyword.merge(options)
      |> Map.new()

    options
    |> validate_locale()
    |> validate_number_system()
    |> validate_currency()
    |> validate_format()
    |> validate_symbols()
    |> validate_rounding_mode()
    |> resolve_standard_format()
    |> resolve_currency_symbol()
    |> resolve_currency_spacing()
    |> set_pattern(number)
    |> structify()
    |> wrap_ok()
  end

  defp validate_locale(%{locale: locale} = options) when is_map(options) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> Map.put(options, :locale, language_tag)
      {:error, _} = error -> error
    end
  end

  defp validate_locale(error), do: error

  defp validate_number_system(%{locale: locale, number_system: number_system} = options)
       when is_map(options) do
    case number_system do
      nil ->
        case System.number_system_from_locale(locale) do
          {:ok, system} -> Map.put(options, :number_system, system)
          {:error, _} = error -> error
        end

      :default ->
        case System.number_system_from_locale(locale) do
          {:ok, system} -> Map.put(options, :number_system, system)
          {:error, _} = error -> error
        end

      system_name ->
        case System.system_name_from(system_name, locale) do
          {:ok, name} -> Map.put(options, :number_system, name)
          {:error, _} = error -> error
        end
    end
  end

  defp validate_number_system(error), do: error

  defp validate_currency(%{currency: nil} = options) when is_map(options), do: options

  defp validate_currency(%{currency: %Localize.Currency{}} = options) when is_map(options),
    do: options

  defp validate_currency(%{currency: currency} = options) when is_map(options) do
    case Localize.Currency.validate_currency(currency) do
      {:ok, code} ->
        case Localize.Currency.currency_for_code(code, locale: options[:locale]) do
          {:ok, currency_struct} -> Map.put(options, :currency, currency_struct)
          {:error, _} = error -> error
        end

      {:error, _} = error ->
        error
    end
  end

  defp validate_currency(error), do: error

  defp validate_format(%{currency: %Localize.Currency{}, format: :standard} = options) do
    # When a currency is provided and format is default (:standard),
    # automatically switch to currency format
    currency_format = derive_currency_format(options)
    Map.put(options, :format, currency_format)
  end

  defp validate_format(options) when is_map(options), do: options
  defp validate_format(error), do: error

  defp derive_currency_format(%{locale: locale}) do
    case Localize.Currency.currency_format_from_locale(locale) do
      {:ok, format} -> format
      _ -> :currency
    end
  end

  defp validate_symbols(%{locale: locale, number_system: number_system} = options)
       when is_map(options) do
    case Symbol.number_symbols_for(locale, number_system) do
      {:ok, symbols} -> Map.put(options, :symbols, symbols)
      _other -> Map.put(options, :symbols, nil)
    end
  end

  defp validate_symbols(error), do: error

  defp validate_rounding_mode(%{rounding_mode: mode} = options)
       when is_map(options) and mode in @rounding_modes do
    options
  end

  defp validate_rounding_mode(%{rounding_mode: nil} = options) when is_map(options) do
    Map.put(options, :rounding_mode, :half_even)
  end

  defp validate_rounding_mode(error), do: error

  defp resolve_standard_format(%{format: format} = options)
       when is_map(options) and format in @standard_formats do
    %{locale: locale, number_system: number_system} = options

    with {:ok, formats} <- Format.formats_for(locale, number_system) do
      case Map.get(formats, format) do
        nil -> options
        resolved -> Map.put(options, :format, resolved)
      end
    end
  end

  defp resolve_standard_format(%{format: format} = options)
       when is_map(options) and format in @short_formats do
    options
  end

  defp resolve_standard_format(options) when is_map(options), do: options
  defp resolve_standard_format(error), do: error

  # Resolve the currency symbol from the currency struct and options
  defp resolve_currency_symbol(%{currency: %Localize.Currency{} = currency} = options)
       when is_map(options) do
    symbol =
      case options[:currency_symbol] do
        :narrow -> currency.narrow_symbol || currency.symbol
        :iso -> to_string(currency.code)
        :symbol -> currency.symbol
        nil -> currency.symbol
        other when is_binary(other) -> other
        _ -> currency.symbol
      end

    Map.put(options, :currency_symbol, symbol)
  end

  defp resolve_currency_symbol(options) when is_map(options), do: options
  defp resolve_currency_symbol(error), do: error

  # Resolve currency spacing from locale data
  defp resolve_currency_spacing(
         %{currency: %Localize.Currency{}, locale: locale, number_system: number_system} = options
       )
       when is_map(options) do
    spacing = Localize.Number.Format.currency_spacing(locale, number_system)
    Map.put(options, :currency_spacing, spacing)
  end

  defp resolve_currency_spacing(options) when is_map(options), do: options
  defp resolve_currency_spacing(error), do: error

  defp set_pattern(options, number) when is_map(options) and is_number(number) and number < 0 do
    Map.put(options, :pattern, :negative)
  end

  defp set_pattern(options, %Decimal{sign: sign}) when is_map(options) and sign < 0 do
    Map.put(options, :pattern, :negative)
  end

  defp set_pattern(options, _number) when is_map(options) do
    Map.put(options, :pattern, :positive)
  end

  defp set_pattern(error, _number), do: error

  defp structify(options) when is_map(options) do
    struct(__MODULE__, options)
  end

  defp structify(error), do: error

  defp wrap_ok(%__MODULE__{} = options), do: {:ok, options}
  defp wrap_ok(other), do: other
end
