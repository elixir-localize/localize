defmodule Localize.DateTime.LocationZoneFormatTest do
  @moduledoc """
  The location zone format (`VVVV`), by the steps TR35 gives for "the
  location formats": a zone that is the only one in its country, or CLDR's
  primary zone for it, is written by the country, by its short name where
  the locale has one, else its name, else its code; any other zone is
  written by its city.

  The expected strings are ICU4C 78.3's, as is TR35's own example of a
  country the locale does not name ("Hora de CU" for Havana's zone), and
  CLDR's own `TimezoneFormatter`'s where a metazone's name is qualified.
  This suite configures `:tz` as the time zone database.

  """

  use ExUnit.Case, async: true

  # The test of every test locale decodes each locale's data, which takes a
  # while beside the rest of the suite.
  @moduletag timeout: 300_000

  alias Localize.DateTime.Timezone

  defp at(zone) do
    {:ok, utc} = DateTime.from_naive(~N[2026-01-15 12:00:00], "Etc/UTC")
    {:ok, zoned} = DateTime.shift_zone(utc, zone)
    zoned
  end

  defp written(zone, locale, format \\ "VVVV") do
    {:ok, text} = Localize.DateTime.to_string(at(zone), locale: locale, format: format)
    text
  end

  describe "a zone that is the only one in its country, or its primary zone" do
    test "is written by the country's name" do
      assert written("America/Havana", :en) == "Cuba Time"
      assert written("Africa/Monrovia", :en) == "Liberia Time"
      assert written("Asia/Shanghai", :en) == "China Time"
      assert written("America/Havana", :ebu) == "Kuba"
      assert written("Asia/Shanghai", :su) == "Tiongkok"
    end

    # `en.xml` gives the United Kingdom, Hong Kong, Myanmar and Bosnia and
    # Herzegovina the short names "UK", "Hong Kong", "Myanmar" and "Bosnia",
    # which TR35 has the format take: "continue with short country name, if
    # it exists, otherwise the country name". ICU4C writes the full name, a
    # recorded divergence, and that is read back as well.
    test "is written by the country's short name where the locale has one" do
      assert written("Europe/London", :en) == "UK Time"
      assert written("Asia/Hong_Kong", :en) == "Hong Kong Time"
      assert written("Asia/Yangon", :en) == "Myanmar Time"
      assert written("Europe/Sarajevo", :en) == "Bosnia Time"

      for text <- ["UK Time", "United Kingdom Time"] do
        assert Timezone.parse_zone(text, locale: :en) ==
                 {:ok, {:zone, "Europe/London", :generic}}
      end
    end

    # `su.xml`, `oc.xml`, `sd_Deva.xml` and `nnh.xml` name no Cuba, `raj.xml`
    # no China and `ebu.xml` no Saint Martin; `oc`'s region format is "ora de
    # {0}", TR35's own example in another language.
    test "is written by the country's code where the locale does not name it" do
      assert written("America/Havana", :su) == "CU"
      assert written("America/Havana", :oc) == "ora de CU"
      assert written("America/Havana", :"sd-Deva") == "CU वक़्तु"
      assert written("America/Havana", :nnh) == "CU"
      assert written("Asia/Shanghai", :raj) == "CN"
      assert written("America/Marigot", :ebu) == "MF"
    end
  end

  describe "any other zone" do
    test "is written by its city" do
      assert written("America/Argentina/Buenos_Aires", :en) == "Buenos Aires Time"
      assert written("America/Argentina/Buenos_Aires", :su) == "Buenos Aires"
      assert written("America/Argentina/Buenos_Aires", :oc) == "ora de Buenos Aires"
    end
  end

  describe "the generic formats, where the locale has no name for the zone" do
    test "are the location format" do
      for format <- ["v", "vvvv"] do
        assert written("America/Havana", :su, format) == "CU"
        assert written("Africa/Johannesburg", :oc, format) == "ora de ZA"
      end
    end
  end

  describe "a location read back" do
    test "is the same instant, in every test locale" do
      zones =
        ~w(America/Havana Africa/Johannesburg Africa/Monrovia Asia/Shanghai Europe/Rome
           Europe/Berlin America/Argentina/Buenos_Aires America/Marigot America/Lower_Princes
           America/Tortola America/St_Thomas America/Miquelon Asia/Yerevan Asia/Hong_Kong)

      for locale <- Localize.Test.InstalledLocales.all(), zone <- zones do
        datetime = at(zone)
        format = "y-MM-dd HH:mm:ss VVVV"
        {:ok, text} = Localize.DateTime.to_string(datetime, locale: locale, format: format)

        assert {:ok, %DateTime{} = parsed} =
                 Localize.DateTime.parse(text, locale: locale, format: format),
               "#{locale} #{zone}: #{text}"

        assert DateTime.compare(parsed, datetime) == :eq, "#{locale} #{zone}: #{text}"
      end
    end

    test "is its country's zone where it is the country's code" do
      havana = {:ok, {:zone, "America/Havana", :generic}}

      assert Timezone.parse_zone("CU", locale: :su) == havana
      assert Timezone.parse_zone("ora de CU", locale: :oc) == havana
      assert Timezone.parse_zone("CU वक़्तु", locale: :"sd-Deva") == havana
    end

    # ICU4C writes Saint Pierre and Miquelon's zone "PM" in `nnh` and
    # "Santapieri na Mikeloni" in `ebu`, both with the place alone as their
    # region format; `en` names Cuba.
    test "is a code only where the locale writes the country by its code" do
      assert Timezone.parse_zone("PM", locale: :nnh) ==
               {:ok, {:zone, "America/Miquelon", :generic}}

      assert {:error, %Localize.UnknownTimezoneError{}} = Timezone.parse_zone("PM", locale: :ebu)

      assert {:error, %Localize.UnknownTimezoneError{}} =
               Timezone.parse_zone("CU Time", locale: :en)
    end

    # ICU4C writes "10:00 PM" for 10:00 in Saint Pierre and Miquelon in `nnh`
    # at "HH:mm VVVV". A pattern without a zone is read first, so a time a
    # day period can follow is that time of day.
    test "leaves a day period its reading" do
      assert Localize.Time.parse("10:05 PM", locale: :nnh) == {:ok, ~T[22:05:00]}

      assert {:ok, %DateTime{time_zone: "America/Miquelon", hour: 22, minute: 5}} =
               Localize.DateTime.parse("2026-01-15 22:05 PM",
                 locale: :nnh,
                 format: "y-MM-dd HH:mm VVVV"
               )

      assert {:error, %Localize.TimeParseError{}} = Localize.Time.parse("22:05 PM", locale: :ebu)
    end
  end

  describe "a country's name in the shape of the fallback format" do
    # `fr_CA.xml` names Saint Martin "Saint-Martin (France)" and Sint Maarten
    # "Saint-Martin (Pays-Bas)", and `ru.xml` the British Virgin Islands
    # "Виргинские о-ва (Великобритания)".
    test "is read whole, never as a name and the country in its parentheses" do
      assert written("America/Marigot", :"fr-CA") == "heure : Saint-Martin (France)"

      assert Timezone.parse_zone("heure : Saint-Martin (France)", locale: :"fr-CA") ==
               {:ok, {:zone, "America/Marigot", :generic}}

      assert Timezone.parse_zone("heure : Saint-Martin (Pays-Bas)", locale: :"fr-CA") ==
               {:ok, {:zone, "America/Lower_Princes", :generic}}

      assert written("America/Tortola", :ru) == "Виргинские о-ва (Великобритания)"

      assert Timezone.parse_zone("Виргинские о-ва (Великобритания)", locale: :ru) ==
               {:ok, {:zone, "America/Tortola", :generic}}
    end

    test "qualifies a metazone's name as any country does" do
      assert written("America/Tortola", :ru, "vvvv") ==
               "Атлантическое время (Виргинские о-ва (Великобритания))"

      assert Timezone.parse_zone(
               "Атлантическое время (Виргинские о-ва (Великобритания))",
               locale: :ru
             ) == {:ok, {:zone, "America/Tortola", :generic}}

      assert Timezone.parse_zone("heure de l’Atlantique (Saint-Martin (France))",
               locale: :"fr-CA"
             ) == {:ok, {:zone, "America/Marigot", :generic}}

      assert Timezone.parse_zone("Pacific Time (Canada)", locale: :en) ==
               {:ok, {:zone, "America/Vancouver", :generic}}
    end
  end
end
