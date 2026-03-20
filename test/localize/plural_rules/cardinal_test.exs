defmodule Localize.Number.PluralRule.CardinalTest do
  use ExUnit.Case, async: true

  alias Localize.Number.PluralRule.Cardinal

  test "cardinal plural rule for English integers" do
    assert Cardinal.plural_rule(0, "en") == :other
    assert Cardinal.plural_rule(1, "en") == :one
    assert Cardinal.plural_rule(2, "en") == :other
    assert Cardinal.plural_rule(5, "en") == :other
    assert Cardinal.plural_rule(100, "en") == :other
  end

  test "cardinal plural rule for Arabic integers" do
    assert Cardinal.plural_rule(0, "ar") == :zero
    assert Cardinal.plural_rule(1, "ar") == :one
    assert Cardinal.plural_rule(2, "ar") == :two
    assert Cardinal.plural_rule(3, "ar") == :few
    assert Cardinal.plural_rule(11, "ar") == :many
    assert Cardinal.plural_rule(100, "ar") == :other
  end

  test "cardinal plural rule for French integers" do
    assert Cardinal.plural_rule(0, "fr") == :one
    assert Cardinal.plural_rule(1, "fr") == :one
    assert Cardinal.plural_rule(2, "fr") == :other
    assert Cardinal.plural_rule(1_000_000, "fr") == :many
  end

  test "cardinal plural rule for Russian integers" do
    assert Cardinal.plural_rule(1, "ru") == :one
    assert Cardinal.plural_rule(2, "ru") == :few
    assert Cardinal.plural_rule(5, "ru") == :many
    assert Cardinal.plural_rule(21, "ru") == :one
    assert Cardinal.plural_rule(22, "ru") == :few
    assert Cardinal.plural_rule(25, "ru") == :many
  end

  test "cardinal plural rule for Japanese (always :other)" do
    assert Cardinal.plural_rule(0, "ja") == :other
    assert Cardinal.plural_rule(1, "ja") == :other
    assert Cardinal.plural_rule(100, "ja") == :other
  end

  test "cardinal pluralize with substitutions" do
    substitutions = %{one: "one", other: "other"}
    assert Cardinal.pluralize(1, "en", substitutions) == "one"
    assert Cardinal.pluralize(2, "en", substitutions) == "other"
  end

  test "non-integer decimal pluralization" do
    decimal = Decimal.new("1234.50")
    substitutions = %{one: "one", two: "two", other: "other"}
    assert Cardinal.pluralize(decimal, "en", substitutions) == "other"
  end

  test "cardinal plural rule for float" do
    # 1.0 as a float has visible fraction digits (v > 0), so it's :other
    # in English where :one requires i = 1 and v = 0
    assert Cardinal.plural_rule(1.0, "en") == :other
    assert Cardinal.plural_rule(1.5, "en") == :other
  end

  test "cardinal plural rule for Decimal" do
    assert Cardinal.plural_rule(Decimal.new("1"), "en") == :one
    assert Cardinal.plural_rule(Decimal.new("2"), "en") == :other
    assert Cardinal.plural_rule(Decimal.new("1.5"), "en") == :other
  end

  test "available_locale_names returns a non-empty sorted list" do
    locales = Cardinal.available_locale_names()
    assert is_list(locales)
    assert length(locales) > 0
    assert locales == Enum.sort(locales)
    assert :en in locales
  end

  test "plural_rules_for returns rules for a known locale" do
    rules = Cardinal.plural_rules_for("en")
    assert is_list(rules)
    assert Keyword.has_key?(rules, :one)
    assert Keyword.has_key?(rules, :other)
  end

  test "error for unknown locale" do
    result = Cardinal.plural_rule(1, "xx-UNKNOWN")

    case result do
      {:error, %Localize.UnknownPluralRulesError{}} -> :ok
      {:error, _} -> :ok
    end
  end
end
