defmodule Localize.Inflection.Synthesizer.Ru do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  # The Russian grammar synthesizer, ported from
  # `RuGrammarSynthesizer` and `RussianExposableMorphology`.
  # Every significant word of a phrase is inflected (right to
  # left), with suffix-exemplar guessing for unknown words and
  # four phonologically-conditioned preposition selectors.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{
    Articles,
    Data,
    Dictionary,
    DisplayValue,
    Inflector,
    Lookup,
    PhraseProperties,
    Tokenizer
  }

  import Bitwise

  @locale :ru

  @genders ["feminine", "masculine", "neuter"]
  @animacies ["animate", "inanimate"]
  @numbers ["singular", "plural"]

  @priorities [
    ["proper-noun", "noun", "adjective", "verb"],
    ["nominative", "genitive", "dative", "accusative", "instrumental", "prepositional"],
    ["masculine", "feminine", "neuter"],
    ["singular", "plural"],
    ["inanimate", "animate"],
    ["informal"]
  ]

  @ignore_sets [["proper-noun", "plural"]]

  @do_not_inflect ~w(августа апреля декабря июля июня марта мая мин ноября октября сентября февраля января)

  @in_words ~w(мне что)
  @with_words ~w(всем всеми всех всяким всякими всяких всяческим всяческими вторник вторника второго вторых многих мной мною)
  @to_words ~w(всему всякому всяческому вторнику второму мне многим многому)

  @max_suffix_length 5

  # Russian letters (with ё) for inflectable-character checks.
  @russian_chars ~r/^[а-яё\-\s]+$/iu

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("gender", display_value, _constraints) do
    empty_to_nil(Lookup.determine(@locale, display_value.display_string, @genders))
  end

  def feature_value("animacy", display_value, _constraints) do
    empty_to_nil(Lookup.determine(@locale, display_value.display_string, @animacies))
  end

  def feature_value("aboutPrep", display_value, _constraints) do
    Articles.create_preposition(display_value, about_preposition(display_value), false)
  end

  def feature_value("withAboutPrep", display_value, _constraints) do
    derived_or(display_value, "aboutPrep", &about_preposition/1)
  end

  def feature_value("inPrep", display_value, _constraints) do
    Articles.create_preposition(display_value, in_preposition(display_value), false)
  end

  def feature_value("withInPrep", display_value, _constraints) do
    derived_or(display_value, "inPrep", &in_preposition/1)
  end

  def feature_value("withPrep", display_value, _constraints) do
    Articles.create_preposition(display_value, with_preposition(display_value), false)
  end

  def feature_value("withWithPrep", display_value, _constraints) do
    derived_or(display_value, "withPrep", &with_preposition/1)
  end

  def feature_value("toPrep", display_value, _constraints) do
    Articles.create_preposition(display_value, to_preposition(display_value), false)
  end

  def feature_value("withToPrep", display_value, _constraints) do
    derived_or(display_value, "toPrep", &to_preposition/1)
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  defp derived_or(display_value, derived_feature, preposition_fun) do
    article =
      Map.get(display_value.constraints, derived_feature) || preposition_fun.(display_value)

    Articles.create_preposition(display_value, article, true)
  end

  # ── Preposition selection ────────────────────────────────────

  defp about_preposition(display_value) do
    display_string = display_value.display_string
    lowercased = String.downcase(display_string)

    cond do
      String.starts_with?(lowercased, ["вс", "рт", "мн"]) -> "обо"
      PhraseProperties.starts_with_vowel?(@locale, display_string) -> "об"
      true -> "о"
    end
  end

  # Case-sensitive on the raw string, as upstream.
  defp in_preposition(display_value) do
    display_string = display_value.display_string

    if display_string in @in_words or String.starts_with?(display_string, ["мног", "множ"]) or
         starts_with_two_consonants?(display_string, ~w(в ф р)) do
      "во"
    else
      "в"
    end
  end

  defp with_preposition(display_value) do
    display_string = display_value.display_string
    lowercased = String.downcase(display_string)

    cond do
      display_string == "" ->
        "с"

      lowercased in @with_words or String.starts_with?(lowercased, "щ") or
        starts_with_two_consonants?(lowercased, ~w(с ж з ш)) or
          String.starts_with?(lowercased, "вч") ->
        "со"

      true ->
        "с"
    end
  end

  defp to_preposition(display_value) do
    if String.downcase(display_value.display_string) in @to_words, do: "ко", else: "к"
  end

  defp starts_with_two_consonants?(word, first_letters) do
    case String.next_codepoint(word) do
      nil ->
        false

      {first, rest} when rest != "" ->
        if String.downcase(first) in first_letters do
          {second, _rest} = String.next_codepoint(rest)
          <<c2::utf8>> = second
          not PhraseProperties.default_vowel?(c2)
        else
          false
        end

      _single ->
        false
    end
  end

  # ── Display function ─────────────────────────────────────────

  @impl true
  def display_value(display_data, constraints, guess?) do
    case List.first(display_data) do
      %DisplayValue{} = display_value -> apply_display(display_value, constraints, guess?)
      _other -> nil
    end
  end

  defp apply_display(display_value, constraints, guess?) do
    display_string = display_value.display_string

    case_ = remap_case(Map.get(constraints, "case", ""))
    count = Map.get(constraints, "number", "")
    gender = Map.get(constraints, "gender", "")
    animacy = Map.get(constraints, "animacy", "")
    pos = Map.get(constraints, "pos", "")

    constraint_values = constraint_vector(case_, count, gender, animacy)

    if constraint_values == [] or not russian_text?(display_string) do
      display_value
    else
      inflected =
        inflect_pipeline(
          display_string,
          case_,
          count,
          gender,
          animacy,
          pos,
          constraint_values,
          guess?
        )

      case inflected do
        "" -> display_value
        result -> %DisplayValue{display_string: result, constraints: constraints}
      end
    end
  end

  defp inflect_pipeline(
         display_string,
         case_,
         count,
         gender,
         animacy,
         pos,
         constraint_values,
         guess?
       ) do
    whole =
      case Dictionary.combined_grammemes(@locale, display_string) do
        nil ->
          ""

        phrase_type ->
          inflect_using_dictionary(display_string, phrase_type, constraint_values, pos) || ""
      end

    {whole, suffix_result} =
      if whole == "" and case_ == "prepositional" do
        static_suffix(display_string, constraint_values)
      else
        {whole, ""}
      end

    if whole != "" do
      whole
    else
      body =
        binary_part(display_string, 0, byte_size(display_string) - byte_size(suffix_result))

      tokens = Tokenizer.word_tokens(@locale, body)

      {count, gender} = deduce_count_gender(tokens, count, gender)

      animacy =
        with "" <- animacy,
             "accusative" <- case_,
             %{value: head} <- List.last(tokens),
             grammemes when is_integer(grammemes) <- Dictionary.combined_grammemes(@locale, head) do
          single_of(grammemes, @animacies)
        else
          _other -> animacy
        end

      deduced = constraint_vector(case_, count, gender, animacy)

      case inflect_phrase(body, tokens, deduced, pos, guess?) do
        "" -> ""
        result -> result <> suffix_result
      end
    end
  end

  defp remap_case("ablative"), do: "instrumental"
  defp remap_case("locative"), do: "prepositional"
  defp remap_case(case_), do: case_

  defp constraint_vector(case_, count, gender, animacy) do
    Enum.reject([case_, count, gender, animacy], &(&1 == ""))
  end

  # Inflectable = contains Russian letters, and no non-Russian
  # Cyrillic (Ukrainian/Serbian text must not be inflected with
  # Russian data).
  defp russian_text?(display_string) do
    String.match?(display_string, ~r/[а-яё]/iu) and
      not String.match?(String.replace(display_string, ~r/[а-яё]/iu, ""), ~r/\p{Cyrillic}/u)
  end

  defp inflectable?(word) do
    String.match?(word, @russian_chars) and String.downcase(word) not in @do_not_inflect
  end

  defp inflect_using_dictionary(word, phrase_type, constraint_values, pos) do
    cond do
      not inflectable?(word) ->
        word

      phrase_type == 0 ->
        nil

      true ->
        options = [
          disambiguation: if(pos == "", do: [], else: [pos]),
          priorities: @priorities,
          ignore: @ignore_sets
        ]

        case Inflector.inflect_word(@locale, word, phrase_type, constraint_values, options) do
          {:ok, inflected} ->
            inflected

          :error ->
            lowercased = String.downcase(word)

            with true <- lowercased != word,
                 {:ok, inflected} <-
                   Inflector.inflect_word(
                     @locale,
                     lowercased,
                     phrase_type,
                     constraint_values,
                     options
                   ) do
              restore_case(word, inflected)
            else
              _other -> nil
            end
        end
    end
  end

  defp restore_case(original, inflected) do
    if original == String.upcase(original) and original != String.downcase(original) do
      String.upcase(inflected)
    else
      {first, _rest} = String.split_at(original, 1)
      {_ifirst, irest} = String.split_at(inflected, 1)
      first <> irest
    end
  end

  # Suffix-exemplar guessing: find a dictionary word declining the
  # same way as the unknown word's ending, inflect it, and splice
  # the unknown word's stem onto the inflected ending.
  defp guess_inflection(word, constraint_values, pos) do
    if String.length(word) <= 2 or not inflectable?(word) do
      nil
    else
      exemplars = Data.metadata!(@locale).suffix_exemplars
      length = String.length(word)

      Enum.find_value(min(@max_suffix_length, length)..1//-1, fn suffix_length ->
        suffix = String.slice(word, length - suffix_length, suffix_length)

        with [exemplar | _rest] <- Map.get(exemplars, suffix, []),
             grammemes when is_integer(grammemes) <-
               Dictionary.combined_grammemes(@locale, exemplar),
             inflected when is_binary(inflected) <-
               inflect_using_dictionary(exemplar, grammemes, constraint_values, pos) do
          splice(word, exemplar, inflected)
        else
          _other -> nil
        end
      end)
    end
  end

  defp splice(word, exemplar, inflected) do
    common = common_prefix_length(inflected, exemplar)
    stem_length = String.length(word) - (String.length(exemplar) - common)
    String.slice(word, 0, stem_length) <> String.slice(inflected, common..-1//1)
  end

  defp common_prefix_length(a, b), do: common_prefix_length(a, b, 0)

  defp common_prefix_length(<<c::utf8, rest_a::binary>>, <<c::utf8, rest_b::binary>>, count) do
    common_prefix_length(rest_a, rest_b, count + 1)
  end

  defp common_prefix_length(_a, _b, count), do: count

  # Right-to-left phrase inflection with hyphen-compound joining.
  defp inflect_phrase(body, tokens, constraint_values, pos, guess?) do
    _ = pos

    result =
      do_inflect_phrase(Enum.reverse(tokens), body, [], constraint_values, guess?)

    case result do
      :error -> ""
      parts -> assemble(body, tokens, parts)
    end
  end

  defp do_inflect_phrase([], _body, acc, _constraints, _guess?), do: acc

  defp do_inflect_phrase([token | rest], body, acc, constraint_values, guess?) do
    # Hyphenated compound: join with the token before the hyphen
    # when the joined form is a dictionary entry.
    {word, rest, joined?} =
      case rest do
        [previous | rest_after] ->
          joined = previous.value <> "-" <> token.value
          gap = binary_part(body, previous.stop, token.start - previous.stop)

          if gap == "-" and Dictionary.combined_grammemes(@locale, joined) != nil do
            {joined, rest_after, true}
          else
            {token.value, rest, false}
          end

        [] ->
          {token.value, rest, false}
      end

    phrase_type = Dictionary.combined_grammemes(@locale, word) || 0

    inflected =
      case inflect_using_dictionary(word, phrase_type, constraint_values, "") do
        nil ->
          cond do
            phrase_type != 0 -> word
            guess? -> guess_inflection(word, constraint_values, "") || word
            true -> :error
          end

        result ->
          result
      end

    case inflected do
      :error ->
        :error

      value ->
        entries = if joined?, do: [{:joined, value}], else: [{:single, value}]
        do_inflect_phrase(rest, body, entries ++ acc, constraint_values, guess?)
    end
  end

  # Reassemble, consuming one token per :single and two per :joined.
  defp assemble(body, tokens, parts) do
    {output, position, _remaining} =
      Enum.reduce(parts, {"", 0, tokens}, fn
        {:single, value}, {output, position, [token | rest]} ->
          separator = binary_part(body, position, token.start - position)
          {output <> separator <> value, token.stop, rest}

        {:joined, value}, {output, position, [left, right | rest]} ->
          separator = binary_part(body, position, left.start - position)
          {output <> separator <> value, right.stop, rest}
      end)

    output <> binary_part(body, position, byte_size(body) - position)
  end

  defp deduce_count_gender(tokens, count, gender) do
    Enum.reduce(tokens, {count, gender}, fn token, {count, gender} ->
      if count == "" or gender == "" do
        case Dictionary.combined_grammemes(@locale, token.value) do
          nil ->
            {count, gender}

          grammemes ->
            count = if count == "", do: single_of(grammemes, @numbers), else: count
            gender = if gender == "", do: single_of(grammemes, @genders), else: gender
            {count, gender}
        end
      else
        {count, gender}
      end
    end)
  end

  defp single_of(grammemes, names) do
    mask = Dictionary.binary_properties(@locale, names) || 0
    Dictionary.property_name(@locale, grammemes &&& mask) || ""
  end

  # "Head, trailing text": inflect only the part before the comma.
  defp static_suffix(display_string, constraint_values) do
    case String.split(display_string, ",", parts: 2) do
      [prefix, tail] ->
        suffix_result = "," <> tail

        case Dictionary.combined_grammemes(@locale, prefix) do
          nil ->
            {"", suffix_result}

          phrase_type ->
            case inflect_using_dictionary(prefix, phrase_type, constraint_values, "") do
              nil -> {"", suffix_result}
              inflected -> {inflected <> suffix_result, suffix_result}
            end
        end

      _no_comma ->
        {"", ""}
    end
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
