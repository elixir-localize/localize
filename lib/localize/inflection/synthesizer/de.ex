defmodule Localize.Inflection.Synthesizer.De do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

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

  # The stems of the ein-words, after which an adjective declines
  # mixed: the negative article and the possessives, in every case
  # form ("keinem", "unsrer", "eurem"). The indefinite article itself
  # is marked in the dictionary.
  @ein_word_stems ~w(kein mein dein sein ihr unser unsr euer eur)

  # The der-words the dictionary has no entry for ("dieser" it has), which
  # decline with the definite article's endings; and those endings by
  # number, gender and case, the plural keyed by "masculine" as the
  # negated-article table is.
  @der_word_stems ~w(jen jed welch manch solch)

  @der_word_endings %{
    {"singular", "masculine", "nominative"} => "er",
    {"singular", "masculine", "accusative"} => "en",
    {"singular", "masculine", "dative"} => "em",
    {"singular", "masculine", "genitive"} => "es",
    {"singular", "feminine", "nominative"} => "e",
    {"singular", "feminine", "accusative"} => "e",
    {"singular", "feminine", "dative"} => "er",
    {"singular", "feminine", "genitive"} => "er",
    {"singular", "neuter", "nominative"} => "es",
    {"singular", "neuter", "accusative"} => "es",
    {"singular", "neuter", "dative"} => "em",
    {"singular", "neuter", "genitive"} => "es",
    {"plural", "masculine", "nominative"} => "e",
    {"plural", "masculine", "accusative"} => "e",
    {"plural", "masculine", "dative"} => "en",
    {"plural", "masculine", "genitive"} => "er"
  }

  # The declension endings a lower-case adjective form may carry, longest
  # first, so "guten" is tried as "gut" before "gute" would be.
  @adjective_endings ~w(en em er es e)

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

        if match?([_, _ | _], tokens) do
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
    case List.first(display_data) do
      %DisplayValue{display_string: ""} ->
        nil

      %DisplayValue{} = display_value ->
        inflected_display(display_data, display_value, constraints, guess?)

      _no_display_value ->
        nil
    end
  end

  defp inflected_display(display_data, display_value, constraints, guess?) do
    display_string = display_value.display_string

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

  # The head word is the last token and the dependent word the token
  # immediately before the last whitespace gap, as upstream reads them;
  # hyphenated compounds ("Domain-Eigentümer") stay attached to the
  # head group, so "der Domain-Eigentümer" yields dependent "der", head
  # "Eigentümer". A determiner and adjectives before an adjective
  # dependent are inflected with it, which upstream does not do: it
  # inflects the two words and leaves "das" of "das kleine Haus" as it
  # is.
  defp inflect_token_chain(display_string, constraints, guess?) do
    tokens = Tokenizer.word_tokens(@locale, display_string)
    groups = whitespace_groups(display_string, tokens)

    case List.last(tokens) do
      nil ->
        :error

      head_token ->
        dependent_token = dependent_token(groups)
        phrase = noun_phrase(groups, dependent_token, head_token)

        result =
          cond do
            phrase ->
              inflect_noun_phrase(phrase, constraints, guess?)

            dependent_token ->
              inflect_dependent_and_head(dependent_token, head_token, constraints, guess?)

            true ->
              inflect_head(head_token, constraints, guess?)
          end

        with {:ok, replacements} <- result do
          {:ok, rebuild(display_string, tokens, replacements)}
        end
    end
  end

  # Tokens grouped by the whitespace between them: tokens with no
  # whitespace between them, as the parts of a hyphenated compound,
  # form one group.
  defp whitespace_groups(_display_string, []) do
    []
  end

  defp whitespace_groups(display_string, [first | rest]) do
    {groups, current} =
      Enum.reduce(rest, {[], [first]}, fn token, {groups, [previous | _rest] = current} ->
        gap = binary_part(display_string, previous.stop, token.start - previous.stop)

        if gap =~ ~r/\s/ do
          {[Enum.reverse(current) | groups], [token]}
        else
          {groups, [token | current]}
        end
      end)

    Enum.reverse([Enum.reverse(current) | groups])
  end

  defp dependent_token(groups) do
    case Enum.at(groups, -2) do
      nil -> nil
      group -> List.last(group)
    end
  end

  defp inflect_head(head_token, constraints, guess?) do
    head_type = Dictionary.combined_grammemes(@locale, head_token.value)

    with {:ok, head} <- inflect_word(head_token.value, head_type, constraints, [], guess?) do
      {:ok, %{head_token => head}}
    end
  end

  defp inflect_dependent_and_head(dependent_token, head_token, constraints, guess?) do
    with {:ok, {head, dependent}} <-
           inflect_two_words(dependent_token.value, head_token.value, constraints, guess?) do
      {:ok, %{head_token => head, dependent_token => dependent}}
    end
  end

  # A noun phrase of a determiner, adjectives and a noun, as
  # `{determiner_token | nil, adjective_tokens, head_token}`, where the
  # dependent is an adjective before a noun and at least one more
  # adjective or a determiner stands before it; nil otherwise, so two
  # words keep upstream's reading. The walk back from the dependent
  # stops at any other word, or at a hyphenated group.
  defp noun_phrase([_first, _second, _third | _rest] = groups, dependent_token, head_token)
       when not is_nil(dependent_token) do
    if adjective_before_noun?(dependent_token, head_token) do
      earlier = groups |> Enum.drop(-2) |> Enum.reverse()

      case phrase_front(earlier, []) do
        {nil, []} -> nil
        {determiner, adjectives} -> {determiner, adjectives ++ [dependent_token], head_token}
      end
    end
  end

  defp noun_phrase(_groups, _dependent_token, _head_token) do
    nil
  end

  defp adjective_before_noun?(dependent_token, head_token) do
    noun = Dictionary.binary_properties(@locale, ["noun"]) || 0
    head_type = Dictionary.combined_grammemes(@locale, head_token.value) || 0

    phrase_adjective?(dependent_token) and (head_type &&& noun) != 0
  end

  # A token is an adjective of a phrase where the dictionary reads its
  # form as an adjective and not as a noun, or, for a word in lower
  # case, where the form less a declension ending is an adjective the
  # dictionary knows: "gute" is only the noun "das Gute" to it and
  # "junge" only a verb, where "gut" and "jung" are adjectives. A noun
  # is written with a capital, so the lower-case form is the adjective.
  defp phrase_adjective?(token) do
    noun = Dictionary.binary_properties(@locale, ["noun"]) || 0
    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0
    type = Dictionary.combined_grammemes(@locale, token.value) || 0

    ((type &&& adjective) != 0 and (type &&& noun) == 0) or
      (lower_case?(token.value) and not is_nil(adjective_stem(token.value)))
  end

  # The adjective the dictionary knows a declined lower-case form by,
  # "gut" for "gute" or "guten"; nil where no ending leaves one.
  defp adjective_stem(word) do
    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0

    Enum.find_value(@adjective_endings, fn ending ->
      stem = String.replace_suffix(word, ending, "")
      type = Dictionary.combined_grammemes(@locale, stem) || 0

      if stem != word and stem != "" and (type &&& adjective) != 0 do
        stem
      end
    end)
  end

  defp lower_case?(word) do
    first = String.first(word) || ""
    first == String.downcase(first) and first != String.upcase(first)
  end

  defp phrase_front([[token] | rest], adjectives) do
    noun = Dictionary.binary_properties(@locale, ["noun"]) || 0
    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0
    determiner = Dictionary.binary_properties(@locale, ["article", "pronoun"]) || 0
    type = Dictionary.combined_grammemes(@locale, token.value) || 0

    # The possessive "sein" is only the verb in the dictionary, and the
    # der-words "jeder" and "welcher" are not in it, so an ein-word or a
    # der-word with no nominal reading counts as a determiner too.
    cond do
      phrase_adjective?(token) ->
        phrase_front(rest, [token | adjectives])

      (type &&& determiner) != 0 ->
        {token, adjectives}

      (ein_word?(token.value) or der_word?(token.value)) and
          (type &&& (noun ||| adjective)) == 0 ->
        {token, adjectives}

      true ->
        {nil, adjectives}
    end
  end

  defp phrase_front(_groups, adjectives) do
    {nil, adjectives}
  end

  # The case comes from the determiner, the number and gender from the
  # noun, each where the constraints do not give it, as for a
  # determiner and a noun; without a determiner the number is singular
  # unless given, as for an adjective and a noun. The adjectives take
  # the declension the determiner selects.
  defp inflect_noun_phrase({determiner, adjectives, head_token}, constraints, guess?) do
    noun = head_token.value
    noun_type = Dictionary.combined_grammemes(@locale, noun) || 0
    noun_mask = Dictionary.binary_properties(@locale, ["noun"]) || 0
    determiner_mask = Dictionary.binary_properties(@locale, ["article", "pronoun"]) || 0

    best_head = best_reading(noun, noun_mask)
    best_dep = determiner && best_reading(determiner.value, determiner_mask)

    {case_, number, gender} = agreement = agreement(constraints, best_dep, best_head, determiner)
    deduced = Enum.reject([case_, number, gender], &is_nil/1)
    declension = phrase_declension(constraints, determiner)

    phrase_constraints =
      constraints
      |> Map.merge(%{"case" => case_, "number" => number, "gender" => gender})
      |> Map.reject(fn {_feature, value} -> is_nil(value) end)

    with {:ok, inflected_noun} <- inflect_word(noun, noun_type, constraints, deduced, guess?),
         {:ok, inflected_determiner} <-
           inflect_determiner(determiner, constraints, deduced, agreement, guess?) do
      inflected_adjectives =
        for token <- adjectives do
          {token,
           inflect_phrase_adjective(token, deduced, declension, phrase_constraints, gender)}
        end

      replacements =
        Map.new([{head_token, inflected_noun} | inflected_adjectives])
        |> Map.merge(inflected_determiner)

      {:ok, replacements}
    end
  end

  # The case, number and gender a phrase agrees in: each the
  # constraints' own, else deduced, the case from the determiner's best
  # reading and the number and gender from the noun's, with no gender
  # in the plural, as upstream deduces them for a determiner and a noun.
  # Without a determiner the number is singular unless given, as
  # upstream reads an adjective and a noun.
  defp agreement(constraints, best_dep, best_head, determiner) do
    case_mask = Dictionary.binary_properties(@locale, @cases) || 0
    count_mask = Dictionary.binary_properties(@locale, @numbers) || 0
    gender_mask = Dictionary.binary_properties(@locale, @genders) || 0

    case_ = deduced_value(constraints, "case", best_dep, case_mask)

    number =
      if determiner do
        deduced_value(constraints, "number", best_head, count_mask)
      else
        deduced_value(constraints, "number", nil, count_mask) || "singular"
      end

    gender =
      if number == "plural" do
        nil
      else
        deduced_value(constraints, "gender", best_head, gender_mask)
      end

    {case_, number, gender}
  end

  defp inflect_determiner(nil, _constraints, _deduced, _agreement, _guess?) do
    {:ok, %{}}
  end

  defp inflect_determiner(token, constraints, deduced, agreement, guess?) do
    type = Dictionary.combined_grammemes(@locale, token.value) || 0

    with {:ok, inflected} <-
           inflect_determiner_word(token.value, type, constraints, deduced, agreement, guess?) do
      {:ok, %{token => inflected}}
    end
  end

  # A determiner is inflected from the dictionary. An ein-word the
  # dictionary leaves as it is, listed without inflection rows ("kein",
  # "seinem", "Ihrem"), known only as a personal pronoun ("ihr", the
  # dative of "sie") or only as the verb ("sein"), is inflected as the
  # negative article is, on its own stem.
  defp inflect_determiner_word(word, type, constraints, deduced, agreement, guess?) do
    case inflect_word(word, type, constraints, deduced, guess?) do
      {:ok, inflected} when inflected == word ->
        {:ok, determiner_form(word, agreement) || inflected}

      {:ok, inflected} ->
        {:ok, inflected}

      :error ->
        determiner_form_or_error(word, agreement)
    end
  end

  defp determiner_form_or_error(word, agreement) do
    case determiner_form(word, agreement) do
      nil -> :error
      form -> {:ok, form}
    end
  end

  # The form of an ein-word or a der-word the dictionary does not
  # inflect; nil for any other word, or where the agreement is unknown.
  defp determiner_form(word, agreement) do
    cond do
      ein_word?(word) -> ein_word_form(word, agreement)
      der_word?(word) -> der_word_form(word, agreement)
      true -> nil
    end
  end

  defp ein_word?(word) do
    String.starts_with?(String.downcase(word), @ein_word_stems)
  end

  defp der_word?(word) do
    String.starts_with?(String.downcase(word), @der_word_stems)
  end

  # The der-word's form for the agreement: the definite article's ending
  # on the word's stem, so "jeder" is "jedem" in the dative.
  defp der_word_form(word, {case_, number, gender}) do
    gender =
      if number == "plural" do
        "masculine"
      else
        gender
      end

    case Map.get(@der_word_endings, {number, gender, case_}) do
      nil ->
        nil

      ending ->
        stem = Enum.find(@der_word_stems, &String.starts_with?(String.downcase(word), &1))
        binary_part(word, 0, byte_size(stem)) <> ending
    end
  end

  # The ein-word's form for the agreement, nil where the case or the
  # number is unknown: the negative article's form with "kein" replaced
  # by the word's own stem, so "mein" is "meinem" where "kein" is
  # "keinem". "euer" and "unser" keep their e only before no ending.
  defp ein_word_form(word, {case_, number, gender}) do
    gender =
      if number == "plural" do
        "masculine"
      else
        gender
      end

    case Map.get(table(:negated), {number, gender, case_}) do
      nil ->
        nil

      form ->
        ending = String.replace_prefix(form, "kein", "")
        stem = Enum.find(@ein_word_stems, &String.starts_with?(String.downcase(word), &1))
        ein_word_stem(binary_part(word, 0, byte_size(stem)), ending) <> ending
    end
  end

  defp ein_word_stem(stem, ending) when ending != "" do
    case String.downcase(stem) do
      "euer" -> binary_part(stem, 0, 2) <> "r"
      _other -> stem
    end
  end

  defp ein_word_stem(stem, "") do
    case String.downcase(stem) do
      "eur" -> binary_part(stem, 0, 2) <> "er"
      "unsr" -> binary_part(stem, 0, 3) <> "er"
      _other -> stem
    end
  end

  defp phrase_declension(constraints, determiner) do
    case Map.get(constraints, "declension", "") do
      "" -> determiner_declension(determiner)
      declension -> declension
    end
  end

  # An adjective is weak after a definite article or another der-word
  # ("dieser"), mixed after an indefinite article or an ein-word (the
  # negative and the possessives) and strong with no determiner. The
  # dictionary marks the articles; the ein-words are known by their
  # stems.
  defp determiner_declension(nil) do
    "strong"
  end

  defp determiner_declension(token) do
    type = Dictionary.combined_grammemes(@locale, token.value) || 0
    definite = Dictionary.binary_properties(@locale, ["definite"]) || 0
    indefinite = Dictionary.binary_properties(@locale, ["indefinite"]) || 0

    cond do
      (type &&& definite) != 0 -> "weak"
      (type &&& indefinite) != 0 -> "mixed"
      String.starts_with?(token.clean, @ein_word_stems) -> "mixed"
      true -> "weak"
    end
  end

  defp inflect_phrase_adjective(token, deduced, declension, phrase_constraints, gender) do
    adjective_type = Dictionary.combined_grammemes(@locale, token.value) || 0
    adjective = Dictionary.binary_properties(@locale, ["adjective"]) || 0

    if (adjective_type &&& adjective) != 0 do
      inflect_read_adjective(
        token,
        adjective_type,
        deduced,
        declension,
        phrase_constraints,
        gender
      )
    else
      constraints = Map.put(phrase_constraints, "declension", declension)
      declension_adjective(adjective_stem(token.value) || token.value, constraints, gender || "")
    end
  end

  # An adjective the dictionary reads as one: inflected by its tables,
  # or, where they cannot reach the case, by a declension suffix on its
  # lemma.
  defp inflect_read_adjective(
         token,
         adjective_type,
         deduced,
         declension,
         phrase_constraints,
         gender
       ) do
    disambiguation =
      for value <- [Map.get(phrase_constraints, "pos")], value not in [nil, ""], do: value

    options = [disambiguation: disambiguation, priorities: @priorities]

    case Inflector.inflect(@locale, token.value, adjective_type, deduced ++ [declension], options) do
      {:ok, inflected} ->
        inflected

      :error ->
        constraints = Map.put(phrase_constraints, "declension", declension)

        declension_adjective(
          adjective_lemma(token.value, adjective_type),
          constraints,
          gender || ""
        )
    end
  end

  # The lemma a declension suffix is added to, for an adjective the
  # dictionary knows but cannot inflect to a case: the word without the
  # suffix its own reading carries ("schöne" is "schön"), or, where the
  # dictionary lists whole forms rather than suffixes ("alte" among
  # "alt", "altem", "alten"), the predicative positive form.
  defp adjective_lemma(word, word_type) do
    patterns = Dictionary.patterns_for_word(@locale, word)
    rows = Enum.flat_map(patterns, &Dictionary.matching_inflections(word, word_type, &1))

    strip =
      rows
      |> Enum.map(fn {_grammemes, suffix} -> suffix end)
      |> Enum.filter(&String.ends_with?(word, &1))
      |> Enum.map(&byte_size/1)
      |> Enum.max(fn -> 0 end)

    if strip < byte_size(word) do
      binary_part(word, 0, byte_size(word) - strip)
    else
      predicative_form(patterns) || word
    end
  end

  defp predicative_form(patterns) do
    predicative = Dictionary.binary_properties(@locale, ["predicative", "positive"]) || 0

    Enum.find_value(patterns, fn pattern ->
      Enum.find_value(pattern.inflections, fn {grammemes, form} ->
        if (grammemes &&& predicative) == predicative do
          form
        end
      end)
    end)
  end

  defp rebuild(display_string, tokens, replacements) do
    {output, position} =
      Enum.reduce(tokens, {"", 0}, fn token, {output, position} ->
        separator = binary_part(display_string, position, token.start - position)
        replacement = Map.get(replacements, token, token.value)
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

    best_dep = best_reading(determiner, determiner_mask)
    best_head = best_reading(noun, noun_mask)

    {case_, number, gender} = agreement = agreement(constraints, best_dep, best_head, determiner)
    deduced = Enum.reject([case_, number, gender], &is_nil/1)

    with {:ok, inflected_head} <- inflect_word(noun, noun_type, constraints, deduced, guess?),
         {:ok, inflected_dep} <-
           inflect_determiner_word(determiner, det_type, constraints, deduced, agreement, guess?) do
      {:ok, {inflected_head, inflected_dep}}
    end
  end

  # The value of a feature: the constraints' own, else the one the best
  # reading carries, else nil.
  defp deduced_value(constraints, feature, best_reading, mask) do
    case Map.get(constraints, feature) do
      value when value not in [nil, ""] ->
        value

      _missing when best_reading != nil ->
        first_property_name(best_reading &&& mask)

      _missing ->
        nil
    end
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
        {noun_gender(constraints, inflected_noun), "singular"}
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

  # The gender of a noun: the one gender its readings together carry,
  # else the constraints', as upstream reads it; else the gender of its
  # best noun reading, which upstream does not consult, so a noun with
  # a reading in another gender ("Haus" has a masculine genitive one)
  # still agrees.
  defp noun_gender(constraints, noun) do
    case gender_string(constraints, Dictionary.combined_grammemes(@locale, noun) || 0) do
      "" -> best_reading_gender(noun)
      gender -> gender
    end
  end

  defp best_reading_gender(noun) do
    noun_mask = Dictionary.binary_properties(@locale, ["noun"]) || 0
    gender_mask = Dictionary.binary_properties(@locale, @genders) || 0

    case best_reading(noun, noun_mask) do
      nil -> ""
      reading -> first_property_name(reading &&& gender_mask) || ""
    end
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
