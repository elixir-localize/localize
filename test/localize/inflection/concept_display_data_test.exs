defmodule Localize.Inflection.ConceptDisplayDataTest do
  # A concept with display data, the equivalent of upstream's
  # SemanticConcept: it renders as the first of its forms that holds
  # every constraint put on it, takes its features from that form, and
  # otherwise renders as the locale's rules inflect its value. Expected
  # values are the forms each test gives, English and Spanish grammar,
  # and the concept of upstream's MF2 fixtures
  # (test/resources/inflection/message2/ru_RU.xml, as of #209).
  use ExUnit.Case, async: true

  alias Localize.Inflection.{Concept, ConceptList, PronounConcept, Quantify}

  describe "rendering" do
    test "a concept renders as the form that holds every constraint (upstream)" do
      assert render(ru_concept(), gender: :neuter, case: :genitive, number: :singular) ==
               "genitive,singular"

      assert render(ru_concept(), case: :dative, number: :plural) == "dative,plural"
    end

    test "the first form that holds the constraints wins" do
      {:ok, concept} =
        Concept.new(:en, "octopus",
          display_data: [{"octopodes", %{number: :plural}}, {"octopi", %{number: :plural}}]
        )

      assert render(concept, number: :plural) == "octopodes"
    end

    test "without constraints a concept renders as its value" do
      assert Concept.to_speakable_string(octopus()) == "octopus"
    end

    test "when no form holds the constraints, the locale's rules inflect the value" do
      assert render(octopus(), definiteness: :definite) == "the octopus"
    end

    test "a form can carry a spoken form, which a speak constraint overrides" do
      {:ok, concept} =
        Concept.new(:en, "light", display_data: [{{"lights", "lites"}, %{number: :plural}}])

      assert render(concept, number: :plural) == {"lights", "lites"}
      assert render(concept, number: :plural, speak: "lytes") == {"lights", "lytes"}
    end
  end

  describe "features" do
    test "come from the form the concept renders as" do
      concept = ru_concept()

      assert Concept.feature_value(concept, :gender) == :neuter
      assert Concept.feature_value(concept, :case) == :nominative

      {:ok, genitive} = Concept.put_constraint(concept, :case, :genitive)

      assert Concept.feature_value(genitive, :case) == :genitive
      assert Concept.feature_value(genitive, :number) == :singular
      assert Concept.feature_value(genitive, :gender) == :neuter
    end

    test "a feature the form does not have comes from the locale's rules" do
      {:ok, concept} = Concept.new(:ru, "перо", display_data: [{"перу", %{case: :dative}}])

      assert Concept.feature_value(concept, :gender) == :neuter
    end
  end

  describe "with other parts of the engine" do
    test "a quantity takes the concept's form" do
      assert Quantify.quantify_formatted(:en, "2", octopus(), plural: :other) ==
               {:ok, "2 octopodes"}

      assert Quantify.quantify_formatted(:en, "1", octopus(), plural: :one) ==
               {:ok, "1 octopus"}
    end

    test "a list renders each member's form" do
      {:ok, dog} = Concept.new(:en, "dog")
      {:ok, list} = ConceptList.and_list(:en, [octopus(), dog])
      {:ok, list} = ConceptList.put_constraint(list, :number, :plural)

      assert ConceptList.to_speakable_string(list) == "octopodes and dogs"
    end

    test "a pronoun agrees with the form of its referent" do
      {:ok, referent} =
        Concept.new(:es, "Zorbix",
          display_data: [{"Zorbixes", %{gender: :feminine, number: :plural}}]
        )

      {:ok, referent} = Concept.put_constraint(referent, :number, :plural)
      {:ok, pronoun} = PronounConcept.new(:es, initial_pronoun: "mío")

      assert PronounConcept.to_speakable_string(pronoun, referent) == "mías"
    end
  end

  test "invalid display data is an error, not a crash" do
    for display_data <- [
          [{"cats", %{bogus: :plural}}],
          [{"cats", %{number: :dual}}],
          [{"cats", "plural"}],
          [{:cats, %{number: :plural}}],
          ["cats"],
          "cats",
          nil
        ] do
      assert {:error, _} = Concept.new(:en, "cat", display_data: display_data)
    end
  end

  defp octopus do
    {:ok, concept} =
      Concept.new(:en, "octopus", display_data: [{"octopodes", %{number: :plural}}])

    concept
  end

  # Upstream's fixture concept: a neuter noun whose twelve case and
  # number forms name themselves, in upstream's order. Its first form
  # is its own, with the features it has.
  defp ru_concept do
    forms =
      for number <- ["singular", "plural"],
          grammatical_case <-
            ["nominative", "instrumental", "accusative", "dative", "genitive", "prepositional"] do
        {"#{grammatical_case},#{number}",
         %{gender: "neuter", case: grammatical_case, number: number}}
      end

    [{value, initial} | _forms] = forms
    {:ok, concept} = Concept.new(:ru, value, initial: initial, display_data: forms)
    concept
  end

  defp render(concept, constraints) do
    constraints
    |> Enum.reduce(concept, fn {name, value}, concept ->
      {:ok, concept} = Concept.put_constraint(concept, name, value)
      concept
    end)
    |> Concept.to_speakable_string()
  end
end
