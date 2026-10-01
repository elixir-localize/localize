defmodule Localize.CalendarCallbacksTest do
  @moduledoc """
  Covers taking a date's month from its calendar's callbacks: the CLDR month
  its name uses is `month_of_year/3` then `cardinal_month/1`, and the day and
  year are the calendar's own fields, never changed. Localize does not depend
  on Calendrical, so these stand-ins answer as Calendrical's calendars do: a
  month-based year beginning in July, and an ISO week calendar laying its
  weeks out 4-4-5 by quarter.

  """

  use ExUnit.Case, async: true

  @thin <<0x2009::utf8>>

  # A fiscal year beginning in July, numbered by the civil year it ends in:
  # 1 July 2025 is the first day of its first month of 2026.
  defmodule FiscalJuly do
    @moduledoc false

    def cldr_calendar_type, do: :gregorian
    def month_of_year(_year, month, _day), do: month
    def cardinal_month(month), do: Integer.mod(month + 7 - 2, 12) + 1
    def year_of_era(year, _month, _day), do: {year, 1}
    def calendar_year(year, _month, _day), do: year

    def day_of_week(year, month, day, starting_on) do
      {civil_year, civil_month} = civil(year, month)
      Calendar.ISO.day_of_week(civil_year, civil_month, day, starting_on)
    end

    defp civil(year, month) when month <= 6, do: {year - 1, cardinal_month(month)}
    defp civil(year, month), do: {year, cardinal_month(month)}
  end

  # The ISO week calendar: a date is its year, its week and its day of the
  # week, and its month the 4-4-5 month of the quarter its week falls in.
  defmodule IsoWeek do
    @moduledoc false

    def cldr_calendar_type, do: :gregorian

    def month_of_year(_year, 53, _day), do: 12

    def month_of_year(_year, week, _day) do
      quarter = div(week - 1, 13)
      week_in_quarter = Integer.mod(week - 1, 13) + 1

      month_in_quarter =
        cond do
          week_in_quarter <= 4 -> 1
          week_in_quarter <= 8 -> 2
          true -> 3
        end

      quarter * 3 + month_in_quarter
    end

    def cardinal_month(month), do: month
    def year_of_era(year, _week, _day), do: {year, 1}
    def calendar_year(year, _week, _day), do: year
  end

  # A calendar with Elixir's callbacks alone, which cannot say what its
  # months are named.
  defmodule Unanswered do
    @moduledoc false

    def day_of_week(year, month, day, starting_on),
      do: Calendar.ISO.day_of_week(year, month, day, starting_on)
  end

  defp date(year, month, day, calendar),
    do: %{year: year, month: month, day: day, calendar: calendar}

  describe "a year beginning in July" do
    test "names its first month July, with the calendar's own day and year" do
      assert Localize.Date.to_string(date(2026, 1, 1, FiscalJuly), locale: :en) ==
               {:ok, "Jul 1, 2026"}

      assert Localize.Date.to_string(date(2026, 1, 1, FiscalJuly), format: "M/d/y", locale: :en) ==
               {:ok, "7/1/2026"}
    end

    test "names its sixth month December and its seventh January" do
      assert Localize.Date.to_string(date(2026, 6, 25, FiscalJuly), locale: :en) ==
               {:ok, "Dec 25, 2026"}

      assert Localize.Date.to_string(date(2026, 7, 4, FiscalJuly), format: "MMMM", locale: :en) ==
               {:ok, "January"}
    end

    test "names its months alike in Localize.Calendar.localize/3, intervals and messages" do
      assert Localize.Calendar.localize(date(2026, 1, 1, FiscalJuly), :month, locale: :en) ==
               {:ok, "July"}

      assert Localize.Interval.to_string(
               date(2026, 1, 1, FiscalJuly),
               date(2026, 1, 15, FiscalJuly),
               locale: :en
             ) ==
               {:ok, "Jul 1#{@thin}–#{@thin}15, 2026"}

      assert Localize.Message.format(
               "{$d :date}",
               %{"d" => %Date{year: 2026, month: 1, day: 1, calendar: FiscalJuly}},
               locale: :en
             ) ==
               {:ok, "Jul 1, 2026"}
    end

    test "names a month without its year or day" do
      assert Localize.Date.to_string(%{month: 1, calendar: FiscalJuly},
               format: "MMM",
               locale: :en
             ) ==
               {:ok, "Jul"}

      assert Localize.Date.to_string(%{year: 2026, month: 12, calendar: FiscalJuly},
               format: "MMM y",
               locale: :en
             ) == {:ok, "Jun 2026"}
    end
  end

  describe "an ISO week calendar" do
    test "names a week by the 4-4-5 month its quarter puts it in, with its own day and year" do
      assert Localize.Date.to_string(date(2026, 25, 2, IsoWeek), locale: :en) ==
               {:ok, "Jun 2, 2026"}

      assert Localize.Date.to_string(date(2026, 25, 2, IsoWeek), format: "M/d/yy", locale: :en) ==
               {:ok, "6/2/26"}

      assert Localize.Date.to_string(date(2026, 27, 1, IsoWeek), locale: :en) ==
               {:ok, "Jul 1, 2026"}

      assert Localize.Date.to_string(date(2026, 53, 7, IsoWeek), format: "M/d", locale: :en) ==
               {:ok, "12/7"}
    end
  end

  describe "a calendar that cannot say what its months are" do
    test "is refused wherever a date enters" do
      value = date(2026, 1, 1, Unanswered)
      unknown = {:error, Localize.UnknownCalendarError.exception(calendar: Unanswered)}

      assert Localize.Date.to_string(value, locale: :en) == unknown
      assert Localize.Date.to_parts(value, locale: :en) == unknown
      assert Localize.DateTime.to_string(Map.put(value, :hour, 10), locale: :en) == unknown
      assert Localize.Interval.to_string(value, value, locale: :en) == unknown
      assert Localize.Interval.to_string(value, nil, locale: :en) == unknown
      assert Localize.Calendar.localize(value, :month, locale: :en) == unknown
    end

    test "a calendar that is not a module is refused too" do
      unknown = {:error, Localize.UnknownCalendarError.exception(calendar: "gregorian")}
      assert Localize.Date.to_string(date(2026, 1, 1, "gregorian"), locale: :en) == unknown
    end
  end
end
