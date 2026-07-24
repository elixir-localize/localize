defmodule Localize.Inflection.Synthesizer.De do
  @moduledoc false

  # The German grammar synthesizer, ported from
  # `DeGrammarSynthesizer` and its lookup and display functions.
  # Articles and adjective endings are keyed by
  # {number, gender, case}.

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

  @locale :de

  @numbers ["singular", "plural"]
  @genders ["masculine", "feminine", "neuter"]
  @cases ["nominative", "accusative", "dative", "genitive"]
  @declensions ["strong", "mixed", "weak"]

  @priorities [
    ["article", "pronoun", "noun", "proper-noun", "adjective"],
    ["nominative", "accusative", "genitive", "dative"],
    ["singular", "plural"],
    ["strong", "mixed", "weak"],
    ["masculine", "feminine"]
  ]

  # Article tables keyed {number, gender, case}. Plural forms do not
  # vary by gender, so plural rows are expanded over all genders.
  defp expand_plural(rows) do
    Enum.flat_map(rows, fn
      {{"plural", :all, case_}, article} ->
        for gender <- @genders, do: {{"plural", gender, case_}, article}

      row ->
        [row]
    end)
    |> Map.new()
  end

  defp table(:pronoun) do
    expand_plural([
      {{"plural", :all, "accusative"}, "sie"},
      {{"plural", :all, "dative"}, "ihnen"},
      {{"plural", :all, "genitive"}, "ihrer"},
      {{"plural", :all, "nominative"}, "sie"},
      {{"singular", "feminine", "accusative"}, "sie"},
      {{"singular", "feminine", "dative"}, "ihr"},
      {{"singular", "feminine", "genitive"}, "ihrer"},
      {{"singular", "feminine", "nominative"}, "sie"},
      {{"singular", "masculine", "accusative"}, "ihn"},
      {{"singular", "masculine", "dative"}, "ihm"},
      {{"singular", "masculine", "genitive"}, "seiner"},
      {{"singular", "masculine", "nominative"}, "er"},
      {{"singular", "neuter", "accusative"}, "es"},
      {{"singular", "neuter", "dative"}, "ihm"},
      {{"singular", "neuter", "genitive"}, "seiner"},
      {{"singular", "neuter", "nominative"}, "es"}
    ])
  end

  defp table(:definite) do
    expand_plural([
      {{"plural", :all, "accusative"}, "die"},
      {{"plural", :all, "dative"}, "den"},
      {{"plural", :all, "genitive"}, "der"},
      {{"plural", :all, "nominative"}, "die"},
      {{"singular", "feminine", "accusative"}, "die"},
      {{"singular", "feminine", "dative"}, "der"},
      {{"singular", "feminine", "genitive"}, "der"},
      {{"singular", "feminine", "nominative"}, "die"},
      {{"singular", "masculine", "accusative"}, "den"},
      {{"singular", "masculine", "dative"}, "dem"},
      {{"singular", "masculine", "genitive"}, "des"},
      {{"singular", "masculine", "nominative"}, "der"},
      {{"singular", "neuter", "accusative"}, "das"},
      {{"singular", "neuter", "dative"}, "dem"},
      {{"singular", "neuter", "genitive"}, "des"},
      {{"singular", "neuter", "nominative"}, "das"}
    ])
  end

  defp table(:definite_in_preposition) do
    expand_plural([
      {{"plural", :all, "accusative"}, "in die"},
      {{"plural", :all, "dative"}, "in den"},
      {{"plural", :all, "genitive"}, "in der"},
      {{"plural", :all, "nominative"}, "in die"},
      {{"singular", "feminine", "accusative"}, "in die"},
      {{"singular", "feminine", "dative"}, "in der"},
      {{"singular", "feminine", "genitive"}, "in der"},
      {{"singular", "feminine", "nominative"}, "in die"},
      {{"singular", "masculine", "accusative"}, "in den"},
      {{"singular", "masculine", "dative"}, "im"},
      {{"singular", "masculine", "genitive"}, "in des"},
      {{"singular", "masculine", "nominative"}, "in der"},
      {{"singular", "neuter", "accusative"}, "ins"},
      {{"singular", "neuter", "dative"}, "im"},
      {{"singular", "neuter", "genitive"}, "in des"},
      {{"singular", "neuter", "nominative"}, "ins"}
    ])
  end

  defp table(:indefinite) do
    Map.new([
      {{"singular", "feminine", "accusative"}, "eine"},
      {{"singular", "feminine", "dative"}, "einer"},
      {{"singular", "feminine", "genitive"}, "einer"},
      {{"singular", "feminine", "nominative"}, "eine"},
      {{"singular", "masculine", "accusative"}, "einen"},
      {{"singular", "masculine", "dative"}, "einem"},
      {{"singular", "masculine", "genitive"}, "eines"},
      {{"singular", "masculine", "nominative"}, "ein"},
      {{"singular", "neuter", "accusative"}, "ein"},
      {{"singular", "neuter", "dative"}, "einem"},
      {{"singular", "neuter", "genitive"}, "eines"},
      {{"singular", "neuter", "nominative"}, "ein"}
    ])
  end

  defp table(:demonstrative) do
    expand_plural([
      {{"plural", :all, "accusative"}, "diesen"},
      {{"plural", :all, "dative"}, "diesen"},
      {{"plural", :all, "genitive"}, "dieser"},
      {{"plural", :all, "nominative"}, "diese"},
      {{"singular", "feminine", "accusative"}, "diese"},
      {{"singular", "feminine", "dative"}, "dieser"},
      {{"singular", "feminine", "genitive"}, "dieser"},
      {{"singular", "feminine", "nominative"}, "diese"},
      {{"singular", "masculine", "accusative"}, "diesen"},
      {{"singular", "masculine", "dative"}, "diesem"},
      {{"singular", "masculine", "genitive"}, "dieses"},
      {{"singular", "masculine", "nominative"}, "dieser"},
      {{"singular", "neuter", "accusative"}, "dieses"},
      {{"singular", "neuter", "dative"}, "diesem"},
      {{"singular", "neuter", "genitive"}, "dieses"},
      {{"singular", "neuter", "nominative"}, "dieses"}
    ])
  end

  defp table(:negated) do
    expand_plural([
      {{"plural", :all, "accusative"}, "keine"},
      {{"plural", :all, "dative"}, "keinen"},
      {{"plural", :all, "genitive"}, "keiner"},
      {{"plural", :all, "nominative"}, "keine"},
      {{"singular", "feminine", "accusative"}, "keine"},
      {{"singular", "feminine", "dative"}, "keiner"},
      {{"singular", "feminine", "genitive"}, "keiner"},
      {{"singular", "feminine", "nominative"}, "keine"},
      {{"singular", "masculine", "accusative"}, "keinen"},
      {{"singular", "masculine", "dative"}, "keinem"},
      {{"singular", "masculine", "genitive"}, "keines"},
      {{"singular", "masculine", "nominative"}, "kein"},
      {{"singular", "neuter", "accusative"}, "kein"},
      {{"singular", "neuter", "dative"}, "keinem"},
      {{"singular", "neuter", "genitive"}, "keines"},
      {{"singular", "neuter", "nominative"}, "kein"}
    ])
  end

  defp table(:possessive_second) do
    expand_plural([
      {{"plural", :all, "accusative"}, "deine"},
      {{"plural", :all, "dative"}, "deinen"},
      {{"plural", :all, "genitive"}, "deiner"},
      {{"plural", :all, "nominative"}, "deine"},
      {{"singular", "feminine", "accusative"}, "deine"},
      {{"singular", "feminine", "dative"}, "deiner"},
      {{"singular", "feminine", "genitive"}, "deiner"},
      {{"singular", "feminine", "nominative"}, "deine"},
      {{"singular", "masculine", "accusative"}, "deinen"},
      {{"singular", "masculine", "dative"}, "deinem"},
      {{"singular", "masculine", "genitive"}, "deines"},
      {{"singular", "masculine", "nominative"}, "dein"},
      {{"singular", "neuter", "accusative"}, "dein"},
      {{"singular", "neuter", "dative"}, "deinem"},
      {{"singular", "neuter", "genitive"}, "deines"},
      {{"singular", "neuter", "nominative"}, "dein"}
    ])
  end

  defp table(:interrogative) do
    expand_plural([
      {{"plural", :all, "accusative"}, "welche"},
      {{"plural", :all, "dative"}, "welchen"},
      {{"plural", :all, "genitive"}, "welcher"},
      {{"plural", :all, "nominative"}, "welche"},
      {{"singular", "feminine", "accusative"}, "welche"},
      {{"singular", "feminine", "dative"}, "welcher"},
      {{"singular", "feminine", "genitive"}, "welcher"},
      {{"singular", "feminine", "nominative"}, "welche"},
      {{"singular", "masculine", "accusative"}, "welchen"},
      {{"singular", "masculine", "dative"}, "welchem"},
      {{"singular", "masculine", "genitive"}, "welches"},
      {{"singular", "masculine", "nominative"}, "welcher"},
      {{"singular", "neuter", "accusative"}, "welches"},
      {{"singular", "neuter", "dative"}, "welchem"},
      {{"singular", "neuter", "genitive"}, "welches"},
      {{"singular", "neuter", "nominative"}, "welches"}
    ])
  end

  # feature name -> {table key, include_semantic_value?}
  @article_features %{
    "pronoun" => {:pronoun, false},
    "withPronoun" => {:pronoun, true},
    "possessivePronoun" => {:pronoun, false},
    "withPossessivePronoun" => {:pronoun, true},
    "defArticle" => {:definite, false},
    "defArticleInPreposition" => {:definite_in_preposition, false},
    "withDefArticleInPreposition" => {:definite_in_preposition, true},
    "indefArticle" => {:indefinite, false},
    "demonArticle" => {:demonstrative, false},
    "withDemonArticle" => {:demonstrative, true},
    "negArticle" => {:negated, false},
    "withNegArticle" => {:negated, true},
    "possArticle" => {:possessive_second, false},
    "withPossArticle" => {:possessive_second, true},
    "interrogativeArticle" => {:interrogative, false},
    "withInterrogativeArticle" => {:interrogative, true}
  }

  @strong_suffixes %{
    {"plural", :all, :all} => "en",
    {"singular", "feminine", "accusative"} => "e",
    {"singular", "feminine", "dative"} => "er",
    {"singular", "feminine", "genitive"} => "er",
    {"singular", "feminine", "nominative"} => "e",
    {"singular", "masculine", "accusative"} => "en",
    {"singular", "masculine", "dative"} => "em",
    {"singular", "masculine", "genitive"} => "en",
    {"singular", "masculine", "nominative"} => "er",
    {"singular", "neuter", "accusative"} => "es",
    {"singular", "neuter", "dative"} => "em",
    {"singular", "neuter", "genitive"} => "en",
    {"singular", "neuter", "nominative"} => "es"
  }

  @weak_suffixes %{
    {"plural", :all, :all} => "en",
    {"singular", "feminine", "accusative"} => "e",
    {"singular", "feminine", "dative"} => "en",
    {"singular", "feminine", "genitive"} => "en",
    {"singular", "feminine", "nominative"} => "e",
    {"singular", "masculine", "accusative"} => "en",
    {"singular", "masculine", "dative"} => "en",
    {"singular", "masculine", "genitive"} => "en",
    {"singular", "masculine", "nominative"} => "e",
    {"singular", "neuter", "accusative"} => "e",
    {"singular", "neuter", "dative"} => "en",
    {"singular", "neuter", "genitive"} => "en",
    {"singular", "neuter", "nominative"} => "e"
  }

  @mixed_suffixes %{
    {"plural", :all, :all} => "en",
    {"singular", "feminine", "accusative"} => "e",
    {"singular", "feminine", "dative"} => "en",
    {"singular", "feminine", "genitive"} => "en",
    {"singular", "feminine", "nominative"} => "e",
    {"singular", "masculine", "accusative"} => "en",
    {"singular", "masculine", "dative"} => "en",
    {"singular", "masculine", "genitive"} => "en",
    {"singular", "masculine", "nominative"} => "er",
    {"singular", "neuter", "accusative"} => "es",
    {"singular", "neuter", "dative"} => "en",
    {"singular", "neuter", "genitive"} => "en",
    {"singular", "neuter", "nominative"} => "es"
  }

  # STRONG plural is case-sensitive, unlike weak/mixed.
  @strong_plural %{
    "accusative" => "e",
    "dative" => "en",
    "genitive" => "er",
    "nominative" => "e"
  }

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("number", display_value, _constraints) do
    empty_to_nil(Lookup.determine(@locale, display_value.display_string, @numbers))
  end

  def feature_value("gender", display_value, _constraints) do
    empty_to_nil(Lookup.determine(@locale, display_value.display_string, @genders))
  end

  def feature_value(feature, display_value, _constraints)
      when is_map_key(@article_features, feature) do
    {table_key, include?} = Map.fetch!(@article_features, feature)
    article_lookup(table_key, display_value, include?)
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  defp article_lookup(table_key, display_value, include?) do
    key = article_key(display_value)
    article = Map.get(table(table_key), key, "")
    Articles.create_preposition(display_value, article, include?)
  end

  defp article_key(display_value) do
    case_ = parse(Map.get(display_value.constraints, "case"), @cases) || "nominative"
    count = parse(Map.get(display_value.constraints, "number"), @numbers)
    gender = parse(Map.get(display_value.constraints, "gender"), @genders)

    phrase_type =
      if count == nil or gender == nil do
        phrase_grammemes(display_value.display_string)
      else
        0
      end

    count = count || deduce_count(phrase_type)
    gender = gender || deduce_gender(phrase_type)
    {count, gender, case_}
  end

  defp phrase_grammemes(display_string) do
    case Dictionary.combined_grammemes(@locale, display_string) do
      nil ->
        tokens = Tokenizer.word_tokens(@locale, display_string)

        if length(tokens) > 1 do
          last = List.last(tokens)
          Dictionary.combined_grammemes(@locale, last.value) || 0
        else
          0
        end

      properties ->
        properties
    end
  end

  defp deduce_count(phrase_type) do
    mask = Dictionary.binary_properties(@locale, @numbers) || 0
    plural = Dictionary.binary_properties(@locale, ["plural"]) || 0

    if phrase_type != 0 and (phrase_type &&& mask) == plural do
      "plural"
    else
      "singular"
    end
  end

  defp deduce_gender(phrase_type) do
    if phrase_type == 0 do
      nil
    else
      mask = Dictionary.binary_properties(@locale, @genders) || 0
      Dictionary.property_name(@locale, phrase_type &&& mask)
    end
  end

  defp parse(value, _allowed) when value in [nil, ""], do: nil
  defp parse(value, allowed), do: if(value in allowed, do: value)

  @impl true
  def display_value(display_data, constraints, guess?) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      result =
        if map_size(constraints) > 0 do
          apply_constraints(display_data, display_value, display_string, constraints, guess?)
        else
          {:ok, display_string}
        end

      case result do
        :error ->
          nil

        {:done, done_value} ->
          done_value

        {:ok, display_string} when display_string != "" ->
          add_definiteness(
            %DisplayValue{display_string: display_string, constraints: constraints},
            constraints
          )

        _other ->
          nil
      end
    else
      _other -> nil
    end
  end

  defp apply_constraints(display_data, _display_value, display_string, constraints, guess?) do
    declension = Map.get(constraints, "declension", "")

    declined =
      if declension != "" do
        inflect_by_declension(display_data, constraints, declension)
      end

    if declined do
      {:done, add_definiteness(declined, constraints)}
    else
      pos = Map.get(constraints, "pos", "")
      case_ = Map.get(constraints, "case", "")

      result =
        cond do
          case_ == "genitive" and pos == "proper-noun" and String.length(display_string) > 1 ->
            {:ok, genitive_proper_noun(display_string)}

          Dictionary.combined_grammemes(@locale, display_string) != nil ->
            inflect_word(
              display_string,
              Dictionary.combined_grammemes(@locale, display_string),
              constraints,
              [],
              guess?
            )

          true ->
            inflect_token_chain(display_string, constraints, guess?)
        end

      case result do
        {:ok, inflected} -> {:ok, inflected}
        :error when guess? -> {:ok, display_string}
        :error -> :error
      end
    end
  end

  # Adjective declension via display data values carrying a stem.
  defp inflect_by_declension(display_data, constraints, declension) do
    if declension in @declensions do
      case_ = Map.get(constraints, "case", "")
      count = Map.get(constraints, "number", "")
      gender = Map.get(constraints, "gender", "")

      exact =
        Enum.find(display_data, fn value ->
          vc = value.constraints

          (case_ == "" or case_ == Map.get(vc, "case")) and
            (count == "" or count == Map.get(vc, "number")) and
            (gender == "" or gender == Map.get(vc, "gender")) and
            not Map.has_key?(vc, "declension")
        end)

      stemmed = Enum.find(display_data, &Map.has_key?(&1.constraints, "stem"))

      cond do
        exact ->
          %DisplayValue{display_string: exact.display_string, constraints: exact.constraints}

        stemmed ->
          stem =
            case Map.get(stemmed.constraints, "stem") do
              value when value in [nil, ""] -> stemmed.display_string
              value -> value
            end

          result = declension_adjective(stem, constraints, gender)
          form_constraints = Map.merge(constraints, stemmed.constraints)
          %DisplayValue{display_string: result, constraints: form_constraints}

        true ->
          nil
      end
    end
  end

  defp declension_adjective(lemma, constraints, target_gender) do
    declension = Map.get(constraints, "declension", "")

    if declension == "" do
      lemma
    else
      count = parse(Map.get(constraints, "number"), @numbers)
      gender = parse(target_gender, @genders)
      case_ = parse(Map.get(constraints, "case"), @cases)
      suffix = declension_suffix(declension, count, gender, case_)

      if suffix, do: lemma <> suffix, else: lemma
    end
  end

  defp declension_suffix(_declension, count, gender, case_)
       when is_nil(count) or is_nil(case_) or (count == "singular" and is_nil(gender)) do
    nil
  end

  defp declension_suffix("strong", "plural", _gender, case_), do: Map.get(@strong_plural, case_)
  defp declension_suffix("weak", "plural", _gender, _case), do: "en"
  defp declension_suffix("mixed", "plural", _gender, _case), do: "en"

  defp declension_suffix(declension, "singular", gender, case_) do
    table =
      case declension do
        "strong" -> @strong_suffixes
        "weak" -> @weak_suffixes
        "mixed" -> @mixed_suffixes
      end

    Map.get(table, {"singular", gender, case_})
  end

  defp genitive_proper_noun(display_string) do
    last = display_string |> String.last() |> String.downcase()

    second_last =
      case String.length(display_string) do
        length when length >= 2 -> display_string |> String.at(length - 2) |> String.downcase()
        _short -> ""
      end

    cond do
      last in ["s", "z", "x", "ß"] or (last == "e" and second_last == "c") ->
        display_string <> "’"

      last != "’" ->
        display_string <> "s"

      true ->
        display_string
    end
  end

  defp inflect_word(word, word_grammemes, constraints, deduced, guess?) do
    word_grammemes = word_grammemes || 0
    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0

    constraint_values =
      if deduced == [] do
        features =
          if (word_grammemes &&& adjective) != 0 do
            ["number", "gender", "case", "declension"]
          else
            ["number", "gender", "case"]
          end

        for feature <- features,
            value = Map.get(constraints, feature),
            value not in [nil, ""],
            do: value
      else
        deduced
      end

    disambiguation = for value <- [Map.get(constraints, "pos")], value not in [nil, ""], do: value
    options = [disambiguation: disambiguation, priorities: @priorities]

    case Inflector.inflect(@locale, word, word_grammemes, constraint_values, options) do
      {:ok, inflected} ->
        {:ok, inflected}

      :error when guess? ->
        {:ok, declension_adjective(word, constraints, Map.get(constraints, "gender", ""))}

      :error ->
        :error
    end
  end

  defp inflect_token_chain(display_string, constraints, guess?) do
    tokens = Tokenizer.word_tokens(@locale, display_string)

    case List.last(tokens) do
      nil ->
        :error

      head_token ->
        dependent_token = dependent_before_whitespace(display_string, tokens)

        result =
          if dependent_token do
            inflect_two_words(dependent_token.value, head_token.value, constraints, guess?)
          else
            case inflect_word(
                   head_token.value,
                   Dictionary.combined_grammemes(@locale, head_token.value),
                   constraints,
                   [],
                   guess?
                 ) do
              {:ok, head} -> {:ok, {head, nil}}
              :error -> :error
            end
          end

        case result do
          :error ->
            :error

          {:ok, {inflected_head, inflected_dependent}} ->
            {:ok,
             rebuild(
               display_string,
               tokens,
               head_token,
               inflected_head,
               dependent_token,
               inflected_dependent
             )}
        end
    end
  end

  # The dependent word is the token immediately before the last
  # whitespace gap — hyphenated compounds ("Domain-Eigentümer")
  # stay attached to the head group, so "der Domain-Eigentümer"
  # yields dependent "der", head "Eigentümer".
  defp dependent_before_whitespace(display_string, tokens) do
    tokens
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reverse()
    |> Enum.find_value(fn [left, right] ->
      gap = binary_part(display_string, left.stop, right.start - left.stop)
      if gap =~ ~r/\s/, do: left
    end)
  end

  defp rebuild(display_string, tokens, head_token, head, dependent_token, dependent) do
    {output, position} =
      Enum.reduce(tokens, {"", 0}, fn token, {output, position} ->
        separator = binary_part(display_string, position, token.start - position)

        replacement =
          cond do
            token == head_token -> head
            dependent != nil and token == dependent_token -> dependent
            true -> token.value
          end

        {output <> separator <> replacement, token.stop}
      end)

    output <> binary_part(display_string, position, byte_size(display_string) - position)
  end

  defp inflect_two_words(dependent, head, constraints, guess?) do
    head_type = Dictionary.combined_grammemes(@locale, head) || 0
    dependent_type = Dictionary.combined_grammemes(@locale, dependent) || 0
    determiner = Dictionary.binary_properties(@locale, ["article", "pronoun"]) || 0
    noun = Dictionary.binary_properties(@locale, ["noun"]) || 0
    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0
    verb = Dictionary.binary_properties(@locale, ["verb"]) || 0

    if (dependent_type &&& determiner) != 0 and (head_type &&& noun) != 0 do
      inflect_determiner_and_noun(
        dependent,
        dependent_type,
        head,
        head_type,
        constraints,
        guess?
      )
    else
      with {:ok, inflected_head} <- inflect_word(head, head_type, constraints, [], guess?) do
        cond do
          (dependent_type &&& adjective) != 0 and (dependent_type &&& noun) == 0 and
              (head_type &&& noun) != 0 ->
            {:ok, inflected_dependent} =
              inflect_adjective_next_to_noun(
                dependent,
                dependent_type,
                constraints,
                inflected_head
              )

            {:ok, {inflected_head, inflected_dependent}}

          (dependent_type &&& verb) != 0 and (dependent_type &&& noun) == 0 and
              (head_type &&& noun) != 0 ->
            gender = gender_string(constraints, head_type)
            {:ok, {inflected_head, declension_adjective(dependent, constraints, gender)}}

          true ->
            {:ok, {inflected_head, dependent}}
        end
      end
    end
  end

  defp inflect_determiner_and_noun(determiner, det_type, noun, noun_type, constraints, guess?) do
    determiner_mask = Dictionary.binary_properties(@locale, ["article", "pronoun"]) || 0
    noun_mask = Dictionary.binary_properties(@locale, ["noun"]) || 0
    case_mask = Dictionary.binary_properties(@locale, @cases) || 0
    count_mask = Dictionary.binary_properties(@locale, @numbers) || 0
    gender_mask = Dictionary.binary_properties(@locale, @genders) || 0

    best_dep = best_reading(determiner, determiner_mask)
    best_head = best_reading(noun, noun_mask)

    deduced =
      []
      |> deduce(constraints, "case", best_dep, case_mask)
      |> deduce(constraints, "number", best_head, count_mask)

    deduced =
      if "plural" in deduced do
        deduced
      else
        deduce(deduced, constraints, "gender", best_head, gender_mask)
      end

    with {:ok, inflected_head} <- inflect_word(noun, noun_type, constraints, deduced, guess?),
         {:ok, inflected_dep} <- inflect_word(determiner, det_type, constraints, deduced, guess?) do
      {:ok, {inflected_head, inflected_dep}}
    end
  end

  defp deduce(deduced, constraints, feature, best_reading, mask) do
    value =
      case Map.get(constraints, feature) do
        value when value not in [nil, ""] ->
          value

        _missing when best_reading != nil ->
          first_property_name(best_reading &&& mask)

        _missing ->
          nil
      end

    if value, do: deduced ++ [value], else: deduced
  end

  defp first_property_name(0), do: nil

  defp first_property_name(mask) do
    @locale
    |> Dictionary.property_names(mask)
    |> List.first()
  end

  # The reading of a word (restricted to a part of speech) ranked
  # best by the German priority tables.
  defp best_reading(word, pos_mask) do
    priority_masks =
      for table <- @priorities do
        for name <- table, do: Dictionary.binary_properties(@locale, [name]) || 0
      end

    @locale
    |> Dictionary.grammeme_sets(word)
    |> Enum.filter(&((&1 &&& pos_mask) != 0))
    |> Enum.min_by(
      fn reading ->
        for table <- priority_masks do
          Enum.find_index(table, fn mask -> mask != 0 and (reading &&& mask) == mask end) ||
            length(table)
        end
      end,
      fn -> nil end
    )
  end

  defp inflect_adjective_next_to_noun(adjective, adjective_type, constraints, inflected_noun) do
    case_ = Map.get(constraints, "case", "")
    count = Map.get(constraints, "number", "")
    declension = Map.get(constraints, "declension", "")

    {gender, count} =
      if count == "plural" do
        {"", "plural"}
      else
        {gender_string(constraints, Dictionary.combined_grammemes(@locale, inflected_noun) || 0),
         "singular"}
      end

    declension = if declension == "", do: "strong", else: declension

    constraint_values = Enum.reject([case_, count, gender, declension], &(&1 == ""))
    disambiguation = for value <- [Map.get(constraints, "pos")], value not in [nil, ""], do: value
    options = [disambiguation: disambiguation, priorities: @priorities]

    case Inflector.inflect(@locale, adjective, adjective_type, constraint_values, options) do
      {:ok, inflected} ->
        {:ok, inflected}

      :error ->
        {:ok, declension_adjective(adjective, constraints, gender)}
    end
  end

  defp gender_string(constraints, binary_type) do
    gender_mask = Dictionary.binary_properties(@locale, @genders) || 0

    from_type =
      if binary_type != 0 do
        Dictionary.property_name(@locale, binary_type &&& gender_mask)
      end

    from_type || Map.get(constraints, "gender", "")
  end

  defp add_definiteness(display_value, constraints) do
    Articles.add_definiteness(
      display_value,
      constraints,
      Articles.article_prefixes(@locale, ["defArticle"]),
      Articles.article_prefixes(@locale, ["indefArticle"]),
      fn base, _constraints -> article_lookup(:definite, base, true) end,
      fn base, _constraints -> article_lookup(:indefinite, base, true) end
    )
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
