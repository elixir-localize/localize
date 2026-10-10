defmodule Localize.CalendarISOWeeksTest do
  @moduledoc """
  `Calendar.ISO` has no weeks of its own, so Localize numbers its weeks from
  the locale's week data by TR35's rule (tr35-dates, "Week Data" and "Week
  of Year"): a week begins on the first day of the week, and week 1 of a
  year, or of a month, is the first week holding at least the minimum days
  of it.

  The expected values are computed here from the rule's other form. A week
  across a boundary holds some days of the old period and the rest of the
  new, so it holds at least `min_days` of the new exactly when the day
  `7 - min_days` after its first is in the new: the week belongs to the
  period of that deciding day, and is as many weeks into it as the day is
  among the days of its weekday there. For ISO 8601's weeks, Monday and
  four days, the deciding day is Thursday, and Erlang's
  `:calendar.iso_week_number/1` numbers the same weeks.

  ICU4C 78.3 gives the same week of the year and week-based year for every
  first day and minimum days on every day of 2015 to 2032, and the same
  week of the month wherever the week is in its date's own month; it keeps
  a week in its date's month where TR35's rule gives it to the month before
  or after.

  """

  use ExUnit.Case, async: true

  alias Localize.Calendar.ISO

  # Eight years and their neighbours: every weekday a year can begin on,
  # leap years among them.
  @days Date.range(~D[2019-12-01], ~D[2028-01-31])

  describe "week_of_year/4" do
    test "is the year of the week's deciding day, for every first day and minimum days" do
      mismatches =
        for first_day <- 1..7,
            min_days <- 1..7,
            date <- @days,
            deciding = deciding_day(date, first_day, min_days),
            expected = {deciding.year, div(Date.day_of_year(deciding) - 1, 7) + 1},
            actual = ISO.week_of_year(date.year, date.month, date.day, {first_day, min_days}),
            actual != expected,
            do: {date, {first_day, min_days}, expected, actual}

      assert mismatches == []
    end

    test "with ISO 8601's weeks is Erlang's week number" do
      for date <- Date.range(~D[1995-01-01], ~D[2035-12-31]) do
        expected = :calendar.iso_week_number(Date.to_erl(date))

        assert ISO.week_of_year(date.year, date.month, date.day) == expected
        assert ISO.week_of_year(date.year, date.month, date.day, {1, 4}) == expected
      end
    end

    # TR35 §Week of Year: January 1, 1998 was a Thursday. With weeks from
    # Monday holding four days, week 1 of 1998 runs from 29 December 1997 to
    # 4 January 1998; with weeks from Sunday it runs from 4 to 10 January,
    # and the first three days of 1998 are in week 53 of 1997.
    test "follows TR35's worked example" do
      assert ISO.week(1998, 1, {1, 4}) == Date.range(~D[1997-12-29], ~D[1998-01-04])
      assert ISO.week(1998, 1, {7, 4}) == Date.range(~D[1998-01-04], ~D[1998-01-10])

      for day <- 1..3 do
        assert ISO.week_of_year(1998, 1, day, {7, 4}) == {1997, 53}
      end

      assert ISO.week_of_year(1998, 1, 4, {7, 4}) == {1998, 1}
      assert ISO.week_of_year(1997, 12, 29, {1, 4}) == {1998, 1}
    end
  end

  describe "week_of_month/4" do
    test "is the month of the week's deciding day, for every first day and minimum days" do
      mismatches =
        for first_day <- 1..7,
            min_days <- 1..7,
            date <- @days,
            deciding = deciding_day(date, first_day, min_days),
            expected = {deciding.month, div(deciding.day - 1, 7) + 1},
            actual = ISO.week_of_month(date.year, date.month, date.day, {first_day, min_days}),
            actual != expected,
            do: {date, {first_day, min_days}, expected, actual}

      assert mismatches == []
    end

    # ISO 8601's rule in a month: a Monday week is the month's that holds
    # its Thursday. 1 October 2021 is a Friday, in the week of Thursday 30
    # September, September's fifth. With weeks from Sunday holding one day,
    # that week holds two days of October and is its first.
    test "gives a week across a month's end to one month" do
      assert ISO.week_of_month(2021, 10, 1) == {9, 5}
      assert ISO.week_of_month(2021, 10, 4) == {10, 1}
      assert ISO.week_of_month(2021, 9, 30, {7, 1}) == {10, 1}
      assert ISO.week_of_month(2021, 10, 1, {7, 1}) == {10, 1}
      assert ISO.week_of_month(2021, 12, 31, {7, 1}) == {1, 1}
      assert ISO.week_of_month(2022, 1, 1, {1, 4}) == {12, 5}
    end
  end

  describe "week/3" do
    # Every day of a week names that week, the week begins on the first day,
    # and a week the year does not have is no week: no day names it.
    test "gives the seven days that name the week, for every first day and minimum days" do
      for first_day <- 1..7, min_days <- 1..7, year <- 2019..2028 do
        week_data = {first_day, min_days}

        named =
          Date.range(Date.new!(year - 1, 12, 20), Date.new!(year + 1, 1, 12))
          |> Enum.group_by(&ISO.week_of_year(&1.year, &1.month, &1.day, week_data))

        for week <- 1..54 do
          case ISO.week(year, week, week_data) do
            %Date.Range{} = days ->
              assert Date.day_of_week(days.first) == first_day
              assert Enum.to_list(days) == Map.fetch!(named, {year, week})

            {:error, :invalid_date} ->
              refute Map.has_key?(named, {year, week})
          end
        end
      end
    end

    # ISO 8601 gives 2026, which begins on a Thursday, 53 weeks and 2025
    # 52; with weeks from Sunday holding one day, 2022 has 53 and 2026 52.
    test "has the weeks its year has" do
      assert ISO.week(2026, 53) == Date.range(~D[2026-12-28], ~D[2027-01-03])
      assert ISO.week(2025, 53) == {:error, :invalid_date}
      assert ISO.week(2022, 53, {7, 1}) == Date.range(~D[2022-12-25], ~D[2022-12-31])
      assert ISO.week(2026, 53, {7, 1}) == {:error, :invalid_date}
      assert ISO.week(2026, 0) == {:error, :invalid_date}
      assert ISO.week(2026, 54) == {:error, :invalid_date}
    end
  end

  describe "weeks_in_month/2 and month_week/3" do
    # With ISO 8601's weeks a week is of the month its Thursday is in, so a
    # month has as many weeks as it has Thursdays, each from the Monday
    # before its Thursday to the Sunday after.
    test "are the weeks whose Thursdays are in the month" do
      for year <- 2019..2028, month <- 1..12 do
        first = Date.new!(year, month, 1)

        thursdays =
          first
          |> Date.range(Date.end_of_month(first))
          |> Enum.filter(&(Date.day_of_week(&1) == 4))

        assert ISO.weeks_in_month(year, month) == length(thursdays)

        for {thursday, week} <- Enum.with_index(thursdays, 1) do
          assert ISO.month_week(year, month, week) ==
                   Date.range(Date.add(thursday, -3), Date.add(thursday, 3))
        end

        assert ISO.month_week(year, month, length(thursdays) + 1) == {:error, :invalid_date}
      end
    end

    test "hold each day in the week of the month week_of_month/3 gives it" do
      for year <- 2019..2028, month <- 1..12, week <- 1..ISO.weeks_in_month(year, month) do
        for date <- ISO.month_week(year, month, week) do
          assert ISO.week_of_month(date.year, date.month, date.day) == {month, week}
        end
      end
    end

    test "are errors for what is no month or no week, never raises" do
      assert ISO.weeks_in_month(2026, 13) == {:error, :invalid_date}
      assert ISO.weeks_in_month(2026, 0) == {:error, :invalid_date}
      assert ISO.weeks_in_month(nil, 1) == {:error, :invalid_date}
      assert ISO.month_week(2026, 13, 1) == {:error, :invalid_date}
      assert ISO.month_week(2026, 5, 0) == {:error, :invalid_date}
      assert ISO.month_week(2026, "5", 1) == {:error, :invalid_date}
    end
  end

  describe "values that are no date" do
    test "are errors, never raises" do
      for {year, month, day} <- [
            {2026, 2, 30},
            {2026, 13, 1},
            {2026, 0, 1},
            {2026, 1, 0},
            {nil, 1, 1},
            {2026, "1", 1},
            {2026, 1, :""}
          ] do
        assert ISO.week_of_year(year, month, day) == {:error, :invalid_date}
        assert ISO.week_of_year(year, month, day, {7, 1}) == {:error, :invalid_date}
        assert ISO.week_of_month(year, month, day) == {:error, :invalid_date}
        assert ISO.week_of_month(year, month, day, {7, 1}) == {:error, :invalid_date}
      end

      for {year, week} <- [{nil, 1}, {2026, nil}, {2026, "1"}, {2026, -1}] do
        assert ISO.week(year, week) == {:error, :invalid_date}
        assert ISO.week(year, week, {7, 1}) == {:error, :invalid_date}
      end
    end
  end

  describe "years beyond four digits" do
    # `Calendar.ISO` has dates beyond the years ISO 8601 writes in four
    # digits, and their weeks are numbered and listed like any other. 31
    # December 9999 is a Friday and 1 January -9999 a Monday.
    test "are numbered across the turn of the year" do
      assert Date.day_of_week(~D[9999-12-31]) == 5
      assert ISO.week_of_year(9999, 12, 31) == {9999, 52}
      assert ISO.week_of_year(9999, 12, 31, {7, 1}) == {10_000, 1}
      assert ISO.week_of_month(9999, 12, 31, {7, 1}) == {1, 1}

      assert ISO.week(10_000, 1, {7, 1}) ==
               Date.range(~D[9999-12-26], Date.new!(10_000, 1, 1))

      assert Date.day_of_week(~D[-9999-01-01]) == 1
      assert ISO.week_of_year(-9999, 1, 1) == {-9999, 1}
      assert ISO.week(-9999, 1) == Date.range(~D[-9999-01-01], ~D[-9999-01-07])

      assert ISO.week(-9999, 1, {7, 1}) ==
               Date.range(Date.new!(-10_000, 12, 31), ~D[-9999-01-06])
    end
  end

  # The day that decides which period a week belongs to: `7 - min_days` days
  # after the week's first day.
  defp deciding_day(date, first_day, min_days) do
    first = Date.add(date, -Integer.mod(Date.day_of_week(date) - first_day, 7))
    Date.add(first, 7 - min_days)
  end
end
