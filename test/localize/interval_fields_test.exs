defmodule Localize.IntervalFieldsTest do
  use ExUnit.Case, async: true

  alias Localize.Interval

  # The en interval separator: thin space (U+2009), en dash
  # (U+2013), thin space (U+2009).
  @separator " – "

  defp interval(from, to, options) do
    {:ok, result} = Interval.to_string(from, to, options)
    result
  end

  describe "to_string/3 date field selections produce exact output" do
    test ":month fields renders abbreviated months only" do
      result =
        interval(~D[2024-01-10], ~D[2024-03-12], fields: :month, locale: :en, prefer: :ascii)

      assert result == "Jan#{@separator}Mar"
    end

    test ":year_and_month fields renders months with a single year" do
      result =
        interval(~D[2024-01-10], ~D[2024-03-12],
          fields: :year_and_month,
          locale: :en,
          prefer: :ascii
        )

      assert result == "Jan#{@separator}Mar 2024"
    end

    test ":month_and_day fields renders month-day pairs" do
      result =
        interval(~D[2024-01-10], ~D[2024-03-12],
          fields: :month_and_day,
          locale: :en,
          prefer: :ascii
        )

      assert result == "Jan 10#{@separator}Mar 12"
    end

    test "unknown fields returns a DateTimeIntervalFormatError" do
      assert {:error,
              %Localize.DateTimeIntervalFormatError{reason: :unknown_fields, fields: :bogus}} =
               Interval.to_string(~D[2024-06-01], ~D[2024-06-10], fields: :bogus, locale: :en)
    end
  end

  describe "to_string/3 across greatest-difference boundaries" do
    test "same month shows the month once" do
      result = interval(~D[2024-06-01], ~D[2024-06-10], locale: :en, prefer: :ascii)
      assert result == "Jun 1#{@separator}10, 2024"
    end

    test "different month within a year repeats the month" do
      result = interval(~D[2024-01-10], ~D[2024-03-12], locale: :en, prefer: :ascii)
      assert result == "Jan 10#{@separator}Mar 12, 2024"
    end

    test "different year repeats the full date" do
      result = interval(~D[2023-11-20], ~D[2024-02-10], locale: :en, prefer: :ascii)
      assert result == "Nov 20, 2023#{@separator}Feb 10, 2024"
    end
  end

  describe "to_string/3 time intervals with skeleton formats" do
    test ":hm skeleton collapses a same-period AM range" do
      result =
        interval(~T[09:00:00], ~T[11:00:00], format: :hm, locale: :en, prefer: :ascii)

      assert result == "9:00#{@separator}11:00 AM"
    end
  end

  describe "to_string/3 same-day datetime interval exact output" do
    test "date renders once with a time range" do
      result =
        interval(~U[2024-06-01 09:00:00Z], ~U[2024-06-01 11:30:00Z],
          locale: :en,
          prefer: :ascii
        )

      assert result == "Jun 1, 2024, 9:00:00 AM#{@separator}11:30:00 AM"
    end
  end

  describe "greatest_difference/2 minute and second resolution" do
    test "minute difference for times" do
      assert {:ok, :m} = Interval.greatest_difference(~T[10:00:00], ~T[10:30:00])
    end

    test "sub-minute difference is no practical difference" do
      assert {:error, %Localize.NoPracticalDifferenceError{}} =
               Interval.greatest_difference(~T[10:00:00], ~T[10:00:30])

      assert {:error, %Localize.NoPracticalDifferenceError{}} =
               Interval.greatest_difference(
                 ~U[2024-06-01 10:00:00Z],
                 ~U[2024-06-01 10:00:30Z]
               )
    end
  end

  describe "split_interval/1 quoting and repeated fields" do
    test "splits at the first repeated field" do
      assert {:ok, ["MMM d – ", "MMM d"]} = Interval.split_interval("MMM d – MMM d")
    end

    test "quoted literals do not trigger a split" do
      assert {:ok, ["h a 'to' ", "h a"]} = Interval.split_interval("h a 'to' h a")
    end
  end
end
