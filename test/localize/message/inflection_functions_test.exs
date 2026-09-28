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
    end

    test "the to option is not supported yet" do
      assert {:error, _} =
               Message.format("{$w :i:inflect to=number}", %{w: "lights"}, locale: :en)
    end

    test "a non-string option value is an error" do
      assert {:error, _} =
               Message.format("{$w :i:inflect number=$n}", %{w: "light", n: 2}, locale: :en)
    end

    test "a non-string operand does not crash" do
      result = Message.format("{$n :i:inflect case=dative}", %{n: 5}, locale: :ru)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
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
end
