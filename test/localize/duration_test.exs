defmodule Localize.DurationTest do
  use ExUnit.Case, async: true

  doctest Localize.Duration

  alias Localize.Test.{LadyDayCalendar, NoYearZeroCalendar, ThirteenMonthCalendar}

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

  # ── new/2 validation ──────────────────────────────────────────

  describe "new/2 validation of datetime pairs" do
    test "accepts differing time zones" do
      to = %{~U[2020-01-02 10:00:00Z] | time_zone: "Australia/Sydney", zone_abbr: "AEST"}
      {:ok, duration} = Localize.Duration.new(~U[2020-01-01 10:00:00Z], to)
      assert duration.day == 1
    end

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
end
