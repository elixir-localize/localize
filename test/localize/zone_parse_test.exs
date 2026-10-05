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

    # TR35 writes the localized GMT format in "the locale's default decimal
    # digits", and its parsing reads the format with "non-Latin numbers".
    # ICU4C 78.3 writes Kolkata's offset so with `O` and `OOOO` in each of
    # these locales, and reads each back as +05:30.
    test "the localized GMT format in a locale's own digits" do
      lrm = <<0x200E::utf8>>
      {:ok, utc} = DateTime.from_naive(~N[2026-01-15 12:00:00], "Etc/UTC")
      {:ok, kolkata} = DateTime.shift_zone(utc, "Asia/Kolkata")

      for {locale, short, long} <- [
            {:"ar-EG", "غرينتش+٥:٣٠", "غرينتش+٠٥:٣٠"},
            {:bn, "GMT +৫:৩০", "GMT +০৫:৩০"},
            {:fa, lrm <> "+۵:۳۰ گرینویچ", lrm <> "+۰۵:۳۰ گرینویچ"},
            {:ne, "GMT+५:३०", "GMT+०५:३०"},
            {:my, "GMT+၅:၃၀", "GMT+၀၅:၃၀"},
            {:mr, "[GMT]+५:३०", "[GMT]+०५:३०"},
            {:dz, "ཇི་ཨེམ་ཏི་+༥:༣༠", "ཇི་ཨེམ་ཏི་+༠༥:༣༠"},
            {:ckb, "گرینیچ +٥:٣٠", "گرینیچ +٠٥:٣٠"}
          ] do
        assert Localize.DateTime.to_string(kolkata, locale: locale, format: "O") == {:ok, short}
        assert Localize.DateTime.to_string(kolkata, locale: locale, format: "OOOO") == {:ok, long}

        for text <- [short, long] do
          assert Timezone.parse_zone(text, locale: locale) == {:ok, {:offset, 19_800}},
                 "#{locale} #{text}"

          assert Timezone.parse_offset(text, locale: locale) == {:ok, 19_800}, "#{locale} #{text}"

          assert {:ok, resolved} = Timezone.resolve(text, ~N[2026-01-15 17:30:00], locale: locale)
          assert DateTime.compare(resolved, utc) == :eq, "#{locale} #{text}"
        end
      end
    end

    # TR35's "non-Latin numbers" are not the locale's alone. CLDR's
    # `numberingSystems.xml` gives each numeric system's digits in the order
    # of their values. ICU4C 78.3 writes Kolkata's offset with the strings
    # below in `en-u-nu-hanidec`, `-fullwide`, `-mathbold`, `-adlm`, `-nkoo`,
    # `-thai`, `-arab` and `-deva`, and reads each as +05:30 in plain `en`
    # but the two of `hanidec`, whose digits are no decimal digits to
    # Unicode: those it reads where the locale asks for them.
    test "the localized GMT format in the digits of any numbering system, in any locale" do
      systems = Localize.Number.System.numeric_systems()
      assert map_size(systems) >= 78

      for {system, %{digits: digits}} <- systems do
        [zero, _one, _two, three, _four, five | _rest] = String.graphemes(digits)
        short = "GMT+" <> five <> ":" <> three <> zero
        long = "UTC-" <> zero <> five <> ":" <> three <> zero

        assert Timezone.parse_offset(short, locale: :en) == {:ok, 19_800}, "#{system} #{short}"
        assert Timezone.parse_zone(long, locale: :de) == {:ok, {:offset, -19_800}}, "#{system}"
      end

      for text <- [
            "GMT+五:三〇",
            "GMT+〇五:三〇",
            "GMT+５:３０",
            "GMT+𝟎𝟓:𝟑𝟎",
            "GMT+𞥕:𞥓𞥐",
            "GMT+߀߅:߃߀",
            "GMT+๕:๓๐",
            "GMT+٠٥:٣٠",
            "GMT+०५:३०"
          ] do
        assert Timezone.parse_zone(text, locale: :en) == {:ok, {:offset, 19_800}}, text

        assert {:ok, resolved} = Timezone.resolve(text, ~N[2026-01-15 17:30:00], locale: :en)

        assert {resolved.utc_offset, DateTime.to_naive(resolved)} ==
                 {19_800, ~N[2026-01-15 17:30:00]}
      end
    end

    # Localize's own: TR35's parsing speaks of other digits in the GMT
    # format alone, and ICU4C 78.3 reads an ISO 8601 offset in 0 to 9 only,
    # "12:00 +0530" in Arabic-Indic digits being an error to it in `ar-EG`.
    # The date and time parsers read a time's digits in the locale's system
    # before its fields, the offset among them, and the zone reader reads
    # the same text alone. The digits are Unicode's decimal digits 0, 5, 3
    # and 8 of each script.
    test "an ISO 8601 offset in other digits" do
      for {text, offset} <- [
            {"+٠٥:٣٠", 19_800},
            {"+٠٥٣٠", 19_800},
            {"-०८:००", -28_800},
            {"-०८", -28_800}
          ] do
        assert Timezone.parse_offset(text, locale: :en) == {:ok, offset}, text
        assert Timezone.parse_zone(text, locale: :"ar-EG") == {:ok, {:offset, offset}}, text
      end

      {:ok, date} = Localize.Date.to_string(~D[2026-07-15], locale: :"ar-EG", format: :short)

      assert {:ok, datetime} =
               Localize.DateTime.parse(date <> " ١٢:٠٠ +٠٥٣٠",
                 locale: :"ar-EG",
                 date_format: :short,
                 time_format: "HH:mm Z"
               )

      assert {datetime.utc_offset, DateTime.to_naive(datetime)} ==
               {19_800, ~N[2026-07-15 12:00:00]}
    end

    # TR35's parsing reads the GMT format's number as "03, 3, 330, 3:30,
    # 33045 or 3:30:45", with "spaces after GMT, +/-, and before number",
    # and its `hourFormat` writes the hour as `H`, 0 to 23. Juneau kept
    # +15:02:19 until 1867 and Manila -15:56:08 until 1845, which ICU4C 78.3
    # writes "GMT+15:02:19" and "GMT-15:56:08" and reads back, with every
    # string here but those with spaces and those with nothing between
    # their digits: it reads the number as the locale's `hourFormat` writes
    # it, which has nothing between its digits in `am`.
    test "an offset's seconds after an hour of one digit, and an hour to 23" do
      for {text, offset} <- [
            {"GMT+3:30:45", 12_645},
            {"GMT+33045", 12_645},
            {"GMT+03:30:45", 12_645},
            {"GMT+033045", 12_645},
            {"GMT+330", 12_600},
            {"GMT +3", 10_800},
            {"GMT+ 3", 10_800},
            {"GMT+1:00:12", 3612},
            {"GMT+15:02:19", 54_139},
            {"GMT-15:56:08", -57_368},
            {"+15:02:19", 54_139},
            {"+150219", 54_139},
            {"-1556", -57_360},
            {"GMT+23:59:59", 86_399},
            {"UTC-23", -82_800}
          ] do
        assert Timezone.parse_offset(text, locale: :en) == {:ok, offset}, text
        assert Timezone.parse_zone(text, locale: :en) == {:ok, {:offset, offset}}, text
      end

      assert Timezone.parse_offset("ጂ ኤም ቲ+10012", locale: :am) == {:ok, 3612}
      assert Timezone.parse_offset("ጂ ኤም ቲ-75258", locale: :am) == {:ok, -28_378}
      assert Timezone.parse_offset("UTC-7.52.58", locale: :fi) == {:ok, -28_378}

      for text <- ["GMT+24", "GMT+3:60", "GMT+3:30:60", "+24:00", "+2400"] do
        assert {:error, %Localize.UnknownTimezoneError{}} =
                 Timezone.parse_offset(text, locale: :en),
               text
      end
    end

    # A date and time at an offset with seconds keeps them: the offset is its
    # `utc_offset`, and its abbreviation spells it as TR35's `xxxxx` does.
    test "an offset with seconds resolves to a date and time at that offset" do
      assert {:ok, datetime} =
               Timezone.resolve("GMT-07:52:58", ~N[1850-01-15 04:07:02], locale: :en)

      assert {datetime.utc_offset, datetime.std_offset, datetime.zone_abbr} ==
               {-28_378, 0, "-07:52:58"}

      assert DateTime.compare(datetime, ~U[1850-01-15 12:00:00Z]) == :eq

      assert {:ok, whole_minutes} =
               Timezone.resolve("GMT+5:30", ~N[2026-07-15 17:30:00], locale: :en)

      assert whole_minutes.zone_abbr == "+05:30"
    end

    # TR35's parsing: "Allow +, -, or nothing. Allow spaces after GMT, +/-,
    # and before number." A number with no sign after the literal, the
    # global one or the locale's, is an offset east of it. ICU4C 78.3 reads
    # none of these: it wants the sign.
    test "an offset with no sign after the GMT literal" do
      for {locale, text, offset} <- [
            {:en, "GMT 3", 10_800},
            {:en, "GMT3", 10_800},
            {:en, "UTC 0530", 19_800},
            {:en, "UT 5:30", 19_800},
            {:en, "gmt 03:30:45", 12_645},
            {:en, "GMT 0", 0},
            {:fr, "UTC 3", 10_800},
            {:fr, "UTC3:30", 12_600},
            {:"ar-EG", "غرينتش٣", 10_800},
            {:"ar-EG", "غرينتش ٣", 10_800},
            {:mr, "[GMT]5:30", 19_800},
            {:pt, "GMT 3", 10_800}
          ] do
        assert Timezone.parse_zone(text, locale: locale) == {:ok, {:offset, offset}},
               "#{locale} #{text}"

        assert Timezone.parse_offset(text, locale: locale) == {:ok, offset}, "#{locale} #{text}"
      end

      for text <- ["GMT 24", "GMT 3:60", "GMT abc", "GMT 1234567"] do
        assert {:error, %Localize.UnknownTimezoneError{}} =
                 Timezone.parse_zone(text, locale: :en),
               text
      end
    end

    # A number before a literal that follows it is as much a time of day in
    # that zone as an offset from it, so it keeps needing its sign: "10:30
    # GMT" is no zone, in `en` or in `pt`, whose GMT format, "{0} GMT", has
    # the literal after the offset.
    test "a number with no sign before the GMT literal is no offset" do
      for {locale, text} <- [
            {:en, "3 GMT"},
            {:en, "10:30 GMT"},
            {:pt, "3 GMT"},
            {:pt, "10:30 GMT"}
          ] do
        assert {:error, %Localize.UnknownTimezoneError{}} =
                 Timezone.parse_zone(text, locale: locale),
               "#{locale} #{text}"
      end

      assert Timezone.parse_zone("+3 GMT", locale: :pt) == {:ok, {:offset, 10_800}}
      assert Timezone.parse_zone("+3 GMT", locale: :en) == {:ok, {:offset, 10_800}}
    end

    # TR35 describes a zone read "as if it were an isolated string", and has
    # a zone "mixed in with other data" adapt that. Among the fields of a
    # date or time a number after the literal can be the next field's, so
    # there it needs its sign: `date` writes "Mon Oct 5 12:00:00 UTC 2026",
    # which is no time at an offset of 20:26, and `zh` and `my` write a zone
    # before the time ("z HH:mm:ss"), where "GMT 12:00:00" is noon in GMT.
    test "a zone among the fields of a date or time needs its offset's sign" do
      assert {:error, %Localize.TimeParseError{}} =
               Localize.Time.Parser.parse_with_zone("12:00:00 UTC 2026", locale: :en)

      assert {:error, %Localize.DateTimeParseError{}} =
               Localize.DateTime.parse("Mon Oct 5 12:00:00 UTC 2026", locale: :en)

      assert {:error, %Localize.DateTimeParseError{}} =
               Localize.DateTime.parse("June 5, 2026 12:00 GMT 3", locale: :en)

      assert {:error, %Localize.UnknownTimezoneError{}} =
               Timezone.parse_zone_field("GMT 3", locale: :en)

      assert Timezone.parse_zone_field("GMT+3", locale: :en) == {:ok, {:offset, 10_800}}
      assert Timezone.parse_zone_field("GMT", locale: :en) == {:ok, {:offset, 0}}

      for locale <- [:zh, :my] do
        assert {:ok, ~T[12:00:00], "GMT"} =
                 Localize.Time.Parser.parse_with_zone("GMT 12:00:00", locale: locale)
      end

      assert {:ok, datetime} = Localize.DateTime.parse("2026年6月5日 GMT 12:00:00", locale: :zh)
      assert {datetime.utc_offset, DateTime.to_naive(datetime)} == {0, ~N[2026-06-05 12:00:00]}
    end

    # An hour no offset has, and digits with no sign, are no offset in any
    # digits.
    test "digits that are no offset" do
      for text <- ["GMT+٢٥", "٥", "٠٥:٣٠"] do
        assert {:error, %Localize.UnknownTimezoneError{}} = Timezone.parse_zone(text, locale: :en)
      end
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

    # ICU4C reads each of these so. A country with several zones stands for
    # its primary zone, as its location is written, only where the string
    # names no other zone: a city in the qualifier comes first, and a name
    # qualified by a country is the metazone's zone for that country, which
    # for Western European time and Spain is the Canary Islands' (`fo`
    # writes that zone so, the Faroe Islands having their own).
    test "a country with several zones" do
      for {locale, text, time_zone} <- [
            {:en, "Germany Time", "Europe/Berlin"},
            {:en, "Spain Time", "Europe/Madrid"},
            {:de, "Spanien (Ortszeit)", "Europe/Madrid"},
            {:en, "Chile Time", "America/Santiago"},
            {:en, "Chile Time (Punta Arenas)", "America/Punta_Arenas"},
            {:en, "Chile Time (Coyhaique)", "America/Coyhaique"},
            {:en, "Central European Time (Spain)", "Europe/Madrid"},
            {:fo, "Vesturevropa tíð (Spania)", "Atlantic/Canary"}
          ] do
        assert Timezone.parse_zone(text, locale: locale) == {:ok, {:zone, time_zone, :generic}},
               "#{locale} #{text}"
      end
    end

    # `ko.xml` names American Samoa's metazone "사모아 표준시", which has the
    # shape of its standard region format, "{0} 표준시", with the country
    # Samoa in it, and `pl.xml` names it "Samoa (czas standardowy)" likewise.
    # No pattern writes a standard region format, so each is the metazone's
    # name, as ICU4C reads them; Samoa's own location is "사모아 시간". With a
    # city, as the formatter qualifies the name for Midway, it is that city.
    test "a metazone's name in the shape of a region format" do
      pago_pago = {:ok, {:zone, "Pacific/Pago_Pago", :standard}}

      assert Timezone.parse_zone("사모아 표준시", locale: :ko) == pago_pago
      assert Timezone.parse_zone("Samoa (czas standardowy)", locale: :pl) == pago_pago

      assert Timezone.parse_zone("사모아 시간", locale: :ko) ==
               {:ok, {:zone, "Pacific/Apia", :generic}}

      assert Timezone.parse_zone("사모아 표준시(미드웨이)", locale: :ko) ==
               {:ok, {:zone, "Pacific/Midway", :standard}}
    end

    # `en`'s short names "ET", "MT" and "PT" are also the codes of Ethiopia,
    # Malta and Portugal; a code is read only in a qualifier, where TR35's
    # composition writes one for a country the locale does not name.
    test "a short name that is also a country's code" do
      for {text, time_zone} <- [
            {"ET", "America/New_York"},
            {"MT", "America/Denver"},
            {"PT", "America/Los_Angeles"},
            {"MT (Phoenix)", "America/Phoenix"},
            {"PT (Canada)", "America/Vancouver"}
          ] do
        assert Timezone.parse_zone(text, locale: :en) == {:ok, {:zone, time_zone, :generic}},
               text
      end

      assert Timezone.parse_zone("Waktu Pasifik (CA)", locale: :su) ==
               {:ok, {:zone, "America/Vancouver", :generic}}
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

    # CLDR 49's `uk.xml` names Eastern time "за східним часом (ET)", itself
    # in the fallback format's shape, with a country's code in parentheses;
    # ICU4C 78.3's CLDR 48 data names it otherwise.
    test "a name in parentheses that is itself a name" do
      assert Timezone.parse_zone("за східним часом (ET)", locale: :uk) ==
               {:ok, {:zone, "America/New_York", :generic}}
    end

    test "text that is no zone" do
      for text <- ["XQZV", "Unknown City", "GMT+?", "AM", ""] do
        assert {:error, %Localize.UnknownTimezoneError{}} = Timezone.parse_zone(text, locale: :en)
      end
    end

    # Bytes that are no UTF-8 name no zone, alone or after what would be
    # an offset or a name; `parse_zone/2` and `resolve/3` raised on them.
    test "bytes that are not text" do
      for bytes <- [
            <<0xFF, 0xFE>>,
            "GMT+5" <> <<0xFF>>,
            "Eastern " <> <<0xC3>> <> " Time",
            <<0xED, 0xA0, 0x80>>
          ] do
        assert {:error, %Localize.UnknownTimezoneError{}} =
                 Timezone.parse_zone(bytes, locale: :en)

        assert {:error, %Localize.UnknownTimezoneError{}} =
                 Timezone.parse_offset(bytes, locale: :en)

        assert {:error, %Localize.UnknownTimezoneError{}} =
                 Timezone.resolve(bytes, ~N[2023-07-01 10:00:00], locale: :en)
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

    # ICU4C reads these four as 07:30, 06:30, 06:30 and 05:30 UTC: a name of
    # standard or daylight time picks its own side of a wall time the clocks
    # pass twice, and keeps its own offset at one they skip.
    test "a name of standard or daylight time where the clocks change" do
      for {text, naive, utc} <- [
            {"Eastern Standard Time", ~N[2023-03-12 02:30:00], ~U[2023-03-12 07:30:00Z]},
            {"Eastern Daylight Time", ~N[2023-03-12 02:30:00], ~U[2023-03-12 06:30:00Z]},
            {"Eastern Standard Time", ~N[2023-11-05 01:30:00], ~U[2023-11-05 06:30:00Z]},
            {"Eastern Daylight Time", ~N[2023-11-05 01:30:00], ~U[2023-11-05 05:30:00Z]}
          ] do
        assert {:ok, datetime} = Timezone.resolve(text, naive, locale: :en)
        assert DateTime.compare(datetime, utc) == :eq, "#{text} at #{naive}"
      end
    end

    # CLDR's `metaZones.xml` gives Punta Arenas `stdOffset="-04"` and
    # `dstOffset="-03"` in the Chile metazone: the -03:00 the zone keeps all
    # year is Chile's summer time, so that name is the zone's own time in
    # every month, and the standard name stands at -04:00. Dublin has
    # `stdOffset="+00" dstOffset="+01"`, and ICU4C reads "Irish Standard
    # Time" in January as 09:00 UTC.
    test "a name of the time a metazone period's offsets name" do
      for naive <- [~N[2026-01-15 10:00:00], ~N[2026-07-15 10:00:00]] do
        assert {:ok,
                %DateTime{time_zone: "America/Punta_Arenas", utc_offset: -10_800, std_offset: 0}} =
                 Timezone.resolve("Chile Summer Time (Punta Arenas)", naive, locale: :en)

        assert {:ok, %DateTime{time_zone: "Etc/UTC", utc_offset: -14_400}} =
                 Timezone.resolve("Chile Standard Time (Punta Arenas)", naive, locale: :en)
      end

      assert {:ok, %DateTime{time_zone: "Europe/Dublin"} = summer} =
               Timezone.resolve("Irish Standard Time", ~N[2026-07-15 10:00:00], locale: :en)

      assert DateTime.compare(summer, ~U[2026-07-15 09:00:00Z]) == :eq

      assert {:ok, %DateTime{time_zone: "Etc/UTC"} = winter} =
               Timezone.resolve("Irish Standard Time", ~N[2026-01-15 10:00:00], locale: :en)

      assert DateTime.compare(winter, ~U[2026-01-15 09:00:00Z]) == :eq
    end

    # Knox, Indiana kept Eastern Standard Time from October 1991 and Central
    # time before it, and Caracas -04:00 until December 2007 and -04:30
    # after. A name is read with the time the zone keeps at the date, not
    # one it kept in the months either side; ICU4C reads the second as
    # 14:00 UTC.
    test "a name near a change of the zone's offset" do
      assert {:ok, %DateTime{time_zone: "America/Indiana/Knox"} = knox} =
               Timezone.resolve("Eastern Standard Time (Knox, Indiana)", ~N[1991-11-15 10:00:00],
                 locale: :en
               )

      assert DateTime.compare(knox, ~U[1991-11-15 15:00:00Z]) == :eq

      assert {:ok, %DateTime{time_zone: "America/Caracas"} = caracas} =
               Timezone.resolve("Venezuela Time", ~N[2007-03-15 10:00:00], locale: :en)

      assert DateTime.compare(caracas, ~U[2007-03-15 14:00:00Z]) == :eq
    end

    # `en.xml` names the Kyrgyzstan metazone "Kyrgyzstan Time" and nothing
    # else, and that is Bishkek's location format too. By TR35's type
    # fallback a metazone with no daylight name needs none and its standard
    # name stands for all three types, so the name is Bishkek's time in the
    # summers it kept daylight time as well: ICU4C reads it as 03:00 UTC
    # with `VVVV` and `vvvv`, and as standard time with `zzzz` (a recorded
    # divergence).
    test "the only name a metazone has, in a zone keeping daylight time" do
      assert {:ok, %DateTime{time_zone: "Asia/Bishkek", std_offset: 3600} = summer} =
               Timezone.resolve("Kyrgyzstan Time", ~N[1990-07-15 10:00:00], locale: :en)

      assert DateTime.compare(summer, ~U[1990-07-15 03:00:00Z]) == :eq

      assert {:ok, %DateTime{time_zone: "Asia/Bishkek", std_offset: 0} = winter} =
               Timezone.resolve("Kyrgyzstan Time", ~N[1990-01-15 10:00:00], locale: :en)

      assert DateTime.compare(winter, ~U[1990-01-15 04:00:00Z]) == :eq
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

    # ISO 8601 writes an offset, or `Z`, hard against a time, and
    # `Time.from_iso8601/1` reads a time that carries one and discards it.
    # A date in a locale's format beside such a time kept no offset and came
    # back a `NaiveDateTime`; it is the offset's `DateTime`, as it is when a
    # space parts the two. The offsets are ISO 8601's: "+02:00" is 7,200
    # seconds ahead of UTC and "-05:00" 18,000 behind.
    test "an ISO 8601 offset hard against the time" do
      for {text, offset} <- [
            {"11/22/2023 14:30:45+02:00", 7200},
            {"11/22/2023 14:30:45+0200", 7200},
            {"11/22/2023 14:30:45+02", 7200},
            {"11/22/2023 14:30:45-05:00", -18_000},
            {"11/22/2023 14:30:45.250+02:00", 7200},
            {"11/22/2023 14:30:45Z", 0},
            {"11/22/2023, 14:30:45 +02:00", 7200}
          ] do
        assert {:ok,
                %DateTime{
                  utc_offset: ^offset,
                  year: 2023,
                  month: 11,
                  day: 22,
                  hour: 14,
                  minute: 30,
                  second: 45
                }} = Localize.DateTime.parse(text, locale: :en),
               text
      end

      assert {:ok, %{hour: 14, utc_offset: 7200, zone_abbr: "+02:00"}} =
               Localize.DateTime.parse("11/22/2023 14:30:45+02:00", locale: :en, as: :map)

      assert Localize.DateTime.parse("11/22/2023 14:30:45", locale: :en) ==
               {:ok, ~N[2023-11-22 14:30:45]}
    end

    # The time's parser hands the offset on, and a time alone has no zone to
    # keep.
    test "an ISO 8601 offset is read with its time" do
      assert Localize.Time.Parser.parse_with_zone("14:30:45+02:00", locale: :en) ==
               {:ok, ~T[14:30:45], "+02:00"}

      assert Localize.Time.Parser.parse_with_zone("14:30:45Z", locale: :en) ==
               {:ok, ~T[14:30:45], "Z"}

      assert Localize.Time.Parser.parse_with_zone("14:30:45", locale: :en) ==
               {:ok, ~T[14:30:45], nil}

      assert Localize.Time.parse("14:30:45+02:00", locale: :en) == {:ok, ~T[14:30:45]}
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
