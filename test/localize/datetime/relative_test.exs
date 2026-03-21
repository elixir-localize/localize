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
