defmodule Localize.DateTime.CyclicYearSymbolTest do
  use ExUnit.Case, async: true

  # Exercises the cyclic year (U) and related Gregorian year (r)
  # format symbols in Localize.DateTime.Formatter.
  #
  # Chinese-style calendars live in the Calendrical library, which
  # depends on Localize (so Localize cannot depend on it). The
  # formatter instead probes the date's calendar module for the
  # protocol functions `cldr_calendar_type/0`, `cyclic_year/3` and
  # `related_gregorian_year/3`. FakeChineseCalendar implements that
  # protocol with fixed values verified against Calendrical:
  # Gregorian 2026-07-05 is Chinese elapsed year 4663 (cycle
  # position 43, 丙午 / "bing-wu"), which began on 2026-02-17.

  defmodule FakeChineseCalendar do
    @moduledoc false

    def cldr_calendar_type, do: :chinese

    # Elapsed years since the Chinese epoch; amod(4663, 60) == 43.
    def cyclic_year(year, _month, _day), do: year

    def related_gregorian_year(year, _month, _day), do: year - 2637
  end

  @chinese_date %{calendar: FakeChineseCalendar, year: 4663, month: 5, day: 21}

  describe "cyclic year (U)" do
    test "renders the abbreviated cyclic name for U, UU and UUU" do
      for format <- ["U", "UU", "UUU"] do
        assert Localize.DateTime.to_string(@chinese_date, format: format, locale: :en) ==
                 {:ok, "bing-wu"}
      end
    end

    test "renders the wide cyclic name for UUUU" do
      assert Localize.DateTime.to_string(@chinese_date, format: "UUUU", locale: :ja) ==
               {:ok, "丙午"}
    end

    test "reduces the elapsed year to its 1..60 cycle position" do
      # Elapsed year 4662 (Gregorian 2025) is position 42, 乙巳 "yi-si".
      date = %{@chinese_date | year: 4662, month: 12, day: 27}

      assert Localize.DateTime.to_string(date, format: "U", locale: :en) == {:ok, "yi-si"}
    end

    test "falls back to the numeric year for calendars without cyclic names" do
      assert Localize.DateTime.to_string(~D[2026-07-05], format: "U", locale: :en) ==
               {:ok, "2026"}
    end
  end

  describe "related Gregorian year (r)" do
    test "renders the Gregorian year in which the calendar year begins" do
      assert Localize.DateTime.to_string(@chinese_date, format: "r", locale: :en) ==
               {:ok, "2026"}
    end

    test "is constant for dates late in the calendar year" do
      # Chinese 4662-12-27 falls on Gregorian 2026-01-15, before the
      # 4663 new year; its related year is 2025, not 2026.
      date = %{@chinese_date | year: 4662, month: 12, day: 27}

      assert Localize.DateTime.to_string(date, format: "r", locale: :en) == {:ok, "2025"}
    end

    test "pads to the requested count" do
      assert Localize.DateTime.to_string(@chinese_date, format: "rrrrr", locale: :en) ==
               {:ok, "02026"}
    end

    test "is the date's own year for Calendar.ISO" do
      assert Localize.DateTime.to_string(~D[2026-07-05], format: "r", locale: :en) ==
               {:ok, "2026"}
    end
  end

  describe "combined patterns" do
    test "formats the CLDR chinese pattern shape r(U)" do
      assert Localize.DateTime.to_string(@chinese_date, format: "r(U)", locale: :en) ==
               {:ok, "2026(bing-wu)"}
    end
  end
end
