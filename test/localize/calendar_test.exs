defmodule Localize.CalendarTest do
  use ExUnit.Case, async: true

  doctest Localize.Calendar

  # ── Locale data access ─────────────────────────────────────────

  describe "eras/2" do
    test "returns era names for :en" do
      {:ok, eras} = Localize.Calendar.eras(:en)
      assert get_in(eras, [:abbreviated, 0]) == "BC"
      assert get_in(eras, [:abbreviated, 1]) == "AD"
    end

    test "returns era names for :de" do
      {:ok, eras} = Localize.Calendar.eras(:de)
      assert get_in(eras, [:abbreviated, 0]) == "v. Chr."
      assert get_in(eras, [:abbreviated, 1]) == "n. Chr."
    end
  end

  describe "months/2" do
    test "returns month names for :en" do
      {:ok, months} = Localize.Calendar.months(:en)
      assert get_in(months, [:format, :wide, 1]) == "January"
      assert get_in(months, [:format, :wide, 12]) == "December"
      assert get_in(months, [:format, :abbreviated, 6]) == "Jun"
    end

    test "returns month names for :fr" do
      {:ok, months} = Localize.Calendar.months(:fr)
      assert get_in(months, [:format, :wide, 6]) == "juin"
    end
  end

  describe "days/2" do
    test "returns day names for :en" do
      {:ok, days} = Localize.Calendar.days(:en)
      assert get_in(days, [:format, :wide, 1]) == "Monday"
      assert get_in(days, [:format, :wide, 6]) == "Saturday"
      assert get_in(days, [:format, :wide, 7]) == "Sunday"
    end

    test "returns abbreviated day names" do
      {:ok, days} = Localize.Calendar.days(:en)
      assert get_in(days, [:format, :abbreviated, 1]) == "Mon"
    end
  end

  describe "quarters/2" do
    test "returns quarter names for :en" do
      {:ok, quarters} = Localize.Calendar.quarters(:en)
      assert get_in(quarters, [:format, :abbreviated, 1]) == "Q1"
      assert get_in(quarters, [:format, :abbreviated, 4]) == "Q4"
    end
  end

  describe "day_periods/2" do
    test "returns day period names for :en" do
      {:ok, periods} = Localize.Calendar.day_periods(:en)
      assert get_in(periods, [:format, :abbreviated, :am, :default]) == "AM"
      assert get_in(periods, [:format, :abbreviated, :pm, :default]) == "PM"
    end
  end

  # ── localize/3 ──────────────────────────────────────────────────

  describe "localize/3 with :month" do
    test "returns abbreviated month name" do
      assert Localize.Calendar.localize(~D[2019-06-01], :month) == "Jun"
    end

    test "returns wide month name" do
      assert Localize.Calendar.localize(~D[2019-06-01], :month, format: :wide) == "June"
    end

    test "returns narrow month name" do
      assert Localize.Calendar.localize(~D[2019-06-01], :month, format: :narrow) == "J"
    end

    test "returns month name in German" do
      assert Localize.Calendar.localize(~D[2019-06-01], :month, locale: :de) == "Juni"
    end
  end

  describe "localize/3 with :day_of_week" do
    test "returns abbreviated day name for Saturday" do
      assert Localize.Calendar.localize(~D[2019-06-01], :day_of_week) == "Sat"
    end

    test "returns wide day name" do
      assert Localize.Calendar.localize(~D[2019-06-01], :day_of_week, format: :wide) ==
               "Saturday"
    end

    test "returns narrow day name" do
      assert Localize.Calendar.localize(~D[2019-06-01], :day_of_week, format: :narrow) == "S"
    end

    test "returns day name in Arabic" do
      result = Localize.Calendar.localize(~D[2019-06-01], :day_of_week, locale: :ar)
      assert is_binary(result)
    end
  end

  describe "localize/3 with :era" do
    test "returns AD for positive year" do
      assert Localize.Calendar.localize(~D[2019-01-01], :era) == "AD"
    end

    test "returns CE for variant era" do
      assert Localize.Calendar.localize(~D[2019-01-01], :era, era: :variant) == "CE"
    end
  end

  describe "localize/3 with :quarter" do
    test "returns Q1 for January" do
      assert Localize.Calendar.localize(~D[2019-01-01], :quarter) == "Q1"
    end

    test "returns Q2 for June" do
      assert Localize.Calendar.localize(~D[2019-06-01], :quarter) == "Q2"
    end

    test "returns Q4 for December" do
      assert Localize.Calendar.localize(~D[2019-12-01], :quarter) == "Q4"
    end
  end

  describe "localize/3 with :days_of_week" do
    test "returns all 7 days" do
      days = Localize.Calendar.localize(~D[2019-01-01], :days_of_week)
      assert length(days) == 7
      assert {1, "Mon"} = hd(days)
      assert {7, "Sun"} = List.last(days)
    end
  end

  # ── strftime_options! ───────────────────────────────────────────

  describe "strftime_options!/1" do
    test "returns month name callbacks for :en" do
      options = Localize.Calendar.strftime_options!(locale: :en)
      assert options[:month_names].(6) == "June"
      assert options[:abbreviated_month_names].(6) == "Jun"
    end

    test "returns day name callbacks for :en" do
      options = Localize.Calendar.strftime_options!(locale: :en)
      assert options[:day_of_week_names].(6) == "Saturday"
      assert options[:abbreviated_day_of_week_names].(1) == "Mon"
    end

    test "returns AM/PM callbacks for :en" do
      options = Localize.Calendar.strftime_options!(locale: :en)
      assert options[:am_pm_names].(:am) == "AM"
      assert options[:am_pm_names].(:pm) == "PM"
    end

    test "returns German month names" do
      options = Localize.Calendar.strftime_options!(locale: :de)
      assert options[:month_names].(1) == "Januar"
    end

    test "returns German day names" do
      options = Localize.Calendar.strftime_options!(locale: :de)
      assert options[:abbreviated_day_of_week_names].(1) == "Mo."
    end
  end

  # ── Territory preferences ───────────────────────────────────────

  describe "first_day_for_territory/1" do
    test "US starts on Sunday" do
      assert Localize.Calendar.first_day_for_territory(:US) == 7
    end

    test "GB starts on Monday" do
      assert Localize.Calendar.first_day_for_territory(:GB) == 1
    end
  end

  describe "min_days_for_territory/1" do
    test "US min days is 1" do
      assert Localize.Calendar.min_days_for_territory(:US) == 1
    end

    test "GB min days is 4" do
      assert Localize.Calendar.min_days_for_territory(:GB) == 4
    end
  end

  describe "weekend/1" do
    test "US weekend is Saturday-Sunday" do
      assert Localize.Calendar.weekend(:US) == [6, 7]
    end

    test "Israel weekend is Friday-Saturday" do
      assert Localize.Calendar.weekend(:IL) == [5, 6]
    end
  end

  describe "weekdays/1" do
    test "US weekdays" do
      assert Localize.Calendar.weekdays(:US) == [1, 2, 3, 4, 5]
    end
  end

  # ── Calendar data availability ─────────────────────────────────

  describe "Buddhist calendar data" do
    test "has era names" do
      {:ok, eras} = Localize.Calendar.eras(:en, :buddhist)
      assert get_in(eras, [:abbreviated, 0]) == "BE"
    end

    test "has month names" do
      {:ok, months} = Localize.Calendar.months(:en, :buddhist)
      assert get_in(months, [:format, :wide, 1]) == "January"
    end
  end

  describe "Hebrew calendar data" do
    test "has era names" do
      {:ok, eras} = Localize.Calendar.eras(:en, :hebrew)
      assert get_in(eras, [:abbreviated, 0]) == "AM"
    end

    test "has month names" do
      {:ok, months} = Localize.Calendar.months(:en, :hebrew)
      assert get_in(months, [:format, :wide, 1]) == "Tishri"
      assert get_in(months, [:format, :wide, 8]) == "Nisan"
    end
  end

  describe "Islamic calendar data" do
    test "has era names for :islamic" do
      {:ok, eras} = Localize.Calendar.eras(:en, :islamic)
      assert get_in(eras, [:abbreviated, 0]) == "AH"
    end

    test "has month names for :islamic" do
      {:ok, months} = Localize.Calendar.months(:en, :islamic)
      assert get_in(months, [:format, :wide, 1]) == "Muharram"
      assert get_in(months, [:format, :wide, 9]) == "Ramadan"
    end

    test "has era names for :islamic_civil" do
      {:ok, eras} = Localize.Calendar.eras(:en, :islamic_civil)
      assert get_in(eras, [:abbreviated, 0]) == "AH"
    end

    test "has era names for :islamic_umalqura" do
      {:ok, eras} = Localize.Calendar.eras(:en, :islamic_umalqura)
      assert get_in(eras, [:abbreviated, 0]) == "AH"
    end
  end

  describe "ROC (Minguo) calendar data" do
    test "has era names" do
      {:ok, eras} = Localize.Calendar.eras(:en, :roc)
      assert get_in(eras, [:abbreviated, 0]) == "B.R.O.C."
      assert get_in(eras, [:abbreviated, 1]) == "Minguo"
    end

    test "has month names" do
      {:ok, months} = Localize.Calendar.months(:en, :roc)
      assert get_in(months, [:format, :wide, 1]) == "January"
    end
  end

  describe "known_calendars/0 includes all calendar systems" do
    test "includes Buddhist, Hebrew, Islamic variants, and ROC" do
      calendars = Localize.Calendar.known_calendars()
      assert :buddhist in calendars
      assert :hebrew in calendars
      assert :islamic in calendars
      assert :islamic_civil in calendars
      assert :islamic_umalqura in calendars
      assert :roc in calendars
      assert :indian in calendars
    end
  end

  describe "first_day_for_locale/1" do
    test "returns first day for :en locale" do
      assert Localize.Calendar.first_day_for_locale(:en) == 7
    end
  end
end
