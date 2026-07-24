defmodule Localize.Inflection.Synthesizer.Ar do
  @moduledoc false

  # The Arabic grammar synthesizer, ported from
  # `ArGrammarSynthesizer`. Definiteness is the ال prefix applied
  # inline (no sun/moon letter assimilation — as upstream);
  # possessive pronoun suffixes come from a number+gender+person
  # table; case falls back genitive → accusative → nominative.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{Dictionary, DisplayValue, Inflector, Lookup, Tokenizer}

  import Bitwise

  @locale :ar

  @priorities [
    ["noun", "adjective", "verb"],
    ["third", "second", "first"],
    ["masculine", "feminine"],
    ["singular", "dual", "plural"],
    ["indefinite", "construct", "definite"]
  ]

  @case_fallback %{"genitive" => "accusative", "accusative" => "nominative"}

  @possessive_pronouns %{
    {"dual", "feminine", "second"} => "كما",
    {"dual", "feminine", "third"} => "هما",
    {"dual", "masculine", "second"} => "كما",
    {"dual", "masculine", "third"} => "هما",
    {"plural", "feminine", "first"} => "نا",
    {"plural", "feminine", "second"} => "كن",
    {"plural", "feminine", "third"} => "هن",
    {"plural", "masculine", "first"} => "نا",
    {"plural", "masculine", "second"} => "كم",
    {"plural", "masculine", "third"} => "هم",
    {"singular", "feminine", "first"} => "ي",
    {"singular", "feminine", "second"} => "ك",
    {"singular", "feminine", "third"} => "ها",
    {"singular", "masculine", "first"} => "ي",
    {"singular", "masculine", "second"} => "ك",
    {"singular", "masculine", "third"} => "ه"
  }

  @pronoun_suffixes Enum.uniq(Map.values(@possessive_pronouns))

  @irregular_nouns ["أخ", "أب"]

  @al "ال"
  # AL + tatweel + plain space, unlike the prepositions' no-break
  # space.
  @al_kasheda "الـ "

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("gender", display_value, _constraints) do
    empty_to_nil(
      Lookup.determine(@locale, display_value.display_string, ["masculine", "feminine"],
        disambiguation: ["noun", "adjective", "verb"]
      )
    )
  end

  def feature_value("number", display_value, _constraints) do
    empty_to_nil(
      Lookup.determine(@locale, display_value.display_string, ["singular", "plural", "dual"],
        disambiguation: ["noun", "adjective", "verb"]
      )
    )
  end

  def feature_value("definiteness", display_value, _constraints) do
    determine_definiteness(display_value.display_string)
  end

  def feature_value("withWithPrep", display_value, _constraints) do
    preposition(display_value, "ب", "بـ ")
  end

  def feature_value("withToPrep", display_value, _constraints) do
    display_string = String.trim(display_value.display_string)

    cond do
      display_string == "" ->
        ""

      arabic_first?(display_string) ->
        # ال + ل elides the alef: الكتاب → للكتاب.
        display_string =
          if String.length(display_string) > 3 and String.starts_with?(display_string, @al) do
            String.slice(display_string, 1..-1//1)
          else
            display_string
          end

        "ل" <> display_string

      true ->
        "لـ " <> display_string
    end
  end

  def feature_value("withAsPrep", display_value, _constraints) do
    preposition(display_value, "ك", "كـ ")
  end

  def feature_value("withPossessivePron", display_value, constraints) do
    possessive_pronoun(display_value, constraints)
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  defp preposition(display_value, attached, detached) do
    display_string = String.trim(display_value.display_string)

    cond do
      display_string == "" -> ""
      arabic_first?(display_string) -> attached <> display_string
      true -> detached <> display_string
    end
  end

  defp arabic_first?(string) do
    case String.next_codepoint(string) do
      {first, _rest} -> first =~ ~r/\p{Arabic}/u
      nil -> false
    end
  end

  defp latin_first?(string) do
    case String.next_codepoint(string) do
      {first, _rest} -> first =~ ~r/\p{Latin}/u
      nil -> false
    end
  end

  defp possessive_pronoun(display_value, constraints) do
    count = Map.get(constraints, "numberPronoun")
    gender = Map.get(constraints, "genderPronoun")
    person = Map.get(constraints, "person")
    suffix = Map.get(@possessive_pronouns, {count, gender, person})
    display_string = display_value.display_string

    # ta-marbuta → ta before suffixation, even when no suffix ends
    # up attached.
    display_string =
      if String.length(display_string) > 2 and String.ends_with?(display_string, "ة") do
        String.slice(display_string, 0..-2//1) <> "ت"
      else
        display_string
      end

    attach? =
      suffix != nil and display_string != "" and
        not String.contains?(String.trim(display_string), " ") and
        not latin_first?(display_string) and
        not String.starts_with?(display_string, @al) and
        (not String.ends_with?(display_string, "ي") or display_string in ["أخي", "أبي"])

    if attach? do
      display_string <> suffix
    else
      display_string
    end
  end

  defp determine_definiteness(display_string) do
    if display_string == "" do
      nil
    else
      word_grammemes = Dictionary.combined_grammemes(@locale, display_string) || 0
      proper = Dictionary.binary_properties(@locale, ["proper-noun"]) || 0

      definiteness_mask =
        Dictionary.binary_properties(@locale, ["definite", "indefinite", "construct"]) || 0

      cond do
        (word_grammemes &&& proper) != 0 ->
          "definite"

        (result =
           Lookup.determine(@locale, display_string, ["definite", "indefinite", "construct"])) !=
            "" ->
          result

        (word_grammemes &&& definiteness_mask) != 0 ->
          nil

        String.starts_with?(String.downcase(display_string), @al) ->
          "definite"

        pronoun_suffixed_noun?(display_string) ->
          "definite"

        true ->
          nil
      end
    end
  end

  defp pronoun_suffixed_noun?(display_string) do
    definite_pos = Dictionary.binary_properties(@locale, ["noun", "adjective", "particle"]) || 0

    Enum.any?(@pronoun_suffixes, fn suffix ->
      with true <- String.ends_with?(display_string, suffix),
           prefix =
             binary_part(display_string, 0, byte_size(display_string) - byte_size(suffix)),
           grammemes when is_integer(grammemes) <-
             Dictionary.combined_grammemes(@locale, prefix) do
        (grammemes &&& definite_pos) != 0
      else
        _other -> false
      end
    end)
  end

  # ── Display function ─────────────────────────────────────────

  @impl true
  def display_value(display_data, constraints, _guess?) do
    case List.first(display_data) do
      %DisplayValue{} = first ->
        inflect_display(display_data, first, constraints)

      _other ->
        nil
    end
  end

  defp inflect_display(display_data, first, constraints) do
    case_ = Map.get(constraints, "case", "")
    count = Map.get(constraints, "number", "")
    gender = Map.get(constraints, "gender", "")
    definiteness = Map.get(constraints, "definiteness", "")
    pronoun_count = Map.get(constraints, "numberPronoun", "")
    pronoun_gender = Map.get(constraints, "genderPronoun", "")

    dialog_word = select_value(display_data, first, case_, count, gender, definiteness)

    context = %{
      case: case_,
      mood: Map.get(constraints, "mood", ""),
      count: count,
      tense: Map.get(constraints, "tense", ""),
      person: Map.get(constraints, "person", ""),
      gender: gender,
      animacy: Map.get(constraints, "animacy", ""),
      definiteness: definiteness,
      pos: Map.get(constraints, "pos", ""),
      disambiguation:
        Enum.flat_map(["pos", "mood", "person", "tense"], fn feature ->
          case Map.get(constraints, feature) do
            value when value in [nil, ""] -> []
            value -> [value]
          end
        end)
    }

    inflection =
      if pronoun_count == "" and pronoun_gender == "" do
        inflect_string(dialog_word, context)
      else
        ""
      end

    if inflection == "" do
      display_string = dialog_word

      display_string =
        if definiteness == "definite" and
             not String.contains?(String.trim(dialog_word), " ") do
          definite_article(display_string)
        else
          display_string
        end

      display_string =
        if case_ != "" and display_string in @irregular_nouns do
          display_string <> irregular_case_suffix(case_)
        else
          display_string
        end

      %DisplayValue{display_string: display_string, constraints: constraints}
    else
      inflection =
        if definiteness == "definite" and
             not String.contains?(String.trim(dialog_word), " ") do
          definite_article(inflection)
        else
          inflection
        end

      %DisplayValue{display_string: inflection, constraints: constraints}
    end
  end

  # The LAST matching display value wins.
  defp select_value(display_data, first, case_, count, gender, definiteness) do
    Enum.reduce(display_data, first.display_string, fn value, acc ->
      vc = value.constraints

      matches? =
        (case_ == "" or Map.get(vc, "case") == case_ or not Map.has_key?(vc, "case")) and
          (count == "" or Map.get(vc, "number") == count) and
          (gender == "" or Map.get(vc, "gender") == gender) and
          (definiteness == "" or Map.get(vc, "definiteness") == definiteness or
             (definiteness in ["construct", "definite"] and
                not Map.has_key?(vc, "definiteness")))

      if matches?, do: value.display_string, else: acc
    end)
  end

  defp irregular_case_suffix("nominative"), do: "و"
  defp irregular_case_suffix("genitive"), do: "ي"
  defp irregular_case_suffix("accusative"), do: "ا"
  defp irregular_case_suffix(_case), do: ""

  defp inflect_string(word, context) do
    case Dictionary.combined_grammemes(@locale, word) do
      grammemes when is_integer(grammemes) ->
        perform_inflection(word, grammemes, context)

      nil ->
        tokens = Tokenizer.word_tokens(@locale, word)

        {output, position} =
          Enum.reduce(tokens, {"", 0}, fn token, {output, position} ->
            separator = binary_part(word, position, token.start - position)

            inflected =
              cond do
                token.value in @pronoun_suffixes ->
                  token.value

                (grammemes = Dictionary.combined_grammemes(@locale, token.value)) != nil ->
                  perform_inflection(token.value, grammemes, context)

                true ->
                  # The upstream Arabic tokenizer splits attached
                  # pronoun suffixes; split them here instead.
                  inflect_with_pronoun_suffix(token.value, context)
              end

            {output <> separator <> inflected, token.stop}
          end)

        output <> binary_part(word, position, byte_size(word) - position)
    end
  end

  defp inflect_with_pronoun_suffix(word, context) do
    split =
      Enum.find_value(@pronoun_suffixes, fn suffix ->
        with true <- String.ends_with?(word, suffix),
             stem = binary_part(word, 0, byte_size(word) - byte_size(suffix)),
             grammemes when is_integer(grammemes) <-
               Dictionary.combined_grammemes(@locale, stem) do
          {stem, grammemes, suffix}
        else
          _other -> nil
        end
      end)

    case split do
      nil ->
        perform_inflection(word, 0, context)

      {stem, grammemes, suffix} ->
        perform_inflection(stem, grammemes, context) <> suffix
    end
  end

  defp perform_inflection(word, word_grammemes, context) do
    verb = Dictionary.binary_properties(@locale, ["verb"]) || 0
    determiner = Dictionary.binary_properties(@locale, ["determiner"]) || 0

    pos_mask =
      ["noun", "adjective", "verb", "determiner"]
      |> Enum.map(&(Dictionary.binary_properties(@locale, [&1]) || 0))
      |> Enum.reduce(0, &Bitwise.bor/2)

    verb? = (word_grammemes &&& pos_mask) == verb and verb != 0
    determiner? = (word_grammemes &&& pos_mask) == determiner and determiner != 0

    base =
      [if(context.count != "", do: context.count, else: "singular")] ++
        if(context.gender != "", do: [context.gender], else: []) ++
        if(context.animacy != "", do: [context.animacy], else: []) ++
        if(context.definiteness == "construct", do: ["construct"], else: [])

    case_constraint =
      cond do
        context.case != "" -> [context.case]
        not verb? and not determiner? and context.pos != "verb" -> ["nominative"]
        true -> []
      end

    person_constraint = if context.person != "", do: [context.person], else: []
    constraints = base ++ case_constraint ++ person_constraint

    inflect_with_fallback(word, word_grammemes, constraints, context.disambiguation, verb?)
  end

  defp inflect_with_fallback(word, word_grammemes, constraints, disambiguation, verb?) do
    options = [disambiguation: disambiguation, priorities: @priorities, fallback: false]

    case Inflector.inflect(@locale, word, word_grammemes, constraints, options) do
      {:ok, inflected} ->
        inflected

      :error when verb? ->
        word

      :error ->
        last = List.last(constraints)

        case Map.get(@case_fallback, last) do
          nil ->
            word

          fallback ->
            constraints = List.replace_at(constraints, -1, fallback)
            inflect_with_fallback(word, word_grammemes, constraints, disambiguation, verb?)
        end
    end
  end

  defp definite_article(display_string) do
    trimmed = String.trim(display_string)

    cond do
      trimmed == "" -> display_string
      String.starts_with?(trimmed, @al) -> trimmed
      arabic_first?(trimmed) -> @al <> trimmed
      true -> @al_kasheda <> trimmed
    end
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
