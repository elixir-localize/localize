defmodule Localize.Message.InflectionFunctionsTest do
  # MF2 `:i:inflect`, `:i:pronoun`, `:i:quantify`, `:i:list` and
  # `:i:numeral`, with the Unicode inflection project's option names.
  # Tests marked "upstream" take their messages and expected values
  # from the print lines of unicode-org/inflection's MF2 test fixtures
  # (test/resources/inflection/message2/*.xml, as of #209). The
  # `:i:numeral` rule-set values come from ICU4C 78.3's
  # RuleBasedNumberFormat, whose default spellout rule set is
  # %spellout-numbering and default ordinal one %digits-ordinal.
  use ExUnit.Case, async: false

  alias Localize.Message

  describe ":i:inflect" do
    test "inflects a phrase for grammatical number" do
      assert {:ok, "lights on the patio"} =
               Message.format("{$w :i:inflect number=plural}", %{w: "light on the patio"},
                 locale: :en
               )
    end

    test "inflects a phrase for grammatical case" do
      assert {:ok, "новым домом"} =
               Message.format("{$w :i:inflect case=instrumental}", %{w: "новый дом"}, locale: :ru)
    end

    test "inflects a phrase for grammatical gender, given as a string or an atom" do
      assert {:ok, "लड़की"} =
               Message.format("{$w :i:inflect gender=feminine}", %{w: "लड़का"}, locale: :hi)

      assert {:ok, "लड़की"} =
               Message.format("{$w :i:inflect gender=$g}", %{w: "लड़का", g: :feminine}, locale: :hi)
    end

    test "a value that is not one of the feature's values is a word to agree with (upstream)" do
      assert {:ok, "The lights are on."} =
               Message.format(
                 "The {$object} {is :i:inflect number=$object} on.",
                 %{object: "lights"},
                 locale: :en
               )

      assert {:ok, "the lights are on."} =
               Message.format(
                 "{$object :i:inflect definiteness=definite} {is :i:inflect number=$object} on.",
                 %{object: "lights"},
                 locale: :en
               )
    end

    test "definiteness adds the article and case gives the genitive (upstream)" do
      message =
        "I didn't find {$relationship :i:inflect definiteness=indefinite} in your contacts. " <>
          "What is your {$relationship :i:inflect case=genitive} name?"

      assert {:ok, "I didn't find a brother in your contacts. What is your brother’s name?"} =
               Message.format(message, %{relationship: "brother"}, locale: :en)

      assert {:ok, "I didn't find an aunt in your contacts. What is your aunt’s name?"} =
               Message.format(message, %{relationship: "aunt"}, locale: :en)
    end

    test "several constraints apply together (upstream)" do
      assert {:ok, "Foo las gatas Bar"} =
               Message.format(
                 "Foo {$name :i:inflect definiteness=definite number=plural gender=feminine} Bar",
                 %{name: "gato"},
                 locale: :es
               )
    end

    test "an option that names no grammatical feature is an error (upstream)" do
      assert {:error, _} =
               Message.format("{$word :i:inflect bogusFeature=value}", %{word: "valid"},
                 locale: :en
               )

      assert {:error, _} =
               Message.format(
                 ".local $v = {$word :i:inflect bogusFeature=value} .match $v\n* {{fallback}}",
                 %{word: "valid"},
                 locale: :en
               )
    end

    test "to gives the phrase's value for a feature, and a selector matches it (upstream)" do
      message = """
      .local $num = {$object :i:inflect to=number} .match $num
      plural {{The {$object} are on}}
      * {{The {$object} is on}}
      """

      for {object, expected} <- [
            {"light", "The light is on"},
            {"lights", "The lights are on"},
            {"lights on the front porch", "The lights on the front porch are on"},
            {"light on the front porch", "The light on the front porch is on"}
          ] do
        assert Message.format(message, %{object: object}, locale: :en) == {:ok, expected}
      end

      assert {:ok, "plural"} =
               Message.format("{$w :i:inflect to=$feature}", %{w: "lights", feature: "number"},
                 locale: :en
               )
    end

    test "to gives the German article with its preposition (upstream)" do
      assert {:ok, "The defArticleInPreposition is in die."} =
               Message.format(
                 "The defArticleInPreposition is " <>
                   "{$name :i:inflect number=singular case=accusative to=defArticleInPreposition}.",
                 %{name: "Bank"},
                 locale: :de
               )

      message = """
      .local $v = {$name :i:inflect number=singular case=dative to=withDefArticleInPreposition}
      .match $v
      |im Fundort| {{matched}}
      * {{other}}
      """

      assert {:ok, "matched"} = Message.format(message, %{name: "Fundort"}, locale: :de)
    end

    test "two selectors match the gender and the number of one phrase (upstream)" do
      message = """
      .local $gender = {$name :i:inflect to=gender}
      .local $number = {$name :i:inflect to=number}
      .match $gender $number
      masculine 2 {{{$name} is Masculine & 2}}
      feminine singular {{{$name} is Feminine & Singular}}
      foo 4 {{{$name} is Foo & 4}}
      masculine singular {{{$name} is Masculine & Singular}}
      hello singular {{{$name} is Hello & Singular}}
      * * {{{$name} is other}}
      """

      assert {:ok, "gato is Masculine & Singular"} =
               Message.format(message, %{name: "gato"}, locale: :es)
    end

    test "an unknown to feature prints the operand and selects only the catch-all (upstream)" do
      assert {:ok, "valid"} =
               Message.format("{$word :i:inflect to=bogus}", %{word: "valid"}, locale: :en)

      message = """
      .local $v = {$word :i:inflect to=bogus} .match $v
      valid {{is valid}}
      * {{other}}
      """

      assert {:ok, "other"} = Message.format(message, %{word: "valid"}, locale: :en)
    end

    test "without to, a selector matches the inflected phrase" do
      message = """
      .local $w = {$word :i:inflect number=plural} .match $w
      cats {{inflected}}
      cat {{uninflected}}
      * {{other}}
      """

      assert {:ok, "inflected"} = Message.format(message, %{word: "cat"}, locale: :en)
    end

    test "a concept operand is inflected, and a concept option value agrees" do
      {:ok, cat} = Localize.Inflection.Concept.new(:en, "cat")
      {:ok, lights} = Localize.Inflection.Concept.new(:en, "lights")

      assert {:ok, "cats"} =
               Message.format("{$c :i:inflect number=plural}", %{c: cat}, locale: :en)

      assert {:ok, "plural"} =
               Message.format("{$c :i:inflect to=number}", %{c: lights}, locale: :en)

      assert {:ok, "are"} = Message.format("{is :i:inflect number=$c}", %{c: lights}, locale: :en)
    end

    test "a concept with display data renders its form, and a selector matches it (upstream)" do
      assert {:ok, "genitive,singular"} =
               Message.format(
                 "{$unit :i:inflect gender=neuter case=genitive number=singular}",
                 %{unit: ru_semantic_concept()},
                 locale: :ru
               )

      message = """
      .local $v = {$unit :i:inflect gender=neuter case=genitive number=singular} .match $v
      |genitive,singular| {{matched genitive singular}}
      * {{other}}
      """

      assert {:ok, "matched genitive singular"} =
               Message.format(message, %{unit: ru_semantic_concept()}, locale: :ru)
    end

    test "a non-string option value is an error" do
      assert {:error, _} =
               Message.format("{$w :i:inflect number=$n}", %{w: "light", n: 2}, locale: :en)

      assert {:error, _} = Message.format("{$w :i:inflect to=5}", %{w: "lights"}, locale: :en)
    end

    test "an operand that is neither a string nor a concept is an error, not a crash" do
      assert {:error, _} = Message.format("{$n :i:inflect case=dative}", %{n: 5}, locale: :ru)

      {:ok, pronoun} = Localize.Inflection.PronounConcept.new(:en)
      assert {:error, _} = Message.format("{$p :i:inflect}", %{p: pronoun}, locale: :en)
    end
  end

  describe ":i:pronoun" do
    test "re-inflects the operand pronoun" do
      assert {:ok, "him"} = Message.format("{|he| :i:pronoun case=accusative}", %{}, locale: :en)
    end

    test "gives a pronoun another gender (upstream)" do
      assert {:ok, "his"} =
               Message.format("{$p :i:pronoun gender=masculine}", %{p: "her"}, locale: :en)
    end

    test "a string that is no pronoun is an error (upstream)" do
      assert {:error, _} = Message.format("{$p :i:pronoun}", %{p: "garbage"}, locale: :en)
    end

    test "a pronoun concept is an operand, and an option value to agree with (upstream)" do
      {:ok, theirs} = Localize.Inflection.PronounConcept.new(:en, initial_pronoun: "theirs")
      {:ok, he} = Localize.Inflection.PronounConcept.new(:en, initial_pronoun: "he")

      assert {:ok, "his"} =
               Message.format("{$p :i:pronoun gender=masculine}", %{p: theirs}, locale: :en)

      assert {:ok, "his"} =
               Message.format("{theirs :i:pronoun gender=$p}", %{p: he}, locale: :en)
    end

    test "a pronoun concept brings its own pronouns (upstream)" do
      {:ok, xe} =
        Localize.Inflection.PronounConcept.new(:en,
          display_data: [
            {"xe", %{person: :third, number: :singular, case: :nominative}},
            {"xem", %{person: :third, number: :singular, case: :accusative}},
            {"xyr", %{person: :third, number: :singular, case: :genitive}}
          ]
        )

      assert {:ok, "xem xe"} =
               Message.format("{$np :i:pronoun case=accusative} {$np :i:pronoun}", %{np: xe},
                 locale: :en
               )
    end

    test "to gives the pronoun's value for a feature, and a selector matches it (upstream)" do
      message = """
      .local $g = {$p :i:pronoun to=gender} .match $g
      feminine {{feminine phrase}}
      masculine {{masculine phrase}}
      * {{other phrase}}
      """

      assert {:ok, "feminine phrase"} = Message.format(message, %{p: "she"}, locale: :en)
      assert {:ok, "masculine phrase"} = Message.format(message, %{p: "him"}, locale: :en)
      assert {:ok, "other phrase"} = Message.format(message, %{p: "they"}, locale: :en)

      assert {:ok, "first"} = Message.format("{$p :i:pronoun to=person}", %{p: "we"}, locale: :en)
      assert {:ok, ""} = Message.format("{$p :i:pronoun to=gender}", %{p: "they"}, locale: :en)
    end

    test "without to, a selector matches the pronoun" do
      message = """
      .local $p = {$s :i:pronoun case=accusative} .match $p
      him {{him}}
      * {{other}}
      """

      assert {:ok, "him"} = Message.format(message, %{s: "he"}, locale: :en)
    end

    test "withReferent chooses the pronoun that agrees with the referent (upstream)" do
      {:ok, casas} = Localize.Inflection.Concept.new(:es, "casas")

      for referent <- ["casas", casas] do
        assert {:ok, "mías"} =
                 Message.format("{$p :i:pronoun withReferent=$obj}", %{p: "mío", obj: referent},
                   locale: :es
                 )
      end
    end

    test "to and withReferent together are an error (upstream)" do
      assert {:error, _} =
               Message.format(
                 "{$p :i:pronoun to=gender withReferent=$obj}",
                 %{p: "her", obj: "cat"},
                 locale: :en
               )
    end

    test "an operand or referent of another kind is an error, not a crash" do
      {:ok, cat} = Localize.Inflection.Concept.new(:en, "cat")

      assert {:error, _} = Message.format("{$p :i:pronoun}", %{p: cat}, locale: :en)
      assert {:error, _} = Message.format("{$p :i:pronoun}", %{p: 5}, locale: :en)

      assert {:error, _} =
               Message.format("{$p :i:pronoun withReferent=$obj}", %{p: "mío", obj: 5},
                 locale: :es
               )
    end
  end

  describe ":i:quantify" do
    test "joins a number with an English noun (upstream)" do
      message = "Your meeting is in {$unit :i:quantify withValue=$n} from now"

      assert {:ok, "Your meeting is in 1 day from now"} =
               Message.format(message, %{unit: "day", n: 1}, locale: :en)

      assert {:ok, "Your meeting is in 2 days from now"} =
               Message.format(message, %{unit: "day", n: 2}, locale: :en)

      assert {:ok, "3 churches were found nearby"} =
               Message.format(
                 "{$unit :i:quantify withValue=$n} were found nearby",
                 %{unit: "church", n: 3},
                 locale: :en
               )
    end

    test "agrees with a Spanish noun (upstream)" do
      message = "Hay {$unit :i:quantify withValue=$n} en el video"

      assert {:ok, "Hay 1 niño en el video"} =
               Message.format(message, %{unit: "niño", n: 1}, locale: :es)

      assert {:ok, "Hay 1 niña en el video"} =
               Message.format(message, %{unit: "niña", n: 1}, locale: :es)

      assert {:ok, "Hay 3 niños en el video"} =
               Message.format(message, %{unit: "niño", n: 3}, locale: :es)
    end

    test "applies Russian numeral government in every case (upstream)" do
      message =
        "{$unit :i:quantify withValue=$n} {$unit :i:quantify withValue=$n case=genitive} " <>
          "{$unit :i:quantify withValue=$n case=accusative} {$unit :i:quantify withValue=$n case=dative} " <>
          "{$unit :i:quantify withValue=$n case=instrumental} {$unit :i:quantify withValue=$n case=prepositional}"

      for {n, expected} <- [
            {1, "1 километр 1 километра 1 километр 1 километру 1 километром 1 километре"},
            {2, "2 километра 2 километров 2 километра 2 километрам 2 километрами 2 километрах"},
            {5, "5 километров 5 километров 5 километров 5 километрам 5 километрами 5 километрах"}
          ] do
        assert Message.format(message, %{unit: "километр", n: n}, locale: :ru) == {:ok, expected}
      end
    end

    test "declines a Finnish noun after a numeral" do
      assert {:ok, "3 taloa"} =
               Message.format("{$noun :i:quantify withValue=3}", %{noun: "talo"}, locale: :fi)
    end

    test "a missing withValue option is an error, not a crash" do
      assert {:error, _} =
               Message.format("{$noun :i:quantify}", %{noun: "kilometer"}, locale: :en)
    end

    test "a non-numeric withValue is an error, not a crash" do
      assert {:error, _} =
               Message.format("{$noun :i:quantify withValue=|abc|}", %{noun: "kilometer"},
                 locale: :en
               )
    end

    test "the reserved withStyle and withVariant options are an error" do
      assert {:error, _} =
               Message.format(
                 "{$noun :i:quantify withValue=2 withStyle=asWords}",
                 %{noun: "kilometer"},
                 locale: :en
               )
    end

    test "a concept operand is quantified" do
      {:ok, day} = Localize.Inflection.Concept.new(:en, "day")

      assert {:ok, "2 days"} =
               Message.format("{$unit :i:quantify withValue=2}", %{unit: day}, locale: :en)
    end

    test "applies Russian numeral government to a concept's own forms (upstream)" do
      message =
        "{$unit :i:quantify withValue=$number} {$unit :i:quantify withValue=$number case=genitive} " <>
          "{$unit :i:quantify withValue=$number case=accusative} {$unit :i:quantify withValue=$number case=dative} " <>
          "{$unit :i:quantify withValue=$number case=instrumental} {$unit :i:quantify withValue=$number case=prepositional}"

      for {number, expected} <- [
            {1,
             "1 nominative,singular 1 genitive,singular 1 accusative,singular " <>
               "1 dative,singular 1 instrumental,singular 1 prepositional,singular"},
            {2,
             "2 genitive,singular 2 genitive,plural 2 genitive,plural " <>
               "2 dative,plural 2 instrumental,plural 2 prepositional,plural"},
            {5,
             "5 genitive,plural 5 genitive,plural 5 genitive,plural " <>
               "5 dative,plural 5 instrumental,plural 5 prepositional,plural"}
          ] do
        assert Message.format(message, %{unit: ru_semantic_concept(), number: number},
                 locale: :ru
               ) ==
                 {:ok, expected}
      end
    end

    test "Italian and Hebrew write the smallest numbers as words (upstream)" do
      for {locale, unit, number, expected} <- [
            {:it, "settimana", 1, "una settimana"},
            {:it, "ora", 1, "un’ora"},
            {:it, "settimana", 2, "2 settimane"},
            {:he, "מכונית", 1, "מכונית אחת"},
            {:he, "מכונית", 2, "שתי מכוניות"},
            {:he, "מכונית", 3, "3 מכוניות"}
          ] do
        assert Message.format("{$unit :i:quantify withValue=$n}", %{unit: unit, n: number},
                 locale: locale
               ) == {:ok, expected}
      end
    end

    test "a non-string operand is an error, not a crash" do
      assert {:error, _} =
               Message.format("{$n :i:quantify withValue=2}", %{n: 5}, locale: :en)
    end
  end

  describe ":i:list" do
    test "an and list agrees its conjunction with the next word (upstream)" do
      message = "¿Te gustan los videos sobre {$words :i:list withType=and}?"

      assert {:ok, "¿Te gustan los videos sobre gatos e idiomas?"} =
               Message.format(message, %{words: ["gatos", "idiomas"]}, locale: :es)

      assert {:ok, "¿Te gustan los videos sobre idiomas y gatos?"} =
               Message.format(message, %{words: ["idiomas", "gatos"]}, locale: :es)
    end

    test "an or list (upstream)" do
      assert {:ok, "¿Te gustan los videos sobre gatos o idiomas?"} =
               Message.format(
                 "¿Te gustan los videos sobre {$words :i:list withType=or}?",
                 %{words: ["gatos", "idiomas"]},
                 locale: :es
               )
    end

    test "a constraint applies to every item (upstream)" do
      message = "¿Te gustan los videos sobre {$words :i:list withType=and definiteness=definite}?"

      assert {:ok, "¿Te gustan los videos sobre el gato, la gata, los gatos y las gatas?"} =
               Message.format(message, %{words: ["gato", "gata", "gatos", "gatas"]}, locale: :es)

      assert {:ok, "¿Te gustan los videos sobre los gatos?"} =
               Message.format(message, %{words: ["gatos"]}, locale: :es)
    end

    test "without a type the items are joined as they are (upstream)" do
      assert {:ok, "gatosidiomas"} =
               Message.format("{$words :i:list}", %{words: ["gatos", "idiomas"]}, locale: :es)
    end

    test "the separators and item affixes can be set (upstream)" do
      assert {:ok, "[gato], [gata] y [gatos]"} =
               Message.format(
                 "{$words :i:list withItemDelimiter=|, | withBeforeLast=| y | withItemPrefix=|[| withItemSuffix=|]|}",
                 %{words: ["gato", "gata", "gatos"]},
                 locale: :es
               )

      assert {:ok, "gato y gata"} =
               Message.format(
                 "{$words :i:list withType=and withAvoidItemAffixRedundancy=false}",
                 %{words: ["gato", "gata"]},
                 locale: :es
               )
    end

    test "a bad operand, type, item or option is an error, not a crash" do
      assert {:error, _} = Message.format("{$w :i:list withType=and}", %{w: "gatos"}, locale: :es)

      assert {:error, _} =
               Message.format("{$w :i:list withType=both}", %{w: ["gatos"]}, locale: :es)

      assert {:error, _} =
               Message.format("{$w :i:list withType=and}", %{w: ["gatos", 2]}, locale: :es)

      assert {:error, _} = Message.format("{$w :i:list withType=and}", %{w: []}, locale: :es)
      assert {:error, _} = Message.format("{$w :i:list sizzle=yes}", %{w: ["gatos"]}, locale: :es)
    end
  end

  describe ":i:numeral" do
    test "writes an ordinal in words and a spoken count in digits (upstream)" do
      assert {:ok, "Your fourth meeting has been canceled"} =
               Message.format(
                 "Your {$n :i:numeral withStyle=asWords withVariant=ordinal} meeting has been canceled",
                 %{n: 4},
                 locale: :en
               )

      assert {:ok, "You have 4 messages"} =
               Message.format(
                 "You have {$count :i:numeral withStyle=asSpokenWords} messages",
                 %{count: 4},
                 locale: :en
               )
    end

    test "words come from the spellout rule sets" do
      assert {:ok, "four"} =
               Message.format("{$n :i:numeral withStyle=asWords}", %{n: 4}, locale: :en)

      assert {:ok, "ein­und­zwanzig"} =
               Message.format("{$n :i:numeral withStyle=asWords}", %{n: 21}, locale: :de)

      assert {:ok, "две"} =
               Message.format(
                 "{$n :i:numeral withStyle=asWords withVariant=cardinal-feminine}",
                 %{n: 2},
                 locale: :ru
               )

      assert {:ok, "tercera"} =
               Message.format(
                 "{$n :i:numeral withStyle=asWords withVariant=ordinal-feminine}",
                 %{n: 3},
                 locale: :es
               )
    end

    test "ordinal digits come from the digits rule sets" do
      assert {:ok, "21st"} =
               Message.format("{$n :i:numeral withStyle=asOrdinalDigits}", %{n: 21}, locale: :en)

      assert {:ok, "21e"} =
               Message.format("{$n :i:numeral withStyle=asOrdinalDigits}", %{n: 21}, locale: :fr)

      assert {:ok, "3.ª"} =
               Message.format(
                 "{$n :i:numeral withStyle=asDigits withVariant=ordinal-feminine}",
                 %{n: 3},
                 locale: :es
               )
    end

    test "without a style, or as plain digits, the number is the locale's decimal format" do
      assert {:ok, "1,234"} = Message.format("{$n :i:numeral}", %{n: 1234}, locale: :en)

      assert {:ok, "1,234"} =
               Message.format("{$n :i:numeral withStyle=asDigits}", %{n: 1234}, locale: :en)
    end

    test "a variant with no rule set in the locale falls back to the default, as upstream does" do
      assert {:ok, "four"} =
               Message.format("{$n :i:numeral withStyle=asWords withVariant=bogus}", %{n: 4},
                 locale: :en
               )
    end

    test "an unknown style or a non-number operand is an error, not a crash" do
      assert {:error, _} =
               Message.format("{$n :i:numeral withStyle=asRunes}", %{n: 4}, locale: :en)

      assert {:error, _} =
               Message.format("{$n :i:numeral withStyle=asWords}", %{n: "four"}, locale: :en)
    end
  end

  describe "selection" do
    test ":i:quantify, :i:list and :i:numeral are not selectors, as upstream registers none" do
      for {declaration, bindings} <- [
            {"{$w :i:quantify withValue=2}", %{w: "day"}},
            {"{$w :i:list}", %{w: ["gatos", "idiomas"]}},
            {"{$w :i:numeral}", %{w: 4}}
          ] do
        assert {:error, _} =
                 Message.format(".local $v = #{declaration} .match $v\n* {{other}}", bindings,
                   locale: :en
                 )
      end
    end
  end

  describe "SSML output" do
    test "a number spoken as words (upstream)" do
      assert {:ok, ssml} =
               Message.format(
                 "You have {$count :i:numeral withStyle=asSpokenWords} messages",
                 %{count: 4},
                 locale: :en,
                 output: :ssml
               )

      assert ssml == "You have <sub alias=\"four\">4</sub> messages"
      assert print_and_speak(ssml) == {"You have 4 messages", "You have four messages"}
    end

    test "a quantity speaks its number in agreement with the noun (upstream)" do
      message = "Hay {$unit :i:quantify withValue=$n} en el video"

      for {unit, number, print, speak} <- [
            {"niño", 1, "Hay 1 niño en el video", "Hay un niño en el video"},
            {"niña", 1, "Hay 1 niña en el video", "Hay una niña en el video"},
            {"niño", 3, "Hay 3 niños en el video", "Hay tres niños en el video"}
          ] do
        assert {:ok, ssml} =
                 Message.format(message, %{unit: unit, n: number}, locale: :es, output: :ssml)

        assert print_and_speak(ssml) == {print, speak}
      end
    end

    test "a Russian number speaks in the gender and case of a concept's forms (upstream)" do
      message =
        "{$unit :i:quantify withValue=$number} {$unit :i:quantify withValue=$number case=genitive} " <>
          "{$unit :i:quantify withValue=$number case=accusative} {$unit :i:quantify withValue=$number case=dative} " <>
          "{$unit :i:quantify withValue=$number case=instrumental} {$unit :i:quantify withValue=$number case=prepositional}"

      for {number, speak} <- [
            {1,
             "одно nominative,singular одного genitive,singular одно accusative,singular " <>
               "одному dative,singular одним instrumental,singular одном prepositional,singular"},
            {2,
             "два genitive,singular двух genitive,plural два genitive,plural " <>
               "двум dative,plural двумя instrumental,plural двух prepositional,plural"},
            {5,
             "пять genitive,plural пяти genitive,plural пять genitive,plural " <>
               "пяти dative,plural пятью instrumental,plural пяти prepositional,plural"}
          ] do
        assert {:ok, ssml} =
                 Message.format(message, %{unit: ru_semantic_concept(), number: number},
                   locale: :ru,
                   output: :ssml
                 )

        assert {_print, ^speak} = print_and_speak(ssml)
      end
    end

    test "regional digits speak as the language's own digits or words (upstream)" do
      for {locale, number, expected} <- [
            {:"de-AT", 1234, {"1 234", "1.234"}},
            {:"de-CH", 1234, {"1'234", "1.234"}},
            {:"fr-CH", 75, {"75", "septante-cinq"}}
          ] do
        assert {:ok, ssml} =
                 Message.format("{$n :i:numeral}", %{n: number}, locale: locale, output: :ssml)

        assert print_and_speak(ssml) == expected
      end
    end

    test "a result spoken as it is printed is written as text" do
      assert {:ok, "four"} =
               Message.format("{$n :i:numeral withStyle=asWords}", %{n: 4},
                 locale: :en,
                 output: :ssml
               )

      assert {:ok, "The lights are on."} =
               Message.format(
                 "The {$object} {is :i:inflect number=$object} on.",
                 %{object: "lights"},
                 locale: :en,
                 output: :ssml
               )
    end

    test "text and every placeholder are escaped" do
      assert {:ok, "Tom &amp; a&lt;b &gt; <sub alias=\"four\">4</sub>"} =
               Message.format(
                 "Tom & {$x} > {$n :i:numeral withStyle=asSpokenWords}",
                 %{x: "a<b", n: 4},
                 locale: :en,
                 output: :ssml
               )

      assert {:ok, "<sub alias=\"say &quot;x&quot;\">x&amp;y</sub>"} =
               Message.format("{$w :i:inflect speak=|say \"x\"|}", %{w: "x&y"},
                 locale: :en,
                 output: :ssml
               )
    end

    test "a placeholder naming a declaration speaks as the declaration does" do
      message =
        ".local $q = {$unit :i:quantify withValue=$n} .local $r = {$q} {{Hay {$q}; {$r}}}"

      assert {:ok, ssml} =
               Message.format(message, %{unit: "niña", n: 3}, locale: :es, output: :ssml)

      assert print_and_speak(ssml) == {"Hay 3 niñas; 3 niñas", "Hay tres niñas; tres niñas"}
    end

    test "plain output is the default, and another output is an error" do
      message = "You have {$count :i:numeral withStyle=asSpokenWords} messages"

      assert {:ok, "You have 4 messages"} = Message.format(message, %{count: 4}, locale: :en)

      assert {:ok, "You have 4 messages"} =
               Message.format(message, %{count: 4}, locale: :en, output: :plain)

      assert {:error, _} = Message.format(message, %{count: 4}, locale: :en, output: :html)
    end

    test "format_to_iolist writes SSML, and format_to_safe_list stays plain" do
      message = "You have {$count :i:numeral withStyle=asSpokenWords} messages"

      assert {:ok, iolist, _bound, []} =
               Message.format_to_iolist(message, %{count: 4}, locale: :en, output: :ssml)

      assert IO.iodata_to_binary(iolist) == "You have <sub alias=\"four\">4</sub> messages"

      assert {:ok, [{:text, "You have 4 messages"}]} =
               Message.format_to_safe_list(message, %{count: 4}, locale: :en, output: :ssml)
    end
  end

  # The print and speak lines of SSML output, derived as upstream's MF2
  # test harness derives them: text is both, and each
  # <sub alias="speak">print</sub> gives each its own.
  defp print_and_speak(ssml) do
    ~r/<sub alias="[^"]*">.*?<\/sub>/s
    |> Regex.split(ssml, include_captures: true)
    |> Enum.reduce({"", ""}, fn part, {print, speak} ->
      case Regex.run(~r/\A<sub alias="([^"]*)">(.*?)<\/sub>\z/s, part, capture: :all_but_first) do
        [spoken, printed] -> {print <> xml_unescape(printed), speak <> xml_unescape(spoken)}
        nil -> {print <> xml_unescape(part), speak <> xml_unescape(part)}
      end
    end)
  end

  defp xml_unescape(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&amp;", "&")
  end

  # The semantic concept of upstream's ru fixtures: a neuter noun whose
  # twelve case and number forms name themselves, in upstream's order,
  # as display data. Its first form is its own, with the features it
  # has.
  defp ru_semantic_concept do
    forms =
      for number <- ["singular", "plural"],
          grammatical_case <-
            ["nominative", "instrumental", "accusative", "dative", "genitive", "prepositional"] do
        {"#{grammatical_case},#{number}",
         %{gender: "neuter", case: grammatical_case, number: number}}
      end

    [{value, initial} | _forms] = forms

    {:ok, concept} =
      Localize.Inflection.Concept.new(:ru, value, initial: initial, display_data: forms)

    concept
  end
end
