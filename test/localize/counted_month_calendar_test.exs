defmodule Localize.CountedMonthCalendarTest do
  @moduledoc """
  Covers a calendar whose months are counted from the year's first day.

  `Localize.Test.CountedMonthCalendar` stands in for
  `Calendrical.Julian.March25`, which Localize cannot load: its month 1 day 1
  is the day the Julian calendar names 25 March, so a date's month and day
  fields are its place in the counted month and not the month and day that
  name it. The formatter writes the names through `cardinal_month/1` and
  `cardinal_day/3`, and the parser reads them back through the calendar's
  `date_from_julian_date/3`.

  """

  use ExUnit.Case, async: true

  alias Localize.Test.CountedMonthCalendar, as: Counted
  alias Localize.Test.LadyDayCalendar

  # Each counted date beside the month and day that name it. Month 1 is 25 to
  # 31 March, months 2 to 12 are April to February, month 13 is 1 to 24 March,
  # and the year written is always the calendar's own.
  @dates [
    {{1750, 1, 1}, "March 25, 1750"},
    {{1750, 1, 7}, "March 31, 1750"},
    {{1750, 2, 1}, "April 1, 1750"},
    {{1750, 2, 15}, "April 15, 1750"},
    {{1750, 10, 25}, "December 25, 1750"},
    {{1750, 11, 5}, "January 5, 1750"},
    {{1750, 12, 28}, "February 28, 1750"},
    {{1750, 13, 1}, "March 1, 1750"},
    {{1750, 13, 24}, "March 24, 1750"}
  ]

  defp date({year, month, day}),
    do: %Date{year: year, month: month, day: day, calendar: Counted}

  defp fields(%Date{} = date), do: {date.year, date.month, date.day}

  describe "writing" do
    test "the month and day a date's calendar names it by" do
      for {counted, written} <- @dates do
        assert {:ok, ^written} =
                 Localize.Date.to_string(date(counted), locale: :en, format: :long),
               "expected #{inspect(counted)} to be written #{inspect(written)}"
      end
    end

    test "a padded day is the named day padded" do
      assert {:ok, "03/25/1750"} =
               Localize.Date.to_string(date({1750, 1, 1}), locale: :en, format: "MM/dd/y")

      assert {:ok, "3/25/50"} =
               Localize.Date.to_string(date({1750, 1, 1}), locale: :en, format: :short)
    end

    test "an ordinal day is the named day" do
      assert {:ok, text} =
               Localize.Date.to_string(date({1750, 1, 1}), locale: :en, format: "MMMM ddd, y")

      assert text =~ "25"
    end
  end

  describe "reading back" do
    test "every written date gives the date it was written from" do
      for {counted, written} <- @dates do
        assert {:ok, read} = Localize.Date.parse(written, locale: :en, calendar: Counted),
               "#{inspect(written)} did not parse"

        assert fields(read) == counted,
               "#{inspect(written)} read as #{inspect(fields(read))}, not #{inspect(counted)}"
      end
    end

    test "a date read as a map carries the calendar's own fields" do
      assert {:ok, read} =
               Localize.Date.parse("March 25, 1750", locale: :en, calendar: Counted, as: :map)

      assert %{year: 1750, month: 1, day: 1} = read
    end

    test "an interval of two written dates reads back" do
      assert {:ok, text} =
               Localize.Interval.to_string(date({1750, 1, 1}), date({1750, 2, 15}),
                 locale: :en,
                 format: :long
               )

      assert {:ok, %Date.Range{first: first, last: last}} =
               Localize.Interval.parse(text, locale: :en, calendar: Counted)

      assert fields(first) == {1750, 1, 1}
      assert fields(last) == {1750, 2, 15}
    end

    test "a day the named month has but the counted month does not is refused" do
      # Month 1 holds seven days, 25 to 31 March, so there is no 24th in it;
      # "March 24" is month 13 and reads as that rather than as month 1 day 0.
      assert {:ok, read} = Localize.Date.parse("March 24, 1750", locale: :en, calendar: Counted)
      assert fields(read) == {1750, 13, 24}
    end
  end

  describe "a calendar that does not name its days" do
    test "keeps the day field it was given" do
      # LadyDayCalendar's year turns on 25 March but its months and days are
      # ISO's, and it exports neither callback, so nothing is renamed.
      date = %Date{year: 1750, month: 3, day: 25, calendar: LadyDayCalendar}

      assert {:ok, "March 25, 1750"} = Localize.Date.to_string(date, locale: :en, format: :long)

      assert {:ok, read} =
               Localize.Date.parse("March 25, 1750", locale: :en, calendar: LadyDayCalendar)

      assert {read.year, read.month, read.day} == {1750, 3, 25}
    end

    test "Calendar.ISO is unaffected" do
      assert {:ok, "June 15, 2026"} =
               Localize.Date.to_string(~D[2026-06-15], locale: :en, format: :long)

      assert {:ok, ~D[2026-06-15]} = Localize.Date.parse("June 15, 2026", locale: :en)
    end
  end
end
