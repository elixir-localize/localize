defmodule Localize.Number.ScannerTest do
  use ExUnit.Case, async: true

  alias Localize.Number.{Lexicon, Scanner}

  defp scan(string, locale, options \\ []) do
    {:ok, language_tag} = Localize.validate_locale(locale)
    {:ok, number_system} = Lexicon.number_system(language_tag, string, options)
    {:ok, lexicon} = Lexicon.fetch(language_tag, number_system, options)
    Scanner.scan(string, lexicon, options)
  end

  describe "the shape of a number" do
    test "a sign is read only before the digits, touching them" do
      assert [-5] = scan("-5", :en)
      assert [-5] = scan("−5", :en)
      assert [5, "-"] = scan("5-", :en)
      assert ["- ", 5] = scan("- 5", :en)
      assert ["(", 5, ")"] = scan("(5)", :en)
    end

    test "a bidi control before the digits is part of the number, one after is text" do
      assert [-5] = scan("‎-5", :en)
      assert [-5] = scan("-‎5", :en)
      assert [5, "‎"] = scan("5‎", :en)
      assert ["‎x"] = scan("‎x", :en)
    end

    test "a group separator is followed by two digits or more leniently" do
      assert [1234] = scan("1,234", :en)
      assert [1, ",", 2] = scan("1,2", :en)
      assert [3, " ", 4, " ", 5] = scan("3 4 5", :fr)
      assert [121_416] = scan("12 14 16", :fr)
    end

    test "and by a group of the locale's size strictly" do
      strict = [lenient: false, grouping: :strict]
      assert [12, " ", 14, " ", 16] = scan("12 14 16", :fr, strict)
      assert [1, " ", 23] = scan("1 23", :fr, strict)
      assert [1_234_567] = scan("12,34,567", :"en-IN", strict)
      assert ["12,34", ",", 5] = scan("12,34,5", :"en-IN", strict)
    end

    test "a decimal separator needs a digit or an underscore after it" do
      assert [1.5] = scan("1.5", :en)
      assert [5, "."] = scan("5.", :en)
      assert [5, ".x"] = scan("5.x", :en)
      assert [".", 5] = scan(".5", :en)
    end

    test "a zero fraction is one or two dashes with no digit after, leniently only" do
      assert ["CHF ", 5] = scan("CHF 5.–", :"de-CH")
      assert ["CHF ", 5] = scan("CHF 5.––", :"de-CH")
      assert ["CHF ", 5, ".–"] = scan("CHF 5.–", :"de-CH", lenient: false, grouping: :strict)
      assert [1, ".", -2] = scan("1.-2", :en)
      assert [5, -5] = scan("5.--5", :en)
      assert [5, "-"] = scan("5.---", :en)
    end

    test "an exponent follows the integer or a fraction written with digits" do
      assert [1.0e5] = scan("1e5", :en)
      assert [1.2e6] = scan("12e5", :en)
      assert [0.0015] = scan("1.5e-3", :en)
      assert [1500.0] = scan("1.5e3", :en)
      assert [1, "e"] = scan("1e", :en)
      assert [1, "ex"] = scan("1ex", :en)
      assert [1, ".e", 5] = scan("1.e5", :en)
    end

    test "an underscore is read only between two digits" do
      assert [1000] = scan("1_000", :en)
      assert ["_", 5] = scan("_5", :en)
      assert ["5_"] = scan("5_", :en)
      assert ["1__000"] = scan("1__000", :en)
    end
  end

  describe "text" do
    test "consecutive pieces of text are one string, as written" do
      assert ["abc-def"] = scan("abc-def", :en)
      assert ["The prize is ", 23, " today"] = scan("The prize is 23 today", :en)
    end

    test "a run the grammar refuses is text as it was written, in a piece of its own" do
      assert ["٥_", " apples"] = scan("٥_ apples", :"ar-EG")
      assert ["1.23"] = scan("1.23", :de, grouping: :sizes)
      assert ["x ", "1.23", " y"] = scan("x 1.23 y", :de, grouping: :sizes)
    end

    test "digits of another number system are text" do
      assert ["٥ apples"] = scan("٥ apples", :en, number_system: :latn)
      assert [5, "٥"] = scan("5٥", :en, number_system: :latn)
    end

    test "a run longer than the byte cap is text" do
      assert ["12345"] = scan("12345", :en, max_number_bytes: 4)
      assert [12_345] = scan("12345", :en, max_number_bytes: 5)
    end
  end

  describe "readings" do
    test "the currency's separators lead where they differ from the plain ones" do
      assert [1234.56, " CHF"] = scan("1'234.56 CHF", :"fr-CH", currency: :CHF)
      assert [1234.56] = scan("1'234,56", :"fr-CH")
    end

    test "the number type applies to every number" do
      assert [%Decimal{}, " and ", %Decimal{}] = scan("1 and 2.5", :en, number: :decimal)
    end
  end
end
