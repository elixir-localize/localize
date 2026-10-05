defmodule Localize.ParsingCoverageTest do
  use ExUnit.Case, async: true

  # A calendar sharing its CLDR type with another, as `Calendrical.Gregorian`
  # does with `Calendar.ISO`: every `Calendar` callback is `Calendar.ISO`'s.
  defmodule GregorianLike do
    @moduledoc false
    use Localize.Test.StandInCalendar
    @behaviour Calendar

    def cldr_calendar_type, do: :gregorian
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month

    for {name, arity} <- Calendar.behaviour_info(:callbacks) do
      args = Macro.generate_arguments(arity, __MODULE__)

      def unquote(name)(unquote_splicing(args)),
        do: Calendar.ISO.unquote(name)(unquote_splicing(args))
    end
  end

  doctest Localize.DateTime.ParseOptions
  doctest Localize.DateTime.Week

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

    # 23 May is the 143rd day of 2026, which has 365.
    test "basic ordinal date (YYYYDDD) in :ja" do
      assert Date.day_of_year(~D[2026-05-23]) == 143
      assert Localize.Date.parse("2026143", locale: :ja) == {:ok, ~D[2026-05-23]}

      for text <- ["2026366", "2026000"] do
        assert {:error, %Localize.DateParseError{}} = Localize.Date.parse(text, locale: :ja)
      end
    end

    # A year and a month, or a year, at reduced precision is no date: it is
    # the fields it holds, alike in every locale, where a locale's patterns
    # read one or the other. `YYYYMM` is no ISO 8601 form.
    test "a year and a month, and a year (YYYY-MM and YYYY)" do
      for locale <- [:en, :de, :ja] do
        assert Localize.Date.parse("2026-03", locale: locale, as: :map) ==
                 {:ok, %{calendar: Calendar.ISO, year: 2026, month: 3}},
               inspect(locale)

        assert Localize.Date.parse("2026", locale: locale, as: :map) ==
                 {:ok, %{calendar: Calendar.ISO, year: 2026}},
               inspect(locale)

        assert {:error, %Localize.DateParseError{}} =
                 Localize.Date.parse("2026-03", locale: locale)

        for text <- ["2026-13", "2026-00", "202603"] do
          assert {:error, %Localize.DateParseError{}} =
                   Localize.Date.parse(text, locale: locale, as: :map),
                 inspect({locale, text})
        end
      end
    end

    # A year is the whole of the text as it was given. `es` abbreviates both
    # March and Tuesday "mar", and "mar 2024" with the weekday stripped is
    # "2024": it is `yMMM`'s March 2024, "MMM y", not the year alone.
    test "a year is not read from text with a leading weekday stripped" do
      assert Localize.Date.parse("mar 2024", locale: :es, as: :map) ==
               {:ok, %{calendar: Calendar.ISO, year: 2024, month: 3}}
    end

    test "ISO week date (YYYY-Www-D) in :ja" do
      assert Localize.Date.parse("2026-W21-6", locale: :ja) == {:ok, ~D[2026-05-23]}
    end

    test "basic ISO week date (YYYYWwwD) in :ja" do
      assert Localize.Date.parse("2026W216", locale: :ja) == {:ok, ~D[2026-05-23]}
    end

    # ISO 8601's week at reduced precision names no day. As a date it is the
    # week's Monday, in ISO 8601's weeks whatever the locale's: `en`'s begin
    # on Sunday, so its "week 25 of 2026" begins on 14 June. As a map it is
    # the week-based year and the week. `:calendar.iso_week_number/1` puts
    # 15 June 2026 in week 25 and 28 December 2026 in week 53, which 2025
    # does not have.
    test "week without a day (YYYY-Www and YYYYWww)" do
      assert :calendar.iso_week_number({2026, 6, 15}) == {2026, 25}
      assert :calendar.iso_week_number({2026, 12, 28}) == {2026, 53}

      for locale <- [:en, :ja, :de], text <- ["2026-W25", "2026W25"] do
        assert Localize.Date.parse(text, locale: locale) == {:ok, ~D[2026-06-15]},
               inspect({locale, text})
      end

      assert Localize.Date.parse("week 25 of 2026", locale: :en) == {:ok, ~D[2026-06-14]}
      assert Localize.Date.parse("2026-W53", locale: :en) == {:ok, ~D[2026-12-28]}

      assert Localize.Date.parse("2026-W25", locale: :en, as: :map) ==
               {:ok,
                %{calendar: Calendar.ISO, year: 2026, week_based_year: 2026, week_of_year: 25}}

      for text <- ["2025-W53", "2026-W54", "2026-W00", "2026-W2", "2026W25-2", "2026-W252"] do
        assert {:error, %Localize.DateParseError{}} = Localize.Date.parse(text, locale: :en),
               text
      end
    end

    # In a calendar whose weeks are not its fields the week is its first
    # day, whole, as every other ISO 8601 date is converted.
    test "week without a day in another calendar" do
      monday = Date.new!(2026, 6, 15, GregorianLike)

      assert Localize.Date.parse("2026-W25", locale: :en, calendar: GregorianLike) ==
               {:ok, monday}

      assert Localize.Date.parse("2026-W25", locale: :en, calendar: GregorianLike, as: :map) ==
               {:ok, %{calendar: GregorianLike, year: 2026, month: 6, day: 15}}
    end

    test "weeks without days as an interval and as text of unknown shape" do
      assert Localize.Interval.parse("2026-W25 – 2026-W27", locale: :en) ==
               {:ok, Date.range(~D[2026-06-15], ~D[2026-06-29])}

      assert Localize.DateTime.Parser.parse("2026-W25", locale: :en) == {:ok, ~D[2026-06-15]}
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

      # Calendar.ISO's weeks are the locale's: en's begin on Sunday and its
      # week 1 holds 1 January, so week 20 of 2026 begins on Sunday 10 May,
      # as ICU4C 78.3 reads it.
      assert Localize.Date.parse("week 20 of 2026", locale: :en) == {:ok, ~D[2026-05-10]}
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
    test "the default calendar is Calendar.ISO" do
      assert Localize.Date.parse("2026-05-16", locale: :en) == {:ok, ~D[2026-05-16]}

      assert Localize.Date.parse("2026-05-16", locale: :en, calendar: Calendar.ISO) ==
               {:ok, ~D[2026-05-16]}
    end

    test "a CLDR calendar type is not a calendar" do
      for calendar <- [:gregorian, :hebrew, :chinese, :buddhist, :coptic, :islamic, :persian] do
        assert {:error, %Localize.UnknownCalendarError{calendar: ^calendar}} =
                 Localize.Date.parse("2026-05-16", locale: :en, calendar: calendar)
      end
    end

    test "the date is built and returned in the calendar module given" do
      assert {:ok, %Date{calendar: GregorianLike, year: 2026, month: 5, day: 16}} =
               Localize.Date.parse("16.05.2026", locale: :de, calendar: GregorianLike)

      assert {:ok, %Date{calendar: GregorianLike, year: 2026, month: 5, day: 16}} =
               Localize.Date.parse("2026-05-16", locale: :en, calendar: GregorianLike)

      assert {:ok, %{calendar: GregorianLike, year: 2026, month: 5, day: 16}} =
               Localize.Date.parse("16.05.2026", locale: :de, calendar: GregorianLike, as: :map)

      assert {:ok, %Date.Range{first: %Date{calendar: GregorianLike}}} =
               Localize.Interval.parse("May 5 – 10, 2026", locale: :en, calendar: GregorianLike)
    end

    # Both input shapes must agree. The ISO path used to skip calendar
    # resolution entirely and return a Gregorian date, so asking for a
    # calendar it could not honour succeeded with the wrong answer.
    test "ISO and locale-formatted input agree about an unavailable calendar" do
      iso = Localize.Date.parse("2026-05-16", locale: :de, calendar: Calendrical.Hebrew)
      locale = Localize.Date.parse("16.05.2026", locale: :de, calendar: Calendrical.Hebrew)

      assert {:error, %Localize.UnknownCalendarError{}} = iso
      assert iso == locale
    end

    test "an unknown calendar is rejected rather than quietly ignored" do
      for calendar <- [:bogus, NoSuchCalendarModule, nil, "hebrew"] do
        assert {:error, %Localize.UnknownCalendarError{}} =
                 Localize.Date.parse("2026-05-16", locale: :en, calendar: calendar)
      end
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
      assert error.calendar == Calendar.ISO

      assert Exception.message(error) ==
               "could not parse \"not a date\" as a date in locale :en " <>
                 "(calendar Calendar.ISO); ISO-8601 (YYYY-MM-DD) is always accepted as a fallback"
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

    # Which date is the earlier is the calendar's to say, by its days, and
    # not read from the dates' fields. In a calendar whose year turns on 25
    # March, 1 January 2024 is the day after 31 December 2024 (ISO 1 January
    # 2025 and 31 December 2024), so December to January ascends and January
    # to December is the inverted range.
    test "a range is inverted by its days, not by its dates' fields" do
      calendar = Localize.Test.LadyDayCalendar
      december = Date.new!(2024, 12, 31, calendar)
      january = Date.new!(2024, 1, 1, calendar)

      assert Date.diff(january, december) == 1

      assert Localize.Interval.parse("12/31/2024 – 1/1/2024", locale: :en, calendar: calendar) ==
               {:ok, Date.range(december, january)}

      assert {:error, %Localize.DateRangeParseError{reason: :inverted}} =
               Localize.Interval.parse("1/1/2024 – 12/31/2024", locale: :en, calendar: calendar)

      assert Localize.Interval.parse("1/1/2024 – 12/31/2024",
               locale: :en,
               calendar: calendar,
               allow_inverted: true
             ) == {:ok, Date.range(january, december, -1)}
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

    # Without a date a named zone has no offset, so the map carries the zone
    # the name stands for: ICU4C reads "PST" as America/Los_Angeles.
    test "as: :map surfaces a captured zone" do
      assert Localize.Time.parse("11:30 PST", locale: :en, as: :map) ==
               {:ok, %{hour: 11, minute: 30, time_zone: "America/Los_Angeles"}}
    end

    test "as: :map resolves a captured fixed offset without a date" do
      assert Localize.Time.parse("2:30 PM GMT+5", locale: :en, as: :map) ==
               {:ok,
                %{
                  hour: 14,
                  minute: 30,
                  time_zone: "Etc/UTC",
                  utc_offset: 18_000,
                  std_offset: 0,
                  zone_abbr: "+05:00"
                }}
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

    # An offset's hour is TR35's `H`, 0 to 23, and its minutes and seconds
    # 0 to 59. Fifteen hours is in range: Juneau kept +15:02:19 until 1867.
    # ICU4C 78.3 reads and refuses the same strings.
    test "offsets out of range are rejected" do
      for zone <- ["+24:00", "+05:75", "+05:00:61"] do
        assert {:error, %Localize.UnknownTimezoneError{}} =
                 Localize.DateTime.Timezone.parse_offset(zone)
      end

      assert Localize.DateTime.Timezone.parse_offset("+15:00") == {:ok, 54_000}
      assert Localize.DateTime.Timezone.parse_offset("+23:59") == {:ok, 86_340}
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

    # TR35's parsing: "the absence of a numeric offset should be interpreted
    # as offset 0, whether in localized or global formats", its "HPG" being
    # `Etc/GMT`. CLDR 49's `gmtFormat` for `yo` is "WAT{0}", so "WAT" is GMT
    # there, as ICU4C 78.3 reads it, whatever the letters stand for
    # elsewhere; `yo` has no zone named so. It is no zone in another locale.
    test "a localized literal alone is GMT in its locale" do
      assert Localize.DateTime.Timezone.parse_offset("WAT", locale: :yo) == {:ok, 0}
      assert Localize.DateTime.Timezone.parse_offset("WAT+01:00", locale: :yo) == {:ok, 3600}

      assert {:error, %Localize.UnknownTimezoneError{}} =
               Localize.DateTime.Timezone.parse_offset("WAT", locale: :en)
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

    # A named zone resolves through the time zone database this suite
    # configures. The instants are ICU4C 78.3's readings: "PST" keeps
    # standard time's -08:00 in May, when Los Angeles keeps daylight time,
    # so it is a fixed offset rather than the zone's own `DateTime`.
    test "a zone abbreviation resolves, keeping its own offset" do
      assert {:ok, %DateTime{hour: 14, minute: 30, utc_offset: -28_800, std_offset: 0} = datetime} =
               Localize.DateTime.parse("May 16, 2026 2:30 PM PST", locale: :en)

      assert DateTime.compare(datetime, ~U[2026-05-16 22:30:00Z]) == :eq
    end

    test "an IANA zone name resolves" do
      assert {:ok, %DateTime{time_zone: "Asia/Tokyo", hour: 14, minute: 30} = datetime} =
               Localize.DateTime.parse("May 16, 2026 2:30 PM Asia/Tokyo", locale: :en)

      assert DateTime.compare(datetime, ~U[2026-05-16 05:30:00Z]) == :eq
    end

    # A zone field reads only a zone, as ICU4C's does.
    test "text that is no zone is not read as one" do
      assert {:error, %Localize.DateTimeParseError{}} =
               Localize.DateTime.parse("May 16, 2026 2:30 PM XQZV", locale: :en)
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

    test "a zone ID is read as its zone, not as an offset" do
      # The offset parser must not claim a zone ID, or the zone would lose
      # its daylight time: New York keeps it in May.
      assert {:ok,
              %DateTime{
                time_zone: "America/New_York",
                zone_abbr: "EDT",
                utc_offset: -18_000,
                std_offset: 3600,
                hour: 14
              }} =
               Localize.DateTime.parse("May 16, 2026 2:30 PM America/New_York", locale: :en)
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

    # `aa` names no flexible day periods, so its `B` patterns are written
    # with its AM and PM names (TR35) and read with them; a word it does not
    # name is no day period.
    test "day-period name without flex-period data in :aa" do
      assert Localize.Time.to_string(~T[23:30:00], locale: :aa, format: :Bhm) ==
               {:ok, "11:30 PM"}

      assert Localize.Time.parse("11:30 PM", locale: :aa) == {:ok, ~T[23:30:00]}
      assert Localize.Time.parse("11:30 AM", locale: :aa) == {:ok, ~T[11:30:00]}

      assert {:error, %Localize.TimeParseError{}} =
               Localize.Time.parse("11:30 saaku", locale: :aa)

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

    test "as: :map resolves a fixed offset captured through the locale glue, as the struct does" do
      input = "May 23, 2026, 2:30 PM GMT-3:30"
      zone_fields = [:time_zone, :utc_offset, :std_offset, :zone_abbr]

      assert {:ok, map} = Localize.DateTime.parse(input, locale: :en, as: :map)
      assert {:ok, %DateTime{} = datetime} = Localize.DateTime.parse(input, locale: :en)
      assert Map.take(map, zone_fields) == Map.take(datetime, zone_fields)
      assert map.utc_offset == -12_600
    end

    test "as: :map resolves a fixed offset when the date is partial" do
      assert {:ok, map} = Localize.DateTime.parse("May 5, 2:30 PM GMT+5", locale: :en, as: :map)
      assert %{month: 5, day: 5, time_zone: "Etc/UTC", utc_offset: 18_000} = map
      refute Map.has_key?(map, :year)
    end

    # The date is complete, so "PST" resolves as the struct form's does: to
    # its own -08:00 in May.
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
                  time_zone: "Etc/UTC",
                  utc_offset: -28_800,
                  std_offset: 0,
                  zone_abbr: "-08:00"
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

  # ── Invalid input and options return errors, never raise ──

  describe "invalid input and options" do
    @entry_points [
      {&Localize.Date.parse/2, "May 23, 2026"},
      {&Localize.Date.parse/2, "2026-05-23"},
      {&Localize.Time.parse/2, "10:30 PM"},
      {&Localize.Time.parse/2, "10:30:00"},
      {&Localize.DateTime.parse/2, "May 23, 2026, 10:30 PM"},
      {&Localize.DateTime.parse/2, "2026-05-23T10:30:00"},
      {&Localize.DateTime.Parser.parse/2, "May 23, 2026"},
      {&Localize.Interval.parse/2, "May 5 – 10, 2026"}
    ]

    test "a non-string input is an invalid value error" do
      for {parse, _input} <- @entry_points, bad_input <- [nil, 123, :"", ~D[2026-05-23]] do
        assert {:error, %Localize.InvalidValueError{value: ^bad_input}} = parse.(bad_input, [])
      end
    end

    test "options that are not a keyword list are an invalid value error" do
      for {parse, input} <- @entry_points, bad_options <- [:bogus, [:not_keyword], %{as: :map}] do
        assert {:error, %Localize.InvalidValueError{value: ^bad_options}} =
                 parse.(input, bad_options)
      end
    end

    test "an :as other than :struct or :map is an invalid value error" do
      for {parse, input} <- @entry_points, as <- [:bogus, nil, "map"] do
        assert {:error, %Localize.InvalidValueError{value: ^as, allowed_values: [:struct, :map]}} =
                 parse.(input, as: as)
      end
    end

    test "a :reference_date that is not a date is an invalid value error" do
      for {parse, input} <- @entry_points, reference_date <- ["2026-01-01", 5] do
        assert {:error, %Localize.InvalidValueError{value: ^reference_date}} =
                 parse.(input, reference_date: reference_date)
      end
    end

    test "an invalid locale or calendar returns a result rather than raising" do
      for {parse, input} <- @entry_points,
          option <- [
            locale: 123,
            locale: "",
            locale: :"",
            locale: "xx-invalid-!!",
            calendar: "gregorian",
            calendar: 123
          ] do
        case parse.(input, [option]) do
          {:ok, _value} -> :ok
          {:error, exception} -> assert is_exception(exception)
        end
      end
    end

    test "a range with an invalid locale reports the locale error" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Localize.Interval.parse("May 5 – 10, 2026", locale: 123)
    end

    test "a range tuple with a non-string endpoint is an invalid value error" do
      assert {:error, %Localize.InvalidValueError{value: nil}} =
               Localize.Interval.parse({nil, "2026-05-10"})

      assert {:error, %Localize.InvalidValueError{value: 5}} =
               Localize.Interval.parse({"2026-05-05", 5})
    end
  end

  # ── Week-of-year text is the locale's weeks for Calendar.ISO ──

  describe "week-of-year parsing" do
    # Calendar.ISO has no weeks of its own, so its week text is the locale's
    # weeks, and a date's week text reads back as the first day of its week:
    # Sunday in en, pt-BR and ja, Saturday in ar-EG and fa, Monday in en-GB
    # and de, and the day a `-u-fw-` key, a `-u-rg-` region or the
    # `iso8601` calendar gives (CLDR's weekData and TR35's first day
    # algorithm, as ICU4C 78.3 gives each locale's first day).
    test "the week text of every day around a year boundary round trips" do
      for {locale, first_day} <- [
            {"en", 7},
            {"pt-BR", 7},
            {"ja", 7},
            {"ar-EG", 6},
            {"fa", 6},
            {"en-GB", 1},
            {"de", 1},
            {"en-u-fw-mon", 1},
            {"en-u-fw-wed", 3},
            {"en-u-rg-gbzzzz", 1},
            {"en-u-ca-iso8601", 1}
          ],
          date <- Date.range(~D[2026-12-20], ~D[2027-01-10]) do
        {:ok, week_text} = Localize.Date.to_string(date, locale: locale, format: :yw)

        assert {:ok, parsed} = Localize.Date.parse(week_text, locale: locale)
        assert Localize.Date.to_string(parsed, locale: locale, format: :yw) == {:ok, week_text}
        assert Date.day_of_week(parsed) == first_day
        assert Date.diff(date, parsed) in 0..6
      end
    end

    # 2027 begins on a Friday. In en its week holds 1 January, so it is week
    # 1 and begins on Sunday 27 December 2026; in en-GB, whose weeks are ISO
    # 8601's, week 1 begins on Monday 4 January (ICU4C 78.3 reads both so).
    test "week 1 of 2027 starts on the locale's first day" do
      assert Localize.Date.parse("week 1 of 2027", locale: :en) == {:ok, ~D[2026-12-27]}
      assert Localize.Date.parse("week 1 of 2027", locale: :"en-GB") == {:ok, ~D[2027-01-04]}
      assert :calendar.iso_week_number({2027, 1, 4}) == {2027, 1}
    end

    test "week 53 of 2026 in de starts on Monday 28 December 2026" do
      assert Localize.Date.parse("Woche 53 des Jahres 2026", locale: :de) ==
               {:ok, ~D[2026-12-28]}
    end
  end

  # ── Non-Latin digits ──

  describe "dates written in non-Latin digits" do
    test "each locale's short and medium dates round trip" do
      for locale <- [:"ar-EG", :fa, :bn, :"hi-IN-u-nu-deva", :"th-TH-u-nu-thai", :my, :mr],
          format <- [:short, :medium] do
        {:ok, formatted} = Localize.Date.to_string(~D[2026-05-23], locale: locale, format: format)

        assert Localize.Date.parse(formatted, locale: locale) == {:ok, ~D[2026-05-23]},
               "#{locale} #{format}: #{inspect(formatted)}"
      end
    end
  end

  # ── Remaining date and time shapes ──

  describe "further date shapes" do
    test "ISO input returned as a map carries the calendar" do
      assert Localize.Date.parse("2026-05-23", as: :map) ==
               {:ok, %{calendar: Calendar.ISO, year: 2026, month: 5, day: 23}}
    end

    test "a calendar module is accepted as the :calendar option" do
      assert Localize.Date.parse("23.05.2026", locale: :de, calendar: Calendar.ISO) ==
               {:ok, ~D[2026-05-23]}
    end

    test "a calendar module that is not installed is rejected" do
      assert {:error, %Localize.UnknownCalendarError{calendar: Calendrical.Japanese}} =
               Localize.Date.parse("令和8年5月23日", locale: :ja, calendar: Calendrical.Japanese)
    end
  end

  describe "further time shapes" do
    test "a fractional second written with a decimal comma in fr" do
      assert Localize.Time.parse("10:30:15,5", locale: :fr) == {:ok, ~T[10:30:15.5]}
    end

    test "a flexible day period in en" do
      assert Localize.Time.parse("10:30 at night", locale: :en) == {:ok, ~T[22:30:00]}
    end
  end
end
