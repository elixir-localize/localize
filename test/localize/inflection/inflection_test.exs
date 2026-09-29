defmodule Localize.InflectionTest do
  use ExUnit.Case
  doctest Localize.Inflection
  doctest Localize.Inflection.Concept
  doctest Localize.Inflection.PronounConcept
  doctest Localize.Inflection.SpeakableString
  doctest Localize.Inflection.Dictionary
  doctest Localize.Inflection.Inflector
  doctest Localize.Inflection.DataDir
  doctest Localize.Inflection.Provider
  doctest Localize.Inflection.Quantify
  doctest Localize.Inflection.ConceptList

  # A locale is a well-formed identifier, never a path. "../" in one once
  # reached files outside the inflection data directory, loaded them, and
  # minted a fresh atom for each spelling of the path.
  test "a locale that is not a locale identifier names no inflection data" do
    traversal = "../../localize/locales/en"

    assert Localize.Inflection.Locale.normalize(traversal) == ""

    assert {:error, %Localize.InflectionNotSupportedError{}} =
             Localize.Inflection.Locale.resolve(traversal)

    assert {:error, %Localize.InflectionNotSupportedError{}} =
             Localize.Inflection.inflect("Haus", traversal, case: "dative")
  end

  test "a path-shaped locale creates no atom" do
    probe = "./inflection_probe_#{System.unique_integer([:positive])}"

    assert {:error, _exception} = Localize.Inflection.Locale.resolve(probe)
    assert_raise ArgumentError, fn -> String.to_existing_atom(probe) end
  end

  test "inflects with invalid constraints" do
    assert {:error, %Localize.UnknownFeatureError{feature: "sizzle"}} =
             Localize.Inflection.inflect("cat", :en, sizzle: "plural")

    assert {:error, %Localize.InvalidValueError{value: "dual", context: "number"}} =
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
    assert {:error, %Localize.UnknownPronounError{pronoun: "garbage"}} =
             Localize.Inflection.pronoun(:en, "garbage", person: "first")

    assert {:error, %Localize.InflectionNotSupportedError{locale: :tlh}} =
             Localize.Inflection.pronoun(:tlh, person: "first")
  end

  test "locales are accepted as strings, matching LanguageTag canonical_locale_id" do
    assert Localize.Inflection.inflect("cat", "en", number: :plural) == {:ok, "cats"}
    assert Localize.Inflection.feature("luces", "es", :number) == {:ok, :plural}

    assert Localize.Inflection.pronoun("zh-TW", person: :first) ==
             Localize.Inflection.pronoun(:"zh-TW", person: :first)

    assert {:ok, _values} = Localize.Inflection.feature_values("de", :case)

    assert Localize.Inflection.inflect("cat", "tlh", number: :plural) ==
             {:error, %Localize.InflectionNotSupportedError{locale: "tlh"}}
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

  test "English takes \"an\" before numbers spoken with a leading vowel" do
    for {text, article} <- [
          {"8", "an"},
          {"11", "an"},
          {"18", "an"},
          {"800", "an"},
          {"18000", "an"},
          {"7", "a"},
          {"1,800", "a"},
          {"+8", "a"},
          {",8", "a"}
        ] do
      assert Localize.Inflection.inflect(text, :en, definiteness: :indefinite) ==
               {:ok, "#{article} #{text}"}
    end
  end

  # Extensions name no inflection data, so a locale with them inflects
  # by its language's rules. Expected values from upstream's QuantifyTest
  # (ar_SA, zh_CN) and MF2 fixtures (es_MX), and the Turkish and
  # Taiwanese grammar tested elsewhere; each but the pronoun differed
  # while the extensions were kept.
  test "a locale's extensions do not change its inflection rules" do
    alias Localize.Inflection.{Concept, ConceptList, Locale, PronounConcept, Quantify}

    assert Locale.normalize("ar-SA-u-nu-arab") == "ar_SA"
    assert Locale.normalize("ca-ES-valencia-u-nu-latn") == "ca_ES_valencia"
    assert Locale.normalize("en-US-x-twain") == "en_US"
    assert Locale.normalize("x-twain") == ""

    {:ok, message} = Concept.new("ar-SA-u-ca-islamic", "رسالة")
    assert Quantify.quantify("ar-SA-u-ca-islamic", 2, message) == {:ok, "رسالتان"}

    {:ok, word} = Concept.new("zh-u-ca-chinese", "word")
    assert Quantify.quantify("zh-u-ca-chinese", 1, word) == {:ok, "1word"}

    {:ok, cats} = Concept.new("es-u-co-trad", "gatos")
    {:ok, languages} = Concept.new("es-u-co-trad", "idiomas")
    {:ok, list} = ConceptList.and_list("es-u-co-trad", [cats, languages])
    assert ConceptList.to_speakable_string(list) == "gatos e idiomas"

    {:ok, you} = PronounConcept.new("zh-TW-u-ca-roc")
    {:ok, you} = PronounConcept.put_constraint(you, :person, :second)
    {:ok, you} = PronounConcept.put_constraint(you, :gender, :feminine)
    assert PronounConcept.to_speakable_string(you) == "妳"

    assert Localize.Unit.to_string(Localize.Unit.new!(2, "kilometer"),
             locale: "tr-u-ca-gregory",
             grammatical_case: :dative,
             inflect: :safe
           ) == {:ok, "2 kilometreye"}
  end
end
