defmodule Localize.DateTime.TimezoneFormatTest do
  use ExUnit.Case, async: true

  alias Localize.DateTime.Timezone

  @new_york_standard %{time_zone: "America/New_York", utc_offset: -18_000, std_offset: 0}
  @new_york_daylight %{time_zone: "America/New_York", utc_offset: -18_000, std_offset: 3600}
  @paris %{time_zone: "Europe/Paris", utc_offset: 3600, std_offset: 0}

  describe "timezone data lookups" do
    test "timezones_for_territory/1 returns zones for a known territory" do
      assert {:ok, zones} = Timezone.timezones_for_territory(:AU)
      assert Enum.any?(zones, &(&1.short_zone == "ausyd"))
    end

    test "timezones_for_territory/1 returns an error for an unknown territory" do
      assert {:error, %Localize.UnknownTerritoryError{territory: :XX}} =
               Timezone.timezones_for_territory(:XX)
    end

    test "timezone_count_for_territory/1 counts zones" do
      assert {:ok, count} = Timezone.timezone_count_for_territory(:US)
      assert count > 0
    end

    test "timezone_count_for_territory/1 propagates unknown-territory errors" do
      assert {:error, %Localize.UnknownTerritoryError{territory: :ZZ}} =
               Timezone.timezone_count_for_territory(:ZZ)
    end

    test "get_short_zone/2 returns the default for unknown codes" do
      assert Timezone.get_short_zone("nope") == nil
      assert Timezone.get_short_zone("nope", :missing) == :missing
      assert %{territory: :AU} = Timezone.get_short_zone("ausyd")
    end

    test "fetch_short_zone/1 and validate_short_zone/1 error on unknown codes" do
      assert {:error, %Localize.UnknownTimezoneError{timezone: "nope"}} =
               Timezone.fetch_short_zone("nope")

      assert {:ok, "Australia/Sydney"} = Timezone.validate_short_zone("ausyd")

      assert {:error, %Localize.UnknownTimezoneError{timezone: "nope"}} =
               Timezone.validate_short_zone("nope")
    end

    test "territories_by_timezone/0 maps IANA names to territories" do
      territories = Timezone.territories_by_timezone()
      assert territories["Australia/Sydney"] == :AU
      assert territories["America/New_York"] == :US
    end
  end

  describe "non_location_format/3" do
    test "specific type selects standard or daylight from std_offset" do
      assert {:ok, "Eastern Standard Time"} =
               Timezone.non_location_format(@new_york_standard, :en)

      assert {:ok, "Eastern Daylight Time"} =
               Timezone.non_location_format(@new_york_daylight, :en)
    end

    test "explicit :standard and :daylight types override std_offset" do
      assert {:ok, "Central European Standard Time"} =
               Timezone.non_location_format(@paris, :en, type: :standard)

      assert {:ok, "Central European Summer Time"} =
               Timezone.non_location_format(@paris, :en, type: :daylight)
    end

    test ":generic type ignores daylight saving" do
      assert {:ok, "Eastern Time"} =
               Timezone.non_location_format(@new_york_standard, :en, type: :generic)

      assert {:ok, "Eastern Time"} =
               Timezone.non_location_format(@new_york_daylight, :en, type: :generic)
    end

    test "short format returns the abbreviation" do
      assert {:ok, "EST"} =
               Timezone.non_location_format(@new_york_standard, :en, format: :short)

      assert {:ok, "EDT"} =
               Timezone.non_location_format(@new_york_daylight, :en, format: :short)
    end

    test "unknown zone falls back to the GMT format" do
      unknown_zone = %{time_zone: "Mars/Olympus", utc_offset: 7200, std_offset: 0}

      assert {:ok, "GMT+02:00"} = Timezone.non_location_format(unknown_zone, :en)
    end

    test "localized names come from the requested locale" do
      assert {:ok, name} = Timezone.non_location_format(@new_york_standard, :fr)
      assert name =~ "Est"
    end

    test "zone-level names take precedence over the metazone" do
      utc = %{time_zone: "Etc/UTC", utc_offset: 0, std_offset: 0}

      assert {:ok, "Coordinated Universal Time"} = Timezone.non_location_format(utc, :en)
      assert {:ok, "UTC"} = Timezone.non_location_format(utc, :en, format: :short)

      assert {:ok, "Coordinated Universal Time"} =
               Timezone.non_location_format(utc, :en, type: :generic)

      assert {:ok, "UTC"} = Timezone.non_location_format(utc, :bg, format: :short)

      london = %{time_zone: "Europe/London", utc_offset: 0, std_offset: 3600}
      assert {:ok, "British Summer Time"} = Timezone.non_location_format(london, :en)

      gmt = %{time_zone: "Etc/GMT", utc_offset: 0, std_offset: 0}
      assert {:ok, "Greenwich Mean Time"} = Timezone.non_location_format(gmt, :en)
    end

    # ICU 77, through `Intl.DateTimeFormat` with `timeZone: "-05:00"`, gives
    # "GMT-5" and "GMT-05:00" for the short and long names, specific and
    # generic alike: an offset has no name. The struct is the one an ISO 8601
    # parse of a fixed offset gives, which keeps a UTC identifier.
    test "an offset carried under a UTC identifier is not named UTC" do
      offset = %{time_zone: "Etc/UTC", utc_offset: -18_000, std_offset: 0}

      assert {:ok, "GMT-05:00"} = Timezone.non_location_format(offset, :en)
      assert {:ok, "GMT-5"} = Timezone.non_location_format(offset, :en, format: :short)
      assert {:ok, "GMT-05:00"} = Timezone.non_location_format(offset, :en, type: :generic)

      assert {:ok, "GMT-5"} =
               Timezone.non_location_format(offset, :en, type: :generic, format: :short)

      {:ok, parsed} = Localize.DateTime.parse("2006-01-02T15:04:06-05:00")

      assert {:ok, "3:04 PM GMT-5"} =
               Localize.DateTime.to_string(parsed, format: :jmz, locale: :en)
    end

    test "a map naming no real date and time takes the zone's current metazone" do
      for datetime <- [
            %{year: 2006, month: 13},
            %{year: 2006, month: "x"},
            %{year: 2006, day: 1.5},
            %{year: 2006, utc_offset: nil}
          ] do
        assert Timezone.metazone_for("America/New_York", datetime) == :america_eastern
      end
    end
  end

  describe "gmt_format/3" do
    # CLDR removed `gmtZeroFormat` from the spec. TR35 now defines one style
    # for a known offset — spelled out, whatever its value — and its own
    # example list carries "GMT+00:00" and "UTC+0". CLDR's conformance data
    # agrees: `O` on `Etc/GMT` is "GMT+0".
    test "a zero offset is spelled out" do
      assert {:ok, "GMT+00:00"} = Timezone.gmt_format(%{utc_offset: 0, std_offset: 0}, :en)

      assert {:ok, "GMT+0"} =
               Timezone.gmt_format(%{utc_offset: 0, std_offset: 0}, :en, format: :short)
    end

    # The second of TR35's two styles: a zone whose offset is not known.
    # Rendering "GMT+00:00" here would be a definite claim about a zone we
    # know nothing about.
    test "an unknown offset renders the locale's gmtUnknownFormat" do
      assert {:ok, "GMT+?"} = Timezone.gmt_format(%{time_zone: "Etc/Unknown"}, :en)
      assert {:ok, "GMT+?"} = Timezone.gmt_format(%{}, :en)
      assert {:ok, "GMT+?"} = Timezone.gmt_format(%{utc_offset: nil}, :en)
    end

    # `gmtUnknownFormat` is translated, where the old hard-coded "GMT" was
    # not — it was returned for every locale alike.
    test "the unknown format is localized" do
      for locale <- [:en, :de, :fr, :ja, :ru] do
        {:ok, unknown} = Timezone.gmt_format(%{}, locale)
        assert is_binary(unknown)
        assert String.contains?(unknown, "?")
      end
    end

    test "long format includes minutes for fractional-hour offsets" do
      assert {:ok, "GMT-05:30"} =
               Timezone.gmt_format(%{utc_offset: -19_800, std_offset: 0}, :en)

      assert {:ok, "GMT+01:00"} = Timezone.gmt_format(%{utc_offset: 3600, std_offset: 0}, :en)
    end

    # TR35 writes the offset in the locale's digits ("they might be from
    # ०..९"), and ICU4C 78.3 writes four hours west as "GMT-४" in `ne`, whose
    # default numbering system is Devanagari, and "غرينتش-٤" in `ar-EG`,
    # whose is Arabic-Indic.
    test "the offset is written in the locale's digits" do
      four_west = %{utc_offset: -14_400, std_offset: 0}

      assert {:ok, "GMT-४"} = Timezone.gmt_format(four_west, :ne, format: :short)
      assert {:ok, "غرينتش-٤"} = Timezone.gmt_format(four_west, :"ar-EG", format: :short)
      assert {:ok, "GMT-4"} = Timezone.gmt_format(four_west, :en, format: :short)
    end

    test "the offset is written in the digits of the numbering system asked for" do
      four_west = %{utc_offset: -14_400, std_offset: 0}

      assert {:ok, "GMT-4"} =
               Timezone.gmt_format(four_west, :ne, format: :short, number_system: :latn)

      assert {:ok, "GMT-४"} =
               Timezone.gmt_format(four_west, :en, format: :short, number_system: :deva)

      # A numbering system without digits of its own writes 0 to 9.
      assert {:ok, "GMT-4"} =
               Timezone.gmt_format(four_west, :en, format: :short, number_system: :roman)
    end

    # The formatter writes the offset in the digits of its other fields:
    # the locale's, or those `-u-nu-` names.
    test "a formatted zone's offset takes the digits of the date" do
      datetime = %DateTime{
        year: 2026,
        month: 1,
        day: 15,
        hour: 9,
        minute: 30,
        second: 0,
        microsecond: {0, 0},
        time_zone: "America/New_York",
        zone_abbr: "EST",
        utc_offset: -18_000,
        std_offset: 0
      }

      assert {:ok, "GMT-५"} = Localize.DateTime.to_string(datetime, locale: "ne", format: "O")

      assert {:ok, "GMT-5"} =
               Localize.DateTime.to_string(datetime, locale: "ne-u-nu-latn", format: "O")

      assert {:ok, "GMT-०५:००"} =
               Localize.DateTime.to_string(datetime, locale: "ne", format: "OOOO")
    end

    test "short format drops zero minutes and leading hour zero" do
      assert {:ok, "GMT-8"} =
               Timezone.gmt_format(%{utc_offset: -28_800, std_offset: 0}, :en, format: :short)
    end

    test "short format keeps non-zero minutes after an hour with no leading zero" do
      # TR35: the short format "uses hour fields without leading zero, with
      # optional 2-digit minutes".
      assert {:ok, "GMT+5:30"} =
               Timezone.gmt_format(%{utc_offset: 19_800, std_offset: 0}, :en, format: :short)

      assert {:ok, "GMT-9:30"} =
               Timezone.gmt_format(%{utc_offset: -34_200, std_offset: 0}, :en, format: :short)
    end

    # TR35: "The long format always uses 2-digit hours field and minutes
    # field", and the short format "uses hour fields without leading zero".
    # `fi`'s `hourFormat` is "+H.mm;-H.mm", an hour of one digit, which the
    # long format was written with. The strings are ICU4C 78.3's for `OOOO`
    # and `O` in `fi`, for Kolkata, St. John's in summer, Paris in summer,
    # the Marquesas, Kiritimati and UTC.
    test "the long format has a two-digit hour whatever the locale's hourFormat writes" do
      for {offset, long, short} <- [
            {19_800, "UTC+05.30", "UTC+5.30"},
            {-9000, "UTC-02.30", "UTC-2.30"},
            {7200, "UTC+02.00", "UTC+2"},
            {-34_200, "UTC-09.30", "UTC-9.30"},
            {50_400, "UTC+14.00", "UTC+14"},
            {0, "UTC+00.00", "UTC+0"}
          ] do
        datetime = %{utc_offset: offset, std_offset: 0}

        assert Timezone.gmt_format(datetime, :fi) == {:ok, long}, "#{offset}"
        assert Timezone.gmt_format(datetime, :fi, format: :short) == {:ok, short}, "#{offset}"

        for text <- [long, short] do
          assert Timezone.parse_offset(text, locale: :fi) == {:ok, offset}, text
        end
      end

      {:ok, kolkata} = DateTime.new(~D[2026-07-15], ~T[17:30:00], "Asia/Kolkata")

      for {pattern, expected} <- [
            {"OOOO", "UTC+05.30"},
            {"ZZZZ", "UTC+05.30"},
            {"O", "UTC+5.30"}
          ] do
        assert Localize.DateTime.to_string(kolkata, locale: :fi, format: pattern) ==
                 {:ok, expected},
               pattern
      end
    end

    # TR35 gives the long format "2-digit hours field and minutes field, with
    # optional 2-digit seconds field" and the short one an hour without a
    # leading zero "with optional 2-digit minutes and seconds fields". An
    # offset a zone kept before standard time has seconds: Los Angeles
    # -7:52:58, Juneau +15:02:19, N'Djamena +1:00:12 and Manaus -4:00:04.
    # The strings are ICU4C 78.3's for `OOOO` and `O` on 15 January 1850. It
    # writes the seconds after the minutes, behind what the locale's
    # `hourFormat` has between its hours and minutes, which is nothing in
    # `am`, and before what follows the minutes, a mark in `he`.
    test "an offset's seconds are written after its minutes" do
      lrm = <<0x200E::utf8>>

      for {locale, offset, long, short} <- [
            {:en, -28_378, "GMT-07:52:58", "GMT-7:52:58"},
            {:en, 54_139, "GMT+15:02:19", "GMT+15:02:19"},
            {:en, 3612, "GMT+01:00:12", "GMT+1:00:12"},
            {:en, -14_404, "GMT-04:00:04", "GMT-4:00:04"},
            {:fi, -28_378, "UTC-07.52.58", "UTC-7.52.58"},
            {:fi, 3612, "UTC+01.00.12", "UTC+1.00.12"},
            {:da, -28_378, "GMT-07.52.58", "GMT-7.52.58"},
            {:fr, -28_378, "UTC−07:52:58", "UTC−7:52:58"},
            {:am, -28_378, "ጂ ኤም ቲ-075258", "ጂ ኤም ቲ-75258"},
            {:am, 3612, "ጂ ኤም ቲ+010012", "ጂ ኤም ቲ+10012"},
            {:am, 54_139, "ጂ ኤም ቲ+150219", "ጂ ኤም ቲ+150219"},
            {:"ar-EG", -28_378, "غرينتش-٠٧:٥٢:٥٨", "غرينتش-٧:٥٢:٥٨"},
            {:fa, -28_378, lrm <> "−۰۷:۵۲:۵۸ گرینویچ", lrm <> "−۷:۵۲:۵۸ گرینویچ"},
            {:he, -28_378, "GMT-07:52:58" <> lrm <> lrm, "GMT-7:52:58" <> lrm <> lrm},
            {:he, 3612, "GMT" <> lrm <> "+01:00:12" <> lrm, "GMT" <> lrm <> "+1:00:12" <> lrm}
          ] do
        datetime = %{utc_offset: offset, std_offset: 0}

        assert Timezone.gmt_format(datetime, locale) == {:ok, long}, "#{locale} #{offset}"

        assert Timezone.gmt_format(datetime, locale, format: :short) == {:ok, short},
               "#{locale} #{offset}"

        for text <- [long, short] do
          assert Timezone.parse_offset(text, locale: locale) == {:ok, offset},
                 "#{locale} #{text}"
        end
      end
    end

    test "std_offset is added to the base offset" do
      assert {:ok, "GMT-04:00"} = Timezone.gmt_format(@new_york_daylight, :en)
    end

    test "locale-specific GMT patterns are honoured" do
      # French uses "UTC" with a minus sign (U+2212) for negative offsets, and
      # the short format drops the hour's leading zero after either sign.
      assert {:ok, "UTC−5"} =
               Timezone.gmt_format(%{utc_offset: -18_000, std_offset: 0}, :fr, format: :short)
    end

    # `he` puts a left-to-right mark before its positive pattern and after its
    # negative one ("+HH:mm;-HH:mm" with the marks), and its GMT format adds
    # one after the offset. ICU drops the minutes of a whole hour's short form
    # by keeping the pattern up to its hour field, so that form carries one
    # mark after a negative offset and every other form two. The expected
    # strings are ICU 77's, through `Intl.DateTimeFormat` with `timeZoneName`
    # `shortOffset` and `longOffset`.
    test "he's marks are placed as ICU places them" do
      lrm = <<0x200E::utf8>>

      for {offset, format, expected} <- [
            {-18_000, :short, "GMT-5" <> lrm},
            {-18_000, :long, "GMT-05:00" <> lrm <> lrm},
            {-12_600, :short, "GMT-3:30" <> lrm <> lrm},
            {-12_600, :long, "GMT-03:30" <> lrm <> lrm},
            {19_800, :short, "GMT" <> lrm <> "+5:30" <> lrm},
            {19_800, :long, "GMT" <> lrm <> "+05:30" <> lrm},
            {32_400, :short, "GMT" <> lrm <> "+9" <> lrm},
            {32_400, :long, "GMT" <> lrm <> "+09:00" <> lrm}
          ] do
        datetime = %{utc_offset: offset, std_offset: 0}

        assert Timezone.gmt_format(datetime, :he, format: format) == {:ok, expected},
               "#{offset} #{format}"

        assert Timezone.parse_offset(expected, locale: :he) == {:ok, offset}
      end
    end
  end

  describe "iso_format/2" do
    test "zero offset renders Z by default" do
      assert {:ok, "Z"} = Timezone.iso_format(%{utc_offset: 0, std_offset: 0})
    end

    test "z_for_zero: false renders the numeric zero offset" do
      assert {:ok, "+0000"} =
               Timezone.iso_format(%{utc_offset: 0, std_offset: 0}, z_for_zero: false)
    end

    test "basic and extended types differ by separator" do
      assert {:ok, "+0500"} = Timezone.iso_format(%{utc_offset: 18_000, std_offset: 0})

      assert {:ok, "+05:30"} =
               Timezone.iso_format(%{utc_offset: 19_800, std_offset: 0}, type: :extended)
    end

    test "short format drops zero minutes" do
      assert {:ok, "+05"} =
               Timezone.iso_format(%{utc_offset: 18_000, std_offset: 0}, format: :short)

      assert {:ok, "+0530"} =
               Timezone.iso_format(%{utc_offset: 19_800, std_offset: 0}, format: :short)
    end

    test "full format appends seconds when the offset has them" do
      assert {:ok, "+05:45:20"} =
               Timezone.iso_format(%{utc_offset: 20_720, std_offset: 0},
                 format: :full,
                 type: :extended
               )

      assert {:ok, "+010020"} =
               Timezone.iso_format(%{utc_offset: 3620, std_offset: 0},
                 format: :full,
                 type: :basic,
                 z_for_zero: false
               )
    end

    test "full format omits seconds when the offset is whole minutes" do
      assert {:ok, "-04:00"} =
               Timezone.iso_format(@new_york_daylight, format: :full, type: :extended)
    end

    test "a map with only utc_offset is accepted" do
      assert {:ok, "+0100"} = Timezone.iso_format(%{utc_offset: 3600})
    end

    # TR35's symbol table: `Z` to `ZZZ` are "the ISO8601 basic format with
    # hours, minutes and optional seconds fields", "equivalent to the "xxxx"
    # specifier"; `XXXX`, `XXXXX`, `xxxx`, `xxxxx` and `ZZZZZ` have the
    # optional seconds too, and the shorter `X` and `x` fields have hours and
    # minutes alone, so they cut an offset's seconds off. The strings are
    # ICU4C 78.3's on 15 January 1850, for Los Angeles at -7:52:58 and
    # N'Djamena at +1:00:12.
    test "an offset's seconds in each pattern's zone field" do
      {:ok, utc} = DateTime.new(~D[1850-01-15], ~T[12:00:00], "Etc/UTC")
      {:ok, los_angeles} = DateTime.shift_zone(utc, "America/Los_Angeles")
      {:ok, ndjamena} = DateTime.shift_zone(utc, "Africa/Ndjamena")

      assert {los_angeles.utc_offset, ndjamena.utc_offset} == {-28_378, 3612}

      for {pattern, west, east} <- [
            {"Z", "-075258", "+010012"},
            {"ZZ", "-075258", "+010012"},
            {"ZZZ", "-075258", "+010012"},
            {"ZZZZ", "GMT-07:52:58", "GMT+01:00:12"},
            {"ZZZZZ", "-07:52:58", "+01:00:12"},
            {"O", "GMT-7:52:58", "GMT+1:00:12"},
            {"OOOO", "GMT-07:52:58", "GMT+01:00:12"},
            {"X", "-0752", "+01"},
            {"XX", "-0752", "+0100"},
            {"XXX", "-07:52", "+01:00"},
            {"XXXX", "-075258", "+010012"},
            {"XXXXX", "-07:52:58", "+01:00:12"},
            {"x", "-0752", "+01"},
            {"xx", "-0752", "+0100"},
            {"xxx", "-07:52", "+01:00"},
            {"xxxx", "-075258", "+010012"},
            {"xxxxx", "-07:52:58", "+01:00:12"}
          ] do
        assert Localize.DateTime.to_string(los_angeles, locale: :en, format: pattern) ==
                 {:ok, west},
               pattern

        assert Localize.DateTime.to_string(ndjamena, locale: :en, format: pattern) ==
                 {:ok, east},
               pattern
      end
    end
  end

  # CLDR gives most zones' first metazone period no beginning. TR35 has such
  # a period reach "as far backwards in time as there is data for", and tells
  # zones apart "at any time back to 1970"; no period of CLDR's data begins
  # before 1971. So the period begins with 1970, in UTC (user, 2026-10-06),
  # as ICU begins it, and before it a zone is written by its offset and its
  # location, where it was "Eastern Standard Time" in 1965 and "Pacific
  # Standard Time" at Los Angeles' local mean time of 1850. The strings are
  # ICU4C 78.3's for the instants, in `z`, `zzzz`, `v` and `vvvv`.
  describe "a zone before 1970, when it keeps no metazone" do
    defp zone_names(utc, zone, locale) do
      {:ok, datetime} = DateTime.shift_zone(utc, zone)

      for pattern <- ["z", "zzzz", "v", "vvvv"] do
        {:ok, text} = Localize.DateTime.to_string(datetime, locale: locale, format: pattern)
        text
      end
    end

    test "is written by its offset and its location" do
      for {locale, zone, utc, expected} <- [
            {:en, "America/New_York", ~U[1965-01-15 12:00:00Z],
             ["GMT-5", "GMT-05:00", "New York Time", "New York Time"]},
            {:en, "America/New_York", ~U[1965-07-15 12:00:00Z],
             ["GMT-4", "GMT-04:00", "New York Time", "New York Time"]},
            {:fr, "America/New_York", ~U[1965-01-15 12:00:00Z],
             ["UTC−5", "UTC−05:00", "heure : New York", "heure : New York"]},
            {:de, "Europe/Paris", ~U[1965-07-15 12:00:00Z],
             ["GMT+1", "GMT+01:00", "Frankreich (Ortszeit)", "Frankreich (Ortszeit)"]},
            {:en, "Asia/Kolkata", ~U[1965-01-15 12:00:00Z],
             ["GMT+5:30", "GMT+05:30", "India Time", "India Time"]},
            {:en, "America/Los_Angeles", ~U[1850-01-15 00:00:00Z],
             ["GMT-7:52:58", "GMT-07:52:58", "Los Angeles Time", "Los Angeles Time"]}
          ] do
        assert zone_names(utc, zone, locale) == expected, "#{locale} #{zone} #{utc}"
      end
    end

    # The period begins at 00:00 on 1 January 1970 in UTC: 19:00 the evening
    # before in New York, and 09:00 that morning in Tokyo.
    test "keeps its metazone from the first second of 1970 in UTC" do
      assert zone_names(~U[1969-12-31 23:59:59Z], "America/New_York", :en) ==
               ["GMT-5", "GMT-05:00", "New York Time", "New York Time"]

      assert zone_names(~U[1970-01-01 00:00:00Z], "America/New_York", :en) ==
               ["EST", "Eastern Standard Time", "ET", "Eastern Time"]

      assert ["GMT+9", "GMT+09:00", "Japan Time", "Japan Time"] =
               zone_names(~U[1969-12-31 23:59:59Z], "Asia/Tokyo", :en)

      assert ["GMT+9", "Japan Standard Time", "Japan Time", _generic] =
               zone_names(~U[1970-01-01 00:00:00Z], "Asia/Tokyo", :en)
    end

    # CLDR 49's `metaZones.xml` gives London the British metazone from
    # 1971-10-31 02:00, a beginning of its own, which stands.
    test "a period with a beginning of its own begins there" do
      assert ["GMT+1", "GMT+01:00" | _location] =
               zone_names(~U[1971-07-15 12:00:00Z], "Europe/London", :en)

      assert ["GMT+1", "British Summer Time" | _generic] =
               zone_names(~U[1972-07-15 12:00:00Z], "Europe/London", :en)
    end

    test "has none in metazone_for/2" do
      assert Timezone.metazone_for("America/New_York", ~N[1969-12-31 23:59:59]) == nil

      assert Timezone.metazone_for("America/New_York", ~N[1970-01-01 00:00:00]) ==
               :america_eastern

      assert Timezone.metazone_for("America/New_York", ~N[1850-06-01 00:00:00]) == nil
      assert Timezone.metazone_for("America/New_York") == :america_eastern

      {:ok, evening} = DateTime.shift_zone(~U[1970-01-01 00:00:00Z], "America/New_York")
      assert {evening.year, evening.hour} == {1969, 19}
      assert Timezone.metazone_for("America/New_York", evening) == :america_eastern
    end
  end

  # TR35 lets a metazone period name which offset is standard time and which
  # daylight, where the time zone database's flag is unreliable. CLDR 49's
  # `metaZones.xml` gives `Europe/Dublin` stdOffset "+00" and dstOffset
  # "+01" from 1971-10-31, and `America/Winnipeg` "-06" and "-05". In `en`,
  # Dublin's daylight name is "Irish Standard Time", and Central time's
  # "Central Daylight Time".
  describe "a metazone period's standard and daylight offsets" do
    @summer %{year: 2024, month: 7, day: 1, hour: 12, minute: 0, second: 0}
    @winter %{year: 2024, month: 1, day: 15, hour: 12, minute: 0, second: 0}

    test "decide the specific name whatever std_offset says" do
      # Irish Standard Time flagged as standard time, as the time zone
      # database's main data has it, and as daylight saving time.
      for offsets <- [%{utc_offset: 3600, std_offset: 0}, %{utc_offset: 0, std_offset: 3600}] do
        dublin = @summer |> Map.merge(offsets) |> Map.put(:time_zone, "Europe/Dublin")
        assert {:ok, "Irish Standard Time"} = Timezone.non_location_format(dublin, :en)
      end

      # Winter's GMT with a negative saving, and without one.
      for offsets <- [%{utc_offset: 3600, std_offset: -3600}, %{utc_offset: 0, std_offset: 0}] do
        dublin = @winter |> Map.merge(offsets) |> Map.put(:time_zone, "Europe/Dublin")
        assert {:ok, "Greenwich Mean Time"} = Timezone.non_location_format(dublin, :en)
      end

      winnipeg =
        Map.merge(@summer, %{time_zone: "America/Winnipeg", utc_offset: -18_000, std_offset: 0})

      # Winnipeg is Canada's zone for Central time and not the United States', so in
      # `en` its name is qualified, as CLDR's `TimezoneFormatter` writes it.
      assert {:ok, "Central Daylight Time (Canada)"} =
               Timezone.non_location_format(winnipeg, :en)
    end

    test "leave the flag to decide where the period names none" do
      chicago =
        Map.merge(@summer, %{time_zone: "America/Chicago", utc_offset: -21_600, std_offset: 3600})

      assert {:ok, "Central Daylight Time"} = Timezone.non_location_format(chicago, :en)

      chicago =
        Map.merge(@winter, %{time_zone: "America/Chicago", utc_offset: -21_600, std_offset: 0})

      assert {:ok, "Central Standard Time"} = Timezone.non_location_format(chicago, :en)
    end
  end
end
