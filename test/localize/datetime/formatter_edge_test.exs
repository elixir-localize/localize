defmodule Localize.DateTime.FormatterEdgeTest.CalendarYearCalendar do
  @moduledoc false
  # A calendar whose `calendar_year/3` numbers every year 12, as an
  # era-aware calendar numbers its years within the era.
  use Localize.Test.StandInCalendar

  def calendar_year(_year, _month, _day), do: 12
end

defmodule Localize.DateTime.FormatterEdgeTest.BadYearOfEraCalendar do
  @moduledoc false
  # A calendar whose `year_of_era/3` answers with something that is not a
  # year of era and an era.
  use Localize.Test.StandInCalendar

  def year_of_era(_year, _month, _day), do: :not_a_tuple
end

defmodule Localize.DateTime.FormatterEdgeTest.BeforeEraCalendar do
  @moduledoc false
  # Numbers years as Calendrical's Gregorian calendar does: `calendar_year/3`
  # gives the year as it is, and `year_of_era/3` counts a year below 1 back
  # from the era, year 0 being 1 BC.
  use Localize.Test.StandInCalendar

  def year_of_era(year, _month, _day) when year > 0, do: {year, 1}
  def year_of_era(year, _month, _day), do: {1 - year, 0}
end

defmodule Localize.DateTime.FormatterEdgeTest.NoYearZeroCalendar do
  @moduledoc false
  # Numbers years as Calendrical's Julian calendar does, with no year 0, so
  # year -1 is 1 BC.
  use Localize.Test.StandInCalendar

  def year_of_era(year, _month, _day) when year > 0, do: {year, 1}
  def year_of_era(year, _month, _day), do: {-year, 0}
end

defmodule Localize.DateTime.FormatterEdgeTest do
  use ExUnit.Case, async: true

  # Second-round coverage for Localize.DateTime.Formatter: lenient
  # missing-field rendering, quoting edge cases, wide-count padding,
  # locale week configuration, number-system overrides, calendar
  # derivation fallbacks, and the timezone symbol family.

  alias Localize.DateTime.Formatter
  alias Localize.DateTime.FormatterEdgeTest.BadYearOfEraCalendar
  alias Localize.DateTime.FormatterEdgeTest.BeforeEraCalendar
  alias Localize.DateTime.FormatterEdgeTest.CalendarYearCalendar
  alias Localize.DateTime.FormatterEdgeTest.NoYearZeroCalendar

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

  describe "fields the value does not hold" do
    # A pattern asking for a field the value lacks is an error naming the
    # fields; only zone symbols, which TR35 gives fallbacks, render empty.
    test "the remaining date symbols against a Time" do
      assert {:error, %Localize.DateTimeInvalidInputError{missing: [:year, :month, :day]}} =
               Localize.Time.to_string(@time, format: "Y u U r q D W F e c L g", locale: :en)
    end

    test "the time symbols and the {0} placeholder against a Date" do
      assert {:error,
              %Localize.DateTimeInvalidInputError{
                missing: [:hour, :minute, :second, :microsecond]
              }} = Localize.Date.to_string(@date, format: "a b B h K k m s S A {0}", locale: :en)
    end

    test "the {1} date placeholder against a Time" do
      assert {:error, %Localize.DateTimeInvalidInputError{missing: [:year, :month, :day]}} =
               Localize.Time.to_string(@time, format: "{1}", locale: :en)
    end

    test "a field holding the wrong type is reported as invalid" do
      assert {:error, %Localize.DateTimeInvalidInputError{missing: [], invalid: [:year]}} =
               Localize.Date.to_string(%{year: "2024", month: 7, day: 6},
                 format: "y",
                 locale: :en
               )
    end

    test "the z zone symbol renders empty against a Date" do
      assert date_format(@date, "z") == ""
    end
  end

  describe "wide-count padding and caps" do
    test "S wider than six digits pads with zeros to its width" do
      # TR35: a fractional second truncates, or pads, to exactly as many
      # digits as the field has letters.
      assert time_format(@time, "SSSSSSS") == "1234560"
    end

    test "A pads milliseconds of day to the requested width" do
      assert time_format(@time, "AAAAAAAAAA") == "0052245123"
    end

    # TR35 lists no longer widths for these symbols, so each is an invalid
    # field that formats as U+FFFD, where ICU pads or clamps it.
    test "hour symbols wider than two are invalid fields" do
      assert time_format(@time, "hhh:KKK:kkk") == "�:�:�"
    end

    test "seven-wide E is an invalid field" do
      assert date_format(@date, "EEEEEEE") == "�"
    end

    test "six-wide L is an invalid field" do
      assert date_format(@date, "LLLLLL") == "�"
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

  describe "digit boundaries between fields" do
    # TR35 §Boundary Spacing (CLDR-19227): zh's `Hmsv` is "vHH:mm:ss". A zone
    # with neither a name nor a location falls back to the localized GMT
    # format, whose digits would run into the hour's; root's
    # placeholderBoundarySpacing, a space, sets them apart.
    @gmt_plus_8 %DateTime{
      year: 2024,
      month: 7,
      day: 6,
      hour: 14,
      minute: 30,
      second: 45,
      microsecond: {0, 0},
      time_zone: "Etc/GMT-8",
      zone_abbr: "+08",
      utc_offset: 28_800,
      std_offset: 0,
      calendar: Calendar.ISO
    }

    test "a zone ending in a digit is set apart from the hour" do
      assert {:ok, "GMT+8 14:30:45"} =
               Localize.DateTime.to_string(@gmt_plus_8, format: :Hmsv, locale: :zh)
    end

    test "the parts carry the spacing as a literal" do
      assert {:ok, parts} = Localize.DateTime.to_parts(@gmt_plus_8, format: :Hmsv, locale: :zh)
      assert Enum.map_join(parts, & &1.value) == "GMT+8 14:30:45"
      assert %{type: :literal, value: " "} in parts
    end

    # Two numeric fields written together are meant to run together.
    test "numeric fields written together stay together" do
      assert {:ok, "20240706"} =
               Localize.DateTime.to_string(@gmt_plus_8, format: "yyyyMMdd", locale: :zh)
    end
  end

  describe "flexible day periods (B) fallbacks and ranges" do
    test "a language without day-period rules falls back to AM/PM names" do
      # `ak` has no entry in the supplemental day-period rules, so B
      # renders the locale's AM/PM marker instead — abbreviated, since a
      # single `B` selects that width. This was `aa` until CLDR 49 stopped
      # publishing locales below Basic coverage; `ak` is at modern, so it
      # clears that gate on coverage alone rather than by being one of the
      # locales ICU happens to ship.
      assert time_format(~T[15:00:00], "B", :ak) == "ANW"
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

    test "a user-supplied override survives Localize.Date.to_string/2" do
      # Localize.Date.to_string/2 computes calendar-derived overrides
      # internally; it must merge them under (not clobber) an override
      # the caller passed in options.
      assert {:ok, "Jul ٦, ٢٠٢٤"} =
               Localize.Date.to_string(~D[2024-07-06],
                 format: :medium,
                 locale: :en,
                 number_system_overrides: %{"all" => :arab}
               )
    end

    test "a user-supplied override wins over a calendar-derived one per field" do
      # For a partial date the derived overrides map is empty for
      # :en/gregorian; the user's field-specific override must be
      # honoured on that path too.
      assert {:ok, "٢٠٢٤"} =
               Localize.Date.to_string(%{year: 2024},
                 format: "y",
                 locale: :en,
                 number_system_overrides: %{"y" => :arab}
               )
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

  describe "fields as the calendar answers them" do
    test "the year is the calendar's calendar_year/3" do
      date = %{year: 2024, month: 7, day: 6, calendar: CalendarYearCalendar}
      assert date_format(date, "y") == "12"
    end

    # The era is the calendar's `year_of_era/3`, never guessed from the sign
    # of the year, so an answer that is not a year of era and an era is an
    # error wherever the era is written or settles the year.
    test "a calendar answering year_of_era with something else is an error" do
      date = %{year: 2024, month: 7, day: 6, calendar: BadYearOfEraCalendar}

      for format <- ["G", "y G", "GGGG"] do
        assert {:error, %Localize.InvalidValueError{value: :not_a_tuple}} =
                 Localize.Date.to_string(date, format: format, locale: :en)
      end

      assert date_format(date, "y") == "2024"
    end

    # TR35 counts a year before the first era back from it, so year 0 is 1 BC
    # as `Calendar.ISO` renders it; a calendar without a year 0 writes 44 BC
    # as -44.
    test "a year below 1 from calendar_year/3 is shown as its year of era" do
      for year <- [0, -1, -44], pattern <- ["y G", "yy G"] do
        date = %{year: year, month: 3, day: 15, calendar: BeforeEraCalendar}
        assert date_format(date, pattern) == date_format(Date.new!(year, 3, 15), pattern)
      end

      assert date_format(%{year: 0, month: 3, day: 15, calendar: BeforeEraCalendar}, "y G") ==
               "1 BC"

      assert date_format(%{year: 0, calendar: BeforeEraCalendar}, "y G") == "1 BC"

      assert date_format(%{year: -1, month: 3, day: 15, calendar: NoYearZeroCalendar}, "y G") ==
               "1 BC"

      assert date_format(%{year: -44, month: 3, day: 15, calendar: NoYearZeroCalendar}, "y G") ==
               "44 BC"
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
      assert datetime_format(@utc_datetime, "z") == "UTC"
      assert datetime_format(@utc_datetime, "zzzz") == "Coordinated Universal Time"
    end

    test "Z widths render basic, GMT, and extended ISO forms" do
      assert datetime_format(@utc_datetime, "Z") == "+0000"
      assert datetime_format(@utc_datetime, "ZZZZ") == "GMT+00:00"
      assert datetime_format(@utc_datetime, "ZZZZZ") == "Z"
    end

    test "six-wide Z is an invalid field" do
      # ICU formats it as ZZZZ; TR35 lists Z only to five letters.
      assert datetime_format(@utc_datetime, "ZZZZZZ") == "�"
    end

    test "O widths render localized GMT formats" do
      assert datetime_format(@utc_datetime, "O") == "GMT+0"
      assert datetime_format(@utc_datetime, "OOOO") == "GMT+00:00"
    end

    test "O widths TR35 does not list are invalid fields" do
      assert datetime_format(@utc_datetime, "OO") == "�"
      assert datetime_format(@utc_datetime, "OOO") == "�"
    end

    test "v widths render the generic non-location name" do
      assert datetime_format(@utc_datetime, "v") == "UTC"
      assert datetime_format(@utc_datetime, "vvvv") == "Coordinated Universal Time"
    end

    test "V widths render zone id and location formats" do
      assert datetime_format(@utc_datetime, "V") == "utc"
      assert datetime_format(@utc_datetime, "VV") == "Etc/UTC"
      # CLDR names no exemplar city for Etc/UTC, which is no place, so TR35
      # falls back to Etc/Unknown's, as ICU4C 78.3 renders it.
      assert datetime_format(@utc_datetime, "VVV") == "Unknown Location"
      assert datetime_format(@utc_datetime, "VVVV") == "GMT+00:00"
    end

    test "x widths render ISO offsets without Z" do
      assert datetime_format(@utc_datetime, "x") == "+00"
      assert datetime_format(@utc_datetime, "xx") == "+0000"
      assert datetime_format(@utc_datetime, "xxx") == "+00:00"
      assert datetime_format(@utc_datetime, "xxxx") == "+0000"
      assert datetime_format(@utc_datetime, "xxxxx") == "+00:00"
    end

    test "six-wide x is an invalid field" do
      assert datetime_format(@utc_datetime, "xxxxxx") == "�"
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
