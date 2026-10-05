defmodule Localize.DateTime.TimezoneCalendarTest do
  use ExUnit.Case, async: true

  # The tests of every test locale decode each locale's data, which takes a
  # while beside the rest of the suite.
  @moduletag timeout: 300_000

  alias Localize.DateTime.Timezone
  alias Localize.Test.LadyDayCalendar
  alias Localize.Test.ThirteenMonthCalendar

  # A date and time's fields are its calendar's, so the instant they name,
  # and with it the metazone its zone kept at that instant, is found through
  # the calendar. The names expected are CLDR's own
  # `org.unicode.cldr.util.TimezoneFormatter`'s for the instant, run at the
  # pinned commit: Asia/Almaty kept the Kazakhstan_Eastern metazone until
  # 2024-02-29 18:00 UTC and the Kazakhstan one since, and
  # America/Indiana/Knox the America_Eastern one until 2006 and America_Central
  # since (`common/supplemental/metaZones.xml`).
  #
  # Localize cannot load Calendrical's calendars, so each kind is stood in
  # for by a calendar whose fields for a day are not `Calendar.ISO`'s: years
  # counted from another epoch (the Persian, the Buddhist, the Islamic), a
  # year that begins in another month (a fiscal year), a year that turns
  # within a month (the Julian calendars of a reform), and months of another
  # length (the Hebrew, the Chinese, the Korean).

  defmodule ShiftedYears do
    @moduledoc false
    # `Calendar.ISO` with its years counted from 621 years later, as the
    # Persian calendar's are: 2026 is 1405.
    use Localize.Test.StandInCalendar
    @offset 621

    def valid_date?(year, month, day)
        when is_integer(year) and is_integer(month) and is_integer(day),
        do: Calendar.ISO.valid_date?(year + @offset, month, day)

    def valid_date?(_year, _month, _day), do: false

    def days_in_month(year, month), do: Calendar.ISO.days_in_month(year + @offset, month)

    def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
      Calendar.ISO.naive_datetime_to_iso_days(
        year + @offset,
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

      {year - @offset, month, day, hour, minute, second, microsecond}
    end
  end

  defmodule OctoberYears do
    @moduledoc false
    # A fiscal year that begins on 1 October and takes the number of the
    # year it ends in, as the United States' does: its fourth month is
    # January.
    use Localize.Test.StandInCalendar

    def valid_date?(year, month, day)
        when is_integer(year) and month in 1..12 and is_integer(day),
        do: Calendar.ISO.valid_date?(iso_year(year, month), iso_month(month), day)

    def valid_date?(_year, _month, _day), do: false

    def days_in_month(year, month),
      do: Calendar.ISO.days_in_month(iso_year(year, month), iso_month(month))

    def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
      Calendar.ISO.naive_datetime_to_iso_days(
        iso_year(year, month),
        iso_month(month),
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

      if month >= 10,
        do: {year + 1, month - 9, day, hour, minute, second, microsecond},
        else: {year, month + 3, day, hour, minute, second, microsecond}
    end

    defp iso_month(month) when month <= 3, do: month + 9
    defp iso_month(month), do: month - 3

    defp iso_year(year, month) when month <= 3, do: year - 1
    defp iso_year(year, _month), do: year
  end

  @calendars [ShiftedYears, OctoberYears, LadyDayCalendar, ThirteenMonthCalendar]

  defp iso(naive, zone) do
    {:ok, utc} = DateTime.from_naive(naive, "Etc/UTC")
    {:ok, zoned} = DateTime.shift_zone(utc, zone)
    zoned
  end

  defp at(naive, zone, calendar) do
    {:ok, converted} = naive |> iso(zone) |> DateTime.convert(calendar)
    converted
  end

  defp name(datetime, pattern, locale) do
    case Localize.DateTime.to_string(datetime, format: pattern, locale: locale) do
      {:ok, text} -> text
      {:error, exception} -> {:error, exception.__struct__}
    end
  end

  describe "the stand-in calendars" do
    test "name 15 January 2026 with other fields than Calendar.ISO's" do
      fields =
        for calendar <- @calendars do
          datetime = at(~N[2026-01-15 12:00:00], "Etc/UTC", calendar)
          {calendar, {datetime.year, datetime.month, datetime.day}}
        end

      assert {ShiftedYears, {1405, 1, 15}} in fields
      assert {OctoberYears, {2026, 4, 15}} in fields
      assert {LadyDayCalendar, {2025, 1, 15}} in fields
      refute Enum.any?(fields, fn {_calendar, date} -> date == {2026, 1, 15} end)
    end
  end

  describe "a zone's metazone is the one it kept at the instant the fields name" do
    test "in the specific and the generic name of a zone that changed its metazone" do
      for calendar <- @calendars,
          {naive, locale, expected} <- [
            {~N[2023-06-01 12:00:00], :en, "East Kazakhstan Time"},
            {~N[2026-01-15 12:00:00], :en, "Kazakhstan Time"},
            {~N[2026-07-15 12:00:00], :en, "Kazakhstan Time"},
            {~N[2023-06-01 12:00:00], :de, "Ostkasachische Zeit"},
            {~N[2026-01-15 12:00:00], :de, "Kasachische Zeit"}
          ],
          pattern <- ["zzzz", "vvvv"] do
        assert name(at(naive, "Asia/Almaty", calendar), pattern, locale) == expected,
               "#{inspect(calendar)} #{naive} #{locale} #{pattern}"
      end
    end

    test "in the generic name of a zone that changed its metazone and its offset" do
      for calendar <- @calendars,
          {naive, locale, expected} <- [
            {~N[2000-06-01 12:00:00], :en, "Eastern Time (Knox, Indiana)"},
            {~N[2020-06-01 12:00:00], :en, "Central Time (Knox, Indiana)"},
            {~N[2000-06-01 12:00:00], :de, "Nordamerikanische Ostküstenzeit (Knox, Indiana)"},
            {~N[2020-06-01 12:00:00], :de, "Nordamerikanische Zentralzeit (Knox, Indiana)"}
          ] do
        assert name(at(naive, "America/Indiana/Knox", calendar), "vvvv", locale) == expected,
               "#{inspect(calendar)} #{naive} #{locale}"
      end
    end

    # A zone's first metazone period begins with 1970 in UTC where CLDR
    # gives it no beginning, and the instant is the one the fields name in
    # their calendar. The names are ICU4C 78.3's for the instants.
    test "and none before 1970, to the second" do
      for calendar <- [Calendar.ISO | @calendars],
          {naive, zone, pattern, expected} <- [
            {~N[1969-12-31 23:59:59], "America/New_York", "zzzz", "GMT-05:00"},
            {~N[1970-01-01 00:00:00], "America/New_York", "zzzz", "Eastern Standard Time"},
            {~N[1969-12-31 23:59:59], "America/New_York", "vvvv", "New York Time"},
            {~N[1970-01-01 00:00:00], "America/New_York", "vvvv", "Eastern Time"},
            {~N[1965-07-15 12:00:00], "America/New_York", "zzzz", "GMT-04:00"},
            {~N[1969-12-31 23:59:59], "Asia/Tokyo", "zzzz", "GMT+09:00"},
            {~N[1970-01-01 00:00:00], "Asia/Tokyo", "zzzz", "Japan Standard Time"}
          ] do
        assert name(at(naive, zone, calendar), pattern, :en) == expected,
               "#{inspect(calendar)} #{naive} #{zone} #{pattern}"
      end

      for calendar <- @calendars do
        {:ok, before} = NaiveDateTime.convert(~N[1969-12-31 23:59:59], calendar)
        {:ok, since} = NaiveDateTime.convert(~N[1970-01-01 00:00:00], calendar)

        assert Timezone.metazone_for("America/New_York", before) == nil, inspect(calendar)

        assert Timezone.metazone_for("America/New_York", since) == :america_eastern,
               inspect(calendar)
      end
    end

    test "in metazone_for/2, for a date and time with no zone" do
      for calendar <- @calendars do
        {:ok, before} = NaiveDateTime.convert(~N[2000-06-01 00:00:00], calendar)
        {:ok, since} = NaiveDateTime.convert(~N[2020-06-01 00:00:00], calendar)

        assert Timezone.metazone_for("America/Indiana/Knox", before) == :america_eastern,
               inspect(calendar)

        assert Timezone.metazone_for("America/Indiana/Knox", since) == :america_central,
               inspect(calendar)
      end
    end
  end

  # Every test locale: the locales `test/test_helper.exs` lists, the same
  # on every machine (`Localize.Test.InstalledLocales`).
  describe "in every test locale" do
    @moments [
      {~N[2026-01-15 12:00:00], "Asia/Almaty"},
      {~N[2000-06-01 12:00:00], "America/Indiana/Knox"},
      {~N[2026-07-15 12:00:00], "Europe/Berlin"}
    ]

    @patterns ["z", "zzzz", "v", "vvvv", "VVVV"]

    defp written(datetime, locale) do
      time =
        case Localize.Time.to_string(datetime, format: :full, locale: locale) do
          {:ok, text} -> text
          {:error, exception} -> {:error, exception.__struct__}
        end

      Enum.map(@patterns, &name(datetime, &1, locale)) ++ [time]
    end

    test "a date and time in another calendar is named as the same instant in Calendar.ISO" do
      failures =
        for locale <- Localize.Test.InstalledLocales.all(),
            {naive, zone} <- @moments,
            expected = written(iso(naive, zone), locale),
            calendar <- @calendars,
            actual = written(at(naive, zone, calendar), locale),
            actual != expected do
          {locale, zone, calendar, expected, actual}
        end

      assert failures == []
    end

    test "its long specific name is read back in its calendar as in Calendar.ISO" do
      failures =
        for locale <- Localize.Test.InstalledLocales.all(),
            {naive, zone} <- @moments,
            zoned = iso(naive, zone),
            text = name(zoned, "zzzz", locale),
            expected = read(text, DateTime.to_naive(zoned), locale),
            calendar <- @calendars,
            actual = read(text, DateTime.to_naive(at(naive, zone, calendar)), locale),
            actual != expected do
          {locale, zone, calendar, text, expected, actual}
        end

      assert failures == []
    end

    # TR35 writes the localized GMT format in the locale's digits and reads
    # it with "non-Latin numbers", and gives it and the longer ISO 8601
    # fields an optional seconds field: in 1850 Los Angeles kept -7:52:58,
    # Juneau +15:02:19 and N'Djamena +1:00:12. The text is held to the moment
    # it was written from, in the calendar of the date and time read with it.
    test "its offset is read back as the moment it was written from, in its calendar" do
      written =
        for locale <- Localize.Test.InstalledLocales.all(),
            {naive, zone} <- [
              {~N[2026-01-15 12:00:00], "Asia/Kolkata"},
              {~N[2026-01-15 12:00:00], "America/St_Johns"},
              {~N[2026-07-15 12:00:00], "Asia/Kathmandu"},
              {~N[1850-01-15 12:00:00], "America/Los_Angeles"},
              {~N[1850-01-15 12:00:00], "America/Juneau"},
              {~N[1850-01-15 12:00:00], "Africa/Ndjamena"}
            ],
            calendar <- [Calendar.ISO | @calendars],
            datetime = at(naive, zone, calendar),
            pattern <- ["O", "OOOO", "ZZZZ", "Z", "ZZZZZ", "xxxx", "XXXXX"] do
          {locale, calendar, pattern, datetime, name(datetime, pattern, locale)}
        end

      failures =
        for {locale, calendar, pattern, datetime, text} <- written,
            not same_moment?(read_offset(text, datetime, locale), datetime) do
          {locale, calendar, pattern, text}
        end

      assert failures == []

      # Some of the test locales write digits of their own.
      other_digits =
        for {locale, _calendar, _pattern, _datetime, text} <- written,
            is_binary(text) and not String.match?(text, ~r/[0-9]/),
            uniq: true,
            do: locale

      assert Enum.count(other_digits) >= 8
    end

    defp read(text, naive, locale) do
      case Timezone.resolve(text, naive, locale: locale) do
        {:ok, %DateTime{} = datetime} -> {datetime.time_zone, DateTime.to_unix(datetime)}
        {:error, exception} -> {:error, exception.__struct__}
      end
    end

    defp read_offset(text, datetime, locale) when is_binary(text),
      do: Timezone.resolve(text, DateTime.to_naive(datetime), locale: locale)

    defp read_offset(unwritten, _datetime, _locale), do: unwritten

    defp same_moment?({:ok, %DateTime{} = read}, datetime) do
      read.calendar == datetime.calendar and DateTime.compare(read, datetime) == :eq and
        DateTime.to_naive(read) == DateTime.to_naive(datetime)
    end

    defp same_moment?(_unread, _datetime), do: false
  end

  describe "a calendar that does not answer" do
    defmodule NoCalendar do
      @moduledoc false
    end

    test "leaves the zone's current metazone, and nothing is raised" do
      for calendar <- [NoCalendar, :no_such_module, "Persian", nil, 42] do
        value = %{
          calendar: calendar,
          year: 1405,
          month: 1,
          day: 15,
          hour: 12,
          minute: 0,
          second: 0,
          time_zone: "Asia/Almaty",
          utc_offset: 18_000,
          std_offset: 0
        }

        assert Timezone.metazone_for("Asia/Almaty", value) == :kazakhstan, inspect(calendar)

        assert Timezone.non_location_format(value, :en) == {:ok, "Kazakhstan Time"},
               inspect(calendar)
      end
    end
  end
end
