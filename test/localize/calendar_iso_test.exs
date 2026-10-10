defmodule Localize.CalendarISOTest do
  @moduledoc """
  `Localize.Calendar.ISO` answers the whole Calendrical behaviour for
  `Calendar.ISO`, which has none of its callbacks, so that every question
  Localize puts to a calendar goes to a calendar module (user, 2026-10-02).
  Localize does not depend on Calendrical, so the behaviour's callbacks are
  listed here; Calendrical's own tests hold the module to the behaviour
  itself and to `Calendrical.ISO`'s answers.

  The expected values are Elixir's: `Date` and `Calendar.ISO` give a
  period's days, `Date.shift/2` the date a number of months or years on,
  with the day brought into a shorter month, and Erlang's
  `:calendar.iso_week_number/1` the ISO 8601 weeks. The weeks themselves are
  covered in `Localize.CalendarISOWeeksTest`.

  """

  use ExUnit.Case, async: true

  alias Localize.Calendar.ISO

  # The callbacks of the Calendrical behaviour, as Calendrical 1.4 declares
  # them.
  @calendrical_callbacks [
    month_of_year: 3,
    cardinal_month: 1,
    cardinal_day: 3,
    numeric_month: 3,
    lunar_month_of_year: 2,
    ordinal_month_from_traditional: 2,
    leap_month: 1,
    traditional_leap_month: 1,
    traditional_months: 1,
    named_month: 2,
    date_from_day_of_year: 2,
    week_of_year: 3,
    iso_week_of_year: 3,
    week_of_month: 3,
    cldr_calendar_type: 0,
    calendar_base: 0,
    periods_in_year: 1,
    weeks_in_year: 1,
    days_in_year: 1,
    days_in_month: 1,
    dates_in_gregorian_year: 3,
    months_in_year: 0,
    era_calendar_type: 0,
    parsing_calendar: 0,
    calendar_year: 3,
    extended_year: 3,
    related_gregorian_year: 3,
    cyclic_year: 3,
    year: 1,
    quarter: 2,
    quadrimester: 2,
    semester: 2,
    month: 2,
    week: 2,
    plus: 6,
    diff: 3
  ]

  @years [-9999, -44, 0, 1, 1900, 2000, 2023, 2024, 2025, 2026, 2027, 2028, 9999, 10_000]

  @dates [
    ~D[2024-01-31],
    ~D[2024-02-29],
    ~D[2024-03-31],
    ~D[2025-02-28],
    ~D[2025-12-31],
    ~D[2026-06-16],
    ~D[2026-10-30],
    ~D[2027-01-01],
    ~D[0001-01-01],
    ~D[-0044-03-15]
  ]

  describe "the behaviours" do
    test "every callback of the Calendrical behaviour is answered" do
      Code.ensure_loaded!(ISO)

      missing =
        for {name, arity} <- @calendrical_callbacks,
            not function_exported?(ISO, name, arity),
            do: {name, arity}

      assert Enum.count(@calendrical_callbacks) == 36
      assert missing == []
    end

    test "every callback of the Calendar behaviour is answered" do
      Code.ensure_loaded!(ISO)

      missing =
        for {name, arity} <- Calendar.behaviour_info(:callbacks),
            not function_exported?(ISO, name, arity),
            do: {name, arity}

      assert missing == []
    end

    test "it is a calendar of months, the Gregorian calendar, read as itself" do
      assert ISO.calendar_base() == :month
      assert ISO.cldr_calendar_type() == :gregorian
      assert ISO.era_calendar_type() == :gregorian
      assert ISO.parsing_calendar() == Calendar.ISO
    end

    test "its twelve months are their own numbering, and no year has a leap month" do
      for year <- @years do
        assert ISO.traditional_months(year) == Enum.to_list(1..12)
        assert ISO.leap_month(year) == nil
        assert ISO.traditional_leap_month(year) == nil

        for month <- 1..12 do
          assert ISO.lunar_month_of_year(year, month) == month
          assert ISO.ordinal_month_from_traditional(year, month) == {:ok, month}
        end

        assert ISO.lunar_month_of_year(year, 13) == {:error, :invalid_month}
        assert ISO.ordinal_month_from_traditional(year, 0) == {:error, :invalid_month}

        assert ISO.ordinal_month_from_traditional(year, {2, :leap}) ==
                 {:error, :invalid_leap_month}
      end
    end

    test "the days of a named month are the month's, and a day of a year is counted from 1 January" do
      for year <- @years do
        for month <- 1..12 do
          first = Date.new!(year, month, 1)
          assert ISO.named_month(year, month) == [Date.range(first, Date.end_of_month(first))]
        end

        assert ISO.named_month(year, 13) == []
        assert ISO.named_month(year, 0) == []

        last = if Calendar.ISO.leap_year?(year), do: 366, else: 365
        assert ISO.date_from_day_of_year(year, 1) == Date.new!(year, 1, 1)
        assert ISO.date_from_day_of_year(year, 60) == Date.add(Date.new!(year, 1, 1), 59)
        assert ISO.date_from_day_of_year(year, last) == Date.new!(year, 12, 31)
        assert ISO.date_from_day_of_year(year, last + 1) == {:error, :invalid_date}
        assert ISO.date_from_day_of_year(year, 0) == {:error, :invalid_date}
      end

      assert ISO.date_from_day_of_year(nil, 1) == {:error, :invalid_date}
      assert ISO.date_from_day_of_year(2026, "1") == {:error, :invalid_date}
    end

    test "a date's day names it, and its month is written with its own number" do
      for %Date{year: year, month: month, day: day} <- @dates do
        assert ISO.cardinal_day(year, month, day) == day
        assert ISO.numeric_month(year, month, day) == month
      end
    end
  end

  describe "the periods of a year" do
    test "a year is its days from 1 January to 31 December" do
      for year <- @years do
        assert ISO.year(year) == Date.range(Date.new!(year, 1, 1), Date.new!(year, 12, 31))
      end
    end

    test "a month is its days from the first to the last" do
      for year <- @years, month <- 1..12 do
        first = Date.new!(year, month, 1)
        assert ISO.month(year, month) == Date.range(first, Date.end_of_month(first))
      end
    end

    # A quarter is three months, a quadrimester four and a semester six,
    # each counted from January: the days of a year that Elixir puts in the
    # quarter (`Date.quarter_of_year/1`), or whose month falls in the third
    # or the half.
    test "a quarter, a quadrimester and a semester are the days of their months" do
      for year <- [2023, 2024, 2026] do
        days = Enum.to_list(ISO.year(year))

        for quarter <- 1..4 do
          assert Enum.to_list(ISO.quarter(year, quarter)) ==
                   Enum.filter(days, &(Date.quarter_of_year(&1) == quarter))
        end

        for quadrimester <- 1..3 do
          assert Enum.to_list(ISO.quadrimester(year, quadrimester)) ==
                   Enum.filter(days, &(div(&1.month - 1, 4) + 1 == quadrimester))
        end

        for semester <- 1..2 do
          assert Enum.to_list(ISO.semester(year, semester)) ==
                   Enum.filter(days, &(div(&1.month - 1, 6) + 1 == semester))
        end
      end
    end

    test "a period the year does not have is an error" do
      assert ISO.month(2026, 0) == {:error, :invalid_date}
      assert ISO.month(2026, 13) == {:error, :invalid_date}
      assert ISO.quarter(2026, 0) == {:error, :invalid_date}
      assert ISO.quarter(2026, 5) == {:error, :invalid_date}
      assert ISO.quadrimester(2026, 4) == {:error, :invalid_date}
      assert ISO.semester(2026, 3) == {:error, :invalid_date}
    end
  end

  describe "the counts of a year" do
    test "its days, months and periods are Calendar.ISO's" do
      for year <- @years do
        assert ISO.days_in_year(year) == Enum.count(ISO.year(year))
        assert ISO.days_in_year(year) == if(Calendar.ISO.leap_year?(year), do: 366, else: 365)
        assert ISO.periods_in_year(year) == Calendar.ISO.months_in_year(year)
      end

      assert ISO.months_in_year() == 12
    end

    # A month's days without a year are the days it has in every year, and
    # February's are one of two.
    test "a month's days without a year are those every year gives it" do
      for month <- 1..12 do
        lengths =
          2021..2024
          |> Enum.map(&Calendar.ISO.days_in_month(&1, month))
          |> Enum.uniq()
          |> Enum.sort()

        expected =
          case lengths do
            [days] -> days
            [fewest, most] -> {:ambiguous, fewest..most}
          end

        assert ISO.days_in_month(month) == expected
      end

      assert ISO.days_in_month(0) == {:error, :undefined}
      assert ISO.days_in_month(13) == {:error, :undefined}
    end

    # 28 December is always in a year's last ISO 8601 week, so its week
    # number is the year's count of weeks, each of seven days.
    test "its weeks are ISO 8601's, 52 or 53 of seven days" do
      for year <- 1995..2035 do
        {^year, weeks} = :calendar.iso_week_number({year, 12, 28})
        assert ISO.weeks_in_year(year) == {weeks, 7}
      end

      assert ISO.weeks_in_year(2026) == {53, 7}
      assert ISO.weeks_in_year(2025) == {52, 7}
    end
  end

  describe "a date's own answers" do
    test "its ISO 8601 week, extended year and place in a Gregorian year" do
      for date <- @dates do
        {year, month, day} = Date.to_erl(date)

        assert ISO.iso_week_of_year(year, month, day) == ISO.week_of_year(year, month, day)
        assert ISO.extended_year(year, month, day) == year
        assert ISO.dates_in_gregorian_year(year, month, day) == [date]
      end

      assert ISO.iso_week_of_year(2027, 1, 1) == :calendar.iso_week_number({2027, 1, 1})
      assert ISO.dates_in_gregorian_year(2025, 2, 29) == []
      assert ISO.dates_in_gregorian_year(2024, 2, 29) == [~D[2024-02-29]]
    end
  end

  describe "plus/6" do
    # `Date.shift/2` is `Calendar.ISO`'s own arithmetic: a month or a year
    # on keeps the day and brings it into a shorter month.
    test "adds years, quarters, months, weeks and days as Date.shift/2 does" do
      for date <- @dates, count <- [-400, -25, -13, -12, -1, 0, 1, 2, 11, 12, 13, 25, 400] do
        {year, month, day} = Date.to_erl(date)

        for {date_part, duration} <- [
              years: [year: count],
              quarters: [month: count * 3],
              months: [month: count],
              weeks: [week: count],
              days: [day: count]
            ] do
          expected = date |> Date.shift(duration) |> Date.to_erl()

          assert ISO.plus(year, month, day, date_part, count, []) == expected,
                 "#{date} #{date_part} #{count}"

          assert ISO.plus(year, month, day, date_part, count, coerce: true) == expected
        end
      end
    end

    test "leaves the day as it stands when asked not to coerce it" do
      assert ISO.plus(2024, 1, 31, :months, 1, coerce: true) == {2024, 2, 29}
      assert ISO.plus(2024, 1, 31, :months, 1, coerce: false) == {2024, 2, 31}
      assert ISO.plus(2024, 2, 29, :years, 1, coerce: true) == {2025, 2, 28}
      assert ISO.plus(2024, 2, 29, :years, 1, coerce: false) == {2025, 2, 29}
    end

    test "has five arguments too, coercing the day" do
      assert ISO.plus(2024, 1, 31, :months, 1) == {2024, 2, 29}
    end
  end

  describe "diff/3" do
    # The whole months, quarters or years from one date to another are the
    # most that `Date.shift/2` adds to the earlier without passing the
    # later, counted here one at a time; weeks and days are the days between.
    test "counts the whole periods Date.shift/2 fits between two dates" do
      for from <- @dates,
          gap <- [
            -800,
            -400,
            -366,
            -365,
            -62,
            -31,
            -30,
            -29,
            -28,
            -1,
            0,
            1,
            27,
            28,
            29,
            30,
            31,
            59,
            62,
            365,
            366,
            400,
            800
          ] do
        to = Date.add(from, gap)
        {earlier, later, sign} = if gap < 0, do: {to, from, -1}, else: {from, to, 1}

        for {date_part, unit, step} <- [
              {:months, :month, 1},
              {:quarters, :month, 3},
              {:years, :year, 1}
            ] do
          whole =
            Stream.iterate(1, &(&1 + 1))
            |> Enum.find(&(Date.compare(Date.shift(earlier, [{unit, &1 * step}]), later) == :gt))
            |> Kernel.-(1)

          assert ISO.diff(Date.to_erl(from), Date.to_erl(to), date_part) == sign * whole,
                 "#{from} to #{to} in #{date_part}"
        end

        assert ISO.diff(Date.to_erl(from), Date.to_erl(to), :days) == gap
        assert ISO.diff(Date.to_erl(from), Date.to_erl(to), :weeks) == sign * div(abs(gap), 7)
      end
    end

    test "from the end of a month" do
      assert ISO.diff({2024, 1, 31}, {2024, 2, 29}, :months) == 1
      assert ISO.diff({2024, 1, 31}, {2024, 2, 28}, :months) == 0
      assert ISO.diff({2024, 2, 29}, {2024, 1, 31}, :months) == -1
      assert ISO.diff({2024, 2, 29}, {2025, 2, 28}, :years) == 1
      assert ISO.diff({2024, 2, 29}, {2025, 2, 27}, :years) == 0
    end
  end

  describe "values that are no date, year or period" do
    test "are errors, never raises" do
      assert ISO.year(nil) == {:error, :invalid_date}
      assert ISO.year("2026") == {:error, :invalid_date}
      assert ISO.month(nil, 1) == {:error, :invalid_date}
      assert ISO.month(2026, nil) == {:error, :invalid_date}
      assert ISO.quarter(nil, 1) == {:error, :invalid_date}
      assert ISO.semester("2026", 1) == {:error, :invalid_date}
      assert ISO.quadrimester(2026, :first) == {:error, :invalid_date}
      assert ISO.days_in_year(nil) == {:error, :invalid_date}
      assert ISO.periods_in_year(nil) == {:error, :invalid_date}
      assert ISO.weeks_in_year("2026") == {:error, :invalid_date}
      assert ISO.days_in_month(nil) == {:error, :undefined}
      assert ISO.dates_in_gregorian_year(nil, 1, 1) == []
      assert ISO.iso_week_of_year(2026, 2, 30) == {:error, :invalid_date}

      assert ISO.plus(nil, 1, 1, :months, 1, []) == {:error, :invalid_date}
      assert ISO.plus(2026, 13, 1, :months, 1, []) == {:error, :invalid_date}
      assert ISO.plus(2026, 1, 1, :months, "1", []) == {:error, :invalid_date}
      assert ISO.plus(2026, 1, 1, :fortnights, 1, []) == {:error, :invalid_date}
      assert ISO.plus(2026, 2, 30, :days, 1, []) == {:error, :invalid_date}

      assert ISO.diff({2026, 2, 30}, {2026, 3, 1}, :months) == {:error, :invalid_date}
      assert ISO.diff({2026, 1, 1}, {2026, 13, 1}, :days) == {:error, :invalid_date}
      assert ISO.diff({nil, 1, 1}, {2026, 3, 1}, :months) == {:error, :invalid_date}
      assert ISO.diff({2026, 1, 1}, {2026, 3, 1}, :fortnights) == {:error, :invalid_date}
      assert ISO.diff(:today, {2026, 3, 1}, :months) == {:error, :invalid_date}
    end
  end
end
