defmodule Localize.ParsingCoverageTest do
  use ExUnit.Case, async: true

  # Systematic coverage of the parser engines through their public
  # entry points: `Localize.DateTime.Parser.parse/2`, `Localize.Date.parse/2`,
  # `Localize.Interval.parse/2`, `Localize.Time.parse/2`, and
  # `Localize.DateTime.parse/2`, plus the ISO-8601 calendar
  # callbacks that route through `Calendrical.Parse`.
  #
  # Each documented lenient-parsing behavior from CHANGELOG 0.6.0
  # through 0.9.1 is exercised at least once, in a non-:en locale
  # where applicable.

  @reference_date ~D[2026-07-05]

  # ── Date: ISO 8601 escape hatches (accepted in every locale) ──

  describe "Date.parse/2 ISO 8601 forms" do
    test "extended format in :fr" do
      assert Localize.Date.parse("2026-05-23", locale: :fr) == {:ok, ~D[2026-05-23]}
    end

    test "basic format (YYYYMMDD) in :ja" do
      assert Localize.Date.parse("20260523", locale: :ja) == {:ok, ~D[2026-05-23]}
    end

    test "ordinal date (YYYY-DDD) in :ja" do
      assert Localize.Date.parse("2026-143", locale: :ja) == {:ok, ~D[2026-05-23]}
    end

    test "ISO week date (YYYY-Www-D) in :ja" do
      assert Localize.Date.parse("2026-W21-6", locale: :ja) == {:ok, ~D[2026-05-23]}
    end
  end

  # ── Date: documented lenient behaviors ──

  describe "Date.parse/2 lenient behaviors" do
    test "M<->d swap under :en (CLDR ships MMM d, y)" do
      assert Localize.Date.parse("23 May 2026", locale: :en) == {:ok, ~D[2026-05-23]}
      assert Localize.Date.parse("23 Feb 2013", locale: :en) == {:ok, ~D[2013-02-23]}
    end

    test "M<->d swap under :fr (CLDR ships d MMM y)" do
      assert Localize.Date.parse("mai 23", locale: :fr, reference_date: @reference_date) ==
               {:ok, ~D[2026-05-23]}
    end

    test "case-insensitive month names in :fr" do
      assert Localize.Date.parse("23 Mai", locale: :fr, reference_date: @reference_date) ==
               {:ok, ~D[2026-05-23]}

      assert Localize.Date.parse("23 mai 2026", locale: :fr) == {:ok, ~D[2026-05-23]}
    end

    test "abbreviated month with omitted period in :fr (CLDR ships janv.)" do
      assert Localize.Date.parse("5 janv 2026", locale: :fr) == {:ok, ~D[2026-01-05]}
    end

    test "abbreviated month with added period in :en (CLDR ships Jun)" do
      assert Localize.Date.parse("01/Jun./2018", locale: :en) == {:ok, ~D[2018-06-01]}
    end

    test "dash/slash/period-separated swap variants in :en" do
      assert Localize.Date.parse("01-Feb-18", locale: :en, reference_date: @reference_date) ==
               {:ok, ~D[2018-02-01]}

      assert Localize.Date.parse("01.Feb.2018", locale: :en) == {:ok, ~D[2018-02-01]}
    end

    test "comma omission in :en (CLDR ships MMM d, y)" do
      assert Localize.Date.parse("May 5 2026", locale: :en) == {:ok, ~D[2026-05-05]}
    end

    test "interior double whitespace is collapsed" do
      assert Localize.Date.parse("May  5,  2026", locale: :en) == {:ok, ~D[2026-05-05]}
    end

    test "weekday-prefix stripping in :en" do
      assert Localize.Date.parse("Sun, 01 January 2017", locale: :en) == {:ok, ~D[2017-01-01]}

      assert Localize.Date.parse("Tuesday, November 29, 2016", locale: :en) ==
               {:ok, ~D[2016-11-29]}
    end

    test "weekday-prefix stripping in :fr" do
      assert Localize.Date.parse("lundi, 1 janvier 2025", locale: :fr) == {:ok, ~D[2025-01-01]}
    end

    test "ordinal-suffix stripping in :en" do
      assert Localize.Date.parse("1st January 2026", locale: :en) == {:ok, ~D[2026-01-01]}
      assert Localize.Date.parse("3rd March 2023", locale: :en) == {:ok, ~D[2023-03-03]}
    end

    test "ordinal-suffix stripping in :fr" do
      assert Localize.Date.parse("1er janvier 2025", locale: :fr) == {:ok, ~D[2025-01-01]}
    end

    test "ordinal-prefix stripping in :ja (RBNF renders 第16)" do
      assert Localize.Date.parse("2026年5月第16日", locale: :ja) == {:ok, ~D[2026-05-16]}
    end

    test "locale-preferred numeric orders" do
      assert Localize.Date.parse("16.05.2026", locale: :de) == {:ok, ~D[2026-05-16]}
      assert Localize.Date.parse("16. Mai 2026", locale: :de) == {:ok, ~D[2026-05-16]}
      assert Localize.Date.parse("2026/05/16", locale: :ja) == {:ok, ~D[2026-05-16]}
      assert Localize.Date.parse("2026年5月16日", locale: :ja) == {:ok, ~D[2026-05-16]}
    end

    test "two-digit year pivots against the reference date" do
      assert Localize.Date.parse("5/16/26", locale: :en, reference_date: @reference_date) ==
               {:ok, ~D[2026-05-16]}
    end

    test "quarter and week skeletons in :en" do
      assert Localize.Date.parse("Q2 2026", locale: :en) == {:ok, ~D[2026-04-01]}
      assert Localize.Date.parse("2nd quarter 2026", locale: :en) == {:ok, ~D[2026-04-01]}
      assert Localize.Date.parse("week 20 of 2026", locale: :en) == {:ok, ~D[2026-05-11]}
    end

    test "trailing weekday name is validated against the date in :ja" do
      # 2026-05-16 is a Saturday; the CLDR :ja full pattern carries EEEE.
      assert Localize.Date.parse("2026年5月16日土曜日", locale: :ja) == {:ok, ~D[2026-05-16]}
    end

    test "mismatched trailing weekday name rejects the parse in :ja" do
      assert {:error, %Localize.DateParseError{}} =
               Localize.Date.parse("2026年5月16日月曜日", locale: :ja)
    end
  end

  # ── Date: calendars ──

  # The `:calendar` option is resolved to a calendar module before any
  # parsing happens, so an unavailable or unknown calendar is reported the
  # same way whichever shape the input takes. Only `Calendar.ISO` ships
  # with this library; the CLDR calendars come from `calendrical`, and
  # their per-calendar parsing behaviour is covered by that package's own
  # suite.
  describe "Date.parse/2 calendar handling" do
    test "the default calendar needs no dependency" do
      for calendar <- [:gregorian, Calendar.ISO] do
        assert Localize.Date.parse("2026-05-16", locale: :en, calendar: calendar) ==
                 {:ok, ~D[2026-05-16]}
      end
    end

    test "a CLDR calendar whose module is absent names the package it needs" do
      for calendar <- [:hebrew, :chinese, :buddhist, :coptic, :islamic, :persian] do
        assert {:error, %Localize.DependencyRequiredError{package: "calendrical"}} =
                 Localize.Date.parse("2026-05-16", locale: :en, calendar: calendar)
      end
    end

    # Both input shapes must agree. The ISO path used to skip calendar
    # resolution entirely and return a Gregorian date, so asking for a
    # calendar it could not honour succeeded with the wrong answer.
    test "ISO and locale-formatted input agree about an unavailable calendar" do
      iso = Localize.Date.parse("2026-05-16", locale: :de, calendar: :hebrew)
      locale = Localize.Date.parse("16.05.2026", locale: :de, calendar: :hebrew)

      assert {:error, %Localize.DependencyRequiredError{}} = iso
      assert iso == locale
    end

    test "an unknown calendar is rejected rather than quietly ignored" do
      for calendar <- [:bogus, NoSuchCalendarModule, nil, "hebrew"] do
        assert {:error, %Localize.UnknownCalendarError{}} =
                 Localize.Date.parse("2026-05-16", locale: :en, calendar: calendar)
      end
    end

    # `:return_calendar` governs the calendar of the returned date, not the
    # one the input is interpreted in, so it cannot stand in for a calendar
    # module that is not installed.
    test "return_calendar: :iso does not waive the parsing calendar" do
      assert {:error, %Localize.DependencyRequiredError{}} =
               Localize.Date.parse("2026-05-16",
                 locale: :en,
                 calendar: :hebrew,
                 return_calendar: :iso
               )

      assert Localize.Date.parse("2026-05-16", locale: :en, return_calendar: :iso) ==
               {:ok, ~D[2026-05-16]}
    end
  end

  # ── Date: as: :map ──

  describe "Date.parse/2 with as: :map" do
    test "partial month + day in :en" do
      assert Localize.Date.parse("May 5", locale: :en, as: :map) ==
               {:ok, %{calendar: Calendar.ISO, month: 5, day: 5}}
    end

    test "year only in :en" do
      assert Localize.Date.parse("2026", locale: :en, as: :map) ==
               {:ok, %{calendar: Calendar.ISO, year: 2026}}
    end

    test "month only in :fr" do
      assert Localize.Date.parse("mai", locale: :fr, as: :map) ==
               {:ok, %{calendar: Calendar.ISO, month: 5}}
    end

    test "month + year in :de" do
      assert Localize.Date.parse("Mai 2026", locale: :de, as: :map) ==
               {:ok, %{calendar: Calendar.ISO, month: 5, year: 2026}}
    end
  end

  # ── Date: error paths ──

  describe "Date.parse/2 error paths" do
    test "unparseable input returns a DateParseError with a rendered message" do
      assert {:error, %Localize.DateParseError{} = error} =
               Localize.Date.parse("not a date", locale: :en)

      assert error.input == "not a date"
      assert error.locale == :en
      assert error.calendar == :gregorian

      assert Exception.message(error) ==
               "could not parse \"not a date\" as a date in locale :en " <>
                 "(calendar :gregorian); ISO-8601 (YYYY-MM-DD) is always accepted as a fallback"
    end

    test "unparseable input in :de (locale without ordinal suffixes)" do
      assert {:error, %Localize.DateParseError{locale: :de}} =
               Localize.Date.parse("kauderwelsch", locale: :de)
    end

    test "unparseable input in :ru (bare-digit ordinal RBNF)" do
      assert {:error, %Localize.DateParseError{locale: :ru}} =
               Localize.Date.parse("абракадабра", locale: :ru)
    end

    test "week number out of range" do
      assert {:error, %Localize.DateParseError{}} =
               Localize.Date.parse("week 99 of 2026", locale: :en)
    end

    test "day that does not exist in the month" do
      assert {:error, %Localize.DateParseError{}} =
               Localize.Date.parse("February 31, 2026", locale: :en)
    end

    test "day of month out of range" do
      assert {:error, %Localize.DateParseError{}} =
               Localize.Date.parse("May 45, 2026", locale: :en)
    end

    test "numeric month out of range" do
      assert {:error, %Localize.DateParseError{}} =
               Localize.Date.parse("25/45/6789", locale: :en)
    end
  end

  # ── Date ranges ──

  describe "Date.parse_range/2 lenient behaviors" do
    test "CLDR en-dash interval with year inheritance" do
      assert Localize.Interval.parse("May 5 – May 10, 2026", locale: :en) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}
    end

    test "ASCII hyphen where CLDR declares an en-dash" do
      assert Localize.Interval.parse("May 23 - 25, 2026", locale: :en) ==
               {:ok, Date.range(~D[2026-05-23], ~D[2026-05-25])}
    end

    test "wide month where the pattern declares abbreviated" do
      assert Localize.Interval.parse("May 5 – June 10, 2026", locale: :en) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-06-10])}

      assert Localize.Interval.parse("May 5 – Jun 10, 2026", locale: :en) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-06-10])}
    end

    test "day-first cross-endpoint month shift" do
      assert Localize.Interval.parse("23 - 25 May, 2026", locale: :en) ==
               {:ok, Date.range(~D[2026-05-23], ~D[2026-05-25])}
    end

    test "day-first per-endpoint month/day swap" do
      assert Localize.Interval.parse("5 May – 10 June, 2026", locale: :en) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-06-10])}
    end

    test "comma omission in a range" do
      assert Localize.Interval.parse("23 – 25 May 2026", locale: :en) ==
               {:ok, Date.range(~D[2026-05-23], ~D[2026-05-25])}
    end

    test "two-digit years in both endpoints pivot" do
      assert Localize.Interval.parse("5/5/26 – 5/10/26",
               locale: :en,
               reference_date: @reference_date
             ) == {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}
    end

    test "range in :fr" do
      assert Localize.Interval.parse("5 mai – 10 mai 2026", locale: :fr) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}

      assert Localize.Interval.parse("5–10 mai 2026", locale: :fr) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}
    end

    test "range in :de" do
      assert Localize.Interval.parse("5.–10. Mai 2026", locale: :de) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}

      assert Localize.Interval.parse("05.05.2026 – 10.05.2026", locale: :de) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}
    end

    test "range in :ja with wave-dash separator" do
      assert Localize.Interval.parse("2026年5月5日～5月10日", locale: :ja) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}

      assert Localize.Interval.parse("2026/05/05～2026/05/10", locale: :ja) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}
    end

    test "range in :es (patterns with quoted 'de' literals)" do
      assert {:ok, %Date.Range{}} =
               Localize.Interval.parse("5 de mayo – 10 de mayo de 2026", locale: :es)
    end
  end

  describe "Date.parse_range/2 with as: :map" do
    test "year inheritance across endpoints" do
      assert Localize.Interval.parse("May 5 – May 10, 2026", locale: :en, as: :map) ==
               {:ok,
                {%{calendar: Calendar.ISO, year: 2026, month: 5, day: 5},
                 %{calendar: Calendar.ISO, year: 2026, month: 5, day: 10}}}
    end

    test "month-only endpoints omit the day key" do
      assert Localize.Interval.parse("May – June 2026", locale: :en, as: :map) ==
               {:ok,
                {%{calendar: Calendar.ISO, month: 5, year: 2026},
                 %{calendar: Calendar.ISO, month: 6, year: 2026}}}
    end

    test "pair form returns two maps" do
      assert Localize.Interval.parse({"May 5, 2026", "May 10, 2026"},
               locale: :en,
               as: :map
             ) ==
               {:ok,
                {%{calendar: Calendar.ISO, year: 2026, month: 5, day: 5},
                 %{calendar: Calendar.ISO, year: 2026, month: 5, day: 10}}}
    end
  end

  describe "Date.parse_range/2 inverted ranges" do
    test "inverted single-string range is rejected by default" do
      assert {:error, %Localize.DateRangeParseError{} = error} =
               Localize.Interval.parse("2026-05-10 – 2026-05-05", locale: :en)

      assert error.reason == :inverted
      assert error.from == ~D[2026-05-10]
      assert error.to == ~D[2026-05-05]

      assert Exception.message(error) ==
               "range end ~D[2026-05-05] is before start ~D[2026-05-10]; " <>
                 "pass `allow_inverted: true` to permit descending ranges"
    end

    test "inverted single-string range with allow_inverted: true descends" do
      assert Localize.Interval.parse("2026-05-10 – 2026-05-05",
               locale: :en,
               allow_inverted: true
             ) == {:ok, Date.range(~D[2026-05-10], ~D[2026-05-05], -1)}
    end

    test "inverted pair form is rejected by default" do
      assert {:error, %Localize.DateRangeParseError{reason: :inverted}} =
               Localize.Interval.parse({"2026-05-10", "2026-05-05"}, locale: :en)
    end

    test "inverted pair form with allow_inverted: true descends" do
      assert Localize.Interval.parse({"2026-05-10", "2026-05-05"},
               locale: :en,
               allow_inverted: true
             ) == {:ok, Date.range(~D[2026-05-10], ~D[2026-05-05], -1)}
    end
  end

  describe "Date.parse_range/2 error paths" do
    test ":no_separator reason and message" do
      assert {:error, %Localize.DateRangeParseError{} = error} =
               Localize.Interval.parse("gibberish", locale: :en)

      assert error.reason == :no_separator
      assert error.locale == :en
      assert Exception.message(error) =~ "could not find an interval separator in \"gibberish\""
    end

    test ":from_parse_failed carries the endpoint cause" do
      assert {:error, %Localize.DateRangeParseError{} = error} =
               Localize.Interval.parse({"nonsense", "2026-05-10"}, locale: :en)

      assert error.reason == :from_parse_failed
      assert %Localize.DateParseError{input: "nonsense"} = error.cause

      assert Exception.message(error) =~
               "range from-endpoint \"nonsense\" could not be parsed: could not parse"
    end

    test ":to_parse_failed carries the endpoint cause" do
      assert {:error, %Localize.DateRangeParseError{} = error} =
               Localize.Interval.parse({"2026-05-10", "nonsense"}, locale: :en)

      assert error.reason == :to_parse_failed
      assert %Localize.DateParseError{input: "nonsense"} = error.cause
    end

    test "endpoint failure after separator split" do
      assert {:error, %Localize.DateRangeParseError{reason: :from_parse_failed}} =
               Localize.Interval.parse("25/45/2026 – 27/46/2026", locale: :en)
    end

    test "reason_atoms/0 enumerates the closed reason set" do
      assert Localize.DateRangeParseError.reason_atoms() ==
               [:no_separator, :inverted, :from_parse_failed, :to_parse_failed]
    end

    test "catch-all message for an exception without a reason" do
      error = Localize.DateRangeParseError.exception(input: "x")
      assert Exception.message(error) == "could not parse \"x\" as a date range"
    end
  end

  # ── Time ──

  describe "Time.parse/2" do
    test "ISO 8601 forms" do
      assert Localize.Time.parse("14:30:15", locale: :en) == {:ok, ~T[14:30:15]}
      assert Localize.Time.parse("14:30:15.5", locale: :en) == {:ok, ~T[14:30:15.5]}
    end

    test "12-hour clock with day-period marker in :en" do
      assert Localize.Time.parse("2:30 PM", locale: :en) == {:ok, ~T[14:30:00]}
      assert Localize.Time.parse("11 am", locale: :en) == {:ok, ~T[11:00:00]}
    end

    test "day-period boundaries: noon and midnight" do
      assert Localize.Time.parse("12 noon", locale: :en) == {:ok, ~T[12:00:00]}
      assert Localize.Time.parse("12 midnight", locale: :en) == {:ok, ~T[00:00:00]}
    end

    test "flexible day periods disambiguate AM/PM in :en" do
      assert Localize.Time.parse("10 in the morning", locale: :en) == {:ok, ~T[10:00:00]}
      assert Localize.Time.parse("4 in the afternoon", locale: :en) == {:ok, ~T[16:00:00]}
      assert Localize.Time.parse("10 at night", locale: :en) == {:ok, ~T[22:00:00]}
    end

    test "narrow day-period markers do not consume zone letters" do
      # Regression shape from 0.7.0: "P" must not match as day_period
      # leaving "ST" as the zone.
      assert Localize.Time.parse("11:30 PST", locale: :en) == {:ok, ~T[11:30:00]}
    end

    test "non-:en locales" do
      assert Localize.Time.parse("14:30", locale: :fr) == {:ok, ~T[14:30:00]}
      assert Localize.Time.parse("午前11:30", locale: :ja) == {:ok, ~T[11:30:00]}
    end

    test "as: :map returns only supplied fields" do
      assert Localize.Time.parse("11 am", locale: :en, as: :map) == {:ok, %{hour: 11}}

      assert Localize.Time.parse("14:30:15", locale: :en, as: :map) ==
               {:ok, %{hour: 14, minute: 30, second: 15}}

      assert Localize.Time.parse("14:30:15.25", locale: :en, as: :map) ==
               {:ok, %{hour: 14, minute: 30, second: 15, microsecond: {250_000, 2}}}
    end

    test "as: :map surfaces a captured zone" do
      assert Localize.Time.parse("11:30 PST", locale: :en, as: :map) ==
               {:ok, %{hour: 11, minute: 30, time_zone: "PST"}}
    end

    test "unparseable input returns a TimeParseError with a rendered message" do
      assert {:error, %Localize.TimeParseError{} = error} =
               Localize.Time.parse("not a time", locale: :en)

      assert error.input == "not a time"
      assert error.locale == :en

      assert Exception.message(error) ==
               "could not parse \"not a time\" as a time in locale :en; " <>
                 "ISO-8601 (HH:MM[:SS[.frac]]) is always accepted as a fallback"
    end
  end

  # ── DateTime ──

  describe "Timezone.parse_offset/2" do
    test "ISO 8601 offsets" do
      assert Localize.DateTime.Timezone.parse_offset("Z") == {:ok, 0}
      assert Localize.DateTime.Timezone.parse_offset("+05:30") == {:ok, 19_800}
      assert Localize.DateTime.Timezone.parse_offset("+0530") == {:ok, 19_800}
      assert Localize.DateTime.Timezone.parse_offset("+05") == {:ok, 18_000}
      assert Localize.DateTime.Timezone.parse_offset("-08:00") == {:ok, -28_800}
      assert Localize.DateTime.Timezone.parse_offset("+10:30:15") == {:ok, 37_815}
    end

    test "ISO 8601 requires a two-digit hour" do
      assert {:error, %Localize.UnknownTimezoneError{}} =
               Localize.DateTime.Timezone.parse_offset("+5")
    end

    test "offsets out of range are rejected" do
      for zone <- ["+15:00", "+05:75", "+05:00:61"] do
        assert {:error, %Localize.UnknownTimezoneError{}} =
                 Localize.DateTime.Timezone.parse_offset(zone)
      end
    end

    test "ASCII GMT, UTC and UT spellings, in either position" do
      assert Localize.DateTime.Timezone.parse_offset("GMT") == {:ok, 0}
      assert Localize.DateTime.Timezone.parse_offset("UTC") == {:ok, 0}
      assert Localize.DateTime.Timezone.parse_offset("UT") == {:ok, 0}
      assert Localize.DateTime.Timezone.parse_offset("GMT+10:30") == {:ok, 37_800}
      assert Localize.DateTime.Timezone.parse_offset("gmt+3") == {:ok, 10_800}
      assert Localize.DateTime.Timezone.parse_offset("UTC-5:30") == {:ok, -19_800}
      assert Localize.DateTime.Timezone.parse_offset("GMT +01:00") == {:ok, 3600}
      assert Localize.DateTime.Timezone.parse_offset("+10:30 GMT") == {:ok, 37_800}
    end

    test "round-trips the short form gmt_format/3 emits" do
      offset = -28_800

      {:ok, formatted} =
        Localize.DateTime.Timezone.gmt_format(%{utc_offset: offset}, :en, format: :short)

      assert formatted == "GMT-8"
      assert Localize.DateTime.Timezone.parse_offset(formatted) == {:ok, offset}
    end

    test "a locale's own GMT spelling, prefix and suffix" do
      # `ar` spells the literal "غرينتش" and `pt-TL` places it after the
      # offset — neither is reachable through the ASCII branch.
      assert Localize.DateTime.Timezone.parse_offset("غرينتش+03:00", locale: :ar) == {:ok, 10_800}

      assert Localize.DateTime.Timezone.parse_offset("+03:00 GMT", locale: :"pt-TL") ==
               {:ok, 10_800}
    end

    test "a localized literal that is also a zone abbreviation needs an offset" do
      # `yo` spells the GMT format "WAT", which is also West Africa Time.
      # Reading a bare "WAT" as UTC would be wrong, so only the form
      # carrying an offset resolves.
      assert {:error, %Localize.UnknownTimezoneError{}} =
               Localize.DateTime.Timezone.parse_offset("WAT", locale: :yo)

      assert Localize.DateTime.Timezone.parse_offset("WAT+01:00", locale: :yo) == {:ok, 3600}
    end

    test "named zones are rejected rather than guessed at" do
      for zone <- ["PST", "Asia/Tokyo", "Asia/Beirut", "America/New_York", "XQZV"] do
        assert {:error, %Localize.UnknownTimezoneError{}} =
                 Localize.DateTime.Timezone.parse_offset(zone)
      end
    end

    test "malformed input returns an error rather than raising" do
      for zone <- ["", "+", "-", "GMT+", "GMT+:", "----", "  ", "Z+05:00", "+aa:bb"] do
        assert {:error, %Localize.UnknownTimezoneError{}} =
                 Localize.DateTime.Timezone.parse_offset(zone)
      end
    end

    test "non-binary input returns an error rather than raising" do
      for zone <- [nil, :utc, 42, %{}, ["GMT"]] do
        assert {:error, %Localize.UnknownTimezoneError{}} =
                 Localize.DateTime.Timezone.parse_offset(zone)
      end
    end
  end

  describe "DateTime.parse/2" do
    test "ISO 8601 with T and with space separator" do
      assert Localize.DateTime.parse("2026-05-23T14:30:00", locale: :en) ==
               {:ok, ~N[2026-05-23 14:30:00]}

      assert Localize.DateTime.parse("2026-05-23 14:30:00", locale: :en) ==
               {:ok, ~N[2026-05-23 14:30:00]}
    end

    # The offset the input carried is kept rather than normalised away, so
    # the wall time is the one the user wrote. `DateTime.from_iso8601/1`
    # shifts to UTC and discards the offset; that loses information the
    # locale-formatted path preserves, and one function returning two
    # different structs for the same instant is the bug this avoids.
    test "ISO 8601 with zone information keeps the offset it carried" do
      assert Localize.DateTime.parse("2026-05-23T14:30:00Z", locale: :en) ==
               {:ok, ~U[2026-05-23 14:30:00Z]}

      assert {:ok, %DateTime{hour: 14, minute: 30, utc_offset: 18_000}} =
               Localize.DateTime.parse("2026-05-23T14:30:00+05:00", locale: :en)
    end

    test "the two spellings of one offset produce the same struct" do
      {:ok, iso} = Localize.DateTime.parse("2026-05-16T14:30:00+10:30", locale: :en)
      {:ok, localized} = Localize.DateTime.parse("May 16, 2026 2:30 PM GMT+10:30", locale: :en)

      assert iso == localized
    end

    test "universal fallback glue separators" do
      assert Localize.DateTime.parse("01/01/2018 14:44", locale: :en) ==
               {:ok, ~N[2018-01-01 14:44:00]}

      assert Localize.DateTime.parse("01/01/2018 - 17:06", locale: :en) ==
               {:ok, ~N[2018-01-01 17:06:00]}

      assert Localize.DateTime.parse("23-05-2019 @ 10:01", locale: :de) ==
               {:ok, ~N[2019-05-23 10:01:00]}
    end

    test "locale glue with and without the CLDR comma in :en" do
      assert Localize.DateTime.parse("May 16, 2026, 2:30 PM", locale: :en) ==
               {:ok, ~N[2026-05-16 14:30:00]}

      assert Localize.DateTime.parse("May 16, 2026 2:30 PM", locale: :en) ==
               {:ok, ~N[2026-05-16 14:30:00]}
    end

    test "non-:en locales" do
      assert Localize.DateTime.parse("16/05/2026 14:30", locale: :fr) ==
               {:ok, ~N[2026-05-16 14:30:00]}

      assert Localize.DateTime.parse("16.05.2026, 14:30", locale: :de) ==
               {:ok, ~N[2026-05-16 14:30:00]}

      assert Localize.DateTime.parse("2026/05/16 14:30", locale: :ja) ==
               {:ok, ~N[2026-05-16 14:30:00]}
    end

    test "weekday prefix and ordinal suffix strip in a datetime" do
      assert Localize.DateTime.parse("Wednesday 3rd March 2023 3:45 PM", locale: :en) ==
               {:ok, ~N[2023-03-03 15:45:00]}
    end

    # Named-zone and GMT-format suffixes are resolved by
    # `Calendrical.TimeZone`, reached optionally at runtime. Localize does
    # not depend on `calendrical`, so in this suite every one of them
    # degrades to the `NaiveDateTime` — the parse is preserved, the zone
    # is dropped. With `calendrical` present these return a `DateTime`;
    # that direction is covered by that package's own suite.
    test "zone abbreviation is dropped without a zone resolver" do
      assert Localize.DateTime.parse("May 16, 2026 2:30 PM PST", locale: :en) ==
               {:ok, ~N[2026-05-16 14:30:00]}
    end

    test "IANA zone name is dropped without a zone resolver" do
      assert Localize.DateTime.parse("May 16, 2026 2:30 PM Asia/Tokyo", locale: :en) ==
               {:ok, ~N[2026-05-16 14:30:00]}
    end

    test "unresolvable zone abbreviation falls back to a NaiveDateTime" do
      assert Localize.DateTime.parse("May 16, 2026 2:30 PM XQZV", locale: :en) ==
               {:ok, ~N[2026-05-16 14:30:00]}
    end

    # A fixed offset is arithmetic, so it resolves with no dependency.
    # The wall time the user typed is kept and the offset attached, the
    # same as the ISO 8601 path.
    test "GMT-format offset resolves to a fixed-offset DateTime" do
      assert {:ok, %DateTime{utc_offset: 37_800, hour: 14, minute: 30, zone_abbr: "+10:30"}} =
               Localize.DateTime.parse("May 16, 2026 2:30 PM GMT+10:30", locale: :en)
    end

    test "GMT-format offset accepts the short hour gmt_format/3 emits" do
      assert {:ok, %DateTime{utc_offset: -28_800, hour: 14}} =
               Localize.DateTime.parse("May 16, 2026 2:30 PM GMT-8", locale: :en)
    end

    test "bare GMT, UTC and UT resolve to a zero offset" do
      for zone <- ["GMT", "UTC", "UT"] do
        assert {:ok, %DateTime{utc_offset: 0, hour: 14, minute: 30}} =
                 Localize.DateTime.parse("May 16, 2026 2:30 PM #{zone}", locale: :en)
      end
    end

    test "ISO 8601 offset in a locale-formatted datetime resolves" do
      assert {:ok, %DateTime{utc_offset: 19_800, hour: 14, minute: 30}} =
               Localize.DateTime.parse("May 16, 2026 2:30 PM +05:30", locale: :en)
    end

    test "a named zone still degrades when a fixed offset is not present" do
      # The offset parser must not claim a zone it cannot resolve, or the
      # named-zone delegation below it would never be reached.
      assert Localize.DateTime.parse("May 16, 2026 2:30 PM America/New_York", locale: :en) ==
               {:ok, ~N[2026-05-16 14:30:00]}
    end

    test "as: :map for the ISO path" do
      assert Localize.DateTime.parse("2026-05-23T14:30:00", locale: :en, as: :map) ==
               {:ok,
                %{
                  calendar: Calendar.ISO,
                  year: 2026,
                  month: 5,
                  day: 23,
                  hour: 14,
                  minute: 30,
                  second: 0
                }}
    end

    test "as: :map surfaces microseconds and zone fields" do
      assert Localize.DateTime.parse("2026-05-23T14:30:00.5Z", locale: :en, as: :map) ==
               {:ok,
                %{
                  calendar: Calendar.ISO,
                  year: 2026,
                  month: 5,
                  day: 23,
                  hour: 14,
                  minute: 30,
                  second: 0,
                  microsecond: {500_000, 1},
                  time_zone: "Etc/UTC",
                  zone_abbr: "UTC",
                  utc_offset: 0,
                  std_offset: 0
                }}
    end

    test "as: :map for the locale-glue path" do
      assert Localize.DateTime.parse("May 16, 2026 2:30 PM", locale: :en, as: :map) ==
               {:ok,
                %{calendar: Calendar.ISO, year: 2026, month: 5, day: 16, hour: 14, minute: 30}}
    end

    test "ISO-shaped input with an invalid time falls through to an error" do
      assert {:error, %Localize.DateTimeParseError{}} =
               Localize.DateTime.parse("2026-05-16 14:30:99", locale: :en)
    end

    test "unparseable input returns a DateTimeParseError with a rendered message" do
      assert {:error, %Localize.DateTimeParseError{} = error} =
               Localize.DateTime.parse("utterly wrong", locale: :en)

      assert error.input == "utterly wrong"
      assert error.locale == :en

      assert Exception.message(error) ==
               "could not parse \"utterly wrong\" as a datetime in locale :en; " <>
                 "ISO-8601 (YYYY-MM-DDTHH:MM:SS[Z|±HH:MM]) is always accepted as a fallback"
    end
  end

  # ── Unified Localize.DateTime.Parser.parse/2 ──

  describe "Localize.DateTime.Parser.parse/2" do
    test "dispatches to the date parser" do
      assert Localize.DateTime.Parser.parse("2026-05-16", locale: :en) == {:ok, ~D[2026-05-16]}
    end

    test "dispatches to the time parser" do
      assert Localize.DateTime.Parser.parse("14:30", locale: :en) == {:ok, ~T[14:30:00]}
    end

    test "dispatches to the datetime parser" do
      assert Localize.DateTime.Parser.parse("2026-05-16T14:30:00", locale: :en) ==
               {:ok, ~N[2026-05-16 14:30:00]}

      assert Localize.DateTime.Parser.parse("May 16, 2026 2:30 PM", locale: :en) ==
               {:ok, ~N[2026-05-16 14:30:00]}
    end

    test "dispatches to the interval parser" do
      assert Localize.DateTime.Parser.parse("2026-05-05 – 2026-05-10", locale: :en) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}
    end

    test "as: :map is forwarded to the winning sub-parser" do
      assert Localize.DateTime.Parser.parse("May 5", locale: :en, as: :map) ==
               {:ok, %{calendar: Calendar.ISO, month: 5, day: 5}}

      assert Localize.DateTime.Parser.parse("11 am", locale: :en, as: :map) == {:ok, %{hour: 11}}
    end

    test "failure returns a ParseError recording every attempt" do
      assert {:error, %Localize.DateTimeParseError{} = error} =
               Localize.DateTime.Parser.parse("xyzzy", locale: :en)

      assert [
               {:date, %Localize.DateParseError{}},
               {:time, %Localize.TimeParseError{}},
               {:datetime, %Localize.DateTimeParseError{}}
             ] = error.attempts

      assert Exception.message(error) ==
               "could not parse \"xyzzy\" as a date, time, datetime, or " <>
                 "interval in locale :en"
    end

    test "interval-shaped failure records the interval attempt first" do
      assert {:error, %Localize.DateTimeParseError{} = error} =
               Localize.DateTime.Parser.parse("foo – bar", locale: :en)

      assert [
               {:interval, %Localize.DateRangeParseError{}},
               {:date, %Localize.DateParseError{}},
               {:time, %Localize.TimeParseError{}},
               {:datetime, %Localize.DateTimeParseError{}}
             ] = error.attempts
    end
  end

  # ── Calendrical.Parse via ISO-8601 calendar callbacks ──

  # ── Locale data variety ──
  #
  # These locales carry CLDR data shapes the mainstream locales do
  # not: :"en-CA" ships variant/standard pattern pairs, :nnh ships
  # patterns with unbalanced quote characters, :ee declares a
  # time-first `{0} {1}` datetime glue, :bal declares a nonstandard
  # interval fallback shape, :cy ships numeric quarter skeletons,
  # :aa has no flexible day periods, and the :buddhist calendar
  # ships standalone weekday-name (cccc) patterns.

  describe "locale data variety" do
    test "variant/standard pattern pairs in :en-CA" do
      assert Localize.Date.parse("May 5, 2026", locale: :"en-CA") == {:ok, ~D[2026-05-05]}
      assert Localize.Time.parse("2:30 PM", locale: :"en-CA") == {:ok, ~T[14:30:00]}
    end

    test "patterns with unbalanced quotes in :nnh do not crash the parsers" do
      assert {:error, %Localize.DateParseError{}} =
               Localize.Date.parse("blah blah", locale: :nnh)

      assert {:error, %Localize.TimeParseError{}} =
               Localize.Time.parse("blah", locale: :nnh)

      assert Localize.Time.parse("14:30", locale: :nnh) == {:ok, ~T[14:30:00]}
    end

    test "time-first datetime glue in :ee falls back to universal separators" do
      assert Localize.DateTime.parse("5/16/2026 14:30", locale: :ee) ==
               {:ok, ~N[2026-05-16 14:30:00]}

      assert {:error, %Localize.DateTimeParseError{}} =
               Localize.DateTime.parse("no such thing", locale: :ee)
    end

    test "nonstandard interval fallback shape in :bal still splits ranges" do
      assert Localize.Interval.parse("2026-05-05 – 2026-05-10", locale: :bal) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}

      assert Localize.DateTime.Parser.parse("2026-05-05 – 2026-05-10", locale: :bal) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}
    end

    test "numeric quarter skeleton in :cy" do
      assert Localize.Date.parse("Ch2 2026", locale: :cy) == {:ok, ~D[2026-04-01]}
      assert Localize.Date.parse("2 2026", locale: :cy) == {:ok, ~D[2026-04-01]}

      assert {:error, %Localize.DateParseError{}} =
               Localize.Date.parse("0 2026", locale: :cy)
    end

    test "day-period name without flex-period data in :aa" do
      assert Localize.Time.parse("11:30 saaku", locale: :aa) == {:ok, ~T[11:30:00]}

      assert {:error, %Localize.TimeParseError{}} =
               Localize.Time.parse("qqq", locale: :aa)
    end

    test "split fallback in :bal when interval patterns do not match" do
      assert {:error, %Localize.DateRangeParseError{reason: :from_parse_failed}} =
               Localize.Interval.parse("gibberish – 2026-05-10", locale: :bal)
    end

    test "range in :da (interval patterns with dot literals)" do
      assert Localize.Interval.parse("5.–10. maj 2026", locale: :da) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}

      assert Localize.Interval.parse("5. maj – 10. maj 2026", locale: :da) ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}
    end

    test "locale can be a string or a LanguageTag" do
      assert Localize.Date.parse("May 5, 2026", locale: "en") == {:ok, ~D[2026-05-05]}
      assert Localize.Time.parse("2:30 PM", locale: "en") == {:ok, ~T[14:30:00]}

      tag = Localize.LanguageTag.new!("en")
      assert Localize.Date.parse("May 5, 2026", locale: tag) == {:ok, ~D[2026-05-05]}
      assert Localize.Time.parse("2:30 PM", locale: tag) == {:ok, ~T[14:30:00]}
    end

    test "as: :map surfaces the zone captured through the locale glue" do
      assert Localize.DateTime.parse("May 16, 2026 2:30 PM PST", locale: :en, as: :map) ==
               {:ok,
                %{
                  calendar: Calendar.ISO,
                  year: 2026,
                  month: 5,
                  day: 16,
                  hour: 14,
                  minute: 30,
                  time_zone: "PST"
                }}
    end
  end

  # ── Default-options entry points ──

  describe "single-argument entry points" do
    test "each parser accepts input without options" do
      assert Localize.Date.Parser.parse("2026-05-16") == {:ok, ~D[2026-05-16]}

      assert Localize.Interval.parse("2026-05-05 – 2026-05-10") ==
               {:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}

      assert Localize.Time.Parser.parse("14:30:15") == {:ok, ~T[14:30:15]}
      assert Localize.Time.Parser.parse_with_zone("14:30:15") == {:ok, ~T[14:30:15], nil}

      assert Localize.DateTime.Parser.parse("2026-05-23T14:30:00") ==
               {:ok, ~N[2026-05-23 14:30:00]}

      assert Localize.DateTime.Parser.parse("2026-05-16") == {:ok, ~D[2026-05-16]}
    end
  end

  describe "regression: glue, day periods and interval determinism" do
    test "fr atTime glue separator parses" do
      assert Localize.DateTime.parse("16 mai 2026 à 14:30", locale: :fr) ==
               {:ok, ~N[2026-05-16 14:30:00]}
    end

    test "es day periods accept ASCII spaces for the shipped NBSP names" do
      assert Localize.Time.parse("3:30 a. m.", locale: :es) == {:ok, ~T[03:30:00]}
      assert Localize.Time.parse("3:30 p. m.", locale: :es) == {:ok, ~T[15:30:00]}
    end

    test "locale day-period names resolve AM/PM" do
      assert Localize.Time.parse("午後2:30", locale: :ja) == {:ok, ~T[14:30:00]}
      assert Localize.Time.parse("午前2:30", locale: :ja) == {:ok, ~T[02:30:00]}
    end

    test "map-mode ranges prefer day-bearing interval patterns deterministically" do
      assert Localize.Interval.parse("May 5 – May 10", locale: :en, as: :map) ==
               {:ok,
                {%{calendar: Calendar.ISO, month: 5, day: 5},
                 %{calendar: Calendar.ISO, month: 5, day: 10}}}
    end
  end
end
