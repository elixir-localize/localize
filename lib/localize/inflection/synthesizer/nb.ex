defmodule Localize.Inflection.Synthesizer.Nb do
  @moduledoc false

  # The Norwegian Bokmål grammar synthesizer, ported from
  # `NbGrammarSynthesizer` and its lookup and display functions.
  # Three genders (ei/di feminine forms); definite forms are
  # suffixed via the inflector, never a prepended article.

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

  @locale :nb

  @numbers ["singular", "plural"]
  @genders ["masculine", "feminine", "neuter"]

  @priorities [
    ["noun", "adjective"],
    ["singular", "plural"],
    ["comparative", "superlative"],
    ["indefinite", "definite"]
  ]

  @vowels_nb ~w(i å e a u o y ø æ)

  # {include?, sg_m, sg_f, sg_n, plural}
  @articles %{
    "defArticle" => {false, "den", "den", "det", "de"},
    "indefArticle" => {false, "en", "ei", "et", "flere"},
    "interrogativeArticle" => {false, "hvilken", "hvilken", "hvilket", "hvilke"},
    "withInterrogativeArticle" => {true, "hvilken", "hvilken", "hvilket", "hvilke"},
    "possArticle" => {false, "din", "di", "ditt", "dine"},
    "withPossArticle" => {true, "din", "di", "ditt", "dine"},
    "demonArticle" => {false, "denne", "denne", "dette", "disse"},
    "withDemonArticle" => {true, "denne", "denne", "dette", "disse"}
  }

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
    {include?, sg_m, sg_f, sg_n, plural} = Map.fetch!(@articles, feature)
    article_lookup({sg_m, sg_f, sg_n, plural}, display_value, include?)
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  defp article_lookup({sg_m, sg_f, sg_n, plural}, display_value, include?) do
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
          "masculine"

      article =
        case gender do
          "neuter" -> sg_n
          "feminine" -> sg_f
          _masculine -> sg_m
        end

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
        if map_size(constraints) > 0 do
          case Dictionary.combined_grammemes(@locale, display_string) do
            nil ->
              inflect_token_chain(display_string, constraints)

            grammemes ->
              inflect_word(constraints, display_string, grammemes)
          end
        else
          display_string
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

    case Dictionary.combined_grammemes(@locale, last) do
      nil ->
        if Map.get(constraints, "case") == "genitive" do
          List.replace_at(words, -1, genitive(last))
        else
          []
        end

      last_type ->
        adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0
        noun = Dictionary.binary_properties(@locale, ["noun"]) || 0
        first_mask = Dictionary.combined_grammemes(@locale, List.first(words)) || 0

        pair? =
          length(words) == 2 and (first_mask &&& adjective) != 0 and (last_type &&& noun) != 0

        if pair? do
          [first, second] = words
          first_type = Dictionary.combined_grammemes(@locale, first) || 0

          [
            inflect_word_full(constraints, first, first_type, second, false),
            inflect_word_full(constraints, second, last_type, second, true)
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
    inflect_word_full(constraints, word, grammemes, word, true)
  end

  defp inflect_word_full(constraints, attr_string, attr_grammemes, head_string, suspected_noun?) do
    count = Map.get(constraints, "number", "")
    definiteness = Map.get(constraints, "definiteness", "")
    case_ = Map.get(constraints, "case", "")

    head_type =
      if attr_string == head_string do
        attr_grammemes
      else
        Dictionary.combined_grammemes(@locale, head_string) || 0
      end

    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0
    noun = Dictionary.binary_properties(@locale, ["noun"]) || 0

    adjective? =
      Map.get(constraints, "pos") == "adjective" or
        ((head_type &&& adjective) != 0 and (head_type &&& noun) == 0)

    gender = Map.get(constraints, "gender", "")

    inflected =
      if adjective? or not suspected_noun? do
        gender =
          if gender == "" do
            Lookup.determine(@locale, head_string, @genders)
          else
            gender
          end

        inflect_adjective(attr_string, definiteness, gender, count)
      else
        inflect_noun(attr_string, attr_grammemes, count, definiteness, gender)
      end

    if case_ == "genitive" and suspected_noun? and String.length(inflected) > 1 do
      genitive(inflected)
    else
      inflected
    end
  end

  defp inflect_noun(word, grammemes, count, definiteness, gender) do
    constraint_values =
      if(count != "", do: [count], else: []) ++
        if(definiteness != "", do: [definiteness], else: []) ++
        if(count != "plural" and gender != "", do: [gender], else: [])

    case Inflector.inflect(@locale, word, grammemes, constraint_values, priorities: @priorities) do
      {:ok, inflected} -> inflected
      :error -> word
    end
  end

  defp genitive(""), do: ""

  defp genitive(string) do
    if String.last(string) in ["s", "z", "x"] do
      string <> "’"
    else
      string <> "s"
    end
  end

  defp inflect_adjective(lemma, definiteness, gender, count) do
    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0
    grammemes = Dictionary.combined_grammemes(@locale, lemma)

    from_dictionary =
      if grammemes != nil and (grammemes &&& adjective) != 0 do
        comparison = Dictionary.binary_properties(@locale, ["comparative", "superlative"]) || 0

        constraint_values =
          if (grammemes &&& comparison) != 0 do
            if definiteness != "", do: [definiteness], else: []
          else
            if(count != "", do: [count], else: []) ++
              if(count != "plural" and definiteness != "", do: [definiteness], else: []) ++
              if(count != "plural" and definiteness != "definite" and gender != "",
                do: [gender],
                else: []
              )
          end

        case Inflector.inflect(@locale, lemma, grammemes, constraint_values,
               disambiguation: ["adjective"],
               priorities: @priorities
             ) do
          {:ok, inflected} -> inflected
          :error -> nil
        end
      end

    from_dictionary || heuristic_adjective(lemma, definiteness, gender, count)
  end

  defp heuristic_adjective(lemma, definiteness, gender, count) do
    length = String.length(lemma)

    if length < 1 do
      lemma
    else
      c1 = String.at(lemma, length - 1)
      ends_consonant? = c1 not in @vowels_nb

      cond do
        count == "plural" or definiteness == "definite" ->
          declined_form(lemma, length, c1, ends_consonant?)

        count == "singular" and gender == "neuter" and ends_consonant? ->
          neuter_t(lemma, length, c1)

        true ->
          lemma
      end
    end
  end

  # Plural/definite adjective form with syncope (vakker → vakre).
  defp declined_form(lemma, length, c1, ends_consonant?) do
    c2 = if length > 1, do: String.at(lemma, length - 2)
    c3 = if length > 2, do: String.at(lemma, length - 3)
    c4 = if length > 3, do: String.at(lemma, length - 4)

    cond do
      length > 3 and c2 == "e" and c1 in ["n", "l", "r"] and c3 == c4 and
          c3 not in @vowels_nb ->
        String.slice(lemma, 0, length - 3) <> c1 <> "e"

      length > 3 and c2 == "e" and c1 in ["n", "l", "r"] ->
        String.slice(lemma, 0, length - 2) <> c1 <> "e"

      ends_consonant? ->
        lemma <> "e"

      true ->
        lemma
    end
  end

  defp neuter_t(lemma, length, c1) do
    if length > 2 do
      c2 = String.at(lemma, length - 2)

      cond do
        (c2 == "s" and c1 == "k") or (c2 == "i" and c1 == "g") or (c2 == "e" and c1 == "t") ->
          lemma

        c2 not in @vowels_nb and c1 in ["t", "d"] ->
          lemma

        c2 not in @vowels_nb and c1 == c2 ->
          String.slice(lemma, 0, length - 1) <> "t"

        true ->
          lemma <> "t"
      end
    else
      lemma <> "t"
    end
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
