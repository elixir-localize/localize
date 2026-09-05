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

    test "UTC renders its zone-level names" do
      assert zone_format(@utc, "z") == "UTC"
      assert zone_format(@utc, "zzzz") == "Coordinated Universal Time"
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

    # TR35 groups `ZZZZ` with `O+` as the localized GMT formats, so a zero
    # offset is spelled out rather than using `gmtZeroFormat`, matching `OOOO`.
    test "ZZZZ renders the localized long GMT format" do
      assert zone_format(@utc, "ZZZZ") == "GMT+00:00"
      assert zone_format(@utc, "ZZZZ") == zone_format(@utc, "OOOO")
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

    # TR35 **Type Fallback**: a metazone with no daylight type does not need
    # daylight support, so the generic request resolves to the standard name.
    # India keeps no daylight time, so `vvvv` is "India Standard Time".
    test "a zone that keeps no daylight time uses its standard name" do
      assert zone_format(@kolkata, "vvvv") == "India Standard Time"
    end

    # The `gmt` metazone carries only a standard name, which is how CLDR's
    # conformance data renders `Etc/GMT` for the generic zone style.
    test "Etc/GMT resolves to the Greenwich Mean Time metazone name" do
      gmt = %{@utc | time_zone: "Etc/GMT"}

      assert zone_format(gmt, "vvvv") == "Greenwich Mean Time"
    end

    # CLDR ships no short India name, so `v` takes TR35's intermediate step
    # and renders the generic location format rather than a GMT offset.
    test "a zone with no short name falls back to the generic location format" do
      assert zone_format(@kolkata, "v") == "India Time"
    end

    # Only the generic symbols take that step. A specific symbol with no name
    # goes straight to the localized GMT format.
    test "a specific symbol with no name goes straight to the GMT format" do
      assert zone_format(@kolkata, "z") == "GMT+05:30"
    end
  end

  describe "V — zone ID and location" do
    # `V` has meant the BCP 47 short timezone identifier since CLDR 23; only
    # `VV` is the IANA name. TR35's own example is `uslax` /
    # `America/Los_Angeles`.
    test "V renders the BCP 47 short zone identifier and VV the IANA name" do
      assert zone_format(@new_york_standard, "V") == "usnyc"
      assert zone_format(@new_york_standard, "VV") == "America/New_York"
      assert zone_format(@utc, "V") == "utc"
      assert zone_format(@utc, "VV") == "Etc/UTC"
    end

    # Every alias of a zone shares its short identifier and its exemplar city.
    test "V and VVV resolve an alias to its canonical zone" do
      eastern = %{@new_york_standard | time_zone: "US/Eastern"}

      assert zone_format(eastern, "V") == "usnyc"
      assert zone_format(eastern, "VVV") == "New York"
    end

    # `VVV` is the bare exemplar city; `VVVV` is the generic location format,
    # the city substituted into the locale's `regionFormat`.
    test "VVV renders the exemplar city and VVVV the generic location format" do
      assert zone_format(@new_york_standard, "VVV") == "New York"
      assert zone_format(@new_york_standard, "VVVV") == "New York Time"
    end

    # TR35 restricts the localized GMT fallback to GMT-style zone IDs, which
    # have no place to name. CLDR's conformance data renders `Etc/GMT` as
    # "GMT+00:00" and `Australia/Adelaide` as "Adelaide Time" for `VVVV`.
    test "VVVV falls back to the long localized GMT format for Etc zones only" do
      assert zone_format(@utc, "VVVV") == "GMT+00:00"

      adelaide = %{@new_york_standard | time_zone: "Australia/Adelaide", utc_offset: 34_200}
      assert zone_format(adelaide, "VVVV") == "Adelaide Time"
    end

    # TR35 rule 5.2.1: the location format names the country when the zone is
    # the only one in its territory. Italy, Portugal and India each keep one.
    test "VVVV names the country for a territory with a single zone" do
      rome = %{@new_york_standard | time_zone: "Europe/Rome", utc_offset: 3_600}

      assert zone_format(rome, "VVVV") == "Italy Time"
      assert zone_format(@kolkata, "VVVV") == "India Time"
    end

    # The same rule for a zone CLDR lists in `primaryZones`, which is how a
    # multi-zone country still gets named: Germany keeps two zones.
    test "VVVV names the country for a primary zone" do
      berlin = %{@new_york_standard | time_zone: "Europe/Berlin", utc_offset: 3_600}
      shanghai = %{@new_york_standard | time_zone: "Asia/Shanghai", utc_offset: 28_800}

      assert zone_format(berlin, "VVVV") == "Germany Time"
      assert zone_format(shanghai, "VVVV") == "China Time"
    end

    # `VVV` is the exemplar city throughout — only the location *format*
    # substitutes a country.
    test "VVV stays the exemplar city even where VVVV names a country" do
      rome = %{@new_york_standard | time_zone: "Europe/Rome", utc_offset: 3_600}

      assert zone_format(rome, "VVV") == "Rome"
      assert zone_format(rome, "VVVV") == "Italy Time"
    end

    # TR35 makes `unk` the fallback short identifier for any zone CLDR does
    # not know. The city still derives from a well-formed `Region/City`
    # identifier, which is CLDR's own convention for the zones it ships no
    # entry for.
    test "an unknown zone falls back to the Unknown Zone identifier" do
      unknown = %{@new_york_standard | time_zone: "Neverwhere/Nowhere"}

      assert zone_format(unknown, "V") == "unk"
      assert zone_format(unknown, "VVV") == "Nowhere"
      assert zone_format(unknown, "VVVV") == "Nowhere Time"
    end

    # With nothing to derive a city from, `VVV` uses the exemplar city of the
    # special zone `Etc/Unknown` and `VVVV` the localized GMT format.
    test "an unparseable zone falls back to the Unknown Location city" do
      unknown = %{@new_york_standard | time_zone: "Bogus", utc_offset: 0}

      assert zone_format(unknown, "V") == "unk"
      assert zone_format(unknown, "VVV") == "Unknown Location"
      assert zone_format(unknown, "VVVV") == "GMT+00:00"
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
