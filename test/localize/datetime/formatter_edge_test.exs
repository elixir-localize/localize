defmodule Localize.DateTime.FormatterEdgeTest.CalendarYearCalendar do
  @moduledoc false
  # Minimal calendar exposing `calendar_year/3` so the formatter's
  # preferred era-year branch (used by Calendrical era-aware
  # calendars) is exercised.

  def calendar_year(_year, _month, _day), do: 12
  def cldr_calendar_type, do: :gregorian

  def day_of_week(year, month, day, starting),
    do: Calendar.ISO.day_of_week(year, month, day, starting)
end

defmodule Localize.DateTime.FormatterEdgeTest.BadYearOfEraCalendar do
  @moduledoc false
  # Calendar whose `year_of_era/3` returns a non-tuple, forcing the
  # formatter to fall back to the proleptic year.

  def year_of_era(_year, _month, _day), do: :not_a_tuple
  def cldr_calendar_type, do: :gregorian
end

defmodule Localize.DateTime.FormatterEdgeTest do
  use ExUnit.Case, async: true

  # Second-round coverage for Localize.DateTime.Formatter: lenient
  # missing-field rendering, quoting edge cases, wide-count padding,
  # locale week configuration, number-system overrides, calendar
  # derivation fallbacks, and the timezone symbol family.

  alias Localize.DateTime.Formatter
  alias Localize.DateTime.FormatterEdgeTest.BadYearOfEraCalendar
  alias Localize.DateTime.FormatterEdgeTest.CalendarYearCalendar

  @date ~D[2024-07-06]
  @time ~T[14:30:45.123456]
  @utc_datetime ~U[2024-07-06 14:30:45Z]

  defp date_format(date, format, locale \\ :en) do
    {:ok, result} = Localize.Date.to_string(date, format: format, locale: locale)
    result
  end

  defp time_format(time, format, locale \\ :en) do
    {:ok, result} = Localize.Time.to_string(time, format: format, locale: locale)
    result
  end

  defp datetime_format(datetime, format, locale \\ :en) do
    {:ok, result} = Localize.DateTime.to_string(datetime, format: format, locale: locale)
    result
  end

  describe "lenient rendering of missing fields" do
    test "remaining date symbols render empty against a Time" do
      assert time_format(@time, "Y u U r q D W F e c L") == "          "
    end

    test "time symbols and the {0} placeholder render empty against a Date" do
      assert date_format(@date, "a b B h K k m s S A {0}") == "          "
    end

    test "the {1} date placeholder renders empty against a Time" do
      assert time_format(@time, "{1}") == ""
    end

    test "the z zone symbol renders empty against a Date" do
      assert date_format(@date, "z") == ""
    end
  end

  describe "wide-count padding and caps" do
    test "S wider than the microsecond precision caps at six digits" do
      assert time_format(@time, "SSSSSSS") == "123456"
    end

    test "A pads milliseconds of day to the requested width" do
      assert time_format(@time, "AAAAAAAAAA") == "0052245123"
    end

    test "hour symbols pad to counts greater than two" do
      assert time_format(@time, "hhh:KKK:kkk") == "002:002:014"
    end

    test "seven-wide E falls back to the abbreviated day name" do
      assert date_format(@date, "EEEEEEE") == "Sat"
    end

    test "six-wide L renders empty (no short month names)" do
      assert date_format(@date, "LLLLLL") == ""
    end

    test "three-wide Y pads the week-aligned year" do
      assert date_format(@date, "YYY") == "2024"
    end

    test "uuuu zero-pads a small extended year" do
      assert date_format(~D[0005-03-01], "uuuu") == "0005"
    end
  end

  describe "literal quoting edge cases" do
    test "a lone doubled quote renders a literal apostrophe" do
      assert time_format(@time, "h''") == "2'"
    end

    test "quoted literal adjacent to symbols is preserved" do
      assert time_format(@time, "z'at'HH") == "at14"
    end
  end

  describe "empty-zone elision around literals" do
    test "a non-whitespace literal before an empty zone is kept intact" do
      assert time_format(@time, "HH:mm'x'z") == "14:30x"
    end

    test "trailing whitespace inside a literal before an empty zone is trimmed" do
      assert time_format(@time, "HH:mm 'Uhr 'z") == "14:30 Uhr"
    end

    test "a leading empty zone swallows the following whitespace literal" do
      assert time_format(@time, "z HH:mm") == "14:30"
    end

    test "leading whitespace inside a literal after an empty zone is trimmed" do
      assert time_format(@time, "zzz' at 'HH:mm") == "at 14:30"
    end

    test "a non-literal value before an empty zone is kept" do
      assert time_format(@time, "Hz") == "14"
    end
  end

  describe "flexible day periods (B) fallbacks and ranges" do
    test "a language without day-period rules falls back to AM/PM names" do
      # `aa` has no entry in the supplemental day-period rules, so B
      # renders the locale's AM/PM marker instead.
      assert time_format(~T[15:00:00], "B", :aa) == "carra"
    end

    test "a range that wraps midnight selects the night period" do
      assert time_format(~T[23:00:00], "B") == "at night"
    end
  end

  describe "locale week configuration (Y, w, W)" do
    test "a date before week one belongs to the previous week-aligned year in de" do
      # 2022-01-01 is a Saturday; with de's firstDay monday and
      # minDays 4 it falls in week 52 of week-aligned year 2021.
      assert date_format(~D[2022-01-01], "YYYY-ww", :de) == "2021-52"
    end

    test "the same date is week one in en (minDays 1)" do
      assert date_format(~D[2022-01-01], "YYYY-ww", :en) == "2022-01"
    end

    test "W renders week zero when the leading partial week is too short" do
      # 2021-10-01 is a Friday; the partial first week has three days,
      # fewer than de's minDays 4, so per ICU it counts as week 0.
      assert date_format(~D[2021-10-01], "W", :de) == "0"
    end
  end

  describe "number system overrides" do
    test "a numeric system override transliterates a single field" do
      assert {:ok, "٢٠٢٤"} =
               Formatter.format(@date, "y", :en, %{number_system_overrides: %{"y" => :arab}})
    end

    test "an \"all\" override transliterates every numeric field" do
      assert {:ok, "٢٠٢٤-٠٧-٠٦"} =
               Formatter.format(@date, "y-MM-dd", :en, %{
                 number_system_overrides: %{"all" => :arab}
               })
    end

    test "an algorithmic override renders through RBNF rules" do
      assert {:ok, "ב׳כ״ד"} =
               Formatter.format(@date, "y", :he, %{number_system_overrides: %{"y" => :hebr}})
    end

    test "an algorithmic override resolves the rule against root for other locales" do
      assert {:ok, "ב׳כ״ד"} =
               Formatter.format(@date, "y", :en, %{number_system_overrides: %{"y" => :hebr}})
    end

    test "roman numerals via an algorithmic month override" do
      assert {:ok, "VII"} =
               Formatter.format(@date, "M", :en, %{number_system_overrides: %{"M" => :roman}})
    end

    test "an unknown number system falls back to ASCII digits" do
      assert {:ok, "2024"} =
               Formatter.format(@date, "y", :en, %{number_system_overrides: %{"y" => :bogus}})
    end

    test "string-keyed override maps are honoured" do
      assert {:ok, "٦"} =
               Formatter.format(@date, "d", :en, %{
                 "number_system_overrides" => %{"d" => :arab}
               })
    end
  end

  describe "format/3 and option-bag flexibility" do
    test "format/3 defaults the options argument" do
      assert {:ok, "2024"} = Formatter.format(@date, "y", :en)
    end

    test "the {1} placeholder honours date_format and prefer from a map bag" do
      assert {:ok, "7/6/24"} =
               Formatter.format(@date, "{1}", :en, %{date_format: :short, prefer: :ascii})
    end
  end

  describe "calendar derivation fallbacks" do
    test "a calendar exporting calendar_year/3 supplies the displayed year" do
      date = %{year: 2024, month: 7, day: 6, calendar: CalendarYearCalendar}
      assert date_format(date, "y") == "12"
    end

    test "a calendar whose year_of_era/3 returns a non-tuple falls back to the year" do
      date = %{year: 2024, month: 7, day: 6, calendar: BadYearOfEraCalendar}
      assert date_format(date, "y") == "2024"
    end

    test "W on a non-ISO calendar uses the plain day-of-month derivation" do
      date = %{year: 2024, month: 7, day: 20, calendar: CalendarYearCalendar}
      assert date_format(date, "W") == "3"
    end

    test "the {1} placeholder accepts a bare map without a :calendar key" do
      assert {:ok, "Jul 6, 2024"} =
               Formatter.format(%{year: 2024, month: 7, day: 6}, "{1}", :en, %{})
    end

    test "A accepts a partial time map without a microsecond field" do
      assert {:ok, "3723000"} =
               Localize.Time.to_string(%{hour: 1, minute: 2, second: 3},
                 format: "A",
                 locale: :en
               )
    end
  end

  describe "timezone symbols on a UTC DateTime" do
    test "z widths render the specific non-location name" do
      assert datetime_format(@utc_datetime, "z") == "GMT"
      assert datetime_format(@utc_datetime, "zzzz") == "Greenwich Mean Time"
    end

    test "Z widths render basic, GMT, and extended ISO forms" do
      assert datetime_format(@utc_datetime, "Z") == "+0000"
      assert datetime_format(@utc_datetime, "ZZZZ") == "GMT"
      assert datetime_format(@utc_datetime, "ZZZZZ") == "Z"
    end

    test "six-wide Z renders empty (no such width)" do
      assert datetime_format(@utc_datetime, "ZZZZZZ") == ""
    end

    test "O widths render localized GMT formats" do
      assert datetime_format(@utc_datetime, "O") == "GMT+0"
      assert datetime_format(@utc_datetime, "OO") == "GMT"
      assert datetime_format(@utc_datetime, "OOOO") == "GMT+00:00"
    end

    test "v widths render the generic non-location name" do
      assert datetime_format(@utc_datetime, "v") == "GMT"
      assert datetime_format(@utc_datetime, "vvvv") == "GMT"
    end

    test "V widths render zone id and location formats" do
      assert datetime_format(@utc_datetime, "V") == "Etc/UTC"
      assert datetime_format(@utc_datetime, "VV") == "Etc/UTC"
      assert datetime_format(@utc_datetime, "VVV") == "GMT"
      assert datetime_format(@utc_datetime, "VVVV") == "GMT"
    end

    test "x widths render ISO offsets without Z" do
      assert datetime_format(@utc_datetime, "x") == "+00"
      assert datetime_format(@utc_datetime, "xx") == "+0000"
      assert datetime_format(@utc_datetime, "xxx") == "+00:00"
      assert datetime_format(@utc_datetime, "xxxx") == "+0000"
      assert datetime_format(@utc_datetime, "xxxxx") == "+00:00"
    end

    test "six-wide x falls back to the long basic ISO form" do
      assert datetime_format(@utc_datetime, "xxxxxx") == "+0000"
    end

    test "X widths render Z for a zero offset" do
      assert datetime_format(@utc_datetime, "X") == "Z"
      assert datetime_format(@utc_datetime, "XXXX") == "Z"
    end
  end

  describe "timezone symbols on an offset-only map" do
    # A map carrying `:utc_offset` but no `:time_zone` takes the
    # localized-GMT fallback paths of the zone handlers.
    @offset_only %{utc_offset: 3600, std_offset: 0, hour: 10, minute: 0}

    test "z falls back to short and long GMT formats" do
      assert {:ok, "GMT+1"} = Formatter.format(@offset_only, "z", :en, %{})
      assert {:ok, "GMT+01:00"} = Formatter.format(@offset_only, "zzzz", :en, %{})
    end

    test "v falls back to the localized GMT format" do
      assert {:ok, "GMT+01:00"} = Formatter.format(@offset_only, "v", :en, %{})
    end

    test "VVVV falls back to the localized GMT format" do
      assert {:ok, "GMT+01:00"} = Formatter.format(@offset_only, "VVVV", :en, %{})
    end
  end
end
