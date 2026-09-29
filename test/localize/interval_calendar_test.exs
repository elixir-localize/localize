defmodule Localize.IntervalCalendarTest do
  @moduledoc """
  Intervals, dates, times and date-times are formatted, and read, with the
  formats of their calendar.

  The expected strings are ICU4C 78.3's `DateIntervalFormat` output for the
  same skeleton, and its readings of the same text, except where a test
  says otherwise. Localize does not
  depend on Calendrical, so the calendars here are stand-ins that answer as
  Calendrical's do.

  """

  use ExUnit.Case, async: true

  # The Gregorian calendar's arithmetic with the Japanese calendar's eras
  # and CLDR data, as Calendrical's Japanese calendar has them.
  defmodule Japanese do
    @moduledoc false

    def cldr_calendar_type, do: :japanese
    def calendar_base, do: :month

    # Reiwa began on 2019-05-01 and Heisei on 1989-01-08.
    def year_of_era(year, month, day) do
      if {year, month, day} >= {2019, 5, 1},
        do: {year - 2018, 236},
        else: {year - 1988, 235}
    end

    def calendar_year(year, month, day), do: elem(year_of_era(year, month, day), 0)

    defdelegate valid_date?(year, month, day), to: Calendar.ISO
    defdelegate days_in_month(year, month), to: Calendar.ISO
    defdelegate months_in_year(year), to: Calendar.ISO
    defdelegate day_of_week(year, month, day, starting_on), to: Calendar.ISO
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
    defdelegate day_rollover_relative_to_midnight_utc, to: Calendar.ISO

    defdelegate naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond),
      to: Calendar.ISO

    defdelegate naive_datetime_from_iso_days(iso_days), to: Calendar.ISO
  end

  # Chinese years as Calendrical numbers them. In 4660 (2023) the leap
  # second month is the third month of thirteen; Gregorian 2023-04-01 is
  # its eleventh day.
  defmodule Chinese do
    @moduledoc false

    def cldr_calendar_type, do: :chinese
    def calendar_base, do: :month

    def months_in_year(4660), do: 13
    def months_in_year(_year), do: 12

    def days_in_month(4660, 3), do: 29
    def days_in_month(_year, _month), do: 30

    def valid_date?(year, month, day),
      do: month in 1..months_in_year(year) and day in 1..days_in_month(year, month)

    def month_of_year(4660, 3, _day), do: {2, :leap}
    def month_of_year(4660, month, _day) when month > 3, do: month - 1
    def month_of_year(_year, month, _day), do: month

    def calendar_year(year, _month, _day), do: year
    def year_of_era(year, _month, _day), do: {year, 0}
    def related_gregorian_year(year, _month, _day), do: year - 2637
    def cyclic_year(year, _month, _day), do: Localize.Utils.Math.amod(year, 60)

    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  # A calendar with the Hebrew calendar's CLDR data, for times.
  defmodule HebrewTimes do
    @moduledoc false

    def cldr_calendar_type, do: :hebrew
  end

  # The Buddhist calendar: the Gregorian calendar's arithmetic, its years
  # numbered 543 ahead in the one era CLDR names for it.
  defmodule Buddhist do
    @moduledoc false
    @offset 543

    def cldr_calendar_type, do: :buddhist
    def calendar_base, do: :month
    def calendar_year(year, _month, _day), do: year
    def year_of_era(year, _month, _day), do: {year, 0}

    def valid_date?(year, month, day), do: Calendar.ISO.valid_date?(year - @offset, month, day)
    def days_in_month(year, month), do: Calendar.ISO.days_in_month(year - @offset, month)
    def months_in_year(year), do: Calendar.ISO.months_in_year(year - @offset)

    def day_of_week(year, month, day, starting_on),
      do: Calendar.ISO.day_of_week(year - @offset, month, day, starting_on)

    defdelegate date_to_string(year, month, day), to: Calendar.ISO
    defdelegate day_rollover_relative_to_midnight_utc, to: Calendar.ISO

    def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
      Calendar.ISO.naive_datetime_to_iso_days(
        year - @offset,
        month,
        day,
        hour,
        minute,
        second,
        microsecond
      )
    end

    def naive_datetime_from_iso_days(iso_days) do
      {year, month, day, hour, minute, second, microsecond} =
        Calendar.ISO.naive_datetime_from_iso_days(iso_days)

      {year + @offset, month, day, hour, minute, second, microsecond}
    end
  end

  defp date(calendar, year, month, day),
    do: %Date{calendar: calendar, year: year, month: month, day: day}

  defp datetime(calendar, year, month, day, hour, minute) do
    %NaiveDateTime{
      calendar: calendar,
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: 0,
      microsecond: {0, 0}
    }
  end

  defp time(calendar, hour, minute),
    do: %Time{calendar: calendar, hour: hour, minute: minute, second: 0, microsecond: {0, 0}}

  describe "a date interval takes its calendar's interval formats" do
    # `en`'s Japanese medium date is `GyMMMd`.
    test "within a Japanese era" do
      assert Localize.Interval.to_string(
               date(Japanese, 2023, 4, 1),
               date(Japanese, 2023, 4, 10),
               locale: :en
             ) == {:ok, "Apr 1\u2009–\u200910, 5 Reiwa"}
    end

    # ICU takes an interval's greatest difference to be its era when the
    # era changes, whatever else changes with it.
    test "across a change of Japanese era within a year" do
      assert Localize.Interval.to_string(
               date(Japanese, 2019, 4, 30),
               date(Japanese, 2019, 5, 1),
               locale: :en
             ) == {:ok, "Apr 30, 31 Heisei\u2009–\u2009May 1, 1 Reiwa"}

      assert Localize.Interval.to_string(
               date(Japanese, 2019, 4, 1),
               date(Japanese, 2019, 6, 10),
               locale: :en
             ) == {:ok, "Apr 1, 31 Heisei\u2009–\u2009Jun 10, 1 Reiwa"}
    end

    test "in a leap month of the Chinese calendar" do
      leap_11 = date(Chinese, 4660, 3, 11)

      for {to, options, expected} <- [
            {date(Chinese, 4660, 3, 20), [locale: :en, fields: :month_and_day],
             "Mo2bis 11\u2009–\u200920"},
            {date(Chinese, 4660, 4, 1), [locale: :en, fields: :month_and_day],
             "Mo2bis 11\u2009–\u2009Mo3 1"},
            {date(Chinese, 4660, 4, 1), [locale: :en, fields: :year_and_month],
             "Mo2bis\u2009–\u2009Mo3 gui-mao"},
            {date(Chinese, 4661, 3, 12), [locale: :en, fields: :year_and_month],
             "Mo2bis gui-mao\u2009–\u2009Mo3 jia-chen"},
            {date(Chinese, 4660, 3, 20), [locale: :zh], "2023年闰二月11至20"},
            {date(Chinese, 4660, 4, 1), [locale: :zh], "2023年闰二月11至三月1"}
          ] do
        assert Localize.Interval.to_string(leap_11, to, options) == {:ok, expected},
               "#{inspect(options)} to #{inspect(to)}"
      end
    end

    # `en`'s Chinese medium date, "MMM d, r", has the skeleton `rMMMd`. TR35
    # matches it to the `yMMMd` interval item, whose "MMM d – d, U" writes
    # the cyclic year where the request asks for the related Gregorian one.
    # ICU4C's interval matcher takes `r` and `y` for different fields, finds
    # no item, and writes both dates in full: "Mo2bis 11, 2023 – Mo2bis 20,
    # 2023".
    test "in the related Gregorian year a Chinese format asks for" do
      assert Localize.Interval.to_string(
               date(Chinese, 4660, 3, 11),
               date(Chinese, 4660, 3, 20),
               locale: :en
             ) == {:ok, "Mo2bis 11\u2009–\u200920, 2023"}
    end
  end

  describe "a time interval takes its calendar's interval formats" do
    # CLDR's `de` Hebrew calendar has the generic calendar's time
    # intervals, without the Gregorian calendar's "Uhr".
    test "in de" do
      assert Localize.Interval.to_string(
               time(HebrewTimes, 10, 0),
               time(HebrewTimes, 11, 30),
               locale: :de,
               format: :short
             ) == {:ok, "10:00–11:30"}

      assert Localize.Interval.to_string(~T[10:00:00], ~T[11:30:00], locale: :de, format: :short) ==
               {:ok, "10:00–11:30 Uhr"}
    end
  end

  describe "a time takes its calendar's formats" do
    # CLDR gives the Chinese calendar root's "h B" for `Bh`, where `de`'s
    # Gregorian calendar has "h 'Uhr' B"; ICU4C 78.3 writes "10 vorm." and
    # "10 Uhr vorm.".
    test "in de" do
      assert Localize.Time.to_string(time(Chinese, 10, 5), locale: :de, format: :Bh) ==
               {:ok, "10 vorm."}

      assert Localize.DateTime.to_string(datetime(Chinese, 4660, 3, 11, 10, 5),
               locale: :de,
               format: :Bh
             ) == {:ok, "10 vorm."}

      assert Localize.Time.to_string(~T[10:05:00], locale: :de, format: :Bh) ==
               {:ok, "10 Uhr vorm."}
    end
  end

  describe "a date-time interval takes its calendar's date-time pattern" do
    # CLDR gives `nl` Buddhist dates the date-time pattern "{1} {0}" and
    # Gregorian ones "{1}, {0}". ICU4C writes "1 apr 2566 BE, 10:00:00 –
    # 10:30:00": its `DateIntervalFormat` joins every calendar's date to its
    # time range with the Gregorian pattern, reading
    # `calendar/gregorian/DateTimePatterns`.
    test "in nl" do
      options = [locale: :nl, format: :medium, style: :standard]

      assert Localize.Interval.to_string(
               datetime(Buddhist, 2566, 4, 1, 10, 0),
               datetime(Buddhist, 2566, 4, 1, 10, 30),
               options
             ) == {:ok, "1 apr 2566 BE 10:00:00\u2009–\u200910:30:00"}

      assert Localize.Interval.to_string(
               ~N[2023-04-01 10:00:00],
               ~N[2023-04-01 10:30:00],
               options
             ) == {:ok, "1 apr 2023, 10:00:00\u2009–\u200910:30:00"}
    end
  end

  describe "a date is read with its calendar's standard formats first" do
    # ICU4C 78.3 reads `de`'s Japanese short "dd.MM.yy GGGGG" "01.04.05 R"
    # as Reiwa 5: `yy` beside an era of a calendar that shows years of an
    # era is the whole year of that era.
    test "a two-digit year of an era" do
      assert Localize.Date.parse("01.04.05 R",
               locale: :de,
               calendar: Japanese,
               reference_date: ~D[2026-06-01]
             ) == {:ok, date(Japanese, 2023, 4, 1)}
    end

    # ICU4C 78.3 reads `am`'s Buddhist short "dd/MM/y GGGGG" "01/04/2566 BE"
    # as 1 April; an available format reads the same digits month first.
    test "a numeric date the standard format writes" do
      assert Localize.Date.parse("01/04/2566 BE",
               locale: :am,
               calendar: Buddhist,
               reference_date: ~D[2026-06-01]
             ) == {:ok, date(Buddhist, 2566, 4, 1)}
    end
  end

  describe "a date-time is read with its calendar's date-time pattern" do
    # CLDR 49 gives `or`'s generic calendar, whose date-time patterns the
    # Buddhist calendar takes, the long at-time pattern "{1} ରେ {0}"; its
    # Gregorian one is "{0} ଠାରେ {1}".
    test "in or" do
      assert Localize.DateTime.parse("ଅପ୍ରେଲ 1, 2566 BE ରେ 10:05:00 AM",
               locale: :or,
               calendar: Buddhist,
               reference_date: ~D[2026-06-01]
             ) == {:ok, datetime(Buddhist, 2566, 4, 1, 10, 5)}
    end
  end

  describe "an interval across a change of era" do
    test "shows each value's era where the locale has an era pattern" do
      assert Localize.Interval.to_string(~D[0000-12-31], ~D[0001-01-01], locale: :en) ==
               {:ok, "Dec 31, 1 BC\u2009–\u2009Jan 1, 1 AD"}

      assert Localize.Interval.to_string(~D[0000-12-31], ~D[0001-01-01],
               locale: :en,
               format: :full
             ) == {:ok, "Sunday, December 31, 1 BC\u2009–\u2009Monday, January 1, 1 AD"}

      assert Localize.Interval.to_string(~D[0000-12-31], ~D[0001-01-01],
               locale: :en,
               fields: :year_and_month
             ) == {:ok, "Dec 1 BC\u2009–\u2009Jan 1 AD"}
    end

    # `es`'s full date matches `yMMMMEd` by width alone, and `es` has no
    # `GyMMMMEd`, so ICU formats both dates in full.
    test "formats both values in full where it has none" do
      assert Localize.Interval.to_string(~D[0000-12-31], ~D[0001-01-01],
               locale: :es,
               format: :full
             ) == {:ok, "domingo, 31 de diciembre de 1\u2009–\u2009lunes, 1 de enero de 1"}
    end

    test "shows no era where the interval shows no year" do
      assert Localize.Interval.to_string(~D[0000-12-31], ~D[0001-01-01],
               locale: :en,
               fields: :month_and_day
             ) == {:ok, "Dec 31\u2009–\u2009Jan 1"}
    end
  end

  # ECMA-402's `formatRange` (V8's, on ICU 77) writes a date shown once in
  # the requested standard format, as `Localize.Date.to_string/2` does.
  # ICU4C agrees for `ko` and `vi`; for `am` it writes "ኤፕሪ 1 2023", from
  # the `availableFormats` entry with the medium format's skeleton.
  describe "a date interval between equal dates" do
    test "shows the date in the requested standard format" do
      for {locale, format, expected} <- [
            {:ko, :medium, "2023. 4. 1."},
            {:vi, :long, "1 tháng 4, 2023"},
            {:am, :medium, "1 ኤፕሪ 2023"}
          ] do
        assert Localize.Interval.to_string(~D[2023-04-01], ~D[2023-04-01],
                 locale: locale,
                 format: format
               ) == {:ok, expected}

        assert Localize.Date.to_string(~D[2023-04-01], locale: locale, format: format) ==
                 {:ok, expected}
      end
    end

    test "in a calendar other than the Gregorian" do
      date = date(Japanese, 2023, 4, 1)

      for format <- [:short, :medium, :long, :full] do
        assert Localize.Interval.to_string(date, date, locale: :en, format: format) ==
                 Localize.Date.to_string(date, locale: :en, format: format)
      end
    end
  end

  describe "endpoints in different calendars" do
    test "are an error" do
      assert {:error, %Localize.DateTimeIntervalFormatError{reason: :mixed_calendars} = error} =
               Localize.Interval.to_string(~D[2023-04-01], date(Japanese, 2023, 4, 10))

      assert Exception.message(error) ==
               "Interval endpoints must be in the same calendar. Found Calendar.ISO and Localize.IntervalCalendarTest.Japanese."

      assert {:error, %Localize.DateTimeIntervalFormatError{reason: :mixed_calendars}} =
               Localize.Interval.to_parts(~D[2023-04-01], date(Japanese, 2023, 4, 10))
    end
  end
end
