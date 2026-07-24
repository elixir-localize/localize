defmodule Localize.Unit.Inflection do
  @moduledoc false

  alias Localize.Inflection.{Concept, Quantify, SpeakableString}
  alias Localize.Inflection.Locale, as: InflectionLocale

  # Engine-backed grammatical-case fallback for unit patterns.
  #
  # CLDR unit patterns are authoritative: when the requested
  # grammatical case is present in the unit's format data this
  # module is never consulted. When the case key is absent — a
  # locale or unit without CLDR grammar coverage — the formatter
  # would silently fall back to the nominative pattern. With the
  # `:inflect` option enabled, this module instead inflects the
  # nominative pattern text through `Localize.Inflection`:
  #
  # * `inflect: :safe` renders with the engine's guessing
  #   disabled: a form changes only through attested dictionary
  #   paths, an unchanged render falls back to CLDR, and
  #   multi-word literals additionally require every word to be
  #   dictionary-known (`Localize.Inflection.known?/2`). Guessed
  #   forms never reach user-visible output.
  #
  # * `inflect: :always` enables the engine's suffix-exemplar
  #   guessing for dictionary-unknown words (usually right,
  #   occasionally very wrong).
  #
  # Every failure path returns `:no_inflection`, degrading to the
  # formatter's existing nominative fallback.

  @modes [false, :safe, :always]

  @doc """
  Attempts to synthesize a unit pattern for a grammatical case the
  CLDR data does not provide.

  ### Arguments

  * `unit_formats` is the unit's format map (case → plural →
    pattern).

  * `grammatical_case` is the requested case atom.

  * `plural` is the resolved plural category atom.

  * `locale` is a validated `Localize.LanguageTag`, atom or binary.

  * `options` is the formatter option list (`:inflect` is read).

  ### Returns

  * `{:ok, pattern}` with an inflected `[position, literal]`
    pattern, or

  * `:no_inflection` when the feature is off, not needed, or not
    safely possible (the caller uses the normal fallback), or

  * `{:error, exception}` when the `:inflect` option value is
    invalid.

  """
  def maybe_inflect_pattern(unit_formats, grammatical_case, plural, locale, options) do
    case Keyword.get(options, :inflect, false) do
      false ->
        :no_inflection

      mode when mode in @modes ->
        inflect_pattern(unit_formats, grammatical_case, plural, locale, mode)

      invalid ->
        {:error,
         Localize.InvalidValueError.exception(
           value: invalid,
           expected: ":inflect option",
           allowed_values: @modes,
           context: "Localize.Unit"
         )}
    end
  end

  defp inflect_pattern(unit_formats, grammatical_case, plural, locale, mode) do
    if grammatical_case == :nominative or Map.has_key?(unit_formats, grammatical_case) do
      :no_inflection
    else
      with [position, literal] when is_integer(position) and is_binary(literal) <-
             base_pattern(unit_formats, plural),
           {leading, text, trailing} <- split_literal(literal),
           :ok <- confidence_gate(mode, text, locale),
           {:ok, inflected} <- inflect_text(text, locale, grammatical_case, plural, mode) do
        {:ok, [position, leading <> inflected <> trailing]}
      else
        _other -> :no_inflection
      end
    end
  end

  @genders %{
    "masculine" => :masculine,
    "feminine" => :feminine,
    "neuter" => :neuter,
    "common" => :common,
    "inanimate" => :inanimate,
    "animate" => :animate,
    "personal" => :personal
  }

  @doc """
  Resolves the grammatical gender of a simple unit.

  The CLDR `gender` field on the unit's format data is
  authoritative when present. Otherwise the inflection engine
  derives the gender from the nominative singular pattern text,
  but only when that text is dictionary-known — gender metadata
  is never guessed.

  ### Arguments

  * `unit_formats` is the unit's format map.

  * `locale` is a validated `Localize.LanguageTag`, atom or binary.

  * `unit_name` is the normalized unit name, used in errors.

  ### Returns

  * `{:ok, gender}` with a gender atom such as `:masculine`, or
    `{:error, exception}` when neither source can determine it.

  """
  def gender(unit_formats, locale, unit_name) do
    case Map.get(unit_formats, :gender) do
      gender when is_map_key(@genders, gender) ->
        {:ok, Map.fetch!(@genders, gender)}

      _no_data_gender ->
        engine_gender(unit_formats, locale, unit_name)
    end
  end

  defp engine_gender(unit_formats, locale, unit_name) do
    not_found =
      {:error,
       Localize.ItemNotFoundError.exception(
         locale: InflectionLocale.normalize(locale),
         keys: [:grammatical_gender, unit_name]
       )}

    with [_position, literal] when is_binary(literal) <- base_pattern(unit_formats, :one),
         text = String.trim(literal),
         true <- Localize.Inflection.known?(text, locale),
         {:ok, gender} when not is_nil(gender) <-
           Localize.Inflection.feature(text, locale, :gender) do
      {:ok, gender}
    else
      _other -> not_found
    end
  end

  # The nominative :one pattern is the inflection source: its text
  # is the closest to the dictionary lemma, and some synthesizers
  # (Finnish) cannot reinflect from an already-inflected surface
  # form such as the partitive in the :other pattern. The quantify
  # constraints then restore the number the plural category calls
  # for. Other pattern shapes (token lists, bare binaries) are not
  # case-inflectable.
  defp base_pattern(unit_formats, plural) do
    case_forms = Map.get(unit_formats, :nominative) || Map.get(unit_formats, :other)

    if is_map(case_forms) do
      Map.get(case_forms, :one) || Map.get(case_forms, plural) || Map.get(case_forms, :other)
    end
  end

  defp split_literal(literal) do
    text = String.trim(literal)

    if text == "" do
      nil
    else
      [leading, trailing] = String.split(literal, text, parts: 2)
      {leading, text, trailing}
    end
  end

  # Under :safe, rendering runs with guessing disabled (see
  # inflect_text/5), so a single word can never come out mangled —
  # it either inflects through attested dictionary paths or stays
  # unchanged (which bails below). Multi-word phrases additionally
  # require every word to be dictionary-known, because a token
  # chain with a known head and an unknown modifier would inflect
  # only partially and break agreement.
  defp confidence_gate(:always, _text, _locale), do: :ok

  defp confidence_gate(:safe, text, locale) do
    if single_word?(text) or Localize.Inflection.known?(text, locale) do
      :ok
    else
      :skip
    end
  end

  defp single_word?(text), do: not String.contains?(text, [" ", "\u00A0"])

  # In a unit pattern the noun always follows a numeral, so its
  # number and case come from the language's numeral-government
  # rules — exactly what the quantify factories encode (Slavic
  # paucals, the Arabic counted-noun case map, Finnish partitive).
  # The noun is rendered through quantify with a sentinel number
  # and the sentinel stripped, keeping the pattern's own number
  # placement and spacing. Turkic and Ugric languages have no
  # quantify factory upstream (the base factory would pluralize)
  # but require the singular after numerals, so they inflect
  # directly.
  @sentinel "\uE000"
  @singular_after_numeral ~w(az hu kk tr)

  defp inflect_text(text, locale, grammatical_case, plural, mode) do
    internal = InflectionLocale.normalize(locale)
    guess? = mode == :always

    rendered =
      if singular_after_numeral?(internal) do
        direct_noun(text, locale, grammatical_case, guess?)
      else
        quantified_noun(text, locale, grammatical_case, plural, guess?)
      end

    # An unchanged render means the engine had no attested form
    # (guess-free renders pass the value through). The source text
    # is the :one lemma, so splicing it unchanged into a plural
    # slot would be wrong — bail to the CLDR fallback instead.
    case rendered do
      {:ok, inflected} when inflected != text -> {:ok, inflected}
      _unchanged_or_error -> :no_inflection
    end
  end

  defp direct_noun(text, locale, grammatical_case, guess?) do
    with {:ok, concept} <-
           Concept.new(locale, text, constraints: %{case: grammatical_case, number: :singular}) do
      concept = %{concept | guess: guess?}
      {:ok, concept |> Concept.to_speakable_string() |> SpeakableString.print()}
    end
  end

  defp singular_after_numeral?(internal) do
    internal in @singular_after_numeral or
      InflectionLocale.parent(internal) in @singular_after_numeral
  end

  # Joins that do not produce "number space noun" (the Arabic dual
  # carries the count in the noun itself) cannot be spliced into a
  # unit pattern that substitutes the number separately, so they
  # fall back.
  defp quantified_noun(text, locale, grammatical_case, plural, guess?) do
    with {:ok, concept} <- Concept.new(locale, text, constraints: %{case: grammatical_case}),
         concept = %{concept | guess: guess?},
         {:ok, speakable} <-
           Quantify.quantify_formatted(locale, @sentinel, concept, plural: plural) do
      case SpeakableString.print(speakable) do
        @sentinel <> " " <> noun -> {:ok, noun}
        _other_join -> :no_inflection
      end
    end
  end
end
