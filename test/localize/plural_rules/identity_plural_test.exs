defmodule Localize.Number.PluralRule.IdentityPluralTest do
  use ExUnit.Case, async: true

  alias Localize.Number.PluralRule.Cardinal
  alias Localize.Number.PluralRule.Ordinal

  test "integer identity plural selection" do
    substitutions = %{42 => "This is 42", :other => "This is not"}
    assert Cardinal.pluralize(42, "en", substitutions) == "This is 42"
    assert Ordinal.pluralize(42, "en", substitutions) == "This is 42"
  end

  test "float identity pluralization" do
    substitutions = %{42 => "This is 42", :other => "This is not"}

    assert Cardinal.pluralize(42.0, "en", substitutions) == "This is 42"
    assert Cardinal.pluralize(Decimal.new("42.0"), "en", substitutions) == "This is 42"
    assert Cardinal.pluralize(Decimal.new(42), "en", substitutions) == "This is 42"
  end
end
