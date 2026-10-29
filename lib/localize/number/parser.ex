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

  alias Localize.Number.{Grammar, Lexicon}
  alias Localize.Number.Parser.Amount

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

  @single_space ~r/^\p{Zs}$/u

  # A run of the Bidi_Control characters in `@bidi_controls`, at the start or
  # the end of a string.
  @leading_bidi_controls Regex.compile!("\\A[" <> @bidi_control_class <> "]+", "u")
  @trailing_bidi_controls Regex.compile!("[" <> @bidi_control_class <> "]+\\z", "u")
  # The three places in `@number_format` that `localize_format_string/3` fills
  # in with the locale: the sign class, the grouping separator and the decimal.
  @format_placeholders ~r/-\+|,|\\\./

  # Smallest group a lenient parse will accept after a separator: two, the
  # floor that keeps "3 4 5" three numbers (see "Grouping shape" below).
  @lenient_group_floor 2

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
         locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0),
         {:ok, language_tag} <- parsing_locale(locale),
         {:ok, _number_type} <- number_type(Keyword.get(options, :number)),
         {:ok, number_system} <- Lexicon.number_system(language_tag, string, options),
         {:ok, symbol} <- Lexicon.number_symbols(language_tag, number_system, options) do
      lenient? = Keyword.get(options, :lenient, true)

      scanner =
        @number_format
        |> localize_format_string(symbol, language_tag)
        |> group_lookahead(language_tag, number_system, symbol, lenient?)
        |> zero_fraction(lenient?)
        |> Regex.compile!([:unicode])

      normalized_string =
        Localize.Number.Transliterate.transliterate_digits(string, Lexicon.digits(number_system))

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
    An underscore between two digits is Elixir's digit separator and
    is ignored, as in `"1_000_000.34"`; anywhere else it makes the text
    no number.

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
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)

    with {:ok, language_tag} <- parsing_locale(locale),
         {:ok, number_type} <- number_type(Keyword.get(options, :number)),
         {:ok, number_system} <- Lexicon.number_system(language_tag, string, options),
         {:ok, grouping} <- grouping_mode(options),
         {:ok, lexicon} <- Lexicon.fetch(language_tag, number_system, options) do
      Grammar.read(string, lexicon,
        number: number_type,
        grouping: grouping,
        max_decimal_exponent: max_decimal_exponent()
      )
    end
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
    the two differ. A caller's currency text may have digits in it, as a
    digital token's identifier "Q9PB7XDNF" does. It is then the first
    word of the amount or the last, which a space separates from the
    number, and it is read only where the amount has no other reading:
    `fr` "USD1 234" is also 1 234 US dollars, so it is neither.

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

      iex> token = fn "Q9PB7XDNF" -> {:ok, "Q9PB7XDNF"}; _other -> :error end
      iex> Localize.Number.Parser.parse_currency_amount("Q9PB7XDNF 5", locale: :en, caller_currency: token)
      {:ok, {"Q9PB7XDNF", Decimal.new("5")}}

  """
  @spec parse_currency_amount(String.t(), Keyword.t()) ::
          {:ok, {Localize.Currency.currency_code() | term(), Decimal.t()}}
          | {:error, Exception.t()}
  def parse_currency_amount(string, options \\ []) do
    with :ok <- validate_arguments(string, :string, options),
         :ok <- validate_amount_size(string),
         locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0),
         {:ok, language_tag} <- parsing_locale(locale) do
      Amount.read(string, language_tag, options)
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
    locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0)

    with {:ok, language_tag} <- parsing_locale(locale) do
      find_currency_in(language_tag, string, options, reading)
    end
  end

  # The same with a language tag the public entry has validated.
  defp find_currency_in(language_tag, string, options, reading) do
    only_filter = Keyword.get(options, :only, [:all])
    except_filter = Keyword.get(options, :except, [])
    fuzzy = Keyword.get(options, :fuzzy, nil)

    filters = [only: only_filter, except: except_filter]

    with {:ok, currency_strings} <- reading_strings(language_tag, filters, reading),
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

  defp reading_strings(language_tag, filters, :amount) do
    Lexicon.currencies(language_tag, filters)
  end

  defp reading_text(string, :nearest) do
    string
  end

  defp reading_text(string, :amount) do
    Lexicon.nfkc(string)
  end

  # A string several of the locale's currencies share ("$" in `fr`) names
  # the currency used where the locale closest to this one is spoken: of
  # the CLDR locales of each claimant's territories, the one
  # `Localize.LanguageTag.match_distance/2` puts nearest, if it is a good
  # fit and no locale of another claimant is as near. So "$" is the
  # Canadian dollar in `fr`, as it is in `fr-CA`, and stays unknown in
  # `es`, which Mexico, the United States and Argentina are as near.
  # A currency amount's text is one currency string or none, so it is
  # looked up rather than searched for: the string as it is, or a string
  # CLDR writes with a closing period ("kr.", "ج.م.") followed by that
  # period. `find_and_replace/3` finds the same two whole-text cases, but
  # otherwise scans every string of the locale for a part of the text, which
  # an amount never wants and which cost half a millisecond per miss.
  defp find_or_resolve_currency(currency_strings, string, nil, language_tag, _filters, :amount) do
    whole_currency(currency_strings, string, language_tag)
  end

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

  defp whole_currency(currency_strings, string, language_tag) do
    case Map.fetch(currency_strings, string) do
      {:ok, currency} -> {:ok, [currency]}
      :error -> period_currency(currency_strings, string, language_tag)
    end
  end

  defp period_currency(currency_strings, string, language_tag) do
    if String.ends_with?(string, ".") do
      key = binary_part(string, 0, byte_size(string) - 1)
      period_key_currency(currency_strings, key, language_tag)
    else
      no_whole_match()
    end
  end

  defp period_key_currency(currency_strings, key, language_tag) do
    if MapSet.member?(period_strings(language_tag), key) do
      case Map.fetch(currency_strings, key) do
        {:ok, currency} -> {:ok, [currency]}
        :error -> no_whole_match()
      end
    else
      no_whole_match()
    end
  end

  defp no_whole_match do
    {:error, parse_error("No match was found")}
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
         locale = Keyword.get_lazy(options, :locale, &Localize.get_locale/0),
         {:ok, language_tag} <- parsing_locale(locale),
         {:ok, number_system} <- Lexicon.number_system(language_tag, string, options),
         {:ok, symbol} <- Lexicon.number_symbols(language_tag, number_system, []) do
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

  @doc false
  # A currency amount's text names a currency only where one alone takes it:
  # "$" in `fr`, which the Canadian, US and other dollars share, is refused
  # rather than read as the Canadian dollar. `[currency]` when the text is
  # one currency string, as `find_and_replace/3` reports it. For
  # `Localize.Number.Parser.Amount`, with the language tag
  # `parse_currency_amount/2` validated and text out of the string it
  # validated, so nothing is checked again here.
  @spec find_amount_currency(String.t(), Localize.LanguageTag.t(), Keyword.t()) ::
          list() | {:error, Exception.t()}
  def find_amount_currency(text, %Localize.LanguageTag{} = language_tag, filters) do
    find_currency_in(language_tag, text, filters, :amount)
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

  defp extract_separator(%{standard: value}) do
    value
  end

  defp extract_separator(value) when is_binary(value) do
    value
  end

  defp extract_separator(_other) do
    ""
  end

  # `parse/2` folds each piece the scanner hands it with CLDR's `parseLenients`
  # sets, so the scanner must accept every character those folds would accept.
  # Matching only the locale's literal symbols splits a number at a folded
  # variant: `de-CH` text grouped with U+2019 rather than its own ASCII
  # apostrophe, or `sv` text signed with U+2212, came back in pieces.
  #
  # A character that folds onto both separators' families is left to the
  # separator it is literally, so the classes never overlap.
  defp localize_format_string(string, symbols, language_tag) do
    sets = Lexicon.lenient_sets(language_tag)
    group_sep = extract_separator(symbols.group)
    decimal_sep = extract_separator(symbols.decimal)
    group_family = Lexicon.family(group_sep, sets)
    decimal_family = Lexicon.family(decimal_sep, sets)

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
  defp sign_characters(sets, extra_signs) do
    for sign <- ["-", "+" | extra_signs],
        sign = String.replace(extract_separator(sign), @format_characters, ""),
        character <- Lexicon.family(sign, sets),
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
    {primary, secondary} = Lexicon.grouping_sizes(language_tag, number_system)

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
         {:ok, data_locale_id} <- Localize.Locale.get(language_tag, [:name]) do
      own_locale_data(language_tag, locale_id(language_tag), data_locale_id)
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
