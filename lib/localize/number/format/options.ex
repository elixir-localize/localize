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
    :minimum_significant_digits,
    :maximum_significant_digits,
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

  @currency_indicator "¤"

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

  @doc """
  Validates and resolves number formatting options into an
  `Options` struct.

  This function performs locale validation, number system
  resolution, format pattern lookup, currency data loading,
  and symbol resolution. The resulting struct can be passed
  directly to `Localize.Number.to_string/2` to bypass options
  resolution on each call.

  This is useful when formatting many numbers with the same
  locale and format. See the
  [Performance and optimization](number_formatting.html#performance-and-optimization)
  section of the Number Formatting guide for benchmarks and
  usage guidance.

  ### Arguments

  * `number` is a representative number used to determine the
    sign pattern. Use `0` for a positive-number format or `-1`
    for a negative-number format.

  * `options` is a keyword list of the same options accepted by
    `Localize.Number.to_string/2`.

  ### Returns

  * `{:ok, options_struct}` where `options_struct` is a
    `t:Localize.Number.Format.Options.t/0`.

  * `{:error, exception}` if any option is invalid.

  ### Examples

      iex> {:ok, options} = Localize.Number.Format.Options.validate_options(0, locale: :en)
      iex> {:ok, _} = Localize.Number.to_string(1234.56, options)

  """
  @spec validate_options(number() | Decimal.t(), Keyword.t()) ::
          {:ok, t()} | {:error, Exception.t()}
  def validate_options(number, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, :standard)
    currency = Keyword.get(options, :currency)
    number_system = Keyword.get(options, :number_system, :default)
    rounding_mode = Keyword.get(options, :rounding_mode, :half_even)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, system_name} <- resolve_number_system(language_tag, number_system),
         {:ok, currency_struct} <- resolve_currency(format, currency, language_tag),
         format <- maybe_switch_currency_format(format, currency_struct, language_tag),
         :ok <- validate_rounding_mode(rounding_mode),
         :ok <- validate_significant_digits(options),
         {:ok, symbols} <- resolve_symbols(language_tag, system_name),
         {:ok, resolved_format, formats} <- resolve_format(format, language_tag, system_name) do
      currency_symbol = resolve_currency_symbol(currency_struct, options[:currency_symbol])
      currency_spacing = resolve_currency_spacing(currency_struct, formats)
      pattern = if negative?(number), do: :negative, else: :positive
      currency_digits = Keyword.get(options, :currency_digits, :accounting)

      # For standard currency formats (not custom pattern strings),
      # set fractional_digits from the currency when not explicitly provided.
      fractional_digits =
        Keyword.get(options, :fractional_digits) ||
          default_currency_fractional_digits(format, currency_struct, currency_digits)

      # Build struct from the options keyword list (passthrough fields)
      # then overlay the resolved values
      result =
        struct(__MODULE__, options)
        |> Map.merge(%{
          locale: language_tag,
          number_system: system_name,
          currency: currency_struct,
          format: resolved_format,
          symbols: symbols,
          rounding_mode: rounding_mode || :half_even,
          currency_symbol: currency_symbol,
          currency_spacing: currency_spacing,
          currency_digits: currency_digits,
          fractional_digits: fractional_digits,
          pattern: pattern
        })

      {:ok, result}
    end
  end

  # ── Number system resolution ────────────────────────────────

  # Fast path: read directly from the LanguageTag U extension struct
  defp resolve_number_system(%Localize.LanguageTag{locale: %{nu: ns}}, :default)
       when not is_nil(ns) do
    {:ok, ns}
  end

  defp resolve_number_system(%Localize.LanguageTag{locale: %{nu: ns}}, nil)
       when not is_nil(ns) do
    {:ok, ns}
  end

  defp resolve_number_system(language_tag, :default) do
    System.number_system_from_locale(language_tag)
  end

  defp resolve_number_system(language_tag, nil) do
    System.number_system_from_locale(language_tag)
  end

  defp resolve_number_system(language_tag, system_name) do
    System.system_name_from(system_name, language_tag)
  end

  # ── Currency resolution ─────────────────────────────────────

  defp resolve_currency(_format, %Localize.Currency{} = currency, _language_tag) do
    {:ok, currency}
  end

  defp resolve_currency(:currency, nil, %Localize.LanguageTag{} = language_tag) do
    with {:ok, code} <- Localize.Currency.currency_from_locale(language_tag) do
      Localize.Currency.currency_for_code(code, locale: language_tag)
    end
  end

  defp resolve_currency(format, nil, %Localize.LanguageTag{} = language_tag)
       when is_binary(format) do
    if String.contains?(format, @currency_indicator) do
      with {:ok, code} <- Localize.Currency.currency_from_locale(language_tag) do
        Localize.Currency.currency_for_code(code, locale: language_tag)
      end
    else
      {:ok, nil}
    end
  end

  defp resolve_currency(_, currency, language_tag) when not is_nil(currency) do
    with {:ok, code} <- Localize.Currency.validate_currency(currency) do
      Localize.Currency.currency_for_code(code, locale: language_tag)
    end
  end

  defp resolve_currency(_format, _currency, _language_tag) do
    {:ok, nil}
  end

  # ── Format auto-switch ──────────────────────────────────────

  defp maybe_switch_currency_format(:standard, %Localize.Currency{}, language_tag) do
    case Localize.Currency.currency_format_from_locale(language_tag) do
      {:ok, format} -> format
      _ -> :currency
    end
  end

  defp maybe_switch_currency_format(format, _currency, _language_tag), do: format

  # ── Rounding mode validation ────────────────────────────────

  defp validate_rounding_mode(nil), do: :ok
  defp validate_rounding_mode(mode) when mode in @rounding_modes, do: :ok

  defp validate_rounding_mode(mode) do
    {:error,
     Localize.InvalidValueError.exception(
       value: mode,
       expected: "a valid rounding mode (#{inspect(@rounding_modes)})"
     )}
  end

  # ── Significant-digit validation ────────────────────────────

  # Per ECMA-402 / TR35, both options must be positive integers in
  # 1..21, and `maximum` must be `>= minimum` when both are set.
  # `nil` means "not set"; the formatter falls back to the format
  # pattern's significant-digit metadata (which defaults to no
  # rounding when the pattern has no `@`).
  defp validate_significant_digits(options) do
    min = Keyword.get(options, :minimum_significant_digits)
    max = Keyword.get(options, :maximum_significant_digits)

    cond do
      not significant_digit_value?(min) ->
        invalid_significant_digits(:minimum_significant_digits, min)

      not significant_digit_value?(max) ->
        invalid_significant_digits(:maximum_significant_digits, max)

      is_integer(min) and is_integer(max) and max < min ->
        {:error,
         Localize.InvalidValueError.exception(
           value: {min, max},
           expected:
             "maximum_significant_digits (#{max}) to be >= minimum_significant_digits (#{min})"
         )}

      true ->
        :ok
    end
  end

  defp significant_digit_value?(nil), do: true
  defp significant_digit_value?(value) when is_integer(value) and value in 1..21, do: true
  defp significant_digit_value?(_), do: false

  defp invalid_significant_digits(option, value) do
    {:error,
     Localize.InvalidValueError.exception(
       value: value,
       expected: "an integer in 1..21",
       context: Atom.to_string(option)
     )}
  end

  # ── Symbols resolution ──────────────────────────────────────

  defp resolve_symbols(language_tag, system_name) do
    case Symbol.number_symbols_for(language_tag, system_name) do
      {:ok, _} = result -> result
      _other -> {:ok, nil}
    end
  end

  # ── Format resolution ───────────────────────────────────────

  # Standard formats: load formats once, look up the pattern
  defp resolve_format(format, language_tag, system_name) when format in @standard_formats do
    locale_id = Localize.Locale.to_locale_id(language_tag)

    with {:ok, all_formats} <- Localize.Locale.get(locale_id, [:number_formats]) do
      formats = Map.get(all_formats, system_name)

      case formats do
        nil ->
          {:ok, format, nil}

        %Format{} = f ->
          resolved = Map.get(f, format, format)
          {:ok, resolved, f}

        %{} = f ->
          {:ok, Map.get(f, format, format), f}
      end
    end
  end

  # Short formats: no resolution needed, but load formats for currency_spacing
  defp resolve_format(format, language_tag, system_name) when format in @short_formats do
    locale_id = Localize.Locale.to_locale_id(language_tag)

    formats =
      case Localize.Locale.get(locale_id, [:number_formats]) do
        {:ok, all} -> Map.get(all, system_name)
        _ -> nil
      end

    {:ok, format, formats}
  end

  # Custom string or other: no format resolution needed
  defp resolve_format(format, _language_tag, _system_name) do
    {:ok, format, nil}
  end

  # ── Currency symbol resolution ──────────────────────────────

  # ── Currency fractional digits ─────────────────────────────

  # Set default fractional digits from the currency data when the
  # format is a standard currency format (atom like :currency,
  # :accounting, etc.) and the user hasn't explicitly provided
  # fractional_digits. Custom format strings keep their own
  # fractional digit specification from the pattern.
  @currency_fraction_formats [
    :currency,
    :accounting,
    :standard,
    :currency_no_symbol,
    :accounting_no_symbol,
    :currency_alpha_next_to_number,
    :accounting_alpha_next_to_number
  ]

  defp default_currency_fractional_digits(format, %Localize.Currency{} = currency, :accounting)
       when format in @currency_fraction_formats do
    currency.digits
  end

  defp default_currency_fractional_digits(format, %Localize.Currency{} = currency, :cash)
       when format in @currency_fraction_formats do
    currency.cash_digits
  end

  defp default_currency_fractional_digits(format, %Localize.Currency{} = currency, :iso)
       when format in @currency_fraction_formats do
    currency.iso_digits
  end

  defp default_currency_fractional_digits(_format, _currency, _currency_digits), do: nil

  # ── Currency symbol resolution ──────────────────────────────

  # Per TR35: if no symbol data is available for a currency in a locale,
  # fall back to the ISO 4217 currency code (e.g., "CHF").
  defp resolve_currency_symbol(nil, _option), do: ""

  defp resolve_currency_symbol(%Localize.Currency{} = c, :narrow),
    do: c.narrow_symbol || c.symbol || iso_code(c)

  defp resolve_currency_symbol(%Localize.Currency{} = c, :iso), do: iso_code(c)
  defp resolve_currency_symbol(%Localize.Currency{} = c, :symbol), do: c.symbol || iso_code(c)
  defp resolve_currency_symbol(%Localize.Currency{} = c, nil), do: c.symbol || iso_code(c)
  defp resolve_currency_symbol(_currency, other) when is_binary(other), do: other
  defp resolve_currency_symbol(%Localize.Currency{} = c, _), do: c.symbol || iso_code(c)

  defp iso_code(%Localize.Currency{code: code}), do: Atom.to_string(code)

  # ── Currency spacing resolution ─────────────────────────────

  defp resolve_currency_spacing(nil, _formats), do: nil

  defp resolve_currency_spacing(%Localize.Currency{}, %Format{currency_spacing: spacing}),
    do: spacing

  defp resolve_currency_spacing(%Localize.Currency{}, %{currency_spacing: spacing}),
    do: spacing

  defp resolve_currency_spacing(%Localize.Currency{}, _formats), do: nil

  # ── Sign detection ──────────────────────────────────────────

  defp negative?(%Decimal{sign: sign}) when sign < 0, do: true
  defp negative?(number) when is_number(number) and number < 0, do: true
  defp negative?(_), do: false
end
