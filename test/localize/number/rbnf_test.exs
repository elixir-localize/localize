defmodule Localize.Number.RbnfTest do
  use ExUnit.Case, async: true

  doctest Localize.Number.Rbnf

  alias Localize.Number.Rbnf

  describe "spellout cardinal (English)" do
    test "zero" do
      assert {:ok, "zero"} = Rbnf.to_string(0, :spellout_cardinal, locale: :en)
    end

    test "single digits" do
      assert {:ok, "one"} = Rbnf.to_string(1, :spellout_cardinal, locale: :en)
      assert {:ok, "five"} = Rbnf.to_string(5, :spellout_cardinal, locale: :en)
      assert {:ok, "nine"} = Rbnf.to_string(9, :spellout_cardinal, locale: :en)
    end

    test "teens" do
      assert {:ok, "ten"} = Rbnf.to_string(10, :spellout_cardinal, locale: :en)
      assert {:ok, "thirteen"} = Rbnf.to_string(13, :spellout_cardinal, locale: :en)
      assert {:ok, "nineteen"} = Rbnf.to_string(19, :spellout_cardinal, locale: :en)
    end

    test "tens" do
      assert {:ok, "twenty"} = Rbnf.to_string(20, :spellout_cardinal, locale: :en)
      assert {:ok, "twenty-one"} = Rbnf.to_string(21, :spellout_cardinal, locale: :en)
      assert {:ok, "ninety-nine"} = Rbnf.to_string(99, :spellout_cardinal, locale: :en)
    end

    test "hundreds" do
      assert {:ok, "one hundred"} = Rbnf.to_string(100, :spellout_cardinal, locale: :en)

      assert {:ok, "one hundred twenty-three"} =
               Rbnf.to_string(123, :spellout_cardinal, locale: :en)

      assert {:ok, "nine hundred ninety-nine"} =
               Rbnf.to_string(999, :spellout_cardinal, locale: :en)
    end

    test "thousands" do
      assert {:ok, "one thousand"} = Rbnf.to_string(1000, :spellout_cardinal, locale: :en)

      assert {:ok, "twelve thousand three hundred forty-five"} =
               Rbnf.to_string(12345, :spellout_cardinal, locale: :en)
    end

    test "millions" do
      assert {:ok, "one million"} = Rbnf.to_string(1_000_000, :spellout_cardinal, locale: :en)
    end

    test "negative numbers" do
      {:ok, result} = Rbnf.to_string(-42, :spellout_cardinal, locale: :en)
      assert String.contains?(result, "forty-two")
    end
  end

  describe "digits ordinal (English)" do
    test "1st through 4th" do
      assert {:ok, "1st"} = Rbnf.to_string(1, :digits_ordinal, locale: :en)
      assert {:ok, "2nd"} = Rbnf.to_string(2, :digits_ordinal, locale: :en)
      assert {:ok, "3rd"} = Rbnf.to_string(3, :digits_ordinal, locale: :en)
      assert {:ok, "4th"} = Rbnf.to_string(4, :digits_ordinal, locale: :en)
    end

    test "teens" do
      assert {:ok, "11th"} = Rbnf.to_string(11, :digits_ordinal, locale: :en)
      assert {:ok, "12th"} = Rbnf.to_string(12, :digits_ordinal, locale: :en)
      assert {:ok, "13th"} = Rbnf.to_string(13, :digits_ordinal, locale: :en)
    end

    test "larger numbers" do
      assert {:ok, "21st"} = Rbnf.to_string(21, :digits_ordinal, locale: :en)
      assert {:ok, "22nd"} = Rbnf.to_string(22, :digits_ordinal, locale: :en)
      assert {:ok, "100th"} = Rbnf.to_string(100, :digits_ordinal, locale: :en)
      assert {:ok, "123rd"} = Rbnf.to_string(123, :digits_ordinal, locale: :en)
    end
  end

  describe "algorithmic number systems" do
    test "Roman numerals" do
      assert {:ok, "XLII"} = Localize.Number.System.to_system(42, :roman)
      assert {:ok, "MMXXIV"} = Localize.Number.System.to_system(2024, :roman)
      assert {:ok, "XIV"} = Localize.Number.System.to_system(14, :roman)
    end
  end

  describe "rule_names_for_locale/1" do
    test "returns rule names for English" do
      {:ok, names} = Rbnf.rule_names_for_locale(:en)
      assert is_list(names)
      assert "spellout_cardinal" in names or :spellout_cardinal in names
    end
  end
end
