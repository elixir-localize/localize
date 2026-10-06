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

  defp iso_week(year, week, day),
    do: %Date{year: year, month: week, day: day, calendar: IsoWeek}

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
    # skeleton's month is the week too: `yM` is the skeleton `yw`.
    test "writes a year and a week as the locale writes a week of the year" do
      week = %{year: 2026, month: 25, calendar: IsoWeek}

      for options <- [[], [format: :short], [format: :medium], [format: :long], [format: :full]] do
        assert Localize.Date.to_string(week, [locale: :en] ++ options) ==
                 {:ok, "week 25 of 2026"},
               inspect(options)
      end

      assert Localize.Date.to_string(week, locale: :de) == {:ok, "Woche 25 des Jahres 2026"}
      assert Localize.Date.to_string(week, locale: :fr) == {:ok, "semaine 25 de 2026"}
      assert Localize.Date.to_string(week, locale: :en, format: :yM) == {:ok, "week 25 of 2026"}

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
    # compares the weeks it writes, so two are both written and two days of
    # one week are that week once (TR35's step 4: one date where no field of
    # the pattern differs). A skeleton's month is the week, so `yM` is a
    # format of weeks as `yw` is; a pattern writes the calendar's period for
    # `M` and compares the periods: weeks 25 and 26 are both in the sixth,
    # which is written once, and week 31 is in the eighth.
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
               {:ok, "week 25 of 2026#{@thin}–#{@thin}week 26 of 2026"}

      assert Localize.Interval.to_string(from, to, locale: :en, format: "M/y") ==
               {:ok, "6/2026"}

      assert Localize.Interval.to_string(from, date(2026, 31, 1, IsoWeek),
               locale: :en,
               format: "M/y"
             ) == {:ok, "6/2026#{@thin}–#{@thin}8/2026"}
    end

    # A skeleton names fields, and a calendar of weeks holds a week in its
    # month field and the day of that week in its day field, so a skeleton's
    # month is the date's week and its day the weekday (user, 2026-10-04:
    # "For week based calendars we need to interpret `:month` as `:week` and
    # pick the correct skeleton accordingly"; 2026-10-06: its own fields,
    # read back in the calendar). `yMMMd` is then the skeleton `ywE`, which
    # no locale has a format for, and TR35's Missing Skeleton Fields appends
    # the weekday to the locale's `yw`: en.xml's "'week' w 'of' Y" with its
    # `Day-Of-Week` append item "{1}, {0}", de.xml's "'Woche' w 'des' 'Jahres'
    # Y" with "{1}, {0}", fr.xml's "'semaine' w 'de' Y" with root's "{1} {0}"
    # and ja.xml's "Y年第w週" with "{0}({1})". 2026-W25-2 is Tuesday 16 June
    # 2026. The calendar's period and day number, written as a month and a
    # day of the month, were "M06 2, 2026 AD", which names no week.
    test "writes a skeleton's month as its week and its day as the weekday" do
      value = iso_week(2026, 25, 2)

      for {locale, expected} <- [
            en: "Tue, week 25 of 2026",
            de: "Di., Woche 25 des Jahres 2026",
            fr: "mar. semaine 25 de 2026",
            ja: "2026年第25週(火)"
          ],
          skeleton <- [:yMMMd, :yMd, :yMMMMd, :yMMMEd, :yMEd, :ywE] do
        assert Localize.Date.to_string(value, format: skeleton, locale: locale) ==
                 {:ok, expected},
               "#{locale} #{skeleton}"

        assert Localize.Date.parse(expected, format: skeleton, locale: locale, calendar: IsoWeek) ==
                 {:ok, value},
               "#{locale} #{skeleton} #{expected}"

        assert Localize.Date.parse(expected, locale: locale, calendar: IsoWeek) == {:ok, value},
               "#{locale} #{expected}"
      end

      for skeleton <- [:yM, :yMMM, :yMMMM, :yw, :Yw] do
        assert Localize.Date.to_string(value, format: skeleton, locale: :en) ==
                 {:ok, "week 25 of 2026"},
               "#{skeleton}"
      end

      # A month and a day without a year are a week and a weekday: en.xml's
      # `E` is "ccc" and its `Week` append item "{0} ({2}: {1})".
      for skeleton <- [:Md, :MMMd, :MEd] do
        assert Localize.Date.to_string(value, format: skeleton, locale: :en) ==
                 {:ok, "Tue (week: 25)"},
               "#{skeleton}"
      end

      assert Localize.Date.to_string(value, format: :d, locale: :en) == {:ok, "Tue"}
      assert Localize.Date.to_string(value, format: :M, locale: :en) == {:ok, "25"}
    end

    # A skeleton with no month and no day is as it was, in CLDR's generic
    # formats, and so is a pattern, which writes the calendar's period for
    # `M`, and a skeleton that names a week beside its month.
    test "keeps a skeleton without a month or a day, and a pattern" do
      value = iso_week(2026, 25, 2)

      assert Localize.Date.to_string(value, format: :y, locale: :en) == {:ok, "2026 AD"}
      assert Localize.Date.to_string(value, format: :yQQQ, locale: :en) == {:ok, "Q2 2026 AD"}

      assert Localize.Date.to_string(value, format: "MMM d, y", locale: :en) ==
               {:ok, "M06 2, 2026"}

      assert Localize.Date.to_string(value, format: :MMMMW, locale: :en) == {:ok, "week 4 of M06"}
    end

    # Text written for a Gregorian date is still read with a skeleton and
    # converted (user, 2026-10-01), after the calendar's own fields.
    test "still reads a Gregorian date with a skeleton" do
      assert Localize.Date.parse("Jun 16, 2026", format: :yMMMd, locale: :en, calendar: IsoWeek) ==
               {:ok, iso_week(2026, 25, 2)}

      assert Localize.Date.parse("week 25 of 2026",
               format: :yM,
               locale: :en,
               calendar: IsoWeek,
               as: :map
             ) == {:ok, %{calendar: IsoWeek, year: 2026, month: 25}}
    end

    # The weekday beside a week is the day of it, in the Gregorian calendar
    # as in a calendar of weeks: it was taken off the front of the text and
    # the week's first day returned, 14 June for "Tue, week 25 of 2026" in
    # `en`, whose weeks begin on Sunday.
    test "reads a weekday beside a week as that day of the week" do
      assert Localize.Date.parse("Tue, week 25 of 2026", locale: :en) == {:ok, ~D[2026-06-16]}
      assert Localize.Date.parse("week 25 of 2026", locale: :en) == {:ok, ~D[2026-06-14]}

      assert Localize.Date.parse("Wed, week 25 of 2026", locale: :en, calendar: IsoWeek) ==
               {:ok, iso_week(2026, 25, 3)}
    end

    # A date and time's skeleton is its date's and its time's: en.xml's
    # medium date-time pattern joins the two with ", ".
    test "writes a date and time's skeleton the same way" do
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

      assert Localize.DateTime.to_string(value, format: :yMMMdHm, locale: :en) ==
               {:ok, "Tue, week 25 of 2026, 10:30"}

      assert Localize.DateTime.to_string(value, format: :yMMMd, locale: :en) ==
               {:ok, "Tue, week 25 of 2026"}

      assert Localize.DateTime.to_string(value, format: :Hm, locale: :en) == {:ok, "10:30"}
    end

    # A skeleton of a date and time is written in one calendar's formats,
    # and where it names a week they are those of the calendar the dates are
    # read in, the time's with the date's. th.xml's Gregorian `Hm` is
    # "HH:mm น." where the generic calendar, a calendar of weeks' own, has
    # root's "HH:mm"; its `yw` is "สัปดาห์ที่ w ของปี Y" and its `Day-Of-Week`
    # append item "{1}ที่ {0}", and root joins a date to a time with a space.
    # The time was read in the generic calendar's formats, as no time.
    test "reads the time of a date and time's skeleton in the formats it is written in" do
      value = at(iso_week(2026, 25, 2), 10, 30)
      text = "อังคารที่ สัปดาห์ที่ 25 ของปี 2026 10:30 น."

      assert Localize.DateTime.to_string(value, format: :yMMMdHm, locale: :th) == {:ok, text}

      for format <- [[format: :yMMMdHm], []] do
        options = [locale: :th, calendar: IsoWeek] ++ format
        assert Localize.DateTime.parse(text, options) == {:ok, value}, inspect(format)
      end

      # A skeleton that names no week is written and read in the calendar's
      # own formats, and a time's skeleton alone with them.
      assert Localize.DateTime.to_string(value, format: :Hm, locale: :th) == {:ok, "10:30"}

      for {locale, expected} <- [
            en: "Tue, week 25 of 2026, 10:30",
            de: "Di., Woche 25 des Jahres 2026, 10:30"
          ] do
        assert Localize.DateTime.to_string(value, format: :yMMMdHm, locale: locale) ==
                 {:ok, expected}

        assert Localize.DateTime.parse(expected,
                 format: :yMMMdHm,
                 locale: locale,
                 calendar: IsoWeek
               ) == {:ok, value}
      end
    end

    # Two dates and times of one day are the date once and an interval of
    # the times (TR35's interval algorithm, step 3.2), and the date is the
    # week and the weekday the skeleton's month and day are, in the formats
    # of the calendar the dates are read in, the times' interval with it.
    # en.xml's Gregorian `Hm` interval is "HH:mm – HH:mm" about thin spaces
    # and its short date and time pattern "{1}, {0}"; de.xml's are
    # "HH:mm–HH:mm 'Uhr'" and "{1}, {0}"; th.xml's "HH:mm น. – HH:mm น." and
    # root's "{1} {0}". The date was the calendar's period and day number,
    # "M06 2, 2026 AD, 10:30 – 12:30", which names no week.
    test "writes the date of two dates and times of one day as the week and the weekday" do
      from = at(iso_week(2026, 25, 2), 10, 30)
      to = at(iso_week(2026, 25, 2), 12, 30)

      for {locale, expected} <- [
            en: "Tue, week 25 of 2026, 10:30#{@thin}–#{@thin}12:30",
            de: "Di., Woche 25 des Jahres 2026, 10:30–12:30 Uhr",
            th: "อังคารที่ สัปดาห์ที่ 25 ของปี 2026 10:30 น. – 12:30 น."
          ] do
        assert Localize.Interval.to_string(from, to, locale: locale, format: :yMMMdHm) ==
                 {:ok, expected},
               "#{locale}"
      end

      # Two days are both dates and times in full, and one moment is one.
      assert Localize.Interval.to_string(from, at(iso_week(2026, 25, 5), 10, 30),
               locale: :en,
               format: :yMMMdHm
             ) ==
               {:ok, "Tue, week 25 of 2026, 10:30#{@thin}–#{@thin}Fri, week 25 of 2026, 10:30"}

      assert Localize.Interval.to_string(from, from, locale: :en, format: :yMMMdHm) ==
               {:ok, "Tue, week 25 of 2026, 10:30"}

      # A skeleton of a time alone names no week, and is the calendar's own.
      assert Localize.Interval.to_string(from, to, locale: :en, format: :Hm) ==
               {:ok, "10:30#{@thin}–#{@thin}12:30"}
    end

    # No interval format is keyed by a week and a weekday, so two dates are
    # written in full about the locale's fallback pattern, or once where
    # they are the same day, and a skeleton without a year takes one across
    # years.
    test "writes an interval at a skeleton with both dates in full, and reads it back" do
      from = iso_week(2026, 25, 2)

      for {to, format, expected} <- [
            {iso_week(2026, 26, 1), :yMMMd,
             "Tue, week 25 of 2026#{@thin}–#{@thin}Mon, week 26 of 2026"},
            {iso_week(2026, 25, 5), :yMMMd,
             "Tue, week 25 of 2026#{@thin}–#{@thin}Fri, week 25 of 2026"},
            {iso_week(2027, 25, 2), :yMd,
             "Tue, week 25 of 2026#{@thin}–#{@thin}Tue, week 25 of 2027"},
            {iso_week(2026, 26, 1), :MMMd, "Tue (week: 25)#{@thin}–#{@thin}Mon (week: 26)"}
          ] do
        assert Localize.Interval.to_string(from, to, locale: :en, format: format) ==
                 {:ok, expected},
               "#{format} #{inspect(to)}"

        assert Localize.Interval.parse(expected,
                 locale: :en,
                 calendar: IsoWeek,
                 format: format,
                 reference_date: from
               ) == {:ok, Date.range(from, to)},
               expected
      end

      assert Localize.Interval.to_string(from, from, locale: :en, format: :yMMMd) ==
               {:ok, "Tue, week 25 of 2026"}

      assert Localize.Interval.to_string(from, iso_week(2027, 25, 2),
               locale: :en,
               format: :MMMd
             ) == {:ok, "Tue, week 25 of 2026#{@thin}–#{@thin}Tue, week 25 of 2027"}

      assert Localize.Interval.parse("Tue, week 25 of 2026 – Mon, week 26 of 2026",
               locale: :en,
               calendar: IsoWeek,
               reference_date: from
             ) == {:ok, Date.range(from, iso_week(2026, 26, 1))}
    end

    # A week written without its year is of the reference date's week-based
    # year, as a date written without its year is of the reference date's
    # year: the year `Y` writes beside `w`, which is not the year of the
    # week's days about the new year. ISO 8601's 2020 has 53 weeks and its
    # last day, 2020-W53-7, is Sunday 3 January 2021; its 2025 begins on
    # Monday 30 December 2024. A week was read as a week of the year of the
    # Gregorian date its reference date is: "Sun (week: 53)" on 3 January
    # 2021 as no date, 2021 having 52 weeks, and "Mon (week: 1)" on 30
    # December 2024 as the first day of 2024.
    test "reads a week written without its year as a week of the reference date's week-based year" do
      for {value, text, gregorian} <- [
            {iso_week(2020, 53, 7), "Sun (week: 53)", ~D[2021-01-03]},
            {iso_week(2025, 1, 1), "Mon (week: 1)", ~D[2024-12-30]},
            {iso_week(2026, 25, 2), "Tue (week: 25)", ~D[2026-06-16]}
          ],
          skeleton <- [:Md, :MMMd, :MEd] do
        assert Date.convert(value, Calendar.ISO) == {:ok, gregorian}

        assert Localize.Date.to_string(value, format: skeleton, locale: :en) == {:ok, text},
               "#{skeleton} #{text}"

        for reference <- [value, gregorian], format <- [[format: skeleton], []] do
          options = [locale: :en, calendar: IsoWeek, reference_date: reference] ++ format

          assert Localize.Date.parse(text, options) == {:ok, value},
                 "#{text} #{inspect(options)}"
        end
      end
    end

    # Two weeks written without a year are read by their week-based years, as
    # two dates written without one are read by their years: the earlier is
    # of the reference date's, and the later of that year or, where its week
    # comes before the earlier's there, of the year after. 2021-W01-1 is
    # Monday 4 January 2021, the day after 2020-W53-7, and 2026-W25-2 is
    # Tuesday 16 June 2026. The same day a year away is no guide to a
    # week-based year: a year on from 3 January 2021 is the first day of ISO
    # 8601's 2022.
    test "reads two weeks written without a year by their week-based years" do
      last = iso_week(2020, 53, 7)
      midyear = iso_week(2026, 25, 2)

      for {text, reference, from, to} <- [
            {"Sun (week: 53) – Mon (week: 1)", last, last, iso_week(2021, 1, 1)},
            {"Sun (week: 53) – Mon (week: 1)", ~D[2020-06-16], last, iso_week(2021, 1, 1)},
            {"Tue (week: 25) – Mon (week: 26)", last, iso_week(2020, 25, 2),
             iso_week(2020, 26, 1)},
            {"Tue (week: 25) – Mon (week: 24)", midyear, midyear, iso_week(2027, 24, 1)},
            {"Tue (week: 25) – Sun (week: 53)", midyear, midyear, iso_week(2026, 53, 7)},
            # One end written with its year: the other is beside it.
            {"Sun (week: 53) – Mon, week 1 of 2021", midyear, last, iso_week(2021, 1, 1)},
            {"Sun, week 53 of 2020 – Mon (week: 1)", midyear, last, iso_week(2021, 1, 1)},
            {"Tue (week: 25) – Mon, week 26 of 2031", midyear, iso_week(2031, 25, 2),
             iso_week(2031, 26, 1)}
          ] do
        options = [locale: :en, calendar: IsoWeek, reference_date: reference]

        assert Localize.Interval.parse(text, options) == {:ok, Date.range(from, to)},
               "#{text} on #{inspect(reference)}"
      end

      # A weekday and an earlier one of one week are an inverted range, as a
      # day and an earlier day of one month are, and not the year to the
      # same week of the next.
      assert {:error, %Localize.DateRangeParseError{reason: :inverted}} =
               Localize.Interval.parse("Tue (week: 25) – Mon (week: 25)",
                 locale: :en,
                 calendar: IsoWeek,
                 reference_date: midyear
               )

      # ISO 8601's 2025 has 52 weeks and its 2026 has 53: a week 53 after
      # week 2 of 2025 is no week of that year, and the one of the year
      # after is more than a week-based year on.
      assert {:error, %Localize.DateRangeParseError{}} =
               Localize.Interval.parse("Mon (week: 2) – Mon (week: 53)",
                 locale: :en,
                 calendar: IsoWeek,
                 reference_date: iso_week(2025, 2, 1)
               )
    end

    # A year, and a year and a quarter, name no day, and read as a map they
    # are the fields the calendar's own format wrote, as a year and a week
    # are. en.xml's generic `y` is "y G" and its `yQQQ` "QQQ y G", and week 25
    # is in the calendar's second quarter, weeks 14 to 26. The year alone was
    # an error, no whole date being read to convert, and the year and the
    # quarter were the quarter's whole first day, `%{year: 2026, month: 14,
    # day: 1}`.
    test "reads a year, and a year and a quarter, as the fields it wrote" do
      value = iso_week(2026, 25, 2)

      for {format, text, fields} <- [
            {:y, "2026 AD", %{year: 2026}},
            {:yQQQ, "Q2 2026 AD", %{year: 2026, quarter: 2}}
          ] do
        assert Localize.Date.to_string(value, format: format, locale: :en) == {:ok, text}

        assert Localize.Date.parse(text,
                 locale: :en,
                 calendar: IsoWeek,
                 format: format,
                 as: :map
               ) == {:ok, Map.put(fields, :calendar, IsoWeek)},
               text
      end

      assert Localize.Date.parse("2026 AD", locale: :en, calendar: IsoWeek, as: :map) ==
               {:ok, %{calendar: IsoWeek, year: 2026}}

      # As a date, a quarter is its first day and a year alone is none.
      assert Localize.Date.parse("Q2 2026 AD", locale: :en, calendar: IsoWeek, format: :yQQQ) ==
               {:ok, iso_week(2026, 14, 1)}

      assert {:error, %Localize.DateParseError{}} =
               Localize.Date.parse("2026 AD", locale: :en, calendar: IsoWeek, format: :y)

      # A quarter the calendar does not have is no quarter of its year.
      assert {:error, %Localize.DateParseError{}} =
               Localize.Date.parse("Q5 2026 AD",
                 locale: :en,
                 calendar: IsoWeek,
                 format: :yQQQ,
                 as: :map
               )

      # A date of a month and a day is still read whole and converted, and a
      # year and a week are the week.
      assert Localize.Date.parse("Jun 16, 2026", locale: :en, calendar: IsoWeek, as: :map) ==
               {:ok, %{calendar: IsoWeek, year: 2026, month: 25, day: 2}}

      assert Localize.Date.parse("week 25 of 2026", locale: :en, calendar: IsoWeek, as: :map) ==
               {:ok, %{calendar: IsoWeek, year: 2026, month: 25}}
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

  # Two dates written for a calendar of weeks without a year share one as the
  # Gregorian dates they are written as, whichever way they are given: 28
  # December 2026 and 3 January 2027 are the Monday and the Sunday of ISO
  # week 53 of 2026 (`:calendar.iso_week_number/1`), and the calendar's own
  # year does not turn between them.
  describe "an interval written without a year for an ISO week calendar" do
    test "ends in the Gregorian year after, across the Gregorian new year" do
      assert :calendar.iso_week_number({2026, 12, 28}) == {2026, 53}
      assert :calendar.iso_week_number({2027, 1, 3}) == {2026, 53}

      week_53 =
        Date.range(
          %Date{year: 2026, month: 53, day: 1, calendar: IsoWeek},
          %Date{year: 2026, month: 53, day: 7, calendar: IsoWeek}
        )

      options = [locale: :en, calendar: IsoWeek, reference_date: ~D[2026-06-01]]

      for input <- ["Dec 28 – Jan 3", "December 28 to January 3", {"Dec 28", "Jan 3"}] do
        assert Localize.Interval.parse(input, options) == {:ok, week_53}, inspect(input)
      end
    end

    # 16 and 20 June 2026 are the Tuesday and the Saturday of ISO week 25.
    test "is of the reference date's year where the months run on" do
      assert :calendar.iso_week_number({2026, 6, 16}) == {2026, 25}

      week_25 =
        Date.range(
          %Date{year: 2026, month: 25, day: 2, calendar: IsoWeek},
          %Date{year: 2026, month: 25, day: 6, calendar: IsoWeek}
        )

      options = [locale: :en, calendar: IsoWeek, reference_date: ~D[2026-01-01]]

      for input <- ["Jun 16 – 20", "June 16 to June 20", {"Jun 16", "Jun 20"}] do
        assert Localize.Interval.parse(input, options) == {:ok, week_25}, inspect(input)
      end
    end

    test "two strings are read as an interval is, as maps and inverted" do
      options = [locale: :en, calendar: IsoWeek]

      assert Localize.Interval.parse({"Feb 1, 2024", "Feb 5, 2024"}, [as: :map] ++ options) ==
               {:ok,
                {%{year: 2024, month: 5, day: 4, calendar: IsoWeek},
                 %{year: 2024, month: 6, day: 1, calendar: IsoWeek}}}

      assert {:error, %Localize.DateRangeParseError{reason: :inverted}} =
               Localize.Interval.parse({"Feb 5, 2024", "Feb 1, 2024"}, options)

      assert Localize.Interval.parse(
               {"Feb 5, 2024", "Feb 1, 2024"},
               [allow_inverted: true] ++ options
             ) ==
               {:ok,
                Date.range(
                  %Date{year: 2024, month: 6, day: 1, calendar: IsoWeek},
                  %Date{year: 2024, month: 5, day: 4, calendar: IsoWeek},
                  -1
                )}

      assert {:error, %Localize.DateRangeParseError{reason: :from_parse_failed}} =
               Localize.Interval.parse({"not a date", "Feb 1, 2024"}, options)

      assert {:error, %Localize.DateRangeParseError{reason: :to_parse_failed}} =
               Localize.Interval.parse({"Feb 1, 2024", "not a date"}, options)
    end

    # An inverted range names its two dates in the calendar asked for, as a
    # range that is read is in it. 1 and 5 February 2024 are the Thursday of
    # ISO week 5 and the Monday of week 6 (`:calendar.iso_week_number/1`),
    # and the Tuesday and the Monday of week 25 of 2026 are 16 and 15 June.
    # The error named the Gregorian dates the text was read as.
    test "an inverted range names its dates in the calendar asked for" do
      assert :calendar.iso_week_number({2024, 2, 1}) == {2024, 5}
      assert :calendar.iso_week_number({2024, 2, 5}) == {2024, 6}

      from = iso_week(2024, 6, 1)
      to = iso_week(2024, 5, 4)

      for input <- [{"Feb 5, 2024", "Feb 1, 2024"}, "Feb 5, 2024 – Feb 1, 2024"] do
        assert Localize.Interval.parse(input, locale: :en, calendar: IsoWeek) ==
                 {:error,
                  %Localize.DateRangeParseError{
                    input: {from, to},
                    reason: :inverted,
                    from: from,
                    to: to
                  }},
               inspect(input)
      end

      tuesday = iso_week(2026, 25, 2)
      monday = iso_week(2026, 25, 1)

      assert Localize.Interval.parse("Tue (week: 25) – Mon (week: 25)",
               locale: :en,
               calendar: IsoWeek,
               reference_date: tuesday
             ) ==
               {:error,
                %Localize.DateRangeParseError{
                  input: {tuesday, monday},
                  reason: :inverted,
                  from: tuesday,
                  to: monday
                }}

      # In the calendar the text is read in, the dates are as they were.
      assert Localize.Interval.parse("Feb 5, 2024 – Feb 1, 2024", locale: :en) ==
               {:error,
                %Localize.DateRangeParseError{
                  input: {~D[2024-02-05], ~D[2024-02-01]},
                  reason: :inverted,
                  from: ~D[2024-02-05],
                  to: ~D[2024-02-01]
                }}
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

    # A week written without its year is of the reference date's week-based
    # year in the weeks it is read in, for `Calendar.ISO` the locale's.
    # supplementalData.xml's weekData gives the United States a first day of
    # Sunday and a week 1 holding 1 January, so Wednesday 30 December 2026 is
    # in en's week 1 of 2027, and it gives Germany ISO 8601's weeks, so
    # Sunday 3 January 2021 is in de's week 53 of 2020
    # (`:calendar.iso_week_number/1`). The week was read as a week of the
    # reference date's own year: 31 December 2025 in `en`, and no date in
    # `de`, whose 2021 has 52 weeks. The week alone is its first day.
    test "written without a year are of the reference date's week-based year" do
      assert :calendar.iso_week_number({2021, 1, 3}) == {2020, 53}

      for {locale, date, format, text} <- [
            {:en, ~D[2026-12-30], "E, 'week' w", "Wed, week 1"},
            {:en, ~D[2026-12-30], :wE, "Wed (week: 1)"},
            {:de, ~D[2021-01-03], "E, 'Woche' w", "So., Woche 53"},
            {:en, ~D[2026-06-16], :wE, "Tue (week: 25)"}
          ] do
        assert Localize.Date.to_string(date, format: format, locale: locale) == {:ok, text}

        assert Localize.Date.parse(text, format: format, locale: locale, reference_date: date) ==
                 {:ok, date},
               text
      end

      assert Localize.Date.parse("Wed (week: 1)", locale: :en, reference_date: ~D[2026-12-30]) ==
               {:ok, ~D[2026-12-30]}

      assert Localize.Date.parse("week 1",
               format: "'week' w",
               locale: :en,
               reference_date: ~D[2026-12-30]
             ) ==
               {:ok, ~D[2026-12-27]}

      # Two weeks without a year across the end of a week-based year: en's
      # week 53 of 2022 is the last week of December, and the week after it
      # is week 1 of 2023, which begins on Sunday 1 January.
      assert Localize.Interval.parse("Sat (week: 53) – Sun (week: 1)",
               locale: :en,
               reference_date: ~D[2022-12-31]
             ) == {:ok, Date.range(~D[2022-12-31], ~D[2023-01-01])}
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
    # needs it: a pattern's field is an error naming the year, and so is
    # `Localize.Calendar.localize/3`, which named a date without its year as
    # the first quarter.
    test "need the year" do
      assert {:error, %Localize.DateTimeInvalidInputError{missing: [:year]}} =
               Localize.Date.to_string(%{month: 5}, format: "QQQ", locale: :en)

      assert {:error, %Localize.DateTimeInvalidInputError{missing: [:year]}} =
               Localize.Calendar.localize(%{month: 5}, :quarter, locale: :en, style: :abbreviated)

      assert Localize.Calendar.localize(%{year: 2026, month: 5}, :quarter,
               locale: :en,
               style: :abbreviated
             ) == {:ok, "Q2"}
    end
  end
end
