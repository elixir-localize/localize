defmodule Localize.Number.Parser.Amount do
  @moduledoc """
  The grammar of a currency amount, read from the tokens of
  `Localize.Number.Lexer`, behind
  `Localize.Number.Parser.parse_currency_amount/2`.

  An amount is a number with currency text before it or after it,
  inside the signs, parentheses and spaces that decorate the number.
  The grammar finds the two; the rules below decide what the currency
  text names, which separators the number is read with, and when an
  amount that could be read two ways is refused instead.

  ## Grammar

  ```ebnf
  amount    = outer, [ currency ], inner, number, closing, [ currency ], outer ;
  currency  = text, [ mark ] ;
  number    = digits, { mark | space | digits } ;
  outer     = { space | tab | sign | "(" | ")" } ;
  inner     = outer ;
  closing   = { space | tab | sign | "(" | ")" | mark | dash } ;
  ```

  with at most one `currency`. `number` is the text from the first
  digit to the last, which `Localize.Number.Parser.parse/2` then reads
  with the currency's separators. A `mark` that ends the currency text
  before the digits ("$.50", "kr.5") is the currency's where CLDR
  writes the currency with it, the number's where it is the currency's
  decimal mark, and otherwise refused (`amount_currency/3`).

  The rules, each a named function:

  * **Currency text** names a currency only where one alone takes it,
    after NFKC normalization, with a trailing period tried off as well
    as on (`text_currency/2`).

  * **A caller's currencies** (`:caller_currency`) take text the locale
    does not name; text naming both a CLDR currency and a different one
    of the caller's is refused, except in a locale whose own currency
    it names (`unclaimed_currency/3`, `uncontested_caller_currency/3`).

  * **A caller's word with digits in it**, such as a digital token
    identifier, is the first word or the last, and is read only where
    the amount has no other reading (`caller_word_amounts/3`,
    `one_reading/3`).

  * **No currency** is the `:default_currency`, or a missing-currency
    error (`amount_currency/3`).

  * **The number** is read with the currency's separators and
    `grouping: :sizes`, and three fraction digits in a currency of fewer
    places are refused as a possible thousands group
    (`amount_number/4`, `unambiguous_fraction/3`).

  """

  alias Localize.Number.{Grammar, Lexer, Lexicon, Parser}

  # A sign or parenthesis that opens or closes text with no digits: "(USD)"
  # and "-" are a number's decorations with no number, not currency text.
  @number_decoration ~r/\A[(+\-\x{2212}]|[)+\-\x{2212}]\z/u

  # A word with a letter and a digit, as a digital token's identifier
  # "Q9PB7XDNF" is.
  @letters_and_digits ~r/\A(?=.*\p{L})(?=.*\p{Nd})/us

  # A number of two runs of digits, one to three and then three, parted by
  # one mark: "73,460" or "1.599", in any script's digits, signed or not.
  @group_shape ~r/\A[^\p{Nd}]*\p{Nd}{1,3}[^\p{Nd}]\p{Nd}{3}[^\p{Nd}]*\z/u

  # Unicode's final quotation marks (`Pf`). A mark that closes currency
  # text before the digits is split from it only when it is other
  # punctuation (`Po`), as "$." and "kr." are written.
  @final_marks ~w(» ’ ” › ⸃ ⸅ ⸊ ⸍ ⸝ ⸡)

  @doc false
  # Reads one currency amount. The caller has validated the string and the
  # locale; `options` carries the locale as a language tag.
  @spec read(String.t(), Localize.LanguageTag.t(), Keyword.t()) ::
          {:ok, {Localize.Currency.currency_code() | term(), Decimal.t()}}
          | {:error, Exception.t()}
  def read(string, %Localize.LanguageTag{} = language_tag, options) do
    options = Keyword.put(options, :locale, language_tag)

    with {:ok, number_system} <- Lexicon.number_system(language_tag, string, []),
         {:ok, lexicon} <- Lexicon.fetch(language_tag, number_system, []) do
      tokens = string |> Lexer.tokens(lexicon) |> Enum.reject(&bidi?/1)
      reading = text_amount(tokens, string, options)
      word_readings = caller_word_amounts(tokens, string, options)
      one_reading(reading, word_readings, string)
    end
  end

  defp text_amount(tokens, string, options) do
    with {:ok, parts} <- amount_parts(tokens, string) do
      parts_amount(parts, string, options)
    end
  end

  defp parts_amount(parts, string, options) do
    with {:ok, currency, separators_of, parts} <- amount_currency(parts, string, options),
         {:ok, number} <- amount_number(parts, currency, separators_of, options) do
      {:ok, {currency, number}}
    end
  end

  # ── The grammar ───────────────────────────────────────────────

  # Splits an amount into its currency text and the text of its number,
  # which is everything else: the digits from the first to the last, with
  # the signs, parentheses, spaces and marks around them, all of which
  # `parse/2` reads. The currency text stands before the number or after
  # it, inside those. The parts are strings, as the rules read them.
  defp amount_parts(tokens, string) do
    case Enum.split_while(tokens, &(not digit?(&1))) do
      {_text, []} ->
        currency_without_number(tokens, string)

      {before, from_first_digit} ->
        {rest, digits} = split_after_last_digit(from_first_digit)
        split_amount(before, digits, rest, string)
    end
  end

  defp split_after_last_digit(tokens) do
    {reversed_rest, reversed_digits} =
      tokens
      |> Enum.reverse()
      |> Enum.split_while(&(not digit?(&1)))

    {Enum.reverse(reversed_rest), Enum.reverse(reversed_digits)}
  end

  # Text with no digits is currency text with no number: "" names no
  # currency, as "100" names none, and "USD" names one whose amount cannot
  # be read, as "USD abc" does. A form's empty field is so reported as a
  # missing amount rather than as text that is not money. Text a sign or a
  # parenthesis opens or closes, "(USD)", is not an amount.
  defp currency_without_number(tokens, string) do
    currency = tokens |> text() |> String.trim()

    if String.match?(currency, @number_decoration) do
      {:error, not_an_amount(string)}
    else
      {:ok, %{currency: currency, mark: "", lead: "", rest: ""}}
    end
  end

  defp split_amount(before, digits, rest, string) do
    {lead, prefix, between, mark} = prefix_parts(before)
    {after_digits, suffix, trailing} = decorations(rest, &closing?/1, &decoration?/1)

    if number_core?(digits) and (prefix == [] or suffix == []) do
      {:ok,
       %{
         currency: text(prefix ++ suffix),
         mark: mark,
         lead: text(lead),
         rest: text(between ++ digits ++ after_digits ++ trailing)
       }}
    else
      {:error, not_an_amount(string)}
    end
  end

  # The text before the digits as its leading decorations, the currency
  # text, the decorations between it and the digits, and a mark the
  # currency text ends in where nothing stands between it and the digits.
  # A mark after a space, a sign or "(" is the number's, as in "USD .5".
  defp prefix_parts(before) do
    {lead, prefix, between} = decorations(before, &decoration?/1, &decoration?/1)

    case closing_mark(prefix) do
      {unmarked, mark} when between == [] -> prefix_mark(lead, prefix, unmarked, mark)
      _no_touching_mark -> {lead, prefix, between, ""}
    end
  end

  defp closing_mark(prefix) do
    case List.last(prefix) do
      {:mark, _value, mark} when mark not in @final_marks -> {Enum.drop(prefix, -1), mark}
      _no_mark -> nil
    end
  end

  defp prefix_mark(lead, prefix, unmarked, mark) do
    case decorations(unmarked, &decoration?/1, &decoration?/1) do
      {_lead, currency, []} when currency != [] -> {lead, prefix, [], mark}
      {_lead, currency, spacing} -> {lead, currency, spacing ++ [{:mark, mark, mark}], ""}
    end
  end

  # Tokens as their leading decorations, the tokens between them and their
  # trailing decorations.
  defp decorations(tokens, leading?, trailing?) do
    {leading, rest} = Enum.split_while(tokens, leading?)
    {reversed_trailing, reversed_middle} = rest |> Enum.reverse() |> Enum.split_while(trailing?)
    {leading, Enum.reverse(reversed_middle), Enum.reverse(reversed_trailing)}
  end

  # ── Caller words ──────────────────────────────────────────────

  # A caller's currency text may have digits in it, as a digital token's
  # identifier "Q9PB7XDNF" does, and is then the amount's first word or its
  # last, which a space separates from the number. Each such word the
  # caller's `:caller_currency` function names gives a reading.
  defp caller_word_amounts(tokens, string, options) do
    case Keyword.get(options, :caller_currency) do
      nil -> []
      resolver -> caller_word_amounts(tokens, string, options, resolver)
    end
  end

  defp caller_word_amounts(tokens, string, options, resolver) do
    tokens
    |> caller_words()
    |> Enum.flat_map(fn parts ->
      claim = caller_claim(resolver, parts.currency)
      caller_word_amount(claim, parts, string, options)
    end)
  end

  defp caller_word_amount({:ok, currency}, parts, string, options) do
    [{currency, parts_amount(parts, string, options)}]
  end

  defp caller_word_amount(:none, _parts, _string, _options) do
    []
  end

  defp caller_word_amount({:error, _invalid_option} = error, _parts, _string, _options) do
    [{nil, error}]
  end

  defp caller_words(tokens) do
    trimmed = trim(tokens)

    [first_word(trimmed), last_word(trimmed)]
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&String.match?(&1.currency, @letters_and_digits))
  end

  defp first_word([]) do
    nil
  end

  defp first_word(tokens) do
    {word, rest} = Enum.split_while(tokens, &(not whitespace?(&1)))
    {lead, currency, trailing} = decorations(word, &decoration?/1, &decoration?/1)
    %{currency: text(currency), mark: "", lead: text(lead), rest: text(trailing ++ rest)}
  end

  defp last_word(tokens) do
    {reversed_word, reversed_rest} =
      tokens |> Enum.reverse() |> Enum.split_while(&(not whitespace?(&1)))

    if reversed_rest == [] do
      nil
    else
      {lead, currency, trailing} =
        decorations(Enum.reverse(reversed_word), &closing?/1, &decoration?/1)

      %{
        currency: text(currency),
        mark: "",
        lead: "",
        rest: text(Enum.reverse(reversed_rest) ++ lead ++ trailing)
      }
    end
  end

  # A caller's word is read only where the amount has no other reading:
  # `fr` "USD1 234" is 1 234 US dollars as well as 234 of a token named
  # "USD1", so it is neither. Two such words are not one amount.
  defp one_reading(reading, [], _string) do
    reading
  end

  defp one_reading(_reading, [{nil, {:error, _invalid_option} = error} | _last], _string) do
    error
  end

  defp one_reading({:ok, {currency, _amount}}, [{word_currency, _word_reading}], string) do
    {:error, two_readings(string, currency, word_currency)}
  end

  defp one_reading(_reading, [{_word_currency, word_reading}], _string) do
    word_reading
  end

  defp one_reading(_reading, [_first, _last], string) do
    {:error, not_an_amount(string)}
  end

  # `fr` "LUNA2 234" is 234 of a token whose names are "LUNA" and "LUNA2",
  # and 2 234 of it.
  defp two_readings(string, currency, currency) do
    Localize.ParseError.exception(
      input: string,
      reason: :unexpected_input,
      detail: "it is two amounts of #{inspect(currency)}"
    )
  end

  defp two_readings(string, currency, other) do
    ambiguous_currency(string, currency, other)
  end

  # ── The currency ──────────────────────────────────────────────

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
  # else is not an amount.
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
    language_tag = Keyword.fetch!(options, :locale)
    filters = Keyword.take(options, [:only, :except])
    found = Parser.find_amount_currency(text, language_tag, filters)
    match?([currency] when is_atom(currency), found)
  end

  defp marked_number(parts, unmarked, currency, separators_of, string, options) do
    %{mark: mark, lead: lead, rest: rest} = parts

    if decimal_mark?(mark, rest, separators_of, options) do
      {:ok, currency, separators_of, %{parts | currency: unmarked, lead: lead <> mark}}
    else
      {:error, not_an_amount(string)}
    end
  end

  # A mark is the number's when it is the decimal mark of any set the
  # number is read with, as `fr-CH` "CHF,5" is.
  defp decimal_mark?(mark, number, separators_of, options) do
    language_tag = Keyword.fetch!(options, :locale)

    lexicon_options =
      options
      |> Keyword.take([:separators])
      |> put_separators_currency(separators_of)

    with {:ok, number_system} <- Lexicon.number_system(language_tag, number, options),
         {:ok, lexicon} <- Lexicon.fetch(language_tag, number_system, lexicon_options) do
      Enum.any?(lexicon.readings, &MapSet.member?(&1.decimal, mark))
    end
    |> Kernel.==(true)
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
    filters = Keyword.take(options, [:only, :except, :fuzzy])

    [text, String.trim_trailing(text, ".")]
    |> Enum.uniq()
    |> first_text_currency(text, filters, options)
  end

  defp first_text_currency([candidate | rest], text, filters, options) do
    language_tag = Keyword.fetch!(options, :locale)

    case Parser.find_amount_currency(candidate, language_tag, filters) do
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
  # claims the same text is refused rather than read: `en` "₮5" is neither
  # the tugrik, whose narrow symbol "₮" is, nor Tether, whose symbol it is
  # too.
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
        Map.get(narrow, Lexicon.nfkc(text)) ||
          Map.get(narrow, Lexicon.nfkc(String.trim_trailing(text, ".")))

      {:error, _no_data} ->
        nil
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
    if Lexicon.own_currency(Keyword.get(options, :locale)) == currency do
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

  # ── The number ────────────────────────────────────────────────

  # The number is read as `Localize.Number.Parser.parse/2` reads it, with
  # the lexicon and grammar directly: the string and the locale were
  # validated at the public entry, so the number's text and the language
  # tag are trusted here.
  defp amount_number(%{lead: lead, rest: rest}, currency, separators_of, options) do
    number = String.trim(lead <> rest)
    language_tag = Keyword.fetch!(options, :locale)

    lexicon_options =
      options
      |> Keyword.take([:separators])
      |> put_separators_currency(separators_of)

    read =
      with {:ok, number_system} <- Lexicon.number_system(language_tag, number, options),
           {:ok, lexicon} <- Lexicon.fetch(language_tag, number_system, lexicon_options) do
        Grammar.read(number, lexicon,
          number: :decimal,
          grouping: :sizes,
          max_decimal_exponent: Parser.max_decimal_exponent()
        )
      end

    case read do
      {:ok, decimal} -> unambiguous_fraction(decimal, number, currency)
      {:error, exception} -> {:error, invalid_amount(currency, number, exception)}
    end
  end

  # One to three digits, a decimal mark and three more are a thousands group
  # where the text was written with other separators, and three fraction
  # digits are unusual for a currency with fewer: German "1,599 €" is a fuel
  # price, but a shop writing English separators means 1599. Such an amount
  # is refused, as is the same shape with a period in `fr`. An amount under
  # one, or in a currency of three decimal places or more, has one reading.
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
    decimal.exp < 0 and Decimal.compare(Decimal.abs(decimal), 1) != :lt and
      String.match?(number, @group_shape)
  end

  defp fewer_digits?(currency, places) when is_atom(currency) do
    case Lexicon.currency_places(currency) do
      {:ok, currency_places} -> currency_places < places
      :error -> false
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

  # ── Tokens ────────────────────────────────────────────────────

  defp text(tokens) do
    Enum.map_join(tokens, fn {_kind, _value, source} -> source end)
  end

  defp trim(tokens) do
    tokens
    |> Enum.drop_while(&whitespace?/1)
    |> Enum.reverse()
    |> Enum.drop_while(&whitespace?/1)
    |> Enum.reverse()
  end

  defp bidi?({kind, _value, _source}) do
    kind == :bidi
  end

  defp digit?({kind, _value, _source}) do
    kind in [:digits, :other_digits]
  end

  defp whitespace?({kind, _value, _source}) do
    kind in [:space, :tab]
  end

  # The decorations around a currency text: spaces, signs and parentheses.
  defp decoration?({kind, _value, _source}) do
    kind in [:space, :tab, :open, :close, :minus, :plus]
  end

  # After the digits, also the marks and dashes that may close a number,
  # as in "5.USD" and "5.– CHF".
  defp closing?({kind, _value, _source}) do
    kind in [:space, :tab, :open, :close, :minus, :plus, :mark, :dash]
  end

  # The digits of a number and what may stand between them: spaces and
  # the punctuation of separators, which `parse/2` judges.
  defp number_core?(tokens) do
    Enum.all?(tokens, fn {kind, _value, _source} ->
      kind in [:digits, :other_digits, :space, :mark]
    end)
  end

  # ── Errors ────────────────────────────────────────────────────

  defp ambiguous_currency(text, currency, other) do
    Localize.ParseError.exception(
      input: text,
      reason: :unexpected_input,
      detail: "it names two currencies, #{inspect(currency)} and #{inspect(other)}"
    )
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
end
