defmodule Localize.Number.GrammarTest do
  use ExUnit.Case, async: true

  alias Localize.Number.{Grammar, Lexicon, Parser}

  doctest Grammar

  defp read(string, locale, options \\ []) do
    {:ok, language_tag} = Localize.validate_locale(locale)
    {:ok, number_system} = Lexicon.number_system(language_tag, string, options)
    {:ok, lexicon} = Lexicon.fetch(language_tag, number_system, options)
    Grammar.read(string, lexicon, Keyword.take(options, [:number, :grouping]))
  end

  describe "an underscore is Elixir's digit separator" do
    test "and reads between two digits" do
      assert {:ok, 1_000_000} = Parser.parse("1_000_000", locale: :en)
      assert {:ok, 1_000.34} = Parser.parse("1_000.34", locale: :en)
      assert {:ok, -1_000_000.34} = Parser.parse("-1_000_000.34", locale: :en)
      assert {:ok, 1_234} = Parser.parse("1.2_34", locale: :de)
    end

    test "and is not a number anywhere else" do
      for string <- ["_5", "5_", "1__000", "5._5", "1_,000", "-_5", "_"] do
        assert {:error, %Localize.InvalidValueError{value: ^string}} =
                 Parser.parse(string, locale: :en),
               string
      end
    end
  end

  describe "the body in one pass" do
    test "an underscore joins digits in the fraction too, and an exponent may take a spaced sign" do
      assert {:ok, 1.55} = read("1.5_5", :en)
      assert {:ok, 1.0e-5} = read("1e -5", :en)
      assert {:ok, 1.0e-5} = read("1e- 5", :en)
      assert {:error, _} = read("1 2", :en)
    end

    test "an empty group refuses the number" do
      for string <- ["1,,234", "1,234,", ",234", "1,234,.5"] do
        assert {:error, %Localize.InvalidValueError{}} = read(string, :en), string
      end
    end

    test "a second decimal mark is refused unless it ends the number" do
      assert {:ok, 1234.56} = read("1,234.56.", :en)
      assert {:ok, 1234} = read("1,234.", :en)
      assert {:error, _} = read("1,234.5.6", :en)
    end

    test "a format character between the digits of a grouped number is dropped" do
      assert {:ok, 12_345} = read("1‎2,345", :en)
      assert {:ok, 1234.5} = read("1,234.‎5", :en)
    end

    test "a group that holds anything but digits refuses the number" do
      assert {:error, _} = read("1,2x4", :en)
      assert {:error, _} = read("1,234e5", :en)
      assert {:ok, 1.2e6} = read("12e5", :en)
    end
  end

  describe "every reading must agree" do
    test "the locale's separators and the root's" do
      assert {:ok, 1234} = read("1.234", :de)

      assert {:error, %Localize.ParseError{detail: detail}} =
               read("1.234", :de, root_separators: true)

      assert detail =~ "ambiguous"
      assert {:ok, 1234.5} = read("1.234,5", :de, root_separators: true)
    end

    test "a currency's separators and the plain ones in de-AT" do
      assert {:ok, 1234} = read("1.234", :"de-AT", currency: :EUR, grouping: :sizes)
      assert {:error, _} = read("1.23", :"de-AT", currency: :EUR, grouping: :sizes)
      assert {:ok, 1234} = read("1 234", :"de-AT", currency: :EUR, grouping: :sizes)
    end
  end

  describe "signs and parentheses" do
    test "one sign, before or after, or parentheses" do
      assert {:ok, -5} = read("-5", :en)
      assert {:ok, -5} = read("5-", :en)
      assert {:ok, -5} = read("(5)", :en)
      assert {:ok, -5} = read("( 5 )", :en)
      assert {:ok, 5} = read("+5", :en)
      assert {:ok, -5} = read("−5", :en)
      assert {:error, _} = read("(-5)", :en)
      assert {:error, _} = read("-5-", :en)
      assert {:error, _} = read("+-5", :en)
      assert {:error, _} = read("5)", :en)
    end

    test "a minus before a bare decimal mark is refused, a plus is not" do
      assert {:error, _} = read("-.5", :en)
      assert {:error, _} = read("−.5", :en)
      assert {:ok, 0.5} = read("+.5", :en)
      assert {:ok, -0.5} = read("(.5)", :en)
      assert {:ok, 0.5} = read(".5", :en)
      assert {:ok, 5} = read("5.", :en)
    end
  end

  describe "a zero fraction written as a dash" do
    test "one or two alike dashes end the number, leniently" do
      assert {:ok, 5} = read("5.–", :en)
      assert {:ok, 5} = read("5.--", :en)
      assert {:ok, 5} = read("5.–", :"de-CH")
      assert {:ok, 5} = read("5,-", :nl)
      assert {:ok, -5} = read("(5.–)", :en)
      assert {:ok, -5} = read("-5.–", :en)
      # Strictly, the dash is a trailing minus after "5.", as TR35 allows.
      assert {:ok, -5} = read("5.–", :en, grouping: :strict)
      assert {:error, _} = read("5.–", :de)
    end
  end

  describe "spaces" do
    test "group only where the locale groups with one" do
      assert {:ok, 1234.5} = read("1 234,5", :fr)
      assert {:ok, 1234.5} = read("1 234,5", :fr)
      assert {:error, _} = read("1 2", :en)
      assert {:ok, 12} = read(" 12 ", :en)
      assert {:ok, -12} = read("- 12", :en)
    end
  end

  describe "grouping modes" do
    test "lenient, strict and sizes" do
      assert {:ok, 1234} = read("1,234", :en)
      assert {:ok, 12_345_678} = read("12,345,678", :en, grouping: :strict)
      assert {:error, _} = read("1,23,456", :en, grouping: :strict)
      assert {:ok, 1_234_567} = read("12,34,567", :"en-IN", grouping: :strict)
      assert {:ok, 1_234_567} = read("1,234,567", :"en-IN", grouping: :sizes)
      assert {:ok, 123} = read("1.23", :de)
      assert {:error, _} = read("1.23", :de, grouping: :sizes)
      assert {:error, _} = read("1,234.56", :de)
      assert {:error, _} = read("1,,000", :en)
    end
  end

  describe "a period foreign to the locale" do
    test "is a decimal point between digits, but not a thousands group" do
      assert {:ok, 1.5} = read("1.5", :fr)
      assert {:error, _} = read("1.234", :fr)
      assert {:error, _} = read("1.234,5", :fr)
      # `de-AT` groups the euro with a period, so with the euro's reading in
      # play its plain reading refuses one; alone it reads a decimal point.
      assert {:error, _} = read("1.5", :"de-AT", currency: :EUR)
      assert {:ok, 1.5} = read("1.5", :"de-AT")
    end
  end

  describe "number types and digits" do
    test "an integer where the text is one, else a float, or the type asked for" do
      assert {:ok, 5} = read("5", :en)
      assert {:ok, 5.5} = read("5.5", :en)
      assert {:ok, 5.0} = read("5", :en, number: :float)
      assert {:error, _} = read("5.5", :en, number: :integer)
      assert {:ok, decimal} = read("1,234.50", :en, number: :decimal)
      assert Decimal.to_string(decimal) == "1234.50"
      assert {:ok, 1.5e-2} = read("1.5E-2", :en)
    end

    test "the locale's digits and Latin digits" do
      assert {:ok, 1234.56} = read("١٬٢٣٤٫٥٦", :"ar-EG")
      assert {:ok, 1234.56} = read("1,234.56", :"ar-EG")
      assert {:ok, 1234.56} = read("१,२३४.५६", :"hi-IN", number_system: :deva)
      assert {:error, _} = read("١٢", :en)
      assert {:error, _} = read("５", :en)
      assert {:error, _} = read("5²", :en)
    end

    test "format characters are dropped anywhere" do
      assert {:ok, -5} = read("‎-5‏", :en)
      assert {:ok, -5} = read("؜-5", :"ar-EG")
      assert {:ok, 1000} = read("1­000", :en)
    end
  end
end
