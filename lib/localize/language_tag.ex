defmodule Localize.LanguageTag do
  @moduledoc """
  Represents a language tag as defined in [rfc5646](https://tools.ietf.org/html/rfc5646)
  with extensions "u" and "t" as defined in [BCP 47](https://tools.ietf.org/html/bcp47).

  Language tags are used to help identify languages, whether spoken,
  written, signed, or otherwise signaled, for the purpose of
  communication.  This includes constructed and artificial languages
  but excludes languages not intended primarily for human
  communication, such as programming languages.

  ## Syntax

  A language tag is composed from a sequence of one or more "subtags",
  each of which refines or narrows the range of language identified by
  the overall tag.  Subtags, in turn, are a sequence of alphanumeric
  characters (letters and digits), distinguished and separated from
  other subtags in a tag by a hyphen ("-", [Unicode] U+002D).

  There are different types of subtag, each of which is distinguished
  by length, position in the tag, and content: each subtag's type can
  be recognized solely by these features.  This makes it possible to
  extract and assign some semantic information to the subtags, even if
  the specific subtag values are not recognized.  Thus, a language tag
  processor need not have a list of valid tags or subtags (that is, a
  copy of some version of the IANA Language Subtag Registry) in order
  to perform common searching and matching operations.  The only
  exceptions to this ability to infer meaning from subtag structure are
  the grandfathered tags listed in the productions 'regular' and
  'irregular' below.  These tags were registered under [RFC3066] and
  are a fixed list that can never change.

  The syntax of the language tag in ABNF is:

   Language-Tag  = langtag             ; normal language tags
                 / privateuse          ; private use tag
                 / grandfathered       ; grandfathered tags

   langtag       = language
                   ["-" script]
                   ["-" region]
                   *("-" variant)
                   *("-" extension)
                   ["-" privateuse]

   language      = 2*3ALPHA            ; shortest ISO 639 code
                   ["-" extlang]       ; sometimes followed by
                                       ; extended language subtags
                 / 4ALPHA              ; or reserved for future use
                 / 5*8ALPHA            ; or registered language subtag

   extlang       = 3ALPHA              ; selected ISO 639 codes
                   *2("-" 3ALPHA)      ; permanently reserved

   script        = 4ALPHA              ; ISO 15924 code

   region        = 2ALPHA              ; ISO 3166-1 code
                 / 3DIGIT              ; UN M.49 code

   variant       = 5*8alphanum         ; registered variants
                 / (DIGIT 3alphanum)

   extension     = singleton 1*("-" (2*8alphanum))

                                       ; Single alphanumerics
                                       ; "x" reserved for private use
   singleton     = DIGIT               ; 0 - 9
                 / %x41-57             ; A - W
                 / %x59-5A             ; Y - Z
                 / %x61-77             ; a - w
                 / %x79-7A             ; y - z

   privateuse    = "x" 1*("-" (1*8alphanum))

   grandfathered = irregular           ; non-redundant tags registered
                 / regular             ; during the RFC 3066 era

   irregular     = "en-GB-oed"         ; irregular tags do not match
                 / "i-ami"             ; the 'langtag' production and
                 / "i-bnn"             ; would not otherwise be
                 / "i-default"         ; considered 'well-formed'
                 / "i-enochian"        ; These tags are all valid,
                 / "i-hak"             ; but most are deprecated
                 / "i-klingon"         ; in favor of more modern
                 / "i-lux"             ; subtags or subtag
                 / "i-mingo"           ; combination
                 / "i-navajo"
                 / "i-pwn"
                 / "i-tao"
                 / "i-tay"
                 / "i-tsu"
                 / "sgn-BE-FR"
                 / "sgn-BE-NL"
                 / "sgn-CH-DE"

   regular       = "art-lojban"        ; these tags match the 'langtag'
                 / "cel-gaulish"       ; production, but their subtags
                 / "no-bok"            ; are not extended language
                 / "no-nyn"            ; or variant subtags: their meaning
                 / "zh-guoyu"          ; is defined by their registration
                 / "zh-hakka"          ; and all of these are deprecated
                 / "zh-min"            ; in favor of a more modern
                 / "zh-min-nan"        ; subtag or sequence of subtags
                 / "zh-xiang"

   alphanum      = (ALPHA / DIGIT)     ; letters and numbers

  All subtags have a maximum length of eight characters.  Whitespace is
  not permitted in a language tag.  There is a subtlety in the ABNF
  production 'variant': a variant starting with a digit has a minimum
  length of four characters, while those starting with a letter have a
  minimum length of five characters.

  ## Unicode BCP 47 Extension type "u" - Locale

  Extension | Description                      | Examples
  +-------+ | -------------------------------  | ---------
  ca        | Calendar type                    | buddhist, chinese, gregory
  cf        | Currency format style            | standard, account
  co        | Collation type                   | standard, search, phonetic, pinyin
  cu        | Currency type                    | ISO4217 code like "USD", "EUR"
  fw        | First day of the week identifier | sun, mon, tue, wed, ...
  hc        | Hour cycle identifier            | h12, h23, h11, h24
  lb        | Line break style identifier      | strict, normal, loose
  lw        | Word break identifier            | normal, breakall, keepall, phrase
  ms        | Measurement system identifier    | metric, ussystem, uksystem
  mu        | Measurement unit override        | celsius, fahrenhe, kelvin which overrides the ms key
  nu        | Number system identifier         | arabext, armnlow, roman, tamldec
  rg        | Region override                  | The value is a unicode_region_subtag for a regular region (not a macroregion), suffixed by "ZZZZ"
  sd        | Subdivision identifier           | A unicode_subdivision_id, which is a unicode_region_subtagconcatenated with a unicode_subdivision_suffix.
  ss        | Break suppressions identifier    | none, standard
  tz        | Timezone identifier              | Short identifiers defined in terms of a TZ time zone database
  va        | Common variant type              | POSIX style locale variant

  ## Unicode BCP 47 Extension type "t" - Transforms

  Extension | Description
  +-------+ | -----------------------------------------
  mo        | Transform extension mechanism: to reference an authority or rules for a type of transformation
  s0        | Transform source: for non-languages/scripts, such as fullwidth-halfwidth conversion.
  d0        | Transform sdestination: for non-languages/scripts, such as fullwidth-halfwidth conversion.
  i0        | Input Method Engine transform
  k0        | Keyboard transform
  t0        | Machine Translation: Used to indicate content that has been machine translated
  h0        | Hybrid Locale Identifiers: h0 with the value 'hybrid' indicates that the -t- value is a language that is mixed into the main language tag to form a hybrid
  x0        | Private use transform

  Extensions are formatted by specifying keyword pairs after an extension
  separator. The example `de-DE-u-co-phonebk` specifies German as spoken in
  Germany with a collation of `phonebk`.  Another example, "en-latn-AU-u-cf-account"
  represents English as spoken in Australia, with the number system "latn" but
  formatting currencies with the "accounting" style.
  """
  import Kernel, except: [to_string: 1]

  alias Localize.Locale
  alias Localize.Locale.Provider
  alias Localize.LanguageTag.{Parser, U, T}

  if Code.ensure_loaded?(Jason) do
    @derive Jason.Encoder
  end

  defstruct language: nil,
            language_subtags: [],
            script: nil,
            territory: nil,
            language_variants: [],
            locale: %{},
            transform: %{},
            extensions: %{},
            private_use: [],
            requested_locale_id: nil,
            canonical_locale_id: nil,
            cldr_locale_id: nil

  @type t :: %__MODULE__{
          language: Locale.language(),
          language_subtags: [String.t()],
          script: Locale.script(),
          territory: Locale.territory(),
          language_variants: [String.t()],
          locale: U.t() | %{},
          transform: T.t() | %{},
          extensions: map(),
          private_use: [String.t()],
          requested_locale_id: String.t(),
          canonical_locale_id: String.t(),
          cldr_locale_id: Locale.locale_id()
        }

  @doc """
  Parse a locale identifier into a `t:Localize.LanguageTag` struct.

  ## Arguments

  * `locale_id` is any [BCP 47](https://tools.ietf.org/search/bcp47)
    string.

  ## Returns

  * `{:ok, t:Localize.LanguageTag}` or

  * `{:error, reason}`

  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, {module(), String.t()}}
  def parse(locale_id) when is_binary(locale_id) do
    Parser.parse(locale_id)
  end

  @doc """
  Parse a locale identifier into a `Localize.LanguageTag` struct and raises on error

  ## Arguments

  * `locale_id` is any [BCP 47](https://tools.ietf.org/search/bcp47)
    string.

  ## Returns

  * `t:Localize.LanguageTag` or

  * raises an exception

  """
  @spec parse!(String.t()) :: t() | none()
  def parse!(locale_string) when is_binary(locale_string) do
    Parser.parse!(locale_string)
  end

  @doc """
  Create a fully resolved language tag from a locale string.

  Parses the input, canonicalizes extensions, adds likely subtags
  to populate missing fields, then computes the minimized
  canonical locale name via remove likely subtags. The resulting
  struct has all fields populated but the `canonical_locale_id`
  is the shortest unambiguous form.

  ### Arguments

  * `locale_id` is any BCP 47 locale string.

  ### Returns

  * `{:ok, language_tag}` with all fields resolved, or

  * `{:error, reason}` if parsing, canonicalization, or likely
    subtag resolution fails.

  ### Examples

      iex> {:ok, tag} = Localize.LanguageTag.new("zh-TW")
      iex> tag.language
      :zh
      iex> tag.script
      :Hant
      iex> tag.territory
      :TW
      iex> tag.canonical_locale_id
      "zh-Hant"

  """
  @all_locale_ids Provider.all_locale_ids()

  @spec new(String.t()) :: {:ok, t()} | {:error, term()}
  def new(locale_id) when is_binary(locale_id) do
    with {:ok, parsed} <- parse(locale_id),
         {:ok, canonical} <- canonicalize(parsed),
         {:ok, resolved} <- remove_likely_subtags(canonical) do
      tag = resolve_cldr_locale(resolved)
      {:ok, tag}
    end
  end

  defp resolve_cldr_locale(%__MODULE__{} = tag) do
    case best_match(tag, @all_locale_ids) do
      {:ok, cldr_locale, _score} ->
        %{tag | cldr_locale_id: cldr_locale}

      {:error, _} ->
        tag
    end
  end

  @doc """
  Create a fully resolved language tag, raising on error.

  Same as `new/1` but returns the struct directly or raises
  an exception.

  """
  @spec new!(String.t()) :: t() | no_return()
  def new!(locale_id) when is_binary(locale_id) do
    case new(locale_id) do
      {:ok, tag} -> tag
      {:error, %{__exception__: true} = exception} -> raise exception
      {:error, {exception, reason}} when is_atom(exception) -> raise exception, reason
      {:error, reason} -> raise ArgumentError, "#{inspect(reason)}"
    end
  end

  @doc """
  Produce the canonical locale identifier string from a
  `Localize.LanguageTag` struct.

  The canonical form follows the Unicode CLDR specification
  at [TR35 Locale ID Canonicalization](https://www.unicode.org/reports/tr35/tr35.html#LocaleId_Canonicalization):

  * Language subtag is lowercase.

  * Script subtag is title case.

  * Region subtag is uppercase.

  * All other subtags are lowercase.

  * Variants are sorted alphabetically.

  * Extensions are sorted alphabetically by their singleton.

  * Within extensions, attributes are sorted alphabetically
    and fields are sorted by key.

  * The keyword value `"true"` is removed from the canonical form.

  If the `canonical_locale_id` has already been computed, it
  is returned directly.

  ### Arguments

  * `language_tag` is a `%Localize.LanguageTag{}` struct.

  ### Returns

  * A canonical string representation of the language tag.

  ### Examples

      iex> {:ok, tag} = Localize.LanguageTag.parse("en-US")
      iex> Localize.LanguageTag.to_string(tag)
      "en-US"

  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{canonical_locale_id: name}) when is_binary(name), do: name

  def to_string(%__MODULE__{} = language_tag) do
    build_canonical_name(language_tag)
  end

  @doc """
  Canonicalize a parsed language tag.

  Takes a `%Localize.LanguageTag{}` struct (typically returned
  by `parse/1`) and applies canonical syntax rules:

  * Sorts variants alphabetically.

  * Canonicalizes the `-u-` and `-t-` extension keys.

  * Sorts extensions by their singleton letter.

  * Computes and stores the canonical locale name string.

  ### Arguments

  * `language_tag` is a `%Localize.LanguageTag{}` struct.

  ### Returns

  * `{:ok, canonicalized_tag}` with the `canonical_locale_id`
    field populated, or

  * `{:error, reason}` if extension validation fails.

  ### Examples

      iex> {:ok, tag} = Localize.LanguageTag.parse("en-US-u-nu-arab-ca-gregory")
      iex> {:ok, canonical} = Localize.LanguageTag.canonicalize(tag)
      iex> canonical.canonical_locale_id
      "en-US-u-ca-gregory-nu-arab"

  """
  @spec canonicalize(t()) :: {:ok, t()} | {:error, term()}
  def canonicalize(%__MODULE__{} = language_tag) do
    with {:ok, tag} <- canonicalize_extensions(language_tag) do
      tag =
        tag
        |> resolve_aliases()
        |> sort_variants()
        |> compute_canonical_name()

      {:ok, tag}
    end
  end

  @doc """
  Canonicalize a parsed language tag, raising on error.

  Same as `canonicalize/1` but returns the struct directly
  or raises an exception.

  """
  @spec canonicalize!(t()) :: t() | no_return()
  def canonicalize!(%__MODULE__{} = language_tag) do
    case canonicalize(language_tag) do
      {:ok, tag} -> tag
      {:error, %{__exception__: true} = exception} -> raise exception
      {:error, reason} -> raise ArgumentError, "Failed to canonicalize: #{inspect(reason)}"
    end
  end

  # ── Language matching ──────────────────────────────────────────

  @language_matching Provider.language_matching()
  @language_match_rules Map.fetch!(@language_matching, :language_match)
  @match_variables Map.fetch!(@language_matching, :match_variables)
  @paradigm_locales Map.fetch!(@language_matching, :paradigm_locales) |> MapSet.new()
  @default_distance 80

  @doc """
  Find the best matching supported locale for a desired locale.

  Implements the [CLDR Language Matching](https://www.unicode.org/reports/tr35/tr35.html#LanguageMatching)
  algorithm. The desired locale is compared against each supported
  locale and the closest match (lowest distance score) is returned.

  ### Arguments

  * `desired` is a `%Localize.LanguageTag{}` struct or a BCP 47
    locale string.

  * `supported` is a list of `%Localize.LanguageTag{}` structs
    or BCP 47 locale strings.

  * `distance` is the maximum acceptable distance score. Matches
    with a score above this threshold are rejected.
    The default is #{@default_distance}.

  ### Returns

  * `{:ok, matched_locale, score}` where `matched_locale` is
    the best supported match and `score` is the numeric distance, or

  * `{:error, reason}` if no match is found within the threshold.

  ### Examples

      iex> {:ok, match, _score} = Localize.LanguageTag.best_match("en-AU", ["en", "en-GB", "fr"])
      iex> match
      "en-GB"

  """
  @spec best_match(t() | String.t() | atom(), [t() | String.t() | atom()], non_neg_integer()) ::
          {:ok, t() | String.t() | atom(), non_neg_integer()} | {:error, String.t()}
  def best_match(desired, supported, distance \\ @default_distance)

  def best_match(%__MODULE__{} = desired, supported, distance) when is_list(supported) do
    locale_string = build_canonical_name(desired)
    best_match(locale_string, supported, distance)
  end

  def best_match(desired, supported, distance) when is_atom(desired) and is_list(supported) do
    best_match(Atom.to_string(desired), supported, distance)
  end

  def best_match(desired, supported, distance) when is_binary(desired) and is_list(supported) do
    # Handle bare "und" as desired — return default (first non-und supported)
    # or exact match if "und" is in supported list.
    if desired == "und" do
      best_match_und(supported)
    else
      with {:ok, desired_tag} <- resolve_for_matching(desired, :desired) do
        # Skip "und" in supported — it only matches desired "und" exactly
        matchable_supported =
          supported
          |> Enum.with_index()
          |> Enum.reject(fn {locale, _index} -> locale == "und" end)

        matches =
          matchable_supported
          |> Enum.flat_map(fn {supported_locale, index} ->
            case resolve_for_matching(supported_locale, :supported) do
              {:ok, supported_tag} ->
                score = compute_match_distance(desired_tag, supported_tag)

                if score <= distance do
                  is_paradigm = is_paradigm_locale?(supported_locale)
                  [{supported_locale, supported_tag, score, index, is_paradigm}]
                else
                  []
                end

              {:error, _} ->
                []
            end
          end)
          |> Enum.sort(&match_comparator/2)

        case matches do
          [{locale, _tag, score, _index, _paradigm} | _] ->
            {:ok, locale, score}

          [] ->
            # Default fallback: return first non-und supported locale.
            # The CLDR matching algorithm always returns a result when there
            # are supported locales available.
            case first_non_und(supported) do
              nil ->
                {:error,
                 Localize.LocaleMatchError.exception(desired: desired, threshold: distance)}

              default ->
                {:ok, default, distance}
            end
        end
      end
    end
  end

  defp best_match_und(supported) do
    if "und" in supported do
      {:ok, "und", 0}
    else
      case first_non_und(supported) do
        nil -> {:error, Localize.LocaleMatchError.exception(desired: "und", threshold: 0)}
        default -> {:ok, default, @default_distance}
      end
    end
  end

  defp first_non_und(list) do
    Enum.find(list, fn
      locale when is_binary(locale) -> locale != "und"
      _ -> true
    end)
  end

  @doc """
  Compute the match distance between two locale tags.

  ### Arguments

  * `desired` is a `%Localize.LanguageTag{}` struct or locale string.

  * `supported` is a `%Localize.LanguageTag{}` struct or locale string.

  ### Returns

  * A non-negative integer distance score. `0` is a perfect match.
    Scores below `10` indicate a good fit. Scores above `50`
    indicate a poor fit.

  ### Examples

      iex> Localize.LanguageTag.match_distance("en", "en")
      0

      iex> Localize.LanguageTag.match_distance("en-AU", "en-GB")
      3

  """
  @spec match_distance(t() | String.t(), t() | String.t()) ::
          non_neg_integer() | {:error, String.t()}
  def match_distance(desired, supported) do
    with {:ok, desired_tag} <- resolve_for_matching(desired, :desired),
         {:ok, supported_tag} <- resolve_for_matching(supported, :supported) do
      compute_match_distance(desired_tag, supported_tag)
    end
  end

  # Resolve a locale to a LanguageTag for matching purposes.
  # For "und*" locales used as desired, skip likely subtags to avoid
  # transforming "und" → "en-Latn-US".
  defp resolve_for_matching(%__MODULE__{} = tag, _role), do: {:ok, ensure_maximized(tag)}

  defp resolve_for_matching(locale, :desired) when is_binary(locale) do
    # Bare "und" should not be maximized (it would become en-Latn-US).
    # But "und-TW", "und-Cyrl" etc. should be maximized normally since
    # the "und" language means "fill in from likely subtags".
    if locale == "und" do
      with {:ok, parsed} <- parse(locale),
           {:ok, canonical} <- canonicalize(parsed) do
        {:ok, canonical}
      end
    else
      with {:ok, parsed} <- parse(locale),
           {:ok, canonical} <- canonicalize(parsed),
           {:ok, maximized} <- add_likely_subtags(canonical) do
        {:ok, maximized}
      end
    end
  end

  defp resolve_for_matching(locale, :supported) when is_binary(locale) do
    with {:ok, parsed} <- parse(locale),
         {:ok, canonical} <- canonicalize(parsed),
         {:ok, maximized} <- add_likely_subtags(canonical) do
      {:ok, maximized}
    end
  end

  defp resolve_for_matching(locale, role) when is_atom(locale) do
    resolve_for_matching(Atom.to_string(locale), role)
  end

  defp ensure_maximized(%__MODULE__{script: nil} = tag) do
    case add_likely_subtags(tag) do
      {:ok, maximized} -> maximized
      _ -> tag
    end
  end

  defp ensure_maximized(%__MODULE__{territory: nil} = tag) do
    case add_likely_subtags(tag) do
      {:ok, maximized} -> maximized
      _ -> tag
    end
  end

  defp ensure_maximized(tag), do: tag

  # Compute match distance by processing subtags in three phases.
  defp compute_match_distance(desired, supported) do
    [
      [:language, :script, :territory],
      [:language, :script],
      [:language]
    ]
    |> Enum.reduce(0, fn subtag_keys, acc ->
      desired_fields = extract_subtags(desired, subtag_keys)
      supported_fields = extract_subtags(supported, subtag_keys)
      subtag_distance(desired_fields, supported_fields, acc)
    end)
  end

  # When the last subtag is identical, skip (no additional distance).
  defp subtag_distance([_, _, t], [_, _, t], acc), do: acc
  defp subtag_distance([_, s], [_, s], acc), do: acc
  defp subtag_distance([l], [l], acc), do: acc
  defp subtag_distance(desired, desired, acc), do: acc + 0

  defp subtag_distance(desired, supported, acc) do
    acc + find_match_score(desired, supported)
  end

  defp find_match_score(desired, supported) do
    Enum.reduce_while(@language_match_rules, 0, fn match, _acc ->
      cond do
        rule_matches?(desired, match.desired) and
            rule_matches?(supported, match.supported) ->
          {:halt, match.distance}

        not Map.get(match, :one_way, false) and
          rule_matches?(desired, match.supported) and
            rule_matches?(supported, match.desired) ->
          {:halt, match.distance}

        true ->
          {:cont, 0}
      end
    end)
  end

  # Rule matching with wildcards and match variables.
  defp rule_matches?([lang, _, _], [lang, :*, :*]), do: true
  defp rule_matches?([lang, _], [lang, :*]), do: true
  defp rule_matches?([lang], [lang]), do: true

  defp rule_matches?([lang, _script], [lang, :*]), do: true
  defp rule_matches?([lang, script, _], [lang, script, :*]), do: true
  defp rule_matches?([lang, script], [lang, script]), do: true

  defp rule_matches?([lang, _, territory], [lang, :*, territory]), do: true
  defp rule_matches?([lang, script, territory], [lang, script, territory]), do: true

  # Match variables
  defp rule_matches?([lang, _script, territory], [lang, :*, {:in, variable}]) do
    territory in expand_variable(variable)
  end

  defp rule_matches?([lang, script, territory], [lang, script, {:in, variable}]) do
    territory in expand_variable(variable)
  end

  defp rule_matches?([lang, _script, territory], [lang, :*, {:not_in, variable}]) do
    territory not in expand_variable(variable)
  end

  defp rule_matches?([lang, script, territory], [lang, script, {:not_in, variable}]) do
    territory not in expand_variable(variable)
  end

  # Wildcard catch-all
  defp rule_matches?([_, _, _], [:*, :*, :*]), do: true
  defp rule_matches?([_, _], [:*, :*]), do: true
  defp rule_matches?([_], [:*]), do: true

  defp rule_matches?(_fields, _rule), do: false

  defp expand_variable(variable) do
    Map.fetch!(@match_variables, variable)
  end

  # Extract subtags as atoms for comparison with match rules.
  # The match rules use strings for language but atoms for script/territory,
  # so we convert language to string and keep script/territory as atoms.
  defp extract_subtags(tag, [:language]) do
    [Atom.to_string(tag.language)]
  end

  defp extract_subtags(tag, [:language, :script]) do
    [Atom.to_string(tag.language), tag.script]
  end

  defp extract_subtags(tag, [:language, :script, :territory]) do
    [Atom.to_string(tag.language), tag.script, tag.territory]
  end

  # Sort matches: lower distance first, then paradigm locale preference,
  # then original order.
  defp match_comparator(
         {_, _, distance_a, index_a, paradigm_a},
         {_, _, distance_b, index_b, paradigm_b}
       ) do
    cond do
      distance_a != distance_b -> distance_a < distance_b
      paradigm_a != paradigm_b -> paradigm_a
      true -> index_a < index_b
    end
  end

  defp is_paradigm_locale?(locale) when is_binary(locale) do
    MapSet.member?(@paradigm_locales, locale)
  end

  defp is_paradigm_locale?(_), do: false

  # ── Likely subtags ──────────────────────────────────────────────

  @likely_subtags Provider.likely_subtags()

  @doc """
  Add likely subtags to a language tag.

  Implements the *Add Likely Subtags* algorithm from
  [Unicode TR35](https://www.unicode.org/reports/tr35/tr35.html#Likely_Subtags).
  This fills in missing script and region subtags with the most
  likely values from the CLDR likely subtags data.

  ### Arguments

  * `language_tag` is a `%Localize.LanguageTag{}` struct.

  ### Returns

  * `{:ok, maximized_tag}` with all subtags filled in and
    `canonical_locale_id` updated, or

  * `{:error, reason}` if no likely subtags data is found.

  ### Examples

      iex> {:ok, tag} = Localize.LanguageTag.parse("en")
      iex> {:ok, max} = Localize.LanguageTag.add_likely_subtags(tag)
      iex> max.canonical_locale_id
      "en-Latn-US"

      iex> {:ok, tag} = Localize.LanguageTag.parse("zh-TW")
      iex> {:ok, max} = Localize.LanguageTag.add_likely_subtags(tag)
      iex> max.canonical_locale_id
      "zh-Hant-TW"

  """
  @spec add_likely_subtags(t()) :: {:ok, t()} | {:error, String.t()}
  def add_likely_subtags(%__MODULE__{} = language_tag) do
    language = language_tag.language || :und
    script = strip_sentinel(language_tag.script, :Zzzz)
    region = strip_sentinel(language_tag.territory, :ZZ)

    # If all three are already present and language is not :und, return as-is
    if language != :und and script != nil and region != nil do
      tag = compute_canonical_name(language_tag)
      {:ok, tag}
    else
      # Build string keys for lookup
      lang_str = Atom.to_string(language)
      script_str = if script, do: Atom.to_string(script), else: nil
      region_str = if region, do: Atom.to_string(region), else: nil

      case lookup_likely_subtags(lang_str, script_str, region_str) do
        {:ok, matched} ->
          # Fill in missing fields from the match, converting to atoms.
          matched_lang = to_atom(matched.language)
          matched_script = to_atom(matched.script)
          matched_territory = to_atom(matched.territory)

          tag = %{
            language_tag
            | language: if(language != :und, do: language, else: matched_lang),
              script: script || matched_script,
              territory: region || matched_territory
          }

          {:ok, compute_canonical_name(tag)}

        :error ->
          locale_name = build_canonical_name(language_tag)
          {:error, Localize.LikelySubtagsError.exception(locale: locale_name)}
      end
    end
  end

  @doc """
  Add likely subtags to a language tag, raising on error.

  Same as `add_likely_subtags/1` but returns the struct directly
  or raises an exception.

  """
  @spec add_likely_subtags!(t()) :: t() | no_return()
  def add_likely_subtags!(%__MODULE__{} = language_tag) do
    case add_likely_subtags(language_tag) do
      {:ok, tag} -> tag
      {:error, %{__exception__: true} = exception} -> raise exception
    end
  end

  @doc """
  Remove likely subtags from a language tag.

  Implements the *Remove Likely Subtags* algorithm from
  [Unicode TR35](https://www.unicode.org/reports/tr35/tr35.html#Likely_Subtags),
  using the "favor script" variant.

  This removes script and/or region subtags that can be inferred
  from the remaining subtags using the likely subtags data, producing
  the shortest unambiguous locale identifier.

  ### Arguments

  * `language_tag` is a `%Localize.LanguageTag{}` struct.

  ### Returns

  * `{:ok, minimized_tag}` with redundant subtags removed and
    `canonical_locale_id` updated, or

  * `{:error, reason}` if maximization fails.

  ### Examples

      iex> {:ok, tag} = Localize.LanguageTag.parse("en-Latn-US")
      iex> {:ok, min} = Localize.LanguageTag.remove_likely_subtags(tag)
      iex> min.canonical_locale_id
      "en"

      iex> {:ok, tag} = Localize.LanguageTag.parse("zh-Hant-TW")
      iex> {:ok, min} = Localize.LanguageTag.remove_likely_subtags(tag)
      iex> min.canonical_locale_id
      "zh-Hant"

  """
  @spec remove_likely_subtags(t()) :: {:ok, t()} | {:error, String.t()}
  def remove_likely_subtags(%__MODULE__{} = language_tag) do
    with {:ok, maximized} <- add_likely_subtags(language_tag) do
      max_lang = maximized.language
      max_script = maximized.script
      max_region = maximized.territory

      # Try removing both script and region (language only)
      trial_lang = %{maximized | script: nil, territory: nil}

      minimized_name =
        cond do
          matches_maximized?(trial_lang, max_lang, max_script, max_region) ->
            build_canonical_name(trial_lang)

          # Favor script: try language + script (remove region)
          matches_maximized?(
            %{maximized | territory: nil},
            max_lang,
            max_script,
            max_region
          ) ->
            build_canonical_name(%{maximized | territory: nil})

          # Try language + region (remove script)
          matches_maximized?(
            %{maximized | script: nil},
            max_lang,
            max_script,
            max_region
          ) ->
            build_canonical_name(%{maximized | script: nil})

          true ->
            build_canonical_name(maximized)
        end

      # Return the original tag with maximized fields but minimized canonical name
      {:ok, %{maximized | canonical_locale_id: minimized_name}}
    end
  end

  @doc """
  Remove likely subtags from a language tag, raising on error.

  Same as `remove_likely_subtags/1` but returns the struct directly
  or raises an exception.

  """
  @spec remove_likely_subtags!(t()) :: t() | no_return()
  def remove_likely_subtags!(%__MODULE__{} = language_tag) do
    case remove_likely_subtags(language_tag) do
      {:ok, tag} -> tag
      {:error, %{__exception__: true} = exception} -> raise exception
    end
  end

  # Check if adding likely subtags to a trial tag produces the same
  # maximized language, script, and region.
  defp matches_maximized?(trial, max_lang, max_script, max_region) do
    case add_likely_subtags(trial) do
      {:ok, trial_max} ->
        trial_max.language == max_lang and
          trial_max.script == max_script and
          trial_max.territory == max_region

      {:error, _} ->
        false
    end
  end

  # Lookup likely subtags in the CLDR data.
  # Tries keys in order: lang-script-region, lang-script, lang-region, lang.
  defp lookup_likely_subtags(language, script, region) do
    candidates =
      [
        build_lookup_key(language, script, region),
        build_lookup_key(language, script, nil),
        build_lookup_key(language, nil, region),
        build_lookup_key(language, nil, nil),
        # Fall back to und variants
        if(language != "und", do: build_lookup_key("und", script, region)),
        if(language != "und", do: build_lookup_key("und", script, nil)),
        if(language != "und", do: build_lookup_key("und", nil, region)),
        if(language != "und", do: build_lookup_key("und", nil, nil))
      ]
      |> Enum.reject(&is_nil/1)

    Enum.find_value(candidates, :error, fn key ->
      case Map.get(@likely_subtags, key) do
        nil -> nil
        match -> {:ok, match}
      end
    end)
  end

  defp build_lookup_key(language, nil, nil), do: language
  defp build_lookup_key(language, script, nil), do: "#{language}-#{script}"
  defp build_lookup_key(language, nil, region), do: "#{language}-#{region}"

  defp build_lookup_key(language, script, region),
    do: "#{language}-#{script}-#{region}"

  # Strip sentinel values (Zzzz, ZZ) to nil.
  defp strip_sentinel(nil, _sentinel), do: nil
  defp strip_sentinel(value, sentinel) when value == sentinel, do: nil
  defp strip_sentinel(value, _sentinel), do: value

  # Convert to atom, handling nil, atoms, and strings.
  defp to_atom(nil), do: nil
  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_atom(value)

  # ── Alias resolution ──────────────────────────────────────────────

  @aliases Provider.aliases()
  @language_aliases @aliases[:language]
  @region_aliases @aliases[:region]
  @script_aliases @aliases[:script]
  @variant_aliases @aliases[:variant]

  # Resolve aliased subtags to their canonical replacements.
  #
  # The order follows TR35 Locale ID Canonicalization:
  # 1. Resolve territory aliases (numeric codes, deprecated codes)
  # 2. Resolve simple language aliases (3-letter codes, deprecated codes)
  # 3. Resolve compound language+territory aliases (e.g., "sgn-US" → "ase")
  # 4. Resolve compound language+variant aliases iteratively (e.g., "zh-hakka" → "hak")
  #    Also tries "und-variant" as fallback.
  # 5. Resolve script aliases
  # 6. Resolve variant aliases
  defp resolve_aliases(%__MODULE__{} = tag) do
    tag
    |> resolve_territory_alias()
    |> resolve_simple_language_alias()
    |> resolve_language_territory_alias()
    |> resolve_language_variant_aliases()
    |> resolve_script_alias()
    |> resolve_variant_aliases()
  end

  # Step 2: Simple language alias (e.g., "aar" → "aa", "iw" → "he")
  defp resolve_simple_language_alias(%__MODULE__{language: language} = tag)
       when is_atom(language) do
    lang_str = Atom.to_string(language)

    case Map.get(@language_aliases, lang_str) do
      nil ->
        tag

      replacement ->
        apply_language_replacement(tag, replacement)
    end
  end

  defp resolve_simple_language_alias(tag), do: tag

  # Step 3: Compound language+territory alias (e.g., "sgn-US" → "ase")
  defp resolve_language_territory_alias(%__MODULE__{territory: nil} = tag), do: tag

  defp resolve_language_territory_alias(
         %__MODULE__{language: language, territory: territory} = tag
       )
       when is_atom(language) and is_atom(territory) do
    compound_key = "#{language}-#{territory}"

    case Map.get(@language_aliases, compound_key) do
      nil ->
        tag

      replacement ->
        # Territory was consumed by the compound match — clear it unless
        # the replacement carries its own territory.
        tag = %{tag | territory: nil}
        apply_language_replacement(tag, replacement)
    end
  end

  defp resolve_language_territory_alias(tag), do: tag

  # Step 4: Compound language+variant aliases, applied iteratively.
  # Tries multi-variant compound keys (e.g., "und-hepburn-heploc"),
  # then single-variant keys ("lang-variant"), then "und-variant" as fallback.
  # When matched, the consumed variants are removed from the tag.
  # Repeat until stable (no more matches).
  defp resolve_language_variant_aliases(%__MODULE__{language_variants: []} = tag), do: tag

  defp resolve_language_variant_aliases(%__MODULE__{} = tag) do
    current_lang = Atom.to_string(tag.language)

    # First try multi-variant compound keys (pairs of variants)
    case try_multi_variant_alias(tag, current_lang) do
      {:ok, new_tag} ->
        resolve_language_variant_aliases(new_tag)

      :none ->
        # Then try single-variant compound keys
        {new_tag, changed?} =
          Enum.reduce(tag.language_variants, {tag, false}, fn variant, {acc_tag, changed?} ->
            cur_lang = Atom.to_string(acc_tag.language)
            compound_key = "#{cur_lang}-#{variant}"

            result =
              case Map.get(@language_aliases, compound_key) do
                nil ->
                  und_key = "und-#{variant}"

                  case Map.get(@language_aliases, und_key) do
                    nil -> nil
                    replacement -> {:ok, replacement}
                  end

                replacement ->
                  {:ok, replacement}
              end

            case result do
              nil ->
                {acc_tag, changed?}

              {:ok, replacement} ->
                remaining = Enum.reject(acc_tag.language_variants, &(&1 == variant))
                acc_tag = %{acc_tag | language_variants: remaining}
                {apply_language_replacement(acc_tag, replacement), true}
            end
          end)

        if changed? do
          resolve_language_variant_aliases(new_tag)
        else
          new_tag
        end
    end
  end

  # Try compound keys with two variants: "lang-v1-v2"
  defp try_multi_variant_alias(%__MODULE__{language_variants: variants} = tag, lang_str) do
    pairs =
      for v1 <- variants, v2 <- variants, v1 < v2 do
        {v1, v2}
      end

    Enum.find_value(pairs, :none, fn {v1, v2} ->
      key = "#{lang_str}-#{v1}-#{v2}"

      result =
        case Map.get(@language_aliases, key) do
          nil ->
            und_key = "und-#{v1}-#{v2}"
            Map.get(@language_aliases, und_key)

          replacement ->
            replacement
        end

      if result do
        remaining = Enum.reject(variants, &(&1 in [v1, v2]))
        new_tag = %{tag | language_variants: remaining}
        {:ok, apply_language_replacement(new_tag, result)}
      end
    end)
  end

  # Apply a language alias replacement to a tag, filling in missing subtags.
  defp apply_language_replacement(%__MODULE__{} = tag, %{} = replacement) do
    replacement_lang = replacement.language
    replacement_script = replacement[:script]
    replacement_territory = replacement[:territory]
    replacement_variants = replacement[:language_variants] || []

    # Replace language (unless replacement is "und", meaning keep original)
    tag =
      if replacement_lang != nil and replacement_lang != "und" do
        %{tag | language: to_atom(replacement_lang)}
      else
        tag
      end

    # Fill in script if not already present
    tag =
      if tag.script == nil and replacement_script != nil do
        %{tag | script: to_atom(replacement_script)}
      else
        tag
      end

    # Fill in territory if not already present
    tag =
      if tag.territory == nil and replacement_territory != nil do
        %{tag | territory: to_atom(replacement_territory)}
      else
        tag
      end

    # Add replacement variants if not already present
    tag =
      if replacement_variants != [] do
        existing = tag.language_variants
        new_variants = Enum.reject(replacement_variants, &(&1 in existing))
        %{tag | language_variants: existing ++ new_variants}
      else
        tag
      end

    tag
  end

  defp resolve_script_alias(%__MODULE__{script: nil} = tag), do: tag

  defp resolve_script_alias(%__MODULE__{script: script} = tag) when is_atom(script) do
    script_str = Atom.to_string(script)

    case Map.get(@script_aliases, script_str) do
      nil -> tag
      replacement -> %{tag | script: String.to_atom(replacement)}
    end
  end

  defp resolve_territory_alias(%__MODULE__{territory: nil} = tag), do: tag

  defp resolve_territory_alias(%__MODULE__{territory: territory} = tag)
       when is_atom(territory) do
    territory_str = Atom.to_string(territory)

    case Map.get(@region_aliases, territory_str) do
      nil ->
        tag

      replacement when is_binary(replacement) ->
        %{tag | territory: String.to_atom(replacement)}

      [first | _rest] ->
        # Multiple replacements — use the first one per CLDR spec.
        %{tag | territory: String.to_atom(first)}
    end
  end

  defp resolve_variant_aliases(%__MODULE__{language_variants: []} = tag), do: tag

  defp resolve_variant_aliases(%__MODULE__{language_variants: variants} = tag) do
    resolved =
      Enum.map(variants, fn variant ->
        case Map.get(@variant_aliases, variant) do
          nil -> variant
          replacement -> replacement
        end
      end)

    %{tag | language_variants: resolved}
  end

  # ── Canonicalization helpers ──────────────────────────────────────

  defp sort_variants(%__MODULE__{language_variants: variants} = tag) do
    %{tag | language_variants: Enum.sort(variants)}
  end

  defp canonicalize_extensions(tag) do
    with {:ok, tag} <- U.canonicalize_locale_keys(tag),
         {:ok, tag} <- T.canonicalize_transform_keys(tag) do
      {:ok, tag}
    end
  end

  defp compute_canonical_name(tag) do
    name = build_canonical_name(tag)
    %{tag | canonical_locale_id: name}
  end

  defp build_canonical_name(%__MODULE__{} = tag) do
    basic_parts =
      [tag.language]
      |> maybe_append(tag.language_subtags)
      |> maybe_append_value(tag.script)
      |> maybe_append_value(tag.territory)
      |> maybe_append(Enum.sort(tag.language_variants))

    extension_parts = build_extension_parts(tag)
    private_use_part = format_private_use(tag.private_use)

    (basic_parts ++ extension_parts ++ private_use_part)
    |> Enum.join("-")
  end

  defp build_extension_parts(%__MODULE__{} = tag) do
    extensions =
      [{"t", tag.transform}, {"u", tag.locale}]
      |> Kernel.++(Map.to_list(tag.extensions))
      |> Enum.map(&format_extension/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn part -> part end)

    extensions
  end

  defp format_extension({singleton, extension}) when is_struct(extension) do
    str = Localize.LanguageTag.Chars.to_string(extension)
    if str == "", do: nil, else: "#{singleton}-#{str}"
  end

  defp format_extension({singleton, extension}) when is_map(extension) do
    if extension == %{} do
      nil
    else
      # Raw map (not yet canonicalized) — format keys sorted alphabetically
      parts =
        extension
        |> Enum.sort_by(fn {k, _v} -> k end)
        |> Enum.flat_map(fn
          {key, nil} -> [key]
          {key, "true"} -> [key]
          {key, value} -> [key, value]
        end)

      if parts == [], do: nil, else: "#{singleton}-#{Enum.join(parts, "-")}"
    end
  end

  defp format_extension({_singleton, _other}) do
    nil
  end

  defp maybe_append(parts, []), do: parts
  defp maybe_append(parts, list), do: parts ++ list

  defp maybe_append_value(parts, nil), do: parts
  defp maybe_append_value(parts, value), do: parts ++ [Kernel.to_string(value)]

  defp format_private_use([]), do: []
  defp format_private_use(private_use), do: ["x-" <> Enum.join(private_use, "-")]

  @doc false
  def empty?({_k, ""}), do: true
  def empty?(""), do: true
  def empty?(nil), do: true
  def empty?([]), do: true
  def empty?(_other), do: false

  # This is primarily to support
  # implementing canonical locale names
  defimpl Localize.LanguageTag.Chars, for: Map do
    def to_string(%{}) do
      ""
    end
  end

  defimpl Localize.LanguageTag.Chars, for: Tuple do
    def to_string({k, v}) do
      {k, Localize.LanguageTag.Chars.to_string(v)}
    end
  end

  defimpl Localize.LanguageTag.Chars, for: Atom do
    def to_string(nil) do
      ""
    end

    def to_string(atom) do
      Atom.to_string(atom)
    end
  end

  defimpl Localize.LanguageTag.Chars, for: BitString do
    def to_string(string) do
      string
    end
  end

  defimpl Localize.LanguageTag.Chars, for: List do
    def to_string([]) do
      ""
    end

    def to_string(list) do
      list
      |> Enum.sort()
      |> Enum.join("-")
    end
  end

  defimpl String.Chars do
    def to_string(language_tag) do
      language_tag.canonical_locale_id
    end
  end

  defimpl Inspect do
    def inspect(%Localize.LanguageTag{requested_locale_id: nil} = l, _opts) do
      locale_id =
        Localize.Locale.locale_id_from(l.language, l.script, l.territory, l.language_variants)

      "#Localize.LanguageTag<" <> locale_id <> " [tokenized]>"
    end

    def inspect(%Localize.LanguageTag{canonical_locale_id: nil} = language_tag, _opts) do
      "#Localize.LanguageTag<" <> language_tag.requested_locale_id <> " [parsed]>"
    end

    def inspect(%Localize.LanguageTag{cldr_locale_id: nil} = language_tag, _opts) do
      "#Localize.LanguageTag<" <> language_tag.canonical_locale_id <> " [canonical]>"
    end

    def inspect(%Localize.LanguageTag{} = language_tag, _opts) do
      string = Localize.LanguageTag.to_string(language_tag)

      "Localize.LanguageTag.new!(" <> inspect(string) <> ")"
      # "#Localize.LanguageTag<" <> language_tag.canonical_locale_id <> " [validated]>"
    end
  end
end
