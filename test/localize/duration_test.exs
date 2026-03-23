defmodule Localize.DurationTest do
  use ExUnit.Case, async: true

  doctest Localize.Duration

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
      assert s == "11 months and 30 days"
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
  end

  # ── to_time_string!/2 ─────────────────────────────────────────

  describe "to_time_string!/2" do
    test "returns string directly" do
      d = Localize.Duration.new_from_seconds(136_092)
      assert "37:48:12" = Localize.Duration.to_time_string!(d)
    end
  end
end
