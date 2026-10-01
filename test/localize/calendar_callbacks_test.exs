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
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :gregorian
    def month_of_year(_year, month, _day), do: month
    def cardinal_month(month), do: Integer.mod(month + 7 - 2, 12) + 1
    def year_of_era(year, _month, _day), do: {year, 1}
    def calendar_year(year, _month, _day), do: year

    def day_of_week(year, month, day, starting_on) do
      {civil_year, civil_month} = civil(year, month)
      Calendar.ISO.day_of_week(civil_year, civil_month, day, starting_on)
    end

    def days_in_month(year, month) do
      {civil_year, civil_month} = civil(year, month)
      Calendar.ISO.days_in_month(civil_year, civil_month)
    end

    def valid_date?(year, month, day),
      do: month in 1..12 and day in 1..days_in_month(year, month)

    defp civil(year, month) when month <= 6, do: {year - 1, cardinal_month(month)}
    defp civil(year, month), do: {year, cardinal_month(month)}
  end

  # The ISO week calendar: a date is its year, its week and its day of the
  # week, and its month the 4-4-5 month of the quarter its week falls in.
  defmodule IsoWeek do
    @moduledoc false
    use Localize.Test.StandInCalendar

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

  # A calendar answering Localize's questions with things that are not
  # answers.
  defmodule Misanswering do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def calendar_year(_year, _month, _day), do: :no_year
    def related_gregorian_year(_year, _month, _day), do: :no_year
    def cyclic_year(_year, _month, _day), do: :no_year
    def iso_week_of_year(_year, _month, _day), do: :no_week
    def day_of_year(_year, _month, _day), do: :no_day
    def day_of_week(_year, _month, _day, _starting_on), do: :no_day
  end

  # A calendar answering the questions Localize puts to a Calendrical
  # calendar, but without the `Calendar` behaviour they extend.
  defmodule Unconvertible do
    @moduledoc false

    def cldr_calendar_type, do: :gregorian
    def era_calendar_type, do: :gregorian
    def month_of_year(_year, month, _day), do: month
    def cardinal_month(month), do: month
    def calendar_year(year, _month, _day), do: year
    def related_gregorian_year(year, _month, _day), do: year
    def cyclic_year(year, _month, _day), do: year
    def iso_week_of_year(year, month, day), do: :calendar.iso_week_number({year, month, day})
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

    # A month is written as the CLDR month its name uses, in figures as in
    # words, so it reads back to the calendar's own month: the first month
    # is written 7 and July.
    test "writes dates that parse back in each locale's standard formats" do
      reference = date(2026, 1, 1, FiscalJuly)

      dates =
        for {year, month, day} <- [{2026, 1, 1}, {2026, 6, 25}, {2026, 7, 4}, {2026, 12, 30}],
            do: %Date{year: year, month: month, day: day, calendar: FiscalJuly}

      failures =
        for locale <- [:en, :de, :fr, :ja, :zh],
            format <- [:short, :medium, :long],
            date <- dates,
            {:ok, text} = Localize.Date.to_string(date, format: format, locale: locale),
            parsed =
              Localize.Date.parse(text,
                locale: locale,
                calendar: FiscalJuly,
                reference_date: reference
              ),
            parsed != {:ok, date} do
          {locale, format, date, text, parsed}
        end

      assert failures == []
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

    test "is refused by relative time, time formats and the parser" do
      unknown = {:error, Localize.UnknownCalendarError.exception(calendar: Unanswered)}
      value = %Date{year: 2026, month: 1, day: 1, calendar: Unanswered}
      time = %Time{hour: 10, minute: 0, second: 0, microsecond: {0, 0}, calendar: Unanswered}

      assert Localize.DateTime.Relative.to_string(value, relative_to: ~D[2026-02-01]) == unknown
      assert Localize.DateTime.Relative.to_string(~D[2026-02-01], relative_to: value) == unknown
      assert Localize.Time.to_string(time, locale: :en) == unknown
      assert Localize.Time.to_parts(time, locale: :en) == unknown
      assert Localize.Date.parse("Jan 1, 2026", locale: :en, calendar: Unanswered) == unknown
    end

    test "a calendar without the Calendar behaviour is refused too" do
      unknown = {:error, Localize.UnknownCalendarError.exception(calendar: Unconvertible)}
      value = %Date{year: 2026, month: 1, day: 1, calendar: Unconvertible}

      assert Localize.Date.to_string(value, locale: :en) == unknown
      assert Localize.Date.parse("Jan 1, 2026", locale: :en, calendar: Unconvertible) == unknown
      assert Localize.DateTime.Relative.to_string(value, relative_to: ~D[2026-02-01]) == unknown
    end

    test "a calendar that is not a module is refused too" do
      unknown = {:error, Localize.UnknownCalendarError.exception(calendar: "gregorian")}
      assert Localize.Date.to_string(date(2026, 1, 1, "gregorian"), locale: :en) == unknown
    end
  end

  describe "an answer that is not one" do
    test "is an error in the field that asks for it" do
      value = date(2026, 1, 1, Misanswering)

      for {format, answer} <- [
            {"y", :no_year},
            {"r", :no_year},
            {"U", :no_year},
            {"Y", :no_week},
            {"w", :no_week},
            {"D", :no_day},
            {"E", :no_day},
            {"e", :no_day},
            {"c", :no_day}
          ] do
        assert {:error, %Localize.InvalidValueError{value: ^answer}} =
                 Localize.Date.to_string(value, format: format, locale: :en),
               format
      end
    end
  end

  describe "Calendar.ISO" do
    # Localize answers for `Calendar.ISO`, which has none of the Calendrical
    # behaviour's callbacks, through one module that answers every question
    # put to any other calendar.
    test "is answered for by a module that answers every question" do
      assert Localize.Calendar.answering(Calendar.ISO) == Localize.Calendar.ISO
      assert Localize.Calendar.validate_calendar(%{calendar: Localize.Calendar.ISO}) == :ok
    end

    test "is answered as the Gregorian calendar" do
      iso = Localize.Calendar.ISO

      assert iso.cldr_calendar_type() == :gregorian
      assert iso.era_calendar_type() == :gregorian
      assert iso.month_of_year(2026, 10, 1) == 10
      assert iso.cardinal_month(10) == 10
      assert iso.calendar_year(-44, 3, 15) == -44
      assert iso.related_gregorian_year(2026, 10, 1) == 2026
      assert iso.iso_week_of_year(2027, 1, 1) == {2026, 53}
      assert iso.year_of_era(-44, 3, 15) == Calendar.ISO.year_of_era(-44, 3, 15)
    end
  end
end
