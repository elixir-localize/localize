defmodule Localize.DurationTest do
  use ExUnit.Case, async: true

  doctest Localize.Duration

  alias Localize.Test.{
    LadyDayCalendar,
    NoYearZeroCalendar,
    SequentialShiftCalendar,
    ThirteenMonthCalendar
  }

  # ── new/2 with dates ──────────────────────────────────────────

  describe "new/2 with dates" do
    test "calculates duration between two dates" do
      {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2019-12-31])
      assert d.year == 0
      assert d.month == 11
      assert d.day == 30
    end

    test "calculates duration spanning years" do
      {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2021-06-15])
      assert d.year == 2
      assert d.month == 5
      assert d.day == 14
    end

    test "returns zero duration for same date" do
      {:ok, d} = Localize.Duration.new(~D[2020-06-15], ~D[2020-06-15])
      assert d.year == 0
      assert d.month == 0
      assert d.day == 0
    end

    test "returns error when from is after to" do
      assert {:error, %ArgumentError{}} =
               Localize.Duration.new(~D[2020-01-01], ~D[2019-01-01])
    end
  end

  # ── new/2 with times ──────────────────────────────────────────

  describe "new/2 with times" do
    test "calculates duration between two times" do
      {:ok, d} = Localize.Duration.new(~T[10:00:00], ~T[12:30:45])
      assert d.hour == 2
      assert d.minute == 30
      assert d.second == 45
    end

    test "returns zero duration for same time" do
      {:ok, d} = Localize.Duration.new(~T[12:00:00], ~T[12:00:00])
      assert d.hour == 0
      assert d.minute == 0
      assert d.second == 0
    end

    test "returns error when from is after to" do
      assert {:error, %ArgumentError{}} =
               Localize.Duration.new(~T[12:30:45], ~T[10:00:00])
    end
  end

  # ── new/2 with naive datetimes ─────────────────────────────────

  describe "new/2 with naive datetimes" do
    test "calculates duration between two naive datetimes" do
      {:ok, d} = Localize.Duration.new(~N[2024-01-01 10:00:00], ~N[2024-06-15 12:30:00])
      assert d.year == 0
      assert d.month == 5
      assert d.day == 14
      assert d.hour == 2
      assert d.minute == 30
    end

    test "returns zero duration for equal naive datetimes" do
      {:ok, d} = Localize.Duration.new(~N[2024-01-01 10:00:00], ~N[2024-01-01 10:00:00])
      assert d.year == 0
      assert d.hour == 0
    end

    test "returns error when from is after to" do
      assert {:error, %ArgumentError{}} =
               Localize.Duration.new(~N[2024-06-15 12:30:00], ~N[2024-01-01 10:00:00])
    end
  end

  # ── new/1 with Date.Range ──────────────────────────────────────

  describe "new/1 with Date.Range" do
    test "accepts a Date.Range" do
      {:ok, d} = Localize.Duration.new(Date.range(~D[2019-01-01], ~D[2019-12-31]))
      assert d.month == 11
      assert d.day == 30
    end
  end

  # ── new!/2 ─────────────────────────────────────────────────────

  describe "new!/2" do
    test "returns struct directly" do
      d = Localize.Duration.new!(~D[2019-01-01], ~D[2019-12-31])
      assert d.month == 11
    end

    test "raises on error" do
      assert_raise ArgumentError, fn ->
        Localize.Duration.new!(~D[2020-01-01], ~D[2019-01-01])
      end
    end
  end

  # ── new_from_seconds/1 ─────────────────────────────────────────

  describe "new_from_seconds/1" do
    test "creates duration from integer seconds" do
      d = Localize.Duration.new_from_seconds(136_092)
      assert d.hour == 37
      assert d.minute == 48
      assert d.second == 12
    end

    test "creates duration from float seconds" do
      d = Localize.Duration.new_from_seconds(90.5)
      assert d.minute == 1
      assert d.second == 30
      assert elem(d.microsecond, 0) == 500_000
    end

    test "handles zero seconds" do
      d = Localize.Duration.new_from_seconds(0)
      assert d.hour == 0
      assert d.minute == 0
      assert d.second == 0
    end
  end

  # ── to_string/2 ────────────────────────────────────────────────

  describe "to_string/2" do
    test "formats duration with unit names" do
      {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2019-12-31])
      {:ok, s} = Localize.Duration.to_string(d, locale: :en)
      assert s == "11 months, 30 days"
    end

    test "omits zero parts" do
      d = Localize.Duration.new_from_seconds(3661)
      {:ok, s} = Localize.Duration.to_string(d, locale: :en)
      assert s =~ "hour"
      assert s =~ "minute"
      assert s =~ "second"
      refute s =~ "year"
      refute s =~ "month"
    end

    test "respects :except option" do
      d = Localize.Duration.new_from_seconds(3661)
      {:ok, s} = Localize.Duration.to_string(d, locale: :en, except: [:second, :microsecond])
      assert s =~ "hour"
      assert s =~ "minute"
      refute s =~ "second"
    end
  end

  # ── to_time_string/2 ──────────────────────────────────────────

  describe "to_time_string/2" do
    test "formats h:mm:ss with default pattern" do
      d = Localize.Duration.new_from_seconds(136_092)
      assert {:ok, "37:48:12"} = Localize.Duration.to_time_string(d)
    end

    test "formats with custom pattern" do
      d = Localize.Duration.new_from_seconds(65)
      assert {:ok, "1:05"} = Localize.Duration.to_time_string(d, format: "m:ss")
    end

    test "zero-pads hours with hh" do
      d = Localize.Duration.new_from_seconds(3661)
      assert {:ok, "01:01:01"} = Localize.Duration.to_time_string(d)
    end

    test "no zero-pad with h" do
      d = Localize.Duration.new_from_seconds(3661)
      assert {:ok, "1:01:01"} = Localize.Duration.to_time_string(d, format: "h:mm:ss")
    end

    test "handles zero duration" do
      d = Localize.Duration.new_from_seconds(0)
      assert {:ok, "00:00:00"} = Localize.Duration.to_time_string(d)
    end

    test "a field longer than two letters formats as U+FFFD" do
      d = Localize.Duration.new_from_seconds(136_092)
      assert {:ok, "�:48:12"} = Localize.Duration.to_time_string(d, format: "hhh:mm:ss")
      assert {:ok, "37:�"} = Localize.Duration.to_time_string(d, format: "h:mmm")
      assert {:ok, "37:48:�"} = Localize.Duration.to_time_string(d, format: "h:mm:sss")
    end

    test "single-quoted text is literal per TR35" do
      d = Localize.Duration.new_from_seconds(136_092)
      assert {:ok, "37h 48m"} = Localize.Duration.to_time_string(d, format: "h'h' m'm'")
    end

    test "a doubled quote is a literal quote character" do
      d = Localize.Duration.new_from_seconds(59)
      assert {:ok, "59''"} = Localize.Duration.to_time_string(d, format: "s''''")
    end

    test "an unterminated quote takes the rest of the pattern as literal" do
      d = Localize.Duration.new_from_seconds(59)
      assert {:ok, "59 sec"} = Localize.Duration.to_time_string(d, format: "s' sec")
    end
  end

  # ── to_time_string!/2 ─────────────────────────────────────────

  describe "to_time_string!/2" do
    test "returns string directly" do
      d = Localize.Duration.new_from_seconds(136_092)
      assert "37:48:12" = Localize.Duration.to_time_string!(d)
    end

    test "defaults the options argument" do
      d = Localize.Duration.new_from_seconds(10)
      assert "00:00:10" = Localize.Duration.to_time_string!(d)
    end

    test "single s field renders unpadded seconds" do
      d = Localize.Duration.new_from_seconds(65)
      assert {:ok, "5"} = Localize.Duration.to_time_string(d, format: "s")
    end
  end

  # ── new/2 negative time-of-day carry ──────────────────────────

  describe "new/2 borrows a day when the time of day decreases" do
    test "borrows one day across a month boundary" do
      {:ok, duration} = Localize.Duration.new(~U[2020-01-31 23:00:00Z], ~U[2020-02-01 01:00:00Z])
      assert {duration.year, duration.month, duration.day, duration.hour} == {0, 0, 0, 2}
    end

    # The two below are 722 and 8,738 hours (`DateTime.diff/3`), and each is
    # the span that `DateTime.shift/2` adds to the earlier value to reach the
    # later: 30 days and 2 hours on from 23:00 on 1 March is 01:00 on 1 April.
    test "borrows through day zero into the previous month" do
      {:ok, duration} = Localize.Duration.new(~U[2020-03-01 23:00:00Z], ~U[2020-04-01 01:00:00Z])
      assert {duration.year, duration.month, duration.day, duration.hour} == {0, 0, 30, 2}
    end

    test "borrows through month zero into the previous year" do
      {:ok, duration} = Localize.Duration.new(~U[2021-01-01 23:00:00Z], ~U[2022-01-01 01:00:00Z])
      assert {duration.year, duration.month, duration.day, duration.hour} == {0, 11, 30, 2}
    end
  end

  # ── new/2 day and month borrow on date-only inputs ────────────

  describe "new/2 date borrow arithmetic" do
    test "borrows a month when the from day exceeds the to day" do
      {:ok, duration} = Localize.Duration.new(~D[2020-01-31], ~D[2020-02-01])
      assert {duration.year, duration.month, duration.day} == {0, 0, 1}
    end

    test "borrows a year when the from month exceeds the to month" do
      {:ok, duration} = Localize.Duration.new(~D[2020-11-15], ~D[2021-02-15])
      assert {duration.year, duration.month, duration.day} == {0, 3, 0}
    end
  end

  # ── new/2 counts with the calendar ────────────────────────────

  describe "new/2 counts the calendar's own periods" do
    # The whole months first, and then the days left: five months on from 14
    # January is 14 June, and 13 July is 29 days after it. A day of the month
    # is brought into a shorter month, so 31 January to 29 February is a whole
    # month, and 29 February 2020 to 28 February 2021 a whole year.
    test "the days are those left after the whole months" do
      for {from, to, expected} <- [
            {~D[2023-01-14], ~D[2023-07-13], {0, 5, 29}},
            {~D[2023-01-30], ~D[2023-03-01], {0, 1, 1}},
            {~D[2023-01-31], ~D[2023-03-30], {0, 1, 30}},
            {~D[2024-01-31], ~D[2024-02-29], {0, 1, 0}},
            {~D[2020-02-29], ~D[2021-02-28], {1, 0, 0}},
            {~D[2020-02-29], ~D[2021-03-28], {1, 0, 28}},
            {~D[2020-02-29], ~D[2021-03-29], {1, 1, 0}},
            {~D[2020-02-29], ~D[2021-03-30], {1, 1, 1}},
            {~D[2019-12-31], ~D[2020-01-01], {0, 0, 1}},
            {~D[1999-12-31], ~D[2024-02-29], {24, 2, 0}}
          ] do
        assert {:ok, duration} = Localize.Duration.new(from, to)

        assert {duration.year, duration.month, duration.day} == expected,
               "#{from} to #{to}"
      end
    end

    # A duration is the span `Date.shift/2` adds to the earlier date to reach
    # the later, with the most of each unit that does not pass it. Both are
    # checked against `Date.shift/2` itself.
    test "added to the earlier date it is the later, with the most of each unit" do
      gaps =
        [0, 1, 27, 28, 29, 30, 31, 32, 58, 59, 60, 61, 62, 89, 90, 91, 92] ++
          [364, 365, 366, 367, 400, 730, 731, 1461, 1500]

      for from <- Enum.take_every(Date.range(~D[2023-12-25], ~D[2025-03-05]), 3), gap <- gaps do
        to = Date.add(from, gap)
        assert {:ok, duration} = Localize.Duration.new(from, to)
        %{year: years, month: months, day: days} = duration

        assert years >= 0 and months in 0..11 and days >= 0, "#{from} to #{to}"
        assert Date.shift(from, year: years, month: months, day: days) == to, "#{from} to #{to}"
        assert Date.after?(Date.shift(from, year: years + 1), to), "#{from} to #{to}"

        assert Date.after?(Date.shift(from, year: years, month: months + 1), to),
               "#{from} to #{to}"
      end
    end

    # A date and a time of day: where the later time of day is the earlier
    # of the two, the dates are counted to the day before. 22:00 on 31
    # January to 10:00 on 1 March 2024 is a month, to 22:00 on 29 February,
    # and twelve hours.
    test "a date-time counts its dates to the day before across midnight" do
      assert {:ok, duration} =
               Localize.Duration.new(~N[2024-01-31 22:00:00], ~N[2024-03-01 10:00:00])

      assert {duration.year, duration.month, duration.day, duration.hour} == {0, 1, 0, 12}

      assert NaiveDateTime.shift(~N[2024-01-31 22:00:00], month: 1, hour: 12) ==
               ~N[2024-03-01 10:00:00]
    end

    # The calendar counts, not the dates' fields. In a calendar whose year
    # turns on 25 March, 1 January 2024 is the day after 31 December 2024,
    # and from the year's first day to its last, 25 March 2024 to 24 March
    # 2025 in ISO dates, is eleven months, to 25 February, and 27 days.
    test "a calendar whose fields are not in the order of its days" do
      december = Date.new!(2024, 12, 31, LadyDayCalendar)
      january = Date.new!(2024, 1, 1, LadyDayCalendar)
      first_day = Date.new!(2024, 3, 25, LadyDayCalendar)
      last_day = Date.new!(2024, 3, 24, LadyDayCalendar)

      assert Date.convert!(last_day, Calendar.ISO) == ~D[2025-03-24]

      assert {:ok, %{year: 0, month: 0, day: 1}} = Localize.Duration.new(december, january)
      assert {:ok, %{year: 0, month: 11, day: 27}} = Localize.Duration.new(first_day, last_day)
      assert {:error, %ArgumentError{}} = Localize.Duration.new(january, december)
    end

    # The Julian calendar has no year 0, so 15 June 2 BC to 15 June AD 2 is
    # three years, where the years' numbers are four apart.
    test "a calendar whose years are not numbered one after another" do
      two_bc = Date.new!(-2, 6, 15, NoYearZeroCalendar)
      two_ad = Date.new!(2, 6, 15, NoYearZeroCalendar)

      assert {:ok, %{year: 3, month: 0, day: 0}} = Localize.Duration.new(two_bc, two_ad)
    end

    # A year is not twelve of a calendar's months where its years have
    # thirteen: twelve months on from a year's first day is the first of its
    # thirteenth month, and the year after begins a month later.
    test "a calendar whose years have thirteen months" do
      first = Date.new!(5, 1, 1, ThirteenMonthCalendar)

      assert {:ok, %{year: 0, month: 12, day: 0}} =
               Localize.Duration.new(first, Date.new!(5, 13, 1, ThirteenMonthCalendar))

      assert {:ok, %{year: 1, month: 0, day: 0}} =
               Localize.Duration.new(first, Date.new!(6, 1, 1, ThirteenMonthCalendar))

      assert {:ok, %{year: 1, month: 12, day: 27}} =
               Localize.Duration.new(first, Date.new!(6, 13, 28, ThirteenMonthCalendar))
    end

    # A calendar composes a shift of years and months in its own way, and a
    # duration is the span its own shifting adds. Shifting by the years and
    # then by the months, a year on from 29 February 2020 is 28 February 2021
    # and a month on from there 28 March, so to 30 March is a year, a month
    # and two days. `Calendar.ISO` counts thirteen months on, to 29 March,
    # and has one day. Calendrical's calendars of weeks shift the first way:
    # a year on from week 53 is week 52, and twelve months on is another day.
    test "a calendar that shifts by its years and then by its months" do
      from = Date.new!(2020, 2, 29, SequentialShiftCalendar)
      to = Date.new!(2021, 3, 30, SequentialShiftCalendar)

      assert Date.shift(from, year: 1, month: 1) ==
               Date.new!(2021, 3, 28, SequentialShiftCalendar)

      assert Date.shift(~D[2020-02-29], year: 1, month: 1) == ~D[2021-03-29]

      assert {:ok, %{year: 1, month: 1, day: 2}} = Localize.Duration.new(from, to)

      assert {:ok, %{year: 1, month: 1, day: 1}} =
               Localize.Duration.new(~D[2020-02-29], ~D[2021-03-30])

      for gap <- [0, 1, 27, 28, 29, 30, 31, 59, 60, 365, 366, 367, 395, 396, 397, 730, 1461],
          start <- [~D[2020-02-29], ~D[2020-01-31], ~D[2023-12-31], ~D[2024-08-30]] do
        from = Date.convert!(start, SequentialShiftCalendar)
        to = Date.convert!(Date.add(start, gap), SequentialShiftCalendar)

        assert {:ok, %{year: years, month: months, day: days}} = Localize.Duration.new(from, to)
        assert years >= 0 and months >= 0 and days >= 0

        assert Date.shift(from, year: years, month: months, day: days) == to,
               "#{start} and #{gap} days: #{inspect({years, months, days})}"

        assert Date.diff(Date.shift(from, year: years + 1), to) > 0
        assert Date.diff(Date.shift(from, year: years, month: months + 1), to) > 0
      end
    end

    # The calendar's count of years and months is a first count, which its
    # own shifting settles: a calendar whose `diff/3` is one out either way
    # gives the durations `Calendar.ISO` gives.
    test "a calendar whose count is out is settled by its shifting" do
      defmodule CountsOver do
        @moduledoc false
        use Localize.Test.StandInCalendar

        def diff(from, to, :days), do: Localize.Calendar.ISO.diff(from, to, :days)
        def diff(from, to, part), do: Localize.Calendar.ISO.diff(from, to, part) + 1
      end

      defmodule CountsUnder do
        @moduledoc false
        use Localize.Test.StandInCalendar

        def diff(from, to, :days), do: Localize.Calendar.ISO.diff(from, to, :days)
        def diff(from, to, part), do: max(Localize.Calendar.ISO.diff(from, to, part) - 1, 0)
      end

      for {from, to} <- [
            {~D[2023-01-14], ~D[2023-07-13]},
            {~D[2020-02-29], ~D[2021-03-28]},
            {~D[1999-12-31], ~D[2024-02-29]},
            {~D[2024-01-31], ~D[2024-01-31]}
          ],
          calendar <- [CountsOver, CountsUnder] do
        {:ok, expected} = Localize.Duration.new(from, to)

        assert Localize.Duration.new(Date.convert!(from, calendar), Date.convert!(to, calendar)) ==
                 {:ok, expected},
               "#{inspect(calendar)} from #{from} to #{to}"
      end
    end

    test "a date its calendar does not have, or fields that are not integers, is an error" do
      no_day = %Date{year: 2023, month: 2, day: 30, calendar: Calendar.ISO}
      no_year = %Date{year: nil, month: 2, day: 1, calendar: Calendar.ISO}
      no_hour = %{~N[2023-02-01 10:00:00] | hour: nil}

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Duration.new(no_day, ~D[2023-03-01])

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Duration.new(~D[2023-01-01], no_day)

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Duration.new(no_year, ~D[2023-03-01])

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Duration.new(no_hour, ~N[2023-03-01 00:00:00])
    end
  end

  # ── new/2 between two date-times in time zones ───────────────

  # Two date-times in time zones are measured where the earlier is, as
  # ECMA-262 Temporal measures two zoned date-times and as relative time
  # does (user, 2026-10-02): the later is moved to the earlier's time zone,
  # the years, months and days are counted on that wall clock, and the hours,
  # minutes and seconds are the time that passes after them. The expected
  # durations are those of the specification's `DifferenceZonedDateTime`,
  # taken step by step, and the times that pass are `DateTime.diff/3`'s.
  describe "new/2 between two date-times in time zones" do
    # 10:00 UTC is 15:00 in Karachi, three hours before 18:00 there.
    test "is the time that passes, whatever the two clocks read" do
      utc = ~U[2026-06-15 10:00:00Z]
      karachi = zoned(~D[2026-06-15], ~T[18:00:00], "Asia/Karachi")

      assert DateTime.diff(karachi, utc) == 3 * 3600
      assert parts(Localize.Duration.new(utc, karachi)) == {0, 0, 0, 3, 0, 0}

      assert parts(
               Localize.Duration.new(
                 zoned(~D[2026-06-15], ~T[15:00:00], "Asia/Karachi"),
                 ~U[2026-06-15 13:00:00Z]
               )
             ) == {0, 0, 0, 3, 0, 0}

      assert {:error, %ArgumentError{}} = Localize.Duration.new(karachi, utc)
    end

    # New York's clocks went from 02:00 to 03:00 on 10 March 2024 and from
    # 02:00 back to 01:00 on 3 November, Lord Howe Island's back half an hour
    # on 7 April, and Samoa had no 30 December 2011.
    test "counts a day on the wall clock across a change of clocks" do
      for {from, to, seconds, expected} <- [
            {zoned(~D[2024-03-09], ~T[12:00:00], "America/New_York"),
             zoned(~D[2024-03-10], ~T[12:00:00], "America/New_York"), 23 * 3600,
             {0, 0, 1, 0, 0, 0}},
            {zoned(~D[2024-11-02], ~T[12:00:00], "America/New_York"),
             zoned(~D[2024-11-03], ~T[12:00:00], "America/New_York"), 25 * 3600,
             {0, 0, 1, 0, 0, 0}},
            {zoned(~D[2024-04-06], ~T[12:00:00], "Australia/Lord_Howe"),
             zoned(~D[2024-04-07], ~T[12:00:00], "Australia/Lord_Howe"), 24 * 3600 + 1800,
             {0, 0, 1, 0, 0, 0}},
            {zoned(~D[2011-12-29], ~T[12:00:00], "Pacific/Apia"),
             zoned(~D[2011-12-31], ~T[12:00:00], "Pacific/Apia"), 24 * 3600, {0, 0, 2, 0, 0, 0}}
          ] do
        assert DateTime.diff(to, from) == seconds
        assert parts(Localize.Duration.new(from, to)) == expected, inspect({from, to})
      end
    end

    # 23:00 to 04:00 is five hours on the wall clock and four that pass. A
    # time the clocks skip comes an hour on: 02:30 on 10 March is 03:30, so
    # 02:30 the day before to 03:30 is a day, and to a second short of it is
    # 23 hours 59 minutes 59 seconds.
    test "counts the time that passes across an hour the clocks skip" do
      for {from, to, seconds, expected} <- [
            {{~D[2024-03-09], ~T[23:00:00]}, {~D[2024-03-10], ~T[04:00:00]}, 4 * 3600,
             {0, 0, 0, 4, 0, 0}},
            {{~D[2024-03-08], ~T[02:30:00]}, {~D[2024-03-10], ~T[03:10:00]}, 47 * 3600 + 2400,
             {0, 0, 1, 23, 40, 0}},
            {{~D[2024-03-09], ~T[02:30:00]}, {~D[2024-03-10], ~T[03:30:00]}, 24 * 3600,
             {0, 0, 1, 0, 0, 0}},
            {{~D[2024-03-09], ~T[02:30:00]}, {~D[2024-03-10], ~T[03:29:59]}, 24 * 3600 - 1,
             {0, 0, 0, 23, 59, 59}}
          ] do
        {from_date, from_time} = from
        {to_date, to_time} = to
        from = zoned(from_date, from_time, "America/New_York")
        to = zoned(to_date, to_time, "America/New_York")

        assert DateTime.diff(to, from) == seconds
        assert parts(Localize.Duration.new(from, to)) == expected, inspect({from, to})
      end
    end

    # On 3 November 2024 the hour from 01:00 came twice in New York. A day
    # is whole when the earlier's time of day comes again, at its first
    # occurrence: 01:30 the day before to the second 01:10 is short of it,
    # 24 hours 40 minutes, and to the second 01:40 is a day and the hour and
    # ten minutes after the first 01:30.
    test "counts the time that passes across an hour the clocks repeat" do
      first_0130 = zoned(~D[2024-11-03], ~T[01:30:00], "America/New_York")
      second_0110 = second(~D[2024-11-03], ~T[01:10:00], "America/New_York")
      second_0140 = second(~D[2024-11-03], ~T[01:40:00], "America/New_York")
      day_before = zoned(~D[2024-11-02], ~T[01:30:00], "America/New_York")

      assert DateTime.diff(second_0110, first_0130) == 40 * 60
      assert parts(Localize.Duration.new(first_0130, second_0110)) == {0, 0, 0, 0, 40, 0}

      assert DateTime.diff(second_0110, day_before) == 24 * 3600 + 40 * 60
      assert parts(Localize.Duration.new(day_before, second_0110)) == {0, 0, 0, 24, 40, 0}

      assert DateTime.diff(second_0140, day_before) == 25 * 3600 + 10 * 60
      assert parts(Localize.Duration.new(day_before, second_0140)) == {0, 0, 1, 1, 10, 0}
    end

    # From the second occurrence of a time, the time that passes is counted
    # from that moment. The second 01:30 to 01:30 the next day is a day, and
    # to 01:10 the next day 23 hours 40 minutes: the specification's steps
    # resolve the earlier's own time again, at its first occurrence, and
    # answer 24 hours 40 minutes there, an hour more than passes.
    test "counts from the earlier moment itself where its time is repeated" do
      second_0130 = second(~D[2024-11-03], ~T[01:30:00], "America/New_York")
      next_0130 = zoned(~D[2024-11-04], ~T[01:30:00], "America/New_York")
      next_0110 = zoned(~D[2024-11-04], ~T[01:10:00], "America/New_York")

      assert DateTime.diff(next_0130, second_0130) == 24 * 3600
      assert parts(Localize.Duration.new(second_0130, next_0130)) == {0, 0, 1, 0, 0, 0}

      assert DateTime.diff(next_0110, second_0130) == 23 * 3600 + 40 * 60
      assert parts(Localize.Duration.new(second_0130, next_0110)) == {0, 0, 0, 23, 40, 0}
    end

    # 31 January to 10 March the next year is a year, a month, to 29
    # February, and ten days, noon to noon though the clocks changed that
    # morning. 22:00 on 31 January to 02:30 on 31 March in London is a month,
    # to 29 February, 30 days, to 22:00 on 30 March, and the three hours and
    # a half that pass from then: the clocks went from 01:00 to 02:00.
    test "counts years and months on the wall clock" do
      new_york = zoned(~D[2023-01-31], ~T[12:00:00], "America/New_York")
      later = zoned(~D[2024-03-10], ~T[12:00:00], "America/New_York")

      assert parts(Localize.Duration.new(new_york, later)) == {1, 1, 10, 0, 0, 0}

      london = zoned(~D[2024-01-31], ~T[22:00:00], "Europe/London")
      summer = zoned(~D[2024-03-31], ~T[02:30:00], "Europe/London")

      assert DateTime.diff(summer, zoned(~D[2024-03-30], ~T[22:00:00], "Europe/London")) ==
               3 * 3600 + 30 * 60

      assert parts(Localize.Duration.new(london, summer)) == {0, 1, 30, 3, 30, 0}
    end

    # 23:00 on 9 March in New York to 09:30 on 11 March in Karachi, which is
    # 00:30 on 11 March in New York: a day, to 23:00 on 10 March, and an hour
    # and a half. 24 hours 30 minutes pass, the day being 23 hours long.
    test "moves the later to the earlier's time zone" do
      new_york = zoned(~D[2024-03-09], ~T[23:00:00], "America/New_York")
      karachi = zoned(~D[2024-03-11], ~T[09:30:00], "Asia/Karachi")

      assert DateTime.shift_zone!(karachi, "America/New_York") ==
               zoned(~D[2024-03-11], ~T[00:30:00], "America/New_York")

      assert DateTime.diff(karachi, new_york) == 24 * 3600 + 30 * 60
      assert parts(Localize.Duration.new(new_york, karachi)) == {0, 0, 1, 1, 30, 0}
    end

    # A fixed offset is carried under `Etc/UTC`, as parsing gives it, and a
    # zone no time zone database knows keeps the offset its value carries:
    # 15:00 at +05:00 is 10:00 UTC.
    test "keeps a value's offset where no time zone database places it" do
      fixed = %{~U[2026-06-15 15:00:00Z] | utc_offset: 18_000}
      unknown = %{fixed | time_zone: "Nowhere/Unknown", zone_abbr: "NWT"}

      for from <- [fixed, unknown] do
        assert DateTime.diff(~U[2026-06-15 13:00:00Z], from) == 3 * 3600
        assert parts(Localize.Duration.new(from, ~U[2026-06-15 13:00:00Z])) == {0, 0, 0, 3, 0, 0}

        assert parts(Localize.Duration.new(~U[2026-06-15 09:00:00Z], from)) ==
                 {0, 0, 0, 1, 0, 0}

        # 13:00 UTC two days on is 18:00 there, a day and three hours after
        # 15:00 the day before.
        assert parts(Localize.Duration.new(from, ~U[2026-06-16 13:00:00Z])) ==
                 {0, 0, 1, 3, 0, 0}
      end
    end

    test "keeps the fraction of a second that passes" do
      from = %{
        zoned(~D[2024-03-09], ~T[12:00:00], "America/New_York")
        | microsecond: {250_000, 6}
      }

      to = %{zoned(~D[2024-03-10], ~T[12:00:00], "America/New_York") | microsecond: {750_000, 6}}

      assert {:ok, %{day: 1, hour: 0, second: 0, microsecond: {500_000, 6}}} =
               Localize.Duration.new(from, to)
    end

    # The calendar counts the days, as it does between two dates: noon to
    # noon across the change of clocks in a calendar with no year 0.
    test "counts in the date-times' own calendar" do
      from =
        ~D[2024-03-09]
        |> zoned(~T[12:00:00], "America/New_York")
        |> DateTime.convert!(NoYearZeroCalendar)

      to =
        ~D[2025-04-10]
        |> zoned(~T[11:00:00], "America/New_York")
        |> DateTime.convert!(NoYearZeroCalendar)

      assert parts(Localize.Duration.new(from, to)) == {1, 1, 0, 23, 0, 0}
    end

    test "a zoned date-time without its offsets or its zone is an error" do
      whole = zoned(~D[2024-03-09], ~T[12:00:00], "America/New_York")

      for broken <- [
            %{whole | utc_offset: nil},
            %{whole | std_offset: nil},
            %{whole | time_zone: nil}
          ] do
        assert {:error, %Localize.InvalidValueError{}} = Localize.Duration.new(broken, whole)
        assert {:error, %Localize.InvalidValueError{}} = Localize.Duration.new(whole, broken)
      end
    end

    # The hours that pass are not bounded by a day's.
    test "formats more than a day of hours" do
      day_before = zoned(~D[2024-11-02], ~T[01:30:00], "America/New_York")
      second_0110 = second(~D[2024-11-03], ~T[01:10:00], "America/New_York")
      {:ok, duration} = Localize.Duration.new(day_before, second_0110)

      assert Localize.Duration.to_string(duration, locale: :en) == {:ok, "24 hours, 40 minutes"}
      assert Localize.Duration.to_time_string(duration) == {:ok, "24:40:00"}
    end
  end

  # ── new/2 between values of two kinds ────────────────────────

  # Only two date-times in time zones are two moments. Any other two values
  # are measured on the wall clocks they are written in: a date is its
  # midnight, and a time is measured against a date-time's time of day.
  describe "new/2 between values of two kinds" do
    test "a date-time without a time zone is measured on the wall clock" do
      karachi = zoned(~D[2026-01-02], ~T[03:00:00], "Asia/Karachi")

      assert parts(Localize.Duration.new(~N[2026-01-01 10:00:00], karachi)) ==
               {0, 0, 0, 17, 0, 0}

      assert parts(Localize.Duration.new(~N[2026-01-01 10:00:00], ~U[2026-01-02 12:30:00Z])) ==
               {0, 0, 1, 2, 30, 0}

      assert {:error, %ArgumentError{}} = Localize.Duration.new(karachi, ~N[2026-01-01 10:00:00])
    end

    test "a date is its midnight on a date-time's wall clock" do
      karachi = zoned(~D[2026-01-02], ~T[03:00:00], "Asia/Karachi")

      assert parts(Localize.Duration.new(~D[2026-01-01], ~N[2026-01-02 12:30:00])) ==
               {0, 0, 1, 12, 30, 0}

      assert parts(Localize.Duration.new(~N[2026-01-01 10:00:00], ~D[2026-01-02])) ==
               {0, 0, 0, 14, 0, 0}

      assert parts(Localize.Duration.new(~D[2026-01-01], karachi)) == {0, 0, 1, 3, 0, 0}
      assert parts(Localize.Duration.new(~D[2026-01-02], karachi)) == {0, 0, 0, 3, 0, 0}

      assert {:error, %ArgumentError{} = exception} =
               Localize.Duration.new(karachi, ~D[2026-01-02])

      assert Exception.message(exception) =~ "~D[2026-01-02]"
      assert {:error, %ArgumentError{}} = Localize.Duration.new(~D[2026-01-03], karachi)
    end

    test "a time is measured against a date-time's time of day" do
      karachi = zoned(~D[2026-01-02], ~T[03:00:00], "Asia/Karachi")

      for {from, to, expected} <- [
            {~T[10:00:00], ~N[2026-01-01 12:30:00], {0, 0, 0, 2, 30, 0}},
            {~N[2026-01-01 10:00:00], ~T[12:30:00], {0, 0, 0, 2, 30, 0}},
            {~T[10:00:00], ~U[2026-01-02 12:30:00Z], {0, 0, 0, 2, 30, 0}},
            {karachi, ~T[10:00:00], {0, 0, 0, 7, 0, 0}}
          ] do
        assert parts(Localize.Duration.new(from, to)) == expected, inspect({from, to})
      end

      for {from, to} <- [
            {~T[12:30:00], ~N[2026-01-01 10:00:00]},
            {~N[2026-01-02 12:30:00], ~T[10:00:00]},
            {~T[10:00:00], karachi}
          ] do
        assert {:error, %ArgumentError{}} = Localize.Duration.new(from, to), inspect({from, to})
      end
    end

    test "a date and a time cannot be measured" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Duration.new(~D[2026-01-01], ~T[10:00:00])

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Duration.new(~T[10:00:00], ~D[2026-01-01])
    end

    # No two kinds of value raise, and none gives a duration with a part
    # below zero.
    test "every pairing is a duration with no negative part, or an error" do
      values = [
        ~D[2026-01-01],
        ~D[2026-01-02],
        ~T[10:00:00],
        ~T[12:30:00],
        ~N[2026-01-01 10:00:00],
        ~N[2026-01-02 12:30:00],
        ~U[2026-01-01 10:00:00Z],
        ~U[2026-01-02 12:30:00Z],
        zoned(~D[2026-01-02], ~T[03:00:00], "Asia/Karachi"),
        zoned(~D[2026-01-01], ~T[12:00:00], "America/New_York"),
        %{year: 2026, month: 1, day: 1, calendar: Calendar.ISO},
        %{hour: 10, minute: 0, second: 0},
        nil
      ]

      for from <- values, to <- values do
        case Localize.Duration.new(from, to) do
          {:ok, duration} ->
            {microsecond, _precision} = duration.microsecond

            assert Enum.all?(
                     [duration.year, duration.month, duration.day, duration.hour] ++
                       [duration.minute, duration.second, microsecond],
                     &(&1 >= 0)
                   ),
                   inspect({from, to, duration})

          {:error, exception} ->
            assert is_exception(exception), inspect({from, to})
        end
      end
    end
  end

  # ── new/2 validation ──────────────────────────────────────────

  describe "new/2 validation of datetime pairs" do
    test "rejects mismatched calendars" do
      to = %{~N[2020-06-01 00:00:00] | calendar: :not_a_real_calendar}

      assert {:error, %ArgumentError{}} =
               Localize.Duration.new(~N[2020-01-01 00:00:00], to)
    end

    test "rejects reversed datetime order" do
      assert {:error, %ArgumentError{}} =
               Localize.Duration.new(~U[2020-01-02 00:00:00Z], ~U[2020-01-01 00:00:00Z])
    end
  end

  # ── to_string/2 variants and error paths ──────────────────────

  describe "to_string/2 formats and errors" do
    test "defaults the options argument" do
      duration = Localize.Duration.new!(~D[2019-01-01], ~D[2019-12-31])
      assert {:ok, "11 months, 30 days"} = Localize.Duration.to_string(duration)
    end

    test "an all-zero duration formats as zero seconds" do
      duration = Localize.Duration.new_from_seconds(0)
      assert {:ok, "0 seconds"} = Localize.Duration.to_string(duration, locale: :en)
    end

    test "short format abbreviates unit names" do
      duration = Localize.Duration.new!(~D[2019-01-01], ~D[2019-12-31])

      assert {:ok, "11 mths, 30 days"} =
               Localize.Duration.to_string(duration, locale: :en, format: :short)
    end

    test "an invalid locale returns an error tuple" do
      duration = Localize.Duration.new_from_seconds(3661)

      assert {:error, %Localize.InvalidLocaleError{}} =
               Localize.Duration.to_string(duration, locale: :zzz)
    end

    test "an invalid locale on a zero duration returns an error tuple" do
      duration = Localize.Duration.new_from_seconds(0)

      assert {:error, %Localize.InvalidLocaleError{}} =
               Localize.Duration.to_string(duration, locale: :zzz)
    end
  end

  describe "to_string!/2" do
    test "returns the formatted string" do
      duration = Localize.Duration.new_from_seconds(60)
      assert Localize.Duration.to_string!(duration, locale: :en) == "1 minute"
    end

    test "raises on an invalid locale" do
      duration = Localize.Duration.new_from_seconds(60)

      assert_raise Localize.InvalidLocaleError, fn ->
        Localize.Duration.to_string!(duration, locale: :zzz)
      end
    end
  end

  # ── microsecond precision ─────────────────────────────────────

  describe "new_from_seconds/1 microsecond precision" do
    test "precision tracks the magnitude of the fractional part" do
      fractions = [1.000001, 1.00005, 1.0005, 1.005, 1.05, 1.5]

      microseconds =
        for fraction <- fractions do
          Localize.Duration.new_from_seconds(fraction).microsecond
        end

      assert microseconds == [
               {1, 1},
               {50, 2},
               {500, 3},
               {5000, 4},
               {50_000, 5},
               {500_000, 6}
             ]
    end
  end

  describe "to_string/2 per-unit options" do
    test "display :always renders zero-valued units" do
      assert {:ok, "2 hours, 0 minutes"} =
               Localize.Duration.to_string(%Localize.Duration{hour: 2},
                 locale: :en,
                 display: [minute: :always]
               )
    end

    test "display :always applies to an all-zero duration" do
      assert {:ok, "0 hours"} =
               Localize.Duration.to_string(%Localize.Duration{},
                 locale: :en,
                 display: [hour: :always]
               )
    end

    test "per-unit formats override the format" do
      assert {:ok, "2h, 30 minutes"} =
               Localize.Duration.to_string(%Localize.Duration{hour: 2, minute: 30},
                 locale: :en,
                 formats: [hour: :narrow]
               )
    end

    test "invalid per-unit values are errors" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Duration.to_string(%Localize.Duration{hour: 2},
                 locale: :en,
                 display: [minute: :sometimes]
               )

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Duration.to_string(%Localize.Duration{hour: 2},
                 locale: :en,
                 formats: [hour: :digital]
               )
    end
  end

  # A wall-clock time in a time zone: the one moment it names, or the first
  # where the clocks repeat it.
  defp zoned(date, time, time_zone) do
    case DateTime.new(date, time, time_zone) do
      {:ok, datetime} -> datetime
      {:ambiguous, first, _second} -> first
    end
  end

  # The second occurrence of a wall-clock time the clocks repeat.
  defp second(date, time, time_zone) do
    {:ambiguous, _first, second} = DateTime.new(date, time, time_zone)
    second
  end

  defp parts({:ok, duration}),
    do:
      {duration.year, duration.month, duration.day, duration.hour, duration.minute,
       duration.second}

  defp parts(error), do: error
end
