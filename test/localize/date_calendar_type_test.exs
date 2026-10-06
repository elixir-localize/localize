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

  # A calendar of the generic calendar's formats and months, with the
  # Gregorian calendar's eras, as the calendar a composite had before its
  # change is a calendar of its own.
  defmodule Earlier do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :generic
    def era_calendar_type, do: :gregorian
  end

  # A composite of two calendars with different CLDR types, as
  # Calendrical's `Reform.Japan` is of its lunisolar and its Japanese
  # calendar: its dates before 2000 are written with the formats of
  # `Earlier`, which it names for them to be read in.
  defmodule Composite do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :gregorian
    def era_calendar_type, do: :gregorian
    def cldr_calendar_type(year, _month, _day) when year < 2000, do: :generic
    def cldr_calendar_type(_year, _month, _day), do: :gregorian
    def parsing_calendars, do: [Earlier]
  end

  defmodule NamesNoCalendar do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def parsing_calendars, do: [String, "hebrew", :hebrew]
  end

  defmodule NamesNoList do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def parsing_calendars, do: :generic
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

  # A composite calendar writes the dates of each of its calendars with
  # that calendar's formats, so the formats of its own CLDR type do not
  # read them all. It names the other calendars with the optional
  # `parsing_calendars/0`, and a date is read in each as any calendar's is
  # and converted (user, 2026-10-06; the calendars are named as modules,
  # which is mine). en.xml's generic medium date is "MMM d, y G" and root's
  # generic months are "M01" to "M12".
  describe "a calendar that names more calendars for its dates to be read in" do
    test "answers them after the calendar its dates are read in" do
      assert Localize.Calendar.parsing_calendars(Composite) == {:ok, [Composite, Earlier]}
      assert Localize.Calendar.parsing_calendars(Split) == {:ok, [Split]}
      assert Localize.Calendar.parsing_calendars(Calendar.ISO) == {:ok, [Calendar.ISO]}
    end

    test "reads a date of its earlier calendar as that calendar writes it" do
      assert Localize.Date.to_string(date(1999, Composite), locale: :en) ==
               {:ok, "M03 15, 1999 AD"}

      assert Localize.Date.parse("M03 15, 1999 AD", locale: :en, calendar: Composite) ==
               {:ok, date(1999, Composite)}

      assert Localize.Date.parse("Mar 15, 2005", locale: :en, calendar: Composite) ==
               {:ok, date(2005, Composite)}
    end

    test "reads back every date it writes, at a standard format and a skeleton" do
      for year <- [1999, 2005],
          locale <- [:en, :de, :ja, :ar],
          format <- [:short, :medium, :long, :full, :yMMMd, :yMd] do
        written = date(year, Composite)
        {:ok, text} = Localize.Date.to_string(written, locale: locale, format: format)

        assert Localize.Date.parse(text, locale: locale, calendar: Composite, format: format) ==
                 {:ok, written},
               "#{year} #{locale} #{format} #{text}"

        if format in [:medium, :long, :full] do
          assert Localize.Date.parse(text, locale: locale, calendar: Composite) == {:ok, written},
                 "#{year} #{locale} #{format} #{text}"
        end
      end
    end

    # A reading is held to the calendar its date is written in: a day the
    # composite writes with another calendar's formats than the text has is
    # one the formatter writes otherwise.
    test "refuses a date written in the formats of the calendar it is not of" do
      assert {:error, %Localize.DateParseError{input: "Mar 15, 1999", calendar: Composite}} =
               Localize.Date.parse("Mar 15, 1999", locale: :en, calendar: Composite)

      assert {:error, %Localize.DateParseError{}} =
               Localize.Date.parse("M03 15, 2005 AD", locale: :en, calendar: Composite)
    end

    test "reads an interval and a date and time the same way" do
      from = date(1999, Composite)
      to = %{from | day: 20}

      {:ok, interval} = Localize.Interval.to_string(from, to, locale: :en)

      assert Localize.Interval.parse(interval, locale: :en, calendar: Composite) ==
               {:ok, Date.range(from, to)}

      naive = %NaiveDateTime{
        year: 1999,
        month: 3,
        day: 15,
        hour: 9,
        minute: 30,
        second: 0,
        microsecond: {0, 0},
        calendar: Composite
      }

      {:ok, written} = Localize.DateTime.to_string(naive, locale: :en)
      assert written =~ "M03"
      assert Localize.DateTime.parse(written, locale: :en, calendar: Composite) == {:ok, naive}
    end

    # A calendar that names none is read as it was, its dates not held.
    test "leaves a calendar that names none as it was" do
      assert Localize.Date.parse("Mar 15, 1999", locale: :en, calendar: Split) ==
               {:ok, date(1999, Split)}
    end

    test "is an error, and no raise, where what it names is no calendar" do
      for calendar <- [NamesNoCalendar, NamesNoList] do
        assert {:error, exception} = Localize.Calendar.parsing_calendars(calendar)
        assert is_exception(exception)

        assert {:error, _exception} =
                 Localize.Date.parse("Mar 15, 1999", locale: :en, calendar: calendar)

        assert {:error, _exception} =
                 Localize.DateTime.parse("Mar 15, 1999, 9:30 AM", locale: :en, calendar: calendar)

        assert {:error, _exception} =
                 Localize.Interval.parse("Mar 15 – 20, 1999", locale: :en, calendar: calendar)
      end
    end
  end
end
