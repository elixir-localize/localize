defmodule Localize.TimeTest do
  use ExUnit.Case, async: true

  doctest Localize.Time

  describe "to_string/2 with standard formats" do
    test "medium format (default)" do
      assert {:ok, "2:30:45 PM"} =
               Localize.Time.to_string(~T[14:30:45], locale: :en, prefer: :ascii)
    end

    test "short format" do
      assert {:ok, "2:30 PM"} =
               Localize.Time.to_string(~T[14:30:00], format: :short, locale: :en, prefer: :ascii)
    end

    test "AM time" do
      assert {:ok, "9:15:00 AM"} =
               Localize.Time.to_string(~T[09:15:00], locale: :en, prefer: :ascii)
    end
  end

  describe "to_string/2 with locales" do
    test "German locale uses 24-hour format" do
      assert {:ok, result} = Localize.Time.to_string(~T[14:30:00], locale: :de)
      assert String.contains?(result, "14:30:00")
    end
  end

  describe "to_string/2 with format patterns" do
    test "24-hour format pattern" do
      assert {:ok, "14:30:45"} = Localize.Time.to_string(~T[14:30:45], format: "HH:mm:ss")
    end

    test "12-hour format pattern" do
      assert {:ok, result} = Localize.Time.to_string(~T[14:30:45], format: "h:mm:ss a")
      assert String.contains?(result, "2:30:45")
    end

    test "flexible day periods (B) follow the locale's day-period rules" do
      # Expected values verified against ICU4C 78.3, except midnight: per
      # TR35, B selects the exact-point rules (noon, midnight), where ICU
      # never produces "midnight". A time is judged at the precision its
      # pattern shows, as in ICU, so "BBBB" alone shows 12:01 as noon and
      # "h:mm BBBB" shows it as 12:01 in the afternoon.
      b = fn time, format, locale ->
        {:ok, result} = Localize.Time.to_string(time, format: format, locale: locale)
        result
      end

      assert b.(~T[08:30:00], "BBBB", :en) == "in the morning"
      assert b.(~T[12:00:00], "BBBB", :en) == "noon"
      assert b.(~T[12:01:00], "BBBB", :en) == "noon"
      assert b.(~T[12:01:00], "h:mm BBBB", :en) == "12:01 in the afternoon"
      assert b.(~T[15:00:00], "BBBB", :en) == "in the afternoon"
      assert b.(~T[19:00:00], "BBBB", :en) == "in the evening"
      assert b.(~T[22:00:00], "BBBB", :en) == "at night"
      assert b.(~T[00:00:00], "BBBB", :en) == "midnight"

      assert b.(~T[08:30:00], "BBBB", :de) == "morgens"
      assert b.(~T[12:01:00], "BBBB", :de) == "mittags"
      assert b.(~T[15:00:00], "BBBB", :de) == "nachmittags"
      assert b.(~T[19:00:00], "BBBB", :de) == "abends"
    end

    test "noon/midnight day periods (b) render at exact points only" do
      # As for B, the point is judged at the precision the pattern shows
      # (ICU4C 78.3): a pattern that shows seconds shows 12:00:30 as PM.
      b = fn time, format, locale ->
        {:ok, result} = Localize.Time.to_string(time, format: format, locale: locale)
        result
      end

      assert b.(~T[12:00:00], "bbbb", :en) == "noon"
      assert b.(~T[00:00:00], "bbbb", :en) == "midnight"
      assert b.(~T[12:01:00], "bbbb", :en) == "noon"
      assert b.(~T[12:01:00], "h:mm bbbb", :en) == "12:01 PM"
      assert b.(~T[12:00:30], "h:mm:ss bbbb", :en) == "12:00:30 PM"
      assert b.(~T[08:30:00], "bbbb", :en) == "AM"
    end

    test "locales without day-period rules fall back to AM/PM for B" do
      # A locale whose language has no dayPeriods rule set renders
      # B as AM/PM rather than failing.
      assert {:ok, result} = Localize.Time.to_string(~T[08:30:00], format: "BBBB", locale: :kok)
      assert is_binary(result) and result != ""
    end
  end

  describe "to_string/2 with partial times" do
    test "hour and minute with skeleton" do
      assert {:ok, "2:30 PM"} =
               Localize.Time.to_string(%{hour: 14, minute: 30},
                 format: :hm,
                 locale: :en,
                 prefer: :ascii
               )
    end

    test "standard format on partial time derives a skeleton from present fields" do
      # Hour + minute under `:medium` should render as the `:hm` skeleton
      # (`h:mm a` in English), not error with DateTimeUnresolvedFormatError
      # and not include an empty `ss` slot.
      assert {:ok, "2:30\u202FPM"} =
               Localize.Time.to_string(%{hour: 14, minute: 30},
                 format: :medium,
                 locale: :en,
                 prefer: :unicode
               )

      assert {:ok, "2:30 PM"} =
               Localize.Time.to_string(%{hour: 14, minute: 30},
                 format: :medium,
                 locale: :en,
                 prefer: :ascii
               )
    end

    test "standard format on hour-only partial time derives :h skeleton" do
      # Hour alone under `:medium` should render as the `:h` skeleton
      # (`h a` in English). Previously returned
      # DateTimeUnresolvedFormatError{format: :medium}.
      assert {:ok, "2 PM"} =
               Localize.Time.to_string(%{hour: 14},
                 format: :medium,
                 locale: :en,
                 prefer: :ascii
               )
    end

    test "derive_format_id/1 produces canonical order" do
      # The hour is TR35's `j`, the locale's preferred hour symbol.
      assert :jm = Localize.Time.derive_format_id(%{hour: 14, minute: 30})
      assert :jms = Localize.Time.derive_format_id(%{hour: 14, minute: 30, second: 0})
      assert :ms = Localize.Time.derive_format_id(%{minute: 30, second: 0})
    end

    test "a partial time keeps the locale's hour cycle and its -u-hc- override" do
      # CLDR's timeData prefers `H` for Germany and `h` for the United States.
      assert {:ok, "14:30"} = Localize.Time.to_string(%{hour: 14, minute: 30}, locale: :de)
      assert {:ok, "14 Uhr"} = Localize.Time.to_string(%{hour: 14}, locale: :de)

      assert {:ok, "14:30"} =
               Localize.Time.to_string(%{hour: 14, minute: 30}, locale: "en-u-hc-h23")

      assert {:ok, "2:30 PM"} =
               Localize.Time.to_string(%{hour: 14, minute: 30}, locale: "de-u-hc-h12")
    end
  end

  describe "to_string/2 with skeleton formats" do
    test "hms skeleton" do
      assert {:ok, result} =
               Localize.Time.to_string(~T[14:30:45], format: :hms, locale: :en, prefer: :ascii)

      assert String.contains?(result, "2:30:45")
      assert String.contains?(result, "PM")
    end

    test "Hms skeleton (24-hour)" do
      assert {:ok, result} =
               Localize.Time.to_string(~T[14:30:45], format: :Hms, locale: :en)

      assert String.contains?(result, "14:30:45")
    end

    test "hm skeleton" do
      assert {:ok, result} =
               Localize.Time.to_string(~T[14:30:00], format: :hm, locale: :en, prefer: :ascii)

      assert String.contains?(result, "2:30")
      assert String.contains?(result, "PM")
    end
  end

  describe "to_string/2 with Unicode/ASCII preference" do
    test "ascii produces standard space before AM/PM" do
      {:ok, ascii_result} =
        Localize.Time.to_string(~T[14:30:00], locale: :en, prefer: :ascii)

      assert String.contains?(ascii_result, " PM")
    end

    test "unicode may use narrow no-break space" do
      {:ok, unicode_result} =
        Localize.Time.to_string(~T[14:30:00], locale: :en, prefer: :unicode)

      # Unicode version uses narrow no-break space (\u202F)
      assert String.contains?(unicode_result, "PM")
    end
  end

  describe "to_string/2 error handling" do
    test "non-time map returns error" do
      assert {:error, %Localize.DateTimeInvalidInputError{}} =
               Localize.Time.to_string(%{foo: :bar})
    end

    test "string input returns error" do
      assert {:error, %Localize.DateTimeInvalidInputError{}} =
               Localize.Time.to_string("not a time")
    end
  end

  describe "to_string!/2" do
    test "returns string directly" do
      result = Localize.Time.to_string!(~T[01:23:00], locale: :en, prefer: :ascii)
      assert result == "1:23:00 AM"
    end

    test "raises on error" do
      # `apply/3` is type-opaque so the Elixir 1.20 type checker does
      # not flag this deliberate contract-violation test.
      assert_raise Localize.DateTimeInvalidInputError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(Localize.Time, :to_string!, [%{foo: :bar}])
      end
    end
  end

  describe "hour_format_from_locale/1" do
    test "24-hour locales return :h23" do
      assert {:ok, :h23} = Localize.Time.hour_format_from_locale(:ja)
      assert {:ok, :h23} = Localize.Time.hour_format_from_locale(:de)
      assert {:ok, :h23} = Localize.Time.hour_format_from_locale(:fr)
    end

    test "12-hour locales return :h12" do
      assert {:ok, :h12} = Localize.Time.hour_format_from_locale(:en)
      assert {:ok, :h12} = Localize.Time.hour_format_from_locale("en-AU")
    end

    test "honours -u-hc-h12 override on a 24-hour locale" do
      assert {:ok, :h12} = Localize.Time.hour_format_from_locale("fr-u-hc-h12")
    end

    test "honours -u-hc-h23 override on a 12-hour locale" do
      assert {:ok, :h23} = Localize.Time.hour_format_from_locale("en-u-hc-h23")
    end

    test "honours -u-hc-h11 override" do
      assert {:ok, :h11} = Localize.Time.hour_format_from_locale("ja-u-hc-h11")
    end

    test "accepts a LanguageTag struct directly" do
      {:ok, language_tag} = Localize.validate_locale("fr-u-hc-h12")
      assert {:ok, :h12} = Localize.Time.hour_format_from_locale(language_tag)
    end

    test "bang variant returns the bare cycle atom" do
      assert :h23 == Localize.Time.hour_format_from_locale!(:ja)
    end
  end

  describe "to_string/2 honours -u-hc- on standard formats" do
    # Reported by @woylie as a follow-up to #22. Standard formats
    # (`:short`/`:medium`/`:long`/`:full`) used to read the locale's
    # static `time_formats[:style]` skeleton with no awareness of any
    # `-u-hc-` Unicode-extension override, so e.g. `"fr-u-hc-h12"`
    # silently produced 24-hour output. The fix remaps the standard
    # format to the locale's cycle-appropriate `:hm`/`:hms`/`:hmsv`
    # (12-hour) or `:Hm`/`:Hms`/`:Hmsv` (24-hour) skeleton.

    test "fr-u-hc-h12 flips :short/:medium to 12-hour with AM/PM" do
      assert {:ok, "9:00 PM"} =
               Localize.Time.to_string(~T[21:00:00], format: :short, locale: "fr-u-hc-h12")

      assert {:ok, "9:00:00 PM"} =
               Localize.Time.to_string(~T[21:00:00], format: :medium, locale: "fr-u-hc-h12")
    end

    test "en-u-hc-h23 flips :short/:medium to 24-hour, no AM/PM" do
      assert {:ok, "21:00"} =
               Localize.Time.to_string(~T[21:00:00], format: :short, locale: "en-u-hc-h23")

      assert {:ok, "21:00:00"} =
               Localize.Time.to_string(~T[21:00:00], format: :medium, locale: "en-u-hc-h23")
    end

    test "ja-u-hc-h12 emits Japanese AM/PM marker before the time" do
      {:ok, short} =
        Localize.Time.to_string(~T[21:00:00], format: :short, locale: "ja-u-hc-h12")

      assert short =~ "午後"
      assert short =~ "9"
      refute short =~ "21"
    end

    test "no override: ja keeps its native 24-hour cycle" do
      assert {:ok, "21:00"} = Localize.Time.to_string(~T[21:00:00], format: :short, locale: :ja)

      assert {:ok, "21:00:00"} =
               Localize.Time.to_string(~T[21:00:00], format: :medium, locale: :ja)
    end

    test "no override: en keeps its native 12-hour cycle" do
      assert {:ok, "9:00 PM"} =
               Localize.Time.to_string(~T[21:00:00], format: :short, locale: :en, prefer: :ascii)
    end

    test "a skeleton's j takes the hc override, and an explicit hour keeps its cycle" do
      # TR35's `hc` replaces the locale's preferred hour cycle, which a
      # skeleton asks for with `j`; an explicit `h` or `H` names its own
      # cycle. ICU4C 78.3's DateTimePatternGenerator gives these results.
      assert Localize.Time.to_string(~T[21:00:00], format: :jm, locale: "fr-u-hc-h12") ==
               {:ok, "9:00 PM"}

      assert Localize.Time.to_string(~T[21:00:00], format: :jm, locale: "en-u-hc-h23") ==
               {:ok, "21:00"}

      assert Localize.Time.to_string(~T[21:00:00], format: :Hms, locale: "fr-u-hc-h12") ==
               {:ok, "21:00:00"}

      assert Localize.Time.to_string(~T[21:00:00], format: :hms, locale: "en-u-hc-h23") ==
               {:ok, "9:00:00 PM"}

      assert Localize.Time.to_string(~T[21:00:00], format: :Hms, locale: "ja-u-hc-h12") ==
               {:ok, "21:00:00"}
    end

    test "binary patterns are NOT remapped by hc override (user assertion)" do
      # The spec is silent on raw binary patterns. We treat them as
      # the user's deliberate assertion of the exact pattern, so
      # `"HH:mm:ss"` stays 24h even with hc=h12.
      assert {:ok, "21:00:00"} =
               Localize.Time.to_string(~T[21:00:00],
                 format: "HH:mm:ss",
                 locale: "fr-u-hc-h12"
               )
    end
  end

  describe "to_string/2 strips empty zone padding on zoneless inputs" do
    # Several locales' `:long`/`:full` time patterns end in
    # `" z"` / `" zzzz"`. With a `Time` (no zone) or `NaiveDateTime`
    # (no zone), the zone field renders empty but the literal space
    # used to remain, leaving outputs like `"21:00:00 "` and
    # `"21時00分00秒 "`. The formatter now elides empty zone results
    # along with their immediately-bounding whitespace.

    test ":ja :long on a Time loses the trailing space" do
      assert {:ok, out} = Localize.Time.to_string(~T[21:00:00], format: :long, locale: :ja)
      refute String.ends_with?(out, " ")
      assert out == "21:00:00"
    end

    test "NaiveDateTime via Localize.Time.to_string also strips zone fields" do
      # `%NaiveDateTime{}` is also zoneless by construction, so the
      # same skeleton-strip applies when callers route a NaiveDateTime
      # through `Localize.Time.to_string` (e.g., displaying just the
      # time portion of a wall-clock value).
      ndt = ~N[2026-05-08 21:00:00]

      assert {:ok, "21:00:00"} = Localize.Time.to_string(ndt, format: :long, locale: :ja)
      assert {:ok, "21:00:00"} = Localize.Time.to_string(ndt, format: :full, locale: :ja)
      assert {:ok, "21:00:00"} = Localize.Time.to_string(ndt, format: :long, locale: :de)
      assert {:ok, "21:00:00"} = Localize.Time.to_string(ndt, format: :full, locale: :es)
    end

    test ":ja :full on a Time strips zone fields (and collapses with :medium)" do
      # `:ja`'s `:full` skeleton (`:Hmmsszzzz`) is the only one that
      # carries the Japanese unit chars `時/分/秒` — they live in the
      # zone-bearing pattern, not the zone-free one. Stripping the
      # zone falls back to ja's `:Hmmss` skeleton, which maps to the
      # Western-style `"H:mm:ss"`. So `:full` on a `%Time{}` loses
      # both the trailing space AND the Japanese unit chars; this
      # collapses :long/:full with :medium for zoneless inputs, which
      # is correct — there is no zone to differentiate them by.
      assert {:ok, "21:00:00"} = Localize.Time.to_string(~T[21:00:00], format: :full, locale: :ja)
      assert {:ok, "21:00:00"} = Localize.Time.to_string(~T[21:00:00], format: :long, locale: :ja)

      assert {:ok, "21:00:00"} =
               Localize.Time.to_string(~T[21:00:00], format: :medium, locale: :ja)
    end

    test ":de :long/:full on a Time loses the trailing space" do
      assert {:ok, "21:00:00"} = Localize.Time.to_string(~T[21:00:00], format: :long, locale: :de)
      assert {:ok, "21:00:00"} = Localize.Time.to_string(~T[21:00:00], format: :full, locale: :de)
    end

    test "DateTime with a real zone keeps the zone (no regression)" do
      {:ok, out} =
        Localize.DateTime.to_string(~U[2026-01-01 21:00:00Z], format: :long, locale: :de)

      assert out =~ "UTC"
      refute String.ends_with?(out, " ")
    end

    test "NaiveDateTime (no zone) loses the trailing space" do
      assert {:ok, out} =
               Localize.DateTime.to_string(~N[2026-01-01 21:00:00], format: :long, locale: :de)

      refute String.ends_with?(out, " ")
    end
  end

  describe "to_string/2 at a standard format whose pattern has no zone" do
    # A standard format writes the locale's standard pattern, in a `%Time{}`
    # as in a map: `kl`'s medium time is "HH.mm.ss", `yo`'s "H:m:s", `bg`'s
    # short time "H:mm" and `am`'s "h:mm a", whose morning is "ጥዋት". Each
    # locale's `Hm`, `Hms` or `hm` in `availableFormats` is another pattern
    # ("H:mm 'ч'." in `bg`), which the skeleton of the format resolved to.
    test "is the locale's standard pattern" do
      for {locale, format, expected} <- [
            {:kl, :medium, "10.30.00"},
            {:yo, :medium, "10:30:0"},
            {:bg, :short, "10:30"},
            {:am, :short, "10:30 ጥዋት"}
          ] do
        assert Localize.Time.to_string(~T[10:30:00], locale: locale, format: format) ==
                 {:ok, expected},
               inspect({locale, format})

        assert Localize.Time.to_string(~N[2024-04-03 10:30:00], locale: locale, format: format) ==
                 {:ok, expected},
               inspect({locale, format})
      end
    end

    # CLDR's skeleton for a time format is not always its pattern's: `cop`
    # and `syr` write a 12-hour pattern beside a 24-hour skeleton, and `bo`
    # and `ug` the reverse. The pattern decides, so a struct and a map of
    # the same fields are written alike, at every hour.
    test "writes a struct as a map of the same fields" do
      for locale <- [:nds, :oc, :cop, :kxv, :syr, :bo, :ii, :ug, :am, :kok, :yo, :bg, :kl, :as],
          format <- [:short, :medium],
          time <- [~T[10:30:00], ~T[22:05:09]] do
        fields = Map.take(time, [:hour, :minute, :second])

        assert Localize.Time.to_string(time, locale: locale, format: format) ==
                 Localize.Time.to_string(fields, locale: locale, format: format),
               inspect({locale, format, time})
      end
    end
  end

  describe "a value with no zone at :long and :full" do
    # A long or a full time pattern has a zone field, which a value with no
    # zone cannot fill, so its other fields are written as the locale
    # writes them alone. The expected times are ECMA-402's for a
    # `Temporal.PlainTime` at those styles (Node 24.9): `ja`'s full time is
    # "H時mm分ss秒 zzzz" and its `Hms` "H:mm:ss".
    @plain_times [
      ja: "10:30:00",
      th: "10:30:00",
      lo: "10:30:00",
      fa: "۱۰:۳۰:۰۰",
      ko: "오전 10:30:00",
      "zh-Hant": "上午10:30:00"
    ]

    test "writes the time without the zone field, in a struct and in a map" do
      naive = ~N[2024-04-03 10:30:00]
      fields = Map.take(naive, [:hour, :minute, :second])

      for {locale, expected} <- @plain_times,
          format <- [:long, :full],
          value <- [naive, fields] do
        assert Localize.Time.to_string(value, locale: locale, format: format) == {:ok, expected},
               inspect({locale, format})
      end
    end

    # A date and time writes the same time, so it leaves nothing of the
    # zone behind, as `fa`'s "H:mm:ss (z)" and `zh-Hant`'s "Bh:mm:ss [z]"
    # left their brackets, and it reads back as the value it was written
    # from. `ja` joins its full date "y年M月d日EEEE" to the time with a space.
    test "writes a date and time with that time, which reads back" do
      naive = ~N[2024-04-03 10:30:00]

      fields =
        Map.take(naive, [:calendar, :year, :month, :day, :hour, :minute, :second, :microsecond])

      assert Localize.DateTime.to_string(naive, locale: :ja, format: :full) ==
               {:ok, "2024年4月3日水曜日 10:30:00"}

      for {locale, time} <- @plain_times, format <- [:long, :full], value <- [naive, fields] do
        assert {:ok, text} = Localize.DateTime.to_string(value, locale: locale, format: format)
        assert String.ends_with?(text, time), inspect({locale, format, text})
        refute String.contains?(text, ["()", "[]"]), inspect({locale, format, text})
        assert Localize.DateTime.parse(text, locale: locale) == {:ok, naive}
      end
    end

    # A value that holds a zone keeps the format's zone field, in a struct
    # and in a map.
    test "keeps the zone of a value that has one" do
      utc = ~U[2024-04-03 10:30:00Z]
      fields = Map.take(utc, [:hour, :minute, :second, :time_zone, :utc_offset, :std_offset])

      assert Localize.Time.to_string(utc, locale: :en, format: :long, prefer: :ascii) ==
               {:ok, "10:30:00 AM UTC"}

      assert Localize.Time.to_string(Map.put(fields, :zone_abbr, "UTC"),
               locale: :en,
               format: :long,
               prefer: :ascii
             ) == {:ok, "10:30:00 AM UTC"}
    end
  end
end
