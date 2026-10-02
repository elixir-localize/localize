defmodule Localize.HebrewNumeralDateParseTest do
  @moduledoc """
  `he` writes a Hebrew date's day and year in Hebrew numerals, the `hebr`
  numbering system: 22 Tevet 5784 is "כ״ב בטבת ה׳תשפ״ד". The letters add up
  (כ 20 and ב 2; ת 400, ש 300, פ 80 and ד 4), a geresh after a letter that
  more letters follow counts thousands (ה׳, 5000), and 15 and 16 are ט״ו and
  ט״ז, never the letters of the divine name.

  """

  use ExUnit.Case, async: true

  alias Localize.Number.HebrewNumerals

  # Stands in for Calendrical's Hebrew calendar: its names and numerals are
  # the CLDR Hebrew calendar's, its fields counted as ISO's are.
  defmodule Hebrew do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :hebrew
  end

  describe "Localize.Number.HebrewNumerals.parse/1" do
    test "adds up the letters, the largest first" do
      assert HebrewNumerals.parse("כ״ב") == {:ok, 22}
      assert HebrewNumerals.parse("ט״ו") == {:ok, 15}
      assert HebrewNumerals.parse("ט״ז") == {:ok, 16}
      assert HebrewNumerals.parse("ה׳") == {:ok, 5}
      assert HebrewNumerals.parse("ק׳") == {:ok, 100}
      assert HebrewNumerals.parse("תתקצ״ט") == {:ok, 999}
      assert HebrewNumerals.parse("תשפ\"ד") == {:ok, 784}
    end

    test "counts the letters before a geresh that more letters follow as thousands" do
      assert HebrewNumerals.parse("ה׳תשפ״ד") == {:ok, 5784}
      assert HebrewNumerals.parse("ה'תשפ\"ד") == {:ok, 5784}
      assert HebrewNumerals.parse("ה׳א׳") == {:ok, 5001}
    end

    test "reads a whole number of thousands written with the word for them" do
      assert HebrewNumerals.parse("אלף") == {:ok, 1000}
      assert HebrewNumerals.parse("ה׳ אלפים") == {:ok, 5000}
    end

    test "reads no word, and nothing else, as a numeral" do
      for not_a_numeral <- ["בטבת", "אב", "יי", "", "׳", "5784", "abc", "ה׳ ימים", nil, 5784] do
        assert HebrewNumerals.parse(not_a_numeral) == :error, inspect(not_a_numeral)
      end
    end
  end

  describe "a Hebrew date in he" do
    test "is read with its day and year in Hebrew numerals" do
      assert Localize.Date.parse("כ״ב בטבת ה׳תשפ״ד", locale: :he, calendar: Hebrew) ==
               {:ok, Date.new!(5784, 4, 22, Hebrew)}
    end

    test "reads back as the formatter writes it" do
      for {year, month, day} <- [{5784, 4, 22}, {5785, 1, 15}, {5785, 7, 16}, {5786, 12, 30}],
          date = Date.new!(year, month, day, Hebrew),
          format <- [:short, :long, :full] do
        {:ok, text} = Localize.Date.to_string(date, locale: :he, format: format)
        assert Localize.Date.parse(text, locale: :he, calendar: Hebrew) == {:ok, date}, text
      end
    end
  end
end
