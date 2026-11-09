defmodule Localize.Number.Format.Options do
  @moduledoc """
  Validation and resolution of number formatting options.

  `validate_options/2` resolves a keyword list of the options accepted by `Localize.Number.to_string/2` into a `t:Localize.Number.Format.Options.t/0` struct — locale validation, number system resolution, format pattern lookup, currency data loading and symbol resolution all happen once. Passing the resulting struct to `Localize.Number.to_string/2` bypasses that resolution on every call, which is significantly faster when formatting many numbers with the same locale and format. See the [Performance and optimization](number_formatting.html#performance-and-optimization) section of the Number Formatting guide for benchmarks.

  """

  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  alias Localize.Number.{Format, Symbol, System}

  @options [
    :locale,
    :number_system,
    :currency,
    :format,
    :grammatical_case,
    :grammatical_gender,
    :currency_format,
    :currency_digits,
    :currency_spacing,
    :currency_symbol,
    :symbols,
    :minimum_grouping_digits,
    :locale_minimum_grouping_digits,
    :pattern,
    :rounding_mode,
    :fractional_digits,
    :min_fractional_digits,
    :max_fractional_digits,
    :maximum_integer_digits,
    :minimum_integer_digits,
    :minimum_significant_digits,
    :maximum_significant_digits,
    :round_nearest,
    :wrapper,
    :separators,
    :exponent_style,
    :sign_display,
    :trailing_zero_display,
    :rounding_priority
  ]

  @exponent_styles [:e, :superscript]

  @sign_displays [:auto, :always, :except_zero, :negative, :never]

  @digit_count_options [
    :fractional_digits,
    :min_fractional_digits,
    :max_fractional_digits,
    :maximum_integer_digits
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
    :engineering,
    :percent,
    :currency_no_symbol,
    :accounting_no_symbol,
    :currency_alpha_next_to_number,
    :accounting_alpha_next_to_number
  ]

  # TR35 specifies the engineering rule but CLDR ships no
  # `scientificFormats/engineering` block. When the user passes
  # `format: :engineering`, we synthesize this pattern: max 3 integer
  # digits → exponent forced to a multiple of 3; up to 6 fraction
  # digits in the mantissa for full `Decimal` precision through the
  # exponent shift. Users wanting different precision should pass an
  # explicit pattern string such as `"##0.###E0"`.
  @default_engineering_pattern "##0.######E0"

  @short_formats [
    :currency_short,
    :currency_long_with_symbol,
    :currency_long,
    :decimal_short,
    :decimal_long
  ]

  # The fields of a locale's `Localize.Number.Format` a decimal format reads,
  # kept per locale and number system in `Localize.FormatCache`. The compact
  # formats are left out: they are most of the struct, an ETS read copies
  # the entry, and the compact formatters read them from the locale.
  @cached_format_fields @standard_formats ++ [:currency_spacing]

  defstruct @options

  @type t :: %__MODULE__{}

  @currency_indicator "¤"

  # Set default fractional digits from the currency data when the
  # caller hasn't provided fractional_digits and the format is either a
  # standard currency format (an atom like :currency or :accounting) or
  # a pattern string with a currency sign. TR35 has the currency's
  # supplemental data override a currency pattern's decimal places, as
  # ICU does; a pattern with significant digits keeps them.
  @currency_fraction_formats [
    :currency,
    :accounting,
    :standard,
    :currency_no_symbol,
    :accounting_no_symbol,
    :currency_alpha_next_to_number,
    :accounting_alpha_next_to_number,
    # The long forms apply the currency's fraction digits to the
    # number portion per ECMA-402 `currencyDisplay: "name"`:
    # "1,234.50 US dollars", not "1,234.5 US dollars".
    :currency_long,
    :currency_long_with_symbol
  ]

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
  #     grammatical_case: :nominative,
  #     grammatical_gender: nil,
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

  * `number` is a representative number, such as `0`. The
    struct formats numbers of either sign: each call takes the
    sign from the number it formats.

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
  def validate_options(number, options) when is_keyword_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    currency = Keyword.get(options, :currency)
    format = options |> Keyword.get(:format, :standard) |> resolve_format_alias(currency)
    number_system = Keyword.get(options, :number_system, :default)
    rounding_mode = Keyword.get(options, :rounding_mode, :half_even)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, locale_data} <- locale_number_data(language_tag, number_system),
         {:ok, currency_struct} <- resolve_currency(format, currency, language_tag),
         format <-
           maybe_switch_currency_format(
             format,
             currency_struct,
             language_tag,
             options[:currency_symbol]
           ),
         :ok <- validate_rounding_mode(rounding_mode),
         :ok <- validate_significant_digits(options),
         :ok <- validate_minimum_integer_digits(Keyword.get(options, :minimum_integer_digits)),
         :ok <- validate_exponent_style(Keyword.get(options, :exponent_style)),
         :ok <- validate_sign_display(Keyword.get(options, :sign_display)),
         :ok <- validate_trailing_zero_display(Keyword.get(options, :trailing_zero_display)),
         :ok <- validate_rounding_priority(Keyword.get(options, :rounding_priority)),
         :ok <- validate_digit_counts(options, @digit_count_options),
         :ok <- validate_wrapper(Keyword.get(options, :wrapper)),
         {:ok, symbols} <- resolve_symbols(locale_data.symbols, currency_struct),
         {:ok, resolved_format, formats} <- resolve_format(format, locale_data) do
      currency_symbol = resolve_currency_symbol(currency_struct, options[:currency_symbol])
      currency_spacing = resolve_currency_spacing(currency_struct, formats)
      pattern = if negative?(number), do: :negative, else: :positive
      currency_digits = Keyword.get(options, :currency_digits, :accounting)

      # For standard currency formats (not custom pattern strings), the
      # currency's digits are the default for whichever fraction bound the
      # caller did not give, as ECMA-402's currency defaults are.
      currency_fraction =
        default_currency_fractional_digits(format, currency_struct, currency_digits)

      {fractional_digits, min_fractional_digits, max_fractional_digits} =
        currency_fraction_bounds(options, currency_fraction)

      # Build struct from the options keyword list (passthrough fields)
      # then overlay the resolved values
      result =
        struct(__MODULE__, options)
        |> Map.merge(%{
          locale: language_tag,
          number_system: locale_data.system_name,
          currency: currency_struct,
          format: resolved_format,
          symbols: symbols,
          locale_minimum_grouping_digits: locale_data.minimum_grouping_digits,
          rounding_mode: rounding_mode || :half_even,
          currency_symbol: currency_symbol,
          currency_spacing: currency_spacing,
          currency_digits: currency_digits,
          fractional_digits: fractional_digits,
          min_fractional_digits: min_fractional_digits,
          max_fractional_digits: max_fractional_digits,
          pattern: pattern
        })

      {:ok, result}
    end
  end

  def validate_options(_number, options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  # ── Format aliases ──────────────────────────────────────────

  # `:short` and `:long` are accepted for compatibility with ex_cldr,
  # resolving to the compact decimal formats or, when a currency is
  # specified, to the compact currency formats.
  defp resolve_format_alias(:short, nil), do: :decimal_short
  defp resolve_format_alias(:short, _currency), do: :currency_short
  defp resolve_format_alias(:long, nil), do: :decimal_long
  defp resolve_format_alias(:long, _currency), do: :currency_long
  defp resolve_format_alias(format, _currency), do: format

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

  defp resolve_currency(format, nil, %Localize.LanguageTag{} = language_tag)
       when format in [:currency, :currency_long, :currency_long_with_symbol] do
    with {:ok, code} <- Localize.Currency.currency_from_locale(language_tag) do
      currency_for_locale(code, language_tag)
    end
  end

  defp resolve_currency(format, nil, %Localize.LanguageTag{} = language_tag)
       when is_binary(format) do
    if String.contains?(format, @currency_indicator) do
      with {:ok, code} <- Localize.Currency.currency_from_locale(language_tag) do
        currency_for_locale(code, language_tag)
      end
    else
      {:ok, nil}
    end
  end

  defp resolve_currency(_, currency, language_tag) when not is_nil(currency) do
    with {:ok, code} <- Localize.Currency.validate_currency(currency) do
      currency_for_locale(code, language_tag)
    end
  end

  defp resolve_currency(_format, _currency, _language_tag) do
    {:ok, nil}
  end

  # A locale's CLDR data lists the currencies it names, and a sparse
  # locale lists few, so a currency missing from it ("ady" has no KWD,
  # "es" no VED) is formatted with its parent's data, ending at the
  # default locale. The digits are the currency's own whatever the
  # locale; only the symbol and names come from a fallback locale.
  defp currency_for_locale(code, language_tag) do
    Localize.Currency.currency_for_code(code, locale: language_tag, fallback: true)
  end

  # ── Format auto-switch ──────────────────────────────────────

  # `currency_symbol: :none` flips any currency-shaped format to
  # the corresponding no-symbol variant. The result uses the
  # CLDR `currency_no_symbol` (or `accounting_no_symbol`) pattern
  # so spacing, grouping and decimal separators stay locale-
  # correct — only the symbol character is omitted.
  defp maybe_switch_currency_format(:standard, %Localize.Currency{}, _language_tag, :none),
    do: :currency_no_symbol

  defp maybe_switch_currency_format(:currency, %Localize.Currency{}, _language_tag, :none),
    do: :currency_no_symbol

  defp maybe_switch_currency_format(:accounting, %Localize.Currency{}, _language_tag, :none),
    do: :accounting_no_symbol

  defp maybe_switch_currency_format(:standard, %Localize.Currency{}, language_tag, _symbol) do
    case Localize.Currency.currency_format_from_locale(language_tag) do
      {:ok, format} -> format
      _ -> :currency
    end
  end

  defp maybe_switch_currency_format(format, _currency, _language_tag, _symbol), do: format

  # ── Rounding mode validation ────────────────────────────────

  defp validate_rounding_mode(nil), do: :ok
  defp validate_rounding_mode(mode) when mode in @rounding_modes, do: :ok

  defp validate_rounding_mode(mode) do
    {:error,
     Localize.InvalidValueError.exception(
       value: mode,
       expected: :rounding_mode,
       allowed_values: @rounding_modes
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

  # ── Exponent style validation ──────────────────────────────

  # Controls how scientific patterns render the exponent. `:e` (the
  # default, including `nil`) emits `<exp_symbol><sign><digits>` per
  # `Localize.Number.Formatter.Decimal.reassemble_number_string/3`.
  # `:superscript` emits `<superscriptingExponent>10<superscript_digits>`
  # — the `1.23 × 10⁴` form. Anything else is rejected so unfamiliar
  # values surface as clear errors rather than silently emitting the
  # default.
  defp validate_exponent_style(nil), do: :ok
  defp validate_exponent_style(style) when style in @exponent_styles, do: :ok

  defp validate_exponent_style(style) do
    {:error,
     Localize.InvalidValueError.exception(
       value: style,
       expected: :exponent_style,
       allowed_values: @exponent_styles
     )}
  end

  # ── Minimum integer digits validation ──────────────────────

  # ECMA-402 `minimumIntegerDigits`: a positive integer in 1..21.
  # `nil` means "not set" — the format pattern's own minimum
  # integer width (its leading `0` placeholders) applies unchanged.
  defp validate_minimum_integer_digits(nil), do: :ok

  defp validate_minimum_integer_digits(digits) when is_integer(digits) and digits in 1..21 do
    :ok
  end

  defp validate_minimum_integer_digits(digits) do
    {:error,
     Localize.InvalidValueError.exception(
       value: digits,
       expected: "minimum_integer_digits to be an integer in 1..21"
     )}
  end

  # ── Digit count validation ─────────────────────────────────

  # `:fractional_digits`, `:min_fractional_digits`,
  # `:max_fractional_digits` and `:maximum_integer_digits` are digit
  # counts. `nil` means "not set".
  defp validate_digit_counts(_options, []), do: :ok

  defp validate_digit_counts(options, [key | keys]) do
    case Keyword.get(options, key) do
      digits when is_nil(digits) or is_integer(digits) ->
        validate_digit_counts(options, keys)

      digits ->
        {:error,
         Localize.InvalidValueError.exception(
           value: digits,
           expected: "#{key} to be an integer"
         )}
    end
  end

  # ── Wrapper validation ─────────────────────────────────────

  # `:wrapper` is called with each formatted string and its tag.
  defp validate_wrapper(nil), do: :ok
  defp validate_wrapper(wrapper) when is_function(wrapper, 2), do: :ok

  defp validate_wrapper(wrapper) do
    {:error,
     Localize.InvalidValueError.exception(
       value: wrapper,
       expected: "wrapper to be a function of arity 2"
     )}
  end

  # ── Rounding priority validation ───────────────────────────

  # ECMA-402 `roundingPriority`: resolves the conflict when both
  # fraction-digit and significant-digit bounds are given. `:auto`
  # (or `nil`, the default) lets significant digits win;
  # `:more_precision` / `:less_precision` pick the bound that
  # yields more/fewer digits for the value being formatted.
  defp validate_rounding_priority(priority)
       when priority in [nil, :auto, :more_precision, :less_precision] do
    :ok
  end

  defp validate_rounding_priority(priority) do
    {:error,
     Localize.InvalidValueError.exception(
       value: priority,
       expected: :rounding_priority,
       allowed_values: [:auto, :more_precision, :less_precision]
     )}
  end

  # ── Trailing zero display validation ───────────────────────

  # ECMA-402 `trailingZeroDisplay`: `:auto` (or `nil`, the default)
  # keeps the minimum-fraction padding; `:strip_if_integer` drops
  # the fraction entirely when the rounded value is an integer.
  defp validate_trailing_zero_display(display) when display in [nil, :auto, :strip_if_integer] do
    :ok
  end

  defp validate_trailing_zero_display(display) do
    {:error,
     Localize.InvalidValueError.exception(
       value: display,
       expected: :trailing_zero_display,
       allowed_values: [:auto, :strip_if_integer]
     )}
  end

  # ── Sign display validation ────────────────────────────────

  # Mirrors ECMA-402 `signDisplay` (auto | always | exceptZero |
  # negative | never) as snake_case atoms. `nil` means "not set"
  # and behaves as `:auto` — the format pattern's own sign
  # handling applies unchanged.
  defp validate_sign_display(nil), do: :ok
  defp validate_sign_display(sign_display) when sign_display in @sign_displays, do: :ok

  defp validate_sign_display(sign_display) do
    {:error,
     Localize.InvalidValueError.exception(
       value: sign_display,
       expected: :sign_display,
       allowed_values: @sign_displays
     )}
  end

  # ── Symbols resolution ──────────────────────────────────────

  # A currency amount is separated by the locale's currency symbols where it
  # has them: CLDR gives `fr-CH` a `currencyDecimal` and `de-AT` a
  # `currencyGroup` that differ from their plain-number separators.
  defp resolve_symbols(nil, _currency) do
    {:ok, nil}
  end

  defp resolve_symbols(symbols, nil) do
    {:ok, symbols}
  end

  defp resolve_symbols(symbols, currency) do
    {:ok, Symbol.for_currency(symbols, currency)}
  end

  # ── Locale number data ──────────────────────────────────────

  # The locale data a format reads: the number system the request
  # resolves to, and the symbols, standard format patterns, currency
  # spacing and minimum grouping digits of that system. Each is a read of
  # the locale through `Localize.Locale.get/3`, and the formats merge the
  # system's own with the locale's default system's, so together they
  # were most of a format's cost (#67). They are resolved once per locale
  # and number system and kept in `Localize.FormatCache`, where a hit is
  # one ETS read. The read copies the entry, so it holds the format
  # fields of `@cached_format_fields` and not the compact formats. The
  # key carries the number system as it was asked for, since a type such
  # as `:default` resolves against the locale; an error is not kept, so
  # an unknown system name stays an error and leaves nothing.
  defp locale_number_data(language_tag, number_system) do
    key =
      {:localize, :number_locale_data, language_tag.cldr_locale_id,
       system_key(language_tag, number_system)}

    case Localize.FormatCache.lookup(key) do
      {:ok, locale_data} -> {:ok, locale_data}
      :miss -> resolve_locale_number_data(key, language_tag, number_system)
    end
  end

  defp resolve_locale_number_data(key, language_tag, number_system) do
    with {:ok, system_name} <- resolve_number_system(language_tag, number_system) do
      locale_data = %{
        system_name: system_name,
        symbols: symbols_for_system(language_tag, system_name),
        formats: cached_formats(formats_for_system(language_tag, system_name)),
        minimum_grouping_digits: minimum_grouping_digits_for(language_tag)
      }

      Localize.FormatCache.store(key, locale_data)
      {:ok, locale_data}
    end
  end

  # A tag's `-u-nu-` names the system a `:default` request resolves to,
  # as `resolve_number_system/2` reads it, so it is the key's system.
  defp system_key(%Localize.LanguageTag{locale: locale}, number_system)
       when number_system in [:default, nil] do
    case locale do
      %{nu: system_name} when not is_nil(system_name) -> system_name
      _no_number_system -> :default
    end
  end

  defp system_key(_language_tag, number_system) do
    number_system
  end

  defp symbols_for_system(language_tag, system_name) do
    case Symbol.number_symbols_for(language_tag, system_name) do
      {:ok, symbols} -> symbols
      {:error, _no_symbols} -> nil
    end
  end

  defp formats_for_system(language_tag, system_name) do
    case Format.formats_for(language_tag, system_name) do
      {:ok, formats} -> formats
      {:error, _no_formats} -> nil
    end
  end

  defp cached_formats(nil) do
    nil
  end

  defp cached_formats(%Format{} = formats) do
    Map.take(formats, @cached_format_fields)
  end

  defp minimum_grouping_digits_for(language_tag) do
    case Format.minimum_grouping_digits_for(language_tag) do
      {:ok, digits} -> digits
      {:error, _no_digits} -> nil
    end
  end

  # ── Format resolution ───────────────────────────────────────

  # `:engineering` is intercepted before the generic standard-formats
  # lookup. The locale's `Format` struct still goes through (so
  # caller-side downstream resolutions — currency spacing, etc. — still
  # work), but the pattern is the struct's `:engineering` pattern when it
  # is populated or the synthesised default, never the atom literal.
  defp resolve_format(:engineering, %{formats: formats}) do
    pattern =
      case formats do
        %{engineering: p} when is_binary(p) -> p
        _ -> @default_engineering_pattern
      end

    {:ok, pattern, formats}
  end

  # Standard formats: look up the pattern in the locale's formats for
  # the number system. `Format.formats_for/2` inherits per-field from
  # the locale's default system when the requested system has no data
  # of its own, so a numeric system requested via `-u-nu-` (for
  # example `en-u-nu-thai`) always resolves to a pattern string.
  #
  # `:standard` with an algorithmic system (`:hans`, `:roman`, …) is
  # the exception: it stays an atom so `Localize.Number.to_string/2`
  # dispatches to the system's RBNF rules instead of the decimal
  # formatter: TR35 has "the rules for presentation of numbers in an
  # algorithmic system" given by its RBNF rule set. All other standard
  # formats degrade to the default system's pattern (with latin
  # digits) since algorithmic systems define no patterns for them.
  defp resolve_format(format, %{system_name: system_name, formats: formats})
       when format in @standard_formats do
    cond do
      format == :standard and algorithmic_system?(system_name) -> {:ok, :standard, nil}
      is_nil(formats) -> {:ok, format, nil}
      true -> {:ok, Map.get(formats, format) || format, formats}
    end
  end

  # Short formats need no resolution, and a custom pattern none either,
  # but the locale's formats still supply the currency spacing TR35
  # applies wherever a currency sign meets the number.
  defp resolve_format(format, %{formats: formats})
       when format in @short_formats or is_binary(format) do
    {:ok, format, formats}
  end

  defp resolve_format(format, _locale_data) do
    {:ok, format, nil}
  end

  defp algorithmic_system?(system_name) do
    Map.has_key?(System.algorithmic_systems(), system_name)
  end

  # ── Currency symbol resolution ──────────────────────────────

  # ── Currency fractional digits ─────────────────────────────

  defp default_currency_fractional_digits(format, %Localize.Currency{} = currency, digits)
       when format in @currency_fraction_formats do
    currency_fraction_digits(currency, digits)
  end

  defp default_currency_fractional_digits(format, %Localize.Currency{} = currency, digits)
       when is_binary(format) do
    if currency_pattern?(format), do: currency_fraction_digits(currency, digits)
  end

  defp default_currency_fractional_digits(_format, _currency, _currency_digits), do: nil

  # The fraction bounds once the currency's default fills the ones the
  # caller did not give. With none given the default sets both, as
  # `:fractional_digits`; with only a maximum the default minimum is capped
  # at it, and with only a minimum the default maximum is raised to it
  # (ECMA-402: mnfd = min(mnfdDefault, mxfd), mxfd = max(mxfdDefault, mnfd)),
  # so `max_fractional_digits: 0` writes "$1,235", not "$1,235.00".
  defp currency_fraction_bounds(options, default) do
    fractional_digits = Keyword.get(options, :fractional_digits)
    minimum = Keyword.get(options, :min_fractional_digits)
    maximum = Keyword.get(options, :max_fractional_digits)

    cond do
      not is_nil(fractional_digits) or is_nil(default) ->
        {fractional_digits, minimum, maximum}

      is_nil(minimum) and is_nil(maximum) ->
        {default, nil, nil}

      is_nil(minimum) ->
        {nil, min(default, maximum), maximum}

      is_nil(maximum) ->
        {nil, minimum, max(default, minimum)}

      true ->
        {nil, minimum, maximum}
    end
  end

  defp currency_fraction_digits(currency, :accounting), do: currency.digits
  defp currency_fraction_digits(currency, :cash), do: currency.cash_digits
  defp currency_fraction_digits(currency, :iso), do: currency.iso_digits
  defp currency_fraction_digits(_currency, _currency_digits), do: nil

  # A pattern with a currency sign and no significant digits. An invalid
  # pattern is reported when the number is formatted.
  defp currency_pattern?(format) do
    case Localize.Number.Formatter.Decimal.metadata(format) do
      {:ok, %{currency: %{}, significant_digits: %{max: 0}}} -> true
      _other -> false
    end
  end

  # ── Currency symbol resolution ──────────────────────────────

  # Per TR35: if no symbol data is available for a currency in a locale,
  # fall back to the ISO 4217 currency code (e.g., "CHF").
  # Delegates to `Localize.Currency.symbol/2` which is the public
  # entry point for symbol-kind resolution.
  defp resolve_currency_symbol(nil, _option), do: ""

  defp resolve_currency_symbol(%Localize.Currency{} = currency, option) do
    {:ok, symbol} = Localize.Currency.symbol(currency, option)
    symbol
  end

  # ── Currency spacing resolution ─────────────────────────────

  defp resolve_currency_spacing(nil, _formats), do: nil

  defp resolve_currency_spacing(%Localize.Currency{}, %{currency_spacing: spacing}),
    do: spacing

  defp resolve_currency_spacing(%Localize.Currency{}, _formats), do: nil

  # ── Sign detection ──────────────────────────────────────────

  defp negative?(%Decimal{sign: sign}) when sign < 0, do: true

  # IEEE-754 negative zero compares equal to zero, so `< 0` misses it, but it
  # is negative and CLDR's decimal conformance data has it rendered with its
  # sign — `-0.0` is "-0", not "0". Read the sign bit rather
  # than the value; for every other float it agrees with `< 0`.
  defp negative?(number) when is_float(number),
    do: match?(<<1::1, _::bitstring>>, <<number::float>>)

  defp negative?(number) when is_number(number) and number < 0, do: true
  defp negative?(_), do: false
end
