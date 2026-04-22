defmodule Localize.IntervalTest.GenericGregorian do
  @moduledoc false
  # Minimal non-ISO calendar module used to exercise the generic-calendar
  # branch of `Localize.Calendar.iso_day_of_week/1`. Only implements the
  # callbacks that path actually invokes.

  def day_of_week(y, m, d, start), do: Calendar.ISO.day_of_week(y, m, d, start)
  def cldr_calendar_type, do: :gregorian
end

defmodule Localize.IntervalTest do
  use ExUnit.Case, async: true

  doctest Localize.Interval

  alias Localize.Interval
  alias Localize.IntervalTest.GenericGregorian

  describe "to_string/3 with dates" do
    test "same month different days" do
      assert {:ok, result} = Interval.to_string(~D[2022-04-22], ~D[2022-04-25], locale: :en)
      assert String.contains?(result, "Apr")
      assert String.contains?(result, "22")
      assert String.contains?(result, "25")
    end

    test "different months" do
      assert {:ok, result} = Interval.to_string(~D[2022-01-15], ~D[2022-03-20], locale: :en)
      assert String.contains?(result, "Jan")
      assert String.contains?(result, "Mar")
    end

    test "different years" do
      assert {:ok, result} = Interval.to_string(~D[2022-01-15], ~D[2023-03-20], locale: :en)
      assert String.contains?(result, "2022")
      assert String.contains?(result, "2023")
    end

    test "same day returns single date" do
      assert {:ok, result} = Interval.to_string(~D[2022-04-22], ~D[2022-04-22], locale: :en)
      assert String.contains?(result, "Apr 22, 2022")
    end
  end

  describe "to_string/3 with locales" do
    test "French interval" do
      assert {:ok, result} = Interval.to_string(~D[2022-04-22], ~D[2022-04-25], locale: :fr)
      assert String.contains?(result, "avr.")
    end

    test "German interval" do
      assert {:ok, result} = Interval.to_string(~D[2022-01-15], ~D[2022-03-20], locale: :de)
      assert String.contains?(result, "Jan.")
      assert String.contains?(result, "März")
    end
  end

  describe "to_string/3 with styles" do
    test "month_and_day style" do
      assert {:ok, result} =
               Interval.to_string(~D[2022-04-22], ~D[2022-04-25],
                 locale: :en,
                 style: :month_and_day
               )

      assert String.contains?(result, "Apr")
    end

    test "year_and_month style" do
      assert {:ok, result} =
               Interval.to_string(~D[2022-01-15], ~D[2022-03-20],
                 locale: :en,
                 style: :year_and_month
               )

      assert String.contains?(result, "2022")
    end
  end

  describe "to_string/3 with format options" do
    test "short format" do
      assert {:ok, result} =
               Interval.to_string(~D[2022-04-22], ~D[2022-04-25],
                 locale: :en,
                 format: :short
               )

      assert String.contains?(result, "22")
      assert String.contains?(result, "25")
    end
  end

  describe "to_string!/3" do
    test "returns string directly" do
      result = Interval.to_string!(~D[2022-04-22], ~D[2022-04-25], locale: :en)
      assert is_binary(result)
      assert String.contains?(result, "Apr")
    end
  end

  describe "to_string/3 with open intervals" do
    test "open-end date (to is nil) in English" do
      assert {:ok, result} = Interval.to_string(~D[2020-01-01], nil, locale: :en)
      assert String.starts_with?(result, "Jan 1, 2020")
      assert String.contains?(result, "\u2013")
      refute String.starts_with?(result, "\u2013")
    end

    test "open-start date (from is nil) in English" do
      assert {:ok, result} = Interval.to_string(nil, ~D[2020-01-01], locale: :en)
      assert String.ends_with?(result, "Jan 1, 2020")
      assert String.contains?(result, "\u2013")
      refute String.ends_with?(result, "\u2013")
    end

    test "open-end date (to is nil) in Japanese uses fullwidth tilde" do
      assert {:ok, result} = Interval.to_string(~D[2020-01-01], nil, locale: :ja)
      assert String.contains?(result, "2020")
      assert String.ends_with?(result, "\uFF5E")
    end

    test "open-start date (from is nil) in Japanese uses fullwidth tilde" do
      assert {:ok, result} = Interval.to_string(nil, ~D[2020-01-01], locale: :ja)
      assert String.contains?(result, "2020")
      assert String.starts_with?(result, "\uFF5E")
    end

    test "open-end time in English" do
      assert {:ok, result} = Interval.to_string(~T[10:30:00], nil, locale: :en)
      assert String.contains?(result, "10:30")
      assert String.contains?(result, "\u2013")
    end

    test "open-end naive datetime in English" do
      assert {:ok, result} = Interval.to_string(~N[2020-01-01 10:30:00], nil, locale: :en)
      assert String.contains?(result, "Jan 1, 2020")
      assert String.contains?(result, "10:30")
      assert String.contains?(result, "\u2013")
    end

    test "both nil returns an invalid input error" do
      assert {:error, %Localize.DateTimeInvalidInputError{type: :datetime}} =
               Interval.to_string(nil, nil, locale: :en)
    end
  end

  describe "to_string/3 datetime intervals (same-day vs different-day)" do
    test "same-day interval shows date once and a time range" do
      # Feature-compatible with ex_cldr: same-day NaiveDateTime interval
      # formats as `date, time – time`, not as `date – date`.
      assert {:ok, result} =
               Interval.to_string(
                 ~N[2026-04-08 12:00:00],
                 ~N[2026-04-08 14:00:00],
                 locale: :en,
                 format: :medium,
                 time_format: :short
               )

      assert String.contains?(result, "Apr 8, 2026")
      assert String.contains?(result, "12:00")
      assert String.contains?(result, "2:00")
      # Date must appear only once (not on both sides).
      assert length(String.split(result, "Apr 8")) == 2
    end

    test "different-day interval shows full datetime on both sides" do
      assert {:ok, result} =
               Interval.to_string(
                 ~N[2026-04-15 00:49:00],
                 ~N[2026-04-16 01:49:00],
                 locale: :en,
                 format: :medium,
                 time_format: :short
               )

      assert String.contains?(result, "Apr 15, 2026")
      assert String.contains?(result, "Apr 16, 2026")
      assert String.contains?(result, "12:49")
      assert String.contains?(result, "1:49")
    end

    test "different-month datetime interval shows full datetime on both sides" do
      assert {:ok, result} =
               Interval.to_string(
                 ~N[2026-04-15 12:00:00],
                 ~N[2026-05-15 12:00:00],
                 locale: :en
               )

      assert String.contains?(result, "Apr 15, 2026")
      assert String.contains?(result, "May 15, 2026")
    end

    test "same-day datetime interval in Japanese" do
      assert {:ok, result} =
               Interval.to_string(
                 ~N[2026-04-08 12:00:00],
                 ~N[2026-04-08 14:00:00],
                 locale: :ja
               )

      assert String.contains?(result, "2026")
      # Japanese interval fallback uses a fullwidth tilde.
      assert String.contains?(result, "\uFF5E")
    end
  end

  describe "to_string/3 with time-only intervals" do
    test "hour difference in English" do
      assert {:ok, result} = Interval.to_string(~T[10:00:00], ~T[12:30:00], locale: :en)
      assert String.contains?(result, "10:00")
      assert String.contains?(result, "12:30")
    end

    test "minute difference in English" do
      assert {:ok, result} = Interval.to_string(~T[10:00:00], ~T[10:30:00], locale: :en)
      assert String.contains?(result, "10:00")
      assert String.contains?(result, "10:30")
    end
  end

  describe "greatest_difference/2" do
    test "year difference" do
      assert {:ok, :y} = Interval.greatest_difference(~D[2022-04-22], ~D[2023-04-22])
    end

    test "month difference" do
      assert {:ok, :M} = Interval.greatest_difference(~D[2022-04-22], ~D[2022-05-22])
    end

    test "day difference" do
      assert {:ok, :d} = Interval.greatest_difference(~D[2022-04-22], ~D[2022-04-23])
    end

    test "no difference" do
      assert {:error, :no_practical_difference} =
               Interval.greatest_difference(~D[2022-04-22], ~D[2022-04-22])
    end

    test "hour difference for datetimes" do
      assert {:ok, :H} =
               Interval.greatest_difference(
                 ~N[2022-04-22 10:00:00],
                 ~N[2022-04-22 14:00:00]
               )
    end
  end

  describe "split_interval/1" do
    test "splits a simple interval pattern" do
      assert {:ok, ["MMM d – ", "d, y"]} = Interval.split_interval("MMM d – d, y")
    end

    test "splits with month difference" do
      assert {:ok, ["MMM d – ", "MMM d, y"]} = Interval.split_interval("MMM d – MMM d, y")
    end
  end

  describe "to_string/3 with datetime intervals" do
    test "same day different times" do
      assert {:ok, result} =
               Interval.to_string(
                 ~N[2022-04-22 10:00:00],
                 ~N[2022-04-22 14:00:00],
                 locale: :en,
                 prefer: :ascii
               )

      assert is_binary(result)
    end

    test "different days with times" do
      assert {:ok, result} =
               Interval.to_string(
                 ~N[2022-04-22 10:00:00],
                 ~N[2022-04-25 14:00:00],
                 locale: :en,
                 prefer: :ascii
               )

      assert is_binary(result)
    end
  end

  describe "to_string/3 error handling" do
    test "reversed dates" do
      result = Interval.to_string(~D[2023-01-01], ~D[2022-01-01], locale: :en)

      # Should either format anyway or return error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "date_styles/0" do
    test "returns expected styles" do
      styles = Interval.date_styles()
      assert Map.has_key?(styles, :date)
      assert Map.has_key?(styles, :month)
      assert Map.has_key?(styles, :month_and_day)
      assert Map.has_key?(styles, :year_and_month)
    end
  end

  describe "regression: non-ISO calendar with :long date style" do
    test "month-resolution :long does not crash on generic calendar day_of_week" do
      # Previously `iso_day_of_week/1` destructured the `day_of_week/4`
      # return value as a 2-tuple, but the Calendar behaviour returns
      # `{day, first, last}`. Any non-ISO calendar carrying a
      # `day_of_week/4` callback raised MatchError here.
      from = %{year: 2026, month: 6, day: 1, calendar: GenericGregorian}
      to = %{year: 2026, month: 6, day: 30, calendar: GenericGregorian}

      assert {:ok, result} =
               Interval.to_string(from, to, format: :long, style: :date, locale: :en)

      assert String.contains?(result, "Mon")
      assert String.contains?(result, "Tue")
      assert String.contains?(result, "Jun")
    end
  end

  describe "regression: partial-time endpoints" do
    test "hour-carrying maps without minute/second format cleanly" do
      # Tempo's fallback path produced either
      # DateTimeUnresolvedFormatError{format: :medium} (from Time.to_string
      # on partial times) or silently stripped the hour (from
      # DateTime.to_string dispatching partial datetimes to Date).
      from = %{year: 2026, month: 6, day: 15, hour: 9, calendar: Calendar.ISO}
      to = %{year: 2026, month: 6, day: 15, hour: 17, calendar: Calendar.ISO}

      assert {:ok, result} =
               Interval.to_string(from, to, format: :medium, locale: :en, prefer: :ascii)

      assert String.contains?(result, "9")
      assert String.contains?(result, "5")
      assert String.contains?(result, "AM")
      assert String.contains?(result, "PM")
      refute result =~ ~r/:\s/
    end
  end
end
