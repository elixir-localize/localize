defmodule Localize.DateTime.RelativeTest do
  use ExUnit.Case, async: true

  doctest Localize.DateTime.Relative

  @date ~D[2021-10-01]
  @relative_to ~D[2021-09-19]

  @datetime ~U[2021-10-01 10:15:00+00:00]
  @relative_datetime_to ~U[2021-09-19 12:15:00+00:00]

  @time ~T[18:11:01]
  @relative_time_to ~T[11:52:03]

  alias Localize.DateTime.Relative

  # A date shifted by years and months as Calendrical's calendars shift one
  # in their `shift_date/4`, after Temporal: the years keep the month by its
  # name, by `month_of_year/3`, wherever it falls in the new year; the months
  # count on from it through each year's months; and the day is clamped to
  # the month reached. A leap month the year lacks is the ordinary month it
  # doubles, and an ordinary month the year has only as a leap month is
  # that month, as Adar is the leap year's Adar II. Any other name the year
  # lacks, Adar I in an ordinary year, is the month in the same place,
  # clamped to the year's months.
  defmodule Shift do
    @moduledoc false

    def date(calendar, year, month, day, %Duration{year: years, month: months, week: 0, day: 0}) do
      {year, month} = same_month(calendar, year, month, day, year + years)
      {year, month} = months_on(calendar, year, month, months)
      {year, month, min(day, calendar.days_in_month(year, month))}
    end

    defp same_month(_calendar, year, month, _day, year), do: {year, month}

    defp same_month(calendar, year, month, day, to_year) do
      name = calendar.month_of_year(year, month, day)
      months = calendar.months_in_year(to_year)
      names = Enum.map(1..months, &{&1, calendar.month_of_year(to_year, &1, 1)})

      to_month =
        Enum.find_value(names, fn {place, other} -> other == name && place end) ||
          Enum.find_value(names, fn {place, other} -> number(other) == number(name) && place end) ||
          min(month, months)

      {to_year, to_month}
    end

    defp months_on(_calendar, year, month, 0), do: {year, month}

    defp months_on(calendar, year, month, months) when months > 0 do
      left = calendar.months_in_year(year) - month

      if months <= left,
        do: {year, month + months},
        else: months_on(calendar, year + 1, 1, months - left - 1)
    end

    defp months_on(calendar, year, month, months) do
      if month + months >= 1,
        do: {year, month + months},
        else: months_on(calendar, year - 1, calendar.months_in_year(year - 1), months + month)
    end

    defp number({number, :leap}), do: number
    defp number(number), do: number
  end

  # A calendar whose years need not have twelve months, as a Hebrew leap
  # year has thirteen: every third year has thirteen months, every month
  # thirty days, and days count on from an arbitrary epoch. Localize cannot
  # load Calendrical's calendars, which depend on it.
  defmodule Thirteen do
    @moduledoc false
    use Localize.Test.StandInCalendar

    @epoch 700_000

    def shift_date(year, month, day, duration),
      do: Shift.date(__MODULE__, year, month, day, duration)

    def months_in_year(year), do: if(rem(year, 3) == 0, do: 13, else: 12)
    def days_in_month(_year, _month), do: 30

    def valid_date?(year, month, day),
      do: year >= 1 and month in 1..months_in_year(year) and day in 1..30

    def quarter_of_year(_year, month, _day), do: min(div(month - 1, 3) + 1, 4)

    def day_of_week(year, month, day, starting_on) do
      {days, _fraction} = naive_datetime_to_iso_days(year, month, day, 0, 0, 0, {0, 0})
      {iso_year, iso_month, iso_day} = Calendar.ISO.date_from_iso_days(days)
      Calendar.ISO.day_of_week(iso_year, iso_month, iso_day, starting_on)
    end

    def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
      days_before = Enum.reduce(1..(year - 1)//1, 0, &(months_in_year(&1) * 30 + &2))
      days = @epoch + days_before + (month - 1) * 30 + day - 1
      {days, Calendar.ISO.time_to_day_fraction(hour, minute, second, microsecond)}
    end

    def naive_datetime_from_iso_days({days, fraction}) do
      {year, day_of_year} = year_of(days - @epoch, 1)
      {hour, minute, second, microsecond} = Calendar.ISO.time_from_day_fraction(fraction)

      {year, div(day_of_year, 30) + 1, rem(day_of_year, 30) + 1, hour, minute, second,
       microsecond}
    end

    defp year_of(days, year) do
      length = months_in_year(year) * 30
      if days < length, do: {year, days}, else: year_of(days - length, year + 1)
    end

    def day_rollover_relative_to_midnight_utc, do: {0, 1}
    def date_to_string(year, month, day), do: "#{year}-#{month}-#{day} Thirteen"
  end

  # `Thirteen` with its months named as Calendrical's lunisolar calendars
  # name them, by `month_of_year/3`: a year of thirteen has a leap month,
  # `{5, :leap}`, after its fifth, so a month after it sits one place later
  # than in a year of twelve.
  defmodule Intercalary do
    @moduledoc false
    use Localize.Test.StandInCalendar

    defdelegate months_in_year(year), to: Thirteen
    defdelegate days_in_month(year, month), to: Thirteen
    defdelegate valid_date?(year, month, day), to: Thirteen
    defdelegate quarter_of_year(year, month, day), to: Thirteen
    defdelegate day_of_week(year, month, day, starting_on), to: Thirteen

    defdelegate naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond),
      to: Thirteen

    defdelegate naive_datetime_from_iso_days(iso_days), to: Thirteen
    defdelegate day_rollover_relative_to_midnight_utc, to: Thirteen
    defdelegate date_to_string(year, month, day), to: Thirteen

    def shift_date(year, month, day, duration),
      do: Shift.date(__MODULE__, year, month, day, duration)

    def month_of_year(year, month, _day) do
      cond do
        months_in_year(year) == 12 or month <= 5 -> month
        month == 6 -> {5, :leap}
        true -> month - 1
      end
    end
  end

  # `Thirteen` with its months named as the Hebrew calendar's are: a year of
  # thirteen has Adar I, 6, and Adar II, `{7, :leap}`, where a year of twelve
  # has Adar, 7, alone.
  defmodule Adar do
    @moduledoc false
    use Localize.Test.StandInCalendar

    defdelegate months_in_year(year), to: Thirteen
    defdelegate days_in_month(year, month), to: Thirteen
    defdelegate valid_date?(year, month, day), to: Thirteen
    defdelegate quarter_of_year(year, month, day), to: Thirteen
    defdelegate day_of_week(year, month, day, starting_on), to: Thirteen

    defdelegate naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond),
      to: Thirteen

    defdelegate naive_datetime_from_iso_days(iso_days), to: Thirteen
    defdelegate day_rollover_relative_to_midnight_utc, to: Thirteen
    defdelegate date_to_string(year, month, day), to: Thirteen

    def shift_date(year, month, day, duration),
      do: Shift.date(__MODULE__, year, month, day, duration)

    def month_of_year(year, month, _day) do
      cond do
        month <= 5 -> month
        months_in_year(year) == 12 -> month + 1
        month == 7 -> {7, :leap}
        true -> month
      end
    end
  end

  # A calendar of weeks, as Calendrical's week calendars are: a date is its
  # year, its week and its day of the week, every year has 52 weeks, and a
  # date's month is the period of weeks its week falls in, four, four and
  # five to each quarter. It shifts a date by months from its week of the
  # period, and by years from its week, as Calendrical's week calendars do.
  defmodule Weeks do
    @moduledoc false
    use Localize.Test.StandInCalendar

    @epoch 700_000

    def months_in_year(_year), do: 12
    def valid_date?(year, week, day), do: year >= 1 and week in 1..52 and day in 1..7
    def quarter_of_year(_year, week, _day), do: div(week - 1, 13) + 1

    def month_of_year(_year, week, _day) do
      week_of_quarter = rem(week - 1, 13)
      div(week - 1, 13) * 3 + min(div(week_of_quarter, 4), 2) + 1
    end

    def shift_date(year, week, day, %Duration{year: years, month: months, week: 0, day: 0}) do
      month = month_of_year(year, week, day)
      months_on = (year + years) * 12 + month - 1 + months
      to_month = Integer.mod(months_on, 12) + 1
      week_of_month = min(week - first_week(month), weeks_in(to_month) - 1)
      {Integer.floor_div(months_on, 12), first_week(to_month) + week_of_month, day}
    end

    defp first_week(month), do: div(month - 1, 3) * 13 + rem(month - 1, 3) * 4 + 1
    defp weeks_in(month), do: if(rem(month - 1, 3) == 2, do: 5, else: 4)

    def day_of_week(year, week, day, starting_on) do
      {days, _fraction} = naive_datetime_to_iso_days(year, week, day, 0, 0, 0, {0, 0})
      {iso_year, iso_month, iso_day} = Calendar.ISO.date_from_iso_days(days)
      Calendar.ISO.day_of_week(iso_year, iso_month, iso_day, starting_on)
    end

    def naive_datetime_to_iso_days(year, week, day, hour, minute, second, microsecond) do
      days = @epoch + (year - 1) * 364 + (week - 1) * 7 + day - 1
      {days, Calendar.ISO.time_to_day_fraction(hour, minute, second, microsecond)}
    end

    def naive_datetime_from_iso_days({days, fraction}) do
      days = days - @epoch
      {hour, minute, second, microsecond} = Calendar.ISO.time_from_day_fraction(fraction)

      {div(days, 364) + 1, div(rem(days, 364), 7) + 1, rem(days, 7) + 1, hour, minute, second,
       microsecond}
    end

    def date_to_string(year, week, day), do: "#{year}-W#{week}-#{day}"
  end

  # A calendar whose day begins at noon, which no date of another calendar
  # converts into.
  defmodule Noon do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def day_rollover_relative_to_midnight_utc, do: {1, 2}
  end

  describe "to_string/2 with integer offsets" do
    test "yesterday" do
      assert {:ok, "yesterday"} = Relative.to_string(-1, unit: :day, locale: :en)
    end

    test "today" do
      assert {:ok, "today"} = Relative.to_string(0, unit: :day, locale: :en)
    end

    test "tomorrow" do
      assert {:ok, "tomorrow"} = Relative.to_string(1, unit: :day, locale: :en)
    end

    test "days ago" do
      assert {:ok, "3 days ago"} = Relative.to_string(-3, unit: :day, locale: :en)
    end

    test "in days" do
      assert {:ok, "in 5 days"} = Relative.to_string(5, unit: :day, locale: :en)
    end

    test "last week" do
      assert {:ok, "last week"} = Relative.to_string(-1, unit: :week, locale: :en)
    end

    test "next month" do
      assert {:ok, "next month"} = Relative.to_string(1, unit: :month, locale: :en)
    end

    test "in hours" do
      assert {:ok, "in 2 hours"} = Relative.to_string(2, unit: :hour, locale: :en)
    end

    test "minutes ago" do
      assert {:ok, "5 minutes ago"} = Relative.to_string(-5, unit: :minute, locale: :en)
    end
  end

  describe "to_string/2 with weekday units" do
    test "last Wednesday" do
      assert {:ok, "last Wednesday"} = Relative.to_string(-1, unit: :wed, locale: :en)
    end

    test "next Monday" do
      assert {:ok, "next Monday"} = Relative.to_string(1, unit: :mon, locale: :en)
    end
  end

  describe "to_string/2 with locales" do
    test "French relative" do
      assert {:ok, "le mois dernier"} = Relative.to_string(-1, unit: :month, locale: :fr)
    end

    test "French last Monday" do
      assert {:ok, "lundi dernier"} = Relative.to_string(-1, unit: :mon, locale: :fr)
    end

    test "German yesterday" do
      assert {:ok, "gestern"} = Relative.to_string(-1, unit: :day, locale: :de)
    end
  end

  describe "to_string/2 with Date structs" do
    test "relative dates with specified unit" do
      assert {:ok, result} = Relative.to_string(@date, relative_to: @relative_to, unit: :day)
      assert String.contains?(result, "12")
      assert String.contains?(result, "day")
    end

    test "relative dates auto-derive unit" do
      assert {:ok, result} = Relative.to_string(@date, relative_to: @relative_to)
      assert String.contains?(result, "week")
    end
  end

  # A difference is counted in calendar periods from the clock's fields:
  # from 11:52 to 18:11 is seven hours of the clock, 11 to 18, as from late
  # on Monday to early on Wednesday is two days.
  describe "to_string/2 with Time structs" do
    test "relative time with unit" do
      assert {:ok, "in 7 hours"} =
               Relative.to_string(@time, relative_to: @relative_time_to, unit: :hour)
    end

    test "relative time auto-derive" do
      assert {:ok, "in 7 hours"} = Relative.to_string(@time, relative_to: @relative_time_to)
    end
  end

  describe "to_string/2 with DateTime structs" do
    test "relative datetime with unit" do
      assert {:ok, result} =
               Relative.to_string(@datetime,
                 relative_to: @relative_datetime_to,
                 unit: :day
               )

      assert String.contains?(result, "12")
      assert String.contains?(result, "day")
    end

    test "relative datetime auto-derive" do
      assert {:ok, result} =
               Relative.to_string(@datetime, relative_to: @relative_datetime_to)

      assert String.contains?(result, "week")
    end
  end

  describe "to_string/2 with short format" do
    test "short format" do
      assert {:ok, result} = Relative.to_string(-3, unit: :day, locale: :en, format: :short)
      assert String.contains?(result, "3")
    end

    test "narrow format" do
      assert {:ok, result} = Relative.to_string(-3, unit: :day, locale: :en, format: :narrow)
      assert String.contains?(result, "3")
    end
  end

  describe "to_string/2 error cases" do
    test "invalid unit" do
      assert {:error, _} = Relative.to_string(1, unit: :ziggeraut, locale: :en)
    end

    test "invalid format" do
      assert {:error, _} = Relative.to_string(1, unit: :day, format: :bogus, locale: :en)
    end
  end

  describe "to_string!/2" do
    test "returns string directly" do
      assert "yesterday" = Relative.to_string!(-1, unit: :day, locale: :en)
    end

    test "raises on error" do
      assert_raise Localize.InvalidValueError, fn ->
        Relative.to_string!(1, unit: :ziggeraut, locale: :en)
      end
    end
  end

  describe "to_string/2 automatic unit selection boundaries" do
    test "seconds up to one minute" do
      assert {:ok, "in 30 seconds"} = Relative.to_string(30, locale: :en)
      assert {:ok, "in 59 seconds"} = Relative.to_string(59, locale: :en)
    end

    # Counted to the nearest, a half away from zero: 90 seconds is 1.5
    # minutes.
    test "minutes from 60 seconds up to one hour" do
      assert {:ok, "in 1 minute"} = Relative.to_string(60, locale: :en)
      assert {:ok, "in 2 minutes"} = Relative.to_string(90, locale: :en)
      assert {:ok, "2 minutes ago"} = Relative.to_string(-90, locale: :en)
      assert {:ok, "in 60 minutes"} = Relative.to_string(3599, locale: :en)
    end

    test "hours from one hour up to one day" do
      assert {:ok, "in 1 hour"} = Relative.to_string(3600, locale: :en)
      assert {:ok, "in 24 hours"} = Relative.to_string(86_399, locale: :en)
    end

    test "days from one day up to one week" do
      assert {:ok, "tomorrow"} = Relative.to_string(86_400, locale: :en)
      assert {:ok, "in 7 days"} = Relative.to_string(604_799, locale: :en)
    end

    test "weeks from one week up to one month" do
      assert {:ok, "next week"} = Relative.to_string(604_800, locale: :en)
      assert {:ok, "in 4 weeks"} = Relative.to_string(2_629_743, locale: :en)
    end

    # A number of seconds has no calendar, so it is never counted in months
    # or years, which have no fixed length: 2,629,744 seconds is 4.35 weeks
    # and 31,556,926 seconds 52.18.
    test "weeks are the largest unit a number of seconds reaches" do
      assert {:ok, "in 4 weeks"} = Relative.to_string(2_629_744, locale: :en)
      assert {:ok, "in 52 weeks"} = Relative.to_string(31_556_926, locale: :en)
    end

    # 604,800 × 10⁴⁰⁰ seconds is 10⁴⁰⁰ weeks, a number no float can hold:
    # "10" and then 133 groups of three zeros.
    test "a number of seconds beyond the range of a float" do
      weeks = "10" <> String.duplicate(",000", 133)

      assert Relative.to_string(604_800 * 10 ** 400, locale: :en) == {:ok, "in #{weeks} weeks"}
      assert Relative.to_string(-604_800 * 10 ** 400, locale: :en) == {:ok, "#{weeks} weeks ago"}
    end

    test "negative offsets select past forms" do
      assert {:ok, "45 seconds ago"} = Relative.to_string(-45, locale: :en)
      assert {:ok, "2 hours ago"} = Relative.to_string(-7200, locale: :en)
    end
  end

  describe "to_string/2 input type coverage" do
    test "a float with a unit is a count of that unit" do
      assert {:ok, "in 90.5 minutes"} = Relative.to_string(90.5, unit: :minute, locale: :en)
    end

    test "NaiveDateTime with a NaiveDateTime relative_to" do
      assert {:ok, "30 seconds ago"} =
               Relative.to_string(~N[2024-06-01 10:00:00],
                 relative_to: ~N[2024-06-01 10:00:30]
               )
    end

    test "Date pairs auto-derive a day unit" do
      assert {:ok, "5 days ago"} =
               Relative.to_string(~D[2024-06-10], relative_to: ~D[2024-06-15])
    end
  end

  describe "to_string/2 with quarter and weekday plurals" do
    test "quarter ordinal and plural forms" do
      assert {:ok, "last quarter"} = Relative.to_string(-1, unit: :quarter, locale: :en)
      assert {:ok, "in 2 quarters"} = Relative.to_string(2, unit: :quarter, locale: :en)
    end

    test "weekday units pluralize beyond the ordinal window" do
      assert {:ok, "in 2 Mondays"} = Relative.to_string(2, unit: :mon, locale: :en)
      assert {:ok, "3 Sundays ago"} = Relative.to_string(-3, unit: :sun, locale: :en)
    end

    test "zero offset uses the current-period ordinal" do
      assert {:ok, "this week"} = Relative.to_string(0, unit: :week, locale: :en)
    end
  end

  # A difference is counted in quarters of three months, and in calendar
  # weeks for a weekday unit, each week starting on the locale's first day:
  # CLDR's week data starts the United States' weeks on Sunday and the
  # United Kingdom's on Monday. The strings are CLDR's `en` names.
  describe "a date difference in quarters and weekday units" do
    test "quarters" do
      assert Relative.to_string(~D[2026-10-01],
               relative_to: ~D[2026-07-01],
               unit: :quarter,
               locale: :en
             ) == {:ok, "next quarter"}

      assert Relative.to_string(~D[2026-01-01],
               relative_to: ~D[2026-07-01],
               unit: :quarter,
               locale: :en
             ) == {:ok, "2 quarters ago"}
    end

    test "weekdays count calendar weeks" do
      for {date, expected} <- [
            {~D[2026-07-13], "next Monday"},
            {~D[2026-06-29], "last Monday"},
            {~D[2026-07-20], "in 2 Mondays"},
            {~D[2026-07-08], "this Monday"}
          ] do
        assert Relative.to_string(date, relative_to: ~D[2026-07-06], unit: :mon, locale: :en) ==
                 {:ok, expected}
      end
    end

    test "a week starts on the locale's first day" do
      assert Relative.to_string(~D[2026-07-13],
               relative_to: ~D[2026-07-12],
               unit: :mon,
               locale: :"en-US"
             ) == {:ok, "this Monday"}

      assert Relative.to_string(~D[2026-07-13],
               relative_to: ~D[2026-07-12],
               unit: :mon,
               locale: :"en-GB"
             ) == {:ok, "next Monday"}
    end

    test "a date-time counts by its date" do
      assert Relative.to_string(~N[2026-07-13 09:00:00],
               relative_to: ~N[2026-07-06 18:00:00],
               unit: :fri,
               locale: :en
             ) == {:ok, "next Friday"}

      assert Relative.to_string(~U[2026-07-13 09:00:00Z],
               relative_to: ~U[2026-07-06 18:00:00Z],
               unit: :fri,
               locale: :en
             ) == {:ok, "next Friday"}
    end

    test "times have no weeks between them" do
      assert Relative.to_string(~T[10:00:00], relative_to: ~T[09:00:00], unit: :mon, locale: :en) ==
               {:ok, "this Monday"}
    end

    test "to_parts/2 agrees" do
      assert Relative.to_parts(~D[2026-10-01],
               relative_to: ~D[2026-07-01],
               unit: :quarter,
               locale: :en
             ) == {:ok, [%{type: :literal, value: "next quarter"}]}
    end
  end

  # A difference is counted with the calendar's arithmetic in its periods:
  # "next month" is any day of the next month and "this year" any day of the
  # year, never a number of seconds divided by an average month or year.
  describe "calendar arithmetic" do
    test "a unit's periods at their boundaries" do
      for {relative, relative_to, unit, expected} <- [
            {~D[2026-01-31], ~D[2026-01-01], :month, "this month"},
            {~D[2026-02-01], ~D[2026-01-31], :month, "next month"},
            {~D[2026-12-31], ~D[2026-01-01], :year, "this year"},
            {~D[2027-01-01], ~D[2026-12-31], :year, "next year"},
            {~D[2026-07-01], ~D[2026-06-30], :quarter, "next quarter"},
            {~D[2026-09-30], ~D[2026-07-01], :quarter, "this quarter"},
            {~N[2026-07-02 01:00:00], ~N[2026-07-01 23:00:00], :day, "tomorrow"},
            {~N[2026-07-01 01:00:00], ~N[2026-06-30 23:00:00], :month, "next month"}
          ] do
        assert Relative.to_string(relative, relative_to: relative_to, unit: unit, locale: :en) ==
                 {:ok, expected},
               "#{inspect(relative)} against #{inspect(relative_to)} in #{unit}"
      end
    end

    # The largest unit of which a whole one lies between them, counted in
    # its periods: from 25 January to 6 March is a whole month, and March is
    # two months on. A day of the month is clamped to a shorter month, so 31
    # January to 28 February is a whole month, and 29 February 2024 to 28
    # February 2025 a whole year.
    test "the unit chosen" do
      for {relative, relative_to, expected} <- [
            {~D[2026-02-03], ~D[2026-01-25], "next week"},
            {~D[2026-02-01], ~D[2026-01-25], "next week"},
            {~D[2026-01-31], ~D[2026-01-25], "in 6 days"},
            {~D[2026-03-06], ~D[2026-01-25], "in 2 months"},
            {~D[2026-04-01], ~D[2026-01-31], "in 3 months"},
            {~D[2026-02-28], ~D[2026-01-31], "next month"},
            {~D[2026-02-27], ~D[2026-01-31], "in 4 weeks"},
            {~D[2025-02-28], ~D[2024-02-29], "next year"},
            {~N[2026-07-01 10:01:10], ~N[2026-07-01 10:00:50], "in 20 seconds"},
            {~D[2027-01-01], ~D[2026-12-31], "tomorrow"},
            {~D[2026-12-31], ~D[2026-01-01], "in 11 months"},
            {~D[2027-01-02], ~D[2026-01-01], "next year"},
            {~D[2025-11-15], ~D[2026-01-01], "2 months ago"},
            {~D[2026-07-01], ~D[2026-07-01], "today"},
            {~N[2026-07-02 01:00:00], ~N[2026-07-01 23:00:00], "in 2 hours"},
            {~N[2026-07-01 10:00:30], ~N[2026-07-01 10:00:00], "in 30 seconds"}
          ] do
        assert Relative.to_string(relative, relative_to: relative_to, locale: :en) ==
                 {:ok, expected},
               "#{inspect(relative)} against #{inspect(relative_to)}"
      end
    end

    # In a year of thirteen months, the thirteenth is followed by the next
    # year's first: "next month", where twelve months to a year would make
    # it this month. Year 3 has thirteen months, so from the twelfth month of
    # year 2 to the first of year 4 is 0 + 13 + 1 months.
    test "months of a calendar whose years have thirteen" do
      month_13 = Date.new!(3, 13, 20, Thirteen)
      next_january = Date.new!(4, 1, 20, Thirteen)

      assert Relative.to_string(next_january, relative_to: month_13, unit: :month, locale: :en) ==
               {:ok, "next month"}

      assert Relative.to_string(next_january, relative_to: month_13, locale: :en) ==
               {:ok, "next month"}

      assert Relative.to_string(month_13,
               relative_to: Date.new!(3, 12, 20, Thirteen),
               locale: :en
             ) ==
               {:ok, "next month"}

      assert Relative.to_string(Date.new!(4, 1, 15, Thirteen),
               relative_to: Date.new!(2, 12, 15, Thirteen),
               unit: :month,
               locale: :en
             ) == {:ok, "in 14 months"}

      assert Relative.to_string(Date.new!(4, 1, 15, Thirteen),
               relative_to: Date.new!(2, 12, 15, Thirteen),
               unit: :quarter,
               locale: :en
             ) == {:ok, "in 5 quarters"}

      # The thirteenth month is clamped to the twelfth in a year of twelve,
      # so from it to the twelfth month of the next year is a whole year.
      assert Relative.to_string(Date.new!(4, 12, 20, Thirteen),
               relative_to: month_13,
               locale: :en
             ) ==
               {:ok, "next year"}
    end

    # A baseline in another calendar is taken into the value's before its
    # periods are counted: the ISO date of the thirteenth month is a month
    # before the next year's first.
    test "a baseline in another calendar" do
      month_13 = Date.new!(3, 13, 20, Thirteen)
      {:ok, iso_month_13} = Date.convert(month_13, Calendar.ISO)

      naive = %NaiveDateTime{
        year: 4,
        month: 1,
        day: 20,
        hour: 10,
        minute: 0,
        second: 0,
        microsecond: {0, 0},
        calendar: Thirteen
      }

      {:ok, iso_naive} = NaiveDateTime.convert(%{naive | year: 3, month: 13}, Calendar.ISO)

      assert Relative.to_string(Date.new!(4, 1, 20, Thirteen),
               relative_to: iso_month_13,
               unit: :month,
               locale: :en
             ) == {:ok, "next month"}

      assert Relative.to_string(naive, relative_to: iso_naive, unit: :month, locale: :en) ==
               {:ok, "next month"}
    end

    # 08:00 on 2 July in Tokyo is 23:00 UTC on 1 July, an hour after the
    # baseline: counted on Tokyo's wall clock, it is an hour away and the
    # same day.
    test "a date-time baseline on the value's wall clock" do
      tokyo = DateTime.new!(~D[2026-07-02], ~T[08:00:00], "Asia/Tokyo")

      assert Relative.to_string(tokyo, relative_to: ~U[2026-07-01 22:00:00Z], locale: :en) ==
               {:ok, "in 1 hour"}

      assert Relative.to_string(tokyo,
               relative_to: ~U[2026-07-01 22:00:00Z],
               unit: :day,
               locale: :en
             ) == {:ok, "today"}
    end

    # A fixed offset, as parsing "GMT-4" gives, is the same instant as the
    # UTC baseline four hours later on the clock. 10 PM on 1 July at GMT-4 is
    # 02:00 UTC on 2 July, and a baseline an hour before it is the same day
    # on the value's clock.
    test "a date-time at a fixed offset" do
      {:ok, fixed} = Localize.DateTime.parse("July 1, 2026 at 10:00:00 AM GMT-4", locale: :en)
      {:ok, late} = Localize.DateTime.parse("July 1, 2026 at 10:00:00 PM GMT-4", locale: :en)

      assert Relative.to_string(fixed, relative_to: ~U[2026-07-01 14:00:00Z], locale: :en) ==
               {:ok, "now"}

      assert Relative.to_string(late,
               relative_to: ~U[2026-07-02 01:00:00Z],
               unit: :day,
               locale: :en
             ) == {:ok, "today"}

      # Noon on 2 July at GMT+5 is 26 hours after 10:00 on 1 July there: a
      # whole day, with no change of offset to resolve a time across.
      {:ok, east} = Localize.DateTime.parse("July 2, 2026 at 12:00:00 PM GMT+5", locale: :en)

      assert Relative.to_string(east, relative_to: ~U[2026-07-01 05:00:00Z], locale: :en) ==
               {:ok, "tomorrow"}
    end

    # On 8 March 2026 New York's clocks go from 02:00 to 03:00, and on 1
    # November from 02:00 back to 01:00. Hours, minutes and seconds count the
    # time that passes: 01:50 to 03:10 on the first is 20 minutes, crossing
    # the hour at 03:00, and 01:50 before the change to 01:10 after it on the
    # second is 20 minutes on, crossing the hour at the second 01:00. Days are
    # counted on the wall clock, so noon to noon over the change is a day of
    # 23 hours, and 23:30 the evening before is the day before, though at
    # the later offset it would be past midnight.
    test "across a change of UTC offset" do
      spring_before = DateTime.new!(~D[2026-03-08], ~T[01:50:00], "America/New_York")
      spring_after = DateTime.new!(~D[2026-03-08], ~T[03:10:00], "America/New_York")

      {:ambiguous, fall_before, _standard} =
        DateTime.new(~D[2026-11-01], ~T[01:50:00], "America/New_York")

      {:ambiguous, _daylight, fall_after} =
        DateTime.new(~D[2026-11-01], ~T[01:10:00], "America/New_York")

      noon_before = DateTime.new!(~D[2026-03-07], ~T[12:00:00], "America/New_York")
      noon_after = DateTime.new!(~D[2026-03-08], ~T[12:00:00], "America/New_York")
      late_before = DateTime.new!(~D[2026-03-07], ~T[23:30:00], "America/New_York")

      assert DateTime.diff(spring_after, spring_before, :minute) == 20
      assert DateTime.diff(fall_after, fall_before, :minute) == 20
      assert DateTime.diff(noon_after, noon_before, :hour) == 23

      for {relative, relative_to, unit, expected} <- [
            {spring_after, spring_before, nil, "in 20 minutes"},
            {spring_after, spring_before, :hour, "in 1 hour"},
            {spring_after, spring_before, :second, "in 1,200 seconds"},
            {spring_before, spring_after, nil, "20 minutes ago"},
            {fall_after, fall_before, nil, "in 20 minutes"},
            {fall_after, fall_before, :hour, "in 1 hour"},
            {fall_before, fall_after, nil, "20 minutes ago"},
            {fall_after, fall_before, :day, "today"},
            {noon_after, noon_before, nil, "tomorrow"},
            {noon_after, noon_before, :hour, "in 23 hours"},
            {noon_after, late_before, :day, "tomorrow"}
          ] do
        assert Relative.to_string(relative,
                 relative_to: relative_to,
                 unit: unit,
                 locale: :en
               ) == {:ok, expected},
               "#{inspect(relative)} against #{inspect(relative_to)} in #{inspect(unit)}"
      end
    end

    # The unit chosen across a change of UTC offset is the one ECMA-262
    # Temporal's DifferenceZonedDateTime gives: a day is whole once the wall
    # clock is at or past the earlier time and that time, resolved as
    # `compatible` (a skipped time at the offset before the gap), has passed.
    # 02:30 on 8 March 2026 is skipped in New York and taken as 03:30, so at
    # 03:10 a day from 02:30 the day before is not yet whole (PT23H40M), and
    # at 03:40 it is (P1DT10M). A month from 02:30 on 8 February is likewise
    # short at 03:10 on 8 March, four weeks (P27DT23H40M). At 01:55 in the
    # first occurrence of the repeated hour on 1 November, a day from 01:50
    # has passed (P1DT5M); at 01:10 in the second, the wall clock is short of
    # 01:50 (PT24H20M; ICU, which reaches the first 01:50, has a day). Samoa
    # skipped 30 December 2011, so 10:00 on the 29th to 09:00 on the 31st is
    # 23 hours (PT23H).
    test "a whole unit across a change of UTC offset" do
      new_york = fn date, time -> DateTime.new!(date, time, "America/New_York") end

      before_fall_back = new_york.(~D[2026-10-31], ~T[01:50:00])

      {:ambiguous, first_occurrence, _standard} =
        DateTime.new(~D[2026-11-01], ~T[01:55:00], "America/New_York")

      {:ambiguous, _daylight, after_fall_back} =
        DateTime.new(~D[2026-11-01], ~T[01:10:00], "America/New_York")

      samoa_before = DateTime.new!(~D[2011-12-29], ~T[10:00:00], "Pacific/Apia")
      samoa_after = DateTime.new!(~D[2011-12-31], ~T[09:00:00], "Pacific/Apia")

      for {relative, relative_to, unit, expected} <- [
            {new_york.(~D[2026-03-08], ~T[03:10:00]), new_york.(~D[2026-03-07], ~T[02:30:00]),
             nil, "in 24 hours"},
            {new_york.(~D[2026-03-08], ~T[03:10:00]), new_york.(~D[2026-03-07], ~T[02:30:00]),
             :day, "tomorrow"},
            {new_york.(~D[2026-03-08], ~T[03:40:00]), new_york.(~D[2026-03-07], ~T[02:30:00]),
             nil, "tomorrow"},
            {new_york.(~D[2026-03-07], ~T[02:30:00]), new_york.(~D[2026-03-08], ~T[03:10:00]),
             nil, "24 hours ago"},
            {after_fall_back, before_fall_back, nil, "in 25 hours"},
            {first_occurrence, before_fall_back, nil, "tomorrow"},
            {new_york.(~D[2026-03-08], ~T[03:10:00]), new_york.(~D[2026-02-08], ~T[02:30:00]),
             nil, "in 4 weeks"},
            {samoa_after, samoa_before, nil, "in 23 hours"},
            {samoa_after, samoa_before, :day, "in 2 days"}
          ] do
        assert Relative.to_string(relative, relative_to: relative_to, unit: unit, locale: :en) ==
                 {:ok, expected},
               "#{inspect(relative)} against #{inspect(relative_to)} in #{inspect(unit)}"
      end
    end

    # A lunisolar year is whole on the month of the same name, as Temporal's
    # month codes have it, not the month in the same place: a month after a
    # leap month sits one place later. A leap month the next year lacks is the
    # ordinary month it doubles (Temporal's skip-backward, M05L to M05), and
    # Adar the leap year's Adar II (M06 in both). Year 3 has thirteen months.
    test "a lunisolar year ends on the month of the same name" do
      for {calendar, {relative_year, relative_month, relative_day}, {year, month, day}, expected} <-
            [
              {Intercalary, {4, 7, 10}, {3, 8, 10}, "next year"},
              {Intercalary, {3, 8, 9}, {2, 7, 10}, "in 13 months"},
              {Intercalary, {4, 5, 10}, {3, 6, 10}, "next year"},
              {Intercalary, {4, 5, 9}, {3, 6, 10}, "in 12 months"},
              {Adar, {4, 6, 15}, {3, 7, 10}, "next year"},
              {Adar, {3, 6, 15}, {2, 6, 10}, "in 12 months"},
              {Adar, {3, 7, 20}, {2, 7, 10}, "in 12 months"},
              {Adar, {4, 6, 10}, {3, 6, 10}, "next year"}
            ] do
        relative = Date.new!(relative_year, relative_month, relative_day, calendar)
        relative_to = Date.new!(year, month, day, calendar)

        assert Relative.to_string(relative, relative_to: relative_to, locale: :en) ==
                 {:ok, expected},
               "#{inspect(relative)} against #{inspect(relative_to)}"
      end
    end

    # A week calendar's month is a period of its weeks, which its week field
    # does not count: from the tenth week, in the third month, 300 days on is
    # the first week of the next year, ten months on, where the week fields
    # would count three. Year 1's 50th week is in its twelfth month.
    test "a week calendar counts its months as periods of weeks" do
      week_10 = Date.new!(2, 10, 3, Weeks)

      assert Relative.to_string(Date.add(week_10, 300), relative_to: week_10, locale: :en) ==
               {:ok, "in 10 months"}

      assert Relative.to_string(Date.add(week_10, -40), relative_to: week_10, locale: :en) ==
               {:ok, "2 months ago"}

      assert Relative.to_string(Date.add(week_10, 364), relative_to: week_10, locale: :en) ==
               {:ok, "next year"}

      assert Relative.to_string(Date.new!(3, 2, 1, Weeks),
               relative_to: Date.new!(1, 50, 1, Weeks),
               unit: :month,
               locale: :en
             ) == {:ok, "in 13 months"}
    end

    test "a baseline in a calendar the value's cannot take" do
      noon = %Date{year: 1, month: 1, day: 1, calendar: Noon}

      assert {:error, %Localize.InvalidValueError{}} =
               Relative.to_string(~D[2026-07-01], relative_to: noon, locale: :en)
    end
  end

  describe "to_string/2 narrow and short exact forms" do
    test "narrow forms abbreviate the unit" do
      assert {:ok, "3d ago"} = Relative.to_string(-3, unit: :day, locale: :en, format: :narrow)
      assert {:ok, "in 2h"} = Relative.to_string(2, unit: :hour, locale: :en, format: :narrow)
    end

    test "short forms use abbreviated unit names" do
      assert {:ok, "in 3 mo."} =
               Relative.to_string(3, unit: :month, locale: :en, format: :short)

      assert {:ok, "2 wk. ago"} =
               Relative.to_string(-2, unit: :week, locale: :en, format: :short)
    end
  end

  describe "to_string/2 locale validation" do
    test "invalid locale returns an error tuple" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Relative.to_string(1, unit: :day, locale: "zz-invalid!")
    end
  end

  describe "to_string/2 with numeric: :always" do
    test "forces numeric output inside the named-form window" do
      assert {:ok, "1 day ago"} =
               Relative.to_string(-1, unit: :day, locale: :en, numeric: :always)

      assert {:ok, "in 1 day"} = Relative.to_string(1, unit: :day, locale: :en, numeric: :always)

      assert {:ok, "in 2 days"} =
               Relative.to_string(2, unit: :day, locale: :en, numeric: :always)
    end

    test "zero formats with the future pattern per ECMA-402" do
      assert {:ok, "in 0 days"} = Relative.to_string(0, unit: :day, locale: :en, numeric: :always)
    end

    test "numeric: :auto keeps named forms" do
      assert {:ok, "yesterday"} = Relative.to_string(-1, unit: :day, locale: :en, numeric: :auto)
      assert {:ok, "today"} = Relative.to_string(0, unit: :day, locale: :en)
    end

    test "applies in other locales" do
      assert {:ok, "il y a 1 jour"} =
               Relative.to_string(-1, unit: :day, locale: :fr, numeric: :always)
    end

    test "an invalid numeric value is an error" do
      assert {:error, %Localize.InvalidValueError{}} =
               Relative.to_string(1, unit: :day, numeric: :sometimes)
    end
  end

  describe "known_units/0" do
    test "returns expected units" do
      units = Relative.known_units()
      assert :day in units
      assert :hour in units
      assert :minute in units
      assert :second in units
      assert :week in units
      assert :month in units
      assert :year in units
      assert :mon in units
      assert :wed in units
      assert :quarter in units
    end
  end
end
