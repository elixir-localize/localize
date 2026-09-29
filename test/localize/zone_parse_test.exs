defmodule Localize.ZoneParseTest do
  @moduledoc """
  Time zones written in any form a locale formats one in parse back, and
  resolve to the instants ICU4C reads.

  The expected zones are ICU4C 78.3's readings of the same text through
  `TimeZoneFormat`, which accepts every style, and the expected instants
  its readings through `SimpleDateFormat`, except where a test says
  otherwise. This suite configures `:tz` as the time zone database.

  """

  use ExUnit.Case, async: true

  alias Localize.DateTime.Timezone

  describe "a zone written in any form" do
    test "specific and generic names, locations, cities and IDs" do
      for {locale, text, zone} <- [
            {:en, "EDT", {:zone, "America/New_York", :daylight}},
            {:en, "Eastern Daylight Time", {:zone, "America/New_York", :daylight}},
            {:en, "Eastern Time", {:zone, "America/New_York", :generic}},
            {:en, "ET", {:zone, "America/New_York", :generic}},
            {:en, "New York Time", {:zone, "America/New_York", :generic}},
            {:en, "New York", {:zone, "America/New_York", :generic}},
            {:en, "America/New_York", {:zone, "America/New_York", :generic}},
            {:en, "usnyc", {:zone, "America/New_York", :generic}},
            {:en, "Italy Time", {:zone, "Europe/Rome", :generic}},
            {:en, "China Time", {:zone, "Asia/Shanghai", :generic}},
            {:en, "Adelaide Time", {:zone, "Australia/Adelaide", :generic}},
            {:en, "India Standard Time", {:zone, "Asia/Calcutta", :standard}},
            {:en, "Mountain Standard Time", {:zone, "America/Denver", :standard}},
            {:fr, "heure d’été de l’Est nord-américain", {:zone, "America/New_York", :daylight}},
            {:fr, "heure : New York", {:zone, "America/New_York", :generic}},
            {:fr, "temps universel coordonné", {:zone, "Etc/UTC", :standard}},
            {:de, "Nordamerikanische Ostküsten-Sommerzeit",
             {:zone, "America/New_York", :daylight}},
            {:de, "Koordinierte Weltzeit", {:zone, "Etc/UTC", :standard}}
          ] do
        assert Timezone.parse_zone(text, locale: locale) == {:ok, zone}, "#{locale} #{text}"
      end
    end

    test "a name in any case" do
      assert Timezone.parse_zone("eastern daylight time", locale: :en) ==
               {:ok, {:zone, "America/New_York", :daylight}}

      assert Timezone.parse_zone("EASTERN TIME", locale: :en) ==
               {:ok, {:zone, "America/New_York", :generic}}
    end

    # TR35 lets a parse allow "different spacing, punctuation, or other
    # variation"; ICU4C 78.3 reads neither of these (a recorded divergence).
    test "a name with another apostrophe or spacing" do
      assert Timezone.parse_zone("heure d'été de l'Est nord-américain", locale: :fr) ==
               {:ok, {:zone, "America/New_York", :daylight}}

      assert Timezone.parse_zone("Eastern  Daylight   Time", locale: :en) ==
               {:ok, {:zone, "America/New_York", :daylight}}
    end

    # ICU4C 78.3 reads CLDR 48, where `fr` names UTC "UTC"; CLDR 49's
    # `fr.xml` names it "TU", as the formatter writes it.
    test "a zone's short name from CLDR 49" do
      assert Timezone.parse_zone("TU", locale: :fr) == {:ok, {:zone, "Etc/UTC", :standard}}
    end

    test "the localized GMT format in each locale's spelling" do
      lrm = <<0x200E::utf8>>

      for {locale, text} <- [
            {:en, "GMT-4"},
            {:en, "GMT-04:00"},
            {:fr, "UTC−4"},
            {:"ar-EG", "غرينتش-4"},
            {:bn, "GMT -4"},
            {:mr, "[GMT]-4"},
            {:fa, lrm <> "−4 گرینویچ"}
          ] do
        assert Timezone.parse_zone(text, locale: locale) == {:ok, {:offset, -14_400}},
               "#{locale} #{text}"
      end

      assert Timezone.parse_zone("UTC", locale: :en) == {:ok, {:offset, 0}}
    end

    test "a metazone name or a country stands for its zone in the country named" do
      for {locale, text, time_zone} <- [
            {:en, "Pacific Time (Canada)", "America/Vancouver"},
            {:en, "Mountain Time (Phoenix)", "America/Phoenix"},
            {:en, "Central European Time", "Europe/Paris"},
            {:de, "Mitteleuropäische Zeit", "Europe/Berlin"},
            {:"de-AT", "Mitteleuropäische Zeit", "Europe/Vienna"},
            {:"en-JM", "Eastern Time", "America/Jamaica"},
            {:"en-JM", "Eastern Time (United States)", "America/New_York"},
            {:raj, "GB", "Europe/London"}
          ] do
        assert Timezone.parse_zone(text, locale: locale) == {:ok, {:zone, time_zone, :generic}},
               "#{locale} #{text}"
      end
    end

    # "Greenwich Mean Time" names the GMT, British and Irish metazones.
    test "a name several metazones share" do
      for {locale, time_zone} <- [
            {:en, "Atlantic/Reykjavik"},
            {:"en-GB", "Europe/London"},
            {:"en-IE", "Europe/Dublin"}
          ] do
        assert Timezone.parse_zone("Greenwich Mean Time", locale: locale) ==
                 {:ok, {:zone, time_zone, :standard}}
      end
    end

    # `bg` names Accra "Акра", as it names the Acre metazone: a city comes
    # before a metazone.
    test "a city before a metazone of the same name" do
      assert Timezone.parse_zone("Акра", locale: :bg) == {:ok, {:zone, "Africa/Accra", :generic}}
    end

    # `he` writes a standard name as the generic one with "(חורף)",
    # "(winter)", which has the fallback format's shape but names no place.
    test "a name in parentheses that is no place" do
      assert Timezone.parse_zone("שעון אזור ההרים בארה״ב (חורף)", locale: :he) ==
               {:ok, {:zone, "America/Denver", :standard}}

      assert Timezone.parse_zone("שעון אזור ההרים בארה״ב", locale: :he) ==
               {:ok, {:zone, "America/Denver", :generic}}
    end

    test "text that is no zone" do
      for text <- ["XQZV", "Unknown City", "GMT+?", "AM", ""] do
        assert {:error, %Localize.UnknownTimezoneError{}} = Timezone.parse_zone(text, locale: :en)
      end
    end

    test "bad arguments" do
      assert {:error, %Localize.UnknownTimezoneError{}} = Timezone.parse_zone(nil, locale: :en)
      assert {:error, _exception} = Timezone.parse_zone("EDT", locale: :xx_invalid)
      assert {:error, _exception} = Timezone.parse_zone("EDT", :not_options)
    end
  end

  describe "a zone resolved at a date and time" do
    # A specific name keeps its own offset: EST in July is 10:00 at -05:00,
    # a fixed offset, since New York keeps daylight time then.
    test "a name of standard or daylight time" do
      assert {:ok, %DateTime{time_zone: "Etc/UTC", utc_offset: -18_000} = datetime} =
               Timezone.resolve("EST", ~N[2023-07-01 10:00:00], locale: :en)

      assert DateTime.compare(datetime, ~U[2023-07-01 15:00:00Z]) == :eq

      assert {:ok, datetime} = Timezone.resolve("EDT", ~N[2023-01-01 10:00:00], locale: :en)
      assert DateTime.compare(datetime, ~U[2023-01-01 14:00:00Z]) == :eq

      assert {:ok, %DateTime{time_zone: "America/New_York", zone_abbr: "EDT"} = datetime} =
               Timezone.resolve("EDT", ~N[2023-07-01 10:00:00], locale: :en)

      assert DateTime.compare(datetime, ~U[2023-07-01 14:00:00Z]) == :eq
    end

    # 01:30 on the day New York falls back is read in standard time, and
    # 02:30 on the day it springs forward at the offset before the change.
    test "a wall time the clocks pass twice, or skip" do
      assert {:ok, %DateTime{zone_abbr: "EST"} = datetime} =
               Timezone.resolve("ET", ~N[2023-11-05 01:30:00], locale: :en)

      assert DateTime.compare(datetime, ~U[2023-11-05 06:30:00Z]) == :eq

      assert {:ok, %DateTime{zone_abbr: "EDT", hour: 3, minute: 30} = datetime} =
               Timezone.resolve("ET", ~N[2023-03-12 02:30:00], locale: :en)

      assert DateTime.compare(datetime, ~U[2023-03-12 07:30:00Z]) == :eq
    end

    test "text that is no zone" do
      assert {:error, %Localize.UnknownTimezoneError{}} =
               Timezone.resolve("XQZV", ~N[2023-07-01 10:00:00], locale: :en)
    end
  end

  describe "a date-time with a zone" do
    # `en`'s full date-time writes a specific name (`zzzz`) and its long one
    # a short one (`z`); TR35 reads any form in either field, where ICU4C
    # reads these two as errors (a recorded divergence).
    test "a zone form other than the field's" do
      for text <- [
            "Saturday, July 1, 2023 at 10:00:00 AM Eastern Time",
            "July 1, 2023 at 10:00:00 AM New York Time"
          ] do
        assert {:ok, %DateTime{time_zone: "America/New_York"} = datetime} =
                 Localize.DateTime.parse(text, locale: :en)

        assert DateTime.compare(datetime, ~U[2023-07-01 14:00:00Z]) == :eq, text
      end
    end

    # ICU4C 78.3's full and long date-times of these instants.
    test "in each locale's words" do
      for {locale, text, instant} <- [
            {:fr, "samedi 1 juillet 2023 à 10:05:00 heure d’été de l’Est nord-américain",
             ~U[2023-07-01 14:05:00Z]},
            {:de, "Samstag, 1. Juli 2023 um 10:05:00 Nordamerikanische Ostküsten-Sommerzeit",
             ~U[2023-07-01 14:05:00Z]},
            {:en, "Sunday, January 15, 2023 at 10:05:00\u{202F}AM Central European Standard Time",
             ~U[2023-01-15 09:05:00Z]},
            {:ja, "2023年1月15日日曜日 10時05分00秒 日本標準時", ~U[2023-01-15 01:05:00Z]},
            {:"ar-EG", "١٥ يناير ٢٠٢٣ في ١٠:٠٥:٠٠ ص غرينتش+٥:٣٠", ~U[2023-01-15 04:35:00Z]},
            {:en,
             "Sunday, January 15, 2023 at 10:35:00\u{202F}AM Australian Central Daylight Time",
             ~U[2023-01-15 00:05:00Z]}
          ] do
        assert {:ok, %DateTime{} = datetime} = Localize.DateTime.parse(text, locale: locale)
        assert DateTime.compare(datetime, instant) == :eq, "#{locale} #{text}"
      end
    end
  end
end

defmodule Localize.ZoneParseWithoutDatabaseTest do
  @moduledoc """
  Without a time zone database a named zone cannot resolve, and the parse
  keeps the date and time rather than failing. The database is set for the
  whole node, so these tests run apart from the asynchronous ones.

  """

  use ExUnit.Case, async: false

  setup do
    database = Calendar.get_time_zone_database()
    Calendar.put_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase)
    on_exit(fn -> Calendar.put_time_zone_database(database) end)
  end

  test "a named zone keeps the date and time as a NaiveDateTime" do
    assert Localize.DateTime.parse("May 16, 2026 2:30 PM Asia/Tokyo", locale: :en) ==
             {:ok, ~N[2026-05-16 14:30:00]}
  end

  test "a fixed offset, or UTC, needs no database" do
    assert {:ok, %DateTime{utc_offset: -14_400, hour: 14}} =
             Localize.DateTime.parse("May 16, 2026 2:30 PM GMT-4", locale: :en)

    assert {:ok, %DateTime{utc_offset: 0, hour: 14}} =
             Localize.DateTime.parse("May 16, 2026 2:30 PM Coordinated Universal Time",
               locale: :en
             )
  end
end
