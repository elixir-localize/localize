defmodule Localize.Message.InflectionFunctionsTest do
  # MF2 `:l:inflect`, `:l:pronoun` and `:l:quantify` functions
  # wrapping the in-tree Localize.Inflection engine.
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

  describe ":l:quantify" do
    test "joins a count with an English noun" do
      assert {:ok, "2 kilometers"} =
               Message.format("{$noun :l:quantify count=2}", %{noun: "kilometer"}, locale: :en)
    end

    test "applies Russian numeral government (paucal, few)" do
      assert {:ok, "2 часа"} =
               Message.format("{$noun :l:quantify count=2}", %{noun: "час"}, locale: :ru)
    end

    test "applies Russian numeral government (genitive plural, many)" do
      assert {:ok, "5 часов"} =
               Message.format("{$noun :l:quantify count=5}", %{noun: "час"}, locale: :ru)
    end

    test "declines a Finnish noun after a numeral" do
      assert {:ok, "3 taloa"} =
               Message.format("{$noun :l:quantify count=3}", %{noun: "talo"}, locale: :fi)
    end

    test "the count may be supplied by a variable" do
      assert {:ok, "5 часов"} =
               Message.format("{$noun :l:quantify count=$n}", %{noun: "час", n: 5}, locale: :ru)
    end

    test "a grammatical constraint on the noun does not crash" do
      result =
        Message.format(
          "{$noun :l:quantify count=5 grammaticalCase=dative}",
          %{noun: "час"},
          locale: :ru
        )

      assert match?({:ok, _}, result)
    end

    test "a missing count option is an error, not a crash" do
      assert {:error, _} =
               Message.format("{$noun :l:quantify}", %{noun: "kilometer"}, locale: :en)
    end

    test "a non-numeric count is an error, not a crash" do
      assert {:error, _} =
               Message.format("{$noun :l:quantify count=|abc|}", %{noun: "kilometer"},
                 locale: :en
               )
    end

    test "a non-string operand is an error, not a crash" do
      assert {:error, _} =
               Message.format("{$n :l:quantify count=2}", %{n: 5}, locale: :en)
    end
  end
end
