defmodule Localize.Inflection.Synthesizer.Fr do
  @moduledoc false

  # The French grammar synthesizer, ported from
  # `FrGrammarSynthesizer` and its lookup and display functions.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{
    Articles,
    Dictionary,
    DisplayValue,
    GrammemeLookup,
    Inflector,
    Lookup,
    PhraseProperties,
    Tokenizer
  }

  import Bitwise

  @locale :fr

  @number_tags ["singular", "plural"]
  @gender_tags ["masculine", "feminine"]
  @gender_disambiguation ["noun", "adjective", "determiner", "verb"]
  @count_disambiguation ["noun", "adjective"]

  @priorities [
    ["noun", "adjective", "verb"],
    ["third", "first", "second"],
    ["singular", "plural"],
    ["masculine", "feminine"]
  ]

  @masculine_suffixes ~w(an ans en ens ge ges in ins ire ires lon lons me mes ste stes ton tre tres)
  @feminine_suffixes ~w(a e es n ns é és)

  # {insert_space?, contraction?, vowel_elision_both_genders?, derived,
  #  default, default_vowel, sg_m, sg_f, sg_vowel, plural}
  @articles %{
    "defArticle" => {false, false, true, nil, "", "", "le ", "la ", "l’", "les "},
    "indefArticle" => {false, false, true, nil, "", "", "un", "une", "", "des"},
    "aPrepArticle" => {false, false, true, nil, "à ", "", "au ", "à la ", "à l’", "aux "},
    "withAPrepArticle" =>
      {false, true, true, "aPrepArticle", "à ", "", "au ", "à la ", "à l’", "aux "},
    "dePrepArticle" => {false, false, true, nil, "de ", "d’", "du ", "de la ", "de l’", "des "},
    "withDePrepArticle" =>
      {false, true, true, "dePrepArticle", "de ", "d’", "du ", "de la ", "de l’", "des "},
    "demonArticle" => {false, false, false, nil, "ce", "", "ce", "cette", "cet", "ces"},
    "withDemonArticle" =>
      {true, false, false, "demonArticle", "ce", "", "ce", "cette", "cet", "ces"},
    "genitiveArticle" => {false, false, true, nil, "de ", "", "de ", "de la ", "de l’", "des "},
    "withGenitiveArticle" =>
      {false, true, true, "genitiveArticle", "de ", "", "de ", "de la ", "de l’", "des "}
  }

  # {derived, default, consonant, vowel}
  @elisions %{
    "dePrep" => {nil, "", "de ", "d’"},
    "withDePrep" => {"dePrep", "", "de ", "d’"},
    "que" => {nil, "", "que ", "qu’"},
    "withQue" => {"que", "", "que ", "qu’"}
  }

  @words_preventing_inflection ~w(d de des du en par à)

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("number", display_value, _constraints) do
    empty_to_nil(determine_count(display_value.display_string))
  end

  def feature_value("gender", display_value, _constraints) do
    empty_to_nil(determine_gender(display_value.display_string))
  end

  def feature_value("definiteness", display_value, _constraints) do
    Articles.detect_definiteness(
      @locale,
      display_value,
      Articles.article_prefixes(
        @locale,
        ["defArticle", "dePrepArticle", "aPrepArticle", "genitiveArticle"],
        ["d’", "de "]
      ),
      Articles.article_prefixes(@locale, ["indefArticle"], ["à "])
    )
  end

  def feature_value(feature, display_value, _constraints) when is_map_key(@articles, feature) do
    {_space, _contraction, _both, derived, _d, _dv, _sm, _sf, _sv, _pl} =
      Map.fetch!(@articles, feature)

    article_lookup(feature, display_value, derived != nil)
  end

  def feature_value(feature, display_value, _constraints) when is_map_key(@elisions, feature) do
    {derived, default, consonant, vowel} = Map.fetch!(@elisions, feature)
    include? = derived != nil
    display_string = display_value.display_string

    article =
      cond do
        display_string == "" -> default
        PhraseProperties.starts_with_vowel?(@locale, display_string) -> vowel
        true -> consonant
      end

    Articles.create_preposition(display_value, article, include?, false)
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  defp determine_gender(phrase) do
    GrammemeLookup.determine(@locale, phrase, @gender_tags,
      disambiguation: @gender_disambiguation,
      default: "masculine",
      first_word_determines?: true,
      suffix_function: &guess_gender_by_suffix/1
    )
  end

  defp guess_gender_by_suffix(word) do
    cond do
      String.ends_with?(word, @masculine_suffixes) -> "masculine"
      String.ends_with?(word, @feminine_suffixes) -> "feminine"
      true -> ""
    end
  end

  # Port of FrGrammarSynthesizer_CountLookupFunction.
  defp determine_count(phrase) do
    case determine_count_word(phrase) do
      {:ok, result} ->
        result

      :none ->
        first =
          case Tokenizer.first_word(@locale, phrase) do
            nil -> ""
            token -> token.value
          end

        with :none <- if(first != phrase, do: determine_count_word(first), else: :none) do
          noun = Dictionary.binary_properties(@locale, ["noun"]) || 0

          if noun != 0 and Dictionary.has_all_properties?(@locale, first, noun) do
            if String.ends_with?(first, ["s", "x"]), do: {:ok, "plural"}, else: {:ok, "singular"}
          else
            {:ok, ""}
          end
        end
        |> elem(1)
    end
  end

  defp determine_count_word(word) do
    out = Lookup.determine(@locale, word, @number_tags, disambiguation: @count_disambiguation)

    if out != "" do
      {:ok, out}
    else
      properties = Dictionary.combined_grammemes(@locale, word) || 0
      proper = Dictionary.binary_properties(@locale, ["proper-noun"]) || 0
      invariant = Dictionary.binary_properties(@locale, ["plural", "singular"]) || 0

      cond do
        proper != 0 and (properties &&& proper) == proper -> {:ok, ""}
        invariant_noun?(word, properties, invariant) -> {:ok, "singular"}
        true -> :none
      end
    end
  end

  # A word tagged both singular and plural is invariant only when
  # its inflection pattern agrees.
  defp invariant_noun?(word, properties, invariant) do
    (properties &&& invariant) == invariant and invariant != 0 and
      Enum.any?(Dictionary.patterns_for_word(@locale, word), fn pattern ->
        inflections = Dictionary.matching_inflections(word, properties, pattern)

        case inflections do
          [] ->
            false

          [_single] ->
            true

          many ->
            combined = Enum.reduce(many, 0, fn {grammemes, _suffix}, acc -> acc ||| grammemes end)
            (combined &&& invariant) == invariant
        end
      end)
  end

  # Port of FrGrammarSynthesizer_ArticleLookupFunction.getFeatureValue/2.
  defp article_lookup(feature, display_value, include?, space_override \\ nil) do
    {insert_space?, contraction?, both_genders?, derived, default, default_vowel, sg_m, sg_f,
     sg_vowel, plural} = Map.fetch!(@articles, feature)

    insert_space? = if is_nil(space_override), do: insert_space?, else: space_override

    derived_value = derived && Map.get(display_value.constraints, derived)

    cond do
      derived_value != nil ->
        Articles.create_preposition(display_value, derived_value, include?, insert_space?)

      contraction_result = contraction? && apply_contraction(display_value, sg_m, plural) ->
        contraction_result

      true ->
        display_string = display_value.display_string

        count =
          parse(Map.get(display_value.constraints, "number"), @number_tags) ||
            parse(determine_count(display_string), @number_tags)

        gender =
          parse(Map.get(display_value.constraints, "gender"), @gender_tags) ||
            parse(determine_gender(display_string), @gender_tags)

        forms = {both_genders?, default, default_vowel, sg_m, sg_f, sg_vowel, plural}
        article = select_article(count, gender, display_value.display_string, forms)
        Articles.create_preposition(display_value, article, include?, insert_space?)
    end
  end

  defp select_article(count, gender, display_string, forms) do
    {both_genders?, default, default_vowel, sg_m, sg_f, sg_vowel, plural} = forms

    vowel? =
      display_string != "" and PhraseProperties.starts_with_vowel?(@locale, display_string)

    cond do
      count == "plural" ->
        plural

      count == "singular" and sg_vowel != "" and vowel? and
          (both_genders? or gender == "masculine") ->
        sg_vowel

      count == "singular" and gender == "masculine" ->
        sg_m

      count == "singular" and gender == "feminine" ->
        sg_f

      default_vowel != "" and vowel? ->
        default_vowel

      true ->
        default
    end
  end

  # Rewrites a leading "le"/"les" into the contracted form, e.g.
  # "le Louvre" + dePrepArticle -> "du Louvre".
  defp apply_contraction(display_value, sg_m, plural) do
    display_string = display_value.display_string

    with false <- display_string == "",
         %{clean: clean, stop: stop} <- Tokenizer.first_word(@locale, display_string),
         true <- clean in ["le", "les"] do
      rest =
        if byte_size(display_string) > stop do
          binary_part(display_string, stop + 1, byte_size(display_string) - stop - 1)
        else
          ""
        end

      article = if clean == "le", do: sg_m, else: plural
      String.trim(article <> rest)
    else
      _other -> nil
    end
  end

  defp parse(value, _allowed) when value in [nil, ""], do: nil
  defp parse(value, allowed), do: if(value in allowed, do: value)

  @impl true
  def display_value(display_data, constraints, guess?) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      value_constraints = Map.merge(display_value.constraints, constraints)

      inflected =
        if Map.get(constraints, "number") || Map.get(constraints, "gender") do
          inflect_string(display_string, constraints, guess?)
        else
          {:ok, display_string}
        end

      case inflected do
        :error ->
          nil

        {:ok, display_string} ->
          add_definiteness(
            %DisplayValue{display_string: display_string, constraints: value_constraints},
            constraints
          )
      end
    else
      _other -> nil
    end
  end

  defp inflect_string(display_string, constraints, guess?) do
    known? = Dictionary.combined_grammemes(@locale, display_string) != nil
    tokens = Tokenizer.word_tokens(@locale, display_string)

    if known? or length(tokens) == 1 do
      word_type = Dictionary.combined_grammemes(@locale, display_string) || 0
      inflect_word(display_string, word_type, constraints, guess?)
    else
      inflect_compound(display_string, tokens, constraints, guess?)
    end
  end

  defp inflect_word(word, word_type, constraints, guess?) do
    constraint_values =
      for value <- [Map.get(constraints, "number"), Map.get(constraints, "gender")],
          value not in [nil, ""],
          do: value

    disambiguation = for value <- [Map.get(constraints, "pos")], value not in [nil, ""], do: value
    options = [disambiguation: disambiguation, priorities: @priorities]

    case Inflector.inflect(@locale, word, word_type, constraint_values, options) do
      {:ok, inflected} ->
        {:ok, inflected}

      :error when not guess? ->
        :error

      :error ->
        if Map.get(constraints, "number") == "plural" do
          {:ok, guess_plural(word)}
        else
          {:ok, word}
        end
    end
  end

  defp inflect_compound(display_string, tokens, constraints, guess?) do
    {result, _position, _prevent?} =
      Enum.reduce_while(tokens, {"", 0, false}, fn token, {output, position, prevent?} ->
        separator = binary_part(display_string, position, token.start - position)

        cond do
          token.clean in @words_preventing_inflection ->
            {:cont, {output <> separator <> token.value, token.stop, true}}

          prevent? ->
            {:cont, {output <> separator <> token.value, token.stop, false}}

          true ->
            word_type = Dictionary.combined_grammemes(@locale, token.value) || 0

            case inflect_word(token.value, word_type, constraints, guess?) do
              {:ok, inflected} ->
                {:cont, {output <> separator <> inflected, token.stop, false}}

              :error ->
                {:halt, {:error, position, prevent?}}
            end
        end
      end)

    case result do
      :error ->
        :error

      output ->
        tail_start =
          case List.last(tokens) do
            nil -> 0
            token -> token.stop
          end

        {:ok,
         output <> binary_part(display_string, tail_start, byte_size(display_string) - tail_start)}
    end
  end

  defp guess_plural(word) do
    cond do
      not pluralizable?(word) -> word
      String.ends_with?(word, ["s", "x", "z"]) -> word
      String.ends_with?(word, ["eau", "eu"]) -> word <> "x"
      String.ends_with?(word, "al") -> String.slice(word, 0..-3//1) <> "aux"
      String.ends_with?(word, "ail") -> String.slice(word, 0..-4//1) <> "aux"
      true -> word <> "s"
    end
  end

  defp pluralizable?(word) do
    if String.length(word) <= 2 do
      false
    else
      case Dictionary.combined_grammemes(@locale, word) do
        nil ->
          true

        properties ->
          blocked =
            Dictionary.binary_properties(@locale, [
              "article",
              "pronoun",
              "proper-noun",
              "preposition",
              "adposition"
            ]) || blocked_mask()

          noun_adjective = Dictionary.binary_properties(@locale, ["noun", "adjective"]) || 0
          adverb = Dictionary.binary_properties(@locale, ["adverb"]) || 0
          verb = Dictionary.binary_properties(@locale, ["verb"]) || 0

          cond do
            (properties &&& blocked) != 0 -> false
            (properties &&& noun_adjective) != 0 -> true
            (properties &&& adverb) != 0 -> false
            (properties &&& verb) != 0 -> String.ends_with?(word, ["é", "ée"])
            true -> true
          end
      end
    end
  end

  # Not every blocked part of speech exists as a grammeme in every
  # dictionary; fall back to the ones that do.
  defp blocked_mask do
    ["article", "pronoun", "proper-noun", "preposition", "adposition"]
    |> Enum.map(&(Dictionary.binary_properties(@locale, [&1]) || 0))
    |> Enum.reduce(0, &Bitwise.bor/2)
  end

  defp add_definiteness(display_value, constraints) do
    Articles.add_definiteness(
      display_value,
      constraints,
      Articles.article_prefixes(@locale, ["defArticle"]),
      Articles.article_prefixes(@locale, ["indefArticle"]),
      fn base, _constraints -> article_lookup("defArticle", base, true, false) end,
      fn base, _constraints -> article_lookup("indefArticle", base, true, true) end
    )
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
