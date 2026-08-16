defmodule Localize.Number.Parser do
  @moduledoc """
  Functions for parsing numbers and currencies from strings
  in a locale-aware manner.

  The parser handles locale-specific digit transliteration,
  grouping separators, and decimal separators to convert
  localized number strings back into Elixir numeric values.

  """

  alias Localize.Number.{Symbol, System}

  @type per :: :percent | :permille

  @number_format "[-+]?[0-9]([0-9_]|[,](?=[0-9]))*(\\.?[0-9_]+([eE][-+]?[0-9]+)?)?"

  # TR35's loose matching for lenient parsing says to ignore every character in
  # `[:Zs:]`, and separately to normalize to NFKC, "thus no-break space will map
  # to space". Both readings make the whole space category equivalent here, so a
  # number typed with an ordinary keyboard space parses under a locale that
  # groups with U+202F, and one copied out of formatted output — carrying
  # U+00A0, U+2009 or U+202F — parses anywhere.
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

  # Smallest group a lenient parse will accept after a separator. ICU's own
  # lenient mode uses two, which is the floor that keeps "3 4 5" three numbers.
  @lenient_group_floor 2

  # {primary, secondary} for a locale whose pattern carries no grouping.
  @default_grouping_sizes {3, 3}

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
    least two digits, which is ICU's lenient rule and is what keeps
    `"3 4 5"` three numbers rather than one. `false` requires each
    group to be exactly the locale's grouping size, so `fr` takes
    `"1 234 567"` and refuses `"1 23"`.

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
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, symbols} <- Symbol.number_symbols_for(language_tag),
         {:ok, number_system} <- digits_number_system_from(language_tag, options) do
      symbol = symbols_for_number_system(symbols, number_system)

      scanner =
        @number_format
        |> localize_format_string(symbol, options)
        |> group_lookahead(
          language_tag,
          number_system,
          symbol,
          Keyword.get(options, :lenient, true)
        )
        |> Regex.compile!([:unicode])

      normalized_string = transliterate_digits(string, number_system)

      scanner
      |> Regex.split(normalized_string, include_captures: true, trim: true)
      |> Enum.map(&parse_element(&1, options))
    end
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
    least two digits, which is ICU's lenient rule and is what keeps
    `"3 4 5"` three numbers rather than one. `false` requires each
    group to be exactly the locale's grouping size, so `fr` takes
    `"1 234 567"` and refuses `"1 23"`.

  ### Returns

  * `{:ok, number}` on success.

  * `{:error, exception}` if parsing fails.

  ### Examples

      iex> Localize.Number.Parser.parse("-1_000_000.34")
      {:ok, -1000000.34}

  """
  @spec parse(String.t(), Keyword.t()) ::
          {:ok, integer() | float() | Decimal.t()}
          | {:error, Exception.t()}
  def parse(string, options \\ []) when is_binary(string) and is_list(options) do
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

  # Maximum byte length accepted by `parse/2`. A 1 KB cap fits even
  # very long localised group/decimal-separated representations of a
  # value with hundreds of digits. Override with
  # `config :localize, :max_number_bytes, n`.
  @default_max_number_bytes 1_024

  @doc false
  def max_number_bytes do
    Application.get_env(:localize, :max_number_bytes, @default_max_number_bytes)
  end

  # Maximum absolute value of a parsed Decimal exponent. CLDR-shipped
  # number formats never produce exponents this large; capping here
  # prevents downstream operations (multiplication, formatting) from
  # materialising mantissa-sized work for an attacker-controlled
  # `"1e9999999999"`. Override with
  # `config :localize, :max_decimal_exponent, n`.
  @default_max_decimal_exponent 100

  @doc false
  def max_decimal_exponent do
    Application.get_env(:localize, :max_decimal_exponent, @default_max_decimal_exponent)
  end

  defp do_parse(string, options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, symbols} <- Symbol.number_symbols_for(language_tag),
         {:ok, number_system} <- digits_number_system_from(language_tag, options) do
      symbol = symbols_for_number_system(symbols, number_system)

      lenient? = Keyword.get(options, :lenient, true)

      with {:ok, normalized} <-
             string
             |> transliterate_digits(number_system)
             |> normalize_number_string(symbol, language_tag, number_system, lenient?),
           {:ok, _value} = success <-
             normalized |> String.trim() |> parse_number(Keyword.get(options, :number)) do
        bound_decimal_exponent(success, string)
      else
        _error -> {:error, parse_error(string)}
      end
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

  ### Returns

  * A list with currency strings replaced by currency code atoms.

  ### Examples

      iex> Localize.Number.Parser.scan("100 US dollars")
      ...> |> Localize.Number.Parser.resolve_currencies()
      [100, :USD]

  """
  @spec resolve_currencies([String.t() | number()], Keyword.t()) ::
          list(atom() | String.t() | number())
  def resolve_currencies(list, options \\ []) when is_list(list) do
    resolve(list, &resolve_currency/2, options)
  end

  @doc """
  Resolves a currency from the beginning and/or end of a string.

  ### Arguments

  * `string` is a string potentially containing a currency name or symbol.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `:en`.

  * `:only` is a filter for currencies to include.

  * `:except` is a filter for currencies to exclude.

  * `:fuzzy` is a float for fuzzy matching.

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
  def resolve_currency(string, options \\ []) when is_binary(string) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    only_filter = Keyword.get(options, :only, [:all])
    except_filter = Keyword.get(options, :except, [])
    fuzzy = Keyword.get(options, :fuzzy, nil)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         locale_id <- locale_id(language_tag),
         {:ok, currency_strings} <-
           Localize.Currency.currency_strings(locale_id,
             only: only_filter,
             except: except_filter
           ),
         {:ok, currency} <- find_and_replace(currency_strings, string, fuzzy) do
      currency
    else
      {:error, _} ->
        {:error, Localize.UnknownCurrencyError.exception(currency: string)}
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
          list(per() | String.t() | number())
  def resolve_pers(list, options \\ []) when is_list(list) do
    resolve(list, &resolve_per/2, options)
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
  def resolve_per(string, options \\ []) when is_binary(string) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, symbols} <- Symbol.number_symbols_for(language_tag),
         {:ok, number_system} <- digits_number_system_from(language_tag, options) do
      symbol = symbols_for_number_system(symbols, number_system)

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
  @spec resolve(list(), (String.t(), Keyword.t() -> term()), Keyword.t()) :: list()
  def resolve(list, resolver, options) do
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

  @doc """
  Finds and replaces substrings from a map at the beginning
  and/or end of a string.

  ### Arguments

  * `string_map` is a map of `%{search_string => replacement}`.

  * `string` is the string to search.

  * `fuzzy` is an optional float for fuzzy matching.

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
    if String.trim(string) == "" do
      {:ok, string}
    else
      do_find_and_replace(string_map, string, fuzzy)
    end
  end

  # ── Private helpers ──────────────────────────────────────────

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

  defp normalize_number_string(string, symbols, language_tag, number_system, lenient?) do
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
      |> normalize_spaces(group_sep)

    with :ok <-
           validate_grouping(
             folded,
             group_sep,
             decimal_sep,
             language_tag,
             number_system,
             lenient?
           ) do
      {:ok,
       folded
       |> String.replace(group_sep, "")
       |> String.replace(@spaces, "")
       |> String.replace(decimal_sep, ".")
       # CLDR names the minus set by the sample "_", so folding it yields that
       # placeholder rather than a sign. Restoring it last keeps a minus from
       # being mistaken for a separator while the separators are being removed.
       |> String.replace("_", "-")}
    end
  end

  # Where the locale groups with a space, every space folds onto that separator
  # so the grouping check below can see it. Deleting them instead — which is
  # what makes a stray space harmless in a locale that groups with a comma —
  # would erase the very characters whose positions are being validated.
  defp normalize_spaces(string, group_sep) do
    if String.match?(group_sep, @single_space) do
      String.replace(string, @spaces, group_sep)
    else
      string
    end
  end

  # ── Grouping shape ─────────────────────────────────────────────
  #
  # ICU validates that grouping separators sit in plausible positions, and does
  # so in both of its modes — the two differ only in how strict "plausible" is:
  #
  #   * strict  — every group is exactly the locale's grouping size, so `fr`
  #     takes "1 234 567" and refuses "1 23".
  #
  #   * lenient — every group is at least two digits, so "1 23" is taken but
  #     "3 4" is not.
  #
  # The lenient floor of two is what keeps a space usable as a grouping
  # separator without swallowing adjacent small numbers: "3 4 5" is three
  # numbers in any locale, and no mode reads it as 345.

  defp validate_grouping(string, group_sep, decimal_sep, language_tag, number_system, lenient?) do
    integer_part =
      string
      |> String.split(decimal_sep, parts: 2)
      |> hd()
      |> String.replace(["_", "+"], "")

    case String.split(integer_part, group_sep) do
      # No grouping separator at all: grouping is optional in input.
      [_ungrouped] -> :ok
      groups -> validate_groups(groups, grouping_sizes(language_tag, number_system), lenient?)
    end
  end

  defp validate_groups(groups, {primary, secondary}, lenient?) do
    [leading | rest] = groups
    {last, middle} = List.pop_at(rest, -1)

    valid? =
      cond do
        # A group that is not all digits is not a group at all.
        Enum.any?(groups, &(&1 == "" or not String.match?(&1, @digits_only))) -> false
        lenient? -> Enum.all?(rest, &(String.length(&1) >= @lenient_group_floor))
        String.length(last) != primary -> false
        Enum.any?(middle, &(String.length(&1) != secondary)) -> false
        true -> String.length(leading) <= secondary
      end

    if valid?, do: :ok, else: {:error, :grouping}
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
          if length(runs) >= 3, do: runs |> Enum.at(-2) |> String.length(), else: primary

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
      for scope <- [:number, :general],
          {:ok, sets} <-
            [Localize.Locale.get(language_tag, [:lenient_parse, scope], fallback: true)],
          {sample, set} <- sets,
          characters = lenient_characters(set),
          characters != [],
          do: {:binary.compile_pattern(characters), sample}
    end)
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
        :persistent_term.put(pt_key, value)
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

  defp digits_number_system_from(language_tag, options) do
    number_system =
      Keyword.get_lazy(options, :number_system, fn ->
        case System.number_system_from_locale(language_tag) do
          {:ok, system} -> system
          _ -> :latn
        end
      end)

    case System.number_system_digits(number_system) do
      {:ok, _digits} -> {:ok, number_system}
      {:error, _} = error -> error
    end
  end

  defp symbols_for_number_system(symbols, number_system) do
    Map.get(symbols, number_system) || Map.get(symbols, :latn)
  end

  defp localize_format_string(string, symbols, _options) do
    group_sep = extract_separator(symbols.group)
    decimal_sep = extract_separator(symbols.decimal)

    string
    |> String.replace(",", group_class(group_sep))
    |> String.replace("\\.", "\\" <> decimal_sep)
  end

  # What counts as a grouping separator inside the scanner's character class.
  # Where the locale groups with a space, the whole space category counts, so a
  # number typed with an ordinary keyboard space is found in text that a locale
  # would format with U+202F. The grouping-shape lookahead below is what keeps
  # that from joining unrelated numbers.
  defp group_class(group_sep) do
    if String.match?(group_sep, @single_space), do: "\\p{Zs}", else: group_sep
  end

  # `@number_format` admits a grouping separator whenever a digit follows. That
  # is too permissive once the separator can be a space: it would read "3 4 5"
  # as one number. Requiring a plausible group instead — ICU's rule, two digits
  # leniently or an exact group size strictly — is what makes the wider class
  # safe.
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

  defp do_find_and_replace(string_map, string, nil) do
    canonical = String.downcase(String.trim(string))

    if code = Map.get(string_map, canonical) do
      {:ok, [code]}
    else
      [starting_code, remainder] = starting_string(string_map, string)
      [remainder, ending_code] = ending_string(string_map, remainder)

      if starting_code == "" && ending_code == "" do
        {:error, parse_error("No match was found")}
      else
        {:ok, Enum.reject([starting_code, remainder, ending_code], &(&1 == ""))}
      end
    end
  end

  defp do_find_and_replace(string_map, _search, fuzzy)
       when map_size(string_map) == 0 and is_float(fuzzy) and fuzzy > 0.0 and fuzzy <= 1.0 do
    {:error, parse_error("No match was found")}
  end

  defp do_find_and_replace(string_map, search, fuzzy)
       when is_float(fuzzy) and fuzzy > 0.0 and fuzzy <= 1.0 do
    canonical_search = String.downcase(search)

    {distance, code} =
      string_map
      |> Enum.map(fn {k, v} -> {String.jaro_distance(k, canonical_search), v} end)
      |> Enum.sort(fn {k1, _}, {k2, _} -> k1 > k2 end)
      |> hd()

    if distance >= fuzzy do
      {:ok, [code]}
    else
      {:error, parse_error("No match was found")}
    end
  end

  defp do_find_and_replace(_string_map, _string, fuzzy) do
    {:error,
     Localize.InvalidValueError.exception(
       value: fuzzy,
       expected: "a number > 0.0 and <= 1.0",
       context: "option :fuzzy"
     )}
  end

  defp starting_string(string_map, search) do
    trimmed = String.downcase(String.trim_leading(search))

    matches =
      Enum.filter(string_map, fn {k, _v} -> String.starts_with?(trimmed, k) end)

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
          [code, remainder]
        else
          ["", search]
        end
    end
  end

  defp ending_string(string_map, search) do
    trimmed = String.downcase(String.trim_trailing(search))

    matches =
      Enum.filter(string_map, fn {k, _v} -> String.ends_with?(trimmed, k) end)

    case matches do
      [] ->
        [search, ""]

      list ->
        {match_string, code} = longest_match(list)
        match_length = byte_size(match_string)
        total = byte_size(String.trim_trailing(search))
        keep = total - match_length
        <<remainder::binary-size(^keep), _::binary>> = search
        [remainder, code]
    end
  end

  defp longest_match(matches) do
    matches
    |> Enum.sort(fn {k1, _}, {k2, _} -> String.length(k1) > String.length(k2) end)
    |> hd()
  end

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
