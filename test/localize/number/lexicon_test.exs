defmodule Localize.Number.LexiconTest do
  use ExUnit.Case, async: true

  alias Localize.Number.Lexicon

  doctest Lexicon

  defp lexicon(locale, number_system \\ :latn, options \\ []) do
    {:ok, language_tag} = Localize.validate_locale(locale)
    {:ok, lexicon} = Lexicon.fetch(language_tag, number_system, options)
    lexicon
  end

  defp member?(set, character) do
    MapSet.member?(set, character)
  end

  describe "readings" do
    test "en reads a period decimal and a comma group, with their folds" do
      %{readings: [reading]} = lexicon(:en)

      assert member?(reading.decimal, ".")
      assert member?(reading.decimal, "．")
      assert member?(reading.group, ",")
      assert member?(reading.group, "，")
      refute member?(reading.group, ".")
      refute reading.space_group?
      assert reading.sizes == {3, 3}
    end

    test "de reads a comma decimal and a period group" do
      %{readings: [reading], period: period} = lexicon(:de)

      assert member?(reading.decimal, ",")
      assert member?(reading.group, ".")
      assert member?(period, ".")
    end

    test "de-AT groups a plain number with a space and the euro with a period" do
      %{readings: [plain]} = lexicon(:"de-AT")
      assert plain.space_group?
      assert member?(plain.group, " ")

      %{readings: [currency, plain]} = lexicon(:"de-AT", :latn, currency: :EUR)
      assert member?(currency.group, ".")
      refute currency.space_group?
      assert plain.space_group?
      assert member?(currency.decimal, ",") and member?(plain.decimal, ",")
    end

    test "de-CH groups with either apostrophe" do
      %{readings: [reading]} = lexicon(:"de-CH")

      assert member?(reading.group, "'")
      assert member?(reading.group, "’")
      assert member?(reading.decimal, ".")
    end

    test "fr-CH reads a franc amount with the currency's decimal point and the plain comma" do
      %{readings: [currency, plain]} = lexicon(:"fr-CH", :latn, currency: :CHF)

      assert member?(currency.decimal, ".")
      assert member?(plain.decimal, ",")
      assert member?(currency.group, "'") and member?(plain.group, "'")
    end

    test "en-IN groups by three and then by two" do
      %{readings: [reading]} = lexicon(:"en-IN")
      assert reading.sizes == {3, 2}
    end

    test "root separators add a reading only where they differ" do
      %{readings: [_en]} = lexicon(:en, :latn, root_separators: true)

      %{readings: [de, und]} = lexicon(:de, :latn, root_separators: true)
      assert member?(de.group, ".")
      assert member?(und.group, ",")
      assert und.tag.cldr_locale_id == :und
    end

    test "a currency's reading is cached and equal on a second fetch" do
      assert lexicon(:de, :latn, currency: :EUR) == lexicon(:de, :latn, currency: :EUR)
    end
  end

  describe "digits and signs" do
    test "ar-EG in arab digits reads them and Latin digits, with the arab separators" do
      %{digits: digits, readings: [reading]} = lexicon(:"ar-EG", :arab)

      assert digits["٠"] == 0 and digits["٩"] == 9
      assert digits["0"] == 0 and digits["9"] == 9
      assert member?(reading.decimal, "٫")
      assert member?(reading.decimal, ",")
      assert member?(reading.group, "٬")
    end

    test "ar-EG in Latin digits reads the Latin separators" do
      %{readings: [reading]} = lexicon(:"ar-EG", :latn)

      assert member?(reading.decimal, ".")
      assert member?(reading.group, ",")
    end

    test "the minus family reads as a minus, never the underscore" do
      %{minus: minus, plus: plus, dashes: dashes} = lexicon(:en)

      assert member?(minus, "-")
      assert member?(minus, "−")
      assert member?(minus, "–")
      refute member?(minus, "_")
      assert member?(plus, "+")
      assert member?(plus, "＋")

      # The em dash is no minus in `en`, so it may still stand for a zero
      # fraction; the dashes that are a minus do so as a minus.
      assert member?(dashes, "—")
      refute member?(dashes, "-")
      refute member?(dashes, "−")
    end
  end

  describe "number_system/3" do
    setup do
      {:ok, ar_eg} = Localize.validate_locale(:"ar-EG")
      {:ok, en} = Localize.validate_locale(:en)
      %{ar_eg: ar_eg, en: en}
    end

    test "the locale's system where its digits are written, else Latin", %{ar_eg: ar_eg} do
      assert {:ok, :arab} = Lexicon.number_system(ar_eg, "١٢٣", [])
      assert {:ok, :arab} = Lexicon.number_system(ar_eg, "1٢", [])
      assert {:ok, :latn} = Lexicon.number_system(ar_eg, "123", [])
      assert {:ok, :latn} = Lexicon.number_system(ar_eg, "", [])
    end

    test "an option names the system", %{ar_eg: ar_eg, en: en} do
      assert {:ok, :latn} = Lexicon.number_system(ar_eg, "١٢٣", number_system: :latn)
      assert {:ok, :deva} = Lexicon.number_system(en, "123", number_system: :deva)
    end

    test "a system with no digits is an error", %{en: en} do
      assert {:error, _} = Lexicon.number_system(en, "123", number_system: :nope)
    end
  end

  describe "errors" do
    test "an unknown currency" do
      {:ok, en} = Localize.validate_locale(:en)
      assert {:error, _} = Lexicon.fetch(en, :latn, currency: :XYZ)
    end
  end
end
