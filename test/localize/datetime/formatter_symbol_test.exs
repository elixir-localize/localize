defmodule Localize.DateTime.FormatterSymbolTest do
  use ExUnit.Case, async: true

  # Exercises every CLDR format symbol handler in
  # Localize.DateTime.Formatter across its width variants,
  # through the public Localize.Date / Localize.Time /
  # Localize.DateTime formatting API.

  @date ~D[2024-07-06]
  @january ~D[2024-01-15]
  @time ~T[14:30:45.123456]
  @midnight ~T[00:00:00]
  @noon ~T[12:00:00]
  @last_minute ~T[23:59:59]

  defp date_format(date, format, locale \\ :en) do
    {:ok, result} = Localize.Date.to_string(date, format: format, locale: locale)
    result
  end

  defp time_format(time, format, locale \\ :en) do
    {:ok, result} = Localize.Time.to_string(time, format: format, locale: locale)
    result
  end

  describe "era (G)" do
    test "abbreviated, wide and narrow widths for AD dates" do
      assert date_format(@date, "G") == "AD"
      assert date_format(@date, "GG") == "AD"
      assert date_format(@date, "GGG") == "AD"
      assert date_format(@date, "GGGG") == "Anno Domini"
      assert date_format(@date, "GGGGG") == "A"
    end

    test "abbreviated, wide and narrow widths for BC dates" do
      bc_date = %Date{year: -100, month: 3, day: 15, calendar: Calendar.ISO}

      assert date_format(bc_date, "G") == "BC"
      assert date_format(bc_date, "GGGG") == "Before Christ"
      assert date_format(bc_date, "GGGGG") == "B"
    end

    test "era: :variant option selects the CE/BCE form" do
      assert {:ok, "Common Era"} =
               Localize.Date.to_string(@date, format: "GGGG", era: :variant, locale: :en)
    end
  end

  describe "year (y, Y, u, U, r)" do
    test "y widths pad and truncate the calendar year" do
      assert date_format(@date, "y") == "2024"
      assert date_format(@date, "yy") == "24"
      assert date_format(@date, "yyy") == "2024"
      assert date_format(@date, "yyyyy") == "02024"
    end

    test "yy renders the era-relative year modulo 100 for BC dates" do
      bc_date = %Date{year: -100, month: 3, day: 15, calendar: Calendar.ISO}

      assert date_format(bc_date, "y") == "101"
      assert date_format(bc_date, "yy") == "01"
    end

    test "Y widths render the week-aligned year" do
      assert date_format(@date, "Y") == "2024"
      assert date_format(@date, "YYYY") == "2024"
      assert date_format(@date, "YYYYY") == "02024"
    end

    test "YY renders the week-aligned year modulo 100, honouring week rollover" do
      # 2024-12-31 belongs to week 1 of week-aligned year 2025 in en.
      assert date_format(~D[2024-12-31], "YY") == "25"
    end

    test "u renders the extended (signed proleptic) year" do
      bc_date = %Date{year: -100, month: 3, day: 15, calendar: Calendar.ISO}

      assert date_format(@date, "u") == "2024"
      assert date_format(bc_date, "u") == "-100"
      assert date_format(bc_date, "uuuu") == "-0100"
    end

    test "U (cyclic year) and r (related year) fall back to the calendar year" do
      assert date_format(@date, "U") == "2024"
      assert date_format(@date, "UU") == "2024"
      assert date_format(@date, "r") == "2024"
      assert date_format(@date, "rr") == "2024"
    end
  end

  describe "quarter (Q, q)" do
    test "format quarter widths" do
      assert date_format(@date, "Q") == "3"
      assert date_format(@date, "QQ") == "03"
      assert date_format(@date, "QQQ") == "Q3"
      assert date_format(@date, "QQQQ") == "3rd quarter"
      assert date_format(@date, "QQQQQ") == "3"
    end

    test "standalone quarter widths" do
      assert date_format(@date, "q") == "3"
      assert date_format(@date, "qq") == "03"
      assert date_format(@date, "qqq") == "Q3"
      assert date_format(@date, "qqqq") == "3rd quarter"
      assert date_format(@date, "qqqqq") == "3"
    end

    test "localized wide quarter" do
      assert date_format(@january, "QQQQ", :de) == "1. Quartal"
    end

    test "Q selects format context and q selects stand-alone context" do
      # :blo is one of the few locales whose wide quarter names differ
      # between the format and stand-alone contexts, so it detects a
      # swapped Q/q mapping that :en (identical names) cannot.
      # "ɩŋɔrɩriu ɩriutaja" (format) versus "ɩŋɔrɩriu 3ja" (stand-alone).
      assert date_format(@date, "QQQQ", :blo) == "ɩŋɔrɩriu ɩriutaja"
      assert date_format(@date, "qqqq", :blo) == "ɩŋɔrɩriu 3ja"
    end
  end

  describe "month (M, L)" do
    test "format month widths" do
      assert date_format(@date, "M") == "7"
      assert date_format(@date, "MM") == "07"
      assert date_format(@date, "MMM") == "Jul"
      assert date_format(@date, "MMMM") == "July"
      assert date_format(@date, "MMMMM") == "J"
    end

    test "standalone month widths" do
      assert date_format(@date, "L") == "7"
      assert date_format(@date, "LL") == "07"
      assert date_format(@date, "LLL") == "Jul"
      assert date_format(@date, "LLLL") == "July"
      assert date_format(@date, "LLLLL") == "J"
    end

    test "standalone month differs from format month in Russian" do
      # Russian declines format-context months (genitive) but keeps
      # standalone months in the nominative case.
      assert date_format(@january, "MMMM", :ru) == "января"
      assert date_format(@january, "LLLL", :ru) == "январь"
    end
  end

  describe "week (w, W)" do
    test "week of year widths" do
      assert date_format(@date, "w") == "27"
      assert date_format(@date, "ww") == "27"
      assert date_format(@january, "ww") == "03"
    end

    test "week of month" do
      assert date_format(@date, "W") == "1"
      assert date_format(~D[2024-07-31], "W") == "5"
    end
  end

  describe "day (d, D, F)" do
    test "day of month widths" do
      assert date_format(@date, "d") == "6"
      assert date_format(@date, "dd") == "06"
    end

    test "day of year widths" do
      assert date_format(@date, "D") == "188"
      assert date_format(@date, "DDD") == "188"
      assert date_format(~D[2024-01-05], "D") == "5"
      assert date_format(~D[2024-01-05], "DDD") == "005"
    end

    test "day of year accounts for leap years" do
      assert date_format(~D[2024-03-01], "D") == "61"
      assert date_format(~D[2023-03-01], "D") == "60"
    end

    test "day of week in month" do
      assert date_format(@date, "F") == "1"
      assert date_format(~D[2024-07-31], "F") == "5"
    end
  end

  describe "weekday (E, e, c)" do
    test "day name widths" do
      assert date_format(@date, "E") == "Sat"
      assert date_format(@date, "EE") == "Sat"
      assert date_format(@date, "EEE") == "Sat"
      assert date_format(@date, "EEEE") == "Saturday"
      assert date_format(@date, "EEEEE") == "S"
      assert date_format(@date, "EEEEEE") == "Sa"
    end

    test "day of week number and name widths" do
      assert date_format(@date, "e") == "6"
      assert date_format(@date, "ee") == "06"
      assert date_format(@date, "eee") == "Sat"
      assert date_format(@date, "eeee") == "Saturday"
      assert date_format(@date, "eeeee") == "S"
      assert date_format(@date, "eeeeee") == "Sa"
    end

    test "standalone day of week widths" do
      assert date_format(@date, "c") == "6"
      assert date_format(@date, "cc") == "06"
      assert date_format(@date, "ccc") == "Sat"
      assert date_format(@date, "cccc") == "Saturday"
      assert date_format(@date, "ccccc") == "S"
      assert date_format(@date, "cccccc") == "Sa"
    end

    test "localized weekday names" do
      assert date_format(@january, "EEEE", :fr) == "lundi"
      assert date_format(@january, "cccc", :ru) == "понедельник"
    end
  end

  describe "period (a, b, B)" do
    test "AM/PM widths" do
      assert time_format(@time, "a") == "PM"
      assert time_format(@time, "aaaa") == "PM"
      assert time_format(@time, "aaaaa") == "p"
      assert time_format(@midnight, "a") == "AM"
      assert time_format(@midnight, "aaaaa") == "a"
    end

    test "single-letter b selects noon and midnight at exact points" do
      assert time_format(@noon, "b") == "noon"
      assert time_format(@midnight, "b") == "midnight"
    end

    test "narrow b width" do
      assert time_format(@noon, "bbbbb") == "n"
    end

    test "single-letter B selects a flexible day period" do
      assert time_format(~T[15:00:00], "B") == "in the afternoon"
    end
  end

  describe "hour (h, K, H, k) at edge times" do
    test "afternoon time across all hour cycles" do
      assert time_format(@time, "h") == "2"
      assert time_format(@time, "hh") == "02"
      assert time_format(@time, "K") == "2"
      assert time_format(@time, "KK") == "02"
      assert time_format(@time, "H") == "14"
      assert time_format(@time, "HH") == "14"
      assert time_format(@time, "k") == "14"
      assert time_format(@time, "kk") == "14"
    end

    # `k` stays 1-24 and midnight stays 24. CLDR 49 was expected to deprecate
    # the H24 cycle in favour of H23, but it did not: TR35 still defines `k`
    # as "Hour [1-24]" and `hc=h24` as "Hour system using 1–24", and
    # `bcp47/calendar.xml` carries `h24` with no `deprecated` attribute —
    # which that file does use elsewhere. Do not "fix" this to 0.
    test "midnight renders 12/0/0/24 across the four cycles" do
      assert time_format(@midnight, "h") == "12"
      assert time_format(@midnight, "K") == "0"
      assert time_format(@midnight, "KK") == "00"
      assert time_format(@midnight, "H") == "0"
      assert time_format(@midnight, "HH") == "00"
      assert time_format(@midnight, "k") == "24"
      assert time_format(@midnight, "kk") == "24"
    end

    test "noon renders 12/0/12/12 across the four cycles" do
      assert time_format(@noon, "h") == "12"
      assert time_format(@noon, "K") == "0"
      assert time_format(@noon, "H") == "12"
      assert time_format(@noon, "k") == "12"
    end

    test "23:59 renders 11/11/23/23 across the four cycles" do
      assert time_format(@last_minute, "h") == "11"
      assert time_format(@last_minute, "K") == "11"
      assert time_format(@last_minute, "H") == "23"
      assert time_format(@last_minute, "k") == "23"
    end
  end

  describe "minute (m) and second (s)" do
    test "minute widths" do
      assert time_format(@time, "m") == "30"
      assert time_format(@midnight, "m") == "0"
      assert time_format(@midnight, "mm") == "00"
    end

    test "second widths" do
      assert time_format(@time, "s") == "45"
      assert time_format(@midnight, "s") == "0"
      assert time_format(@midnight, "ss") == "00"
    end
  end

  describe "fractional second (S) and millisecond (A)" do
    test "S truncates the fraction to the requested digit count" do
      assert time_format(@time, "S") == "1"
      assert time_format(@time, "SS") == "12"
      assert time_format(@time, "SSS") == "123"
      assert time_format(@time, "SSSS") == "1234"
      assert time_format(@time, "SSSSSS") == "123456"
    end

    test "S is capped at the value's precision" do
      assert time_format(~N[2024-07-06 14:30:45.9], "ss.SSS") == "45.9"
    end

    test "seconds followed by S get an implicit decimal separator" do
      assert time_format(@time, "ssSSS") == "45.123"
    end

    test "explicit literal separator between s and S is preserved" do
      assert time_format(@time, "ss.SSS") == "45.123"
    end

    test "A renders milliseconds of the day" do
      assert time_format(@time, "A") == "52245123"
      assert time_format(@midnight, "AAA") == "000"
    end
  end

  describe "literals and quoting" do
    test "quoted literal text passes through unchanged" do
      assert time_format(@time, "'at' HH:mm") == "at 14:30"
    end

    test "empty format string produces empty output" do
      assert time_format(@time, "") == ""
    end

    test "doubled quote inside quoted text renders a literal apostrophe" do
      assert time_format(~T[14:00:00], "h 'o''clock'") == "2 o'clock"
    end

    test "standalone doubled quote renders a literal apostrophe" do
      assert time_format(~T[14:00:00], "h''") == "2'"
      assert time_format(~T[14:00:00], "h '' m") == "2 ' 0"
    end

    test "quoted text containing only doubled quotes renders apostrophes" do
      assert time_format(~T[14:00:00], "h ''''") == "2 '"
    end
  end

  describe "lenient formatting of missing fields" do
    test "time symbols render empty against a Date" do
      assert date_format(@date, "H:mm") == ":"
    end

    test "date symbols render empty against a Time" do
      assert time_format(@time, "y G Q M d E w a") == "       PM"
    end

    test "all zone symbols render empty for a zoneless NaiveDateTime" do
      # A zoneless input must not fabricate a UTC zone. Every zone
      # symbol renders "" (with the bounding whitespace stripped),
      # matching the lenient behaviour `z` already had.
      for symbol <- ~w(z zzzz Z ZZZZ ZZZZZ O OOOO v vvvv V VV VVVV x xxx X XXX) do
        assert {:ok, "14:00"} =
                 Localize.DateTime.to_string(~N[2024-07-06 14:00:00],
                   format: "HH:mm #{symbol}",
                   locale: :en
                 ),
               "expected zone symbol #{symbol} to render empty for a NaiveDateTime"
      end
    end

    test "all zone symbols render empty for a zoneless Time" do
      for symbol <- ~w(z Z O v V x X) do
        assert {:ok, "14:00"} =
                 Localize.Time.to_string(~T[14:00:00],
                   format: "HH:mm #{symbol}",
                   locale: :en
                 ),
               "expected zone symbol #{symbol} to render empty for a Time"
      end
    end

    test "zone symbols still render for a DateTime with a zone" do
      {:ok, datetime} = DateTime.from_naive(~N[2024-07-06 14:00:00], "Etc/UTC")

      assert {:ok, "14:00 +0000"} =
               Localize.DateTime.to_string(datetime, format: "HH:mm Z", locale: :en)

      assert {:ok, "14:00 Z"} =
               Localize.DateTime.to_string(datetime, format: "HH:mm X", locale: :en)

      assert {:ok, "14:00 Etc/UTC"} =
               Localize.DateTime.to_string(datetime, format: "HH:mm VV", locale: :en)
    end
  end

  describe "error paths" do
    test "unknown symbol returns a tokenize error" do
      assert {:error, %Localize.DateTimeFormatError{reason: :tokenize_error}} =
               Localize.Time.to_string(@time, format: "hh:mm garbage", locale: :en)
    end

    test "unresolvable date_format inside a {1} placeholder returns an error" do
      assert {:error, %Localize.DateTimeUnresolvedFormatError{format: :bogus}} =
               Localize.DateTime.to_string(~N[2024-07-06 14:30:45],
                 format: "{1}",
                 date_format: :bogus,
                 locale: :en
               )
    end

    test "unresolvable time_format inside a {0} placeholder returns an error" do
      assert {:error, %Localize.DateTimeUnresolvedFormatError{format: :bogus}} =
               Localize.DateTime.to_string(~N[2024-07-06 14:30:45],
                 format: "{0}",
                 time_format: :bogus,
                 locale: :en
               )
    end
  end

  describe "date {1} and time {0} placeholders" do
    test "placeholders compose date and time with literal joiners" do
      assert {:ok, "Jul 6, 2024 at 2:30:45 PM"} =
               Localize.DateTime.to_string(~N[2024-07-06 14:30:45],
                 format: "{1} 'at' {0}",
                 locale: :en,
                 prefer: :ascii
               )
    end

    test "placeholders honour date_format and time_format options" do
      assert {:ok, "7/6/24 at 2:30 PM"} =
               Localize.DateTime.to_string(~N[2024-07-06 14:30:45],
                 format: "{1} 'at' {0}",
                 date_format: :short,
                 time_format: :short,
                 locale: :en,
                 prefer: :ascii
               )
    end
  end

  describe "binary patterns versus skeleton atoms" do
    test "a binary format is a literal pattern, not a skeleton" do
      assert {:ok, "2024761430"} =
               Localize.DateTime.to_string(~N[2024-07-06 14:30:45],
                 format: "yMdHm",
                 locale: :en
               )
    end

    test "the same name as an atom resolves through skeleton matching" do
      assert {:ok, "7/6/2024, 14:30"} =
               Localize.DateTime.to_string(~N[2024-07-06 14:30:45],
                 format: :yMdHm,
                 locale: :en
               )
    end
  end
end
