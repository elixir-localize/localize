defmodule Localize.InflectionTest do
  use ExUnit.Case
  doctest Localize.Inflection
  doctest Localize.Inflection.Concept
  doctest Localize.Inflection.PronounConcept
  doctest Localize.Inflection.SpeakableString
  doctest Localize.Inflection.Dictionary
  doctest Localize.Inflection.Inflector
  doctest Localize.Inflection.DataDir
  doctest Localize.Inflection.Quantify

  test "inflects with invalid constraints" do
    assert {:error, {:unknown_feature, "sizzle"}} =
             Localize.Inflection.inflect("cat", :en, sizzle: "plural")

    assert {:error, {:invalid_feature_value, "number", "dual"}} =
             Localize.Inflection.inflect("cat", :en, number: "dual")
  end

  test "an explicit speak constraint carries into the rendered value" do
    {:ok, concept} =
      Localize.Inflection.Concept.new(:en, "record", constraints: %{"speak" => "rec-ORD"})

    assert Localize.Inflection.Concept.to_speakable_string(concept) == {"record", "rec-ORD"}

    {:ok, concept} =
      Localize.Inflection.Concept.new(:en, "light",
        constraints: %{"number" => "plural", "speak" => "lites"}
      )

    assert Localize.Inflection.Concept.to_speakable_string(concept) == {"lights", "lites"}
  end

  test "pronoun errors" do
    assert {:error, {:unknown_pronoun, "garbage"}} =
             Localize.Inflection.pronoun(:en, "garbage", person: "first")

    assert {:error, {:unknown_locale, :tlh}} = Localize.Inflection.pronoun(:tlh, person: "first")
  end

  test "locales are accepted as strings, matching LanguageTag canonical_locale_id" do
    assert Localize.Inflection.inflect("cat", "en", number: :plural) == {:ok, "cats"}
    assert Localize.Inflection.feature("luces", "es", :number) == {:ok, :plural}

    assert Localize.Inflection.pronoun("zh-TW", person: :first) ==
             Localize.Inflection.pronoun(:"zh-TW", person: :first)

    assert {:ok, _values} = Localize.Inflection.feature_values("de", :case)

    assert Localize.Inflection.inflect("cat", "tlh", number: :plural) ==
             {:error, {:unknown_locale, "tlh"}}
  end

  test "regional locales fall back to their base language" do
    assert Localize.Inflection.inflect("cat", :"en-GB", number: :plural) == {:ok, "cats"}

    assert Localize.Inflection.inflect("Haus", "de-CH", case: :dative, number: :plural) ==
             {:ok, "Häusern"}

    assert Localize.Inflection.feature("luces", "es-MX", :number) == {:ok, :plural}
    assert {:ok, _values} = Localize.Inflection.feature_values(:"fr-CA", :case)
  end

  test "locales are accepted in BCP47 and underscore forms" do
    {:ok, bcp47} = Localize.Inflection.PronounConcept.new(:"zh-TW")
    {:ok, underscore} = Localize.Inflection.PronounConcept.new(:zh_TW)

    assert bcp47.locale == underscore.locale
    assert bcp47.table_locale == "zh_Hant"

    assert Localize.Inflection.pronoun(:"yue-CN", person: :first) ==
             Localize.Inflection.pronoun(:yue_CN, person: :first)
  end

  test "pronoun falls back to the generic entry when nothing matches" do
    {:ok, concept} = Localize.Inflection.PronounConcept.new(:en)

    {:ok, concept} =
      Localize.Inflection.PronounConcept.put_constraint(concept, "person", "second")

    {:ok, concept} =
      Localize.Inflection.PronounConcept.put_constraint(concept, "definiteness", "definite")

    refute Localize.Inflection.PronounConcept.exists?(concept)
    assert Localize.Inflection.PronounConcept.to_speakable_string(concept) == "they"
  end

  test "custom pronoun display data is matched before the locale table" do
    display_data = [
      {"y'all", %{"person" => "second", "number" => "plural", "case" => "nominative"}}
    ]

    {:ok, concept} = Localize.Inflection.PronounConcept.new(:en, display_data: display_data)

    {:ok, concept} =
      Localize.Inflection.PronounConcept.put_constraint(concept, "person", "second")

    assert Localize.Inflection.PronounConcept.to_speakable_string(concept) == "y'all"
    assert Localize.Inflection.PronounConcept.custom_match?(concept)

    {:ok, singular} =
      Localize.Inflection.PronounConcept.put_constraint(concept, "number", "singular")

    assert Localize.Inflection.PronounConcept.to_speakable_string(singular) == "you"
    refute Localize.Inflection.PronounConcept.custom_match?(singular)

    {:ok, plural} = Localize.Inflection.PronounConcept.put_constraint(concept, "number", "plural")
    assert Localize.Inflection.PronounConcept.to_speakable_string(plural) == "y'all"
  end
end
