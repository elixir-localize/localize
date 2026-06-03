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
    `:engineering`, `:decimal_short`, `:decimal_long`. `:scientific`
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

  * `:minimum_significant_digits` is an integer in `1..21` specifying the minimum number of significant digits the formatted output should retain. When set, significant-digit precision overrides the format pattern's fractional-digit settings. Defaults to the value derived from the format pattern's `@@##` notation, or `nil` (no significant-digit constraint).

  * `:maximum_significant_digits` is an integer in `1..21` specifying the maximum number of significant digits to display. Values are rounded to fit using the configured `:rounding_mode`. Pairs with `:minimum_significant_digits`; when only one is set the other defaults to the corresponding ECMA-402 boundary (`1` for minimum, `21` for maximum).

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
        locale_string = locale_to_string(locale)
        Localize.Nif.number_format(number, locale_string, options)

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
        locale_string = locale_to_string(locale)
        Localize.Nif.number_format(number, locale_string, options)

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

    cond do
      is_binary(format) ->
        Formatter.Decimal.to_string(number, format, validated_options)

      is_atom(format) and format in [:decimal_short, :decimal_long, :currency_short] ->
        Formatter.Short.to_string(number, format, validated_options)

      is_atom(format) and format in [:currency_long, :currency_long_with_symbol] ->
        Formatter.Currency.to_string(number, format, validated_options)

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

  @doc """
  Same as `to_string/2` but raises on error.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options.

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
  Formats a numeric range as a localized string.

  Accepts either two numbers or an Elixir `Range`. Uses the
  locale's range pattern (e.g., `"3–5"` in English, `"3～5"` in
  Japanese) to combine two formatted numbers. When the start and
  end are equal, the locale's approximately pattern is used
  instead (e.g., `"~5"`).

  ### Arguments

  * `number_start` is the start of the range (integer, float,
    or Decimal).

  * `number_end` is the end of the range (integer, float, or
    Decimal).

  * `options` is a keyword list of options.

  Alternatively:

  * `range` is an Elixir `t:Range.t/0` (e.g., `3..5`).

  * `options` is a keyword list of options.

  ### Options

  All options accepted by `to_string/2` are supported and applied
  to both numbers. Additional options:

  * `:approximate` is a boolean. When `true`, forces use of the
    approximately pattern regardless of whether start equals end.
    The default is `false`.

  ### Returns

  * `{:ok, formatted_range}` on success.

  * `{:error, exception}` if formatting fails.

  ### Examples

      iex> Localize.Number.to_range_string(3, 5, locale: :en)
      {:ok, "3–5"}

      iex> Localize.Number.to_range_string(3..5, locale: :en)
      {:ok, "3–5"}

      iex> Localize.Number.to_range_string(5, 5, locale: :en)
      {:ok, "~5"}

  """
  @spec to_range_string(Range.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_range_string(%Range{first: first, last: last}, options) do
    to_range_string(first, last, options)
  end

  @spec to_range_string(number() | Decimal.t(), number() | Decimal.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_range_string(number_start, number_end, options \\ []) do
    {approximate, format_options} = Keyword.pop(options, :approximate, false)
    locale = Keyword.get(format_options, :locale, Localize.get_locale())
    format_options = Keyword.put_new(format_options, :locale, locale)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, number_system} <- System.number_system_from_locale(language_tag),
         {:ok, patterns} <- Format.misc_patterns_for(language_tag, number_system) do
      if approximate or number_start == number_end do
        with {:ok, formatted} <- to_string(number_start, format_options) do
          result = Localize.Substitution.substitute([formatted], patterns.approximately)
          {:ok, IO.iodata_to_binary(result)}
        end
      else
        with {:ok, formatted_start} <- to_string(number_start, format_options),
             {:ok, formatted_end} <- to_string(number_end, format_options) do
          result =
            Localize.Substitution.substitute([formatted_start, formatted_end], patterns.range)

          {:ok, IO.iodata_to_binary(result)}
        end
      end
    end
  end

  @doc """
  Same as `to_range_string/3` but raises on error.

  ### Examples

      iex> Localize.Number.to_range_string!(3, 5, locale: :en)
      "3–5"

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

  @spec to_range_string!(number() | Decimal.t(), number() | Decimal.t(), Keyword.t()) ::
          String.t()
  def to_range_string!(number_start, number_end, options \\ []) do
    case to_range_string(number_start, number_end, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats a number with the locale's "at least" pattern.

  Produces strings like `"5+"` (English) or `"5以上"` (Japanese).

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options accepted by
    `to_string/2`.

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
  Formats a number with the locale's "at most" pattern.

  Produces strings like `"≤5"` (English) or `"5以下"` (Japanese).

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options accepted by
    `to_string/2`.

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
  Formats a number with the locale's approximately pattern.

  Produces strings like `"~5"` (English) or `"約 5"` (Japanese).

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `options` is a keyword list of options accepted by
    `to_string/2`.

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

  ### Returns

  * The formatted ratio string.

  ### Raises

  * Raises an exception if the number cannot be converted.

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

  ### Returns

  * A list of strings and numbers.

  """
  defdelegate scan(string, options \\ []), to: Localize.Number.Parser

  @doc """
  Parses a string to a number in a locale-aware manner.

  Delegates to `Localize.Number.Parser.parse/2`.

  ### Arguments

  * `string` is any string.

  * `options` is a keyword list of options.

  ### Returns

  * `{:ok, number}` or `{:error, exception}`.

  """
  defdelegate parse(string, options \\ []), to: Localize.Number.Parser

  @doc """
  Resolves currencies from strings within a list.

  Delegates to `Localize.Number.Parser.resolve_currencies/2`.

  """
  defdelegate resolve_currencies(list, options \\ []), to: Localize.Number.Parser

  @doc """
  Resolves a currency from a string.

  Delegates to `Localize.Number.Parser.resolve_currency/2`.

  """
  defdelegate resolve_currency(string, options \\ []), to: Localize.Number.Parser

  @doc """
  Resolves percent and permille symbols from strings within a list.

  Delegates to `Localize.Number.Parser.resolve_pers/2`.

  """
  defdelegate resolve_pers(list, options \\ []), to: Localize.Number.Parser

  @doc """
  Resolves percent or permille from a string.

  Delegates to `Localize.Number.Parser.resolve_per/2`.

  """
  defdelegate resolve_per(string, options \\ []), to: Localize.Number.Parser

  defp locale_to_string(%Localize.LanguageTag{} = tag), do: Localize.LanguageTag.to_string(tag)
  defp locale_to_string(locale) when is_atom(locale), do: Atom.to_string(locale)
  defp locale_to_string(locale) when is_binary(locale), do: locale
  defp locale_to_string(_), do: "en"
end
