defmodule Localize.DateTime.ZoneSymbolTest do
  use ExUnit.Case, async: true

  # Exercises the timezone format symbols (z, Z, O, v, V, X, x)
  # in Localize.DateTime.Formatter using fixed-offset DateTime
  # structs so no timezone database is required.

  @utc ~U[2024-07-06 14:30:45Z]

  @new_york_standard %DateTime{
    year: 2024,
    month: 1,
    day: 15,
    hour: 9,
    minute: 30,
    second: 0,
    microsecond: {0, 0},
    time_zone: "America/New_York",
    zone_abbr: "EST",
    utc_offset: -18_000,
    std_offset: 0,
    calendar: Calendar.ISO
  }

  @new_york_daylight %DateTime{
    year: 2024,
    month: 7,
    day: 15,
    hour: 9,
    minute: 30,
    second: 0,
    microsecond: {0, 0},
    time_zone: "America/New_York",
    zone_abbr: "EDT",
    utc_offset: -18_000,
    std_offset: 3600,
    calendar: Calendar.ISO
  }

  @kolkata %DateTime{
    year: 2024,
    month: 7,
    day: 6,
    hour: 14,
    minute: 30,
    second: 0,
    microsecond: {0, 0},
    time_zone: "Asia/Kolkata",
    zone_abbr: "IST",
    utc_offset: 19_800,
    std_offset: 0,
    calendar: Calendar.ISO
  }

  defp zone_format(datetime, format, locale \\ :en) do
    {:ok, result} = Localize.DateTime.to_string(datetime, format: format, locale: locale)
    result
  end

  describe "z — specific non-location" do
    test "short and long names for a standard-time zone" do
      assert zone_format(@new_york_standard, "z") == "EST"
      assert zone_format(@new_york_standard, "zz") == "EST"
      assert zone_format(@new_york_standard, "zzz") == "EST"
      assert zone_format(@new_york_standard, "zzzz") == "Eastern Standard Time"
    end

    test "daylight-saving variant is selected from std_offset" do
      assert zone_format(@new_york_daylight, "z") == "EDT"
      assert zone_format(@new_york_daylight, "zzzz") == "Eastern Daylight Time"
    end

    test "UTC renders as GMT names" do
      assert zone_format(@utc, "z") == "GMT"
      assert zone_format(@utc, "zzzz") == "Greenwich Mean Time"
    end

    test "zone with a long metazone name but no short one falls back to GMT format" do
      assert zone_format(@kolkata, "z") == "GMT+05:30"
      assert zone_format(@kolkata, "zzzz") == "India Standard Time"
    end
  end

  describe "Z — ISO basic / localized GMT" do
    test "Z (1-3) renders the ISO basic offset" do
      assert zone_format(@utc, "Z") == "+0000"
      assert zone_format(@new_york_standard, "Z") == "-0500"
      assert zone_format(@new_york_daylight, "ZZ") == "-0400"
      assert zone_format(@kolkata, "ZZZ") == "+0530"
    end

    test "ZZZZ renders the localized long GMT format" do
      assert zone_format(@utc, "ZZZZ") == "GMT"
      assert zone_format(@new_york_standard, "ZZZZ") == "GMT-05:00"
      assert zone_format(@kolkata, "ZZZZ") == "GMT+05:30"
    end

    test "ZZZZZ renders extended ISO with Z for a zero offset" do
      assert zone_format(@utc, "ZZZZZ") == "Z"
      assert zone_format(@new_york_standard, "ZZZZZ") == "-05:00"
      assert zone_format(@kolkata, "ZZZZZ") == "+05:30"
    end
  end

  describe "O — localized GMT" do
    test "O renders the short GMT offset" do
      assert zone_format(@utc, "O") == "GMT+0"
      assert zone_format(@new_york_standard, "O") == "GMT-5"
      assert zone_format(@new_york_daylight, "O") == "GMT-4"
      assert zone_format(@kolkata, "O") == "GMT+05:30"
    end

    test "OOOO renders the long GMT offset" do
      assert zone_format(@utc, "OOOO") == "GMT+00:00"
      assert zone_format(@new_york_standard, "OOOO") == "GMT-05:00"
      assert zone_format(@kolkata, "OOOO") == "GMT+05:30"
    end
  end

  describe "v — generic non-location" do
    test "short and long generic names" do
      assert zone_format(@new_york_standard, "v") == "ET"
      assert zone_format(@new_york_standard, "vvvv") == "Eastern Time"
    end

    test "generic name is the same regardless of daylight saving" do
      assert zone_format(@new_york_daylight, "v") == "ET"
      assert zone_format(@new_york_daylight, "vvvv") == "Eastern Time"
    end

    test "zone without a generic name falls back to GMT format" do
      assert zone_format(@kolkata, "v") == "GMT+05:30"
      assert zone_format(@kolkata, "vvvv") == "GMT+05:30"
    end
  end

  describe "V — zone ID" do
    test "V and VV render the IANA zone name" do
      assert zone_format(@new_york_standard, "V") == "America/New_York"
      assert zone_format(@new_york_standard, "VV") == "America/New_York"
      assert zone_format(@utc, "VV") == "Etc/UTC"
    end

    test "VVV and VVVV fall back to short and long GMT format" do
      assert zone_format(@new_york_standard, "VVV") == "GMT-5"
      assert zone_format(@new_york_standard, "VVVV") == "GMT-05:00"
    end
  end

  describe "X — ISO 8601 with Z for zero" do
    test "all widths render Z at UTC" do
      for format <- ["X", "XX", "XXX", "XXXX", "XXXXX"] do
        assert zone_format(@utc, format) == "Z"
      end
    end

    test "widths for a whole-hour negative offset" do
      assert zone_format(@new_york_standard, "X") == "-05"
      assert zone_format(@new_york_standard, "XX") == "-0500"
      assert zone_format(@new_york_standard, "XXX") == "-05:00"
      assert zone_format(@new_york_standard, "XXXX") == "-0500"
      assert zone_format(@new_york_standard, "XXXXX") == "-05:00"
    end

    test "widths for a half-hour positive offset keep the minutes" do
      assert zone_format(@kolkata, "X") == "+0530"
      assert zone_format(@kolkata, "XX") == "+0530"
      assert zone_format(@kolkata, "XXX") == "+05:30"
    end
  end

  describe "x — ISO 8601 without Z for zero" do
    test "zero offset renders numerically" do
      assert zone_format(@utc, "x") == "+00"
      assert zone_format(@utc, "xx") == "+0000"
      assert zone_format(@utc, "xxx") == "+00:00"
      assert zone_format(@utc, "xxxx") == "+0000"
      assert zone_format(@utc, "xxxxx") == "+00:00"
    end

    test "non-zero offsets match the X widths" do
      assert zone_format(@new_york_daylight, "x") == "-04"
      assert zone_format(@new_york_daylight, "xx") == "-0400"
      assert zone_format(@new_york_daylight, "xxx") == "-04:00"
    end
  end

  describe "zone symbols in composed patterns" do
    test "offset zone in a full datetime pattern" do
      assert zone_format(@new_york_standard, "y-MM-dd HH:mm:ss zzzz") ==
               "2024-01-15 09:30:00 Eastern Standard Time"
    end

    test "localized long GMT in another locale" do
      result = zone_format(@new_york_standard, "zzzz", :fr)
      assert result =~ "Est"
    end
  end
end
