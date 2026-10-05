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
  @narrow <<0x202F::utf8>>

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

  # How Calendrical's calendars of weeks write their dates and read them
  # back: as ISO 8601 writes a week date, "2026-W25-2", and, as Calendrical
  # reads them, any "2024-02-01" as the year, week and day it holds.
  defmodule WeekNotation do
    @moduledoc false

    def write(year, week, day), do: "#{pad(year, 4)}-W#{pad(week, 2)}-#{pad(day, 1)}"

    def read(text, calendar) do
      with [_text, year, week, day] <- Regex.run(~r/\A(\d{4})-W?(\d{2})-(\d{1,2})\z/, text),
           {year, week, day} =
             {String.to_integer(year), String.to_integer(week), String.to_integer(day)},
           true <- calendar.valid_date?(year, week, day) do
        {:ok, {year, week, day}}
      else
        _not_a_date -> {:error, :invalid_date}
      end
    end

    defp pad(value, digits), do: String.pad_leading(Integer.to_string(value), digits, "0")
  end

  # The ISO week calendar: a date is its year, its week and its day of the
  # week, and its month the 4-4-5 month of the quarter its week falls in.
  # Its months have no names, so they take CLDR's generic calendar's, "M01"
  # to "M12", and its eras the Gregorian calendar's, as Calendrical's
  # calendars of weeks answer.
  defmodule IsoWeek do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :generic
    def era_calendar_type, do: :gregorian
    def date_to_string(year, week, day), do: WeekNotation.write(year, week, day)
    def parse_date(text), do: WeekNotation.read(text, __MODULE__)

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

    # Its month field holds a week, of seven days, as Calendrical's
    # calendars of weeks count it.
    def days_in_month(_year, _week), do: 7
    def year_of_era(year, _week, _day), do: {year, 1}
    def calendar_year(year, _week, _day), do: year

    # A written month and day name no single week, so a date is read as a
    # Gregorian one and converted, as Calendrical's week calendars say.
    def parsing_calendar, do: Calendar.ISO

    # Its own weeks are its dates' week fields, and its quarters thirteen of
    # them each, a 53rd week in the last.
    def week_of_year(year, week, _day), do: {year, week}
    def quarter_of_year(_year, week, _day), do: min(div(week - 1, 13) + 1, 4)

    # Its weeks of the month are its 4-4-5 month's weeks, counted from the
    # month's first.
    def week_of_month(year, week, day) do
      month = month_of_year(year, week, day)
      first_week = div(month - 1, 3) * 13 + rem(month - 1, 3) * 4 + 1
      {month, week - first_week + 1}
    end

    def quarter(year, quarter) do
      {_year, last_week} = :calendar.iso_week_number({year, 12, 28})
      last = if quarter == 4, do: last_week, else: quarter * 13

      Date.range(
        %Date{year: year, month: (quarter - 1) * 13 + 1, day: 1, calendar: __MODULE__},
        %Date{year: year, month: last, day: 7, calendar: __MODULE__}
      )
    end

    def valid_date?(_year, week, day), do: week in 1..53 and day in 1..7

    def day_of_week(year, week, day, starting_on) do
      {days, _fraction} = naive_datetime_to_iso_days(year, week, day, 0, 0, 0, {0, 0})
      {iso_year, iso_month, iso_day} = Calendar.ISO.date_from_iso_days(days)
      Calendar.ISO.day_of_week(iso_year, iso_month, iso_day, starting_on)
    end

    # ISO 8601's week date: week 1 is the week holding 4 January, and its
    # days count from Monday.
    def naive_datetime_to_iso_days(year, week, day, hour, minute, second, microsecond) do
      {january_4, _fraction} =
        Calendar.ISO.naive_datetime_to_iso_days(year, 1, 4, 0, 0, 0, {0, 0})

      {weekday, _first, _last} = Calendar.ISO.day_of_week(year, 1, 4, :monday)
      days = january_4 - (weekday - 1) + (week - 1) * 7 + (day - 1)
      {days, Calendar.ISO.time_to_day_fraction(hour, minute, second, microsecond)}
    end

    def naive_datetime_from_iso_days({days, fraction}) do
      {year, month, day} = Calendar.ISO.date_from_iso_days(days)
      {week_year, week} = :calendar.iso_week_number({year, month, day})
      {weekday, _first, _last} = Calendar.ISO.day_of_week(year, month, day, :monday)
      {hour, minute, second, microsecond} = Calendar.ISO.time_from_day_fraction(fraction)
      {week_year, week, weekday, hour, minute, second, microsecond}
    end
  end

  # A calendar numbering its weeks as Calendrical's Gregorian calendar does:
  # they begin on Monday and week 1 is the one holding 1 January, so 2027's
  # week 1 begins on 28 December 2026, as Tempo's `2027Y1w` does.
  defmodule JanuaryWeeks do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def week_of_year(year, month, day) do
      date = Date.new!(year, month, day)

      if Date.compare(date, week_one(year + 1)) == :lt,
        do: {year, div(Date.diff(date, week_one(year)), 7) + 1},
        else: {year + 1, 1}
    end

    def week(year, week) do
      first = Date.add(week_one(year), (week - 1) * 7)
      Date.range(Date.convert!(first, __MODULE__), Date.convert!(Date.add(first, 6), __MODULE__))
    end

    # Its weeks of the month likewise: week 1 is the Monday week holding the
    # first of the month.
    def week_of_month(year, month, day) do
      {first_weekday, _first, _last} = Calendar.ISO.day_of_week(year, month, 1, :monday)
      {month, div(day - 1 + first_weekday - 1, 7) + 1}
    end

    # The Monday on or before 1 January.
    defp week_one(year) do
      january_1 = Date.new!(year, 1, 1)
      Date.add(january_1, 1 - Date.day_of_week(january_1))
    end
  end

  # A calendar of weeks whose weeks begin on Sunday, as the NRF retail
  # calendar's do: a date is its year, its week and its day, Sunday 1, and
  # week 1 is the Sunday week holding 1 January. It reads its written dates
  # as Gregorian ones.
  defmodule SundayWeeks do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :generic
    def era_calendar_type, do: :gregorian
    def date_to_string(year, week, day), do: WeekNotation.write(year, week, day)
    def parse_date(text), do: WeekNotation.read(text, __MODULE__)
    def parsing_calendar, do: Calendar.ISO
    def valid_date?(_year, week, day), do: week in 1..53 and day in 1..7
    def week_of_year(year, week, _day), do: {year, week}

    def week(year, week) do
      first = %Date{year: year, month: week, day: 1, calendar: __MODULE__}
      Date.range(first, %{first | day: 7})
    end

    def naive_datetime_to_iso_days(year, week, day, hour, minute, second, microsecond) do
      {start, _fraction} = week_one(year)

      {start + (week - 1) * 7 + day - 1,
       Calendar.ISO.time_to_day_fraction(hour, minute, second, microsecond)}
    end

    def naive_datetime_from_iso_days({days, fraction}) do
      {year, _month, _day} = Calendar.ISO.date_from_iso_days(days + 7)
      year = if days >= elem(week_one(year), 0), do: year, else: year - 1
      {start, _fraction} = week_one(year)
      {hour, minute, second, microsecond} = Calendar.ISO.time_from_day_fraction(fraction)

      {year, div(days - start, 7) + 1, rem(days - start, 7) + 1, hour, minute, second,
       microsecond}
    end

    def day_of_week(year, week, day, starting_on) do
      {days, _fraction} = naive_datetime_to_iso_days(year, week, day, 0, 0, 0, {0, 0})
      {iso_year, iso_month, iso_day} = Calendar.ISO.date_from_iso_days(days)
      Calendar.ISO.day_of_week(iso_year, iso_month, iso_day, starting_on)
    end

    # The ISO day count of the Sunday on or before 1 January.
    defp week_one(year) do
      {january_1, fraction} = Calendar.ISO.naive_datetime_to_iso_days(year, 1, 1, 0, 0, 0, {0, 0})
      {weekday, _first, _last} = Calendar.ISO.day_of_week(year, 1, 1, :sunday)
      {january_1 - (weekday - 1), fraction}
    end
  end

  # A calendar of weeks that names a year and its era only for a whole date,
  # and counts more days in a week than the week has, 28 where it has seven,
  # as a calendar counts a month a reform took days out of (December 1582
  # in Belgium, 21 days, has no 21st).
  defmodule WholeDateWeeks do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def parsing_calendar, do: Calendar.ISO
    def days_in_month(_year, _period), do: 28

    def year_of_era(_year, week, day) when is_nil(week) or is_nil(day),
      do: {:error, :missing_fields}

    def year_of_era(year, _week, _day), do: {year, 1}

    def calendar_year(_year, week, day) when is_nil(week) or is_nil(day),
      do: {:error, :missing_fields}

    def calendar_year(year, _week, _day), do: year

    def year(year) do
      Date.range(
        %Date{year: year, month: 1, day: 1, calendar: __MODULE__},
        %Date{year: year, month: 52, day: 7, calendar: __MODULE__}
      )
    end

    defdelegate valid_date?(year, week, day), to: SundayWeeks
    defdelegate day_of_week(year, week, day, starting_on), to: SundayWeeks

    defdelegate naive_datetime_to_iso_days(year, week, day, hour, minute, second, microsecond),
      to: SundayWeeks

    defdelegate naive_datetime_from_iso_days(iso_days), to: SundayWeeks
  end

  # A calendar of months whose weeks begin on Sunday: its `day_of_week/4`
  # counts from Sunday by default, as a calendar made for a locale whose
  # weeks begin on Sunday does.
  defmodule SundayFirst do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def day_of_week(year, month, day, :default),
      do: Calendar.ISO.day_of_week(year, month, day, :sunday)

    def day_of_week(year, month, day, starting_on),
      do: Calendar.ISO.day_of_week(year, month, day, starting_on)
  end

  # A calendar of thirteen months, twelve of 30 days and a thirteenth of 5,
  # as the Coptic and Ethiopic calendars are: its quarters are three months
  # each but the last, which holds the thirteenth too.
  defmodule ThirteenMonths do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def months_in_year(_year), do: 13
    def days_in_month(_year, 13), do: 5
    def days_in_month(_year, _month), do: 30
    def valid_date?(_year, month, day), do: month in 1..13 and day in 1..days_in_month(1, month)
    def quarter_of_year(_year, month, _day), do: min(div(month - 1, 3) + 1, 4)
  end

  # A calendar of months whose years are numbered one ahead of the
  # Gregorian calendar's, so a date converted into it is plainly converted.
  defmodule YearAhead do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
      Calendar.ISO.naive_datetime_to_iso_days(
        year - 1,
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

      {year + 1, month, day, hour, minute, second, microsecond}
    end
  end

  # A calendar answering Localize's questions with things that are not
  # answers.
  defmodule Misanswering do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def calendar_year(_year, _month, _day), do: :no_year
    def extended_year(_year, _month, _day), do: :no_year
    def related_gregorian_year(_year, _month, _day), do: :no_year
    def cyclic_year(_year, _month, _day), do: :no_year
    def week_of_year(_year, _month, _day), do: :no_week
    def day_of_year(_year, _month, _day), do: :no_day
    def day_of_week(_year, _month, _day, _starting_on), do: :no_day
    def quarter_of_year(_year, _month, _day), do: :no_quarter
    def week_of_month(_year, _month, _day), do: :no_week
    def year(_year), do: :no_days
    def diff(_from, _to, _date_part), do: :no_count
  end

  # A calendar that counts the months between two dates but cannot say what
  # date a number of months on is.
  defmodule Misadding do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def diff(_from, _to, _date_part), do: 1
    def plus(_year, _month, _day, _date_part, _increment, _options), do: :no_date
  end

  # A calendar that counts the days and periods between two dates but cannot
  # say what date a span of years and months on is: its `shift_date/4`,
  # which a duration is measured by.
  defmodule Misshifting do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def shift_date(_year, _month, _day, _duration), do: :no_date
    def diff(from, to, date_part), do: Localize.Calendar.ISO.diff(from, to, date_part)
  end

  # A calendar whose shifting does not move on: a year or a month on from a
  # date is the date itself.
  defmodule Stuck do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def shift_date(year, month, day, _duration), do: {year, month, day}
    def diff(from, to, date_part), do: Localize.Calendar.ISO.diff(from, to, date_part)
  end

  # A calendar that cannot say which month of its year a date is in.
  defmodule Monthless do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def month_of_year(_year, _month, _day), do: :no_month
  end

  # A calendar answering every question but `parsing_calendar/0`, as a
  # Calendrical calendar before 1.4 does.
  defmodule Unparsing do
    @moduledoc false
    use Localize.Test.StandInCalendar, without: [parsing_calendar: 0]
  end

  # A calendar answering every question but its extended year, which `u`
  # writes.
  defmodule Unextended do
    @moduledoc false
    use Localize.Test.StandInCalendar, without: [extended_year: 3]
  end

  # Calendars answering every question but one of those Localize puts for a
  # year's days and for the months between two dates.
  defmodule Yearless do
    @moduledoc false
    use Localize.Test.StandInCalendar, without: [year: 1]
  end

  defmodule Uncounting do
    @moduledoc false
    use Localize.Test.StandInCalendar, without: [diff: 3]
  end

  defmodule Unadding do
    @moduledoc false
    use Localize.Test.StandInCalendar, without: [plus: 6]
  end

  # A calendar answering the questions Localize puts to a Calendrical
  # calendar, but without the `Calendar` behaviour they extend.
  defmodule Unconvertible do
    @moduledoc false

    def cldr_calendar_type, do: :gregorian
    def era_calendar_type, do: :gregorian
    def parsing_calendar, do: __MODULE__
    def month_of_year(_year, month, _day), do: month
    def cardinal_month(month), do: month
    def calendar_year(year, _month, _day), do: year
    def related_gregorian_year(year, _month, _day), do: year
    def cyclic_year(year, _month, _day), do: year
    def week_of_year(year, month, day), do: :calendar.iso_week_number({year, month, day})
    def week(year, week), do: Localize.Calendar.ISO.week(year, week)
    def week_of_month(year, month, day), do: Localize.Calendar.ISO.week_of_month(year, month, day)
    def quarter(year, quarter), do: Localize.Calendar.ISO.quarter(year, quarter)
    def year(year), do: Localize.Calendar.ISO.year(year)
    def diff(from, to, date_part), do: Localize.Calendar.ISO.diff(from, to, date_part)

    def plus(year, month, day, date_part, increment, options),
      do: Localize.Calendar.ISO.plus(year, month, day, date_part, increment, options)
  end

  # A complete calendar of Elixir's `Calendar` behaviour alone, every
  # callback `Calendar.ISO`'s, which cannot say what its months are named:
  # Localize refuses it wherever a value in it enters (user, 2026-10-01).
  defmodule Unanswered do
    @moduledoc false
    @behaviour Calendar

    for {name, arity} <- Calendar.behaviour_info(:callbacks) do
      arguments = Macro.generate_arguments(arity, __MODULE__)

      @impl true
      def unquote(name)(unquote_splicing(arguments)),
        do: Calendar.ISO.unquote(name)(unquote_splicing(arguments))
    end
  end

  defp date(year, month, day, calendar),
    do: %{year: year, month: month, day: day, calendar: calendar}

  # A date's day at a time, in the date's calendar.
  defp at(%Date{} = date, hour, minute) do
    %NaiveDateTime{
      year: date.year,
      month: date.month,
      day: date.day,
      hour: hour,
      minute: minute,
      second: 0,
      microsecond: {0, 0},
      calendar: date.calendar
    }
  end

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

    # Two months with no year are an interval of them, in CLDR's `MMM`
    # interval format, "MMM – MMM", and two days of one month in its `MMMd`,
    # "MMM d – d", each month named as the calendar names it.
    test "names the months of an interval without a year" do
      assert Localize.Interval.to_string(
               %{month: 1, calendar: FiscalJuly},
               %{month: 3, calendar: FiscalJuly},
               locale: :en
             ) == {:ok, "Jul#{@thin}–#{@thin}Sep"}

      assert Localize.Interval.to_string(
               %{month: 12, day: 15, calendar: FiscalJuly},
               %{month: 12, day: 20, calendar: FiscalJuly},
               locale: :en
             ) == {:ok, "Jun 15#{@thin}–#{@thin}20"}
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

  # A calendar of weeks writes a date in its own notation, as it was given
  # (user, 2026-10-02): ISO 8601's week date, "2026-W25-2" for Tuesday 16 June
  # 2026 (`:calendar.iso_week_number/1`), at every standard format and in
  # every locale, which reads back as itself. A date and time joins it to the
  # locale's time with the locale's date-time pattern, and an interval joins
  # two with the locale's fallback pattern ("{0} – {1}" in `en`). A pattern
  # takes the calendar's answers: CLDR root's generic calendar names its
  # months, "M06" and narrow "6", and its weeks, quarters and days are its
  # own, the days named as the Gregorian calendar names them.
  describe "an ISO week calendar" do
    test "writes a date in its own notation at every standard format" do
      for format <- [nil, :short, :medium, :long, :full], locale <- [:en, :de, :ja, :ar] do
        options = if format, do: [format: format, locale: locale], else: [locale: locale]

        assert Localize.Date.to_string(date(2026, 25, 2, IsoWeek), options) ==
                 {:ok, "2026-W25-2"},
               inspect(options)
      end

      assert Localize.Date.to_string(date(2026, 53, 7, IsoWeek), format: :full, locale: :en) ==
               {:ok, "2026-W53-7"}

      assert Localize.Date.to_parts(date(2026, 25, 2, IsoWeek), locale: :en) ==
               {:ok, [%{type: :literal, value: "2026-W25-2"}]}
    end

    test "reads its notation back as itself" do
      for {week, day} <- [{25, 2}, {1, 1}, {53, 7}] do
        value = %Date{year: 2026, month: week, day: day, calendar: IsoWeek}
        {:ok, text} = Localize.Date.to_string(value, locale: :en)

        assert Localize.Date.parse(text, locale: :en, calendar: IsoWeek) == {:ok, value}

        # A standard format writes the notation, so the notation is what a
        # date written with one reads as.
        for format <- [:short, :medium, :long, :full] do
          assert Localize.Date.parse(text, locale: :en, calendar: IsoWeek, format: format) ==
                   {:ok, value}
        end
      end

      assert {:error, %Localize.DateParseError{}} =
               Localize.Date.parse("2026-W2a-1", locale: :en, calendar: IsoWeek)
    end

    test "writes a date and time as its date's notation and the locale's time" do
      value = %NaiveDateTime{
        year: 2026,
        month: 25,
        day: 2,
        hour: 10,
        minute: 30,
        second: 0,
        microsecond: {0, 0},
        calendar: IsoWeek
      }

      assert Localize.DateTime.to_string(value, locale: :en) ==
               {:ok, "2026-W25-2, 10:30:00#{@narrow}AM"}

      assert Localize.DateTime.to_string(value, format: :short, locale: :en) ==
               {:ok, "2026-W25-2, 10:30#{@narrow}AM"}

      assert Localize.DateTime.to_string(value, locale: :de) == {:ok, "2026-W25-2, 10:30:00"}

      assert Localize.DateTime.parse("2026-W25-2, 10:30:00 AM", locale: :en, calendar: IsoWeek) ==
               {:ok, value}

      # A semantic skeleton whose date resolves to a standard format writes
      # that format, the notation; MessageFormat 2 gives the time to the
      # minute, as TR35 specifies.
      semantic = Localize.DateTime.SemanticSkeleton.semantic("YMD")

      assert Localize.DateTime.to_string(value, format: semantic, locale: :en) ==
               {:ok, "2026-W25-2"}

      assert Localize.Message.format("{$d :date}", %{d: value}, locale: :en) ==
               {:ok, "2026-W25-2"}

      assert Localize.Message.format("{$d :datetime}", %{d: value}, locale: :en) ==
               {:ok, "2026-W25-2, 10:30#{@narrow}AM"}
    end

    test "writes an interval as its notations around the fallback pattern" do
      from = %Date{year: 2026, month: 25, day: 2, calendar: IsoWeek}
      to = %Date{year: 2026, month: 27, day: 1, calendar: IsoWeek}
      written = "2026-W25-2#{@thin}–#{@thin}2026-W27-1"

      assert Localize.Interval.to_string(from, to, locale: :en) == {:ok, written}
      assert Localize.Interval.to_string(from, to, format: :long, locale: :en) == {:ok, written}
      assert Localize.Interval.to_string(from, from, locale: :en) == {:ok, "2026-W25-2"}

      assert Localize.Interval.parse(written, locale: :en, calendar: IsoWeek) ==
               {:ok, Date.range(from, to)}

      morning = at(from, 10, 30)
      afternoon = at(from, 14, 0)
      later = at(to, 14, 0)

      assert Localize.Interval.to_string(morning, afternoon, locale: :en) ==
               {:ok, "2026-W25-2, 10:30:00#{@narrow}AM#{@thin}–#{@thin}2:00:00#{@narrow}PM"}

      assert Localize.Interval.to_string(morning, later, locale: :en) ==
               {:ok,
                "2026-W25-2, 10:30:00#{@narrow}AM#{@thin}–#{@thin}2026-W27-1, 2:00:00#{@narrow}PM"}
    end

    # The fallback pattern joins the two notations, and a locale's may join
    # them with a hyphen, which the notation is written with: `da.xml`'s
    # generic `intervalFormatFallback` is "{0}-{1}" and `el.xml`'s
    # "{0} - {1}". The text was cut at the first hyphen, after "2026". A
    # calendar of weeks is written with CLDR's generic calendar's patterns
    # and read as a Gregorian one, so the pattern looked for was the
    # Gregorian calendar's, "{0} – {1}" in `fr-CH`, where the generic
    # calendar's is "du {0} au {1}".
    test "reads an interval back whatever the locale's fallback pattern joins it with" do
      from = %Date{year: 2026, month: 25, day: 2, calendar: IsoWeek}
      to = %Date{year: 2026, month: 27, day: 1, calendar: IsoWeek}

      for {locale, written} <- [
            {:da, "2026-W25-2-2026-W27-1"},
            {:el, "2026-W25-2 - 2026-W27-1"},
            {:"fr-CH", "du 2026-W25-2 au 2026-W27-1"}
          ] do
        assert Localize.Interval.to_string(from, to, locale: locale) == {:ok, written}

        assert Localize.Interval.parse(written, locale: locale, calendar: IsoWeek) ==
                 {:ok, Date.range(from, to)},
               "#{locale} #{inspect(written)}"
      end
    end

    test "writes a pattern with the calendar's answers" do
      value = date(2026, 25, 2, IsoWeek)

      for {pattern, expected} <- [
            {"MMM", "M06"},
            {"MMMM", "M06"},
            {"LLLL", "M06"},
            {"MMMMM", "6"},
            {"LLLLL", "6"},
            {"M", "6"},
            {"MM", "06"},
            {"Y", "2026"},
            {"ww", "25"},
            {"QQQ", "Q2"},
            {"EEEE", "Tuesday"},
            {"G", "AD"}
          ] do
        assert Localize.Date.to_string(value, format: pattern, locale: :en) == {:ok, expected},
               pattern
      end
    end

    # A year alone, or a year and a week, is asked of the calendar with the
    # fields it has, and a calendar of weeks names its year and era from the
    # year, so both are written without asking which days a week could be
    # (found through Tempo, 2026-10-02).
    test "writes a year alone, and a year and a week" do
      for value <- [
            %{year: 2026, calendar: IsoWeek},
            %{year: 2026, month: 25, calendar: IsoWeek},
            %{year: 2026, month: 53, calendar: IsoWeek}
          ] do
        assert Localize.Date.to_string(value, format: "y", locale: :en) == {:ok, "2026"}
        assert Localize.Date.to_string(value, format: "G y", locale: :en) == {:ok, "AD 2026"}
        assert Localize.Calendar.localize(value, :era, locale: :en) == {:ok, "Anno Domini"}
      end
    end

    # A calendar of weeks holds a week in its dates' month field, so a year
    # and a week is written as the locale writes a week of the year, CLDR's
    # `yw`: "'week' w 'of' Y" in `en`, "'Woche' w 'des' 'Jahres' Y" in `de`
    # and "'semaine' w 'de' Y" in `fr`. Formatting is Localize's, so the
    # calendar is asked only for the week its days are in (user,
    # 2026-10-04). A whole date keeps the calendar's notation, and a
    # skeleton that is asked for is used as it is given.
    test "writes a year and a week as the locale writes a week of the year" do
      week = %{year: 2026, month: 25, calendar: IsoWeek}

      for options <- [[], [format: :short], [format: :medium], [format: :long], [format: :full]] do
        assert Localize.Date.to_string(week, [locale: :en] ++ options) ==
                 {:ok, "week 25 of 2026"},
               inspect(options)
      end

      assert Localize.Date.to_string(week, locale: :de) == {:ok, "Woche 25 des Jahres 2026"}
      assert Localize.Date.to_string(week, locale: :fr) == {:ok, "semaine 25 de 2026"}
      assert Localize.Date.to_string(week, locale: :en, format: :yM) == {:ok, "6/2026 AD"}

      assert Localize.Date.to_string(Map.put(week, :day, 2), locale: :en) ==
               {:ok, "2026-W25-2"}

      assert {:ok, parts} = Localize.Date.to_parts(week, locale: :en)

      assert Enum.reject(parts, &(&1.type == :literal)) == [
               %{type: :week_of_year, value: "25"},
               %{type: :year, value: "2026"}
             ]
    end

    test "writes two weeks as an interval of them" do
      week = %{year: 2026, month: 25, calendar: IsoWeek}

      assert Localize.Interval.to_string(week, %{week | month: 26}, locale: :en) ==
               {:ok, "week 25 of 2026 – week 26 of 2026"}
    end

    # A calendar of weeks holds a week in its month field. A format of weeks
    # compares the weeks it writes, so two are both written, and one that
    # writes the period (`M`) compares the periods: weeks 25 and 26 are both
    # in the sixth, which is written once, and week 31 is in the eighth
    # (TR35's step 4: one date where no field of the pattern differs).
    test "writes two weeks with a week format, and one period for two of its weeks" do
      from = date(2026, 25, 2, IsoWeek)
      to = date(2026, 26, 1, IsoWeek)

      assert Localize.Interval.to_string(from, to, locale: :en, format: :yw) ==
               {:ok, "week 25 of 2026#{@thin}–#{@thin}week 26 of 2026"}

      assert Localize.Interval.to_string(from, date(2026, 25, 5, IsoWeek),
               locale: :en,
               format: :yw
             ) == {:ok, "week 25 of 2026"}

      assert Localize.Interval.to_string(from, to, locale: :en, format: "Y-'W'ww") ==
               {:ok, "2026-W25#{@thin}–#{@thin}2026-W26"}

      assert Localize.Interval.to_string(from, to, locale: :en, format: :yM) ==
               {:ok, "6/2026 AD"}

      assert Localize.Interval.to_string(from, date(2026, 31, 1, IsoWeek),
               locale: :en,
               format: :yM
             ) == {:ok, "6/2026#{@thin}–#{@thin}8/2026 AD"}
    end

    # A week without its year has no week of the year, and says so.
    test "asks for the year of a week alone" do
      assert {:error, %Localize.DateTimeInvalidInputError{missing: [:year]}} =
               Localize.Date.to_string(%{month: 25, calendar: IsoWeek}, locale: :en)
    end

    # The calendar writes its notation from three integers, and raises on
    # anything else, as Calendrical's calendars of weeks do. A date with a
    # field that is no integer is not put to it: the error names the field.
    test "names the field of a date that is not an integer, whole or not" do
      whole = %{year: 2026, month: 25, day: 2, calendar: IsoWeek}

      for {field, value} <- [day: nil, month: nil, year: nil, day: "2", month: 25.0] do
        assert {:error, %Localize.DateTimeInvalidInputError{invalid: invalid}} =
                 Localize.Date.to_string(Map.put(whole, field, value), locale: :en),
               inspect({field, value})

        assert field in invalid, inspect({field, value, invalid})
      end

      for {field, value} <- [month: nil, year: nil, month: "25"] do
        assert {:error, %Localize.DateTimeInvalidInputError{invalid: invalid}} =
                 Localize.Date.to_string(Map.put(Map.delete(whole, :day), field, value),
                   locale: :en
                 ),
               inspect({field, value})

        assert field in invalid, inspect({field, value, invalid})
      end
    end

    # A calendar of weeks that answers only for a whole date is asked about
    # the first and the last day its week, or its year, could be: the last
    # is the last day the calendar has there at or below its count, the
    # seventh where its `days_in_month/2` counts 28.
    test "is asked about a week's own days where it needs the whole date" do
      for value <- [
            %{year: 2026, calendar: WholeDateWeeks},
            %{year: 2026, month: 25, calendar: WholeDateWeeks}
          ] do
        assert Localize.Date.to_string(value, format: "G y", locale: :en) == {:ok, "AD 2026"}
        assert Localize.Calendar.year_of_era(value) == {:ok, {2026, 1}}
      end
    end

    # A calendar of weeks beginning on Sunday numbers Tuesday 3, where ISO
    # 8601 numbers it 2, so its notation reads back only as its own.
    test "reads back a notation counting its own days of the week" do
      value = %Date{year: 2026, month: 25, day: 3, calendar: SundayWeeks}

      assert Localize.Date.to_string(value, locale: :en) == {:ok, "2026-W25-3"}
      assert Localize.Date.parse("2026-W25-3", locale: :en, calendar: SundayWeeks) == {:ok, value}
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
      assert Localize.Duration.new(value, value) == unknown
      assert Localize.Time.to_string(time, locale: :en) == unknown
      assert Localize.Time.to_parts(time, locale: :en) == unknown
      assert Localize.Date.parse("Jan 1, 2026", locale: :en, calendar: Unanswered) == unknown

      assert Localize.DateTime.parse("Jan 1, 2026, 10:00 AM", locale: :en, calendar: Unanswered) ==
               unknown

      assert Localize.Interval.parse("Jan 1 – 4, 2026", locale: :en, calendar: Unanswered) ==
               unknown

      assert {:error, %Localize.FormatError{cause: %Localize.UnknownCalendarError{}}} =
               Localize.Message.format("{$d :date}", %{"d" => value}, locale: :en)
    end

    test "a calendar without the Calendar behaviour is refused too" do
      unknown = {:error, Localize.UnknownCalendarError.exception(calendar: Unconvertible)}
      value = %Date{year: 2026, month: 1, day: 1, calendar: Unconvertible}

      assert Localize.Date.to_string(value, locale: :en) == unknown
      assert Localize.Date.parse("Jan 1, 2026", locale: :en, calendar: Unconvertible) == unknown
      assert Localize.DateTime.Relative.to_string(value, relative_to: ~D[2026-02-01]) == unknown
    end

    # Formatting asks no parsing calendar, but a calendar is checked for
    # every answer wherever it enters, so one Calendrical release is a
    # calendar's or not.
    test "a calendar without parsing_calendar/0 is refused, in formatting too" do
      unknown = {:error, Localize.UnknownCalendarError.exception(calendar: Unparsing)}
      value = %Date{year: 2026, month: 1, day: 1, calendar: Unparsing}

      assert Localize.Date.to_string(value, locale: :en) == unknown
      assert Localize.Date.parse("Jan 1, 2026", locale: :en, calendar: Unparsing) == unknown
    end

    # A year's days and the months between two dates are the calendar's to
    # give, its `year/1`, `diff/3` and `plus/6`, and so is the extended year
    # `u` writes, its `extended_year/3`, so a calendar without one of them is
    # refused as one without any other answer is.
    test "a calendar that cannot give a year's days, count its months or extend its year is refused" do
      for calendar <- [Yearless, Uncounting, Unadding, Unextended] do
        unknown = {:error, Localize.UnknownCalendarError.exception(calendar: calendar)}
        value = %Date{year: 2026, month: 1, day: 1, calendar: calendar}

        assert Localize.Date.to_string(value, locale: :en) == unknown
        assert Localize.Date.parse("Jan 1, 2026", locale: :en, calendar: calendar) == unknown
        assert Localize.DateTime.Relative.to_string(value, relative_to: value) == unknown
      end
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
            {"u", :no_year},
            {"r", :no_year},
            {"U", :no_year},
            {"Y", :no_week},
            {"w", :no_week},
            {"D", :no_day},
            {"E", :no_day},
            {"e", :no_day},
            {"c", :no_day},
            {"Q", :no_quarter},
            {"W", :no_week},
            {"QQQ", :no_quarter}
          ] do
        assert {:error, %Localize.InvalidValueError{value: ^answer}} =
                 Localize.Date.to_string(value, format: format, locale: :en),
               format
      end
    end

    # A year alone could be any of its days. Where the calendar does not name
    # the year from the year alone, it gives the year's days (its `year/1`)
    # so that the year they share can be written.
    test "is an error where a year's days are asked for" do
      assert {:error, %Localize.InvalidValueError{value: :no_days}} =
               Localize.Calendar.displayed_year(%{year: 2026, calendar: Misanswering})

      assert {:error, %Localize.InvalidValueError{value: :no_days}} =
               Localize.Date.to_string(%{year: 2026, calendar: Misanswering},
                 format: "y",
                 locale: :en
               )
    end

    # The years, quarters and months between two dates are the calendar's
    # count (its `diff/3`), set against the date that many on (its `plus/6`)
    # in relative time, and against the date its own shifting reaches (its
    # `shift_date/4`) in a duration.
    test "is an error where the periods between two dates are counted" do
      for {calendar, answer} <- [{Misanswering, :no_count}, {Misadding, :no_date}] do
        from = %Date{year: 2026, month: 1, day: 31, calendar: calendar}
        to = %Date{year: 2026, month: 3, day: 1, calendar: calendar}

        for unit <- [:year, :quarter, :month] do
          assert {:error, %Localize.InvalidValueError{value: ^answer}} =
                   Localize.DateTime.Relative.to_string(to, relative_to: from, unit: unit),
                 "#{inspect(calendar)} in #{unit}"
        end
      end

      for {calendar, answer} <- [{Misanswering, :no_count}, {Misshifting, :no_date}] do
        from = %Date{year: 2026, month: 1, day: 31, calendar: calendar}
        to = %Date{year: 2026, month: 3, day: 1, calendar: calendar}

        assert {:error, %Localize.InvalidValueError{value: ^answer}} =
                 Localize.Duration.new(from, to),
               inspect(calendar)
      end
    end

    # A year or a month is more than a day, so a count of them that reaches
    # the days between two dates is that of a calendar whose shifting does
    # not move on: an error, where it would be counted without end.
    test "a calendar whose shifting does not move on is an error" do
      from = %Date{year: 2026, month: 1, day: 31, calendar: Stuck}
      to = %Date{year: 2026, month: 3, day: 1, calendar: Stuck}

      assert {:error, %Localize.InvalidValueError{}} = Localize.Duration.new(from, to)
      assert {:ok, %{year: 0, month: 0, day: 0}} = Localize.Duration.new(from, from)
    end

    # A month is known by the calendar's `month_of_year/3`, which the months
    # between two dates are counted to.
    test "is an error where a date's month of the year is asked for" do
      from = %Date{year: 2026, month: 1, day: 31, calendar: Monthless}
      to = %Date{year: 2026, month: 3, day: 1, calendar: Monthless}

      assert {:error, %Localize.InvalidValueError{value: :no_month}} =
               Localize.DateTime.Relative.to_string(to, relative_to: from, unit: :month)
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
      assert iso.week_of_year(2027, 1, 1) == {2026, 53}
      assert iso.year_of_era(-44, 3, 15) == Calendar.ISO.year_of_era(-44, 3, 15)
    end
  end

  describe "a date written for an ISO week calendar" do
    # A written month and day name no single week, so the calendar reads
    # its dates as Gregorian ones (`parsing_calendar/0`) and they are
    # converted: 1 February 2024 is the Thursday of ISO week 5, and
    # 5 February the Monday of week 6 (`:calendar.iso_week_number/1`).
    test "is read as a Gregorian date and converted" do
      week_5_thursday = %Date{year: 2024, month: 5, day: 4, calendar: IsoWeek}

      for {text, locale} <- [{"Feb 1, 2024", :en}, {"01/02/2024", :"en-GB"}, {"2024-02-01", :en}] do
        assert Localize.Date.parse(text, locale: locale, calendar: IsoWeek) ==
                 {:ok, week_5_thursday},
               text
      end
    end

    test "comes back whole, as a map too" do
      assert Localize.Date.parse("Feb 1, 2024", locale: :en, calendar: IsoWeek, as: :map) ==
               {:ok, %{year: 2024, month: 5, day: 4, calendar: IsoWeek}}
    end

    test "as an interval or a date and time" do
      week_5_thursday = %Date{year: 2024, month: 5, day: 4, calendar: IsoWeek}
      week_6_monday = %Date{year: 2024, month: 6, day: 1, calendar: IsoWeek}
      range = Date.range(week_5_thursday, week_6_monday)

      assert Localize.Interval.parse("Feb 1 – 5, 2024", locale: :en, calendar: IsoWeek) ==
               {:ok, range}

      assert Localize.Interval.parse({"Feb 1, 2024", "Feb 5, 2024"},
               locale: :en,
               calendar: IsoWeek
             ) == {:ok, range}

      assert {:ok, %NaiveDateTime{calendar: IsoWeek} = datetime} =
               Localize.DateTime.parse("Feb 1, 2024, 10:30 AM", locale: :en, calendar: IsoWeek)

      assert {datetime.year, datetime.month, datetime.day, datetime.hour, datetime.minute} ==
               {2024, 5, 4, 10, 30}
    end
  end

  describe "an ISO 8601 date and time" do
    # ISO 8601 writes a Gregorian date, which is returned in the calendar
    # asked for, as a date alone is.
    test "is returned in the calendar asked for" do
      assert Localize.Date.parse("2026-05-23", locale: :en, calendar: YearAhead) ==
               {:ok, %Date{year: 2027, month: 5, day: 23, calendar: YearAhead}}

      assert {:ok, %NaiveDateTime{calendar: YearAhead, year: 2027, month: 5, day: 23}} =
               Localize.DateTime.parse("2026-05-23T14:30:00", locale: :en, calendar: YearAhead)

      assert {:ok, %DateTime{calendar: YearAhead, year: 2027, hour: 14, utc_offset: 18_000}} =
               Localize.DateTime.parse("2026-05-23T14:30:00+05:00",
                 locale: :en,
                 calendar: YearAhead
               )
    end

    # ISO 8601's other dates before a `T`, a day of the year, a week date and
    # each without its separators, are Gregorian days too: 23 May 2026 is
    # the 143rd day of its year and the Saturday of week 21, by Erlang's
    # calendar.
    test "in any of its forms is returned in the calendar asked for" do
      assert :calendar.iso_week_number({2026, 5, 23}) == {2026, 21}
      assert :calendar.day_of_the_week({2026, 5, 23}) == 6

      assert :calendar.date_to_gregorian_days({2026, 5, 23}) -
               :calendar.date_to_gregorian_days({2026, 1, 1}) + 1 == 143

      for text <- [
            "20260523T1430",
            "2026-143T14:30",
            "2026143T1430",
            "2026-W21-6T14:30",
            "2026W216T1430"
          ] do
        assert {:ok,
                %NaiveDateTime{
                  calendar: YearAhead,
                  year: 2027,
                  month: 5,
                  day: 23,
                  hour: 14,
                  minute: 30
                }} = Localize.DateTime.parse(text, locale: :en, calendar: YearAhead),
               text
      end
    end

    # A calendar of weeks' own date before a `T` is that calendar's, as it is
    # alone and before a space: its notation is read before ISO 8601. In a
    # calendar whose weeks begin on Sunday, week 1 holding 1 January, week 25
    # of 2026 begins on Sunday 14 June, so its day 2 is Monday 15 June, where
    # ISO 8601's 2026-W25-2 is Tuesday 16 June. A date ISO 8601 writes
    # another way is a Gregorian day, converted: 16 June is the calendar's
    # day 3 of that week.
    test "is a calendar of weeks' own date where the text before the T is its notation" do
      assert :calendar.day_of_the_week({2026, 1, 1}) == 4
      assert :calendar.day_of_the_week({2026, 6, 14}) == 7

      assert :calendar.date_to_gregorian_days({2026, 6, 14}) -
               :calendar.date_to_gregorian_days({2025, 12, 28}) == 24 * 7

      own = %Date{year: 2026, month: 25, day: 2, calendar: SundayWeeks}
      assert Date.convert(own, Calendar.ISO) == {:ok, ~D[2026-06-15]}
      assert Localize.Date.parse("2026-W25-2", locale: :en, calendar: SundayWeeks) == {:ok, own}

      for text <- [
            "2026-W25-2 10:30:00",
            "2026-W25-2T10:30:00",
            "2026-W25-2T10:30",
            "2026-W25-2T1030"
          ] do
        assert {:ok,
                %NaiveDateTime{
                  calendar: SundayWeeks,
                  year: 2026,
                  month: 25,
                  day: 2,
                  hour: 10,
                  minute: 30
                }} = Localize.DateTime.parse(text, locale: :en, calendar: SundayWeeks),
               text
      end

      assert {:ok, %DateTime{calendar: SundayWeeks, month: 25, day: 2, utc_offset: 7200}} =
               Localize.DateTime.parse("2026-W25-2T10:30+02:00",
                 locale: :en,
                 calendar: SundayWeeks
               )

      for text <- ["2026-06-16T10:30", "2026-167T10:30", "20260616T1030"] do
        assert {:ok, %NaiveDateTime{calendar: SundayWeeks, year: 2026, month: 25, day: 3}} =
                 Localize.DateTime.parse(text, locale: :en, calendar: SundayWeeks),
               text
      end

      assert Localize.DateTime.parse("2026-W25-2T10:30",
               locale: :en,
               calendar: SundayWeeks,
               as: :map
             ) ==
               {:ok,
                %{calendar: SundayWeeks, year: 2026, month: 25, day: 2, hour: 10, minute: 30}}
    end

    # A calendar's own formats come before ISO 8601 (user, 2026-10-04). `sv`
    # takes CLDR's root short date, "y-MM-dd", which writes a date as ISO
    # 8601 does, so the same text there is the calendar's own 23 May 2026,
    # and the text the formatter writes reads back as the date it was
    # written from. ISO 8601's `T` is in no locale's pattern.
    test "is the calendar's own date where the locale's format writes it that way" do
      own = %Date{year: 2026, month: 5, day: 23, calendar: YearAhead}

      assert Localize.Date.to_string(own, locale: :sv, format: :short) == {:ok, "2026-05-23"}
      assert Localize.Date.parse("2026-05-23", locale: :sv, calendar: YearAhead) == {:ok, own}

      assert {:ok, %NaiveDateTime{calendar: YearAhead, year: 2026, month: 5, day: 23, hour: 14}} =
               Localize.DateTime.parse("2026-05-23 14:30:00", locale: :sv, calendar: YearAhead)

      assert {:ok, %NaiveDateTime{calendar: YearAhead, year: 2027, month: 5, day: 23}} =
               Localize.DateTime.parse("2026-05-23T14:30:00", locale: :sv, calendar: YearAhead)
    end

    # Any of the calendar's formats reads the text (user, 2026-10-04: "Use
    # the broader rule"), in whatever order it writes its fields. `kk-Arab`'s
    # `yMd` is "y-d-M" (CLDR's `kk_Arab.xml`), so a year, a ten and an eleven
    # between hyphens are the calendar's 10 November there. `Calendar.ISO`,
    # whose own notation ISO 8601 is, reads 11 October.
    test "is the calendar's own date in the order its format writes it" do
      assert Localize.Date.parse("2026-10-11", locale: :"kk-Arab", calendar: YearAhead) ==
               {:ok, %Date{year: 2026, month: 11, day: 10, calendar: YearAhead}}

      assert Localize.Date.parse("2026-10-11", locale: :"kk-Arab") == {:ok, ~D[2026-10-11]}
    end
  end

  describe "weeks" do
    # A calendar's week numbers are its own, whatever the locale: a calendar
    # whose week 1 holds 1 January puts 1 January 2027 in week 1 of 2027.
    # `Calendar.ISO` has no weeks of its own, so its are the locale's (user,
    # 2026-10-02): ISO 8601's in `de`, week 53 of 2026
    # (`:calendar.iso_week_number/1`), and in `en`, whose weeks begin on
    # Sunday and whose week 1 holds 1 January, week 1 of 2027 (ICU4C 78.3).
    test "are the calendar's own, and the locale's for Calendar.ISO" do
      assert :calendar.iso_week_number({2027, 1, 1}) == {2026, 53}

      assert Localize.Date.to_string(~D[2027-01-01], format: "Y-ww", locale: :de) ==
               {:ok, "2026-53"}

      assert Localize.Date.to_string(~D[2027-01-01], format: "Y-ww", locale: :en) ==
               {:ok, "2027-01"}

      for locale <- [:en, :de] do
        assert Localize.Date.to_string(date(2027, 1, 1, JanuaryWeeks),
                 format: "Y-ww",
                 locale: locale
               ) == {:ok, "2027-01"}
      end
    end

    # Week text reads back in the weeks it was written in: the calendar's
    # own, its Monday week holding 1 January, and for `Calendar.ISO` the
    # locale's, en's Sunday week holding 1 January and de's ISO 8601 week 1,
    # which begins on Monday 4 January (ICU4C 78.3 reads both so).
    test "read back in the weeks they were written in" do
      assert Localize.Date.parse("week 1 of 2027", locale: :en, calendar: JanuaryWeeks) ==
               {:ok, %Date{year: 2026, month: 12, day: 28, calendar: JanuaryWeeks}}

      assert Localize.Date.parse("week 1 of 2027", locale: :en) == {:ok, ~D[2026-12-27]}

      assert Localize.Date.parse("Woche 1 des Jahres 2027", locale: :de) ==
               {:ok, ~D[2027-01-04]}
    end

    # A calendar of weeks reads a written month and day as a Gregorian date,
    # but its week numbers are its own weeks, so its week text reads back as
    # itself, in a locale whose weeks begin on Sunday too.
    test "of a calendar of weeks round trip through its week text" do
      week_25 = %Date{year: 2026, month: 25, day: 1, calendar: IsoWeek}

      for locale <- [:en, :de] do
        {:ok, text} = Localize.Date.to_string(week_25, format: :yw, locale: locale)
        assert Localize.Date.parse(text, locale: locale, calendar: IsoWeek) == {:ok, week_25}
      end

      assert Localize.Date.parse("2026-W25-2", calendar: IsoWeek) ==
               {:ok, %Date{year: 2026, month: 25, day: 2, calendar: IsoWeek}}

      assert Localize.Date.parse("2026-W25-2") == {:ok, ~D[2026-06-16]}
    end

    # A year and a week of a calendar of weeks is written "week 25 of 2026",
    # which names no day. Read as a map it is the value it was written from,
    # the year and the week its month field holds, the fields the days of
    # that week share, and not the first of them, which the struct form
    # gives. A notation and a Gregorian date name a day and come back whole,
    # and `Calendar.ISO`, which holds a week in no field of a date, keeps
    # it as a week.
    test "of a calendar of weeks read as a map are the year and the week" do
      week = %{year: 2026, month: 25, calendar: IsoWeek}

      for locale <- [:en, :de] do
        {:ok, text} = Localize.Date.to_string(week, locale: locale)

        assert Localize.Date.parse(text, locale: locale, calendar: IsoWeek, as: :map) ==
                 {:ok, week}
      end

      assert Localize.Date.parse("week 25 of 2026", locale: :en, calendar: IsoWeek, as: :map) ==
               {:ok, week}

      assert Localize.Date.parse("week 25 of 2026", locale: :en, calendar: IsoWeek) ==
               {:ok, %Date{year: 2026, month: 25, day: 1, calendar: IsoWeek}}

      assert Localize.Date.parse("2026-W25-2", calendar: IsoWeek, as: :map) ==
               {:ok, %{year: 2026, month: 25, day: 2, calendar: IsoWeek}}

      assert Localize.Date.parse("Jun 16, 2026", locale: :en, calendar: IsoWeek, as: :map) ==
               {:ok, %{year: 2026, month: 25, day: 2, calendar: IsoWeek}}

      assert Localize.Date.parse("week 25 of 2026", locale: :en, as: :map) ==
               {:ok,
                %{calendar: Calendar.ISO, year: 2026, week_of_year: 25, week_based_year: 2026}}
    end

    # ISO 8601's week without a day, "2026-W25", is ISO 8601's week whatever
    # the calendar's own weeks are. Where it is one of the calendar's own
    # weeks, as in a calendar of ISO 8601's weeks, a map is that year and
    # week; where it is not, as in a calendar whose weeks begin on Sunday,
    # it is the day the week begins on, whole: Monday 4 January 2027 is the
    # second day of that calendar's second week.
    test "of ISO 8601 without a day are the calendar's week where they are one of its weeks" do
      assert Localize.Date.parse("2026-W25", locale: :en, calendar: IsoWeek) ==
               {:ok, %Date{year: 2026, month: 25, day: 1, calendar: IsoWeek}}

      assert Localize.Date.parse("2026-W25", locale: :en, calendar: IsoWeek, as: :map) ==
               {:ok, %{year: 2026, month: 25, calendar: IsoWeek}}

      assert Localize.Date.parse("2026W252", locale: :en, calendar: IsoWeek) ==
               {:ok, %Date{year: 2026, month: 25, day: 2, calendar: IsoWeek}}

      monday = %Date{year: 2027, month: 2, day: 2, calendar: SundayWeeks}
      assert Date.convert!(monday, Calendar.ISO) == ~D[2027-01-04]

      assert Localize.Date.parse("2027-W01", locale: :en, calendar: SundayWeeks) == {:ok, monday}

      assert Localize.Date.parse("2027-W01", locale: :en, calendar: SundayWeeks, as: :map) ==
               {:ok, %{year: 2027, month: 2, day: 2, calendar: SundayWeeks}}

      assert Localize.Interval.parse("2026-W25 – 2026-W27",
               locale: :en,
               calendar: IsoWeek,
               as: :map
             ) ==
               {:ok,
                {%{year: 2026, month: 25, calendar: IsoWeek},
                 %{year: 2026, month: 27, calendar: IsoWeek}}}
    end

    # Each end of an interval of weeks is the week it was written from, a
    # week beside a whole date keeps its own shape, and a week beside a time
    # carries the time's fields with the year and the week.
    test "of a calendar of weeks read as a map in an interval and beside a time" do
      week = %{year: 2026, month: 25, calendar: IsoWeek}
      next = %{week | month: 26}
      {:ok, text} = Localize.Interval.to_string(week, next, locale: :en)

      assert Localize.Interval.parse(text, locale: :en, calendar: IsoWeek, as: :map) ==
               {:ok, {week, next}}

      assert Localize.Interval.parse({"week 25 of 2026", "week 26 of 2026"},
               locale: :en,
               calendar: IsoWeek,
               as: :map
             ) == {:ok, {week, next}}

      assert Localize.Interval.parse({"week 25 of 2026", "2026-W26-3"},
               locale: :en,
               calendar: IsoWeek,
               as: :map
             ) == {:ok, {week, %{year: 2026, month: 26, day: 3, calendar: IsoWeek}}}

      assert Localize.DateTime.parse("week 25 of 2026, 10:30 AM",
               locale: :en,
               calendar: IsoWeek,
               as: :map
             ) == {:ok, %{calendar: IsoWeek, year: 2026, month: 25, hour: 10, minute: 30}}
    end

    # The weeks are the calendar asked for's even where it reads its dates
    # as Gregorian ones: a Sunday week calendar's week 1 of 2027 begins on
    # Sunday 27 December 2026, where ISO 8601's begins on Monday 4 January.
    test "of a calendar of weeks read as Gregorian dates are its own" do
      week_1 = %Date{year: 2027, month: 1, day: 1, calendar: SundayWeeks}
      assert Date.convert!(week_1, Calendar.ISO) == ~D[2026-12-27]

      assert Localize.Date.parse("week 1 of 2027", locale: :en, calendar: SundayWeeks) ==
               {:ok, week_1}

      {:ok, text} = Localize.Date.to_string(week_1, format: :yw, locale: :en)
      assert Localize.Date.parse(text, locale: :en, calendar: SundayWeeks) == {:ok, week_1}
    end

    # A weekday name is an ISO day of the week, matched against the date's
    # ISO day whatever day the calendar's weeks begin on: 3 January 2027 is
    # a Sunday. `ja` writes the weekday after the date, where it is checked;
    # a leading one is stripped when it does not match.
    test "a weekday is checked as an ISO day whatever day the calendar's weeks begin on" do
      assert Localize.Date.parse("2027年1月3日日曜日", locale: :ja, calendar: SundayFirst) ==
               {:ok, %Date{year: 2027, month: 1, day: 3, calendar: SundayFirst}}

      assert {:error, %Localize.DateParseError{}} =
               Localize.Date.parse("2027年1月3日月曜日", locale: :ja, calendar: SundayFirst)
    end

    # `W` is the calendar's own week of the month, its `week_of_month/3`
    # (user, 2026-10-01), and for `Calendar.ISO` the locale's (user,
    # 2026-10-02). In `de`, whose weeks are ISO 8601's, 1 October 2021, a
    # Friday, is in the week holding Thursday 30 September, the fifth of
    # September. In `en`, whose weeks begin on Sunday and belong to a month
    # they hold one day of, that week is the first of October, on 30
    # September as on 1 October. A calendar whose week 1 holds the first of
    # the month puts it in week 1 of October, and a calendar of weeks counts
    # its own month's weeks: ISO week 25 is the fourth of its 4-4-5 June.
    test "of the month are the calendar's own, and the locale's for Calendar.ISO" do
      thursday = Date.add(~D[2021-10-01], 4 - Date.day_of_week(~D[2021-10-01], :monday))
      assert {thursday.month, div(thursday.day - 1, 7) + 1} == {9, 5}

      assert Localize.Date.to_string(~D[2021-10-01], format: "W", locale: :de) == {:ok, "5"}
      assert Localize.Date.to_string(~D[2021-10-04], format: "W", locale: :de) == {:ok, "1"}

      assert Localize.Date.to_string(~D[2021-09-30], format: "W", locale: :en) == {:ok, "1"}
      assert Localize.Date.to_string(~D[2021-10-01], format: "W", locale: :en) == {:ok, "1"}
      assert Localize.Date.to_string(~D[2021-10-03], format: "W", locale: :en) == {:ok, "2"}

      assert Localize.Date.to_string(date(2021, 10, 1, JanuaryWeeks), format: "W", locale: :en) ==
               {:ok, "1"}

      assert Localize.Date.to_string(date(2021, 10, 4, JanuaryWeeks), format: "W", locale: :en) ==
               {:ok, "2"}

      assert Localize.Date.to_string(date(2026, 25, 2, IsoWeek), format: "W", locale: :en) ==
               {:ok, "4"}
    end

    # A pattern with `W` names the month its week belongs to, and the year
    # and era that month is in, as `Y` names the year `w` belongs to (user,
    # 2026-10-01). CLDR's `MMMMW` is "'week' W 'of' MMMM" in `en` and
    # `en-GB`. In `en-GB`, whose weeks are ISO 8601's, 1 October 2021, in
    # September's fifth week, is "week 5 of September", and 30 December
    # 2019, whose week holds Thursday 2 January 2020, is in January 2020's
    # first. In `en` a week belongs to the month it holds one day of, so 30
    # September 2021 is in "week 1 of October". The day stays the date's, so
    # a pattern that writes it too pairs it with the week's month; no CLDR
    # pattern does.
    test "of the month name the month the week belongs to" do
      assert Localize.Date.to_string(~D[2021-10-01], format: :MMMMW, locale: :"en-GB") ==
               {:ok, "week 5 of September"}

      assert Localize.Date.to_string(~D[2021-10-04], format: :MMMMW, locale: :"en-GB") ==
               {:ok, "week 1 of October"}

      assert Localize.Date.to_string(~D[2019-12-30],
               format: "'week' W 'of' MMMM y G",
               locale: :"en-GB"
             ) == {:ok, "week 1 of January 2020 AD"}

      assert Localize.Date.to_string(~D[2021-10-01],
               format: "d MMMM, 'week' W",
               locale: :"en-GB"
             ) == {:ok, "1 September, week 5"}

      assert {:ok, parts} =
               Localize.Date.to_parts(~D[2021-10-01], format: :MMMMW, locale: :"en-GB")

      assert Enum.map_join(parts, & &1.value) == "week 5 of September"
      assert %{type: :month, value: "September"} in parts

      assert Localize.Date.to_string(~D[2021-09-30], format: :MMMMW, locale: :en) ==
               {:ok, "week 1 of October"}

      assert Localize.Date.to_string(~D[2021-10-01], format: :MMMMW, locale: :en) ==
               {:ok, "week 1 of October"}

      assert Localize.Date.to_string(~D[2019-12-30],
               format: "'week' W 'of' MMMM y G",
               locale: :en
             ) == {:ok, "week 1 of January 2020 AD"}

      assert Localize.Date.to_string(~D[2021-09-30], format: "d MMMM, 'week' W", locale: :en) ==
               {:ok, "30 October, week 1"}
    end

    # TR35's rule gives a week to the month that holds at least the fewest
    # days of it, which is the month of one deciding day of the week: of an
    # ISO 8601 week (Monday, four days) its Thursday, as in `en-GB`, and of
    # en's (Sunday, one day) its last day, Saturday. The week is that day's
    # place among its month's Thursdays, or Saturdays.
    test "of the month name the week's month on every day" do
      {:ok, months} = Localize.Locale.get(:en, [:dates, :calendars, :gregorian, :months])
      names = months.format.wide

      for date <- Date.range(~D[2015-01-01], ~D[2026-12-31]),
          {locale, deciding_day} <- [
            {:"en-GB", Date.add(date, 4 - Date.day_of_week(date, :monday))},
            {:en, Date.add(date, 7 - Date.day_of_week(date, :sunday))}
          ] do
        week = div(deciding_day.day - 1, 7) + 1
        expected = "#{week} #{Map.fetch!(names, deciding_day.month)} #{deciding_day.year}"

        assert Localize.Date.to_string(date, format: "W MMMM y", locale: locale) ==
                 {:ok, expected},
               "#{locale} #{date}"
      end
    end

    # A calendar whose week never leaves its month names the date's own:
    # ISO week 25 is the fourth week of its sixth 4-4-5 month, which CLDR's
    # generic calendar names "M06", and a calendar whose week 1 holds the
    # first of the month cuts its weeks at the month's end.
    test "of the month name the date's month where the week never leaves it" do
      assert Localize.Date.to_string(date(2026, 25, 2, IsoWeek), format: :MMMMW, locale: :en) ==
               {:ok, "week 4 of M06"}

      assert Localize.Date.to_string(date(2021, 10, 1, JanuaryWeeks),
               format: :MMMMW,
               locale: :en
             ) == {:ok, "week 1 of October"}

      assert Localize.Date.to_string(date(2021, 9, 30, JanuaryWeeks),
               format: :MMMMW,
               locale: :en
             ) == {:ok, "week 5 of September"}
    end
  end

  describe "quarters" do
    # A quarter is the calendar's answer, its `quarter_of_year/3`: a
    # thirteenth month is in the last quarter, where its month's place
    # would make it the fifth.
    test "are the calendar's own" do
      for {month, quarter} <- [{1, "1"}, {6, "2"}, {10, "4"}, {13, "4"}] do
        value = date(2026, month, 1, ThirteenMonths)
        assert Localize.Date.to_string(value, format: "Q", locale: :en) == {:ok, quarter}
      end

      assert Localize.Calendar.localize(date(2026, 13, 1, ThirteenMonths), :quarter, locale: :en) ==
               {:ok, "4th quarter"}

      assert Localize.Date.to_string(date(2026, 25, 2, IsoWeek), format: "QQQ y", locale: :en) ==
               {:ok, "Q2 2026"}
    end

    # The parser counts a quarter in the calendar's own quarters, so a
    # calendar of weeks' quarter reads back as the first day of its week 14.
    test "read back in the calendar's own quarters" do
      week_14 = %Date{year: 2026, month: 14, day: 1, calendar: IsoWeek}
      {:ok, text} = Localize.Date.to_string(week_14, format: "QQQ y", locale: :en)

      assert text == "Q2 2026"
      assert Localize.Date.parse(text, locale: :en, calendar: IsoWeek) == {:ok, week_14}
      assert Localize.Date.parse("Q2 2026", locale: :en) == {:ok, ~D[2026-04-01]}
    end

    # The year decides a thirteen-month calendar's quarters, so a quarter
    # needs it: a pattern's field is an error, and `Localize.Calendar.localize/3`
    # names a date without its year as the first quarter, as it names one
    # without any field.
    test "need the year" do
      assert {:error, _missing_year} =
               Localize.Date.to_string(%{month: 5}, format: "QQQ", locale: :en)

      assert Localize.Calendar.localize(%{month: 5}, :quarter, locale: :en, style: :abbreviated) ==
               {:ok, "Q1"}

      assert Localize.Calendar.localize(%{year: 2026, month: 5}, :quarter,
               locale: :en,
               style: :abbreviated
             ) == {:ok, "Q2"}
    end
  end
end
