defmodule Localize.Number.PluralRuleDispatchTest do
  use ExUnit.Case, async: true

  alias Localize.Number.PluralRule
  alias Localize.Number.PluralRule.Compiler

  doctest Localize.Number.PluralRule

  describe "plural_type/2 with the Elixir backend" do
    test "defaults to the current locale and cardinal type" do
      assert PluralRule.plural_type(1) == :one
      assert PluralRule.plural_type(2) == :other
    end

    test "a Decimal with a fractional representation is :other in English" do
      assert PluralRule.plural_type(Decimal.new("1.0"), locale: "en") == :other
    end

    test "a float that is not an integer is :other in English" do
      assert PluralRule.plural_type(1.5, locale: "en") == :other
    end

    test "Russian cardinal categories" do
      assert PluralRule.plural_type(2, locale: "ru") == :few
      assert PluralRule.plural_type(5, locale: "ru") == :many
    end

    test "Arabic cardinal categories cover zero, two, and many" do
      assert PluralRule.plural_type(0, locale: "ar") == :zero
      assert PluralRule.plural_type(2, locale: "ar") == :two
      assert PluralRule.plural_type(11, locale: "ar") == :many
      assert PluralRule.plural_type(100, locale: "ar") == :other
    end

    test "ordinal type is dispatched to the Ordinal module" do
      assert PluralRule.plural_type(3, locale: "en", type: :ordinal) == :few
      assert PluralRule.plural_type(11, locale: "en", type: :ordinal) == :other
      assert PluralRule.plural_type(3, locale: "cy", type: :ordinal) == :few
    end

    test "an invalid locale returns an UnknownPluralRulesError" do
      assert {:error, %Localize.UnknownPluralRulesError{locale_id: "zz-invalid"}} =
               PluralRule.plural_type(1, locale: "zz-invalid")
    end
  end

  describe "plural_type/2 with the NIF backend" do
    @describetag :nif

    test "returns the plural category for a valid locale" do
      if Localize.Nif.available?() do
        # Regression: the NIF backend used to leak the NIF's `{:ok, atom}`
        # tuple while the Elixir backend returned the bare atom. Both
        # backends now return the bare category atom per the @spec.
        assert PluralRule.plural_type(1, locale: "en", backend: :nif) == :one
      end
    end

    test "returns the same bare atom as the Elixir backend" do
      if Localize.Nif.available?() do
        assert PluralRule.plural_type(2, locale: "ru", backend: :nif) ==
                 PluralRule.plural_type(2, locale: "ru", backend: :elixir)

        assert PluralRule.plural_type(2, locale: "ru", backend: :nif) == :few
      end
    end

    test "an invalid locale returns an InvalidLocaleError" do
      if Localize.Nif.available?() do
        assert {:error, %Localize.InvalidLocaleError{}} =
                 PluralRule.plural_type(1, locale: "zz-bogus", backend: :nif)
      end
    end
  end

  describe "Compiler.tokenize/1 and Compiler.parse/1" do
    test "tokenizes a rule definition" do
      assert {:ok, tokens, _end_line} = Compiler.tokenize("n is 1")
      assert [{:operand, 1, ~c"n"}, {:is_op, 1, ~c"is"}, {:integer, 1, 1}] = tokens
    end

    test "parses a token list" do
      {:ok, tokens, _end_line} = Compiler.tokenize("n is 1")
      assert {:ok, [rule: {:==, _, [{:n, _, _}, 1]}]} = Compiler.parse(tokens)
    end

    test "parses a binary definition with a range" do
      assert {:ok, [rule: {:within, _, [{:n, _, _}, {:.., _, [2, 4]}]}]} =
               Compiler.parse("n = 2..4")
    end
  end
end
