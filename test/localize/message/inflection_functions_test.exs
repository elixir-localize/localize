defmodule Localize.Message.InflectionFunctionsTest do
  # MF2 `:l:inflect` and `:l:pronoun` functions wrapping the in-tree
  # Localize.Inflection engine.
  use ExUnit.Case, async: false

  alias Localize.Message

  describe ":l:inflect" do
    test "inflects a phrase for grammatical number" do
      assert {:ok, "lights on the patio"} =
               Message.format(
                 "{$w :l:inflect grammaticalNumber=plural}",
                 %{w: "light on the patio"},
                 locale: :en
               )
    end

    test "inflects a phrase for grammatical case" do
      assert {:ok, "новым домом"} =
               Message.format(
                 "{$w :l:inflect grammaticalCase=instrumental}",
                 %{w: "новый дом"},
                 locale: :ru
               )
    end

    test "inflects a phrase for grammatical gender" do
      assert {:ok, "लड़की"} =
               Message.format(
                 "{$w :l:inflect grammaticalGender=feminine}",
                 %{w: "लड़का"},
                 locale: :hi
               )
    end

    test "a non-string operand does not crash" do
      result =
        Message.format("{$n :l:inflect grammaticalCase=dative}", %{n: 5}, locale: :ru)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe ":l:pronoun" do
    test "re-inflects the operand pronoun" do
      assert {:ok, "him"} =
               Message.format("{|he| :l:pronoun grammaticalCase=accusative}", %{}, locale: :en)
    end
  end
end
