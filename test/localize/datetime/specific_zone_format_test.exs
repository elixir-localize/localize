defmodule Localize.DateTime.SpecificZoneFormatTest do
  @moduledoc """
  The specific non-location zone format (`z`, `zzzz`), by the steps TR35
  gives for "the non-location formats (generic or specific)" and as CLDR's
  own `TimezoneFormatter` implements them: a zone's own name is written as
  it is, and a metazone's name is qualified by the zone's country or city
  unless the zone is the metazone's preferred zone for the locale's country.

  The expected strings are that class's
  (`org.unicode.cldr.util.TimezoneFormatter`, run at the pinned CLDR commit)
  for 12:00 UTC on 15 January and 15 July 2026. ICU never qualifies a
  specific name, which the ICU divergences guide records. This suite
  configures `:tz` as the time zone database.

  """

  use ExUnit.Case, async: true

  # The test of every test locale decodes each locale's data, which takes a
  # while beside the rest of the suite.
  @moduletag timeout: 300_000

  alias Localize.DateTime.Timezone

  @winter ~N[2026-01-15 12:00:00]
  @summer ~N[2026-07-15 12:00:00]

  defp at(naive, zone) do
    {:ok, utc} = DateTime.from_naive(naive, "Etc/UTC")
    {:ok, zoned} = DateTime.shift_zone(utc, zone)
    zoned
  end

  defp specific(zone, naive, locale, format \\ "zzzz") do
    case Localize.DateTime.to_string(at(naive, zone), locale: locale, format: format) do
      {:ok, text} -> text
      {:error, exception} -> {:error, exception.__struct__}
    end
  end

  describe "the metazone's preferred zone for the locale's country" do
    test "is unqualified" do
      for {zone, naive, locale, long, short} <- [
            {"America/Los_Angeles", @winter, :en, "Pacific Standard Time", "PST"},
            {"America/Los_Angeles", @summer, :en, "Pacific Daylight Time", "PDT"},
            {"America/Vancouver", @winter, :"en-CA", "Pacific Standard Time", "PST"},
            {"America/Toronto", @summer, :"en-CA", "Eastern Daylight Time", "EDT"},
            {"Europe/Berlin", @summer, :de, "Mitteleuropäische Sommerzeit", "MESZ"},
            {"America/Vancouver", @winter, :"fr-CA", "heure normale du Pacifique", "HNP"}
          ] do
        assert specific(zone, naive, locale) == long, "#{locale} #{zone}"
        assert specific(zone, naive, locale, "z") == short, "#{locale} #{zone}"
      end
    end

    # Paris is the Europe_Central metazone's zone for "001", which stands for
    # a country, the United States here, that has no zone of its own in it.
    test "is the metazone's golden zone where the country has none" do
      assert specific("Europe/Paris", @summer, :en) == "Central European Summer Time"
      assert specific("Asia/Tokyo", @winter, :en) == "Japan Standard Time"
      assert specific("Australia/Sydney", @winter, :en) == "Australian Eastern Daylight Time"
    end
  end

  describe "a country's preferred zone" do
    test "is qualified by its country" do
      for {zone, naive, locale, long, short} <- [
            {"America/Vancouver", @winter, :en, "Pacific Standard Time (Canada)", "PST (Canada)"},
            {"America/Vancouver", @summer, :en, "Pacific Daylight Time (Canada)", "PDT (Canada)"},
            {"America/Toronto", @summer, :en, "Eastern Daylight Time (Canada)", "EDT (Canada)"},
            {"America/Winnipeg", @summer, :en, "Central Daylight Time (Canada)", "CDT (Canada)"},
            {"America/Port-au-Prince", @winter, :en, "Eastern Standard Time (Haiti)",
             "EST (Haiti)"},
            {"Africa/Abidjan", @winter, :en, "Greenwich Mean Time (Côte d’Ivoire)",
             "GMT (Côte d’Ivoire)"},
            {"America/Los_Angeles", @winter, :"en-CA", "Pacific Standard Time (United States)",
             "PST (United States)"},
            {"Europe/Copenhagen", @winter, :"en-GB", "Central European Standard Time (Denmark)",
             "CET (Denmark)"},
            {"Europe/Berlin", @summer, :"en-GB", "Central European Summer Time (Germany)",
             "CEST (Germany)"},
            {"Europe/Paris", @summer, :de, "Mitteleuropäische Sommerzeit (Frankreich)",
             "MESZ (Frankreich)"}
          ] do
        assert specific(zone, naive, locale) == long, "#{locale} #{zone}"
        assert specific(zone, naive, locale, "z") == short, "#{locale} #{zone}"
      end
    end

    test "is qualified in both its standard and its daylight name" do
      assert specific("Europe/Berlin", @winter, :en) ==
               "Central European Standard Time (Germany)"

      assert specific("Europe/Berlin", @summer, :en) == "Central European Summer Time (Germany)"
    end
  end

  describe "any other zone" do
    test "is qualified by its city" do
      for {zone, naive, locale, long, short} <- [
            {"America/Phoenix", @summer, :en, "Mountain Standard Time (Phoenix)",
             "MST (Phoenix)"},
            {"America/Indiana/Knox", @winter, :en, "Central Standard Time (Knox, Indiana)",
             "CST (Knox, Indiana)"},
            {"America/Blanc-Sablon", @winter, :en, "Atlantic Standard Time (Blanc-Sablon)",
             "AST (Blanc-Sablon)"},
            {"Africa/Algiers", @summer, :de, "Mitteleuropäische Normalzeit (Algier)",
             "MEZ (Algier)"},
            {"America/Atikokan", @winter, :"fr-CA", "heure normale de l’Est (Atikokan)",
             "HNE (Atikokan)"}
          ] do
        assert specific(zone, naive, locale) == long, "#{locale} #{zone}"
        assert specific(zone, naive, locale, "z") == short, "#{locale} #{zone}"
      end
    end

    # `ar.xml` names Blanc-Sablon "بلانك-سابلون". The locale data keys a zone
    # by the parts of its name in snake case, `blanc_sablon`, and the city
    # was looked for under the lowercase name and never found.
    test "by the city the locale names, whatever the zone's name is keyed by" do
      assert specific("America/Blanc-Sablon", @winter, :ar) ==
               "التوقيت الرسمي الأطلسي (بلانك-سابلون)"

      assert Timezone.exemplar_city("America/Blanc-Sablon", :ar) == {:ok, "بلانك-سابلون"}
    end
  end

  describe "a zone's own name" do
    # `en.xml` names London's own summer time, and Dublin's.
    test "is written as it is" do
      assert specific("Europe/London", @summer, :en) == "British Summer Time"
      assert specific("Europe/London", @winter, :en) == "Greenwich Mean Time"
      assert specific("Europe/Dublin", @summer, :en) == "Irish Standard Time"
    end
  end

  describe "the locale's fallback format" do
    test "writes the name and the place in the locale's own shape" do
      for {locale, expected} <- [
            {:de, "Nordamerikanische Westküsten-Normalzeit (Kanada)"},
            {:fr, "heure normale du Pacifique nord-américain (Canada)"},
            {:"es-MX", "hora estándar del Pacífico (Canadá)"},
            {:pt, "Horário Padrão do Pacífico (Canadá)"},
            {:ru, "Тихоокеанское стандартное время (Канада)"},
            {:hi, "उत्तरी अमेरिकी प्रशांत मानक समय (कनाडा)"},
            {:ar, "توقيت المحيط الهادي الرسمي (كندا)"},
            {:ja, "米国太平洋標準時（カナダ）"},
            {:ko, "미 태평양 표준시(캐나다)"},
            {:zh, "北美太平洋标准时间（加拿大）"}
          ] do
        assert specific("America/Vancouver", @winter, locale) == expected, "#{locale}"
      end
    end
  end

  describe "a named type" do
    test "is qualified as the specific name is" do
      vancouver = at(@winter, "America/Vancouver")

      assert Timezone.non_location_format(vancouver, :en, type: :standard) ==
               {:ok, "Pacific Standard Time (Canada)"}

      assert Timezone.non_location_format(vancouver, :en, type: :daylight) ==
               {:ok, "Pacific Daylight Time (Canada)"}

      assert Timezone.non_location_format(vancouver, :en, type: :daylight, format: :short) ==
               {:ok, "PDT (Canada)"}
    end
  end

  describe "a zone with no name of the width" do
    # TR35's `z` falls back to the short localized GMT format, and `zzzz`
    # keeps the long one (the user's decision, as ICU writes it).
    test "is the localized GMT format, unqualified" do
      assert specific("Europe/Berlin", @winter, :en, "z") == "GMT+1"
      assert specific("Asia/Kolkata", @winter, :en, "z") == "GMT+5:30"
      assert specific("Asia/Amman", @winter, :en) == "GMT+03:00"
      assert specific("Asia/Amman", @winter, :en, "z") == "GMT+3"
    end
  end

  describe "a specific name read back" do
    defp read(zone, naive, locale, format) do
      zoned = at(naive, zone)
      written = Calendar.strftime(zoned, "%Y-%m-%d %H:%M:%S") <> " "
      text = written <> specific(zone, naive, locale, format)

      case Localize.DateTime.parse(text, locale: locale, format: "y-MM-dd HH:mm:ss " <> format) do
        {:ok, %DateTime{} = parsed} -> {parsed.time_zone, DateTime.compare(parsed, zoned)}
        other -> other
      end
    end

    test "is the zone its place names, at the same instant" do
      for {zone, naive, locale} <- [
            {"America/Vancouver", @winter, :en},
            {"America/Vancouver", @summer, :en},
            {"America/Phoenix", @summer, :en},
            {"America/Indiana/Knox", @winter, :en},
            {"America/Blanc-Sablon", @winter, :en},
            {"Europe/Berlin", @summer, :en},
            {"America/Los_Angeles", @winter, :"en-CA"},
            {"Europe/Paris", @summer, :de},
            {"America/Vancouver", @winter, :ja},
            {"America/Vancouver", @winter, :ar},
            {"America/Blanc-Sablon", @winter, :ar}
          ] do
        assert read(zone, naive, locale, "zzzz") == {zone, :eq}, "#{locale} #{zone}"
      end
    end

    # A short name is read as its long name is; a zone with no short name is
    # written as an offset, which names no zone and is the same instant.
    test "is the same for a short name, and the same instant for an offset" do
      for {zone, naive, locale} <- [
            {"America/Vancouver", @winter, :en},
            {"America/Phoenix", @summer, :en},
            {"America/Blanc-Sablon", @winter, :en},
            {"Europe/Paris", @summer, :de},
            {"Europe/Copenhagen", @winter, :"en-GB"}
          ] do
        assert read(zone, naive, locale, "z") == {zone, :eq}, "#{locale} #{zone}"
      end

      assert {_zone, :eq} = read("Europe/Berlin", @summer, :en, "z")
      assert {_zone, :eq} = read("America/Vancouver", @winter, :ja, "z")
    end

    # `pt-AO` names the country "Côte d’Ivoire (Costa do Marfim)", so its
    # Greenwich time ends with two parentheses, and `ko` names Central
    # European Summer Time "중부유럽 하계 표준시", which has the shape of its
    # standard region format, "{0} 표준시".
    test "where the place or the name holds the fallback format's own text" do
      assert specific("Africa/Abidjan", @winter, :"pt-AO") ==
               "Hora de Greenwich (Côte d’Ivoire (Costa do Marfim))"

      assert read("Africa/Abidjan", @winter, :"pt-AO", "zzzz") == {"Africa/Abidjan", :eq}

      assert specific("Europe/Berlin", @summer, :ko) == "중부유럽 하계 표준시(독일)"
      assert read("Europe/Berlin", @summer, :ko, "zzzz") == {"Europe/Berlin", :eq}
    end

    @zones [
      "America/Vancouver",
      "America/Phoenix",
      "Europe/Berlin",
      "Europe/London",
      "Asia/Kolkata",
      "Africa/Abidjan"
    ]

    # Every test locale: the locales `test/test_helper.exs` lists, the same
    # on every machine (`Localize.Test.InstalledLocales`).
    test "is the same instant in every test locale" do
      failures =
        for locale <- Localize.Test.InstalledLocales.all(),
            zone <- @zones,
            naive <- [@winter, @summer],
            format <- ["zzzz", "z"],
            {_zone, result} = read(zone, naive, locale, format),
            result != :eq do
          {locale, zone, naive, format, specific(zone, naive, locale, format), result}
        end

      assert failures == []
    end
  end
end
