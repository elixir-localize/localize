defmodule Localize.DateCalendarTypeTest do
  @moduledoc """
  A calendar whose dates take their names from more than one CLDR calendar
  answers the optional `cldr_calendar_type/3` for a date, as Calendrical's
  composite calendars answer with the calendar in effect on it. Localize
  names a date's months and days from that answer, and from
  `cldr_calendar_type/0` for a calendar without it and where no date is
  given.

  The stand-in names its months from CLDR's generic calendar ("M03") before
  2000 and from the Gregorian ("March") after.

  """

  use ExUnit.Case, async: true

  defmodule Split do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :gregorian
    def era_calendar_type, do: :gregorian
    def cldr_calendar_type(year, _month, _day) when year < 2000, do: :generic
    def cldr_calendar_type(_year, _month, _day), do: :gregorian
  end

  defmodule Whole do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :generic
  end

  defp date(year, calendar), do: %Date{year: year, month: 3, day: 15, calendar: calendar}

  test "a date is named from its calendar's answer for the date" do
    assert Localize.Calendar.date_calendar_type(date(1999, Split)) == :generic
    assert Localize.Calendar.date_calendar_type(date(2000, Split)) == :gregorian
    assert Localize.Calendar.localize(date(1999, Split), :month) == {:ok, "M03"}
    assert Localize.Calendar.localize(date(2000, Split), :month) == {:ok, "March"}

    assert {:ok, before} = Localize.Date.to_string(date(1999, Split), format: :long, locale: :en)
    assert before =~ "M03"
    assert {:ok, after_} = Localize.Date.to_string(date(2000, Split), format: :long, locale: :en)
    assert after_ =~ "March"
  end

  test "a date-time is named from its calendar's answer for its date" do
    datetime = %NaiveDateTime{
      year: 1999,
      month: 3,
      day: 15,
      hour: 9,
      minute: 0,
      second: 0,
      microsecond: {0, 0},
      calendar: Split
    }

    assert {:ok, written} = Localize.DateTime.to_string(datetime, format: :long, locale: :en)
    assert written =~ "M03"
  end

  test "a partial date is asked on its first month and day" do
    assert Localize.Calendar.date_calendar_type(%{year: 1999, calendar: Split}) == :generic
    assert Localize.Calendar.date_calendar_type(%{month: 3, calendar: Split}) == :gregorian
  end

  test "a calendar without the per-date answer is named from its own type" do
    assert Localize.Calendar.date_calendar_type(date(2000, Whole)) == :generic
    assert Localize.Calendar.localize(date(2000, Whole), :month) == {:ok, "M03"}
    assert Localize.Calendar.date_calendar_type(~D[2000-03-15]) == :gregorian
  end
end
