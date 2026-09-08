defmodule Localize.Inflection.Synthesizer.Es do
  @moduledoc false

  # The Spanish grammar synthesizer, ported from
  # `EsGrammarSynthesizer` and its lookup and display functions.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{
    Articles,
    Dictionary,
    DisplayValue,
    Inflector,
    Lookup,
    PhraseProperties,
    Tokenizer
  }

  import Bitwise

  @locale :es

  @number_tags ["singular", "plural"]
  @gender_tags ["feminine", "masculine"]
  @count_gender_disambiguation ["noun", "adjective"]

  @priorities [
    ["noun", "adjective", "verb"],
    ["third", "first", "second"],
    ["singular", "plural"],
    ["masculine", "feminine"]
  ]

  # {derived_feature, default, sg_masculine, sg_feminine,
  #  pl_masculine, pl_feminine, stressed_rule?}
  @articles %{
    "defArticle" => {nil, "", "el", "la", "los", "las", true},
    "indefArticle" => {nil, "", "un", "una", "unos", "unas", true},
    "dePrepArticle" => {nil, "", "del", "de la", "de los", "de las", true},
    "withDePrepArticle" => {"dePrepArticle", "", "del", "de la", "de los", "de las", true},
    "aPrepArticle" => {nil, "", "al", "a la", "a los", "a las", true},
    "withAPrepArticle" => {"aPrepArticle", "", "al", "a la", "a los", "a las", true},
    "demAdj" => {nil, "", "este", "esta", "estos", "estas", false},
    "withDemAdj" => {"demAdj", "", "este", "esta", "estos", "estas", false}
  }

  # The de/a contracted article tables in grammar.xml order, used to
  # detect and strip an existing article prefix before inflection.
  @prefix_articles [
    {"withDePrepArticle", "del", %{"number" => "singular", "gender" => "masculine"}},
    {"withDePrepArticle", "de la", %{"number" => "singular", "gender" => "feminine"}},
    {"withDePrepArticle", "de los", %{"number" => "plural", "gender" => "masculine"}},
    {"withDePrepArticle", "de las", %{"number" => "plural", "gender" => "feminine"}},
    {"withAPrepArticle", "al", %{"number" => "singular", "gender" => "masculine"}},
    {"withAPrepArticle", "a la", %{"number" => "singular", "gender" => "feminine"}},
    {"withAPrepArticle", "a los", %{"number" => "plural", "gender" => "masculine"}},
    {"withAPrepArticle", "a las", %{"number" => "plural", "gender" => "feminine"}}
  ]

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("number", display_value, _constraints) do
    empty_to_nil(determine(display_value.display_string, :number))
  end

  def feature_value("gender", display_value, _constraints) do
    empty_to_nil(determine(display_value.display_string, :gender))
  end

  def feature_value("definiteness", display_value, _constraints) do
    Articles.detect_definiteness(
      @locale,
      display_value,
      Articles.article_prefixes(@locale, ["defArticle", "dePrepArticle", "aPrepArticle"], [
        "a",
        "de"
      ]),
      Articles.article_prefixes(@locale, ["indefArticle"])
    )
  end

  def feature_value(feature, display_value, _constraints) when is_map_key(@articles, feature) do
    {derived, _default, _sm, _sf, _pm, _pf, _stressed} = Map.fetch!(@articles, feature)
    article_lookup(feature, display_value, derived != nil)
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  # Port of EsGrammarSynthesizer_ArticleLookupFunction.getFeatureValue/2.
  defp article_lookup(feature, display_value, include?) do
    {derived, default, sg_m, sg_f, pl_m, pl_f, stressed?} = Map.fetch!(@articles, feature)

    derived_value = derived && Map.get(display_value.constraints, derived)

    if derived_value do
      Articles.create_preposition(display_value, derived_value, include?)
    else
      display_string = display_value.display_string

      count =
        parse_value(Map.get(display_value.constraints, "number"), @number_tags) ||
          parse_value(determine(display_string, :number), @number_tags)

      gender =
        parse_value(Map.get(display_value.constraints, "gender"), @gender_tags) ||
          parse_value(determine(display_string, :gender), @gender_tags)

      forms = {default, sg_m, sg_f, pl_m, pl_f}
      article = select_article(count, gender, forms, stressed?, display_string)
      Articles.create_preposition(display_value, article, include?)
    end
  end

  defp select_article(
         "singular",
         "feminine",
         {_default, sg_m, sg_f, _pl_m, _pl_f},
         stressed?,
         display_string
       ) do
    if stressed? and stressed_first_word?(display_string), do: sg_m, else: sg_f
  end

  defp select_article(
         "singular",
         "masculine",
         {_default, sg_m, _sg_f, _pl_m, _pl_f},
         _stressed?,
         _display_string
       ) do
    sg_m
  end

  defp select_article(
         "plural",
         "masculine",
         {_default, _sg_m, _sg_f, pl_m, _pl_f},
         _stressed?,
         _display_string
       ) do
    pl_m
  end

  defp select_article(
         "plural",
         "feminine",
         {_default, _sg_m, _sg_f, _pl_m, pl_f},
         _stressed?,
         _display_string
       ) do
    pl_f
  end

  defp select_article(
         _count,
         _gender,
         {default, _sg_m, _sg_f, _pl_m, _pl_f},
         _stressed?,
         _display_string
       ) do
    default
  end

  defp parse_value(value, _allowed) when value in [nil, ""], do: nil
  defp parse_value(value, allowed), do: if(value in allowed, do: value)

  # The "el agua" rule: a feminine singular headword whose first
  # word carries the `stressed` grammeme takes the masculine
  # article.
  defp stressed_first_word?(display_string) do
    case Tokenizer.first_word(@locale, display_string) do
      nil -> false
      token -> Lookup.determine(@locale, token.clean, ["stressed"]) == "stressed"
    end
  end

  # Port of EsGrammarSynthesizer_CountGenderLookupFunction.determine/1.
  defp determine(phrase, category) do
    tags = if category == :number, do: @number_tags, else: @gender_tags

    result =
      Lookup.determine_phrase(@locale, phrase, tags, true,
        disambiguation: @count_gender_disambiguation
      )

    if result != "" or phrase == "" do
      result
    else
      guess_category(category, phrase, tags)
    end
  end

  defp guess_category(category, phrase, tags) do
    combined = Dictionary.combined_grammemes(@locale, phrase)
    mask = Dictionary.binary_properties(@locale, tags) || 0

    if category == :gender and combined != nil and (combined &&& mask) == 0 do
      ""
    else
      first_word =
        case Tokenizer.first_word(@locale, phrase) do
          nil -> ""
          token -> token.clean
        end

      case category do
        :gender ->
          guess_gender(first_word, Dictionary.combined_grammemes(@locale, first_word) != nil)

        :number ->
          guess_count(first_word)
      end
    end
  end

  defp guess_gender(word, known?) do
    cond do
      String.ends_with?(word, ["is", "iones", "ie", "ción", "sión", "umbre"]) -> "feminine"
      not known? and String.ends_with?(word, ["as", "a"]) -> "feminine"
      true -> "masculine"
    end
  end

  defp guess_count(word) do
    cond do
      String.ends_with?(word, ["ís", "és", "ás"]) -> "singular"
      String.ends_with?(word, "s") -> "plural"
      true -> "singular"
    end
  end

  @impl true
  def display_value(display_data, constraints, guess?) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      value_constraints = Map.merge(display_value.constraints, constraints)
      {display_string, article} = strip_article_prefix(display_string)

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
          display_string = reattach_article(display_string, value_constraints, article)

          add_definiteness(
            %DisplayValue{display_string: display_string, constraints: value_constraints},
            constraints
          )
      end
    else
      _other -> nil
    end
  end

  defp strip_article_prefix(display_string) do
    Enum.find_value(@prefix_articles, {display_string, nil}, fn {feature, article,
                                                                 article_constraints} ->
      length = byte_size(article)

      cond do
        not String.starts_with?(display_string, article) ->
          nil

        byte_size(display_string) > length and
            binary_part(display_string, length, 1) != " " ->
          nil

        true ->
          strip = min(length + 1, byte_size(display_string))
          rest = binary_part(display_string, strip, byte_size(display_string) - strip)
          {rest, {feature, article_constraints}}
      end
    end)
  end

  defp reattach_article(display_string, value_constraints, nil) do
    _ = value_constraints
    display_string
  end

  defp reattach_article(display_string, value_constraints, {feature, article_constraints}) do
    merged = Map.merge(article_constraints, value_constraints)

    result =
      article_lookup(
        feature,
        %DisplayValue{display_string: display_string, constraints: merged},
        true
      )

    case result do
      nil -> display_string
      speakable -> Localize.Inflection.SpeakableString.print(speakable)
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

  # Port of EsGrammarSynthesizer_EsDisplayFunction.inflectWord/4.
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

      :error when word_type != 0 ->
        {:ok, word}

      :error ->
        {:ok, guess_inflection(word, constraints)}
    end
  end

  defp guess_inflection(word, constraints) do
    word =
      case Map.get(constraints, "gender") do
        nil -> word
        gender -> guess_gendered(word, gender)
      end

    if Map.get(constraints, "number") == "plural" do
      guess_plural(word)
    else
      word
    end
  end

  defp inflect_compound(display_string, tokens, constraints, guess?) do
    preposition = Dictionary.binary_properties(@locale, ["adposition"]) || 0

    {result, _position, _prep?} =
      Enum.reduce_while(tokens, {"", 0, false}, fn token, state ->
        compound_step(token, state, display_string, preposition, constraints, guess?)
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

  defp compound_step(
         token,
         {output, position, prep?},
         display_string,
         preposition,
         constraints,
         guess?
       ) do
    separator = binary_part(display_string, position, token.start - position)
    word_type = Dictionary.combined_grammemes(@locale, token.value) || 0

    cond do
      prep? ->
        {:cont, {output <> separator <> token.value, token.stop, prep?}}

      (word_type &&& preposition) != 0 ->
        {:cont, {output <> separator <> token.value, token.stop, true}}

      true ->
        case inflect_word(token.value, word_type, constraints, guess?) do
          {:ok, inflected} ->
            {:cont, {output <> separator <> inflected, token.stop, prep?}}

          :error ->
            {:halt, {:error, position, prep?}}
        end
    end
  end

  defp guess_gendered(word, "masculine") do
    cond do
      String.ends_with?(word, ["o", "os"]) -> word
      String.ends_with?(word, "as") -> String.slice(word, 0..-3//1) <> "os"
      String.ends_with?(word, "a") -> String.slice(word, 0..-2//1) <> "o"
      true -> word
    end
  end

  defp guess_gendered(word, "feminine") do
    cond do
      String.ends_with?(word, ["a", "as"]) -> word
      String.ends_with?(word, "os") -> String.slice(word, 0..-3//1) <> "as"
      String.ends_with?(word, "o") -> String.slice(word, 0..-2//1) <> "a"
      true -> word
    end
  end

  defp guess_gendered(word, _gender), do: word

  defp guess_plural(word) do
    cond do
      String.ends_with?(word, ["s", "x"]) -> word
      PhraseProperties.ends_with_vowel?(@locale, word) -> word <> "s"
      String.ends_with?(word, "z") -> String.slice(word, 0..-2//1) <> "ces"
      String.ends_with?(word, "ión") -> String.slice(word, 0..-4//1) <> "iones"
      String.ends_with?(word, "c") -> String.slice(word, 0..-2//1) <> "ques"
      String.ends_with?(word, "g") -> String.slice(word, 0..-2//1) <> "gues"
      true -> word <> "es"
    end
  end

  defp add_definiteness(display_value, constraints) do
    Articles.add_definiteness(
      display_value,
      constraints,
      Articles.article_prefixes(@locale, ["defArticle"]),
      Articles.article_prefixes(@locale, ["indefArticle"]),
      fn base, _constraints -> article_lookup("defArticle", base, true) end,
      fn base, _constraints -> article_lookup("indefArticle", base, true) end
    )
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
