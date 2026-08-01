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

  alias Localize.LanguageTag.{Parser, T, U}
  alias Localize.Locale
  alias Localize.SupplementalData

  # The grandfathered tags of RFC 5646 section 2.1 - a closed list
  # registered under RFC 3066 that can never change. The spellings
  # here use the registry case because that is how the CLDR
  # languageAlias supplemental data keys them; lookups are performed
  # on the downcased form (the grammar only sees downcased input).
  @grandfathered_tags [
    "art-lojban",
    "cel-gaulish",
    "en-GB-oed",
    "i-ami",
    "i-bnn",
    "i-default",
    "i-enochian",
    "i-hak",
    "i-klingon",
    "i-lux",
    "i-mingo",
    "i-navajo",
    "i-pwn",
    "i-tao",
    "i-tay",
    "i-tsu",
    "no-bok",
    "no-nyn",
    "sgn-BE-FR",
    "sgn-BE-NL",
    "sgn-CH-DE",
    "zh-guoyu",
    "zh-hakka",
    "zh-min",
    "zh-min-nan",
    "zh-xiang"
  ]

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
          canonical_locale_id: String.t() | nil,
          cldr_locale_id: Locale.locale_id()
        }

  @doc """
  Parse a locale identifier into a `t:Localize.LanguageTag` struct.

  Calls the internal grammar parser, then validates the language,
  script, and territory subtags against the CLDR validity sets
  before atomising them. Subtags that are grammatically valid but
  not recognised return `{:error, %Localize.InvalidSubtagError{}}`
  — this gates atomisation behind a bounded set so untrusted input
  cannot exhaust the atom table.

  ### Arguments

  * `locale_id` is any [BCP 47](https://tools.ietf.org/search/bcp47)
    string.

  ### Returns

  * `{:ok, t:Localize.LanguageTag}` or

  * `{:error, reason}`

  ### Examples

      iex> {:ok, tag} = Localize.LanguageTag.parse("en-US")
      iex> tag.language
      :en
      iex> tag.territory
      :US

      iex> {:error, error} = Localize.LanguageTag.parse("not a locale")
      iex> is_exception(error)
      true

  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, Exception.t()}
  def parse(locale_id) when is_binary(locale_id) do
    if byte_size(locale_id) > max_locale_id_bytes() do
      {:error, Localize.InvalidLocaleError.exception(locale_id: input_summary(locale_id))}
    else
      with {:ok, map} <- Parser.parse(locale_id),
           resolved = resolve_aliases(map),
           {:ok, validated} <- validate_subtags(resolved) do
        {:ok, struct(__MODULE__, validated)}
      end
    end
  end

  # Maximum byte length accepted by `parse/1` and `new/1`. Even the
  # most extravagant well-formed BCP-47 tag fits in well under this
  # bound; the cap prevents unbounded grammar work on hostile input.
  # Override with `config :localize, :max_locale_id_bytes, n`.
  @default_max_locale_id_bytes 256

  @doc false
  def max_locale_id_bytes do
    Application.get_env(:localize, :max_locale_id_bytes, @default_max_locale_id_bytes)
  end

  # Truncate a too-long input to a short representative form for the
  # error message — never echo the full attacker-controlled binary.
  defp input_summary(binary) when is_binary(binary) do
    head = binary |> binary_part(0, min(32, byte_size(binary)))
    "#{head}… (#{byte_size(binary)} bytes, exceeds #{max_locale_id_bytes()})"
  end

  @doc """
  Parse a locale identifier into a `Localize.LanguageTag` struct and raises on error

  ### Arguments

  * `locale_id` is any [BCP 47](https://tools.ietf.org/search/bcp47)
    string.

  ### Returns

  * `t:Localize.LanguageTag` or

  * raises an exception

  ### Examples

      iex> tag = Localize.LanguageTag.parse!("fr-CA")
      iex> tag.language
      :fr
      iex> tag.territory
      :CA

  """
  @spec parse!(String.t()) :: t() | none()
  def parse!(locale_string) when is_binary(locale_string) do
    case parse(locale_string) do
      {:ok, tag} -> tag
      {:error, exception} -> raise exception
    end
  end

  # Lifts the parser's bare map into a struct, atomising the subtags
  # safely with respect to atom-table growth. Each of language, script,
  # and territory is gated through its respective validity module so
  # atomisation is bounded by the CLDR validity sets. Unknown subtags
  # return `Localize.InvalidSubtagError`.
  @spec validate_subtags(map()) :: {:ok, map()} | {:error, Exception.t()}
  defp validate_subtags(%{} = map) do
    with {:ok, language} <- atomize_language(Map.get(map, :language)),
         {:ok, script} <- atomize_script(Map.get(map, :script)),
         {:ok, territory} <- atomize_territory(Map.get(map, :territory)) do
      {:ok,
       map
       |> Map.put(:language, language)
       |> Map.put(:script, script)
       |> Map.put(:territory, territory)}
    end
  end

  defp atomize_language(nil), do: {:ok, nil}

  defp atomize_language(value) when is_binary(value) do
    case Localize.Validity.Language.validate(value) do
      {:ok, code, _status} ->
        {:ok, String.to_atom(code)}

      {:error, _} ->
        {:error,
         Localize.InvalidSubtagError.exception(
           key: :language,
           value: value,
           reason: :unknown_language
         )}
    end
  end

  defp atomize_script(nil), do: {:ok, nil}
  # Already atomised — comes from supplemental alias data, which mixes
  # string and atom forms. Atoms from that source are part of a curated
  # finite set, so no DOS risk.
  defp atomize_script(value) when is_atom(value), do: {:ok, value}

  defp atomize_script(value) when is_binary(value) do
    case Localize.Validity.Script.validate(value) do
      {:ok, code, _status} ->
        {:ok, code}

      {:error, _} ->
        {:error,
         Localize.InvalidSubtagError.exception(
           key: :script,
           value: value,
           reason: :unknown_script
         )}
    end
  end

  defp atomize_territory(nil), do: {:ok, nil}
  # Already atomised — comes from supplemental alias data, which mixes
  # string and atom forms. Atoms from that source are part of a curated
  # finite set, so no DOS risk.
  defp atomize_territory(value) when is_atom(value), do: {:ok, value}

  defp atomize_territory(value) when is_binary(value) do
    case Localize.Validity.Territory.validate(value) do
      {:ok, code, _status} ->
        {:ok, code}

      {:error, _} ->
        {:error,
         Localize.InvalidSubtagError.exception(
           key: :territory,
           value: value,
           reason: :unknown_territory
         )}
    end
  end

  @doc """
  Create a fully resolved language tag from a locale string.

  Parses the input, canonicalizes extensions, and adds likely
  subtags to populate the `language`, `script`, and `territory`
  fields with the maximized resolution. The `canonical_locale_id`
  is set to the *canonical syntax* of the caller's request — the
  input with aliases replaced and subtags ordered, but neither
  maximized nor minimized — so `"en"` stays `"en"` and `"en-US"`
  stays `"en-US"`. Locale identity and data lookup key off
  `cldr_locale_id`, not `canonical_locale_id`.

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
      "zh-TW"

  """
  @spec new(String.t()) :: {:ok, t()} | {:error, term()}
  def new(locale_id) when is_binary(locale_id) do
    with {:ok, parsed} <- parse(locale_id),
         {:ok, canonical} <- canonicalize(parsed),
         {:ok, resolved} <- remove_likely_subtags(canonical) do
      # `remove_likely_subtags/1` maximizes the subtag fields but leaves
      # `canonical_locale_id` set to the minimized form. Restore the
      # canonical-syntax id computed by `canonicalize/1` so the field
      # faithfully reflects the caller's request (`en` stays `en`,
      # `en-US` stays `en-US`) rather than collapsing to the minimal
      # identity form. Locale identity/data lookup keys off
      # `cldr_locale_id`, not this field.
      tag =
        %{resolved | canonical_locale_id: canonical.canonical_locale_id}
        |> resolve_cldr_locale()

      {:ok, tag}
    end
  end

  defp resolve_cldr_locale(%__MODULE__{} = tag) do
    case best_match(tag, SupplementalData.all_locale_ids()) do
      # A score of 80 or more is the CLDR language-mismatch distance:
      # the best "match" speaks a different language. Another
      # language's data is never the right source for a tag (Klingon
      # must not format with Afar data), so per TR35 the tag falls
      # back to the root locale.
      {:ok, _cldr_locale, score} when score >= 80 ->
        %{tag | cldr_locale_id: :und}

      {:ok, cldr_locale, _score} ->
        %{tag | cldr_locale_id: cldr_locale}

      {:error, _} ->
        %{tag | cldr_locale_id: :und}
    end
  end

  @doc """
  Create a fully resolved language tag, raising on error.

  Same as `new/1` but returns the struct directly or raises
  an exception.

  ### Arguments

  * `locale_id` is any BCP 47 locale string.

  ### Returns

  * A fully resolved `t:Localize.LanguageTag.t/0` struct.

  * Raises an exception if parsing, canonicalization, or likely
    subtag resolution fails.

  ### Examples

      iex> tag = Localize.LanguageTag.new!("zh-TW")
      iex> tag.script
      :Hant
      iex> tag.canonical_locale_id
      "zh-TW"

  """
  @spec new!(String.t()) :: t() | no_return()
  def new!(locale_id) when is_binary(locale_id) do
    case new(locale_id) do
      {:ok, tag} -> tag
      {:error, exception} -> raise exception
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
  def to_string(%__MODULE__{canonical_locale_id: name}) when is_binary(name) do
    name
  end

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
        |> sort_variants()
        |> compute_canonical_name()

      {:ok, tag}
    end
  end

  @doc """
  Canonicalize a parsed language tag, raising on error.

  Same as `canonicalize/1` but returns the struct directly
  or raises an exception.

  ### Arguments

  * `language_tag` is a `%Localize.LanguageTag{}` struct.

  ### Returns

  * The canonicalized tag with the `canonical_locale_id` field
    populated.

  * Raises an exception if extension validation fails.

  ### Examples

      iex> tag = Localize.LanguageTag.parse!("en-US-u-nu-arab-ca-gregory")
      iex> canonical = Localize.LanguageTag.canonicalize!(tag)
      iex> canonical.canonical_locale_id
      "en-US-u-ca-gregory-nu-arab"

  """
  @spec canonicalize!(t()) :: t() | no_return()
  def canonicalize!(%__MODULE__{} = language_tag) do
    case canonicalize(language_tag) do
      {:ok, tag} -> tag
      {:error, exception} -> raise exception
    end
  end

  # ── Language matching ──────────────────────────────────────────

  defp paradigm_locales do
    cached(:paradigm_locales, fn ->
      SupplementalData.language_matching()
      |> Map.fetch!(:paradigm_locales)
      |> MapSet.new()
    end)
  end

  @default_distance 80

  @doc false
  def default_distance, do: @default_distance

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
    the best supported match and `score` is the numeric distance.

  * `{:error, reason}` if no match is found within the threshold.

  ### Fallback behaviour

  When using the default threshold (#{@default_distance}), the CLDR
  algorithm always returns a result when the supported list is
  non-empty — even if the best match is very distant. This
  matches the CLDR specification, which says the algorithm should
  always select a locale rather than fail. The first supported
  locale is returned as a last resort.

  When an explicit threshold below the default is provided, no
  fallback occurs. If nothing matches within the threshold, an
  error is returned. This is useful for strict validation (e.g.
  resolving configuration values) where a distant match would be
  surprising.

  ### Examples

      iex> {:ok, match, _score} = Localize.LanguageTag.best_match("en-AU", ["en", "en-GB", "fr"])
      iex> match
      "en-GB"

      iex> # Strict matching: threshold 0 rejects non-exact matches
      iex> {:error, _} = Localize.LanguageTag.best_match("xyzzy", ["en", "fr"], 0)

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
    # Bare "und" as desired short-circuits to the default-supported
    # selection: it only ever exact-matches "und" in supported, and
    # otherwise yields the first non-und entry.
    if desired == "und" do
      best_match_und(supported)
    else
      with {:ok, desired_tag} <- resolve_for_matching(desired, :desired) do
        desired_tag
        |> compute_match_candidates(supported, distance)
        |> select_best_match(desired, supported, distance)
      end
    end
  end

  # Build the list of {locale, tag, score, index, is_paradigm,
  # is_territory_language} tuples for every supported locale within the
  # distance threshold, sorted by `match_comparator/2`. "und" in
  # supported is skipped (it only exact-matches a desired "und",
  # handled above).
  defp compute_match_candidates(desired_tag, supported, distance) do
    territory_language = territory_language(desired_tag)

    supported
    |> Enum.with_index()
    |> Enum.reject(fn {locale, _index} -> locale == "und" end)
    |> Enum.flat_map(&score_candidate(&1, desired_tag, territory_language, distance))
    |> Enum.sort(&match_comparator/2)
  end

  # Score one supported locale. Returns a one-element list when the
  # distance is within the threshold (so the caller's `flat_map`
  # builds the candidate set), or an empty list otherwise.
  defp score_candidate({supported_locale, index}, desired_tag, territory_language, distance) do
    case resolve_for_matching(supported_locale, :supported) do
      {:ok, supported_tag} ->
        score = compute_match_distance(desired_tag, supported_tag)

        if score <= distance do
          [
            {supported_locale, supported_tag, score, index, paradigm_locale?(supported_locale),
             supported_tag.language == territory_language}
          ]
        else
          []
        end

      {:error, _} ->
        []
    end
  end

  # The predominant language of the desired locale's territory, taken
  # from CLDR likely subtags (`und-LT` -> `lt`). The distance trie
  # scores every candidate that shares the desired script and territory
  # identically — `sgs` (Samogitian, spoken in Lithuania) is exactly 80
  # from `lt`, `lt-LT` and `en-LT` alike — so without a further signal
  # the winner is whichever the caller happened to list first. Preferring
  # the territory's own language picks `lt` over `en-LT`, which is both
  # the better match and stable regardless of list order.
  defp territory_language(%__MODULE__{territory: nil}), do: nil

  defp territory_language(%__MODULE__{territory: territory}) do
    case resolve_for_matching("und-#{territory}", :desired) do
      {:ok, %__MODULE__{language: language}} -> language
      _other -> nil
    end
  end

  # Pick the best candidate (head of the sorted list). When no
  # candidate is within range: a threshold below the default is
  # strict and returns an error; the default threshold falls back
  # to the first non-und supported locale, matching the CLDR
  # algorithm's guarantee that a non-empty supported list always
  # yields a match.
  defp select_best_match([{locale, _tag, score, _idx, _par, _terr} | _], _desired, _supported, _d) do
    {:ok, locale, score}
  end

  defp select_best_match([], desired, _supported, distance) when distance < @default_distance do
    {:error, Localize.LocaleMatchError.exception(desired: desired, threshold: distance)}
  end

  defp select_best_match([], desired, supported, distance) do
    case first_non_und(supported) do
      nil -> {:error, Localize.LocaleMatchError.exception(desired: desired, threshold: distance)}
      default -> {:ok, default, distance}
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
          number() | {:error, String.t()}
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
      with {:ok, parsed} <- parse(locale) do
        canonicalize(parsed)
      end
    else
      with {:ok, parsed} <- parse(locale),
           {:ok, canonical} <- canonicalize(parsed) do
        add_likely_subtags(canonical)
      end
    end
  end

  defp resolve_for_matching(locale, :supported) when is_binary(locale) do
    with {:ok, parsed} <- parse(locale),
         {:ok, canonical} <- canonicalize(parsed) do
      add_likely_subtags(canonical)
    end
  end

  defp resolve_for_matching(locale, role) when is_atom(locale) do
    resolve_for_matching(Atom.to_string(locale), role)
  end

  @dialyzer {:nowarn_function, ensure_maximized: 1}
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

  # Compute match distance using the trie-based lookup.
  defp compute_match_distance(desired, supported) do
    Localize.Locale.DistanceTrie.lookup(
      Atom.to_string(desired.language),
      desired.script,
      desired.territory,
      Atom.to_string(supported.language),
      supported.script,
      supported.territory
    )
  end

  # Sort matches: lower distance first, then paradigm locale preference,
  # then the desired territory's own language, then original order.
  defp match_comparator(
         {_, _, distance_a, index_a, paradigm_a, territory_language_a},
         {_, _, distance_b, index_b, paradigm_b, territory_language_b}
       ) do
    cond do
      distance_a != distance_b -> distance_a < distance_b
      paradigm_a != paradigm_b -> paradigm_a
      territory_language_a != territory_language_b -> territory_language_a
      true -> index_a < index_b
    end
  end

  defp paradigm_locale?(locale) when is_binary(locale) do
    MapSet.member?(paradigm_locales(), locale)
  end

  defp paradigm_locale?(_), do: false

  # ── Likely subtags ──────────────────────────────────────────────

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
  @spec add_likely_subtags(t()) :: {:ok, t()} | {:error, Exception.t()}
  # CLDR likely-subtags maximization: per-subtag presence checks plus
  # matched/unmatched and und/non-und fallback outcomes.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
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

        :error when language != :und ->
          # A valid language with no likely-subtags mapping (e.g. the
          # private-use range `qaa`..`qtz`). Maximization adds
          # nothing; the tag passes through unchanged rather than
          # inheriting the `und` mapping's script and region.
          {:ok, compute_canonical_name(language_tag)}

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

  ### Arguments

  * `language_tag` is a `%Localize.LanguageTag{}` struct.

  ### Returns

  * The maximized tag with all subtags filled in and
    `canonical_locale_id` updated.

  * Raises an exception if no likely subtags data is found.

  ### Examples

      iex> tag = Localize.LanguageTag.parse!("en")
      iex> maximized = Localize.LanguageTag.add_likely_subtags!(tag)
      iex> maximized.canonical_locale_id
      "en-Latn-US"

  """
  @spec add_likely_subtags!(t()) :: t() | no_return()
  @dialyzer {:nowarn_function, add_likely_subtags!: 1}
  def add_likely_subtags!(%__MODULE__{} = language_tag) do
    case add_likely_subtags(language_tag) do
      {:ok, tag} -> tag
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Remove likely subtags from a language tag.

  Implements the *Remove Likely Subtags* algorithm from
  [Unicode TR35](https://www.unicode.org/reports/tr35/tr35.html#Likely_Subtags),
  supporting both the "favor script" (default) and "favor region"
  variants.

  This removes script and/or region subtags that can be inferred
  from the remaining subtags using the likely subtags data, producing
  the shortest unambiguous locale identifier.

  ### Arguments

  * `language_tag` is a `%Localize.LanguageTag{}` struct.

  * `options` is a keyword list of options.

  ### Options

  * `:favor` selects which subtag survives when either the script
    or the region alone is enough to identify the locale: `:script`
    (the default) keeps the script, `:region` keeps the region.

  ### Returns

  * `{:ok, minimized_tag}` with redundant subtags removed and
    `canonical_locale_id` updated, or

  * `{:error, reason}` if maximization fails or `:favor` is invalid.

  ### Examples

      iex> {:ok, tag} = Localize.LanguageTag.parse("en-Latn-US")
      iex> {:ok, min} = Localize.LanguageTag.remove_likely_subtags(tag)
      iex> min.canonical_locale_id
      "en"

      iex> {:ok, tag} = Localize.LanguageTag.parse("zh-Hant-TW")
      iex> {:ok, min} = Localize.LanguageTag.remove_likely_subtags(tag)
      iex> min.canonical_locale_id
      "zh-Hant"

      iex> {:ok, tag} = Localize.LanguageTag.parse("zh-Hant-TW")
      iex> {:ok, min} = Localize.LanguageTag.remove_likely_subtags(tag, favor: :region)
      iex> min.canonical_locale_id
      "zh-TW"

  """
  @spec remove_likely_subtags(t(), Keyword.t()) :: {:ok, t()} | {:error, Exception.t()}
  def remove_likely_subtags(language_tag, options \\ [])

  def remove_likely_subtags(%__MODULE__{} = language_tag, options) do
    with {:ok, favor} <- validate_favor(Keyword.get(options, :favor, :script)),
         {:ok, maximized} <- add_likely_subtags(language_tag) do
      {:ok, %{maximized | canonical_locale_id: minimized_name(maximized, favor)}}
    end
  end

  # The favor variant decides which subtag survives when either the
  # script or the territory alone round-trips through maximization:
  # :script tries dropping the territory first (keeping the script),
  # :region tries dropping the script first (keeping the territory).
  defp minimized_name(maximized, favor) do
    {second_attempt, third_attempt} =
      case favor do
        :script -> {[territory: nil], [script: nil]}
        :region -> {[script: nil], [territory: nil]}
      end

    with :no_match <- try_minimal_form(maximized, script: nil, territory: nil),
         :no_match <- try_minimal_form(maximized, second_attempt),
         :no_match <- try_minimal_form(maximized, third_attempt) do
      build_canonical_name(maximized)
    else
      {:match, name} -> name
    end
  end

  defp validate_favor(favor) when favor in [:script, :region] do
    {:ok, favor}
  end

  defp validate_favor(favor) do
    {:error,
     Localize.InvalidValueError.exception(
       value: favor,
       expected: :favor,
       allowed_values: [:script, :region]
     )}
  end

  # Build a trial tag by nilling the given fields, check whether it
  # re-maximizes to the same lang/script/region triple, and if so return
  # its canonical name. Order of attempts in the caller encodes the
  # preference (e.g. favor script over region).
  defp try_minimal_form(maximized, overrides) do
    trial = struct(maximized, overrides)

    if matches_maximized?(trial, maximized.language, maximized.script, maximized.territory) do
      {:match, build_canonical_name(trial)}
    else
      :no_match
    end
  end

  @doc """
  Remove likely subtags from a language tag, raising on error.

  Same as `remove_likely_subtags/2` but returns the struct directly
  or raises an exception.

  ### Arguments

  * `language_tag` is a `%Localize.LanguageTag{}` struct.

  * `options` is a keyword list of options.

  ### Options

  * `:favor` selects which subtag survives when either the script
    or the region alone is enough to identify the locale: `:script`
    (the default) keeps the script, `:region` keeps the region.

  ### Returns

  * The minimized tag with redundant subtags removed and
    `canonical_locale_id` updated.

  * Raises an exception if maximization fails or `:favor` is
    invalid.

  ### Examples

      iex> tag = Localize.LanguageTag.parse!("zh-Hant-TW")
      iex> minimized = Localize.LanguageTag.remove_likely_subtags!(tag)
      iex> minimized.canonical_locale_id
      "zh-Hant"

  """
  @spec remove_likely_subtags!(t(), Keyword.t()) :: t() | no_return()
  @dialyzer {:nowarn_function, remove_likely_subtags!: 2}
  def remove_likely_subtags!(%__MODULE__{} = language_tag, options \\ []) do
    case remove_likely_subtags(language_tag, options) do
      {:ok, tag} -> tag
      {:error, exception} -> raise exception
    end
  end

  # Check if adding likely subtags to a trial tag produces the same
  # maximized language, script, and region.
  @dialyzer {:nowarn_function, matches_maximized?: 4}
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
    # Per TR35 (Likely Subtags, Lookup) the candidate list for a
    # non-und language is language-based only. Falling back to the
    # `und` entries for an unmatched language would fabricate
    # subtags — CLDR's test data marks e.g. `qaa-Cyrl` as FAIL, not
    # `qaa-Cyrl-RU` via und-Cyrl. The und-based candidates apply
    # only when the source language itself is `und`.
    candidates =
      [
        build_lookup_key(language, script, region),
        build_lookup_key(language, script, nil),
        build_lookup_key(language, nil, region),
        build_lookup_key(language, nil, nil)
      ]
      |> Enum.reject(&is_nil/1)

    likely_subtags = SupplementalData.likely_subtags()

    Enum.find_value(candidates, :error, fn key ->
      case Map.get(likely_subtags, key) do
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

  defp language_aliases,
    do: cached(:language_aliases, fn -> SupplementalData.aliases()[:language] end)

  defp region_aliases, do: cached(:region_aliases, fn -> SupplementalData.aliases()[:region] end)
  defp script_aliases, do: cached(:script_aliases, fn -> SupplementalData.aliases()[:script] end)

  defp variant_aliases,
    do: cached(:variant_aliases, fn -> SupplementalData.aliases()[:variant] end)

  # Resolve aliased subtags to their canonical replacements on the
  # bare parser-output map (strings, before atomisation). This must
  # run before `validate_subtags/1` so deprecated aliases like "dut"
  # → "nl" get rewritten before the validity gate, which only knows
  # about current CLDR-registered codes.
  #
  # The order follows TR35 Locale ID Canonicalization:
  # 0. Resolve grandfathered tags to their modern replacements
  # 1. Resolve territory aliases (numeric codes, deprecated codes)
  # 2. Resolve simple language aliases (3-letter codes, deprecated codes)
  # 3. Resolve compound language+territory aliases (e.g., "sgn-US" → "ase")
  # 4. Resolve compound language+variant aliases iteratively (e.g., "zh-hakka" → "hak")
  #    Also tries "und-variant" as fallback.
  # 5. Resolve script aliases
  # 6. Resolve variant aliases
  defp resolve_aliases(%{} = map) do
    map
    |> resolve_grandfathered_tag()
    |> resolve_territory_alias()
    |> resolve_simple_language_alias()
    |> resolve_language_territory_alias()
    |> resolve_language_variant_aliases()
    |> resolve_script_alias()
    |> resolve_variant_aliases()
  end

  # Step 0: Grandfathered tags. The grammar surfaces a grandfathered
  # tag as `grandfathered: [irregular: tag]` (or `regular:`) with no
  # other subtag fields, so the replacement subtags are installed
  # wholesale. Every grandfathered tag has a replacement in the CLDR
  # languageAlias data - including the four with no BCP 47 preferred
  # value, which CLDR maps anyway (cel-gaulish → xtg, i-default → en,
  # i-enochian → und, i-mingo → see). Should a future data release
  # ever drop an entry, the tag degrades to the root language "und"
  # rather than producing an empty tag.
  defp resolve_grandfathered_tag(%{grandfathered: [{_class, tag}]} = map) do
    map = Map.delete(map, :grandfathered)

    case Map.get(grandfathered_aliases(), tag) do
      %{language: language} = replacement ->
        %{
          map
          | language: language,
            script: replacement.script,
            territory: replacement.territory,
            language_variants: replacement.language_variants
        }

      nil ->
        %{map | language: "und"}
    end
  end

  defp resolve_grandfathered_tag(map), do: map

  # Maps each downcased grandfathered tag to its CLDR languageAlias
  # replacement (a map of language/script/territory/language_variants).
  defp grandfathered_aliases do
    cached(:grandfathered_aliases, fn ->
      aliases = language_aliases()

      Map.new(@grandfathered_tags, fn tag ->
        {String.downcase(tag), Map.get(aliases, tag)}
      end)
    end)
  end

  # Step 2: Simple language alias (e.g., "aar" → "aa", "iw" → "he")
  defp resolve_simple_language_alias(%{language: nil} = map), do: map

  defp resolve_simple_language_alias(%{language: language} = map) when is_binary(language) do
    case Map.get(language_aliases(), language) do
      nil -> map
      replacement -> apply_language_replacement(map, replacement)
    end
  end

  defp resolve_simple_language_alias(map), do: map

  # Step 3: Compound language+territory alias (e.g., "sgn-US" → "ase")
  defp resolve_language_territory_alias(%{territory: nil} = map), do: map

  defp resolve_language_territory_alias(%{language: language, territory: territory} = map)
       when is_binary(language) and is_binary(territory) do
    compound_key = "#{language}-#{territory}"

    case Map.get(language_aliases(), compound_key) do
      nil ->
        map

      replacement ->
        # Territory was consumed by the compound match — clear it unless
        # the replacement carries its own territory.
        map = %{map | territory: nil}
        apply_language_replacement(map, replacement)
    end
  end

  defp resolve_language_territory_alias(map), do: map

  # Step 4: Compound language+variant aliases, applied iteratively.
  # Tries multi-variant compound keys (e.g., "und-hepburn-heploc"),
  # then single-variant keys ("lang-variant"), then "und-variant" as fallback.
  # When matched, the consumed variants are removed from the map.
  # Repeat until stable (no more matches).
  defp resolve_language_variant_aliases(%{language_variants: []} = map), do: map

  defp resolve_language_variant_aliases(%{language: language} = map) when is_binary(language) do
    # First try multi-variant compound keys (pairs of variants)
    case try_multi_variant_alias(map, language) do
      {:ok, new_map} ->
        resolve_language_variant_aliases(new_map)

      :none ->
        {new_map, changed?} =
          Enum.reduce(map.language_variants, {map, false}, &try_single_variant_alias/2)

        if changed? do
          resolve_language_variant_aliases(new_map)
        else
          new_map
        end
    end
  end

  defp resolve_language_variant_aliases(map), do: map

  # Try `lang-variant` then fall back to `und-variant`. On a hit, drop the
  # consumed variant from the map and apply the replacement.
  defp try_single_variant_alias(variant, {acc_map, changed?}) do
    compound_key = "#{acc_map.language}-#{variant}"

    replacement =
      Map.get(language_aliases(), compound_key) ||
        Map.get(language_aliases(), "und-#{variant}")

    case replacement do
      nil ->
        {acc_map, changed?}

      replacement ->
        remaining = Enum.reject(acc_map.language_variants, &(&1 == variant))
        acc_map = %{acc_map | language_variants: remaining}
        {apply_language_replacement(acc_map, replacement), true}
    end
  end

  # Try compound keys with two variants: "lang-v1-v2"
  defp try_multi_variant_alias(%{language_variants: variants} = map, lang_str) do
    pairs =
      for v1 <- variants, v2 <- variants, v1 < v2 do
        {v1, v2}
      end

    Enum.find_value(pairs, :none, fn {v1, v2} ->
      key = "#{lang_str}-#{v1}-#{v2}"

      result =
        case Map.get(language_aliases(), key) do
          nil ->
            und_key = "und-#{v1}-#{v2}"
            Map.get(language_aliases(), und_key)

          replacement ->
            replacement
        end

      if result do
        remaining = Enum.reject(variants, &(&1 in [v1, v2]))
        new_map = %{map | language_variants: remaining}
        {:ok, apply_language_replacement(new_map, result)}
      end
    end)
  end

  # Apply a language alias replacement to the map, filling in missing
  # subtags. Replacement values are strings (from supplemental data).
  defp apply_language_replacement(%{} = map, %{} = replacement) do
    replacement_lang = replacement.language
    replacement_script = replacement[:script]
    replacement_territory = replacement[:territory]
    replacement_variants = replacement[:language_variants] || []

    # Replace language (unless replacement is "und", meaning keep original)
    map =
      if replacement_lang != nil and replacement_lang != "und" do
        %{map | language: replacement_lang}
      else
        map
      end

    # Fill in script if not already present
    map =
      if Map.get(map, :script) == nil and replacement_script != nil do
        Map.put(map, :script, replacement_script)
      else
        map
      end

    # Fill in territory if not already present
    map =
      if Map.get(map, :territory) == nil and replacement_territory != nil do
        Map.put(map, :territory, replacement_territory)
      else
        map
      end

    # Add replacement variants if not already present
    if replacement_variants != [] do
      existing = map.language_variants
      new_variants = Enum.reject(replacement_variants, &(&1 in existing))
      %{map | language_variants: existing ++ new_variants}
    else
      map
    end
  end

  defp resolve_script_alias(%{script: nil} = map), do: map

  defp resolve_script_alias(%{script: script} = map) when is_binary(script) do
    case Map.get(script_aliases(), script) do
      nil -> map
      replacement -> %{map | script: replacement}
    end
  end

  defp resolve_script_alias(map), do: map

  defp resolve_territory_alias(%{territory: nil} = map), do: map

  defp resolve_territory_alias(%{territory: territory} = map) when is_binary(territory) do
    case Map.get(region_aliases(), territory) do
      nil ->
        map

      replacement when is_binary(replacement) ->
        %{map | territory: replacement}

      [_ | _] = replacements ->
        %{map | territory: disambiguate_territory_replacement(map, replacements)}
    end
  end

  defp resolve_territory_alias(map), do: map

  # TR35 Annex C ("Territory Exception"): when a territory alias has
  # multiple replacement values, use the most likely territory for the
  # base language (and script, when present) if it appears in the
  # replacement list; otherwise the first entry. `hy-SU` resolves to
  # `hy-AM` because the likely territory for `hy` is AM, while
  # `und-SU` resolves to `und-RU` (the first entry).
  defp disambiguate_territory_replacement(map, [first | _] = replacements) do
    with language when is_binary(language) <- Map.get(map, :language),
         %{territory: likely} when not is_nil(likely) <-
           likely_territory_entry(language, Map.get(map, :script)),
         likely = Kernel.to_string(likely),
         true <- likely in replacements do
      likely
    else
      _ -> first
    end
  end

  defp likely_territory_entry(language, script) do
    likely_subtags = SupplementalData.likely_subtags()

    (script && Map.get(likely_subtags, build_lookup_key(language, script, nil))) ||
      Map.get(likely_subtags, build_lookup_key(language, nil, nil))
  end

  defp resolve_variant_aliases(%{language_variants: []} = map), do: map

  defp resolve_variant_aliases(%{language_variants: variants} = map) do
    resolved =
      Enum.map(variants, fn variant ->
        case Map.get(variant_aliases(), variant) do
          nil -> variant
          replacement -> replacement
        end
      end)

    %{map | language_variants: resolved}
  end

  # ── Canonicalization helpers ──────────────────────────────────────

  defp sort_variants(%__MODULE__{language_variants: variants} = tag) do
    %{tag | language_variants: Enum.sort(variants)}
  end

  defp canonicalize_extensions(tag) do
    with {:ok, tag} <- U.canonicalize_locale_keys(tag) do
      T.canonicalize_transform_keys(tag)
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
      # Raw map (not yet canonicalized) — format keys sorted alphabetically.
      # A raw `-t-` extension stores its transform source under the
      # "language" key; per BCP47 the tlang is rendered first and
      # without its key.
      {transform_language, fields} = Map.pop(extension, "language")

      parts =
        fields
        |> Enum.sort_by(fn {k, _v} -> k end)
        |> Enum.flat_map(fn
          {key, nil} -> [key]
          {key, "true"} -> [key]
          {key, value} -> [key, format_extension_value(value)]
        end)

      parts =
        if transform_language do
          [format_extension_value(transform_language) | parts]
        else
          parts
        end

      if parts == [], do: nil, else: "#{singleton}-#{Enum.join(parts, "-")}"
    end
  end

  defp format_extension({_singleton, _other}) do
    nil
  end

  # Raw extension values may be multi-part lists (e.g. a `-u-` value
  # like ["islamic", "civil"]) or a tokenized LanguageTag (the raw
  # `-t-` transform source). Both must render as their hyphenated
  # canonical string form.
  defp format_extension_value(%__MODULE__{} = language_tag) do
    __MODULE__.to_string(language_tag)
  end

  defp format_extension_value(list) when is_list(list) do
    Enum.join(list, "-")
  end

  defp format_extension_value(value) do
    value
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

  # Lazily caches a derived value in `:persistent_term`. Used to
  # replace compile-time module attributes that previously pulled
  # from `SupplementalData`, so this module no longer has compile-
  # time dependencies on it.
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
