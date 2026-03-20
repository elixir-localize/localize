defmodule Localize.Number.PluralRule.PluralTypeTest do
  use ExUnit.Case, async: true

  alias Localize.Number.PluralRule

  test "plural_type defaults to cardinal and English" do
    assert PluralRule.plural_type(1) == :one
    assert PluralRule.plural_type(2) == :other
  end

  test "plural_type with cardinal type explicitly" do
    assert PluralRule.plural_type(1, locale: "en", type: :cardinal) == :one
    assert PluralRule.plural_type(2, locale: "en", type: :cardinal) == :other
  end

  test "plural_type with ordinal type" do
    assert PluralRule.plural_type(1, locale: "en", type: :ordinal) == :one
    assert PluralRule.plural_type(2, locale: "en", type: :ordinal) == :two
    assert PluralRule.plural_type(3, locale: "en", type: :ordinal) == :few
    assert PluralRule.plural_type(4, locale: "en", type: :ordinal) == :other
  end

  test "plural_type with various locales" do
    assert PluralRule.plural_type(0, locale: "ar") == :zero
    assert PluralRule.plural_type(1, locale: "ar") == :one
    assert PluralRule.plural_type(2, locale: "ar") == :two
  end

  test "plural_type with atom locale" do
    assert PluralRule.plural_type(1, locale: :en) == :one
    assert PluralRule.plural_type(2, locale: :en) == :other
  end

  test "known_plural_types returns all categories" do
    assert PluralRule.known_plural_types() == [:zero, :one, :two, :few, :many, :other]
  end
end
