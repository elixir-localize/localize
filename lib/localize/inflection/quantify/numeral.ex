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

  @masculine_feminine %{"masculine" => "cardinal-masculine", "feminine" => "cardinal-feminine"}
  @masculine_feminine_neuter Map.put(@masculine_feminine, "neuter", "cardinal-neuter")

  # The languages whose numbers take the rule set of the noun's gender,
  # as upstream's `LocalizedCommonConceptFactoryProvider` sets them up.
  @gender_rule_sets %{
    "ar" => @masculine_feminine,
    "bg" => @masculine_feminine_neuter,
    "ca" => @masculine_feminine,
    "da" => %{"common" => "cardinal-common", "neuter" => "cardinal-neuter"},
    "el" => @masculine_feminine_neuter,
    "es" => @masculine_feminine,
    "fr" => @masculine_feminine,
    "is" => @masculine_feminine_neuter,
    "lt" => @masculine_feminine,
    "nb" => @masculine_feminine_neuter,
    "pt" => @masculine_feminine,
    "ro" => @masculine_feminine_neuter,
    "sv" => %{"common" => "cardinal-reale", "neuter" => "cardinal-neuter"}
  }

  # Finnish numbers take the rule set of the noun's case.
  @finnish_cases ~w(ablative adessive allative elative essive genitive illative inessive partitive translative)

  @slavic ~w(cs hr pl ru sk sr uk)

  # The Slavic languages with an animate form of the masculine
  # accusative numeral.
  @animate_accusative ~w(cs hr sk sr uk)

  def formatted(language, locale, number, %Concept{} = concept) do
    cond do
      Map.has_key?(@gender_rule_sets, language) ->
        gendered(Map.fetch!(@gender_rule_sets, language), locale, number, concept)

      language in @slavic ->
        slavic(language, locale, number, concept)

      true ->
        language_specific(language, locale, number, concept)
    end
  end

  defp language_specific("de", locale, number, concept) do
    rule =
      german_rule(
        Quantify.feature_print(concept, "case"),
        Quantify.feature_print(concept, "gender")
      )

    spoken(number, locale, rule)
  end

  defp language_specific("fi", locale, number, concept) do
    base =
      case Quantify.feature_print(concept, "case") do
        grammatical_case when grammatical_case in @finnish_cases ->
          "cardinal-" <> grammatical_case

        _nominative ->
          "cardinal"
      end

    rule = if Finnish.use_plural?(concept), do: base <> "-plural", else: base
    NumberConcept.spoken_words(number, locale, rule)
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
    with 1 <- NumberConcept.whole(number),
         article when not is_nil(article) <- Concept.feature_value(concept, "indefArticle") do
      {:ok, article_print(article)}
    else
      _other -> NumberConcept.spoken_words(number, locale, "cardinal-masculine")
    end
  end

  defp language_specific(_language, locale, number, _concept) do
    NumberConcept.digits(number, locale)
  end

  defp gendered(rule_sets, locale, number, concept) do
    spoken(number, locale, Map.get(rule_sets, Quantify.feature_print(concept, "gender")))
  end

  defp german_rule(grammatical_case, gender) when grammatical_case in ["", "nominative"] do
    Map.get(@masculine_feminine_neuter, gender)
  end

  defp german_rule("genitive", gender) when gender in ["masculine", "neuter"], do: "cardinal-s"
  defp german_rule("genitive", "feminine"), do: "cardinal-r"
  defp german_rule("dative", gender) when gender in ["masculine", "neuter"], do: "cardinal-m"
  defp german_rule("dative", "feminine"), do: "cardinal-r"
  defp german_rule("accusative", "masculine"), do: "cardinal-n"
  defp german_rule("accusative", gender), do: Map.get(@masculine_feminine_neuter, gender)
  defp german_rule(_grammatical_case, _gender), do: nil

  # Slavic numbers agree with the noun's gender and case; with no known
  # gender they are digits.
  defp slavic(language, locale, number, concept) do
    case Quantify.feature_print(concept, "gender") do
      "" ->
        NumberConcept.digits(number, locale)

      gender ->
        grammatical_case = Quantify.feature_print(concept, "case")
        rule = slavic_rule(language, concept, gender, grammatical_case)
        NumberConcept.spoken_words(number, locale, rule)
    end
  end

  defp slavic_rule("pl", concept, gender, grammatical_case) do
    grammatical_case = if grammatical_case == "nominative", do: "", else: grammatical_case

    animacy =
      if gender == "masculine", do: Quantify.feature_print(concept, "animacy"), else: ""

    cond do
      animacy == "human" and grammatical_case in ["", "accusative"] ->
        rule_name(["cardinal", gender, grammatical_case, "personal"])

      animacy == "animate" and grammatical_case == "accusative" ->
        "cardinal-masculine-accusative-animate"

      true ->
        rule_name(["cardinal", gender, grammatical_case])
    end
  end

  defp slavic_rule(language, concept, "masculine", "accusative")
       when language in @animate_accusative do
    if Quantify.feature_print(concept, "animacy") in ["animate", "human"],
      do: "cardinal-masculine-animate-accusative",
      else: "cardinal-masculine-accusative"
  end

  defp slavic_rule(_language, _concept, gender, grammatical_case)
       when grammatical_case in ["", "nominative"],
       do: "cardinal-" <> gender

  defp slavic_rule(_language, _concept, gender, grammatical_case),
    do: rule_name(["cardinal", gender, grammatical_case])

  defp rule_name(parts), do: parts |> Enum.reject(&(&1 == "")) |> Enum.join("-")

  # The article is one of the feature's values, which come as atoms.
  defp article_print(article) when is_atom(article), do: Atom.to_string(article)
  defp article_print(article), do: SpeakableString.print(article)

  defp spoken(number, locale, nil), do: NumberConcept.digits(number, locale)
  defp spoken(number, locale, rule), do: NumberConcept.spoken_words(number, locale, rule)
end
