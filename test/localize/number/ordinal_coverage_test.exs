defmodule Localize.Number.OrdinalCoverageTest do
  use ExUnit.Case, async: true

  alias Localize.Number.PluralRule.Ordinal

  @plural_categories [:zero, :one, :two, :few, :many, :other]
  @sweep_locales ["en", "cy", "it", "sv", "fr", "uk", "ka", "hu", "de", "ja"]

  describe "plural_rule/2 locale sweep" do
    test "every integer 0..120 maps to a valid category in every sweep locale" do
      for locale <- @sweep_locales, number <- 0..120 do
        category = Ordinal.plural_rule(number, locale)

        assert category in @plural_categories,
               "#{locale} #{number} returned #{inspect(category)}"
      end
    end

    test "large integers map to a valid category" do
      for locale <- @sweep_locales, number <- [1_000, 10_007, 999_999, 1_000_000_001] do
        assert Ordinal.plural_rule(number, locale) in @plural_categories
      end
    end
  end

  describe "plural_rule/2 spot checks against CLDR expectations" do
    test "Welsh exercises all six categories" do
      assert Ordinal.plural_rule(0, "cy") == :zero
      assert Ordinal.plural_rule(1, "cy") == :one
      assert Ordinal.plural_rule(2, "cy") == :two
      assert Ordinal.plural_rule(3, "cy") == :few
      assert Ordinal.plural_rule(4, "cy") == :few
      assert Ordinal.plural_rule(5, "cy") == :many
      assert Ordinal.plural_rule(6, "cy") == :many
      assert Ordinal.plural_rule(7, "cy") == :zero
      assert Ordinal.plural_rule(9, "cy") == :zero
      assert Ordinal.plural_rule(10, "cy") == :other
    end

    test "Italian: 8 and 11 are :many" do
      assert Ordinal.plural_rule(8, "it") == :many
      assert Ordinal.plural_rule(11, "it") == :many
      assert Ordinal.plural_rule(1, "it") == :other
      assert Ordinal.plural_rule(80, "it") == :many
      assert Ordinal.plural_rule(100, "it") == :other
    end

    test "Swedish: 1 and 2 are :one, others :other" do
      assert Ordinal.plural_rule(1, "sv") == :one
      assert Ordinal.plural_rule(2, "sv") == :one
      assert Ordinal.plural_rule(3, "sv") == :other
      assert Ordinal.plural_rule(11, "sv") == :other
      assert Ordinal.plural_rule(12, "sv") == :other
      assert Ordinal.plural_rule(21, "sv") == :one
      assert Ordinal.plural_rule(22, "sv") == :one
    end

    test "Ukrainian: n mod 10 = 3 and n mod 100 != 13 is :few" do
      assert Ordinal.plural_rule(3, "uk") == :few
      assert Ordinal.plural_rule(23, "uk") == :few
      assert Ordinal.plural_rule(33, "uk") == :few
      assert Ordinal.plural_rule(13, "uk") == :other
      assert Ordinal.plural_rule(113, "uk") == :other
    end

    test "Hungarian: 1 and 5 are :one" do
      assert Ordinal.plural_rule(1, "hu") == :one
      assert Ordinal.plural_rule(5, "hu") == :one
      assert Ordinal.plural_rule(2, "hu") == :other
      assert Ordinal.plural_rule(15, "hu") == :other
    end

    test "Georgian: 1 is :one, most others :many, hundreds :other" do
      assert Ordinal.plural_rule(1, "ka") == :one
      assert Ordinal.plural_rule(2, "ka") == :many
      assert Ordinal.plural_rule(11, "ka") == :many
      assert Ordinal.plural_rule(100, "ka") == :other
    end

    test "French: only 1 is :one" do
      assert Ordinal.plural_rule(1, "fr") == :one
      assert Ordinal.plural_rule(2, "fr") == :other
      assert Ordinal.plural_rule(21, "fr") == :other
    end
  end

  describe "plural_rule/2 with non-integer input" do
    test "integer-valued Decimal uses the integer rules" do
      assert Ordinal.plural_rule(Decimal.new(3), "en") == :few
      assert Ordinal.plural_rule(Decimal.new("21"), "en") == :one
    end

    test "Decimal with a redundant fractional zero normalizes to an integer" do
      assert Ordinal.plural_rule(Decimal.new("2.0"), "en") == :two
    end

    test "integer-valued float uses the integer classification" do
      assert Ordinal.plural_rule(1.0, "en") == :one
    end

    test "fractional float falls to :other in English" do
      assert Ordinal.plural_rule(3.5, "en") == :other
    end

    test "binary number input is parsed as a Decimal" do
      {:ok, en} = Localize.validate_locale("en")
      assert Ordinal.plural_rule("22", en) == :two
    end

    test "compact tuple form {mantissa, exponent} computes shifted operands" do
      {:ok, en} = Localize.validate_locale("en")
      assert Ordinal.plural_rule({1, 6}, en) == :other
      assert Ordinal.plural_rule({1.0, 6}, en) == :other
      assert Ordinal.plural_rule({Decimal.new(1), 6}, en) == :other
    end

    test "negative integers classify on the absolute value" do
      assert Ordinal.plural_rule(-2, "en") == :two
      assert Ordinal.plural_rule(-1, "en") == :one
      assert Ordinal.plural_rule(-11, "en") == :other
    end
  end

  describe "pluralize/3" do
    test "exact-match integer keys take precedence over category keys" do
      substitutions = %{3 => "exact", few: "rd", other: "th"}
      assert Ordinal.pluralize(3, "en", substitutions) == "exact"
    end

    test "integer-valued float matches an exact integer key" do
      substitutions = %{2 => "exact-two", two: "nd", other: "th"}
      assert Ordinal.pluralize(2.0, "en", substitutions) == "exact-two"
    end

    test "Decimal input pluralizes through the category" do
      assert Ordinal.pluralize(Decimal.new(4), "en", %{one: "st", other: "th"}) == "th"
    end

    test "missing category with no :other fallback returns nil" do
      assert Ordinal.pluralize(11, "en", %{one: "st"}) == nil
    end

    test "falls back to :other when the category has no substitution" do
      assert Ordinal.pluralize(2, "en", %{one: "st", other: "th"}) == "th"
    end

    test "Welsh substitution map exercises :zero and :many" do
      substitutions = %{zero: "fed", one: "af", two: "il", few: "ydd", many: "ed", other: "eg"}
      assert Ordinal.pluralize(0, "cy", substitutions) == "fed"
      assert Ordinal.pluralize(5, "cy", substitutions) == "ed"
    end

    test "invalid locale returns an error tuple" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Ordinal.pluralize(1, "zz", %{one: "st"})
    end
  end

  describe "locale resolution and error paths" do
    test "regional locale falls back to its language rules" do
      assert Ordinal.plural_rule(1, "en-GB") == :one
      assert Ordinal.plural_rule(2, "en-GB") == :two
    end

    test "plural_rules/0 includes English rule categories" do
      rules = Ordinal.plural_rules()
      assert rules[:en] |> Keyword.keys() |> Enum.sort() == [:few, :one, :other, :two]
    end

    test "plural_rules_for/1 accepts a LanguageTag" do
      {:ok, cy} = Localize.validate_locale("cy")
      rules = Ordinal.plural_rules_for(cy)

      assert rules |> Keyword.keys() |> Enum.sort() ==
               [:few, :many, :one, :other, :two, :zero]
    end

    test "plural_rules_for/1 returns an error for an invalid locale" do
      assert {:error, %Localize.InvalidLocaleError{}} = Ordinal.plural_rules_for("zz")
    end

    test "plural_rule/2 returns an error for an invalid locale" do
      assert {:error, %Localize.InvalidLocaleError{}} = Ordinal.plural_rule(1, "zz")
    end
  end
end
