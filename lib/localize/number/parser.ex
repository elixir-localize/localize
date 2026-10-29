defmodule Localize.Number.Parser do
  @moduledoc """
  Functions for parsing numbers and currencies from strings
  in a locale-aware manner.

  The parser handles locale-specific digit transliteration,
  grouping separators, and decimal separators to convert
  localized number strings back into Elixir numeric values.

  Parsing reads with a locale's own data or not at all. When the
  locale is not installed and `:allow_runtime_locale_download` is
  `false`, formatting falls back to a parent locale's data or to
  English, but every function here returns
  `{:error, %Localize.LocaleNotFoundInCacheError{}}`, since with
  English data `en-AU` "$5" would be US dollars. Install the locale
  with `mix localize.download_locales` or allow it to be downloaded.

  """

  alias Localize.Number.{Symbol, System}

  @type per :: :percent | :permille

  # Unicode's Bidi_Control characters: ALM, LRM, RLM, the embeddings and
  # overrides, and the isolates. CLDR writes them into the signs and currency
  # formats of the right-to-left locales, so `ar-EG` puts an RLM between a
  # minus and its digits. The scanner takes any run of them before a number,
  # or between its sign and digits, as part of the number, which `parse/2`
  # then drops with the other format characters. Elsewhere they stay in the
  # text as written. Not all of `\p{Cf}`: that includes the zero-width joiner
  # that emoji sequences in the surrounding text are built with.
  @bidi_control_class "\\x{061C}\\x{200E}\\x{200F}\\x{202A}-\\x{202E}\\x{2066}-\\x{2069}"
  @bidi_controls "[" <> @bidi_control_class <> "]*"

  @number_format @bidi_controls <>
                   "([-+]" <>
                   @bidi_controls <>
                   ")?[0-9]([0-9_]|[,](?=[0-9]))*(\\.ZERO_FRACTION|\\.?[0-9_]+([eE][-+]?[0-9]+)?)?"

  # The dashes that may stand for a zero fraction, "5.–": the hyphen-minus,
  # U+2010 to U+2015 (the hyphens, figure dash, en and em dashes and the
  # horizontal bar), the minus sign and the small and fullwidth forms. The
  # scanner, the currency amount splitter and `parse/2` all read this one
  # list, so they cannot disagree about which dash is which.
  @zero_fraction_dash_characters [
    "-",
    "\u2010",
    "\u2011",
    "\u2012",
    "\u2013",
    "\u2014",
    "\u2015",
    "\u2212",
    "\uFE58",
    "\uFE63",
    "\uFF0D"
  ]
  @dash_class Enum.map_join(@zero_fraction_dash_characters, &Regex.escape/1)

  # A zero fraction for a lenient scan: one or two of those dashes, with no
  # digit after them. A strict scan puts a pattern in its place that never
  # matches.
  @zero_fraction "[" <> @dash_class <> "][" <> @dash_class <> "]?(?![0-9])"

  # TR35's loose matching for lenient parsing says to "ignore all characters in
  # [:Zs:] unless they occur between letters", and separately to normalize to
  # NFKC, "thus no-break space will map to space". Both make the whole space
  # category equivalent here, so a number typed with an ordinary keyboard space
  # parses under a locale that groups with U+202F, and one copied out of
  # formatted output — carrying U+00A0, U+2009 or U+202F — parses in any locale
  # that groups with a space.
  #
  # One departure: where the locale does not group with a space, a space
  # between digits is not ignored. There it parts two numbers, as `scan/2`
  # reads them, so `en` "1 2" is refused rather than read as 12 (user,
  # 2026-10-28; `plans/tr35-audit.md`, "Departs from TR35's sentence by the
  # user's decision"). A space at either end of a number, or beside its sign,
  # is ignored as TR35 says.
  #
  # `[:Zs:]` rather than a full NFKC fold: NFKC also maps superscripts onto
  # digits, so it would silently read "5²" as 52.
  @spaces ~r/\p{Zs}/u

  # The same passage says to ignore all format characters, "in particular, ...
  # any RLM, LRM or ALM used to control BIDI formatting". This is not a
  # hypothetical: CLDR embeds those marks in the number symbols of 19 locales —
  # `ar` writes `minusSign` as LRM followed by "-", and even `root` does — so a
  # negative number copied out of Arabic, Hebrew or Persian text carries one.
  #
  # Safe to strip wholesale here because no locale puts a format character in
  # its `group` or `decimal` symbol, which are the only symbols this function
  # matches on. The percent and per-mille signs do carry them, but those are
  # matched by `resolve_per/2` against the raw string, not through here.
  @format_characters ~r/\p{Cf}/u

  # `{Rs}` and friends in CLDR's general lenient sets name a script's currency
  # sign rather than a character, so there is nothing to fold them to.
  @compound_pattern ~r/\{.*?\}/u

  @digits_only ~r/^[0-9]+$/

  @single_space ~r/^\p{Zs}$/u

  # A number with one period, between digits, and the shape of a thousands
  # group written with a period: one to three digits, the period, three
  # digits. Digits are ASCII by the time these are matched.
  @foreign_decimal_point ~r/\A[^.]*[0-9]\.[0-9][^.]*\z/
  @period_group ~r/\A[0-9]{1,3}\.[0-9]{3}(?![0-9])/

  # A number of two runs of digits, one to three and then three, parted by
  # one mark: "73,460" or "1.599", in any script's digits, signed or not.
  @group_shape ~r/\A[^\p{Nd}]*\p{Nd}{1,3}[^\p{Nd}]\p{Nd}{3}[^\p{Nd}]*\z/u

  # A decimal point that opens or closes a number, beside a digit.
  @opening_point ~r/\A\.(?=[0-9])/
  @closing_point ~r/(?<=[0-9])\.\z/

  # A folded number as its sign before an opening parenthesis, the
  # parenthesis, a sign after it, the digits, a sign before the closing
  # parenthesis, the parenthesis and a sign after it. Every part but the
  # digits may be empty, so it matches any string.
  @signed_number ~r/\A\p{Zs}*([_+]?)\p{Zs}*(\(?)\p{Zs}*([_+]?)\p{Zs}*(.*?)\p{Zs}*([_+]?)\p{Zs}*(\)?)\p{Zs}*([_+]?)\p{Zs}*\z/us

  # Whatever follows the last digit of a number in an accounting format:
  # spaces and a closing parenthesis, all optional, so it matches any string.
  @closing_parenthesis ~r/\p{Zs}*\)?\p{Zs}*\z/u

  # Spaces at either end of a number, or beside its sign once folded: "_" is
  # the minus family's sample.
  @edge_spaces ~r/\A\p{Zs}+|\p{Zs}+\z|(?<=[_+])\p{Zs}+|\p{Zs}+(?=[_+])/u

  # A run of the Bidi_Control characters in `@bidi_controls`, at the start or
  # the end of a string.
  @leading_bidi_controls Regex.compile!("\\A[" <> @bidi_control_class <> "]+", "u")
  @trailing_bidi_controls Regex.compile!("[" <> @bidi_control_class <> "]+\\z", "u")
  @any_bidi_controls Regex.compile!("[" <> @bidi_control_class <> "]", "u")

  # The digits of a currency amount, from the first to the last, and what may
  # stand between them: spaces and the punctuation of separators, which
  # `parse/2` judges.
  @digit_run ~r/\p{Nd}(?:.*\p{Nd})?/us

  # A sign or parenthesis that opens or closes text with no digits: "(USD)"
  # and "-" are a number's decorations with no number, not currency text.
  @number_decoration ~r/\A[(+\-\x{2212}]|[)+\-\x{2212}]\z/u
  @number_core ~r/\A[\p{Nd}\p{Zs}\p{Po}\p{Pf}]*\z/u

  # A currency text's closing punctuation mark, split from the rest.
  @closing_mark_split ~r/\A(.*?)(\p{Po})\z/us

  @ends_in_digit ~r/\p{Nd}\z/u

  # The same dashes as `parse/2` sees them, one or two, once folded: the
  # minus family folds to its sample "_", and the dashes CLDR leaves out of
  # it for a locale stay as they are.
  @zero_fraction_dashes for dash <- ["_" | @zero_fraction_dash_characters],
                            count <- [2, 1],
                            do: String.duplicate(dash, count)

  # The three places in `@number_format` that `localize_format_string/3` fills
  # in with the locale: the sign class, the grouping separator and the decimal.
  @format_placeholders ~r/-\+|,|\\\./

  # Smallest group a lenient parse will accept after a separator: two, the
  # floor that keeps "3 4 5" three numbers (see "Grouping shape" below).
  @lenient_group_floor 2

  # {primary, secondary} for a locale whose pattern carries no grouping.
  @default_grouping_sizes {3, 3}

  # Maximum byte length accepted by `parse/2`. A 1 KB cap fits even
  # very long localised group/decimal-separated representations of a
  # value with hundreds of digits. Override with
  # `config :localize, :max_number_bytes, n`.
  @default_max_number_bytes 1_024

  # Maximum absolute value of a parsed Decimal exponent. CLDR-shipped
  # number formats never produce exponents this large; capping here
  # prevents downstream operations (multiplication, formatting) from
  # materialising mantissa-sized work for an attacker-controlled
  # `"1e9999999999"`. Override with
  # `config :localize, :max_decimal_exponent, n`.
  @default_max_decimal_exponent 100

  # A match distance below this is a good fit (`match_distance/2`): the
  # same language in another territory is 3 to 5, a related language 12
  # and an unrelated one 84.
  @good_fit_distance 10

  @doc """
  Scans a string in a locale-aware manner and returns a list
  of strings and numbers.

  In a locale that groups with a space, a space between digits is
  read as a grouping separator, which is what lets `"1 234,5"` be
  found as one number under `fr`. The consequence is that adjacent
  numbers separated by a space can be read as a single number when
  each run is two digits or more — a list of room numbers or the
  parts of a phone number among them. Pass `lenient: false` to
  require exact grouping sizes, which reads those as separate
  numbers again:

      iex> Localize.Number.Parser.scan("chambres 12 14 16", locale: "fr")
      ["chambres ", 121416]

      iex> Localize.Number.Parser.scan("chambres 12 14 16", locale: "fr", lenient: false)
      ["chambres ", 12, " ", 14, " ", 16]

  ### Arguments

  * `string` is any string.

  * `options` is a keyword list of options.

  ### Options

  * `:number` is one of `:integer`, `:float`, `:decimal`, or
    `nil`. The default is `nil` (auto-detect).

  * `:locale` is a locale identifier. The default is `:en`.

  * `:number_system` is a number system name or type.

  * `:lenient` governs how strictly grouping separators must be
    positioned. `true`, the default, requires each group to be at
    least two digits, which is what keeps `"3 4 5"` three numbers
    rather than one. `false` requires each
    group to be exactly the locale's grouping size, so `fr` takes
    `"1 234 567"` and refuses `"1 23"`.

  * `:grouping` set to `:sizes` checks each group against the sizes the
    locale writes rather than as `:lenient` says: the last group of the
    locale's grouping size, the others of that size or its secondary one,
    so `de` refuses `"1.23"`, which a lenient reading takes as 123, and
    `en-IN` takes both `"12,34,567"` and `"1,234,567"`. Suited to amounts of
    money, where a misread group is a wrong amount. The default is `nil`.

  * `:currency` is a currency code or a `t:Localize.Currency.t/0`. When set,
    the string is read as an amount of that currency, with the separators
    `Localize.Number.to_string/2` formats it with. Two locales separate a
    currency amount differently from a plain number, `de-AT`, which formats
    `€ 1.234,56` but writes `1 234,56` plain, and `fr-CH`, which writes a
    franc amount `1'234.56` but a plain number `1'234,56`. There the string
    is read with both, and refused should both readings be valid and give
    different numbers. `de-AT` groups the euro with a period, so `"1.234"`
    is 1234 euros. The default is `nil`, a plain number.

  * `:root_separators` set to `true` also reads the string with the root
    locale's separators, the locale-neutral `1,234.56`, for an amount of
    something CLDR has no data for, such as a digital token, which is
    commonly written that way. A string both read, as different numbers, is
    refused: `de` `"1.234"` is 1234 or 1.234. The default is `false`.

  * `:separators` names the set of decimal and grouping separators to read
    with, for a locale that has more than one. `en-ZA` writes `1 234,56` with
    its `:standard` set and `1,234.56` with its `:us` set. A locale without
    the named set reads with its standard one. The default is `:standard`.

  ### Returns

  * A list of strings and numbers.

  ### Examples

      iex> Localize.Number.Parser.scan("The prize is 23")
      ["The prize is ", 23]

      iex> Localize.Number.Parser.scan("1kg")
      [1, "kg"]

  """
  @spec scan(String.t(), Keyword.t()) ::
          list(String.t() | integer() | float() | Decimal.t())
          | {:error, Exception.t()}
  def scan(string, options \\ []) do
    with :ok <- validate_arguments(string, :string, options),
         locale = Keyword.get(options, :locale, Localize.get_locale()),
         {:ok, language_tag} <- parsing_locale(locale),
         {:ok, _number_type} <- number_type(Keyword.get(options, :number)),
         {:ok, number_system} <- digits_number_system_from(language_tag, string, options),
         {:ok, symbol} <- number_symbols(language_tag, number_system, options) do
      lenient? = Keyword.get(options, :lenient, true)

      scanner =
        @number_format
        |> localize_format_string(symbol, language_tag)
        |> group_lookahead(language_tag, number_system, symbol, lenient?)
        |> zero_fraction(lenient?)
        |> Regex.compile!([:unicode])

      normalized_string = transliterate_digits(string, number_system)

      # The pieces carry Latin digits now, so `parse/2` is told the number
      # system the scan chose rather than choosing again from those digits.
      element_options = Keyword.put(options, :number_system, number_system)

      scanner
      |> Regex.split(normalized_string, include_captures: true, trim: true)
      |> Enum.map(&parse_element(&1, element_options))
    end
  end

  # Arguments of the wrong type are answered with an error rather than
  # raised on: options that are not a keyword list, or input that is not the
  # string or list the function reads.
  defp validate_arguments(value, type, options) do
    cond do
      not Keyword.keyword?(options) ->
        {:error,
         Localize.InvalidValueError.exception(
           value: options,
           expected: "a keyword list of options"
         )}

      type == :string and not is_binary(value) ->
        {:error, Localize.InvalidValueError.exception(value: value, expected: "a string")}

      # A binary that is not UTF-8 is no string, and the scanner's Unicode
      # regular expression raises on it rather than fail to match.
      type == :string and not String.valid?(value) ->
        {:error, Localize.InvalidValueError.exception(value: value, expected: "a UTF-8 string")}

      type == :list and not is_list(value) ->
        {:error,
         Localize.InvalidValueError.exception(
           value: value,
           expected: "a list of strings and numbers"
         )}

      true ->
        :ok
    end
  end

  # `:number` names the type to parse to; `nil` detects it.
  defp number_type(type) when type in [nil, :integer, :float, :decimal], do: {:ok, type}

  defp number_type(type) do
    {:error,
     Localize.InvalidValueError.exception(
       value: type,
       expected: :number_type,
       allowed_values: [:integer, :float, :decimal]
     )}
  end

  @doc """
  Parses a string in a locale-aware manner and returns a number.

  ### Arguments

  * `string` is any string.

  * `options` is a keyword list of options.

  ### Options

  * `:number` is one of `:integer`, `:float`, `:decimal`, or
    `nil`. The default is `nil` (auto-detect).

  * `:locale` is a locale identifier. The default is `:en`.

  * `:number_system` is a number system name or type.

  * `:lenient` governs how strictly grouping separators must be
    positioned. `true`, the default, requires each group to be at
    least two digits, which is what keeps `"3 4 5"` three numbers
    rather than one. `false` requires each
    group to be exactly the locale's grouping size, so `fr` takes
    `"1 234 567"` and refuses `"1 23"`.

  * `:grouping` set to `:sizes` checks each group against the sizes the
    locale writes rather than as `:lenient` says: the last group of the
    locale's grouping size, the others of that size or its secondary one,
    so `de` refuses `"1.23"`, which a lenient reading takes as 123, and
    `en-IN` takes both `"12,34,567"` and `"1,234,567"`. Suited to amounts of
    money, where a misread group is a wrong amount. The default is `nil`.

  * `:currency` is a currency code or a `t:Localize.Currency.t/0`. When set,
    the string is read as an amount of that currency, with the separators
    `Localize.Number.to_string/2` formats it with. Two locales separate a
    currency amount differently from a plain number, `de-AT`, which formats
    `€ 1.234,56` but writes `1 234,56` plain, and `fr-CH`, which writes a
    franc amount `1'234.56` but a plain number `1'234,56`. There the string
    is read with both, and refused should both readings be valid and give
    different numbers. `de-AT` groups the euro with a period, so `"1.234"`
    is 1234 euros. The default is `nil`, a plain number.

  * `:root_separators` set to `true` also reads the string with the root
    locale's separators, the locale-neutral `1,234.56`, for an amount of
    something CLDR has no data for, such as a digital token, which is
    commonly written that way. A string both read, as different numbers, is
    refused: `de` `"1.234"` is 1234 or 1.234. The default is `false`.

  * `:separators` names the set of decimal and grouping separators to read
    with, for a locale that has more than one. `en-ZA` writes `1 234,56` with
    its `:standard` set and `1,234.56` with its `:us` set. A locale without
    the named set reads with its standard one. The default is `:standard`.

  ### Returns

  * `{:ok, number}` on success, or

  * `{:error, %Localize.LocaleNotFoundInCacheError{}}` when the locale's
    data is not installed (see the module documentation), or

  * `{:error, exception}` if parsing fails.

  ### Examples

      iex> Localize.Number.Parser.parse("-1_000_000.34")
      {:ok, -1000000.34}

  """
  @spec parse(String.t(), Keyword.t()) ::
          {:ok, integer() | float() | Decimal.t()}
          | {:error, Exception.t()}
  def parse(string, options \\ []) do
    with :ok <- validate_arguments(string, :string, options) do
      cap = max_number_bytes()

      if byte_size(string) > cap do
        {:error,
         Localize.ParseError.exception(
           reason: :input_too_large,
           detail: "number string",
           size: byte_size(string),
           limit: cap
         )}
      else
        do_parse(string, options)
      end
    end
  end

  @doc false
  def max_number_bytes do
    Application.get_env(:localize, :max_number_bytes, @default_max_number_bytes)
  end

  @doc false
  def max_decimal_exponent do
    Application.get_env(:localize, :max_decimal_exponent, @default_max_decimal_exponent)
  end

  defp do_parse(string, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, language_tag} <- parsing_locale(locale),
         {:ok, number_type} <- number_type(Keyword.get(options, :number)),
         {:ok, number_system} <- digits_number_system_from(language_tag, string, options),
         {:ok, grouping} <- grouping_mode(options),
         {:ok, symbol_sets} <- symbol_sets(language_tag, number_system, options) do
      period_separator = period_separator?(symbol_sets)

      readings =
        Enum.map(symbol_sets, fn {reading_tag, symbols} ->
          read_number(
            string,
            number_type,
            number_system,
            symbols,
            {reading_tag, period_separator},
            grouping
          )
        end)

      agreed_reading(readings, string)
    end
  end

  # The symbols a number is read with. An amount of a currency is read with
  # the separators the currency is formatted with and, in the two locales
  # that write plain numbers otherwise (`de-AT`, `fr-CH`), with those too: a
  # price may be typed either way.
  #
  # With `root_separators: true` it is read with the root locale's as well,
  # the locale-neutral form `1,234.56`, for an amount of something CLDR has no
  # data for, such as a digital token, which is commonly written that way.
  #
  # Each set comes with the locale whose grouping sizes and folds it is read
  # with.
  defp symbol_sets(language_tag, number_system, options) do
    with {:ok, symbols} <- number_symbols(language_tag, number_system, options),
         {:ok, sets} <- with_plain_symbols([{language_tag, symbols}], number_system, options) do
      with_root_symbols(sets, number_system, options)
    end
  end

  defp with_plain_symbols(sets, number_system, options) do
    if is_nil(options[:currency]) do
      {:ok, sets}
    else
      [{language_tag, _currency_symbols}] = sets
      plain_options = Keyword.delete(options, :currency)

      with {:ok, plain} <- number_symbols(language_tag, number_system, plain_options) do
        {:ok, add_symbol_set(sets, {language_tag, plain})}
      end
    end
  end

  defp with_root_symbols(sets, number_system, options) do
    if options[:root_separators] == true do
      plain_options = Keyword.drop(options, [:currency, :separators])

      with {:ok, root} <- Localize.validate_locale(:und),
           {:ok, symbols} <- number_symbols(root, number_system, plain_options) do
        {:ok, add_symbol_set(sets, {root, symbols})}
      end
    else
      {:ok, sets}
    end
  end

  # A set whose separators another already has adds no reading of its own.
  defp add_symbol_set(sets, {_tag, symbols} = set) do
    if Enum.any?(sets, fn {_other_tag, other} -> same_separators?(other, symbols) end) do
      sets
    else
      sets ++ [set]
    end
  end

  defp same_separators?(this, that) do
    this.group == that.group and this.decimal == that.decimal
  end

  # A number is the one every valid reading gives. Where two readings are
  # valid and differ, the text is ambiguous and refused rather than one
  # guessed: with `root_separators: true`, `de` "1.234" is 1234 with the
  # locale's separators and 1.234 with the root locale's.
  defp agreed_reading(readings, string) do
    values = for {:ok, value} <- readings, do: value

    case values do
      [] -> hd(readings)
      [value | others] -> same_reading(value, others, string)
    end
  end

  defp same_reading(value, others, string) do
    case Enum.reject(others, &same_value?(&1, value)) do
      [] -> {:ok, value}
      [other | _] -> {:error, ambiguous_number(string, value, other)}
    end
  end

  defp same_value?(%Decimal{} = this, %Decimal{} = that) do
    Decimal.equal?(this, that)
  end

  defp same_value?(this, that) do
    this == that
  end

  defp ambiguous_number(string, value, other) do
    Localize.ParseError.exception(
      input: string,
      reason: :unexpected_input,
      detail: "it is ambiguous, #{number_text(value)} or #{number_text(other)}"
    )
  end

  defp number_text(%Decimal{} = decimal) do
    Decimal.to_string(decimal, :normal)
  end

  defp number_text(number) do
    to_string(number)
  end

  # How a grouping separator's position is checked: `:sizes` when asked for,
  # otherwise as `:lenient` says.
  defp grouping_mode(options) do
    case Keyword.get(options, :grouping) do
      nil -> {:ok, lenient_grouping(Keyword.get(options, :lenient, true))}
      :sizes -> {:ok, :sizes}
      other -> {:error, Localize.Utils.Helpers.invalid_value(other, ":sizes")}
    end
  end

  defp lenient_grouping(false) do
    :strict
  end

  defp lenient_grouping(_lenient) do
    :lenient
  end

  # Text that is not a number of this locale is a parse error naming the
  # text, not whichever step of the reading first refused it.
  # A period that is a separator of any set the number is read with is not
  # foreign to the locale: `de-AT` groups the euro with it, so its plain-number
  # set, which does not, must not take "1.23 EUR" for 1.23.
  defp period_separator?(symbol_sets) do
    Enum.any?(symbol_sets, fn {reading_tag, symbols} ->
      lenient = lenient_replacements(reading_tag)

      Enum.any?([symbols.decimal, symbols.group], fn separator ->
        separator
        |> extract_separator()
        |> apply_lenient(lenient)
        |> Kernel.==(".")
      end)
    end)
  end

  defp read_number(string, number_type, number_system, symbol, reading, grouping) do
    case normalized_value(string, number_type, number_system, symbol, reading, grouping) do
      {:ok, _value} = success -> bound_decimal_exponent(success, string)
      _unreadable -> {:error, parse_error(string)}
    end
  end

  defp normalized_value(string, number_type, number_system, symbol, reading, grouping) do
    {language_tag, period_separator} = reading

    with {:ok, normalized} <-
           string
           |> transliterate_digits(number_system)
           |> normalize_number_string(
             symbol,
             language_tag,
             number_system,
             grouping,
             period_separator
           ) do
      normalized |> String.trim() |> parse_number(number_type)
    end
  end

  # If the parsed value is a `Decimal` with an exponent magnitude that
  # would make downstream operations expensive, reject the parse
  # rather than return a value that will misbehave under multiplication
  # or formatting. Integers and floats are bounded by their own range
  # checks and do not need this guard.
  defp bound_decimal_exponent({:ok, %Decimal{exp: exp}} = ok, _string)
       when is_integer(exp) do
    if abs(exp) > max_decimal_exponent() do
      {:error, parse_error("Decimal exponent #{exp} exceeds limit of ±#{max_decimal_exponent()}")}
    else
      ok
    end
  end

  defp bound_decimal_exponent(other, _string), do: other

  @doc """
  Resolves currencies from strings within a list.

  ### Arguments

  * `list` is a list of strings and numbers.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `:en`.

  * `:only` is a filter for currencies to include.

  * `:except` is a filter for currencies to exclude.

  * `:fuzzy` is a float for fuzzy matching via `String.jaro_distance/2`.
    Of equally close currency strings, the alphabetically first is taken.

  ### Returns

  * A list with currency strings replaced by currency code atoms.

  ### Examples

      iex> Localize.Number.Parser.scan("100 US dollars")
      ...> |> Localize.Number.Parser.resolve_currencies()
      [100, :USD]

  """
  @spec resolve_currencies([String.t() | number()], Keyword.t()) ::
          list(atom() | String.t() | number()) | {:error, Exception.t()}
  def resolve_currencies(list, options \\ []) do
    with :ok <- validate_arguments(list, :list, options) do
      resolve(list, &resolve_currency/2, options)
    end
  end

  @doc """
  Resolves a currency from the beginning and/or end of a string.

  A string several of the locale's currencies share names the currency
  of the territory whose CLDR locale is nearest the locale, when that
  locale is a good fit and no other claimant's is as near: "$" is the
  Canadian dollar in `fr`, as in `fr-CA`. Otherwise it stays unknown.

  ### Arguments

  * `string` is a string potentially containing a currency name or symbol.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `:en`.

  * `:only` is a filter for currencies to include.

  * `:except` is a filter for currencies to exclude.

  * `:fuzzy` is a float for fuzzy matching. Of equally close
    currency strings, the alphabetically first is taken.

  ### Returns

  * A list with the currency code and remainder, or
    `{:error, exception}`.

  ### Examples

      iex> Localize.Number.Parser.resolve_currency("US dollars")
      [:USD]

      iex> Localize.Number.Parser.resolve_currency("$100")
      [:USD, "100"]

  """
  @spec resolve_currency(String.t(), Keyword.t()) ::
          list(atom() | String.t()) | {:error, Exception.t()}
  def resolve_currency(string, options \\ []) do
    with :ok <- validate_arguments(string, :string, options) do
      find_currency(string, options, :nearest)
    end
  end

  @doc """
  Parses a string that holds one currency amount into its currency and
  its amount.

  The currency, a code, symbol or name, may come before or after the
  amount, with or without a space between them. A sign may stand
  before the currency, between the currency and the amount, or after
  the amount, or the parentheses of an accounting format may hold it,
  but not both. The amount is read with the separators the locale uses
  for that currency, so `fr-CH` "1’234.56 CHF" reads as it is written,
  and in `de-AT` and `fr-CH`, which write plain numbers otherwise, with
  those too. Its groups must be the sizes the locale writes
  (`grouping: :sizes` of `parse/2`), and a period that is none of its
  separators is read only where it can be nothing but a decimal point.
  Where the text could be two amounts it is
  refused rather than one guessed: `de` "1.23 EUR" is not €123, `fr`
  "1.234 €" is not €1.234, "($-5)" is neither -5 nor 5 dollars,
  "-$.50" is refused since Swiss "Fr. –.15" writes a dash for the zero,
  and `fr` "$2.00" is refused since several dollars share "$" there,
  where `resolve_currency/2` takes the Canadian one. A narrow symbol of
  another currency than the locale's own is read only when it is a
  currency sign that names that currency alone, in the locale and in
  CLDR's root data, so `en-AU` "€5" is the euro and `de-CH` "€ 15.40"
  too, though `de-CH` writes the euro "EUR", but Swiss "15 Rp." (15
  Rappen) is not the rupiah, whose narrow symbol `de-CH` gives as "Rp",
  and `bg` "₩5" is refused, since root gives "₩" to both wons.
  A historic currency is read only by its code or its name, since its
  symbols are reused: `ru` "6 300 Р" is not the ruble of 1991–1998. One
  to three digits, a decimal mark and three more are refused in a
  currency of fewer than three decimal places, since they may be a
  thousands group: `de` "1,599 €" and `en` "$59.568". The currency text,
  but not the number, is matched after NFKC normalization, so `ja`
  "¥1.00" is the yen, which `ja` writes "￥", while "$5²" is refused.
  Bidi controls are ignored. Nothing else may surround the amount.

  ex_money's `Money.parse/2` is built on this function, and its
  [parsing guide](https://hexdocs.pm/ex_money/parsing.html) describes
  what is read and what is refused, with examples.

  ### Arguments

  * `string` is the string to parse.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale/0`.

  * `:number_system` and `:separators` are as for `parse/2`.

  * `:only`, `:except` and `:fuzzy` are as for `resolve_currency/2`,
    except that a fuzzy match is refused where another currency's
    string is as close: `fr` "100 dollars" is neither the Fiji nor the
    Rhodesian dollar.

  * `:default_currency` is the currency of an amount that names none:
    a currency code, or a name or symbol, resolved as currency text
    in the string would be. Without it, such an amount is an error.

  * `:caller_currency` is a function of one argument, called with the
    currency text, for currencies of the caller's own such as digital
    tokens. It returns `{:ok, currency}` when the text names one, or
    anything else. Text that names no currency of the locale is read as
    the caller's currency; text that names one of the locale's and a
    different one of the caller's is ambiguous and refused, as `₮` is the
    tugrik and a digital token's symbol, except where it names the
    locale's own currency: `mn` "₮5" is the tugrik. Pass it only when
    the caller has such currencies, since it is called for every amount.
    Their amounts are read with the locale's separators and the root
    locale's (`root_separators: true` of `parse/2`), and refused where
    the two differ.

  ### Returns

  * `{:ok, {currency, amount}}` where `currency` is a currency code, or
    what `:caller_currency` returned, and `amount` is a `t:Decimal.t/0`,
    or

  * `{:error, %Localize.UnknownCurrencyError{currency: text}}` when the
    currency text names no currency, or

  * `{:error, %Localize.ParseError{reason: :missing_currency}}` when the
    string names no currency and there is no `:default_currency`, or

  * `{:error, %Localize.InvalidAmountError{currency: currency, amount: text}}`
    when the string names a currency but has no number, or one that
    cannot be read with the locale's separators for it, or

  * `{:error, %Localize.ParseError{reason: :unexpected_input}}` when the
    string is not one currency amount, or

  * `{:error, %Localize.LocaleNotFoundInCacheError{}}` when the locale's
    data is not installed (see the module documentation), or

  * `{:error, exception}` for an invalid locale or option.

  ### Examples

      iex> Localize.Number.Parser.parse_currency_amount("USD 100", locale: :en)
      {:ok, {:USD, Decimal.new("100")}}

      iex> Localize.Number.Parser.parse_currency_amount("(1 234,56 €)", locale: :fr)
      {:ok, {:EUR, Decimal.new("-1234.56")}}

      iex> Localize.Number.Parser.parse_currency_amount("kr-127,54", locale: :da)
      {:ok, {:DKK, Decimal.new("-127.54")}}

  """
  @spec parse_currency_amount(String.t(), Keyword.t()) ::
          {:ok, {Localize.Currency.currency_code() | term(), Decimal.t()}}
          | {:error, Exception.t()}
  def parse_currency_amount(string, options \\ []) do
    with :ok <- validate_arguments(string, :string, options),
         :ok <- validate_amount_size(string),
         locale = Keyword.get(options, :locale, Localize.get_locale()),
         {:ok, language_tag} <- parsing_locale(locale),
         options = Keyword.put(options, :locale, language_tag),
         {:ok, parts} <- amount_parts(string, language_tag),
         {:ok, currency, separators_of, parts} <- amount_currency(parts, string, options),
         {:ok, number} <- amount_number(parts, currency, separators_of, options) do
      {:ok, {currency, number}}
    end
  end

  # `reading` is `:nearest` for `resolve_currency/2`, where a string several
  # currencies share names the nearest locale's currency. It is `:amount` for
  # a currency amount, where such a string names none, since an amount in the
  # wrong currency is wrong money, and where the text and the locale's strings
  # are matched after NFKC normalization, as TR35's loose matching asks: `ja`
  # writes the yen "￥", which "¥" then matches. Only currency text is
  # normalized, never a number, where NFKC would make the footnote of "$5²" a
  # digit.
  defp find_currency(string, options, reading) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    only_filter = Keyword.get(options, :only, [:all])
    except_filter = Keyword.get(options, :except, [])
    fuzzy = Keyword.get(options, :fuzzy, nil)

    filters = [only: only_filter, except: except_filter]

    with {:ok, language_tag} <- parsing_locale(locale),
         {:ok, currency_strings} <- reading_strings(language_tag, filters, reading),
         {:ok, currency} <-
           found_currency(
             currency_strings,
             reading_text(string, reading),
             fuzzy,
             language_tag,
             filters,
             reading
           ) do
      currency
    end
  end

  # Only finding no currency means the currency is unknown. An invalid
  # `:fuzzy` value is reported as itself.
  defp found_currency(currency_strings, string, fuzzy, language_tag, filters, reading) do
    case find_or_resolve_currency(
           currency_strings,
           string,
           fuzzy,
           language_tag,
           filters,
           reading
         ) do
      {:ok, _currency} = found ->
        found

      {:error, %Localize.InvalidValueError{context: "Localize.Number.Parser"}} ->
        {:error, Localize.UnknownCurrencyError.exception(currency: string)}

      {:error, _exception} = error ->
        error
    end
  end

  defp reading_strings(language_tag, filters, :nearest) do
    Localize.Currency.currency_strings(locale_id(language_tag), filters)
  end

  # The unfiltered index is built once per locale and currency of the locale;
  # a filtered one is built for each call, and so is its amount form.
  defp reading_strings(language_tag, [only: only, except: except] = filters, :amount)
       when only in [:all, [:all]] and except in [nil, []] do
    own = own_currency(language_tag)
    key = {__MODULE__, :amount_currency_strings, locale_id(language_tag), own}

    case :persistent_term.get(key, nil) do
      nil -> cache_amount_strings(key, language_tag, own, filters)
      strings -> {:ok, strings}
    end
  end

  defp reading_strings(language_tag, filters, :amount) do
    amount_strings(language_tag, own_currency(language_tag), filters)
  end

  defp cache_amount_strings(key, language_tag, own, filters) do
    with {:ok, strings} <- amount_strings(language_tag, own, filters) do
      Localize.LiteralMemory.cache(key, strings)
      {:ok, strings}
    end
  end

  # A currency amount reads a narrow symbol of another currency than the
  # locale's own only when it is a currency sign that names that currency
  # alone: CLDR writes a narrow symbol where the context makes the currency
  # clear, and elsewhere a letter abbreviation may be another thing. `de-CH`
  # gives the rupiah the narrow symbol "Rp", but a Swiss "15 Rp." is 15
  # Rappen, while `en-AU` "€5" is the euro.
  # A historic currency is read only by its code or its name, since its
  # symbols are reused: a Russian "6 300 Р" is not the ruble of 1991–1998.
  defp amount_strings(language_tag, own, filters) do
    locale_id = locale_id(language_tag)

    with {:ok, strings} <- Localize.Currency.currency_strings(locale_id, filters),
         {:ok, narrow} <- Localize.Currency.narrow_symbol_strings(locale_id, filters),
         {:ok, signs} <- Localize.Currency.currency_sign_strings(locale_id, filters),
         {:ok, unclaimed} <- Localize.Currency.unclaimed_sign_strings(locale_id, filters),
         {:ok, historic} <- Localize.Currency.historic_symbol_strings(locale_id, filters) do
      foreign =
        for {string, code} <- narrow,
            code != own,
            not Map.has_key?(signs, string),
            do: string

      dropped = foreign ++ Map.keys(historic)

      amount_strings =
        strings
        |> Map.drop(dropped)
        |> Map.merge(unclaimed)
        |> nfkc_strings()

      {:ok, amount_strings}
    end
  end

  defp own_currency(language_tag) do
    case Localize.Currency.currency_from_locale(language_tag) do
      {:ok, currency} -> currency
      {:error, _no_currency} -> nil
    end
  end

  # Two strings that normalize alike but name different currencies name
  # neither, as a string two currencies share names neither.
  defp nfkc_strings(strings) do
    strings
    |> Enum.group_by(fn {string, _code} -> nfkc(string) end, fn {_string, code} -> code end)
    |> Enum.flat_map(fn {string, codes} -> single_claimant(string, Enum.uniq(codes)) end)
    |> Map.new()
  end

  defp single_claimant(string, [code]) do
    [{string, code}]
  end

  defp single_claimant(_string, _codes) do
    []
  end

  defp reading_text(string, :nearest) do
    string
  end

  defp reading_text(string, :amount) do
    nfkc(string)
  end

  # Text that is not valid Unicode is matched as it is, and found in no index.
  defp nfkc(string) do
    case :unicode.characters_to_nfkc_binary(string) do
      normalized when is_binary(normalized) -> String.downcase(normalized)
      _invalid -> string
    end
  end

  # A string several of the locale's currencies share ("$" in `fr`) names
  # the currency used where the locale closest to this one is spoken: of
  # the CLDR locales of each claimant's territories, the one
  # `Localize.LanguageTag.match_distance/2` puts nearest, if it is a good
  # fit and no locale of another claimant is as near. So "$" is the
  # Canadian dollar in `fr`, as it is in `fr-CA`, and stays unknown in
  # `es`, which Mexico, the United States and Argentina are as near.
  defp find_or_resolve_currency(currency_strings, string, fuzzy, language_tag, filters, reading) do
    case find_and_replace_currency(currency_strings, string, fuzzy, language_tag) do
      {:ok, _found} = found when reading == :amount and is_float(fuzzy) ->
        closest_alone(found, currency_strings, string)

      {:ok, _found} = found ->
        found

      {:error, _not_found} = error when reading == :nearest ->
        resolved_claimants(string, fuzzy, language_tag, filters, error)

      {:error, _not_found} = error ->
        error
    end
  end

  # A fuzzy match names an amount's currency only when no other currency's
  # string is as close: `fr` "dollars" is as close to "dollar rhodésien" as
  # to "dollars fidjiens", and an amount is not read in either by the order
  # of their names, which is how `resolve_currency/2` breaks the tie.
  defp closest_alone(found, currency_strings, string) do
    search = String.downcase(string)

    distances =
      Enum.map(currency_strings, fn {candidate, code} ->
        {String.jaro_distance(candidate, search), code}
      end)

    {closest, _code} = Enum.max_by(distances, &elem(&1, 0))
    codes = for {distance, code} <- distances, distance == closest, uniq: true, do: code

    case codes do
      [_one] ->
        found

      [_ | _] ->
        {:error, parse_error("The closest currencies are equally close: #{inspect(codes)}")}
    end
  end

  # The error stands where the string is not one the locale's currencies
  # share, or where its claimants cannot be told apart.
  defp resolved_claimants(string, fuzzy, language_tag, filters, error) do
    case Localize.Currency.ambiguous_currency_strings(locale_id(language_tag), filters) do
      {:ok, ambiguous} -> claimants_in(ambiguous, string, fuzzy, language_tag, error)
      {:error, _no_shared_strings} -> error
    end
  end

  defp claimants_in(ambiguous, string, fuzzy, language_tag, error) do
    case find_and_replace_currency(ambiguous, string, fuzzy, language_tag) do
      {:ok, found} when is_list(found) -> nearest_claimants(found, language_tag, error)
      _not_a_shared_string -> error
    end
  end

  defp nearest_claimants(found, language_tag, error) do
    case resolve_claimants(found, language_tag) do
      {:ok, resolved} -> {:ok, resolved}
      :error -> error
    end
  end

  defp resolve_claimants(found, language_tag) do
    Enum.reduce_while(found, {:ok, []}, fn
      codes, {:ok, acc} when is_list(codes) ->
        case closest_currency(codes, language_tag) do
          {:ok, code} -> {:cont, {:ok, acc ++ [code]}}
          :error -> {:halt, :error}
        end

      other, {:ok, acc} ->
        {:cont, {:ok, acc ++ [other]}}
    end)
  end

  defp closest_currency(codes, language_tag) do
    scored =
      for code <- codes,
          locale_id <- home_locale_ids(code),
          distance <- [
            Localize.LanguageTag.match_distance(language_tag, Atom.to_string(locale_id))
          ],
          is_number(distance) and distance < @good_fit_distance,
          do: {distance, code}

    nearest_code(scored)
  end

  # `:error` where nothing is a good fit, and where two codes are equally
  # near: a tie names no currency.
  defp nearest_code([]), do: :error

  defp nearest_code(scored) do
    nearest = scored |> Enum.map(&elem(&1, 0)) |> Enum.min()

    case for({^nearest, code} <- scored, uniq: true, do: code) do
      [code] -> {:ok, code}
      _tied -> :error
    end
  end

  # The CLDR locales of the territories whose current currency `code` is.
  defp home_locale_ids(code) do
    locales_by_territory = locales_by_territory()

    for {territory, locale_ids} <- locales_by_territory,
        Localize.Currency.current_currency_for_territory(territory) == code,
        locale_id <- locale_ids,
        do: locale_id
  end

  # Every CLDR locale by its territory, given or likely (`fr-CA` is
  # Canada's, `fr` France's), built once.
  defp locales_by_territory do
    key = {__MODULE__, :locales_by_territory}

    case :persistent_term.get(key, nil) do
      nil ->
        map =
          Enum.group_by(
            for(
              locale_id <- Localize.all_locale_ids(),
              {:ok, territory} <- [Localize.Territory.territory_from_locale(locale_id)],
              do: {territory, locale_id}
            ),
            &elem(&1, 0),
            &elem(&1, 1)
          )

        Localize.LiteralMemory.cache(key, map)
        map

      map ->
        map
    end
  end

  @doc """
  Resolves percent and permille symbols from strings within a list.

  ### Arguments

  * `list` is a list of strings and numbers.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`. The default is
    `Localize.get_locale()`.

  * `:number_system` is a number system name or type atom.
    The default is the number system of `:locale`.

  ### Returns

  * A list with percent/permille strings replaced by `:percent`
    or `:permille` atoms.

  ### Examples

      iex> Localize.Number.Parser.scan("100%")
      ...> |> Localize.Number.Parser.resolve_pers()
      [100, :percent]

  """
  @spec resolve_pers([String.t() | number()], Keyword.t()) ::
          list(per() | String.t() | number()) | {:error, Exception.t()}
  def resolve_pers(list, options \\ []) do
    with :ok <- validate_arguments(list, :list, options) do
      resolve(list, &resolve_per/2, options)
    end
  end

  @doc """
  Resolves percent or permille from a string.

  ### Arguments

  * `string` is a string potentially containing percent
    or permille symbols.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`. The default is
    `Localize.get_locale()`.

  * `:number_system` is a number system name or type atom.
    The default is the number system of `:locale`.

  ### Returns

  * A list with the symbol replaced by `:percent` or `:permille`.

  * `{:error, exception}` if no symbol found.

  ### Examples

      iex> Localize.Number.Parser.resolve_per("11%")
      ["11", :percent]

  """
  @spec resolve_per(String.t(), Keyword.t()) ::
          list(per() | String.t()) | {:error, Exception.t()}
  def resolve_per(string, options \\ []) do
    with :ok <- validate_arguments(string, :string, options),
         locale = Keyword.get(options, :locale, Localize.get_locale()),
         {:ok, language_tag} <- parsing_locale(locale),
         {:ok, number_system} <- digits_number_system_from(language_tag, string, options),
         {:ok, symbol} <- number_symbols(language_tag, number_system, []) do
      per_strings =
        build_per_strings(symbol)

      case find_and_replace(per_strings, string, nil) do
        {:ok, result} -> result
        {:error, _} -> {:error, parse_error("No percent or permille found")}
      end
    end
  end

  @doc """
  Maps a list applying a resolver function to each binary element.

  ### Arguments

  * `list` is a list of terms.

  * `resolver` is a function that takes a string and options.

  * `options` is a keyword list passed to the resolver.

  ### Options

  * The options are passed through unchanged to `resolver` for each
    binary element. See the resolver function (for example
    `resolve_currency/2` or `resolve_per/2`) for the options it
    supports.

  ### Returns

  * The list with binary elements resolved.

  ### Examples

      iex> resolver = &Localize.Number.Parser.resolve_currency/2
      iex> Localize.Number.Parser.resolve(["100", "USD"], resolver, locale: :en)
      ["100", :USD]

  """
  @spec resolve(list(), (String.t(), Keyword.t() -> term()), Keyword.t()) ::
          list() | {:error, Exception.t()}
  def resolve(list, resolver, options) when is_list(list) and is_function(resolver, 2) do
    Enum.map(list, fn
      string when is_binary(string) ->
        case resolver.(string, options) do
          {:error, _} -> string
          other -> other
        end

      other ->
        other
    end)
    |> List.flatten()
  end

  def resolve(list, resolver, _options) when is_list(list),
    do: {:error, Localize.Utils.Helpers.invalid_value(resolver, "a function of arity 2")}

  def resolve(list, _resolver, _options),
    do: {:error, Localize.Utils.Helpers.invalid_value(list, "a list")}

  @doc """
  Finds and replaces substrings from a map at the beginning
  and/or end of a string.

  ### Arguments

  * `string_map` is a map of `%{search_string => replacement}`.

  * `string` is the string to search.

  * `fuzzy` is an optional float for fuzzy matching. Of equally
    close strings, the alphabetically first is taken.

  ### Returns

  * `{:ok, list}` with replacements applied.

  * `{:error, exception}` if no match found.

  ### Examples

      iex> Localize.Number.Parser.find_and_replace(%{"usd" => :USD}, "USD 100")
      {:ok, [:USD, " 100"]}

      iex> Localize.Number.Parser.find_and_replace(%{"%" => :percent}, "11%")
      {:ok, ["11", :percent]}

  """
  @spec find_and_replace(map(), String.t(), float() | nil) ::
          {:ok, list()} | {:error, Exception.t()}
  def find_and_replace(string_map, string, fuzzy \\ nil)

  def find_and_replace(string_map, string, fuzzy) when is_map(string_map) and is_binary(string) do
    replace_strings(string_map, string, fuzzy, MapSet.new())
  end

  def find_and_replace(string_map, _string, _fuzzy) when not is_map(string_map),
    do:
      {:error,
       Localize.Utils.Helpers.invalid_value(string_map, "a map of strings to replacements")}

  def find_and_replace(_string_map, string, _fuzzy),
    do: {:error, Localize.Utils.Helpers.invalid_value(string, "a string")}

  # ── Private helpers ──────────────────────────────────────────

  # ── Currency amounts ─────────────────────────────────────────

  defp validate_amount_size(string) do
    limit = max_number_bytes()

    if byte_size(string) > limit do
      {:error,
       Localize.ParseError.exception(
         reason: :input_too_large,
         detail: "currency amount",
         size: byte_size(string),
         limit: limit
       )}
    else
      :ok
    end
  end

  # Splits an amount into its currency text and the text of its number,
  # which is everything else: the digits from the first to the last, with
  # the signs, parentheses, spaces and marks around them, all of which
  # `parse/2` reads. The currency text stands before the number or after
  # it, inside those.
  defp amount_parts(string, language_tag) do
    text = String.replace(string, @any_bidi_controls, "")

    case Regex.run(@digit_run, text, return: :index) do
      [{start, length}] ->
        before = binary_part(text, 0, start)
        digits = binary_part(text, start, length)
        rest = binary_part(text, start + length, byte_size(text) - start - length)
        split_amount(before, digits, rest, language_tag, string)

      nil ->
        currency_without_number(text, string)
    end
  end

  # Text with no digits is currency text with no number: "" names no
  # currency, as "100" names none, and "USD" names one whose amount cannot
  # be read, as "USD abc" does. A form's empty field is so reported as a
  # missing amount rather than as text that is not money. Text a sign or a
  # parenthesis opens or closes, "(USD)", is not an amount.
  defp currency_without_number(text, string) do
    currency = String.trim(text)

    if String.match?(currency, @number_decoration) do
      {:error, not_an_amount(string)}
    else
      {:ok, %{currency: currency, mark: "", lead: "", rest: ""}}
    end
  end

  defp split_amount(before, digits, rest, language_tag, string) do
    {prefix_pattern, suffix_pattern} = amount_patterns(language_tag)
    {lead, prefix, between, mark} = prefix_parts(prefix_pattern, before)
    {after_digits, suffix, trailing} = decorations(suffix_pattern, rest)

    if String.match?(digits, @number_core) and (prefix == "" or suffix == "") do
      {:ok,
       %{
         currency: prefix <> suffix,
         mark: mark,
         lead: lead,
         rest: between <> digits <> after_digits <> trailing
       }}
    else
      {:error, not_an_amount(string)}
    end
  end

  # The text before the digits as its leading decorations, the currency
  # text, the decorations between it and the digits, and a mark the
  # currency text ends in where nothing stands between it and the digits.
  # A mark after a space, a sign or "(" is the number's, as in "USD .5".
  defp prefix_parts(pattern, before) do
    {lead, prefix, between} = decorations(pattern, before)

    case Regex.run(@closing_mark_split, prefix) do
      [_prefix, unmarked, mark] when between == "" ->
        prefix_mark(pattern, lead, prefix, unmarked, mark)

      _no_touching_mark ->
        {lead, prefix, between, ""}
    end
  end

  defp prefix_mark(pattern, lead, prefix, unmarked, mark) do
    case decorations(pattern, unmarked) do
      {_lead, currency, ""} when currency != "" -> {lead, prefix, "", mark}
      {_lead, currency, spacing} -> {lead, currency, spacing <> mark, ""}
    end
  end

  # `text` as its leading decorations, the text between them and its
  # trailing decorations.
  defp decorations(pattern, text) do
    case Regex.run(pattern, text) do
      [_text, leading, middle, trailing] -> {leading, middle, trailing}
      _no_decorations -> {"", text, ""}
    end
  end

  # The decorations around a currency text: spaces, the locale's signs and
  # parentheses, and after the digits the marks that may close a number, as
  # in "5.USD" and "5.– CHF".
  defp amount_patterns(language_tag) do
    cached({:amount_patterns, language_tag.cldr_locale_id}, fn ->
      signs = sign_characters(lenient_sets(language_tag))
      decoration = "\\p{Zs}\\t()" <> class_characters(signs)
      closing = decoration <> "\\p{Po}\\p{Pf}" <> @dash_class

      {
        Regex.compile!("\\A([" <> decoration <> "]*)(.*?)([" <> decoration <> "]*)\\z", "us"),
        Regex.compile!("\\A([" <> closing <> "]*)(.*?)([" <> decoration <> "]*)\\z", "us")
      }
    end)
  end

  # The currency an amount names, and the currency whose separators its
  # number is read with: none for one the caller's `:caller_currency`
  # function named, which Localize has no separators for.
  defp amount_currency(%{currency: ""} = parts, string, options) do
    default = Keyword.get(options, :default_currency)

    if is_nil(default) do
      {:error, Localize.ParseError.exception(input: string, reason: :missing_currency)}
    else
      default
      |> default_currency(options)
      |> with_parts(parts)
    end
  end

  defp amount_currency(%{currency: text, mark: ""} = parts, _string, options) do
    text
    |> text_currency(options)
    |> with_parts(parts)
  end

  # A mark between the currency and the digits, as in "$.50" or "kr.5". It
  # is the currency's when CLDR writes the currency with it (`da` "kr.",
  # `de-CH` "Fr."), and the number's when it is the currency's decimal mark
  # in the locale, so "$.50" is fifty cents, not fifty dollars. Anything
  # else is ambiguous and refused: `nb` writes the krone "kr" and its decimal
  # with a comma, so "kr.5" could be 5 or 0.5.
  defp amount_currency(%{currency: text, mark: mark} = parts, string, options) do
    if written_with_mark?(text, options) do
      text
      |> text_currency(options)
      |> with_parts(parts)
    else
      unmarked = String.replace_suffix(text, mark, "")

      case text_currency(unmarked, options) do
        {:ok, currency, separators_of} ->
          marked_number(parts, unmarked, currency, separators_of, string, options)

        {:error, _not_a_currency} ->
          text
          |> text_currency(options)
          |> with_parts(parts)
      end
    end
  end

  defp with_parts({:ok, currency, separators_of}, parts) do
    {:ok, currency, separators_of, parts}
  end

  defp with_parts({:error, _reason} = error, _parts) do
    error
  end

  # Matched exactly, never fuzzily, since a fuzzy match would take "$." for
  # a currency of its own.
  defp written_with_mark?(text, options) do
    filters = Keyword.take(options, [:locale, :only, :except])
    match?([currency] when is_atom(currency), amount_currency_text(text, filters))
  end

  defp marked_number(parts, unmarked, currency, separators_of, string, options) do
    %{mark: mark, lead: lead, rest: rest} = parts

    if decimal_mark?(mark, rest, separators_of, options) do
      {:ok, currency, separators_of, %{parts | currency: unmarked, lead: lead <> mark}}
    else
      {:error, not_an_amount(string)}
    end
  end

  defp decimal_mark?(mark, number, separators_of, options) do
    language_tag = Keyword.fetch!(options, :locale)

    symbol_options =
      options
      |> Keyword.take([:separators])
      |> put_separators_currency(separators_of)

    case mark_symbols(language_tag, number, options, symbol_options) do
      {:ok, symbol_sets} ->
        lenient = lenient_replacements(language_tag)
        folded_mark = apply_lenient(mark, lenient)

        Enum.any?(symbol_sets, fn {_tag, symbols} ->
          apply_lenient(extract_separator(symbols.decimal), lenient) == folded_mark
        end)

      {:error, _no_symbols} ->
        false
    end
  end

  # Every set the number is read with, so a mark is the number's when it is
  # the decimal mark of any of them, as `fr-CH` "CHF,5" is.
  defp mark_symbols(language_tag, number, options, symbol_options) do
    with {:ok, number_system} <- digits_number_system_from(language_tag, number, options) do
      symbol_sets(language_tag, number_system, symbol_options)
    end
  end

  defp default_currency(default, options) when is_atom(default) do
    text_currency(Atom.to_string(default), options)
  end

  defp default_currency(default, options) when is_binary(default) do
    text_currency(default, options)
  end

  defp default_currency(default, _options) do
    {:error, Localize.Utils.Helpers.invalid_value(default, "a currency code or name")}
  end

  # A closing period is tried off as well as on, so "100 USD." is dollars as
  # it is in the text of a sentence.
  defp text_currency(text, options) do
    filters = Keyword.take(options, [:locale, :only, :except, :fuzzy])

    [text, String.trim_trailing(text, ".")]
    |> Enum.uniq()
    |> first_text_currency(text, filters, options)
  end

  defp first_text_currency([candidate | rest], text, filters, options) do
    case amount_currency_text(candidate, filters) do
      [currency] when is_atom(currency) ->
        unclaimed_currency(currency, candidate, options)

      {:error, %Localize.UnknownCurrencyError{}} ->
        first_text_currency(rest, text, filters, options)

      {:error, _invalid_option} = error ->
        error

      _part_of_the_text ->
        first_text_currency(rest, text, filters, options)
    end
  end

  defp first_text_currency([], text, _filters, options) do
    case caller_claim(Keyword.get(options, :caller_currency), text) do
      {:ok, currency} -> uncontested_caller_currency(currency, text, options)
      :none -> {:error, Localize.UnknownCurrencyError.exception(currency: text)}
      {:error, _invalid_option} = error -> error
    end
  end

  # The narrow symbol of a currency other than the locale's own is not read
  # as that currency, but it still names it, so a caller's currency that
  # claims the same text is refused rather than read: `en` "₮5" is neither the
  # tugrik, whose narrow symbol "₮" is, nor Tether, whose symbol it is too.
  defp uncontested_caller_currency(currency, text, options) do
    case narrow_symbol_currency(text, options) do
      nil -> {:ok, currency, nil}
      code -> {:error, ambiguous_currency(text, code, currency)}
    end
  end

  defp narrow_symbol_currency(text, options) do
    filters = Keyword.take(options, [:only, :except])

    case Localize.Currency.narrow_symbol_strings(Keyword.get(options, :locale), filters) do
      {:ok, narrow} ->
        Map.get(narrow, nfkc(text)) || Map.get(narrow, nfkc(String.trim_trailing(text, ".")))

      {:error, _no_data} ->
        nil
    end
  end

  # A currency amount's text names a currency only where one alone takes it:
  # "$" in `fr`, which the Canadian, US and other dollars share, is refused
  # rather than read as the Canadian dollar.
  defp amount_currency_text(text, filters) do
    with :ok <- validate_arguments(text, :string, filters) do
      find_currency(text, filters, :amount)
    end
  end

  # Text that names a CLDR currency names it only if the caller's
  # `:caller_currency` does not name another for the same text: `₮` is the
  # tugrik in CLDR and Tether's symbol as a digital token, so `en` "₮5" is
  # refused rather than read as either. In a locale whose own currency the
  # text names, that currency takes it: `mn` "₮5" is the tugrik.
  defp unclaimed_currency(currency, text, options) do
    case caller_claim(Keyword.get(options, :caller_currency), text) do
      {:ok, ^currency} -> {:ok, currency, currency}
      {:ok, other} -> own_or_ambiguous(currency, other, text, options)
      :none -> {:ok, currency, currency}
      {:error, _invalid_option} = error -> error
    end
  end

  defp own_or_ambiguous(currency, other, text, options) do
    if own_currency(Keyword.get(options, :locale)) == currency do
      {:ok, currency, currency}
    else
      {:error, ambiguous_currency(text, currency, other)}
    end
  end

  defp caller_claim(nil, _text) do
    :none
  end

  defp caller_claim(resolver, text) when is_function(resolver, 1) do
    case resolver.(text) do
      {:ok, currency} -> {:ok, currency}
      _not_the_callers -> :none
    end
  end

  defp caller_claim(resolver, _text) do
    {:error, Localize.Utils.Helpers.invalid_value(resolver, "a function of one argument")}
  end

  defp ambiguous_currency(text, currency, other) do
    Localize.ParseError.exception(
      input: text,
      reason: :unexpected_input,
      detail: "it names two currencies, #{inspect(currency)} and #{inspect(other)}"
    )
  end

  defp amount_number(%{lead: lead, rest: rest}, currency, separators_of, options) do
    number = String.trim(lead <> rest)

    parse_options =
      options
      |> Keyword.take([:locale, :number_system, :separators])
      |> Keyword.put(:number, :decimal)
      |> Keyword.put(:grouping, :sizes)
      |> put_separators_currency(separators_of)

    case parse(number, parse_options) do
      {:ok, decimal} -> unambiguous_fraction(decimal, number, currency)
      {:error, exception} -> {:error, invalid_amount(currency, number, exception)}
    end
  end

  # One to three digits, a decimal mark and three more are a thousands group
  # where the text was written with other separators, and three fraction
  # digits are unusual for a currency with fewer: German "1,599 €" is a fuel
  # price, but a shop writing English separators means 1599. Such an amount is
  # refused, as is the same shape with a period in `fr`. An amount under one,
  # or in a currency of three decimal places or more, has one reading.
  defp unambiguous_fraction(decimal, number, currency) do
    if three_fraction_digits?(number, decimal) and fewer_digits?(currency, 3) do
      cause =
        Localize.ParseError.exception(
          input: number,
          reason: :unexpected_input,
          detail: "it may be a whole amount written with a group separator"
        )

      {:error, invalid_amount(currency, number, cause)}
    else
      {:ok, decimal}
    end
  end

  defp three_fraction_digits?(number, decimal) do
    String.match?(number, @group_shape) and decimal.exp < 0 and
      Decimal.compare(Decimal.abs(decimal), 1) != :lt
  end

  defp fewer_digits?(currency, places) when is_atom(currency) do
    case Localize.Currency.currency_for_code(currency) do
      {:ok, %{digits: digits, iso_digits: iso_digits}} -> max(digits, iso_digits || 0) < places
      {:error, _not_iso} -> false
    end
  end

  defp fewer_digits?(_caller_currency, _places) do
    false
  end

  # A currency the caller's `:caller_currency` named has no separators in
  # CLDR, so its amount is read with the locale's plain-number ones and the
  # root locale's, and refused where they differ.
  defp put_separators_currency(options, nil) do
    Keyword.put(options, :root_separators, true)
  end

  defp put_separators_currency(options, currency) do
    Keyword.put(options, :currency, currency)
  end

  defp not_an_amount(string) do
    Localize.ParseError.exception(
      input: string,
      reason: :unexpected_input,
      detail: "not a currency amount"
    )
  end

  defp invalid_amount(currency, number, cause) do
    Localize.InvalidAmountError.exception(currency: currency, amount: number, cause: cause)
  end

  defp find_and_replace_currency(string_map, string, fuzzy, language_tag) do
    replace_strings(string_map, string, fuzzy, period_strings(language_tag))
  end

  defp replace_strings(string_map, string, fuzzy, period_strings) do
    if String.trim(string) == "" do
      {:ok, string}
    else
      do_find_and_replace(string_map, string, fuzzy, period_strings)
    end
  end

  # CLDR writes some currency symbols and names with a closing period, "kr." in
  # `da` and "ج.م.‏" in `ar`, and `Localize.Currency.currency_strings/2` stores
  # them without it, so "kr." matched as "kr" and left the period over as
  # text. These are the stored strings whose CLDR form had one, so the
  # matcher takes a period after them as part of the currency. After any
  # other string a period is left alone: "100 USD." ends a sentence.
  defp period_strings(language_tag) do
    locale = locale_id(language_tag)

    cached({:currency_period_strings, locale}, fn ->
      locale
      |> Localize.Currency.currencies_for_locale()
      |> period_strings_of()
    end)
  end

  defp period_strings_of({:ok, currencies}) do
    for {_code, currency} <- currencies,
        text <- currency_texts(currency),
        text = String.trim_trailing(String.downcase(text), "\u200F"),
        String.ends_with?(text, "."),
        into: MapSet.new(),
        do: String.trim_trailing(text, ".")
  end

  defp period_strings_of({:error, _no_currencies}) do
    MapSet.new()
  end

  defp currency_texts(currency) do
    counts =
      if is_map(currency.count) do
        Map.values(currency.count)
      else
        []
      end

    Enum.filter([currency.name, currency.symbol, currency.narrow_symbol | counts], &is_binary/1)
  end

  defp parse_element(element, options) do
    case parse(element, options) do
      {:ok, number} -> number
      {:error, _} -> element
    end
  end

  defp parse_number(string, nil) do
    with {:error, _} <- parse_number(string, :integer),
         {:error, _} <- parse_number(string, :float) do
      {:error, string}
    end
  end

  defp parse_number(string, :integer) do
    case Integer.parse(string) do
      {integer, ""} -> {:ok, integer}
      _ -> {:error, string}
    end
  end

  defp parse_number(string, :float) do
    case Float.parse(string) do
      {float, ""} -> {:ok, float}
      _ -> {:error, string}
    end
  end

  defp parse_number(string, :decimal) do
    case Localize.Utils.Decimal.parse(string) do
      {:error, _} -> {:error, string}
      {decimal, ""} -> {:ok, decimal}
      _ -> {:error, string}
    end
  end

  defp normalize_number_string(
         string,
         symbols,
         language_tag,
         number_system,
         grouping,
         period_separator
       ) do
    lenient = lenient_replacements(language_tag)

    # TR35 is explicit that loose matching applies "to both the input text and
    # to each of the field elements used in matching". Folding only the input
    # would break the locales whose own separator is one of the characters
    # being folded: `de-CH` groups with an ASCII apostrophe, which the general
    # scope maps onto U+2019, and `ar`'s `arab` decimal separator U+066B is in
    # the comma set. Folding both sides keeps them matching each other.
    group_sep = symbols.group |> extract_separator() |> apply_lenient(lenient)
    decimal_sep = symbols.decimal |> extract_separator() |> apply_lenient(lenient)

    folded =
      string
      # Elixir's own numeric literal separator, dropped before the minus fold
      # below can introduce one of its own.
      |> String.replace("_", "")
      |> String.replace(@format_characters, "")
      |> apply_lenient(lenient)
      # Before the signs are read, so the dash of "5.-" is not a minus.
      |> drop_zero_fraction(decimal_sep, grouping)

    with {:ok, body, negative?} <- signed_body(folded, decimal_sep),
         body = normalize_spaces(body, group_sep),
         :ok <-
           validate_grouping(body, group_sep, decimal_sep, language_tag, number_system, grouping),
         :ok <- no_stray_period(body, group_sep, decimal_sep, period_separator) do
      number =
        body
        |> String.replace(group_sep, "")
        |> String.replace(@spaces, "")
        |> String.replace(decimal_sep, ".")
        |> complete_decimal_point()
        # CLDR names the minus set by the sample "_", so folding it yields
        # that placeholder rather than a sign. What remains of one here is an
        # exponent's.
        |> String.replace("_", "-")

      {:ok, signed_number(number, negative?)}
    end
  end

  # The number is handed to Elixir with "." as its decimal point, so a period
  # that is neither of the locale's separators would pass for one. It is read
  # as one only where it can be nothing else: a single period between digits,
  # in text without the locale's own decimal mark, and not in the shape of a
  # thousands group. `fr` "100.00" is 100, but "1.234" is refused, since one
  # who groups with a period means 1234 by it. Where another set the number is
  # read with has the period, this one leaves it to that set.
  defp no_stray_period(body, group_sep, decimal_sep, period_separator) do
    cond do
      "." in [group_sep, decimal_sep] -> :ok
      not String.contains?(body, ".") -> :ok
      period_separator -> {:error, :stray_period}
      foreign_decimal_point?(body, decimal_sep) -> :ok
      true -> {:error, :stray_period}
    end
  end

  defp foreign_decimal_point?(body, decimal_sep) do
    not String.contains?(body, decimal_sep) and String.match?(body, @foreign_decimal_point) and
      not String.match?(body, @period_group)
  end

  # A number's sign or accounting parentheses, as a money amount writes
  # them: one sign at most, before or after the digits, or parentheses,
  # which make it negative, so "(5)" is -5. TR35's heuristics for parsing a
  # number take a sign as a prefix or a suffix. A sign and parentheses
  # together are refused: "(-5)" is read as -5 by some and as 5 by others.
  # So is a minus before a decimal mark with no digit ahead of it: Swiss
  # "Fr. –.15" and Dutch "€ -,50" write a dash for the zero, so "-.15" may be
  # 0.15 or -0.15. Spaces between them and the digits are not part of the
  # number.
  defp signed_body(folded, decimal_sep) do
    [_whole, before_open, open, after_open, body, before_close, close, after_close] =
      Regex.run(@signed_number, folded)

    signs = Enum.reject([before_open, after_open, before_close, after_close], &(&1 == ""))

    cond do
      body == "" -> {:error, :no_digits}
      match?([_, _ | _], signs) -> {:error, :signs}
      open == "(" != (close == ")") -> {:error, :parentheses}
      open == "(" and match?([_ | _], signs) -> {:error, :signs}
      dash_for_zero?(before_open, after_open, body, decimal_sep) -> {:error, :dash_for_zero}
      true -> {:ok, body, signs == ["_"] or open == "("}
    end
  end

  defp dash_for_zero?(before_open, after_open, body, decimal_sep) do
    "_" in [before_open, after_open] and decimal_sep != "" and
      String.starts_with?(body, decimal_sep)
  end

  # A decimal mark may open or close a number, ".5" or "5.". Elixir's float
  # and integer parsers refuse both and its decimal parser takes them, so the
  # point is completed here and every number type reads them alike.
  defp complete_decimal_point(number) do
    number
    |> String.replace(@opening_point, "0.")
    |> String.replace(@closing_point, "")
  end

  defp signed_number(number, true) do
    "-" <> number
  end

  defp signed_number(number, false) do
    number
  end

  # Swiss "5.–" and Dutch "5,-" write a whole amount with a dash for its
  # fraction. CLDR has no data for the convention (CLDR-3394), so it is read
  # only leniently, after the folds.
  defp drop_zero_fraction(string, decimal_sep, grouping)
       when grouping in [:lenient, :sizes] and decimal_sep != "" do
    # The dash ends the number, which may be followed by the closing
    # parenthesis of an accounting format: "(CHF 5.–)".
    [{start, _length}] = Regex.run(@closing_parenthesis, string, return: :index)
    number = binary_part(string, 0, start)
    closing = binary_part(string, start, byte_size(string) - start)

    Enum.find_value(@zero_fraction_dashes, string, fn dashes ->
      whole = String.replace_suffix(number, decimal_sep <> dashes, "")

      if whole != number and String.match?(whole, @ends_in_digit) do
        whole <> closing
      end
    end)
  end

  defp drop_zero_fraction(string, _decimal_sep, _strict) do
    string
  end

  # Where the locale groups with a space, every space folds onto that separator
  # so the grouping check below can see it. Deleting them instead would erase
  # the very characters whose positions are being validated. Elsewhere a space
  # inside the number is refused by `interior_space?/2`.
  defp normalize_spaces(string, group_sep) do
    if String.match?(group_sep, @single_space) do
      String.replace(string, @spaces, group_sep)
    else
      string
    end
  end

  # ── Grouping shape ─────────────────────────────────────────────
  #
  # TR35's heuristics for parsing a number, which "may be helpful", have a
  # grouping separator ignored wherever it stands, and leave it to the
  # implementation "to disambiguate the sets of characters that might serve in
  # more than one position, based on context". A space is such a character: it
  # groups digits in many locales and parts numbers in all of them. So a
  # grouping separator is held to a plausible position, in both modes, which
  # differ only in how strict "plausible" is (user, 2026-10-06,
  # `plans/tr35-audit.md`; ICU holds it so too, with the same floor):
  #
  #   * strict  — every group is exactly the locale's grouping size, so `fr`
  #     takes "1 234 567" and refuses "1 23".
  #
  #   * lenient — every group is at least two digits, so "1 23" is taken but
  #     "3 4" is not, and no longer than the locale's longest group, so `de`
  #     refuses "1234.56" rather than reading it as 123456. The longest
  #     rather than each position's own size, so `en-IN` still takes
  #     "1,234,567" written with Western grouping.
  #
  # The lenient floor of two is what keeps a space usable as a grouping
  # separator without swallowing adjacent small numbers: "3 4 5" is three
  # numbers in any locale, and no mode reads it as 345.

  defp validate_grouping(string, group_sep, decimal_sep, language_tag, number_system, grouping) do
    [integer_part | fraction] = String.split(string, decimal_sep, parts: 2)
    integer_part = String.replace(integer_part, ["_", "+"], "")

    # Digits after the decimal mark are never grouped, so a grouping
    # separator there means the text is not a number of this locale: `de`
    # "1,234.56" is not 1.23456, nor `fr` "1,5 6" 1.56.
    cond do
      interior_space?(string, group_sep) ->
        {:error, :grouping}

      grouped_fraction?(fraction, group_sep) ->
        {:error, :grouping}

      true ->
        validate_integer_grouping(integer_part, group_sep, language_tag, number_system, grouping)
    end
  end

  # A number is digits joined by the locale's separators. Where the locale
  # groups with a space, `normalize_spaces/2` has already made every space
  # that separator; anywhere else a space inside the number parts two
  # numbers, as `scan/2` reads them, so `en` "1 2" is not 12. A space before
  # or after the number, or beside its sign, is not inside it.
  defp interior_space?(string, group_sep) do
    if String.match?(group_sep, @single_space) do
      false
    else
      string
      |> String.replace(@edge_spaces, "")
      |> String.match?(@spaces)
    end
  end

  defp grouped_fraction?([fraction], group_sep) when group_sep != "" do
    String.contains?(fraction, group_sep)
  end

  defp grouped_fraction?(_no_fraction, _group_sep) do
    false
  end

  defp validate_integer_grouping(integer_part, group_sep, language_tag, number_system, grouping) do
    case String.split(integer_part, group_sep) do
      # No grouping separator at all: grouping is optional in input.
      [_ungrouped] -> :ok
      groups -> validate_groups(groups, grouping_sizes(language_tag, number_system), grouping)
    end
  end

  defp validate_groups(groups, sizes, grouping) do
    # A group that is not all digits is not a group at all.
    digits? = Enum.all?(groups, &(&1 != "" and String.match?(&1, @digits_only)))

    if digits? and grouped?(groups, sizes, grouping) do
      :ok
    else
      {:error, :grouping}
    end
  end

  defp grouped?([leading | rest], {primary, secondary}, :lenient) do
    lenient_groups?(leading, rest, max(primary, secondary))
  end

  # Each group is one the locale writes: the last of the primary size, the
  # ones before it of the primary or secondary size, and the first no longer
  # than either. So `de` refuses "1.23", which a two-digit floor reads as
  # 123 though it may well be 1.23, and `en-IN` takes both "12,34,567" and
  # "1,234,567".
  defp grouped?([leading | rest], {primary, secondary}, :sizes) do
    {last, middle} = List.pop_at(rest, -1)

    String.length(leading) <= max(primary, secondary) and
      String.length(last) == primary and
      Enum.all?(middle, &(String.length(&1) in [primary, secondary]))
  end

  defp grouped?([leading | rest], {primary, secondary}, :strict) do
    {last, middle} = List.pop_at(rest, -1)

    String.length(last) == primary and
      Enum.all?(middle, &(String.length(&1) == secondary)) and
      String.length(leading) <= secondary
  end

  defp lenient_groups?(leading, rest, longest) do
    String.length(leading) <= longest and
      Enum.all?(rest, &(String.length(&1) in @lenient_group_floor..longest//1))
  end

  # The primary group is the rightmost run in the locale's standard pattern and
  # the secondary the one before it. They differ in the Indian system —
  # `en-IN` patterns as `#,##,##0.###`, grouping 12,34,567 — and are the same
  # everywhere else, where a single run means the primary repeats.
  defp grouping_sizes(language_tag, number_system) do
    cached({:grouping_sizes, language_tag.cldr_locale_id, number_system}, fn ->
      keys = [:number_formats, number_system, :standard]

      case Localize.Locale.get(language_tag, keys, fallback: true) do
        {:ok, pattern} -> sizes_from_pattern(pattern)
        {:error, _reason} -> @default_grouping_sizes
      end
    end)
  end

  defp sizes_from_pattern(pattern) do
    runs =
      pattern
      |> String.split(".")
      |> hd()
      |> String.split(",")

    case runs do
      [_ungrouped] ->
        @default_grouping_sizes

      runs ->
        primary = runs |> List.last() |> String.length()

        # With a single separator the leading run is the "#" wildcard rather
        # than a group, so the primary size repeats; a second separator is what
        # introduces a distinct secondary size, as in `en-IN`'s `#,##,##0`.
        secondary =
          if match?([_, _, _ | _], runs),
            do: runs |> Enum.at(-2) |> String.length(),
            else: primary

        {primary, secondary}
    end
  end

  # The character folds CLDR's `parseLenients` data prescribes for this locale,
  # as {compiled pattern, replacement} pairs. The number scope covers the
  # minus, plus and comma families; the general scope adds the full stop, the
  # apostrophe and the currency symbols.
  #
  # Compiled once per locale and memoized. Assembling this walks a dozen set
  # strings, which costs an order of magnitude more than the parse it serves,
  # and the compiled patterns then match without rescanning per character.
  defp lenient_replacements(language_tag) do
    cached({:lenient_parse, language_tag.cldr_locale_id}, fn ->
      for {sample, characters} <- lenient_sets(language_tag) do
        {:binary.compile_pattern(characters), sample}
      end
    end)
  end

  # The same folds as {sample, characters} pairs, for building the scanner's
  # character classes.
  defp lenient_sets(language_tag) do
    cached({:lenient_sets, language_tag.cldr_locale_id}, fn ->
      for scope <- [:number, :general],
          {:ok, sets} <-
            [Localize.Locale.get(language_tag, [:lenient_parse, scope], fallback: true)],
          {sample, set} <- sets,
          characters = lenient_characters(set),
          match?([_ | _], characters),
          do: {sample, characters}
    end)
  end

  # Every character that folds onto the same sample as `character`, itself
  # included.
  defp lenient_equivalents("", _sets) do
    []
  end

  defp lenient_equivalents(character, sets) do
    family =
      Enum.find_value(sets, [], fn {sample, characters} ->
        if character == sample or character in characters do
          [sample | characters]
        end
      end)

    Enum.uniq([character | family])
  end

  defp apply_lenient(string, replacements) do
    Enum.reduce(replacements, string, fn {pattern, replacement}, acc ->
      String.replace(acc, pattern, replacement)
    end)
  end

  @compile {:inline, cached: 2}
  defp cached(key, build_fn) do
    pt_key = {__MODULE__, key}

    case :persistent_term.get(pt_key, :__not_loaded__) do
      :__not_loaded__ ->
        value = build_fn.()
        Localize.LiteralMemory.cache(pt_key, value)
        value

      value ->
        value
    end
  end

  # The sets are flat character lists — no ranges, and the one literal hyphen is
  # backslash-escaped precisely so it is not read as one — so they need
  # unwrapping rather than a UnicodeSet parser. The general scope does carry a
  # few `{Rs}`-style compound patterns, which name no single character and are
  # dropped rather than split into their letters.
  defp lenient_characters(set) do
    set
    |> String.replace(@compound_pattern, "")
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.replace("\\", "")
    |> String.graphemes()
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp extract_separator(%{standard: value}), do: value
  defp extract_separator(value) when is_binary(value), do: value
  defp extract_separator(_), do: ""

  defp transliterate_digits(string, :latn), do: string

  defp transliterate_digits(string, number_system) do
    case System.number_system_digits(number_system) do
      {:ok, digits} ->
        {:ok, latn_digits} = System.number_system_digits(:latn)
        map = System.generate_transliteration_map(digits, latn_digits)
        Localize.Number.Transliterate.transliterate_digits(string, map)

      _ ->
        string
    end
  end

  defp digits_number_system_from(language_tag, string, options) do
    number_system =
      Keyword.get_lazy(options, :number_system, fn ->
        written_number_system(language_tag, string)
      end)

    case System.number_system_digits(number_system) do
      {:ok, _digits} -> {:ok, number_system}
      {:error, _} = error -> error
    end
  end

  # The locale's number system, unless the text is written in Latin digits
  # alone. `ar-EG` writes `arab` digits with ٬ and ٫, and ٫ folds onto ",", so
  # reading typed "100,00" with those separators made it 100.00 and refused
  # "1,234.56". The locale's Latin separators are the ones such text is
  # written with.
  defp written_number_system(language_tag, string) do
    case System.number_system_from_locale(language_tag) do
      {:ok, system} -> system_for_digits(system, string)
      _no_system -> :latn
    end
  end

  defp system_for_digits(:latn, _string) do
    :latn
  end

  defp system_for_digits(system, string) do
    case System.number_system_digits(system) do
      {:ok, digits} -> native_or_latin(system, digits, string)
      {:error, _not_numeric} -> system
    end
  end

  defp native_or_latin(system, digits, string) do
    if String.contains?(string, String.graphemes(digits)) do
      system
    else
      :latn
    end
  end

  defp number_symbols(language_tag, number_system, options) do
    with {:ok, symbols} <- symbols_for(language_tag, number_system, options[:currency]) do
      separators = Keyword.get(options, :separators, :standard)

      {:ok,
       %{
         symbols
         | decimal: variant(symbols.decimal, separators),
           group: variant(symbols.group, separators)
       }}
    end
  end

  # CLDR gives a few locales a second set of separators, such as the `:us` set
  # of `en-ZA`. A locale without the requested set reads with its standard one.
  defp variant(%{standard: standard} = separators, name), do: Map.get(separators, name, standard)
  defp variant(separator, _name), do: separator

  defp symbols_for(language_tag, number_system, nil) do
    with {:ok, symbols} <- Symbol.number_symbols_for(language_tag) do
      {:ok, Map.get(symbols, number_system) || Map.get(symbols, :latn)}
    end
  end

  # A currency amount is read with the symbols `Localize.Number.to_string/2`
  # formats it with, so what it formats parses back.
  defp symbols_for(language_tag, number_system, currency) do
    with {:ok, symbols} <- Symbol.number_symbols_for(language_tag, number_system),
         {:ok, currency} <- currency_for(currency, language_tag) do
      {:ok, Symbol.for_currency(symbols, currency)}
    end
  end

  defp currency_for(%Localize.Currency{} = currency, _language_tag), do: {:ok, currency}

  # Reading needs only the currency's separators, not its display names, so a
  # currency the locale has no names for reads with its parent's data.
  defp currency_for(code, language_tag),
    do: Localize.Currency.currency_for_code(code, locale: language_tag, fallback: true)

  # `parse/2` folds each piece the scanner hands it with CLDR's `parseLenients`
  # sets, so the scanner must accept every character those folds would accept.
  # Matching only the locale's literal symbols splits a number at a folded
  # variant: `de-CH` text grouped with U+2019 rather than its own ASCII
  # apostrophe, or `sv` text signed with U+2212, came back in pieces.
  #
  # A character that folds onto both separators' families is left to the
  # separator it is literally, so the classes never overlap.
  defp localize_format_string(string, symbols, language_tag) do
    sets = lenient_sets(language_tag)
    group_sep = extract_separator(symbols.group)
    decimal_sep = extract_separator(symbols.decimal)
    group_family = lenient_equivalents(group_sep, sets)
    decimal_family = lenient_equivalents(decimal_sep, sets)

    group = Enum.uniq([group_sep | group_family -- decimal_family])
    decimal = Enum.uniq([decimal_sep | decimal_family -- group_family])

    replacements = %{
      "-+" => sign_class(symbols, sets),
      "," => group_class(group_sep, group),
      "\\." => "[" <> class_characters(decimal) <> "]"
    }

    # One pass, so a replacement's own characters are never replaced again.
    Regex.replace(@format_placeholders, string, &Map.fetch!(replacements, &1))
  end

  # The signs `parse/2` reads: ASCII, the locale's own, and their folds. The
  # minus family's sample "_" is left out, because `parse/2` drops an
  # underscore as a digit separator rather than reading it as a sign. Format
  # characters in a locale's sign are not part of the sign here.
  defp sign_class(symbols, sets) do
    sets
    |> sign_characters([symbols.minus_sign, symbols.plus_sign])
    |> class_characters()
  end

  # The signs `parse/2` folds: ASCII's, any `extra_signs` such as the
  # locale's own, and their folds. The minus family's sample "_" is left
  # out, because `parse/2` drops an underscore as a digit separator rather
  # than reading it as a sign. Format characters in a locale's sign are not
  # part of the sign here. The scanner and the currency amount splitter both
  # take their signs from here.
  defp sign_characters(sets, extra_signs \\ []) do
    for sign <- ["-", "+" | extra_signs],
        sign = String.replace(extract_separator(sign), @format_characters, ""),
        character <- lenient_equivalents(sign, sets),
        character != "_",
        uniq: true,
        do: character
  end

  # What counts as a grouping separator inside the scanner's character class.
  # Where the locale groups with a space, the whole space category counts, so a
  # number typed with an ordinary keyboard space is found in text that a locale
  # would format with U+202F. The grouping-shape lookahead below is what keeps
  # that from joining unrelated numbers.
  defp group_class(group_sep, group) do
    if String.match?(group_sep, @single_space) do
      "\\p{Zs}"
    else
      class_characters(group)
    end
  end

  defp class_characters(characters) do
    characters
    |> Enum.reject(&(&1 == ""))
    |> Enum.map_join(&Regex.escape/1)
  end

  defp zero_fraction(pattern, true) do
    String.replace(pattern, "ZERO_FRACTION", @zero_fraction)
  end

  defp zero_fraction(pattern, _strict) do
    String.replace(pattern, "ZERO_FRACTION", "(?!)")
  end

  # `@number_format` admits a grouping separator whenever a digit follows. That
  # is too permissive once the separator can be a space: it would read "3 4 5"
  # as one number. Requiring a plausible group instead, two digits leniently
  # or an exact group size strictly, is what makes the wider class safe.
  defp group_lookahead(pattern, language_tag, number_system, symbols, lenient?) do
    {primary, secondary} = grouping_sizes(language_tag, number_system)

    lookahead =
      if lenient? do
        "(?=[0-9]{#{@lenient_group_floor}})"
      else
        separator = symbols.group |> extract_separator() |> Regex.escape()
        "(?=[0-9]{#{primary}}(?![0-9])|[0-9]{#{secondary}}#{separator})"
      end

    String.replace(pattern, "(?=[0-9])", lookahead)
  end

  defp build_per_strings(symbols) do
    percent = symbols.percent_sign
    per_mille = symbols.per_mille

    entries =
      if percent, do: [{percent, :percent}], else: []

    entries =
      if per_mille, do: entries ++ [{per_mille, :permille}], else: entries

    # Add common ASCII equivalents
    entries =
      entries ++
        [
          {"%", :percent},
          {"‰", :permille}
        ]

    Map.new(entries)
  end

  defp locale_id(%Localize.LanguageTag{cldr_locale_id: id}) when not is_nil(id), do: id
  defp locale_id(%Localize.LanguageTag{}), do: :en

  # Parsing reads with a locale's own data or not at all. When a locale is not
  # installed and cannot be downloaded, the loader puts a parent's data or
  # English in its place, which formatting can live with but parsing cannot:
  # with English data `en-AU` "$5" is US dollars and `zh` "¥1.00" yen.
  defp parsing_locale(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale),
         locale_id = locale_id(language_tag),
         {:ok, data_locale_id} <- Localize.Locale.get(locale_id, [:name]) do
      own_locale_data(language_tag, locale_id, data_locale_id)
    end
  end

  defp own_locale_data(language_tag, locale_id, locale_id) do
    {:ok, language_tag}
  end

  defp own_locale_data(_language_tag, locale_id, _data_locale_id) do
    path = Localize.Locale.Provider.Cache.path(locale_id)
    {:error, Localize.LocaleNotFoundInCacheError.exception(locale_id: locale_id, path: path)}
  end

  defp do_find_and_replace(string_map, string, nil, period_strings) do
    canonical = String.downcase(String.trim(string))

    if code = Map.get(string_map, canonical) do
      {:ok, [code]}
    else
      [starting_code, remainder] = starting_string(string_map, string, period_strings)
      [remainder, ending_code] = ending_string(string_map, remainder, period_strings)

      if starting_code == "" && ending_code == "" do
        {:error, parse_error("No match was found")}
      else
        {:ok, Enum.reject([starting_code, remainder, ending_code], &(&1 == ""))}
      end
    end
  end

  defp do_find_and_replace(string_map, _search, fuzzy, _period_strings)
       when map_size(string_map) == 0 and is_float(fuzzy) and fuzzy > 0.0 and fuzzy <= 1.0 do
    {:error, parse_error("No match was found")}
  end

  defp do_find_and_replace(string_map, search, fuzzy, _period_strings)
       when is_float(fuzzy) and fuzzy > 0.0 and fuzzy <= 1.0 do
    canonical_search = String.downcase(search)

    # Equally distant strings are ranked alphabetically: sorting on the
    # distance alone left a tie to the order the map yielded them in.
    {distance, _string, code} =
      string_map
      |> Enum.map(fn {string, code} ->
        {String.jaro_distance(string, canonical_search), string, code}
      end)
      |> Enum.min_by(fn {distance, string, _code} -> {-distance, string} end)

    if distance >= fuzzy do
      {:ok, [code]}
    else
      {:error, parse_error("No match was found")}
    end
  end

  defp do_find_and_replace(_string_map, _string, fuzzy, _period_strings) do
    {:error,
     Localize.InvalidValueError.exception(
       value: fuzzy,
       expected: "a number > 0.0 and <= 1.0",
       context: "option :fuzzy"
     )}
  end

  # A currency name or code matches only as a whole word: "dolars" ends in
  # "ars", which is not the Argentine peso. A match that begins or ends in a
  # letter must not run on into another letter; a symbol ("$", "€") needs no
  # boundary, and neither does a letter next to a digit ("USD100").
  defp starting_string(string_map, search, period_strings) do
    trimmed = String.downcase(String.trim_leading(search))

    matches =
      Enum.filter(string_map, fn {k, _v} ->
        String.starts_with?(trimmed, k) and
          word_boundary?(last_grapheme(k), String.first(binary_part_after(trimmed, k)))
      end)

    case matches do
      [] ->
        ["", search]

      list ->
        {match_string, code} = longest_match(list)
        match_length = byte_size(match_string)
        # Find the match in the original string (preserving original case/whitespace)
        downcased = String.downcase(search)
        offset = find_offset(downcased, match_string)

        if offset >= 0 do
          skip = offset + match_length
          <<_::binary-size(^skip), remainder::binary>> = search
          [code, drop_closing(remainder, match_string, period_strings)]
        else
          ["", search]
        end
    end
  end

  defp ending_string(string_map, search, period_strings) do
    trimmed = String.downcase(String.trim_trailing(search))
    core = String.replace(trimmed, @trailing_bidi_controls, "")
    closing = byte_size(trimmed) - byte_size(core)

    matches =
      for {key, code} <- string_map,
          consumed <- ending_matches(trimmed, core, closing, key, period_strings),
          do: {consumed, byte_size(key), code}

    case matches do
      [] ->
        [search, ""]

      list ->
        # Of two matches that take as much of the text, the one written out
        # in full wins over one that reaches it through a closing period.
        {consumed, _key_size, code} = Enum.max(list)
        keep = byte_size(String.trim_trailing(search)) - consumed
        <<remainder::binary-size(^keep), _::binary>> = search
        [remainder, code]
    end
  end

  # What follows a currency matched at the start of the text and belongs to
  # it: the closing period its CLDR form was written with, then any bidi
  # controls, which `Localize.Currency.currency_strings/2` also leaves off.
  defp drop_closing(remainder, match_string, period_strings) do
    remainder =
      if MapSet.member?(period_strings, match_string) do
        String.replace_prefix(remainder, ".", "")
      else
        remainder
      end

    String.replace(remainder, @leading_bidi_controls, "")
  end

  # The bytes `key` takes from the end of the text, once for each way it can
  # end it: as written, before a closing run of bidi controls, and before the
  # closing period its CLDR form was written with.
  defp ending_matches(trimmed, core, closing, key, period_strings) do
    candidates = [
      {trimmed, 0},
      {core, closing},
      {period_core(core, key, period_strings), closing + 1}
    ]

    for {text, extra} <- candidates, is_binary(text), ends_with_word?(text, key) do
      byte_size(key) + extra
    end
  end

  defp period_core(core, key, period_strings) do
    if MapSet.member?(period_strings, key) and String.ends_with?(core, ".") do
      binary_part(core, 0, byte_size(core) - 1)
    end
  end

  defp ends_with_word?(text, key) do
    String.ends_with?(text, key) and
      word_boundary?(String.first(key), String.last(binary_part_before(text, key)))
  end

  # Every match is a prefix (or every one a suffix) of the same text, so no
  # two have the same byte size and the longest is unique. Grapheme counts
  # can tie: in te a currency's plural adds a zero-width non-joiner and a
  # suffix that join the last grapheme, so it counts no longer than the
  # singular, and the tie went to whichever the map yielded first.
  defp longest_match(matches) do
    Enum.max_by(matches, fn {match_string, _code} -> byte_size(match_string) end)
  end

  # True when a match whose edge grapheme is `key_edge` may stop where
  # `neighbour` starts: at the end of the string, next to a non-letter, or
  # when the match itself does not stop on a letter.
  defp word_boundary?(_key_edge, nil), do: true

  defp word_boundary?(key_edge, neighbour),
    do: not (letter?(key_edge) and letter?(neighbour))

  defp letter?(grapheme), do: String.match?(grapheme, ~r/\A\p{L}/u)

  defp last_grapheme(string), do: String.last(string)

  defp binary_part_after(string, prefix),
    do: binary_part(string, byte_size(prefix), byte_size(string) - byte_size(prefix))

  defp binary_part_before(string, suffix),
    do: binary_part(string, 0, byte_size(string) - byte_size(suffix))

  defp find_offset(haystack, needle) do
    case :binary.match(haystack, needle) do
      {offset, _length} -> offset
      :nomatch -> -1
    end
  end

  defp parse_error(message) do
    Localize.InvalidValueError.exception(
      value: message,
      expected: "a parseable number string",
      context: "Localize.Number.Parser"
    )
  end
end
