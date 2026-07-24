defmodule Localize.Inflection.Synthesizer.Pt do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  # The Portuguese grammar synthesizer, ported from
  # `PtGrammarSynthesizer` and its lookup and display functions.
  # Portuguese contracts prepositions with articles (de+o=do,
  # em+o=no, por+o=pelo, em+este=neste, …) and uses parenthesized
  # gender-unknown fallbacks such as "o(a)".

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{
    Articles,
    Dictionary,
    DisplayValue,
    GrammemeLookup,
    Inflector,
    Tokenizer
  }

  import Bitwise

  @locale :pt

  @number_tags ["singular", "plural"]
  @gender_tags ["masculine", "feminine"]

  @priorities [["noun", "adjective"], ["singular", "plural"], ["masculine", "feminine"]]

  # {derived, default, default_sg, default_pl, sg_m, sg_f, pl_m, pl_f}
  articles = %{
    "defArticle" => {nil, "", "o(a)", "os(as)", "o", "a", "os", "as"},
    "indefArticle" => {nil, "", "um(a)", "uns(umas)", "um", "uma", "uns", "umas"},
    "emPrepIndefArticle" => {nil, "em", "num(a)", "nuns(umas)", "num", "numa", "nuns", "numas"},
    "aPrepArticle" => {nil, "", "ao(à)", "aos(às)", "ao", "à", "aos", "às"},
    "dePrepArticle" => {nil, "de", "do(a)", "dos(as)", "do", "da", "dos", "das"},
    "emPrepArticle" => {nil, "em", "no(a)", "nos(as)", "no", "na", "nos", "nas"},
    "porPrepArticle" => {nil, "por", "pelo(a)", "pelos(as)", "pelo", "pela", "pelos", "pelas"},
    "demAdj" => {nil, "", "este(a)", "estes(as)", "este", "esta", "estes", "estas"},
    "inDemAdj" => {nil, "", "neste(a)", "nestes(as)", "neste", "nesta", "nestes", "nestas"},
    "ofDemAdj" => {nil, "", "deste(a)", "destes(as)", "deste", "desta", "destes", "destas"},
    "thisDemAdj" => {nil, "", "esse(a)", "esses(as)", "esse", "essa", "esses", "essas"},
    "inThisDemAdj" => {nil, "", "nesse(a)", "nesses(as)", "nesse", "nessa", "nesses", "nessas"},
    "ofThisDemAdj" => {nil, "", "desse(a)", "desses(as)", "desse", "dessa", "desses", "dessas"},
    "thatDemAdj" =>
      {nil, "", "aquele(a)", "aqueles(as)", "aquele", "aquela", "aqueles", "aquelas"},
    "inThatDemAdj" =>
      {nil, "", "naquele(a)", "naqueles(as)", "naquele", "naquela", "naqueles", "naquelas"},
    "ofThatDemAdj" =>
      {nil, "", "daquele(a)", "daqueles(as)", "daquele", "daquela", "daqueles", "daquelas"},
    "possArticle" => {nil, "", "seu(sua)", "seus(suas)", "seu", "sua", "seus", "suas"}
  }

  # Each base feature except defArticle/indefArticle has a with*
  # variant deriving from it.
  with_variants =
    for {feature, {nil, d, dsg, dpl, sm, sf, pm, pf}} <- articles,
        feature not in ["defArticle", "indefArticle"],
        into: %{} do
      with_name =
        "with" <> String.capitalize(String.first(feature)) <> String.slice(feature, 1..-1//1)

      {with_name, {feature, d, dsg, dpl, sm, sf, pm, pf}}
    end

  @articles Map.merge(articles, with_variants)

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("number", display_value, _constraints) do
    empty_to_nil(determine_number(display_value.display_string))
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
        ["defArticle", "dePrepArticle", "aPrepArticle", "emPrepArticle", "withPorPrepArticle"],
        ["de", "em", "por"]
      ),
      Articles.article_prefixes(@locale, ["indefArticle"])
    )
  end

  def feature_value(feature, display_value, _constraints) when is_map_key(@articles, feature) do
    {derived, _d, _dsg, _dpl, _sm, _sf, _pm, _pf} = Map.fetch!(@articles, feature)
    article_lookup(feature, display_value, derived != nil)
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  defp determine_number(phrase) do
    GrammemeLookup.determine(@locale, phrase, @number_tags,
      first_word_determines?: true,
      relevant: []
    )
  end

  defp determine_gender(phrase) do
    GrammemeLookup.determine(@locale, phrase, @gender_tags,
      first_word_determines?: true,
      relevant: []
    )
  end

  defp article_lookup(feature, display_value, include?) do
    {derived, default, default_sg, default_pl, sg_m, sg_f, pl_m, pl_f} =
      Map.fetch!(@articles, feature)

    derived_value = derived && Map.get(display_value.constraints, derived)

    if derived_value do
      Articles.create_preposition(display_value, derived_value, include?)
    else
      display_string = display_value.display_string

      count =
        parse(Map.get(display_value.constraints, "number"), @number_tags) ||
          parse(determine_number(display_string), @number_tags)

      gender =
        parse(Map.get(display_value.constraints, "gender"), @gender_tags) ||
          parse(determine_gender(display_string), @gender_tags)

      article =
        case {count, gender} do
          {"singular", "masculine"} -> sg_m
          {"singular", "feminine"} -> sg_f
          {"plural", "masculine"} -> pl_m
          {"plural", "feminine"} -> pl_f
          {"singular", nil} -> default_sg
          {"plural", nil} -> default_pl
          _other -> default
        end

      Articles.create_preposition(display_value, article, include?)
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
    whole =
      case Dictionary.combined_grammemes(@locale, display_string) do
        nil -> :error
        properties -> inflect_word(display_string, properties, constraints, false)
      end

    case whole do
      {:ok, inflected} ->
        {:ok, inflected}

      :error ->
        tokens = Tokenizer.word_tokens(@locale, display_string)
        words = Enum.map(tokens, & &1.value)

        case inflect_significant_words(words, constraints, guess?) do
          :error ->
            if guess?, do: {:ok, display_string}, else: :error

          {:ok, inflected_words} ->
            {:ok, rebuild(display_string, tokens, inflected_words)}
        end
    end
  end

  defp rebuild(display_string, tokens, inflected_words) do
    {output, position} =
      tokens
      |> Enum.zip(inflected_words)
      |> Enum.reduce({"", 0}, fn {token, word}, {output, position} ->
        separator = binary_part(display_string, position, token.start - position)
        {output <> separator <> word, token.stop}
      end)

    output <> binary_part(display_string, position, byte_size(display_string) - position)
  end

  defp inflect_significant_words([], _constraints, _guess?), do: {:ok, []}

  defp inflect_significant_words([word], constraints, guess?) do
    case inflect_word(
           word,
           Dictionary.combined_grammemes(@locale, word) || 0,
           constraints,
           guess?
         ) do
      {:ok, inflected} -> {:ok, [inflected]}
      :error -> :error
    end
  end

  defp inflect_significant_words([first, last], constraints, guess?) do
    inflect_two_words(first, last, constraints, guess?)
  end

  defp inflect_significant_words([w0, w1, w2] = words, constraints, guess?) do
    adposition = Dictionary.binary_properties(@locale, ["adposition"]) || 0
    middle_type = Dictionary.combined_grammemes(@locale, w1)

    if middle_type != nil and (middle_type &&& adposition) != 0 do
      case inflect_word(w0, Dictionary.combined_grammemes(@locale, w0) || 0, constraints, guess?) do
        {:ok, inflected} -> {:ok, [inflected, w1, w2]}
        :error -> {:ok, words}
      end
    else
      {:ok, words}
    end
  end

  defp inflect_significant_words(words, constraints, guess?) do
    noun = Dictionary.binary_properties(@locale, ["noun"]) || 0
    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0

    {results, _nouns} =
      Enum.reduce_while(words, {[], 0}, fn word, {results, nouns} ->
        word_type = Dictionary.combined_grammemes(@locale, word) || 0

        nouns =
          if (word_type &&& noun) != 0 and (word_type &&& adjective) == 0 do
            nouns + 1
          else
            nouns
          end

        if nouns >= 2 do
          {:cont, {[word | results], nouns}}
        else
          case inflect_word(word, word_type, constraints, guess?) do
            {:ok, inflected} -> {:cont, {[inflected | results], nouns}}
            :error when guess? -> {:cont, {[word | results], nouns}}
            :error -> {:halt, {:error, nouns}}
          end
        end
      end)

    case results do
      :error -> :error
      list -> {:ok, Enum.reverse(list)}
    end
  end

  defp inflect_two_words(first, last, constraints, guess?) do
    first_type = Dictionary.combined_grammemes(@locale, first)
    last_type = Dictionary.combined_grammemes(@locale, last)

    result =
      case two_word_rule(first_type, last_type) do
        :unchanged ->
          {:ok, [first, last]}

        :inflect_last ->
          case inflect_word(last, last_type, constraints, guess?) do
            {:ok, inflected} -> {:ok, [first, inflected]}
            :error -> :fallthrough
          end

        :inflect_both ->
          with {:ok, first_inflected} <- inflect_word(first, first_type, constraints, guess?),
               {:ok, last_inflected} <- inflect_word(last, last_type, constraints, guess?) do
            {:ok, [first_inflected, last_inflected]}
          else
            :error -> :fallthrough
          end

        :fallthrough ->
          :fallthrough
      end

    case result do
      {:ok, _words} = ok -> ok
      :fallthrough when guess? -> {:ok, [first, last]}
      :fallthrough -> :error
    end
  end

  defp two_word_rule(first_type, last_type) when is_nil(first_type) or is_nil(last_type) do
    :fallthrough
  end

  defp two_word_rule(first_type, last_type) do
    first = pos_flags(first_type)
    last = pos_flags(last_type)

    cond do
      first.adjective? and not first.noun? and last.noun? -> :unchanged
      first.adverb? and last.adjective? -> :inflect_last
      first.noun? and not first.verb? and (last.noun? or last.adjective?) -> :inflect_both
      (first.verb? and last.noun?) or (first.adjective? and last.adjective?) -> :inflect_last
      true -> :fallthrough
    end
  end

  defp pos_flags(word_type) do
    %{
      noun?: (word_type &&& (Dictionary.binary_properties(@locale, ["noun"]) || 0)) != 0,
      adjective?:
        (word_type &&& (Dictionary.binary_properties(@locale, ["adjective"]) || 0)) != 0,
      adverb?: (word_type &&& (Dictionary.binary_properties(@locale, ["adverb"]) || 0)) != 0,
      verb?: (word_type &&& (Dictionary.binary_properties(@locale, ["verb"]) || 0)) != 0
    }
  end

  defp inflect_word(word, word_type, constraints, guess?) do
    constraint_values =
      for value <- [Map.get(constraints, "number"), Map.get(constraints, "gender")],
          value not in [nil, ""],
          do: value

    disambiguation = for value <- [Map.get(constraints, "pos")], value not in [nil, ""], do: value
    options = [disambiguation: disambiguation, priorities: @priorities, fallback: false]

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

  defp guess_plural(word) do
    inflectable =
      Dictionary.binary_properties(@locale, ["noun", "adjective", "verb", "adverb"]) || 0

    word_type = Dictionary.combined_grammemes(@locale, word)

    if word_type != nil and (word_type &&& inflectable) == 0 do
      word
    else
      cond do
        String.ends_with?(word, "ês") -> String.slice(word, 0..-3//1) <> "eses"
        String.ends_with?(word, ["r", "z", "s"]) -> word <> "es"
        String.ends_with?(word, "m") -> String.slice(word, 0..-2//1) <> "ns"
        String.ends_with?(word, ["al", "el", "ol", "ul"]) -> String.slice(word, 0..-2//1) <> "is"
        String.ends_with?(word, "ão") -> String.slice(word, 0..-3//1) <> "ões"
        String.ends_with?(word, "il") -> String.slice(word, 0..-2//1) <> "s"
        not String.ends_with?(word, "x") -> word <> "s"
        true -> word
      end
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
