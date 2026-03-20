defmodule Localize.Number.PluralRule.OrdinalTest do
  use ExUnit.Case, async: true

  doctest Localize.Number.PluralRule.Ordinal

  alias Localize.Number.PluralRule.Ordinal

  test "ordinal plural rule for English integers" do
    assert Ordinal.plural_rule(1, "en") == :one
    assert Ordinal.plural_rule(2, "en") == :two
    assert Ordinal.plural_rule(3, "en") == :few
    assert Ordinal.plural_rule(4, "en") == :other
    assert Ordinal.plural_rule(11, "en") == :other
    assert Ordinal.plural_rule(12, "en") == :other
    assert Ordinal.plural_rule(13, "en") == :other
    assert Ordinal.plural_rule(21, "en") == :one
    assert Ordinal.plural_rule(22, "en") == :two
    assert Ordinal.plural_rule(23, "en") == :few
    assert Ordinal.plural_rule(100, "en") == :other
    assert Ordinal.plural_rule(101, "en") == :one
    assert Ordinal.plural_rule(102, "en") == :two
    assert Ordinal.plural_rule(103, "en") == :few
  end

  test "ordinal pluralize with substitutions for English" do
    substitutions = %{one: "st", two: "nd", few: "rd", other: "th"}
    assert Ordinal.pluralize(1, "en", substitutions) == "st"
    assert Ordinal.pluralize(2, "en", substitutions) == "nd"
    assert Ordinal.pluralize(3, "en", substitutions) == "rd"
    assert Ordinal.pluralize(4, "en", substitutions) == "th"
  end

  test "ordinal plural rule for Welsh" do
    assert Ordinal.plural_rule(0, "cy") == :zero
    assert Ordinal.plural_rule(7, "cy") == :zero
    assert Ordinal.plural_rule(1, "cy") == :one
    assert Ordinal.plural_rule(2, "cy") == :two
    assert Ordinal.plural_rule(3, "cy") == :few
    assert Ordinal.plural_rule(4, "cy") == :few
    assert Ordinal.plural_rule(5, "cy") == :many
    assert Ordinal.plural_rule(6, "cy") == :many
  end

  test "ordinal plural rule for Japanese (always :other)" do
    assert Ordinal.plural_rule(0, "ja") == :other
    assert Ordinal.plural_rule(1, "ja") == :other
    assert Ordinal.plural_rule(100, "ja") == :other
  end

  test "available_locale_names returns a non-empty sorted list" do
    locales = Ordinal.available_locale_names()
    assert is_list(locales)
    assert length(locales) > 0
    assert locales == Enum.sort(locales)
    assert :en in locales
  end

  test "plural_rules_for returns rules for a known locale" do
    rules = Ordinal.plural_rules_for("en")
    assert is_list(rules)
    assert Keyword.has_key?(rules, :one)
    assert Keyword.has_key?(rules, :two)
    assert Keyword.has_key?(rules, :few)
    assert Keyword.has_key?(rules, :other)
  end

  test "error for unknown locale" do
    result = Ordinal.plural_rule(1, "xx-UNKNOWN")

    case result do
      {:error, %Localize.UnknownPluralRulesError{}} -> :ok
      {:error, _} -> :ok
    end
  end
end
