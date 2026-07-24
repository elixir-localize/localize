defmodule Localize.Inflection.Synthesizer.Sv do
  @moduledoc false

  # The Swedish grammar synthesizer, ported from
  # `SvGrammarSynthesizer` and its lookup and display functions.
  # Definite forms are purely suffix-based (hus → huset); the
  # display pipeline never prepends articles.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{
    Articles,
    Dictionary,
    DisplayValue,
    Inflector,
    Lookup,
    Tokenizer
  }

  import Bitwise

  @locale :sv

  @numbers ["singular", "plural"]
  @genders ["neuter", "common"]

  @priorities [["noun", "adjective"], ["singular", "plural"]]

  # {sg_common, sg_neuter, plural}
  @articles %{
    "defArticle" => {"den", "det", "de"},
    "indefArticle" => {"en", "ett", "flera"},
    "indefPron" => {"någon", "något", "några"},
    "interrogativeArticle" => {"vilken", "vilket", "vilka"},
    "negArticle" => {"ingen", "inget", "inga"},
    "newArticle" => {"ny", "nytt", "nya"},
    "otherArticle" => {"annan", "annat", "andra"},
    "possArticle" => {"din", "ditt", "dina"}
  }

  @with_articles Map.new(@articles, fn {feature, forms} ->
                   {"with" <>
                      String.capitalize(String.first(feature)) <> String.slice(feature, 1..-1//1),
                    {feature, forms}}
                 end)

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("number", display_value, _constraints) do
    empty_to_nil(Lookup.determine(@locale, display_value.display_string, @numbers))
  end

  def feature_value("gender", display_value, _constraints) do
    empty_to_nil(determine_gender(display_value.display_string))
  end

  def feature_value("definiteness", display_value, _constraints) do
    empty_to_nil(
      Lookup.determine(@locale, display_value.display_string, ["definite", "indefinite"])
    )
  end

  def feature_value(feature, display_value, _constraints) when is_map_key(@articles, feature) do
    article_lookup(Map.fetch!(@articles, feature), display_value, false)
  end

  def feature_value(feature, display_value, _constraints)
      when is_map_key(@with_articles, feature) do
    {_base, forms} = Map.fetch!(@with_articles, feature)
    article_lookup(forms, display_value, true)
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  # Gender lookup with raw-bit fallback; neuter wins on ambiguity.
  defp determine_gender(word) do
    case Lookup.determine(@locale, word, @genders) do
      "" ->
        case Dictionary.combined_grammemes(@locale, word) do
          nil ->
            ""

          binary_type ->
            common = Dictionary.binary_properties(@locale, ["common"]) || 0
            neuter = Dictionary.binary_properties(@locale, ["neuter"]) || 0

            cond do
              (binary_type &&& neuter) != 0 -> "neuter"
              (binary_type &&& common) != 0 -> "common"
              true -> ""
            end
        end

      gender ->
        gender
    end
  end

  defp article_lookup({sg_common, sg_neuter, plural}, display_value, include?) do
    display_string = display_value.display_string

    count =
      parse(Map.get(display_value.constraints, "number"), @numbers) ||
        parse(Lookup.determine(@locale, display_string, @numbers), @numbers) ||
        "singular"

    if count == "plural" do
      Articles.create_preposition(display_value, plural, include?)
    else
      gender =
        parse(Map.get(display_value.constraints, "gender"), ["common", "neuter"]) ||
          parse(determine_gender(display_string), ["common", "neuter"]) ||
          "common"

      article = if gender == "neuter", do: sg_neuter, else: sg_common
      Articles.create_preposition(display_value, article, include?)
    end
  end

  defp parse(value, _allowed) when value in [nil, ""], do: nil
  defp parse(value, allowed), do: if(value in allowed, do: value)

  @impl true
  def display_value(display_data, constraints, _guess?) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      display_string =
        if Dictionary.combined_grammemes(@locale, display_string) != nil do
          inflect_word(constraints, display_string, true)
        else
          inflect_token_chain(display_string, constraints)
        end

      %DisplayValue{display_string: display_string, constraints: constraints}
    else
      _other -> nil
    end
  end

  defp inflect_token_chain(display_string, constraints) do
    tokens = Tokenizer.word_tokens(@locale, display_string)

    case tokens do
      [] ->
        display_string

      _tokens ->
        words = Enum.map(tokens, & &1.value)

        case inflect_significant_tokens(constraints, words) do
          [] -> display_string
          inflected -> rebuild(display_string, tokens, inflected)
        end
    end
  end

  defp inflect_significant_tokens(constraints, words) do
    last = List.last(words)

    cond do
      Dictionary.combined_grammemes(@locale, last) == nil ->
        if Map.get(constraints, "case") == "genitive" do
          List.replace_at(words, -1, genitive_unknown(last))
        else
          []
        end

      length(words) == 2 ->
        [first, second] = words
        first_type = Dictionary.combined_grammemes(@locale, first) || 0
        second_type = Dictionary.combined_grammemes(@locale, second) || 0
        adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0
        noun = Dictionary.binary_properties(@locale, ["noun"]) || 0

        attribute? =
          first_type == 0 or second_type == 0 or
            ((first_type &&& adjective) != 0 and (first_type &&& noun) == 0 and
               (second_type &&& noun) != 0)

        first =
          if attribute?, do: inflect_word_full(constraints, first, second, false), else: first

        [first, inflect_word(constraints, second, true)]

      true ->
        List.replace_at(words, -1, inflect_word(constraints, last, true))
    end
  end

  defp rebuild(display_string, tokens, words) do
    {output, position} =
      tokens
      |> Enum.zip(words)
      |> Enum.reduce({"", 0}, fn {token, word}, {output, position} ->
        separator = binary_part(display_string, position, token.start - position)
        {output <> separator <> word, token.stop}
      end)

    output <> binary_part(display_string, position, byte_size(display_string) - position)
  end

  defp genitive_unknown(""), do: ""

  defp genitive_unknown(word) do
    last = String.last(word)
    lowercased = String.downcase(last)

    cond do
      lowercased in ["s", "x", "z"] -> word
      last != lowercased or last =~ ~r/[[:digit:]]/ -> word <> ":s"
      true -> word <> "s"
    end
  end

  defp inflect_word(constraints, word, noun?) do
    inflect_word_full(constraints, word, word, noun?)
  end

  defp inflect_word_full(constraints, attr_string, head_string, target_noun?) do
    count = Map.get(constraints, "number", "")
    definiteness = Map.get(constraints, "definiteness", "")
    case_ = Map.get(constraints, "case", "")

    gender =
      case Map.get(constraints, "gender", "") do
        "" when count == "singular" -> determine_gender(head_string)
        gender -> gender
      end

    effective_case = if target_noun?, do: case_, else: ""

    inflected =
      inflect_string(attr_string, count, definiteness, effective_case, gender, target_noun?)

    if target_noun? and case_ == "genitive" and String.length(inflected) > 1 and
         String.last(inflected) not in ["s", "z", "x"] do
      inflected <> "s"
    else
      inflected
    end
  end

  defp inflect_string(lemma, count, definiteness, case_, gender, noun?) do
    constraint_values =
      [count] ++
        if(definiteness != "" and (noun? or count == "singular"), do: [definiteness], else: []) ++
        if(case_ != "" and case_ != "nominative", do: [case_], else: []) ++
        if(gender != "", do: [gender], else: [])

    constraint_values = Enum.reject(constraint_values, &(&1 == ""))
    word_grammemes = Dictionary.combined_grammemes(@locale, lemma) || 0

    case Inflector.inflect(@locale, lemma, word_grammemes, constraint_values,
           priorities: @priorities
         ) do
      {:ok, inflected} -> inflected
      :error -> lemma
    end
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
