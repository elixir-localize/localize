defmodule Localize.Inflection.Synthesizer.Da do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  # The Danish grammar synthesizer, ported from
  # `DaGrammarSynthesizer` and its lookup and display functions.
  # Danish genders are common/neuter; definite singular single
  # words take the suffixed form (hus → huset) rather than a
  # freestanding article.

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

  @locale :da

  @numbers ["singular", "plural"]
  @genders ["common", "neuter"]

  @priorities [["noun", "adjective", "verb"], ["singular", "plural"], ["nominative", "genitive"]]

  # {sg_common, sg_neuter, plural}
  @articles %{
    "negArticle" => {"ingen", "intet", "ingen"},
    "defArticle" => {{"den", "dén"}, "det", "de"},
    "indefArticle" => {"en", "et", "flere"},
    "possArticle" => {"din", "dit", "dine"},
    "newArticle" => {"ny", "nyt", "nye"},
    "otherArticle" => {"anden", "andet", "andre"},
    "interrogativeArticle" => {"hvilken", "hvilket", "hvilke"},
    "indefPron" => {"nogen", "noget", "nogle"},
    "demonArticle" => {"denne", "dette", "disse"}
  }

  @with_articles Map.new(@articles, fn {feature, forms} ->
                   {"with" <>
                      String.capitalize(String.first(feature)) <> String.slice(feature, 1..-1//1),
                    {feature, forms}}
                 end)

  @vowels_da ~w(e a u o y ø æ)
  @iaa ~w(i å)

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("number", display_value, _constraints) do
    empty_to_nil(Lookup.determine(@locale, display_value.display_string, @numbers))
  end

  def feature_value("gender", display_value, _constraints) do
    empty_to_nil(Lookup.determine(@locale, display_value.display_string, @genders))
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
        parse(Map.get(display_value.constraints, "gender"), @genders) ||
          parse(Lookup.determine(@locale, display_string, @genders), @genders) ||
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
      if map_size(constraints) > 0 do
        {display_string, multi_word?, word_grammemes, head_gender} =
          inflect_display(display_string, constraints)

        definiteness = Map.get(constraints, "definiteness", "")
        count = Map.get(constraints, "number", "")
        singular? = count in ["", "singular"]
        noun = Dictionary.binary_properties(@locale, ["noun"]) || 0

        noun? =
          multi_word? or
            ((word_grammemes &&& noun) != 0 and Map.get(constraints, "pos") != "adjective")

        wants_article? =
          noun? and
            ((definiteness == "indefinite" and singular?) or
               (definiteness == "definite" and multi_word?))

        if wants_article? do
          value_constraints =
            if head_gender != "" do
              Map.put(constraints, "gender", head_gender)
            else
              constraints
            end

          add_definiteness(
            %DisplayValue{display_string: display_string, constraints: value_constraints},
            value_constraints
          )
        else
          %DisplayValue{display_string: display_string, constraints: constraints}
        end
      else
        %DisplayValue{display_string: display_string, constraints: constraints}
      end
    else
      _other -> nil
    end
  end

  defp inflect_display(display_string, constraints) do
    cond do
      String.ends_with?(display_string, ".") ->
        {genitive_when_requested(constraints, display_string), false, 0, ""}

      Dictionary.combined_grammemes(@locale, display_string) != nil ->
        word_grammemes = Dictionary.combined_grammemes(@locale, display_string)
        {inflect_word(constraints, display_string, word_grammemes), false, word_grammemes, ""}

      true ->
        tokens = Tokenizer.word_tokens(@locale, display_string)

        head_gender =
          if Map.get(constraints, "gender") in [nil, ""] do
            Enum.reduce(tokens, "", fn token, acc ->
              case Lookup.determine(@locale, token.value, @genders) do
                "" -> acc
                gender -> gender
              end
            end)
          else
            ""
          end

        {inflect_token_chain(display_string, tokens, constraints), true, 0, head_gender}
    end
  end

  defp inflect_token_chain(display_string, tokens, constraints) do
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
    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0
    noun = Dictionary.binary_properties(@locale, ["noun"]) || 0

    case Dictionary.combined_grammemes(@locale, last) do
      nil ->
        genitive = genitive_when_requested(constraints, last)

        if genitive != last do
          List.replace_at(words, -1, genitive)
        else
          []
        end

      last_type ->
        first = List.first(words)
        first_type = Dictionary.combined_grammemes(@locale, first)
        first_mask = first_type || 0

        pair? =
          length(words) == 2 and
            (first_type == nil or
               ((first_mask &&& adjective) != 0 and (first_mask &&& noun) == 0 and
                  (last_type &&& noun) != 0))

        if pair? do
          [
            inflect_word_full(constraints, first, first_type || 0, last, last_type, false, false),
            inflect_word_full(constraints, last, last_type, last, last_type, true, true)
          ]
        else
          List.replace_at(words, -1, inflect_word(constraints, last, last_type))
        end
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

  defp inflect_word(constraints, word, grammemes) do
    inflect_word_full(constraints, word, grammemes, word, grammemes, true, false)
  end

  defp inflect_word_full(
         constraints,
         attr_string,
         attr_grammemes,
         head_string,
         head_grammemes,
         suspected_noun?,
         head_with_attribute?
       ) do
    count = Map.get(constraints, "number", "")

    definiteness =
      if head_with_attribute? do
        # A noun with a preceding attribute takes the unsuffixed
        # form; definiteness comes from the freestanding article.
        "indefinite"
      else
        Map.get(constraints, "definiteness", "")
      end

    case_ = Map.get(constraints, "case", "")

    gender =
      case Map.get(constraints, "gender", "") do
        "" -> Lookup.determine(@locale, head_string, @genders)
        gender -> gender
      end

    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0
    noun = Dictionary.binary_properties(@locale, ["noun"]) || 0

    adjective? =
      Map.get(constraints, "pos") == "adjective" or
        ((head_grammemes &&& adjective) != 0 and (head_grammemes &&& noun) == 0)

    target_noun? = not adjective? and suspected_noun?

    inflected =
      inflect_string(
        attr_string,
        attr_grammemes,
        count,
        definiteness,
        case_,
        gender,
        target_noun?
      )

    cond do
      suspected_noun? and inflected == "" ->
        genitive_when_requested(constraints, attr_string)

      inflected == "" ->
        attr_string

      true ->
        String.replace(inflected, "'", "’")
    end
  end

  defp inflect_string(lemma, grammemes, count, definiteness, case_, gender, target_noun?) do
    if target_noun? do
      constraint_values =
        [count] ++
          if(definiteness != "", do: [definiteness], else: []) ++
          if(case_ != "" and case_ != "nominative", do: [case_], else: []) ++
          if(gender != "", do: [gender], else: [])

      constraint_values = Enum.reject(constraint_values, &(&1 == ""))

      case Inflector.inflect(@locale, lemma, grammemes, constraint_values,
             priorities: @priorities
           ) do
        {:ok, inflected} -> String.replace(inflected, "'S", "'s")
        :error -> ""
      end
    else
      count = if count == "", do: "singular", else: count
      definiteness = if definiteness == "", do: "indefinite", else: definiteness
      inflect_adjective(lemma, definiteness, gender, count)
    end
  end

  # sproget.dk genitive rules.
  defp genitive_when_requested(constraints, string) do
    if Map.get(constraints, "case") == "genitive" and String.length(string) > 1 do
      last = string |> String.last() |> String.downcase()

      cond do
        last in ["s", "z", "x"] ->
          string <> "’"

        (string == String.upcase(string) and string != String.downcase(string) and
           last =~ ~r/[[:alnum:]]/u) or last =~ ~r/[[:digit:]]/ or
            String.ends_with?(string, ".dk") ->
          string <> "’s"

        true ->
          string <> "s"
      end
    else
      string
    end
  end

  # Heuristic adjective inflection with syncope (gammel → gamle).
  defp inflect_adjective(lemma, definiteness, gender, count) do
    length = String.length(lemma)

    if length < 1 do
      lemma
    else
      c1 = String.at(lemma, length - 1)
      ends_iaa? = c1 in @iaa
      ends_consonant? = c1 not in @iaa and c1 not in @vowels_da

      cond do
        count == "plural" or definiteness == "definite" ->
          declined_form(lemma, length, c1, ends_consonant?)

        count == "singular" and gender == "neuter" and (ends_iaa? or ends_consonant?) and
            c1 != "t" ->
          lemma <> "t"

        true ->
          lemma
      end
    end
  end

  # Plural/definite adjective form with syncope (gammel → gamle).
  defp declined_form(lemma, length, c1, ends_consonant?) do
    syncope =
      if length > 4 do
        c2 = String.at(lemma, length - 2)
        c3 = String.at(lemma, length - 3)
        c4 = String.at(lemma, length - 4)

        if c2 == "e" and c1 in ["n", "l", "r"] and c3 == c4 and
             c3 not in @iaa and c3 not in @vowels_da do
          String.slice(lemma, 0, length - 3) <> c1 <> "e"
        end
      end

    cond do
      syncope -> syncope
      ends_consonant? -> lemma <> "e"
      true -> lemma
    end
  end

  defp add_definiteness(display_value, constraints) do
    Articles.add_definiteness(
      display_value,
      constraints,
      Articles.article_prefixes(@locale, ["defArticle"]),
      Articles.article_prefixes(@locale, ["indefArticle"]),
      fn base, _constraints ->
        article_lookup(Map.fetch!(@articles, "defArticle"), base, true)
      end,
      fn base, _constraints ->
        article_lookup(Map.fetch!(@articles, "indefArticle"), base, true)
      end
    )
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
