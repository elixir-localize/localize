defmodule Localize.Number.Lexicon do
  @moduledoc """
  What the number lexer and grammar know about a locale, computed
  once and cached.

  A lexicon is built for a locale, a number system and the options a
  number is read with (`:currency`, `:separators` and
  `:root_separators` of `Localize.Number.Parser.parse/2`). It holds
  the digits the lexer reads, the characters that read as a minus or
  a plus sign, the dashes that may stand for a zero fraction, and one
  to three *readings*: the separator sets a number is read with, each
  as the characters that fold onto its decimal and group separator
  under CLDR's lenient-parse data, with the grouping sizes of the
  locale the set belongs to.

  Folding the lenient-parse families into these sets is what lets the
  lexer classify a character with one lookup where the parser
  otherwise rewrote the string once per family.

  """

  alias Localize.Number.{Symbol, System}

  defstruct [
    :locale,
    :number_system,
    :digits,
    :minus,
    :plus,
    :dashes,
    :period,
    :marks,
    :readings
  ]

  @typedoc """
  One set of separators a number is read with.

  * `:tag` is the locale whose grouping sizes and separators these are:
    the locale read in, or `und` for `root_separators: true`.

  * `:decimal` and `:group` are the characters that read as that
    separator: the separator itself and every character CLDR's
    lenient-parse data folds onto it.

  * `:space_group?` is `true` where the group separator is a space, in
    which case every space character groups.

  * `:sizes` are the primary and secondary grouping sizes.

  """
  @type reading :: %{
          tag: Localize.LanguageTag.t(),
          decimal: MapSet.t(String.t()),
          group: MapSet.t(String.t()),
          space_group?: boolean(),
          sizes: {pos_integer(), pos_integer()}
        }

  @typedoc """
  A lexicon.

  * `:locale` is the language tag it was built for.

  * `:number_system` is the number system whose digits are read, with
    Latin digits always read too.

  * `:digits` maps each digit character to its Latin digit, the map
    `Localize.Number.Transliterate.transliterate_digits/2` reads.

  * `:minus` and `:plus` are the characters that read as a sign.

  * `:dashes` are the characters that may stand for a zero fraction
    ("5.–") and are not a minus.

  * `:period` is the characters that fold onto a period, for telling a
    foreign decimal point from the locale's separators.

  * `:marks` is every character that is a separator in some reading,
    or folds onto a period: what the lexer reads as a mark without
    consulting Unicode's categories.

  * `:readings` are the separator sets, the locale's own first.

  """
  @type t :: %__MODULE__{
          locale: Localize.LanguageTag.t(),
          number_system: atom(),
          digits: %{String.t() => String.t()},
          minus: MapSet.t(String.t()),
          plus: MapSet.t(String.t()),
          dashes: MapSet.t(String.t()),
          period: MapSet.t(String.t()),
          marks: MapSet.t(String.t()),
          readings: [reading(), ...]
        }

  # The dashes that may stand for a zero fraction, "5.–": the hyphen-minus,
  # U+2010 to U+2015 (the hyphens, figure dash, en and em dashes and the
  # horizontal bar), the minus sign and the small and fullwidth forms.
  @zero_fraction_dashes [
    "-",
    "‐",
    "‑",
    "‒",
    "–",
    "—",
    "―",
    "−",
    "﹘",
    "﹣",
    "－"
  ]

  # `{Rs}` and friends in CLDR's general lenient sets name a script's currency
  # sign rather than a character, so there is nothing to fold them to.
  @compound_pattern ~r/\{.*?\}/u

  @format_characters ~r/\p{Cf}/u

  # Unicode's Bidi_Control characters, as `Localize.Number.Lexer` knows them.
  @bidi_controls ~r/[\x{061C}\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}]/u

  @single_space ~r/^\p{Zs}$/u

  @default_grouping_sizes {3, 3}

  @latin_digits ~w(0 1 2 3 4 5 6 7 8 9)

  @doc """
  Returns the lexicon for a locale, a number system and reading options.

  ### Arguments

  * `language_tag` is a `t:Localize.LanguageTag.t/0`.

  * `number_system` is the number system whose digits are read, as
    `number_system/3` chooses it.

  * `options` is a keyword list of options.

  ### Options

  * `:currency` is a currency code or a `t:Localize.Currency.t/0`. When
    set, the number is read with the separators the currency is
    formatted with and, where the locale formats plain numbers with
    other separators, with those too.

  * `:separators` names the set of separators to read with, `:standard`
    by default.

  * `:root_separators` set to `true` adds the root locale's separators
    as a reading.

  ### Returns

  * `{:ok, lexicon}`, or

  * `{:error, exception}` when the locale has no symbols for the
    number system or the currency is unknown.

  ### Examples

      iex> {:ok, en} = Localize.validate_locale(:en)
      iex> {:ok, lexicon} = Localize.Number.Lexicon.fetch(en, :latn, [])
      iex> [reading] = lexicon.readings
      iex> MapSet.member?(reading.decimal, ".") and MapSet.member?(reading.group, ",")
      true

      iex> {:ok, de_ch} = Localize.validate_locale(:"de-CH")
      iex> {:ok, lexicon} = Localize.Number.Lexicon.fetch(de_ch, :latn, [])
      iex> [reading] = lexicon.readings
      iex> MapSet.member?(reading.group, "'") and MapSet.member?(reading.group, "’")
      true

  """
  @spec fetch(Localize.LanguageTag.t(), atom(), Keyword.t()) ::
          {:ok, t()} | {:error, Exception.t()}
  def fetch(%Localize.LanguageTag{} = language_tag, number_system, options) do
    currency = Keyword.get(options, :currency)
    separators = Keyword.get(options, :separators, :standard)
    root? = Keyword.get(options, :root_separators) == true

    if is_nil(currency) or is_atom(currency) do
      key = {language_tag.cldr_locale_id, number_system, currency, separators, root?}
      cached({:lexicon, key}, fn -> build(language_tag, number_system, options) end)
    else
      build(language_tag, number_system, options)
    end
  end

  @doc """
  Chooses the number system a string's digits are read in.

  The locale's own number system, unless the string is written in
  Latin digits alone, in which case Latin, with the locale's Latin
  separators. `:number_system` in the options overrides the choice.

  ### Arguments

  * `language_tag` is a `t:Localize.LanguageTag.t/0`.

  * `string` is the text to be read.

  * `options` is a keyword list; `:number_system` names a number
    system to read with.

  ### Returns

  * `{:ok, number_system}`, or

  * `{:error, exception}` when the number system has no digits.

  ### Examples

      iex> {:ok, ar_eg} = Localize.validate_locale(:"ar-EG")
      iex> Localize.Number.Lexicon.number_system(ar_eg, "١٢٣", [])
      {:ok, :arab}

      iex> {:ok, ar_eg} = Localize.validate_locale(:"ar-EG")
      iex> Localize.Number.Lexicon.number_system(ar_eg, "123", [])
      {:ok, :latn}

  """
  @spec number_system(Localize.LanguageTag.t(), String.t(), Keyword.t()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def number_system(%Localize.LanguageTag{} = language_tag, string, options) do
    number_system =
      Keyword.get_lazy(options, :number_system, fn ->
        written_number_system(language_tag, string)
      end)

    case System.number_system_digits(number_system) do
      {:ok, _digits} -> {:ok, number_system}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  # CLDR's lenient-parse families for a locale, from the `:number` and
  # `:general` scopes, as `{sample, characters}` pairs. The sets are flat
  # character lists with the one literal hyphen backslash-escaped, so they
  # are unwrapped rather than parsed as UnicodeSets; the `{Rs}`-style
  # compounds of the general scope name no character and are dropped.
  @spec lenient_sets(Localize.LanguageTag.t()) :: [{String.t(), [String.t()]}]
  def lenient_sets(%Localize.LanguageTag{} = language_tag) do
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

  @doc false
  # Every character that folds onto the same sample as `character`, itself
  # included.
  @spec family(String.t(), [{String.t(), [String.t()]}]) :: [String.t()]
  def family("", _sets) do
    []
  end

  def family(character, sets) do
    members =
      Enum.find_value(sets, [], fn {sample, characters} ->
        if character == sample or character in characters do
          [sample | characters]
        end
      end)

    Enum.uniq([character | members])
  end

  @doc false
  # The primary and secondary grouping sizes: the rightmost run in the
  # locale's standard pattern and the one before it. They differ in the
  # Indian system, where `en-IN` patterns as `#,##,##0.###`.
  @spec grouping_sizes(Localize.LanguageTag.t(), atom()) :: {pos_integer(), pos_integer()}
  def grouping_sizes(%Localize.LanguageTag{} = language_tag, number_system) do
    cached({:grouping_sizes, language_tag.cldr_locale_id, number_system}, fn ->
      keys = [:number_formats, number_system, :standard]

      case Localize.Locale.get(language_tag, keys, fallback: true) do
        {:ok, pattern} -> sizes_from_pattern(pattern)
        {:error, _reason} -> @default_grouping_sizes
      end
    end)
  end

  @doc false
  # The digits of a number system mapped to the Latin digits, with the
  # Latin digits themselves, which are read in every system: the map
  # `Localize.Number.Transliterate.transliterate_digits/2` takes.
  @spec digits(atom()) :: %{String.t() => String.t()}
  def digits(number_system) do
    native =
      case System.number_system_digits(number_system) do
        {:ok, digits} -> String.graphemes(digits)
        {:error, _reason} -> @latin_digits
      end

    native
    |> Enum.zip(@latin_digits)
    |> Map.new()
    |> Map.merge(Map.new(Enum.zip(@latin_digits, @latin_digits)))
  end

  @doc false
  # The currency index a currency amount is read with: every string that
  # names one currency of the locale under the `:only` and `:except`
  # filters, NFKC-normalized and downcased, to its code. Built once per
  # locale and filter set and cached, since a filter changes which strings
  # are unambiguous ("kr" names the krone alone among `only: [:NOK]`) and
  # the build walks every currency.
  #
  # A currency amount reads a narrow symbol of another currency than the
  # locale's own only when it is a currency sign that names that currency
  # alone: CLDR writes a narrow symbol where the context makes the currency
  # clear, and elsewhere a letter abbreviation may be another thing. `de-CH`
  # gives the rupiah the narrow symbol "Rp", but a Swiss "15 Rp." is 15
  # Rappen, while `en-AU` "€5" is the euro. A historic currency is read only
  # by its code or its name, since its symbols are reused: a Russian
  # "6 300 Р" is not the ruble of 1991–1998.
  @spec currencies(Localize.LanguageTag.t(), Keyword.t()) ::
          {:ok, %{String.t() => atom()}} | {:error, Exception.t()}
  def currencies(%Localize.LanguageTag{} = language_tag, filters) do
    only = filters |> Keyword.get(:only, :all) |> List.wrap() |> Enum.sort()
    except = filters |> Keyword.get(:except, []) |> List.wrap() |> Enum.sort()
    key = {__MODULE__, {:currencies, language_tag.cldr_locale_id, only, except}}

    case :persistent_term.get(key, nil) do
      nil -> cache_currencies(key, language_tag, filters)
      strings -> {:ok, strings}
    end
  end

  defp cache_currencies(key, language_tag, filters) do
    with {:ok, strings} <- amount_strings(language_tag, own_currency(language_tag), filters) do
      Localize.LiteralMemory.cache(key, strings)
      {:ok, strings}
    end
  end

  defp amount_strings(language_tag, own, filters) do
    locale_id = language_tag.cldr_locale_id

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

      amount_strings =
        strings
        |> Map.drop(foreign ++ Map.keys(historic))
        |> Map.merge(unclaimed)
        |> nfkc_strings()

      {:ok, amount_strings}
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

  @doc false
  # The locale's own currency, or `nil` where it has none.
  @spec own_currency(Localize.LanguageTag.t()) :: atom() | nil
  def own_currency(%Localize.LanguageTag{} = language_tag) do
    case Localize.Currency.currency_from_locale(language_tag) do
      {:ok, currency} -> currency
      {:error, _no_currency} -> nil
    end
  end

  @doc false
  # Currency text as it is matched: NFKC-normalized and downcased, as
  # TR35's loose matching asks, with the bidi controls CLDR writes into a
  # few currency symbols removed (`he` writes the yuan "‎CN¥‎"), since the
  # text they are matched against has had its own removed. Text that is
  # not valid Unicode is matched as it is, and found in no index.
  @spec nfkc(String.t()) :: String.t()
  def nfkc(string) when is_binary(string) do
    case :unicode.characters_to_nfkc_binary(string) do
      normalized when is_binary(normalized) ->
        String.downcase(String.replace(normalized, @bidi_controls, ""))

      _invalid ->
        string
    end
  end

  # ── Building ──────────────────────────────────────────────────

  defp build(language_tag, number_system, options) do
    sets = lenient_sets(language_tag)
    minus = sign_family("-", sets)
    plus = sign_family("+", sets)

    with {:ok, symbol_sets} <- symbol_sets(language_tag, number_system, options) do
      readings = Enum.map(symbol_sets, &reading(&1, number_system))
      period = MapSet.new(family(".", sets))

      {:ok,
       %__MODULE__{
         locale: language_tag,
         number_system: number_system,
         digits: digits(number_system),
         minus: minus,
         plus: plus,
         dashes: MapSet.difference(MapSet.new(@zero_fraction_dashes), minus),
         period: period,
         marks: marks(readings, period),
         readings: readings
       }}
    end
  end

  defp marks(readings, period) do
    Enum.reduce(readings, period, fn reading, marks ->
      marks
      |> MapSet.union(reading.decimal)
      |> MapSet.union(reading.group)
    end)
  end

  # The minus family's sample is "_", Elixir's digit separator, which is
  # never a sign.
  defp sign_family(sign, sets) do
    sign
    |> family(sets)
    |> List.delete("_")
    |> MapSet.new()
  end

  defp reading({tag, symbols}, number_system) do
    sets = lenient_sets(tag)
    group = separator(symbols.group)

    %{
      tag: tag,
      decimal: symbols.decimal |> separator() |> family(sets) |> MapSet.new(),
      group: group |> family(sets) |> MapSet.new(),
      space_group?: String.match?(group, @single_space),
      sizes: grouping_sizes(tag, number_system)
    }
  end

  # The symbol sets a number is read with. An amount of a currency is read
  # with the separators the currency is formatted with and, in the locales
  # that write plain numbers otherwise (`de-AT`, `fr-CH`), with those too.
  # With `root_separators: true` it is read with the root locale's as well,
  # for an amount of something CLDR has no data for, such as a digital
  # token. A set whose separators another already has adds no reading.
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

  @doc false
  # The number symbols a string is read with: the locale's for the number
  # system, with the currency's separators under `:currency` and the set
  # `:separators` names. For the lexicon's readings and for `scan/2`.
  @spec number_symbols(Localize.LanguageTag.t(), atom(), Keyword.t()) ::
          {:ok, Symbol.t()} | {:error, Exception.t()}
  def number_symbols(%Localize.LanguageTag{} = language_tag, number_system, options) do
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

  # CLDR gives a few locales a second set of separators, such as the `:us`
  # set of `en-ZA`. A locale without the requested set reads with its
  # standard one.
  defp variant(%{standard: standard} = separators, name) do
    Map.get(separators, name, standard)
  end

  defp variant(separator, _name) do
    separator
  end

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

  defp currency_for(%Localize.Currency{} = currency, _language_tag) do
    {:ok, currency}
  end

  # Reading needs only the currency's separators, not its display names, so
  # a currency the locale has no names for reads with its parent's data.
  defp currency_for(code, language_tag) do
    Localize.Currency.currency_for_code(code, locale: language_tag, fallback: true)
  end

  defp separator(%{standard: value}) do
    value
  end

  defp separator(value) when is_binary(value) do
    String.replace(value, @format_characters, "")
  end

  defp separator(_other) do
    ""
  end

  # ── Number system ─────────────────────────────────────────────

  # The locale's number system, unless the text is written in Latin digits
  # alone. `ar-EG` writes `arab` digits with ٬ and ٫, and ٫ folds onto ",",
  # so reading typed "100,00" with those separators made it 100.00 and
  # refused "1,234.56". The locale's Latin separators are the ones such
  # text is written with.
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

  # ── Data helpers ──────────────────────────────────────────────

  defp lenient_characters(set) do
    set
    |> String.replace(@compound_pattern, "")
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.replace("\\", "")
    |> String.graphemes()
    |> Enum.reject(&(String.trim(&1) == ""))
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
        secondary = secondary_size(runs, primary)
        {primary, secondary}
    end
  end

  # With a single separator the leading run is the "#" wildcard rather than
  # a group, so the primary size repeats; a second separator is what
  # introduces a distinct secondary size, as in `en-IN`'s `#,##,##0`.
  defp secondary_size([_, _, _ | _] = runs, _primary) do
    runs
    |> Enum.at(-2)
    |> String.length()
  end

  defp secondary_size(_runs, primary) do
    primary
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
end
