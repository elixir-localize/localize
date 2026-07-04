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

  describe "to_string/2 with Time structs" do
    test "relative time with unit" do
      assert {:ok, "in 6 hours"} =
               Relative.to_string(@time, relative_to: @relative_time_to, unit: :hour)
    end

    test "relative time auto-derive" do
      assert {:ok, "in 6 hours"} = Relative.to_string(@time, relative_to: @relative_time_to)
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

    test "minutes from 60 seconds up to one hour" do
      assert {:ok, "in 1 minute"} = Relative.to_string(60, locale: :en)
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

    test "months from one month up to one year" do
      assert {:ok, "next month"} = Relative.to_string(2_629_744, locale: :en)
      assert {:ok, "in 12 months"} = Relative.to_string(31_556_925, locale: :en)
    end

    test "years from one year onward" do
      assert {:ok, "next year"} = Relative.to_string(31_556_926, locale: :en)
    end

    test "negative offsets select past forms" do
      assert {:ok, "45 seconds ago"} = Relative.to_string(-45, locale: :en)
      assert {:ok, "2 hours ago"} = Relative.to_string(-7200, locale: :en)
    end
  end

  describe "to_string/2 input type coverage" do
    test "float input is truncated and scaled" do
      assert {:ok, "in 2 minutes"} = Relative.to_string(90.5, unit: :minute, locale: :en)
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
