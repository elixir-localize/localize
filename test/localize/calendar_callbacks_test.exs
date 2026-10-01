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

    # A written month and day name no single week, so a date is read as a
    # Gregorian one and converted, as Calendrical's week calendars say.
    def parsing_calendar, do: Calendar.ISO

    # Its own weeks are its dates' week fields, and its quarters thirteen of
    # them each, a 53rd week in the last.
    def week_of_year(year, week, _day), do: {year, week}
    def quarter_of_year(_year, week, _day), do: min(div(week - 1, 13) + 1, 4)

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
    def related_gregorian_year(_year, _month, _day), do: :no_year
    def cyclic_year(_year, _month, _day), do: :no_year
    def week_of_year(_year, _month, _day), do: :no_week
    def day_of_year(_year, _month, _day), do: :no_day
    def day_of_week(_year, _month, _day, _starting_on), do: :no_day
    def quarter_of_year(_year, _month, _day), do: :no_quarter
  end

  # A calendar answering every question but `parsing_calendar/0`, as a
  # Calendrical calendar before 1.4 does.
  defmodule Unparsing do
    @moduledoc false
    use Localize.Test.StandInCalendar, without: [parsing_calendar: 0]
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
    def quarter(year, quarter), do: Localize.Calendar.ISO.quarter(year, quarter)
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
            {"c", :no_day},
            {"Q", :no_quarter},
            {"QQQ", :no_quarter}
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
  end

  describe "weeks" do
    # Week numbers are the calendar's own, never the locale's (user,
    # 2026-10-01): Calendar.ISO's are ISO 8601's, 1 January 2027 being in
    # week 53 of 2026 (`:calendar.iso_week_number/1`), and a calendar whose
    # week 1 holds 1 January puts it in week 1 of 2027.
    test "are the calendar's own" do
      assert :calendar.iso_week_number({2027, 1, 1}) == {2026, 53}

      for locale <- [:en, :de] do
        assert Localize.Date.to_string(~D[2027-01-01], format: "Y-ww", locale: locale) ==
                 {:ok, "2026-53"}

        assert Localize.Date.to_string(date(2027, 1, 1, JanuaryWeeks),
                 format: "Y-ww",
                 locale: locale
               ) == {:ok, "2027-01"}
      end
    end

    test "read back in the calendar's own weeks" do
      assert Localize.Date.parse("week 1 of 2027", locale: :en, calendar: JanuaryWeeks) ==
               {:ok, %Date{year: 2026, month: 12, day: 28, calendar: JanuaryWeeks}}

      assert Localize.Date.parse("week 1 of 2027", locale: :en) == {:ok, ~D[2027-01-04]}
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

    # `W` follows ISO 8601's rule in the calendar's own month: a Monday week
    # is the month's that holds its Thursday. A July fiscal year's first
    # month is July 2025, whose 1st is a Tuesday and 31st a Thursday.
    test "of the month are ISO 8601's in the calendar's month" do
      for {day, week} <- [{1, "1"}, {6, "1"}, {7, "2"}, {31, "5"}] do
        civil = Date.new!(2025, 7, day)
        thursday = Date.add(civil, 4 - Date.day_of_week(civil, :monday))
        assert Integer.to_string(div(thursday.day - 1, 7) + 1) == week

        assert Localize.Date.to_string(date(2026, 1, day, FiscalJuly), format: "W", locale: :en) ==
                 {:ok, week}
      end
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
