defmodule Localize.Number.RbnfRuleProcessorTest do
  use ExUnit.Case, async: true

  alias Localize.Number
  alias Localize.Number.Rbnf.Rule

  describe "Rule.tokenize/1" do
    test "tokenizes a definition with a conditional and modulo call" do
      assert {:ok, tokens, 1} = Rule.tokenize("twenty[->>]")

      assert {:conditional_start, 1, ~c"["} in tokens
      assert {:modulo_call, 1, ~c">"} in tokens
      assert {:conditional_end, 1, ~c"]"} in tokens
    end

    test "tokenizes quotient calls" do
      assert {:ok, tokens, 1} = Rule.tokenize("<< hundred[ >>]")
      assert {:quotient_call, 1, ~c"<"} in tokens
    end

    test "accepts a Rule struct and tokenizes its definition" do
      rule = %Rule{definition: "minus >>"}
      assert {:ok, tokens, 1} = Rule.tokenize(rule)
      assert {:modulo_call, 1, ~c">"} in tokens
    end

    test "strips a single leading apostrophe" do
      assert {:ok, tokens_with, 1} = Rule.tokenize("'minus")
      assert {:ok, tokens_without, 1} = Rule.tokenize("minus")
      assert tokens_with == tokens_without
    end
  end

  describe "Rule.parse/1" do
    test "parses a literal with an optional modulo conditional" do
      assert Rule.parse("twenty[->>]") ==
               {:ok, [literal: "twenty", conditional: [literal: "-", modulo: nil]]}
    end

    test "parses quotient, literal, and conditional modulo" do
      assert Rule.parse("<< hundred[ >>]") ==
               {:ok,
                [
                  quotient: nil,
                  literal: " hundred",
                  conditional: [literal: " ", modulo: nil]
                ]}
    end

    test "parses a decimal-format call" do
      assert Rule.parse("=#,##0=") == {:ok, [call: {:format, "#,##0"}]}
    end

    test "parses a named ruleset call" do
      assert Rule.parse("=%spellout-numbering=") ==
               {:ok, [call: {:rule, :spellout_numbering}]}
    end

    test "parses an empty definition to an empty list" do
      assert Rule.parse("") == {:ok, []}
      assert Rule.parse([]) == {:ok, []}
    end

    test "returns a parser error for an unterminated construct" do
      assert {:error, {1, :rbnf_parser, _reason}} = Rule.parse("twenty[->>];")
    end
  end

  describe "spellout ordinal rulesets" do
    test "English ordinals" do
      assert Number.to_string(0, format: :spellout_ordinal) == {:ok, "zeroth"}
      assert Number.to_string(1, format: :spellout_ordinal) == {:ok, "first"}
      assert Number.to_string(21, format: :spellout_ordinal) == {:ok, "twenty-first"}
      assert Number.to_string(100, format: :spellout_ordinal) == {:ok, "one hundredth"}

      assert Number.to_string(1234, format: :spellout_ordinal) ==
               {:ok, "one thousand two hundred thirty-fourth"}
    end

    test "English negative ordinal synthesizes a minus prefix" do
      assert Number.to_string(-5, format: :spellout_ordinal) == {:ok, "minus fifth"}
    end

    test "German ordinal" do
      assert Number.to_string(3, format: :spellout_ordinal, locale: "de") == {:ok, "dritte"}

      assert Number.to_string(21, format: :spellout_ordinal, locale: "de") ==
               {:ok, "ein­und­zwanzigste"}
    end

    test "French ordinal" do
      assert Number.to_string(1, format: :spellout_ordinal, locale: "fr") == {:ok, "unième"}
    end

    test "Spanish gendered ordinals" do
      assert Number.to_string(2, format: :spellout_ordinal_masculine, locale: "es") ==
               {:ok, "segundo"}

      assert Number.to_string(1, format: :spellout_ordinal_feminine, locale: "es") ==
               {:ok, "primera"}
    end

    test "English verbose rulesets" do
      assert Number.to_string(123, format: :spellout_cardinal_verbose) ==
               {:ok, "one hundred and twenty-three"}

      assert Number.to_string(123, format: :spellout_ordinal_verbose) ==
               {:ok, "one hundred and twenty-third"}
    end
  end

  describe "spellout numbering year" do
    test "English years split into century pairs" do
      assert Number.to_string(1999, format: :spellout_numbering_year) ==
               {:ok, "nineteen ninety-nine"}

      assert Number.to_string(2026, format: :spellout_numbering_year) ==
               {:ok, "twenty twenty-six"}
    end

    test "negative year keeps the minus word" do
      assert Number.to_string(-47, format: :spellout_numbering_year) ==
               {:ok, "minus forty-seven"}
    end

    test "French year form" do
      assert Number.to_string(1999, format: :spellout_numbering_year, locale: "fr") ==
               {:ok, "dix-neuf-cent quatre-vingt-dix-neuf"}
    end
  end

  describe "roman numerals" do
    test "upper case values" do
      assert Number.to_string(4, format: :roman_upper) == {:ok, "IV"}
      assert Number.to_string(49, format: :roman_upper) == {:ok, "XLIX"}
      assert Number.to_string(2026, format: :roman_upper) == {:ok, "MMXXVI"}
      assert Number.to_string(3999, format: :roman_upper) == {:ok, "MMMCMXCIX"}
    end

    test "lower case values" do
      assert Number.to_string(12, format: :roman_lower) == {:ok, "xii"}
      assert Number.to_string(1988, format: :roman_lower) == {:ok, "mcmlxxxviii"}
    end

    test "zero uses the N (nulla) symbol" do
      assert Number.to_string(0, format: :roman_upper) == {:ok, "N"}
    end

    test "5000 uses the U+2181 ROMAN NUMERAL FIVE THOUSAND symbol" do
      assert Number.to_string(5000, format: :roman_upper) == {:ok, "ↁ"}
    end

    test "negative value is prefixed with U+2212 MINUS SIGN" do
      assert Number.to_string(-3, format: :roman_upper) == {:ok, "−III"}
    end
  end

  describe "generic :spellout and :ordinal resolution" do
    test ":spellout resolves for improper fractions" do
      assert Number.to_string(3.25, format: :spellout) == {:ok, "three point two five"}
    end

    test ":ordinal resolves to the digits ordinal ruleset" do
      assert Number.to_string(42, format: :ordinal) == {:ok, "42nd"}
    end

    test ":spellout accepts a Decimal" do
      assert Number.to_string(Decimal.new("123"), format: :spellout) ==
               {:ok, "one hundred twenty-three"}
    end

    test "values beyond the rule range fall back to the decimal format" do
      assert Number.to_string(12_345_678_901_234_567_890, format: :spellout) ==
               {:ok, "12,345,678,901,234,567,890"}
    end
  end

  describe "rule name errors" do
    test "unknown ruleset returns UnknownRbnfRuleError" do
      assert {:error, %Localize.UnknownRbnfRuleError{rule_name: :spellout_bogus}} =
               Number.to_string(12, format: :spellout_bogus)
    end

    test "ruleset valid in one locale is an error in another" do
      assert {:ok, _formatted} =
               Number.to_string(2, format: :spellout_ordinal_masculine, locale: "es")

      assert {:error, %Localize.UnknownRbnfRuleError{}} =
               Number.to_string(2, format: :spellout_ordinal_masculine, locale: "en")
    end
  end

  describe "rule_names_for_locale/1" do
    test "English exposes the standard public rulesets" do
      {:ok, names} = Localize.Number.Rbnf.rule_names_for_locale(:en)

      for name <- ["spellout_cardinal", "spellout_ordinal", "digits_ordinal"] do
        assert name in names
      end
    end
  end
end
