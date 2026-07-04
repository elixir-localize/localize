defmodule Localize.Number.RbnfDecimalCoverageTest do
  use ExUnit.Case, async: true

  alias Localize.Number
  alias Localize.Number.Rbnf.Processor

  # String-keyed rule maps exercise the map-normalization clauses of
  # get_base_value/1, get_range/1, and to_rule_struct/1.
  @raw_rules [
    %{
      "base_value" => 0,
      "range" => 20,
      "definition" => "small=#,##0=",
      "radix" => 10,
      "divisor" => 1
    },
    %{
      "base_value" => 20,
      "range" => "undefined",
      "definition" => "big =%nope=",
      "radix" => 10,
      "divisor" => 10
    }
  ]

  describe "fractional spellout rules (x.x / 0.x)" do
    test "English decimal spellout" do
      assert Number.to_string(1.5, format: :spellout) == {:ok, "one point five"}
    end

    test "English 0.x rule preserves leading fraction zeros" do
      assert Number.to_string(0.05, format: :spellout) == {:ok, "zero point zero five"}
    end

    test "negative decimal synthesizes the minus word" do
      assert Number.to_string(-1.5, format: :spellout) == {:ok, "minus one point five"}
    end

    test "Japanese decimal spellout uses the digit-list fraction rule" do
      assert Number.to_string(1.5, format: :spellout, locale: "ja") == {:ok, "一・五"}
    end

    test "Korean decimal spellout" do
      assert Number.to_string(1.5, format: :spellout, locale: "ko") == {:ok, "일점오"}
    end

    test "German decimal spellout uses Komma" do
      assert Number.to_string(1.5, format: :spellout, locale: "de") == {:ok, "eine Komma fünf"}
    end

    test "French decimal spellout spells fraction digits individually" do
      assert Number.to_string(0.75, format: :spellout, locale: "fr") ==
               {:ok, "zéro virgule sept cinq"}
    end

    test "Kyrgyz fraction-with-rule numerator and denominator" do
      assert Number.to_string(1.5, format: :spellout, locale: "ky") ==
               {:ok, "бир бүтүн ондон беш"}
    end
  end

  describe "plural-keyed substitutions in rule bodies" do
    test "Russian millions select the cardinal many form" do
      # 5_000_000 keeps the quotient (5) and the full number in the same
      # CLDR category (:many), so this assertion is stable regardless of
      # which of the two the substitution uses.
      assert Number.to_string(5_000_000, format: :spellout_numbering, locale: "ru") ==
               {:ok, "пять миллионов"}
    end

    test "Russian plural category is selected on the quotient, not the full number" do
      # Regression: per TR35/ICU the $(cardinal,...)$ plural is selected
      # on the number divided by the rule's divisor. 2_000_000 spells
      # the quotient 2 (:few → "миллиона"); selecting on 2_000_000
      # (:many) wrongly produced "два миллионов".
      assert Number.to_string(2_000_000, format: :spellout_numbering, locale: "ru") ==
               {:ok, "два миллиона"}

      assert Number.to_string(1_000_000, format: :spellout_numbering, locale: "ru") ==
               {:ok, "один миллион"}

      assert Number.to_string(21_000_000, format: :spellout_numbering, locale: "ru") ==
               {:ok, "двадцать один миллион"}
    end

    test "German millions singular and plural" do
      assert Number.to_string(1_000_000, format: :spellout, locale: "de") ==
               {:ok, "eine Million"}

      assert Number.to_string(2_000_000, format: :spellout, locale: "de") ==
               {:ok, "zwei Millionen"}
    end

    test "English digits-ordinal uses ordinal-keyed suffixes" do
      assert Number.to_string(21, format: :digits_ordinal) == {:ok, "21st"}
      assert Number.to_string(102, format: :digits_ordinal) == {:ok, "102nd"}
    end
  end

  describe "unknown rulesets" do
    test "an unknown ruleset returns an UnknownRbnfRuleError" do
      assert {:error, %Localize.UnknownRbnfRuleError{rule_name: :bogus_ruleset}} =
               Number.to_string(123, format: :bogus_ruleset)
    end
  end

  describe "Processor.process/5 with raw rule maps" do
    test "a matching rule with a decimal-format call is applied" do
      assert Processor.process(5, "test-set", @raw_rules, %{}, :en) == {:ok, "small5"}
    end

    test "a rule referencing an unknown rule set returns an error" do
      assert Processor.process(25, "test-set", @raw_rules, %{}, :en) ==
               {:error, "Rule set \"nope\" not found"}
    end

    test "an empty rule list returns a no-matching-rule error" do
      assert Processor.process(7, "empty", [], %{}, :en) ==
               {:error, "No matching rule for 7 in empty"}
    end
  end
end
