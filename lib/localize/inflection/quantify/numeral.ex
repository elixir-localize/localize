defmodule Localize.Inflection.Quantify.Numeral do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity

  # The number of a quantity as upstream's `CommonConceptFactory`
  # `quantify` writes it before joining it to the noun: digits, spoken
  # as words from the rule set that agrees with the noun where the
  # language's numbers agree (in gender, and in case in German, Finnish
  # and the Slavic languages), and written as a word for the smallest
  # numbers in Hebrew and Italian.

  alias Localize.Inflection.{Concept, NumberConcept, Quantify, SpeakableString}
  alias Localize.Inflection.Quantify.Finnish

  # The words of a number come from the `spellout-cardinal` rule set that
  # `Localize.Number.Rbnf` chooses for the noun's grammatical features
  # (`NumberConcept.spoken_cardinal/3`), given here as a map of
  # grammatical options. Which features each language's numbers agree in
  # is upstream's; the rule-set names are CLDR's, and the resolver reads
  # them, so none is spelled out here.

  @masculine_feminine ~w(masculine feminine)
  @masculine_feminine_neuter ~w(masculine feminine neuter)

  # The languages whose numbers agree with the noun's gender, and the
  # genders they agree in, as upstream's
  # `LocalizedCommonConceptFactoryProvider` sets them up. A noun of
  # another gender takes digits.
  @gender_agreement %{
    "ar" => @masculine_feminine,
    "bg" => @masculine_feminine_neuter,
    "ca" => @masculine_feminine,
    "da" => ~w(common neuter),
    "el" => @masculine_feminine_neuter,
    "es" => @masculine_feminine,
    "fr" => @masculine_feminine,
    "is" => @masculine_feminine_neuter,
    "lt" => @masculine_feminine,
    "nb" => @masculine_feminine_neuter,
    "pt" => @masculine_feminine,
    "ro" => @masculine_feminine_neuter,
    "sv" => ~w(common neuter)
  }

  # Finnish numbers take the rule set of the noun's case.
  @finnish_cases ~w(ablative adessive allative elative essive genitive illative inessive partitive translative)

  @slavic ~w(cs hr pl ru sk sr uk)

  # The Slavic languages with an animate form of the masculine
  # accusative numeral.
  @animate_accusative ~w(cs hr sk sr uk)

  def formatted(language, locale, number, %Concept{} = concept) do
    cond do
      Map.has_key?(@gender_agreement, language) ->
        gendered(Map.fetch!(@gender_agreement, language), locale, number, concept)

      language in @slavic ->
        slavic(language, locale, number, concept)

      true ->
        language_specific(language, locale, number, concept)
    end
  end

  defp language_specific("de", locale, number, concept) do
    grammatical_case = Quantify.feature_print(concept, "case")
    gender = Quantify.feature_print(concept, "gender")

    if grammatical_case == "genitive" do
      german_genitive(number, locale, gender)
    else
      spoken(number, locale, german_grammar(grammatical_case, gender))
    end
  end

  defp language_specific("fi", locale, number, concept) do
    base =
      case Quantify.feature_print(concept, "case") do
        grammatical_case when grammatical_case in @finnish_cases ->
          %{grammatical_case: grammatical_case}

        _nominative ->
          %{}
      end

    grammar =
      if Finnish.use_plural?(concept) do
        Map.put(base, :grammatical_number, "plural")
      else
        base
      end

    NumberConcept.spoken_cardinal(number, locale, grammar)
  end

  defp language_specific("he", locale, number, concept) do
    whole = NumberConcept.whole(number)
    definite? = Map.get(concept.constraints, "definiteness") == "definite"

    formatted =
      case {Quantify.feature_print(concept, "gender"), definite?} do
        {"masculine", true} when whole == 1 -> {:ok, SpeakableString.new("1", "היחיד")}
        {"masculine", true} -> NumberConcept.spoken_words(number, locale, "construct-masculine")
        {"masculine", false} -> NumberConcept.spoken_words(number, locale, "cardinal-masculine")
        {"feminine", true} when whole == 1 -> {:ok, SpeakableString.new("1", "היחידה")}
        {"feminine", true} -> NumberConcept.spoken_words(number, locale, "construct-feminine")
        {"feminine", false} -> NumberConcept.spoken_words(number, locale, "cardinal-feminine")
        # Upstream raises for a noun of no known gender.
        _unknown -> NumberConcept.digits(number, locale)
      end

    # One and two are written as the words they are spoken as.
    case formatted do
      {:ok, speakable} when whole in [1, 2] -> {:ok, SpeakableString.speak(speakable)}
      other -> other
    end
  end

  defp language_specific("it", locale, number, concept) do
    # One is the noun's indefinite article, as it is spoken.
    indefinite_article(NumberConcept.whole(number), locale, number, concept)
  end

  defp language_specific(_language, locale, number, _concept) do
    NumberConcept.digits(number, locale)
  end

  # Only one, and only where the concept names an article, is spoken as one.
  defp indefinite_article(1, locale, number, concept) do
    case Concept.feature_value(concept, "indefArticle") do
      nil -> NumberConcept.spoken_cardinal(number, locale, %{grammatical_gender: "masculine"})
      article -> {:ok, article_print(article)}
    end
  end

  defp indefinite_article(_whole, locale, number, _concept) do
    NumberConcept.spoken_cardinal(number, locale, %{grammatical_gender: "masculine"})
  end

  defp gendered(genders, locale, number, concept) do
    gender = Quantify.feature_print(concept, "gender")

    if gender in genders do
      spoken(number, locale, %{grammatical_gender: gender})
    else
      spoken(number, locale, nil)
    end
  end

  # German numbers agree in gender and in the dative and accusative;
  # upstream gives a noun of no known gender digits.
  defp german_grammar(grammatical_case, gender) when grammatical_case in ["", "nominative"] do
    if gender in @masculine_feminine_neuter do
      %{grammatical_gender: gender}
    end
  end

  defp german_grammar(grammatical_case, gender)
       when grammatical_case in ["dative", "accusative"] do
    if gender in @masculine_feminine_neuter do
      %{grammatical_gender: gender, grammatical_case: grammatical_case}
    end
  end

  defp german_grammar(_grammatical_case, _gender) do
    nil
  end

  # The genitive keeps upstream's rule sets, named by their endings
  # (`cardinal-s` for "eines", `cardinal-r` for "einer"), which write
  # "zwei Kinder". CLDR's feature-named genitive rule sets write the
  # declined "zweier", which upstream's tests do not expect.
  defp german_genitive(number, locale, gender) when gender in ["masculine", "neuter"] do
    NumberConcept.spoken_words(number, locale, "cardinal-s")
  end

  defp german_genitive(number, locale, "feminine") do
    NumberConcept.spoken_words(number, locale, "cardinal-r")
  end

  defp german_genitive(number, locale, _gender) do
    NumberConcept.digits(number, locale)
  end

  # Slavic numbers agree with the noun's gender and case; with no known
  # gender they are digits.
  defp slavic(language, locale, number, concept) do
    case Quantify.feature_print(concept, "gender") do
      "" ->
        NumberConcept.digits(number, locale)

      gender ->
        grammatical_case = Quantify.feature_print(concept, "case")
        grammar = slavic_grammar(language, concept, gender, grammatical_case)
        NumberConcept.spoken_cardinal(number, locale, grammar)
    end
  end

  # A masculine noun's animacy is read in CLDR's model, as a gender of
  # its own: Polish `personal` for a human noun, `animate` for another.
  defp slavic_grammar("pl", concept, gender, grammatical_case) do
    animacy =
      if gender == "masculine", do: Quantify.feature_print(concept, "animacy"), else: ""

    cond do
      animacy == "human" and grammatical_case in ["", "nominative", "accusative"] ->
        with_case(%{grammatical_gender: "personal"}, grammatical_case)

      animacy == "animate" and grammatical_case == "accusative" ->
        %{grammatical_gender: "animate", grammatical_case: "accusative"}

      true ->
        with_case(%{grammatical_gender: gender}, grammatical_case)
    end
  end

  defp slavic_grammar(language, concept, "masculine", "accusative")
       when language in @animate_accusative do
    if Quantify.feature_print(concept, "animacy") in ["animate", "human"] do
      %{grammatical_gender: "animate", grammatical_case: "accusative"}
    else
      %{grammatical_gender: "masculine", grammatical_case: "accusative"}
    end
  end

  defp slavic_grammar(_language, _concept, gender, grammatical_case) do
    with_case(%{grammatical_gender: gender}, grammatical_case)
  end

  defp with_case(grammar, grammatical_case) when grammatical_case in ["", "nominative"] do
    grammar
  end

  defp with_case(grammar, grammatical_case) do
    Map.put(grammar, :grammatical_case, grammatical_case)
  end

  # The article is one of the feature's values, which come as atoms.
  defp article_print(article) when is_atom(article), do: Atom.to_string(article)
  defp article_print(article), do: SpeakableString.print(article)

  defp spoken(number, locale, nil), do: NumberConcept.digits(number, locale)

  defp spoken(number, locale, grammar) do
    NumberConcept.spoken_cardinal(number, locale, grammar)
  end
end
