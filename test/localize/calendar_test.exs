defmodule Localize.CalendarTest.BuddhistLikeCalendar do
  @moduledoc false
  # Minimal era-aware calendar: reports the Buddhist CLDR calendar
  # type and a `year_of_era/3` returning the BE era-year and the
  # Buddhist era index 0.

  def cldr_calendar_type, do: :buddhist
  def year_of_era(year, _month, _day), do: {year + 543, 0}

  def day_of_week(year, month, day, starting),
    do: Calendar.ISO.day_of_week(year, month, day, starting)
end

defmodule Localize.CalendarTest.NoYearOfEraCalendar do
  @moduledoc false
  # Calendar without a `year_of_era/3` callback; era localization
  # falls back to the year>0 → era 1 heuristic.

  def cldr_calendar_type, do: :gregorian
end

defmodule Localize.CalendarTest.BadYearOfEraCalendar do
  @moduledoc false
  # Calendar whose `year_of_era/3` returns a non-tuple; era
  # localization falls back to the year>0 → era 1 heuristic.

  def cldr_calendar_type, do: :gregorian
  def year_of_era(_year, _month, _day), do: :not_a_tuple
end

defmodule Localize.CalendarTest do
  use ExUnit.Case, async: true

  alias Localize.CalendarTest.BadYearOfEraCalendar
  alias Localize.CalendarTest.BuddhistLikeCalendar
  alias Localize.CalendarTest.NoYearOfEraCalendar

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

    test "the -u-fw- extension overrides the territory default" do
      assert Localize.Calendar.first_day_for_locale("en-u-fw-mon") == 1
      assert Localize.Calendar.first_day_for_locale("en-u-fw-sat") == 6
      assert Localize.Calendar.first_day_for_locale("de-u-fw-sun") == 7

      {:ok, tag} = Localize.validate_locale("en-u-fw-wed")
      assert Localize.Calendar.first_day_for_locale(tag) == 3
    end

    test "returns an error for an invalid locale" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Localize.Calendar.first_day_for_locale(:zzz)
    end
  end

  describe "min_days_for_locale/1" do
    test "returns min days for :de locale" do
      assert Localize.Calendar.min_days_for_locale(:de) == 4
    end

    test "returns an error for an invalid locale" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Localize.Calendar.min_days_for_locale(:zzz)
    end
  end

  describe "territory fallbacks to the world default" do
    test "unknown territory first day falls back to Monday" do
      assert Localize.Calendar.first_day_for_territory(:ZZ) == 1
    end

    test "unknown territory min days falls back to one" do
      assert Localize.Calendar.min_days_for_territory(:ZZ) == 1
    end

    test "unknown territory weekend falls back to Saturday-Sunday" do
      assert Localize.Calendar.weekend(:ZZ) == [6, 7]
    end
  end

  # ── display_name/3 ─────────────────────────────────────────────

  describe "display_name/3 with :calendar" do
    test "returns the localized calendar name" do
      assert {:ok, "Buddhist Calendar"} = Localize.Calendar.display_name(:calendar, :buddhist)
    end

    test "localizes the calendar name for :de" do
      assert {:ok, "Gregorianischer Kalender"} =
               Localize.Calendar.display_name(:calendar, :gregorian, locale: :de)
    end

    test "returns an error for an unknown calendar" do
      assert {:error, %Localize.UnknownCalendarError{calendar: :bogus}} =
               Localize.Calendar.display_name(:calendar, :bogus)
    end
  end

  describe "display_name/3 with :date_time_field" do
    test "returns the wide field name by default" do
      assert {:ok, "day of the week"} =
               Localize.Calendar.display_name(:date_time_field, :weekday)
    end

    test "supports :short and :narrow styles" do
      assert {:ok, "yr."} =
               Localize.Calendar.display_name(:date_time_field, :year, style: :short)

      assert {:ok, "yr"} =
               Localize.Calendar.display_name(:date_time_field, :year, style: :narrow)
    end

    test "returns an error for an unknown field" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Calendar.display_name(:date_time_field, :bogus)
    end
  end

  describe "display_name/3 with :era" do
    test "returns wide era names by index" do
      assert {:ok, "Before Christ"} = Localize.Calendar.display_name(:era, 0)
      assert {:ok, "Anno Domini"} = Localize.Calendar.display_name(:era, 1)
    end

    test "supports the :abbreviated style" do
      assert {:ok, "AD"} = Localize.Calendar.display_name(:era, 1, style: :abbreviated)
    end

    test "returns an error for an unknown era index" do
      assert {:error, %Localize.InvalidValueError{value: 99}} =
               Localize.Calendar.display_name(:era, 99)
    end

    test "returns an error for a non-integer era value" do
      assert {:error, %Localize.InvalidValueError{value: :not_index}} =
               Localize.Calendar.display_name(:era, :not_index)
    end
  end

  describe "display_name/3 with :quarter, :month, and :day" do
    test "quarter supports the :stand_alone context" do
      assert {:ok, "1st quarter"} =
               Localize.Calendar.display_name(:quarter, 1, context: :stand_alone)
    end

    test "quarter outside 1..4 is an invalid value" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Calendar.display_name(:quarter, 5)
    end

    test "month 13 exists in the Hebrew calendar but not Gregorian" do
      assert {:ok, "Elul"} = Localize.Calendar.display_name(:month, 13, calendar: :hebrew)

      assert {:error, %Localize.InvalidValueError{value: 13}} =
               Localize.Calendar.display_name(:month, 13)
    end

    test "month outside 1..13 is an invalid value" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Calendar.display_name(:month, 99)
    end

    test "day 7 is Sunday and day 8 is invalid" do
      assert {:ok, "Sunday"} = Localize.Calendar.display_name(:day, 7)

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Calendar.display_name(:day, 8)
    end
  end

  describe "display_name/3 with :day_period" do
    test "returns noon and midnight names" do
      assert {:ok, "noon"} = Localize.Calendar.display_name(:day_period, :noon)

      assert {:ok, "midnight"} =
               Localize.Calendar.display_name(:day_period, :midnight, style: :wide)
    end

    test "returns an error for an unknown day period" do
      assert {:error, %Localize.InvalidValueError{value: :bogus}} =
               Localize.Calendar.display_name(:day_period, :bogus)
    end
  end

  describe "display_name!/3" do
    test "returns the name directly" do
      assert Localize.Calendar.display_name!(:day, 1, style: :short) == "Mo"
    end

    test "raises on an invalid value" do
      assert_raise Localize.InvalidValueError, fn ->
        Localize.Calendar.display_name!(:month, 99)
      end
    end
  end

  # ── Cyclic years and month patterns ────────────────────────────

  describe "cyclic_years/2" do
    test "returns cyclic name sets for the Dangi calendar" do
      {:ok, cyclic} = Localize.Calendar.cyclic_years(:en, :dangi)
      assert get_in(cyclic, [:zodiacs, :format, :abbreviated, 1]) == "Rat"
    end

    test "returns an error for a calendar without cyclic names" do
      assert {:error, %Localize.ItemNotFoundError{}} =
               Localize.Calendar.cyclic_years(:en, :gregorian)
    end
  end

  describe "month_patterns/2" do
    test "returns leap month patterns for the Chinese calendar" do
      {:ok, patterns} = Localize.Calendar.month_patterns(:en, :chinese)
      assert get_in(patterns, [:format, :wide, :leap]) == [0, "bis"]
    end

    test "returns an error for a calendar without month patterns" do
      assert {:error, %Localize.ItemNotFoundError{}} =
               Localize.Calendar.month_patterns(:en, :gregorian)
    end
  end

  describe "data access error paths" do
    test "eras/2 returns an error for an invalid locale" do
      assert {:error, %Localize.InvalidLocaleError{}} = Localize.Calendar.eras(:zzz)
    end
  end

  # ── localize/3 remaining branches ───────────────────────────────

  describe "localize/3 :era with era-aware calendars" do
    test "a calendar reporting year_of_era and a Buddhist type renders BE" do
      date = %{year: 2020, month: 6, day: 1, calendar: BuddhistLikeCalendar}
      assert Localize.Calendar.localize(date, :era, locale: :en) == "BE"
    end

    test "a calendar without year_of_era falls back to the year sign" do
      date = %{year: 2020, month: 6, day: 1, calendar: NoYearOfEraCalendar}
      assert Localize.Calendar.localize(date, :era, locale: :en) == "AD"
    end

    test "a calendar with a malformed year_of_era falls back to the year sign" do
      date = %{year: 2020, month: 6, day: 1, calendar: BadYearOfEraCalendar}
      assert Localize.Calendar.localize(date, :era, locale: :en) == "AD"
    end

    test "a BC date renders the era at index zero, with variant BCE" do
      bc_date = %Date{year: -100, month: 1, day: 1, calendar: Calendar.ISO}

      assert Localize.Calendar.localize(bc_date, :era, locale: :en) == "BC"
      assert Localize.Calendar.localize(bc_date, :era, locale: :en, era: :variant) == "BCE"
    end
  end

  describe "localize/3 :am_pm variants and errors" do
    test "the :variant option selects lowercase names in en" do
      assert Localize.Calendar.localize(~T[15:00:00], :am_pm, locale: :en, am_pm: :variant) ==
               "pm"
    end

    test "localizes AM/PM for Japanese" do
      assert Localize.Calendar.localize(~T[15:00:00], :am_pm, locale: :ja) == "午後"
    end

    test "a value without an hour returns an InvalidValueError" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Calendar.localize(~D[2024-07-06], :am_pm, locale: :en)
    end
  end

  describe "localize/3 :day_of_week calendar fallbacks" do
    test "a calendar module without day_of_week/4 falls back to Calendar.ISO" do
      date = %{year: 2024, month: 7, day: 6, calendar: NoYearOfEraCalendar}
      assert Localize.Calendar.localize(date, :day_of_week, locale: :en) == "Sat"
    end

    test "a bare map without a :calendar key uses Calendar.ISO" do
      date = %{year: 2024, month: 7, day: 6}
      assert Localize.Calendar.localize(date, :day_of_week, locale: :en) == "Sat"
    end
  end

  describe "localize/3 defaults for maps without date fields" do
    # Characterization: maps lacking the relevant fields resolve to
    # the first value of each category rather than erroring.
    test "era defaults to the current era" do
      assert Localize.Calendar.localize(%{}, :era, locale: :en) == "AD"
    end

    test "quarter defaults to Q1" do
      assert Localize.Calendar.localize(%{}, :quarter, locale: :en) == "Q1"
    end

    test "month defaults to January" do
      assert Localize.Calendar.localize(%{}, :month, locale: :en) == "Jan"
    end

    test "day of week defaults to Monday" do
      assert Localize.Calendar.localize(%{}, :day_of_week, locale: :en) == "Mon"
    end
  end

  describe "localize/3 :month in the :stand_alone context" do
    test "Russian stand-alone months are nominative" do
      assert Localize.Calendar.localize(~D[2024-01-15], :month,
               locale: :ru,
               context: :stand_alone,
               format: :wide
             ) == "январь"
    end
  end

  # ── strftime_options! remaining branches ───────────────────────

  describe "strftime_options!/1 defaults and errors" do
    test "defaults the options argument" do
      options = Localize.Calendar.strftime_options!()

      assert Keyword.keys(options) == [
               :am_pm_names,
               :month_names,
               :abbreviated_month_names,
               :day_of_week_names,
               :abbreviated_day_of_week_names
             ]
    end

    test "raises for an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Localize.Calendar.strftime_options!(locale: :zzz)
      end
    end

    test "the am_pm callback returns an empty string for unknown keys" do
      options = Localize.Calendar.strftime_options!(locale: :en)
      assert options[:am_pm_names].(:bogus) == ""
    end
  end
end
