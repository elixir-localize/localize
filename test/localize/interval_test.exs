defmodule Localize.IntervalTest do
  use ExUnit.Case, async: true

  doctest Localize.Interval

  alias Localize.Interval

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

  describe "date_styles/0" do
    test "returns expected styles" do
      styles = Interval.date_styles()
      assert Map.has_key?(styles, :date)
      assert Map.has_key?(styles, :month)
      assert Map.has_key?(styles, :month_and_day)
      assert Map.has_key?(styles, :year_and_month)
    end
  end
end
