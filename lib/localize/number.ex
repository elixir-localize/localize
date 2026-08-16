defmodule Localize.Number do
  @moduledoc """
  Functions for formatting numbers in a locale-aware manner.

  This module provides the primary public API for converting
  numbers to localized string representations, including
  standard decimal formatting, currency formatting, percentage
  formatting, and scientific notation.

  All formatting is driven by CLDR locale data accessed at
  runtime via the locale provider.

  """

  alias Localize.Number.Format
  alias Localize.Number.Format.Options
  alias Localize.Number.Formatter
  alias Localize.Number.Rbnf
  alias Localize.Number.System

  @doc """
  Formats a number as a localized string.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`. The default is `:en`.

  * `:number_system` is a number system name or type atom.
    The default is `:default`.

  * `:format` is a format style atom or a format pattern string.
    The default is `:standard`. Common styles include `:standard`,
    `:currency`, `:accounting`, `:percent`, `:scientific`,
    `:engineering`, `:decimal_short`, `:decimal_long`. The aliases
    `:short` and `:long` resolve to `:decimal_short` and
    `:decimal_long`, or to `:currency_short` and `:currency_long`
    when a `:currency` is specified. `:scientific`
    resolves to the locale's CLDR `scientificFormats/standard` pattern
    (e.g. `"#E0"`). `:engineering` resolves to `"##0.######E0"`,
    forcing the exponent to a multiple of 3 — CLDR ships no
    engineering pattern, so this is a Localize-supplied default;
    pass an explicit pattern string for a different mantissa
    precision. Any RBNF rule name atom supported by the locale is
    also accepted (e.g., `:spellout_cardinal`, `:spellout_ordinal`,
    `:digits_ordinal`, `:roman_upper`). The atoms `:spellout` and
    `:ordinal` resolve to the best available spellout or ordinal
    rule for the locale. See
    `Localize.Number.Rbnf.rule_names_for_locale/1` to discover the
    rule names supported by a locale.

  * `:currency` is a currency code atom (e.g., `:USD`). When
    provided, currency formatting is applied.

  * `:rounding_mode` is one of `:down`, `:half_up`, `:half_even`,
    `:ceiling`, `:floor`, `:half_down`, `:up`. The default is
    `:half_even`.

  * `:fractional_digits` is an integer that sets both the minimum
    and maximum fractional digits to the same value. Equivalent to
    setting `:min_fractional_digits` and `:max_fractional_digits`
    to the same integer. Overridden by either of those options when
    they are also provided.

  * `:min_fractional_digits` is an integer specifying the minimum
    number of fractional digits. Trailing zeros are added to reach
    this count. When not set, falls back to `:fractional_digits`
    or the format pattern default.

  * `:max_fractional_digits` is an integer specifying the maximum
    number of fractional digits. Values are rounded to fit. When
    not set, falls back to `:fractional_digits` or the format
    pattern default.

  * `:maximum_integer_digits` is an integer specifying the maximum
    number of integer digits to display.

  * `:minimum_integer_digits` is an integer in `1..21` specifying the minimum number of integer digits to display, mirroring ECMA-402's `minimumIntegerDigits`. The integer part is zero-padded to the requested width and the padding digits group normally, so `123` with `minimum_integer_digits: 5` renders "00,123". The default is the width implied by the format pattern's leading `0` placeholders.

  * `:trailing_zero_display` is `:auto` (the default) or `:strip_if_integer`, mirroring ECMA-402's `trailingZeroDisplay`. With `:strip_if_integer` the fraction is dropped entirely when the rounded value is an integer, even when a fraction minimum would otherwise pad it: `1000` with `fractional_digits: 2` renders "1,000" while `1000.5` renders "1,000.50".

  * `:rounding_priority` is `:auto` (the default), `:more_precision`, or `:less_precision`, mirroring ECMA-402's `roundingPriority`. It applies only when both fraction-digit and significant-digit bounds are given: `:auto` lets significant digits win, while `:more_precision`/`:less_precision` pick whichever bound yields more/fewer digits for the value being formatted.

  * `:minimum_significant_digits` is an integer in `1..21` specifying the minimum number of significant digits the formatted output should retain. When set, significant-digit precision overrides the format pattern's fractional-digit settings. Defaults to the value derived from the format pattern's `@@##` notation, or `nil` (no significant-digit constraint).

  * `:maximum_significant_digits` is an integer in `1..21` specifying the maximum number of significant digits to display. Values are rounded to fit using the configured `:rounding_mode`. Pairs with `:minimum_significant_digits`; when only one is set the other defaults to the corresponding ECMA-402 boundary (`1` for minimum, `21` for maximum).

  * `:sign_display` controls when the number's sign is shown,
    mirroring ECMA-402's `signDisplay` option. `:auto` (the
    default) shows the sign for negative numbers only. `:always`
    shows a sign for every number, rendering the locale's plus
    sign for positive numbers and zero. `:except_zero` shows a
    sign for every number except those that round to zero.
    `:negative` is like `:auto` except that negative numbers
    rounding to zero display no sign. `:never` never shows a
    sign. Zero-ness is judged after rounding, so `-0.2` with
    `fractional_digits: 0` counts as zero. Sign placement follows
    the format's negative subpattern — `format: :accounting`
    keeps parentheses for negative numbers and prefixes the plus
    sign for positive ones. The option applies to decimal,
    currency, percent, scientific and compact formats; it is
    ignored by RBNF formats such as `:spellout`.

  * `:exponent_style` controls how scientific patterns render the
    exponent. `:e` (the default) emits the standard `1.234E3` form
    using the locale's `exponential` symbol and minus/plus signs.
    `:superscript` emits the `1.234 × 10³` form using CLDR's
    `superscriptingExponent` symbol (universally `×`, U+00D7) and
    Unicode superscript digits (`⁰¹²³⁴⁵⁶⁷⁸⁹`, with `⁻` and `⁺`
    for signs). The option is ignored for non-scientific patterns.

  * `:wrapper` is a function of arity 2 that wraps formatted
    components. Useful for adding HTML markup.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if options are invalid or formatting fails.

  ### Examples

      iex> Localize.Number.to_string(1234)
      {:ok, "1,234"}

      iex> Localize.Number.to_string(1234.5, locale: :en)
      {:ok, "1,234.5"}

      iex> Localize.Number.to_string(0.56, format: :percent, locale: :en)
      {:ok, "56%"}

  """
  @spec to_string(number() | Decimal.t(), Keyword.t() | struct()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(number, options \\ [])

  def to_string(number, %Options{} = validated_options) do
    dispatch_format(number, validated_options)
  end

  def to_string(number, options) when is_number(number) and is_list(options) do
    case Localize.Backend.resolve(options) do
      :nif ->
        locale = Keyword.get(options, :locale, Localize.get_locale())

        with {:ok, locale_string} <- validated_locale_string(locale) do
          Localize.Nif.number_format(number, locale_string, options)
        end

      :elixir ->
        with {:ok, validated_options} <- Options.validate_options(number, options) do
          dispatch_format(number, validated_options)
        end
    end
  end

  def to_string(%Decimal{} = number, options) when is_list(options) do
    case Localize.Backend.resolve(options) do
      :nif ->
        locale = Keyword.get(options, :locale, Localize.get_locale())

        with {:ok, locale_string} <- validated_locale_string(locale) do
          Localize.Nif.number_format(number, locale_string, options)
        end

      :elixir ->
        with {:ok, validated_options} <- Options.validate_options(number, options) do
          dispatch_format(number, validated_options)
        end
    end
  end

  def to_string(number, _options) do
    {:error,
     Localize.InvalidValueError.exception(
       value: number,
       expected: "a number (integer, float, or Decimal)"
     )}
  end

  defp dispatch_format(number, validated_options) do
    format = validated_options.format

    if is_binary(format) do
      Formatter.Decimal.to_string(number, format, validated_options)
    else
      dispatch_format_style(number, format, validated_options)
    end
  end

  defp dispatch_format_style(number, format, validated_options) do
    cond do
      format in [:decimal_short, :decimal_long, :currency_short] ->
        Formatter.Short.to_string(number, format, validated_options)

      format in [:currency_long, :currency_long_with_symbol] ->
        Formatter.Currency.to_string(number, format, validated_options)

      # `:standard` survives options resolution as an atom only when
      # the number system is algorithmic (`:hans`, `:roman`, …) —
      # numeric systems always resolve it to a pattern string. Per
      # ICU, decimal formatting in an algorithmic system uses the
      # system's RBNF rules.
      format == :standard and algorithmic_system?(validated_options.number_system) ->
        System.to_system(number, validated_options.number_system)

      is_atom(format) ->
        Rbnf.to_string(number, format, locale: validated_options.locale)

      true ->
        {:error,
         Localize.InvalidValueError.exception(
           value: format,
           expected: "a format string or known format style",
           context: "Localize.Number.to_string/2"
         )}
    end
  end

  defp algorithmic_system?(system_name) do
    Map.has_key?(System.algorithmic_systems(), system_name)
  end

  @doc """
  Same as `to_string/2` but raises on error.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * A formatted string.

  ### Raises

  * Raises an exception if formatting fails.

  ### Examples

      iex> Localize.Number.to_string!(1234)
      "1,234"

  """
  @spec to_string!(number() | Decimal.t(), Keyword.t()) :: String.t()
  def to_string!(number, options \\ []) do
    case to_string(number, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats a number into a list of typed parts, mirroring ECMA-402's `formatToParts`.

  The parts concatenate to exactly the string `to_string/2` produces with the same options, but each segment is tagged with its role so callers can style, wrap, or reorder individual pieces. Part types follow ECMA-402 in snake_case: `:integer`, `:group`, `:decimal`, `:fraction`, `:currency`, `:percent_sign`, `:per_mille`, `:minus_sign`, `:plus_sign`, `:exponent_separator`, `:exponent_minus_sign`, `:exponent_plus_sign`, `:exponent_integer`, `:compact`, `:literal`, `:nan`, and `:infinity`.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options. All `to_string/2` options are supported except `:wrapper` and `backend: :nif` (parts are produced by the Elixir formatting pipeline).

  ### Returns

  * `{:ok, parts}` where `parts` is a list of `%{type: atom(), value: String.t()}` maps.

  * `{:error, exception}` for invalid options, or for formats that do not decompose into parts (the RBNF rule-name formats such as `:spellout`).

  ### Examples

      iex> Localize.Number.to_parts(-1234.5)
      {:ok,
       [
         %{type: :minus_sign, value: "-"},
         %{type: :integer, value: "1"},
         %{type: :group, value: ","},
         %{type: :integer, value: "234"},
         %{type: :decimal, value: "."},
         %{type: :fraction, value: "5"}
       ]}

      iex> Localize.Number.to_parts(1234.5, currency: :USD)
      {:ok,
       [
         %{type: :currency, value: "$"},
         %{type: :integer, value: "1"},
         %{type: :group, value: ","},
         %{type: :integer, value: "234"},
         %{type: :decimal, value: "."},
         %{type: :fraction, value: "50"}
       ]}

  """
  @spec to_parts(number() | Decimal.t(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(number, options \\ []) do
    with {:ok, validated_options} <- Options.validate_options(number, options) do
      dispatch_parts(number, validated_options)
    end
  end

  @doc """
  Same as `to_parts/2` but raises on error.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Options

  See `to_parts/2` for the supported options.

  ### Returns

  * A list of `%{type: atom(), value: String.t()}` maps.

  ### Raises

  * Raises an exception if formatting fails.

  ### Examples

      iex> Localize.Number.to_parts!(42, minimum_integer_digits: 3)
      [%{type: :integer, value: "042"}]

  """
  @spec to_parts!(number() | Decimal.t(), Keyword.t()) :: [%{type: atom(), value: String.t()}]
  def to_parts!(number, options \\ []) do
    case to_parts(number, options) do
      {:ok, parts} -> parts
      {:error, exception} -> raise exception
    end
  end

  defp dispatch_parts(number, validated_options) do
    format = validated_options.format

    cond do
      is_binary(format) ->
        Formatter.Decimal.to_parts(number, format, validated_options)

      format in [:decimal_short, :decimal_long, :currency_short] ->
        Formatter.Short.to_parts(number, format, validated_options)

      format in [:currency_long, :currency_long_with_symbol] ->
        Formatter.Currency.to_parts(number, format, validated_options)

      # Algorithmic numbering systems format via RBNF; the rendered
      # numeral is a single opaque token, so it is one integer part —
      # the same shape ICU produces.
      format == :standard and algorithmic_system?(validated_options.number_system) ->
        with {:ok, formatted} <- System.to_system(number, validated_options.number_system) do
          {:ok, [%{type: :integer, value: formatted}]}
        end

      true ->
        {:error,
         Localize.InvalidValueError.exception(
           value: format,
           expected: "a format that decomposes into parts",
           context: "Localize.Number.to_parts/2"
         )}
    end
  end

  @doc """
  Formats an Elixir `t:Range.t/0` as a localized string.

  Equivalent to `to_range_string(range.first, range.last, options)`.
  See `to_range_string/3` for the full description and options.

  ### Arguments

  * `range` is an Elixir `t:Range.t/0` (e.g., `3..5`).

  * `options` is a keyword list of options. See `to_range_string/3`.

  ### Returns

  * `{:ok, formatted_range}` on success.

  * `{:error, exception}` if formatting fails.

  ### Examples

      iex> Localize.Number.to_range_string(3..5, locale: :en)
      {:ok, "3–5"}

  """
  @spec to_range_string(Range.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_range_string(%Range{first: first, last: last}, options) do
    to_range_string(first, last, options)
  end

  @doc """
  Formats a numeric range as a localized string.

  Uses the locale's range pattern (e.g., `"3–5"` in English,
  `"3～5"` in Japanese) to combine two formatted numbers. When the
  start and end are equal, the locale's approximately pattern is
  used instead (e.g., `"~5"`).

  ### Arguments

  * `number_start` is the start of the range (integer, float,
    or Decimal).

  * `number_end` is the end of the range (integer, float, or
    Decimal).

  * `options` is a keyword list of options.

  ### Options

  All options accepted by `to_string/2` are supported and applied
  to both numbers. Additional options:

  * `:approximate` is a boolean. When `true` and the start and end
    differ, the formatted range is wrapped in the locale's
    approximately pattern (e.g. `"~3–5"`). When the start and end
    are equal, the approximately pattern is applied to the single
    number (which also happens by default). The default is `false`.

  ### Returns

  * `{:ok, formatted_range}` on success.

  * `{:error, exception}` if formatting fails.

  ### Examples

      iex> Localize.Number.to_range_string(3, 5, locale: :en)
      {:ok, "3–5"}

      iex> Localize.Number.to_range_string(5, 5, locale: :en)
      {:ok, "~5"}

      iex> Localize.Number.to_range_string(3, 5, locale: :en, approximate: true)
      {:ok, "~3–5"}

  """
  @spec to_range_string(number() | Decimal.t(), number() | Decimal.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_range_string(number_start, number_end, options \\ []) do
    {approximate, format_options} = Keyword.pop(options, :approximate, false)
    locale = Keyword.get(format_options, :locale, Localize.get_locale())
    format_options = Keyword.put_new(format_options, :locale, locale)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, number_system} <- System.number_system_from_locale(language_tag),
         {:ok, patterns} <- Format.misc_patterns_for(language_tag, number_system) do
      cond do
        number_start == number_end ->
          format_approximate_range(number_start, format_options, patterns)

        approximate ->
          format_approximate_full_range(number_start, number_end, format_options, patterns)

        true ->
          format_full_range(number_start, number_end, format_options, patterns)
      end
    end
  end

  # A genuine range formatted approximately: format the full range
  # first, then wrap it in the locale's approximately pattern
  # (e.g. "~3–5"). Previously the range end was silently dropped,
  # producing "~3".
  defp format_approximate_full_range(number_start, number_end, format_options, patterns) do
    with {:ok, range_string} <-
           format_full_range(number_start, number_end, format_options, patterns) do
      result = Localize.Substitution.substitute([range_string], patterns.approximately)
      {:ok, IO.iodata_to_binary(result)}
    end
  end

  defp format_approximate_range(number_start, format_options, patterns) do
    with {:ok, formatted} <- to_string(number_start, format_options) do
      result = Localize.Substitution.substitute([formatted], patterns.approximately)
      {:ok, IO.iodata_to_binary(result)}
    end
  end

  defp format_full_range(number_start, number_end, format_options, patterns) do
    with {:ok, formatted_start} <- to_string(number_start, format_options),
         {:ok, formatted_end} <- to_string(number_end, format_options) do
      result =
        Localize.Substitution.substitute([formatted_start, formatted_end], patterns.range)

      {:ok, IO.iodata_to_binary(result)}
    end
  end

  @doc """
  Same as `to_range_string/2` but raises on error.

  ### Arguments

  * `range` is an Elixir `t:Range.t/0` (e.g., `3..5`).

  * `options` is a keyword list of options. See `to_range_string/3`.

  ### Returns

  * A formatted string.

  * Raises an exception if formatting fails.

  ### Examples

      iex> Localize.Number.to_range_string!(3..5, locale: :en)
      "3–5"

  """
  @spec to_range_string!(Range.t(), Keyword.t()) :: String.t()
  def to_range_string!(%Range{} = range, options) do
    case to_range_string(range, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Same as `to_range_string/3` but raises on error.

  ### Arguments

  * `number_start` is the start of the range (integer, float,
    or Decimal).

  * `number_end` is the end of the range (integer, float, or
    Decimal).

  * `options` is a keyword list of options.

  ### Options

  See `to_range_string/3` for the supported options.

  ### Returns

  * A formatted string.

  ### Examples

      iex> Localize.Number.to_range_string!(3, 5, locale: :en)
      "3–5"

  """
  @spec to_range_string!(number() | Decimal.t(), number() | Decimal.t(), Keyword.t()) ::
          String.t()
  def to_range_string!(number_start, number_end, options \\ []) do
    case to_range_string(number_start, number_end, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats a numeric range into a list of typed parts, mirroring ECMA-402's `formatRangeToParts`.

  The parts concatenate to exactly the string `to_range_string/3` produces with the same options. In addition to the `:type` and `:value` keys of `to_parts/2`, every part carries a `:source` key: `:start_range` for parts of the range start, `:end_range` for parts of the range end, and `:shared` for separators and signs belonging to neither.

  ### Arguments

  * `number_start` is the start of the range (integer, float, or Decimal).

  * `number_end` is the end of the range (integer, float, or Decimal).

  * `options` is a keyword list of options.

  ### Options

  All options accepted by `to_parts/2` are supported and applied to both numbers, plus the `:approximate` option of `to_range_string/3`. When the start and end are equal the locale's approximately pattern applies and the approximately sign is tagged `:approximately_sign`, matching ECMA-402.

  ### Returns

  * `{:ok, parts}` where `parts` is a list of `%{type: atom(), value: String.t(), source: atom()}` maps.

  * `{:error, exception}` if the options are invalid or the format does not decompose into parts.

  ### Examples

      iex> Localize.Number.to_range_parts(3, 5, locale: :en)
      {:ok,
       [
         %{type: :integer, value: "3", source: :start_range},
         %{type: :literal, value: "–", source: :shared},
         %{type: :integer, value: "5", source: :end_range}
       ]}

      iex> Localize.Number.to_range_parts(5, 5, locale: :en)
      {:ok,
       [
         %{type: :approximately_sign, value: "~", source: :shared},
         %{type: :integer, value: "5", source: :shared}
       ]}

  """
  @spec to_range_parts(number() | Decimal.t(), number() | Decimal.t(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t(), source: atom()}]} | {:error, Exception.t()}
  def to_range_parts(number_start, number_end, options \\ []) do
    {approximate, format_options} = Keyword.pop(options, :approximate, false)
    locale = Keyword.get(format_options, :locale, Localize.get_locale())
    format_options = Keyword.put_new(format_options, :locale, locale)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, number_system} <- System.number_system_from_locale(language_tag),
         {:ok, patterns} <- Format.misc_patterns_for(language_tag, number_system) do
      cond do
        number_start == number_end ->
          approximate_single_parts(number_start, format_options, patterns)

        approximate ->
          approximate_full_range_parts(number_start, number_end, format_options, patterns)

        true ->
          full_range_parts(number_start, number_end, format_options, patterns)
      end
    end
  end

  @doc """
  Same as `to_range_parts/3` but raises on error.

  ### Arguments

  * `number_start` is the start of the range.

  * `number_end` is the end of the range.

  * `options` is a keyword list of options. See `to_range_parts/3`.

  ### Returns

  * A list of `%{type: atom(), value: String.t(), source: atom()}` maps.

  ### Raises

  * Raises an exception if formatting fails.

  ### Examples

      iex> Localize.Number.to_range_parts!(3, 5, locale: :en) |> length()
      3

  """
  @spec to_range_parts!(number() | Decimal.t(), number() | Decimal.t(), Keyword.t()) ::
          [%{type: atom(), value: String.t(), source: atom()}]
  def to_range_parts!(number_start, number_end, options \\ []) do
    case to_range_parts(number_start, number_end, options) do
      {:ok, parts} -> parts
      {:error, exception} -> raise exception
    end
  end

  defp full_range_parts(number_start, number_end, format_options, patterns) do
    with {:ok, start_parts} <- to_parts(number_start, format_options),
         {:ok, end_parts} <- to_parts(number_end, format_options) do
      parts =
        [put_source(start_parts, :start_range), put_source(end_parts, :end_range)]
        |> Localize.Substitution.substitute_parts(patterns.range)
        |> put_default_source(:shared)

      {:ok, parts}
    end
  end

  defp approximate_full_range_parts(number_start, number_end, format_options, patterns) do
    with {:ok, range_parts} <-
           full_range_parts(number_start, number_end, format_options, patterns) do
      parts =
        [range_parts]
        |> Localize.Substitution.substitute_parts(patterns.approximately, :approximately_sign)
        |> put_default_source(:shared)

      {:ok, parts}
    end
  end

  defp approximate_single_parts(number_start, format_options, patterns) do
    with {:ok, number_parts} <- to_parts(number_start, format_options) do
      parts =
        [number_parts]
        |> Localize.Substitution.substitute_parts(patterns.approximately, :approximately_sign)
        |> put_source(:shared)

      {:ok, parts}
    end
  end

  defp put_source(parts, source) do
    Enum.map(parts, &Map.put(&1, :source, source))
  end

  defp put_default_source(parts, source) do
    Enum.map(parts, &Map.put_new(&1, :source, source))
  end

  @doc """
  Formats a number with the locale's "at least" pattern.

  Produces strings like `"5+"` (English) or `"5以上"` (Japanese).

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * `{:ok, formatted}` on success.

  * `{:error, exception}` if formatting fails.

  ### Examples

      iex> Localize.Number.to_at_least_string(5, locale: :en)
      {:ok, "5+"}

  """
  @spec to_at_least_string(number() | Decimal.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_at_least_string(number, options \\ []) do
    format_misc_pattern(number, :at_least, options)
  end

  @doc """
  Same as `to_at_least_string/2` but raises on error.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * A formatted string.

  ### Examples

      iex> Localize.Number.to_at_least_string!(5, locale: :en)
      "5+"

  """
  @spec to_at_least_string!(number() | Decimal.t(), Keyword.t()) :: String.t()
  def to_at_least_string!(number, options \\ []) do
    case to_at_least_string(number, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats a number with the locale's "at most" pattern.

  Produces strings like `"≤5"` (English) or `"5以下"` (Japanese).

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * `{:ok, formatted}` on success.

  * `{:error, exception}` if formatting fails.

  ### Examples

      iex> Localize.Number.to_at_most_string(5, locale: :en)
      {:ok, "≤5"}

  """
  @spec to_at_most_string(number() | Decimal.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_at_most_string(number, options \\ []) do
    format_misc_pattern(number, :at_most, options)
  end

  @doc """
  Same as `to_at_most_string/2` but raises on error.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * A formatted string.

  ### Examples

      iex> Localize.Number.to_at_most_string!(5, locale: :en)
      "≤5"

  """
  @spec to_at_most_string!(number() | Decimal.t(), Keyword.t()) :: String.t()
  def to_at_most_string!(number, options \\ []) do
    case to_at_most_string(number, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats a number with the locale's approximately pattern.

  Produces strings like `"~5"` (English) or `"約 5"` (Japanese).

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * `{:ok, formatted}` on success.

  * `{:error, exception}` if formatting fails.

  ### Examples

      iex> Localize.Number.to_approximately_string(5, locale: :en)
      {:ok, "~5"}

  """
  @spec to_approximately_string(number() | Decimal.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_approximately_string(number, options \\ []) do
    format_misc_pattern(number, :approximately, options)
  end

  @doc """
  Same as `to_approximately_string/2` but raises on error.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * A formatted string.

  ### Examples

      iex> Localize.Number.to_approximately_string!(5, locale: :en)
      "~5"

  """
  @spec to_approximately_string!(number() | Decimal.t(), Keyword.t()) :: String.t()
  def to_approximately_string!(number, options \\ []) do
    case to_approximately_string(number, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  defp format_misc_pattern(number, pattern_key, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    options = Keyword.put_new(options, :locale, locale)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, number_system} <- System.number_system_from_locale(language_tag),
         {:ok, patterns} <- Format.misc_patterns_for(language_tag, number_system),
         {:ok, formatted} <- to_string(number, options) do
      pattern = Map.fetch!(patterns, pattern_key)
      result = Localize.Substitution.substitute([formatted], pattern)
      {:ok, IO.iodata_to_binary(result)}
    end
  end

  # ── Ratio formatting ────────────────────────────────────────

  @doc """
  Formats a number as a rational fraction string.

  Converts a decimal number to its rational fraction representation
  using the continued fraction algorithm, then formats it with CLDR
  rational format patterns.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `Localize.get_locale()`.

  * `:prefer` is a list of rendering preferences. Valid values are `:default`, `:super_sub`, and `:precomposed`. The default is `[:default]`.

  * `:max_denominator` is the largest permitted denominator. The default is `10`.

  * `:max_iterations` is the maximum continued fraction iterations. The default is `20`.

  * `:epsilon` is the tolerance for float comparisons. The default is `1.0e-10`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the number cannot be converted to a ratio or locale data is unavailable.

  ### Examples

      iex> Localize.Number.to_ratio_string(0.5)
      {:ok, "1⁄2"}

      iex> Localize.Number.to_ratio_string(0.5, prefer: [:precomposed])
      {:ok, "½"}

      iex> Localize.Number.to_ratio_string(0.5, prefer: [:super_sub])
      {:ok, "¹⁄₂"}

      iex> Localize.Number.to_ratio_string(1.5)
      {:ok, "1\u202F1⁄2"}

      iex> Localize.Number.to_ratio_string(1.5, prefer: [:super_sub, :precomposed])
      {:ok, "1\u2060½"}

  """
  @spec to_ratio_string(number() | Decimal.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  defdelegate to_ratio_string(number, options \\ []),
    to: Localize.Number.Formatter.Ratio

  @doc """
  Same as `to_ratio_string/2` but raises on error.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

  ### Options

  See `to_ratio_string/2` for the supported options.

  ### Returns

  * The formatted ratio string.

  ### Raises

  * Raises an exception if the number cannot be converted.

  ### Examples

      iex> Localize.Number.to_ratio_string!(0.5)
      "1⁄2"

  """
  @spec to_ratio_string!(number() | Decimal.t(), Keyword.t()) :: String.t()
  def to_ratio_string!(number, options \\ []) do
    case to_ratio_string(number, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Scans a string and returns a list of strings and numbers.

  Delegates to `Localize.Number.Parser.scan/2`.

  ### Arguments

  * `string` is any string.

  * `options` is a keyword list of options.

  ### Options

  * `:number` is one of `:integer`, `:float`, `:decimal`, or
    `nil`. The default is `nil` (auto-detect).

  * `:locale` is a locale identifier. The default is the locale
    returned by `Localize.get_locale/0`.

  * `:number_system` is a number system name or type.

  ### Returns

  * A list of strings and numbers.

  * `{:error, exception}` if the locale or number system is invalid.

  ### Examples

      iex> Localize.Number.scan("The prize is 23")
      ["The prize is ", 23]

      iex> Localize.Number.scan("1kg")
      [1, "kg"]

  """
  @spec scan(String.t(), Keyword.t()) ::
          list(String.t() | integer() | float() | Decimal.t())
          | {:error, Exception.t()}
  defdelegate scan(string, options \\ []), to: Localize.Number.Parser

  @doc """
  Parses a string to a number in a locale-aware manner.

  Delegates to `Localize.Number.Parser.parse/2`.

  ### Arguments

  * `string` is any string.

  * `options` is a keyword list of options.

  ### Options

  * `:number` is one of `:integer`, `:float`, `:decimal`, or
    `nil`. The default is `nil` (auto-detect).

  * `:locale` is a locale identifier. The default is the locale
    returned by `Localize.get_locale/0`.

  * `:number_system` is a number system name or type.

  ### Returns

  * `{:ok, number}` on success.

  * `{:error, exception}` if parsing fails.

  ### Examples

      iex> Localize.Number.parse("+1.000,34", locale: :de)
      {:ok, 1000.34}

      iex> Localize.Number.parse("-1_000_000.34")
      {:ok, -1000000.34}

  """
  @spec parse(String.t(), Keyword.t()) ::
          {:ok, integer() | float() | Decimal.t()}
          | {:error, Exception.t()}
  defdelegate parse(string, options \\ []), to: Localize.Number.Parser

  @doc """
  Resolves currencies from strings within a list.

  Delegates to `Localize.Number.Parser.resolve_currencies/2`.

  ### Arguments

  * `list` is a list of strings and numbers, typically the output
    of `scan/2`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is the locale
    returned by `Localize.get_locale/0`.

  * `:only` is a filter for currencies to include.

  * `:except` is a filter for currencies to exclude.

  * `:fuzzy` is a float between `0.0` and `1.0` for fuzzy matching
    via `String.jaro_distance/2`.

  ### Returns

  * A list with currency strings replaced by currency code atoms.

  ### Examples

      iex> Localize.Number.scan("100 US dollars") |> Localize.Number.resolve_currencies()
      [100, :USD]

  """
  @spec resolve_currencies([String.t() | number()], Keyword.t()) ::
          list(atom() | String.t() | number())
  defdelegate resolve_currencies(list, options \\ []), to: Localize.Number.Parser

  @doc """
  Resolves a currency from a string.

  Delegates to `Localize.Number.Parser.resolve_currency/2`.

  ### Arguments

  * `string` is a string potentially containing a currency name
    or symbol.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is the locale
    returned by `Localize.get_locale/0`.

  * `:only` is a filter for currencies to include.

  * `:except` is a filter for currencies to exclude.

  * `:fuzzy` is a float between `0.0` and `1.0` for fuzzy matching
    via `String.jaro_distance/2`.

  ### Returns

  * A list with the currency code and any remaining string.

  * `{:error, exception}` if no currency can be resolved.

  ### Examples

      iex> Localize.Number.resolve_currency("US dollars")
      [:USD]

  """
  @spec resolve_currency(String.t(), Keyword.t()) ::
          list(atom() | String.t()) | {:error, Exception.t()}
  defdelegate resolve_currency(string, options \\ []), to: Localize.Number.Parser

  @doc """
  Resolves percent and permille symbols from strings within a list.

  Delegates to `Localize.Number.Parser.resolve_pers/2`.

  ### Arguments

  * `list` is a list of strings and numbers, typically the output
    of `scan/2`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is the locale
    returned by `Localize.get_locale/0`.

  * `:number_system` is a number system name or type.

  * `:lenient` governs how strictly grouping separators must be
    positioned. `true`, the default, requires each group to be at
    least two digits, which is ICU's lenient rule and is what keeps
    `"3 4 5"` three numbers rather than one. `false` requires each
    group to be exactly the locale's grouping size, so `fr` takes
    `"1 234 567"` and refuses `"1 23"`.

  ### Returns

  * A list with percent/permille strings replaced by `:percent`
    or `:permille` atoms.

  ### Examples

      iex> Localize.Number.scan("11%") |> Localize.Number.resolve_pers()
      [11, :percent]

  """
  @spec resolve_pers([String.t() | number()], Keyword.t()) ::
          list(atom() | String.t() | number())
  defdelegate resolve_pers(list, options \\ []), to: Localize.Number.Parser

  @doc """
  Resolves percent or permille from a string.

  Delegates to `Localize.Number.Parser.resolve_per/2`.

  ### Arguments

  * `string` is a string potentially containing percent or
    permille symbols.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is the locale
    returned by `Localize.get_locale/0`.

  * `:number_system` is a number system name or type.

  * `:lenient` governs how strictly grouping separators must be
    positioned. `true`, the default, requires each group to be at
    least two digits, which is ICU's lenient rule and is what keeps
    `"3 4 5"` three numbers rather than one. `false` requires each
    group to be exactly the locale's grouping size, so `fr` takes
    `"1 234 567"` and refuses `"1 23"`.

  ### Returns

  * A list with the symbol replaced by `:percent` or `:permille`.

  * `{:error, exception}` if no symbol is found.

  ### Examples

      iex> Localize.Number.resolve_per("11%")
      ["11", :percent]

  """
  @spec resolve_per(String.t(), Keyword.t()) ::
          list(atom() | String.t()) | {:error, Exception.t()}
  defdelegate resolve_per(string, options \\ []), to: Localize.Number.Parser

  # The NIF backend validates the locale through the same canonical
  # path as the Elixir backend (`Localize.validate_locale/1`) and hands
  # ICU the canonical BCP 47 string, so both backends resolve aliases,
  # likely subtags and `-u-` extensions identically.
  defp validated_locale_string(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      {:ok, Localize.LanguageTag.to_string(language_tag)}
    end
  end
end
