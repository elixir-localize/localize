defmodule Localize.ImpossibleValuesTest do
  @moduledoc """
  A value Localize formats must be one its calendar has. A date its
  calendar's `valid_date?/3` rejects, or a time its `valid_time?/4` rejects,
  is an error wherever it enters, never a raise nor a string written from
  impossible fields; a partial value is checked by the fields it holds.

  The impossible values are impossible by the Gregorian calendar's rules,
  which `Calendar.ISO` follows: 2019 is not a leap year, a month has at
  most 31 days, a year 12 months, a day 24 hours of 60 minutes of 60
  seconds, and a second a million microseconds.

  """

  use ExUnit.Case, async: true

  # A calendar whose years have a thirteenth month of five days, so its
  # month 13 is a date `Calendar.ISO` does not have.
  defmodule ThirteenMonths do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def months_in_year(_year), do: 13
    def days_in_month(_year, 13), do: 5
    def days_in_month(_year, _month), do: 30
    def valid_date?(_year, month, day), do: month in 1..13 and day in 1..days_in_month(1, month)
  end

  @impossible_dates [
    %{year: 2019, month: 2, day: 29},
    %{year: 2019, month: 2, day: 30},
    %{year: 2019, month: 13, day: 1},
    %{year: 2019, month: 0, day: 1},
    %{year: 2019, month: 1, day: 0},
    %{year: 2019, month: 1, day: 32},
    %{year: 2019, month: 13},
    %{month: 0},
    %{day: -3},
    %Date{year: 2019, month: 2, day: 30, calendar: Calendar.ISO}
  ]

  @impossible_times [
    %{hour: 24, minute: 0},
    %{hour: 25, minute: 0},
    %{hour: -1, minute: 0},
    %{hour: 10, minute: 60},
    %{hour: 10, minute: 1, second: 60},
    %{hour: 1, minute: 0, second: 0, microsecond: {1_000_000, 6}},
    %Time{hour: 25, minute: 0, second: 0, microsecond: {0, 0}}
  ]

  @date_formats [:short, :medium, :long, :full, "E", "e", "c", "D", "Q", "d", "MMM", "F"] ++
                  ["w", "W", "Y", "G", "y", "g"]

  describe "an impossible date" do
    test "is an error in every format" do
      for date <- @impossible_dates, format <- @date_formats do
        assert {:error, %Localize.InvalidValueError{}} =
                 Localize.Date.to_string(date, format: format),
               "#{inspect(date)} #{inspect(format)}"

        assert {:error, %Localize.InvalidValueError{}} =
                 Localize.Date.to_parts(date, format: format)
      end
    end

    test "is an error with a time" do
      for date <- [%{year: 2019, month: 2, day: 29}, %{year: 2019, month: 13, day: 1}] do
        datetime = Map.merge(date, %{hour: 10, minute: 0, second: 0})
        assert {:error, %Localize.InvalidValueError{}} = Localize.DateTime.to_string(datetime)
        assert {:error, %Localize.InvalidValueError{}} = Localize.DateTime.to_parts(datetime)
      end

      naive = %NaiveDateTime{
        year: 2019,
        month: 2,
        day: 30,
        hour: 1,
        minute: 2,
        second: 3,
        microsecond: {0, 0},
        calendar: Calendar.ISO
      }

      assert {:error, %Localize.InvalidValueError{}} = Localize.DateTime.to_string(naive)
    end

    test "is an error at either end of an interval, closed or open" do
      possible = %{year: 2019, month: 3, day: 5}
      impossible = %{year: 2019, month: 2, day: 30}

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Interval.to_string(impossible, possible)

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Interval.to_string(possible, impossible)

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Interval.to_string(%{year: 2019, month: 2, day: 1}, impossible)

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Interval.to_string(impossible, nil)

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Interval.to_parts(possible, impossible)
    end

    test "is an error in the parts of a calendar, relative time and messages" do
      impossible = %{year: 2019, month: 2, day: 30}

      for part <- [:era, :quarter, :month, :day_of_week] do
        assert {:error, %Localize.InvalidValueError{}} =
                 Localize.Calendar.localize(impossible, part)
      end

      assert {:error, _impossible} =
               Localize.DateTime.Relative.to_string(impossible, relative_to: ~D[2019-03-01])

      assert {:error, _impossible} =
               Localize.DateTime.Relative.to_string(~D[2019-03-01], relative_to: impossible)

      assert {:error, _impossible} =
               Localize.Message.format("{$d :date}", %{
                 d: %Date{year: 2019, month: 2, day: 30, calendar: Calendar.ISO}
               })
    end

    test "is one its own calendar does not have" do
      thirteenth = %{year: 2026, month: 13, day: 5, calendar: ThirteenMonths}
      assert Localize.Date.to_string(thirteenth, format: "d") == {:ok, "5"}

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Date.to_string(%{thirteenth | day: 6}, format: "d")

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Date.to_string(%{thirteenth | calendar: Calendar.ISO}, format: "d")
    end
  end

  describe "an impossible time" do
    test "is an error in every format" do
      for time <- @impossible_times, format <- [:short, :medium, :long, :full, "H", "h", "a"] do
        assert {:error, %Localize.InvalidValueError{}} =
                 Localize.Time.to_string(time, format: format),
               "#{inspect(time)} #{inspect(format)}"

        assert {:error, %Localize.InvalidValueError{}} =
                 Localize.Time.to_parts(time, format: format)
      end
    end

    test "is an error with a date and in an interval" do
      datetime = %{year: 2019, month: 3, day: 1, hour: 25, minute: 0, second: 0}
      assert {:error, %Localize.InvalidValueError{}} = Localize.DateTime.to_string(datetime)

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Interval.to_string(%{hour: 10, minute: 0}, %{hour: 10, minute: 61})
    end
  end

  describe "a possible value" do
    # A leap day is a date in a leap year, and a month and day without a year
    # could be any year's.
    test "formats whole or in part" do
      assert Localize.Date.to_string(%{year: 2020, month: 2, day: 29}, locale: :en) ==
               {:ok, "Feb 29, 2020"}

      assert Localize.Date.to_string(%{year: 2019, month: 2}, format: "MMM y", locale: :en) ==
               {:ok, "Feb 2019"}

      assert Localize.Date.to_string(%{month: 2, day: 29}, format: "MMM d", locale: :en) ==
               {:ok, "Feb 29"}

      assert Localize.Time.to_string(%{hour: 23, minute: 59}, format: "HH:mm", locale: :en) ==
               {:ok, "23:59"}

      assert Localize.Time.to_string(%{hour: 0}, format: "H", locale: :en) == {:ok, "0"}
    end

    # A field that is not an integer is the format's to report, as a field
    # of the wrong type.
    test "with a field of the wrong type is the format's error" do
      assert {:error, %Localize.DateTimeInvalidInputError{invalid: [:month]}} =
               Localize.Date.to_string(%{year: 2019, month: "2", day: 1}, format: "MMM d, y")
    end
  end
end
