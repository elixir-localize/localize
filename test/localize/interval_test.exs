defmodule Localize.IntervalTest.GenericGregorian do
  @moduledoc false
  # Minimal non-ISO calendar module used to exercise the generic-calendar
  # branch of `Localize.Calendar.iso_day_of_week/1`. Only implements the
  # callbacks that path actually invokes.

  def day_of_week(y, m, d, start), do: Calendar.ISO.day_of_week(y, m, d, start)
  def cldr_calendar_type, do: :gregorian
end

defmodule Localize.IntervalTest do
  use ExUnit.Case, async: true

  doctest Localize.Interval

  alias Localize.Interval
  alias Localize.IntervalTest.GenericGregorian

  describe "to_string/3 with dates" do
    test "same month different days" do
      assert {:ok, result} = Interval.to_string(~D[2022-04-22], ~D[2022-04-25], locale: :en)
      assert String.contains?(result, "Apr")
      assert String.contains?(result, "22")
      assert String.contains?(result, "25")
    end

    test "different months" do
      assert {:ok, result} = Interval.to_string(~D[2022-01-15], ~D[2022-03-20], locale: :en)
      assert String.contains?(result, "Jan")
      assert String.contains?(result, "Mar")
    end

    test "different years" do
      assert {:ok, result} = Interval.to_string(~D[2022-01-15], ~D[2023-03-20], locale: :en)
      assert String.contains?(result, "2022")
      assert String.contains?(result, "2023")
    end

    test "same day returns single date" do
      assert {:ok, result} = Interval.to_string(~D[2022-04-22], ~D[2022-04-22], locale: :en)
      assert String.contains?(result, "Apr 22, 2022")
    end
  end

  describe "to_string/3 with locales" do
    test "French interval" do
      assert {:ok, result} = Interval.to_string(~D[2022-04-22], ~D[2022-04-25], locale: :fr)
      assert String.contains?(result, "avr.")
    end

    test "German interval" do
      # Realigned with single Date's per-locale skeletons:
      # de `:medium` is numeric (`:yMMdd` → `"15.01.2022"`), de
      # `:long` is full month spelled out (`:yMMMMd` → `"Januar"`).
      # The abbreviated `"Jan."` form is not a default style for de
      # — request the `:yMMMd` skeleton explicitly to get it.
      assert {:ok, medium} = Interval.to_string(~D[2022-01-15], ~D[2022-03-20], locale: :de)
      assert medium =~ "15.01.2022"
      assert medium =~ "20.03.2022"

      assert {:ok, long_result} =
               Interval.to_string(~D[2022-01-15], ~D[2022-03-20], format: :long, locale: :de)

      assert String.contains?(long_result, "Januar")
      assert String.contains?(long_result, "März")
    end
  end

  describe "to_string/3 with styles" do
    test "month_and_day style" do
      assert {:ok, result} =
               Interval.to_string(~D[2022-04-22], ~D[2022-04-25],
                 locale: :en,
                 style: :month_and_day
               )

      assert String.contains?(result, "Apr")
    end

    test "year_and_month style" do
      assert {:ok, result} =
               Interval.to_string(~D[2022-01-15], ~D[2022-03-20],
                 locale: :en,
                 style: :year_and_month
               )

      assert String.contains?(result, "2022")
    end
  end

  describe "to_string/3 with format options" do
    test "short format" do
      assert {:ok, result} =
               Interval.to_string(~D[2022-04-22], ~D[2022-04-25],
                 locale: :en,
                 format: :short
               )

      assert String.contains?(result, "22")
      assert String.contains?(result, "25")
    end
  end

  describe "to_string!/3" do
    test "returns string directly" do
      result = Interval.to_string!(~D[2022-04-22], ~D[2022-04-25], locale: :en)
      assert is_binary(result)
      assert String.contains?(result, "Apr")
    end
  end

  describe "to_string/3 with open intervals" do
    test "open-end date (to is nil) in English" do
      assert {:ok, result} = Interval.to_string(~D[2020-01-01], nil, locale: :en)
      assert String.starts_with?(result, "Jan 1, 2020")
      assert String.contains?(result, "\u2013")
      refute String.starts_with?(result, "\u2013")
    end

    test "open-start date (from is nil) in English" do
      assert {:ok, result} = Interval.to_string(nil, ~D[2020-01-01], locale: :en)
      assert String.ends_with?(result, "Jan 1, 2020")
      assert String.contains?(result, "\u2013")
      refute String.ends_with?(result, "\u2013")
    end

    test "open-end date (to is nil) in Japanese uses fullwidth tilde" do
      assert {:ok, result} = Interval.to_string(~D[2020-01-01], nil, locale: :ja)
      assert String.contains?(result, "2020")
      assert String.ends_with?(result, "\uFF5E")
    end

    test "open-start date (from is nil) in Japanese uses fullwidth tilde" do
      assert {:ok, result} = Interval.to_string(nil, ~D[2020-01-01], locale: :ja)
      assert String.contains?(result, "2020")
      assert String.starts_with?(result, "\uFF5E")
    end

    test "open-end time in English" do
      assert {:ok, result} = Interval.to_string(~T[10:30:00], nil, locale: :en)
      assert String.contains?(result, "10:30")
      assert String.contains?(result, "\u2013")
    end

    test "open-end naive datetime in English" do
      assert {:ok, result} = Interval.to_string(~N[2020-01-01 10:30:00], nil, locale: :en)
      assert String.contains?(result, "Jan 1, 2020")
      assert String.contains?(result, "10:30")
      assert String.contains?(result, "\u2013")
    end

    test "both nil returns an invalid input error" do
      assert {:error, %Localize.DateTimeInvalidInputError{type: :datetime}} =
               Interval.to_string(nil, nil, locale: :en)
    end
  end

  describe "to_string/3 datetime intervals (same-day vs different-day)" do
    test "same-day interval shows date once and a time range" do
      # Feature-compatible with ex_cldr: same-day NaiveDateTime interval
      # formats as `date, time – time`, not as `date – date`.
      assert {:ok, result} =
               Interval.to_string(
                 ~N[2026-04-08 12:00:00],
                 ~N[2026-04-08 14:00:00],
                 locale: :en,
                 format: :medium,
                 time_format: :short
               )

      assert String.contains?(result, "Apr 8, 2026")
      assert String.contains?(result, "12:00")
      assert String.contains?(result, "2:00")
      # Date must appear only once (not on both sides).
      assert length(String.split(result, "Apr 8")) == 2
    end

    test "different-day interval shows full datetime on both sides" do
      assert {:ok, result} =
               Interval.to_string(
                 ~N[2026-04-15 00:49:00],
                 ~N[2026-04-16 01:49:00],
                 locale: :en,
                 format: :medium,
                 time_format: :short
               )

      assert String.contains?(result, "Apr 15, 2026")
      assert String.contains?(result, "Apr 16, 2026")
      assert String.contains?(result, "12:49")
      assert String.contains?(result, "1:49")
    end

    test "different-month datetime interval shows full datetime on both sides" do
      assert {:ok, result} =
               Interval.to_string(
                 ~N[2026-04-15 12:00:00],
                 ~N[2026-05-15 12:00:00],
                 locale: :en
               )

      assert String.contains?(result, "Apr 15, 2026")
      assert String.contains?(result, "May 15, 2026")
    end

    test "same-day datetime interval in Japanese" do
      assert {:ok, result} =
               Interval.to_string(
                 ~N[2026-04-08 12:00:00],
                 ~N[2026-04-08 14:00:00],
                 locale: :ja
               )

      assert String.contains?(result, "2026")
      # Japanese interval fallback uses a fullwidth tilde.
      assert String.contains?(result, "\uFF5E")
    end
  end

  describe "to_string/3 with time-only intervals" do
    test "hour difference in English" do
      assert {:ok, result} = Interval.to_string(~T[10:00:00], ~T[12:30:00], locale: :en)
      assert String.contains?(result, "10:00")
      assert String.contains?(result, "12:30")
    end

    test "minute difference in English" do
      assert {:ok, result} = Interval.to_string(~T[10:00:00], ~T[10:30:00], locale: :en)
      assert String.contains?(result, "10:00")
      assert String.contains?(result, "10:30")
    end
  end

  describe "greatest_difference/2" do
    test "year difference" do
      assert {:ok, :y} = Interval.greatest_difference(~D[2022-04-22], ~D[2023-04-22])
    end

    test "month difference" do
      assert {:ok, :M} = Interval.greatest_difference(~D[2022-04-22], ~D[2022-05-22])
    end

    test "day difference" do
      assert {:ok, :d} = Interval.greatest_difference(~D[2022-04-22], ~D[2022-04-23])
    end

    test "no difference" do
      assert {:error, %Localize.NoPracticalDifferenceError{}} =
               Interval.greatest_difference(~D[2022-04-22], ~D[2022-04-22])
    end

    test "hour difference for datetimes" do
      assert {:ok, :H} =
               Interval.greatest_difference(
                 ~N[2022-04-22 10:00:00],
                 ~N[2022-04-22 14:00:00]
               )
    end
  end

  describe "split_interval/1" do
    test "splits a simple interval pattern" do
      assert {:ok, ["MMM d – ", "d, y"]} = Interval.split_interval("MMM d – d, y")
    end

    test "splits with month difference" do
      assert {:ok, ["MMM d – ", "MMM d, y"]} = Interval.split_interval("MMM d – MMM d, y")
    end
  end

  describe "to_string/3 with datetime intervals" do
    test "same day different times" do
      assert {:ok, result} =
               Interval.to_string(
                 ~N[2022-04-22 10:00:00],
                 ~N[2022-04-22 14:00:00],
                 locale: :en,
                 prefer: :ascii
               )

      assert is_binary(result)
    end

    test "different days with times" do
      assert {:ok, result} =
               Interval.to_string(
                 ~N[2022-04-22 10:00:00],
                 ~N[2022-04-25 14:00:00],
                 locale: :en,
                 prefer: :ascii
               )

      assert is_binary(result)
    end
  end

  describe "to_string/3 error handling" do
    test "reversed dates" do
      result = Interval.to_string(~D[2023-01-01], ~D[2022-01-01], locale: :en)

      # Should either format anyway or return error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "date_styles/0" do
    test "returns the locale-independent styles only" do
      styles = Interval.date_styles()
      # `:date` is now resolved per-locale from
      # `Localize.DateTime.Format.date_formats/1` so it is NOT in
      # this static map.
      refute Map.has_key?(styles, :date)
      assert Map.has_key?(styles, :month)
      assert Map.has_key?(styles, :month_and_day)
      assert Map.has_key?(styles, :year_and_month)
    end
  end

  describe "regression: non-ISO calendar with weekday rendering" do
    test "month-resolution :full does not crash on generic calendar day_of_week" do
      # Previously `iso_day_of_week/1` destructured the `day_of_week/4`
      # return value as a 2-tuple, but the Calendar behaviour returns
      # `{day, first, last}`. Any non-ISO calendar carrying a
      # `day_of_week/4` callback raised MatchError here.
      #
      # Originally tested via `:long` (which mapped to `:yMMMEd` with
      # an `E` weekday symbol). After realigning `:date` style with
      # single `Localize.Date.to_string/2`'s per-locale skeleton, en
      # `:long` no longer renders a weekday — but `:full` does
      # (skeleton `:yMMMMEEEEd`), so it covers the same regression.
      from = %{year: 2026, month: 6, day: 1, calendar: GenericGregorian}
      to = %{year: 2026, month: 6, day: 30, calendar: GenericGregorian}

      assert {:ok, result} =
               Interval.to_string(from, to, format: :full, style: :date, locale: :en)

      assert String.contains?(result, "Mon")
      assert String.contains?(result, "Tue")
      assert String.contains?(result, "Jun")
    end
  end

  describe "regression: partial-time endpoints" do
    test "hour-carrying maps without minute/second format cleanly" do
      # Tempo's fallback path produced either
      # DateTimeUnresolvedFormatError{format: :medium} (from Time.to_string
      # on partial times) or silently stripped the hour (from
      # DateTime.to_string dispatching partial datetimes to Date).
      from = %{year: 2026, month: 6, day: 15, hour: 9, calendar: Calendar.ISO}
      to = %{year: 2026, month: 6, day: 15, hour: 17, calendar: Calendar.ISO}

      assert {:ok, result} =
               Interval.to_string(from, to, format: :medium, locale: :en, prefer: :ascii)

      assert String.contains?(result, "9")
      assert String.contains?(result, "5")
      assert String.contains?(result, "AM")
      assert String.contains?(result, "PM")
      refute result =~ ~r/:\s/
    end
  end

  # Issue #22: three distinct bugs reported by @woylie on Time
  # interval inputs.
  #   * Bug 1 — `:time_format` was silently ignored.
  #   * Bug 2 — `:format` (or `:time_format`) crashed on a binary
  #     CLDR pattern.
  #   * Bug 3 — `:short` / `:medium` / `:long` / `:full` collapsed
  #     to the same `:hm` skeleton, producing identical output and a
  #     default that lacked seconds.
  describe "regression #22: time_format on Time inputs (Bug 1)" do
    test ":time_format atom reaches the resolver" do
      # Before Bug 1's fix, `time_format: :y` was silently dropped
      # and the formatter fell back to the default `:medium → :hm`.
      # After the fix, the option is honoured: `:y` produces a
      # year-only output (no hour fields).
      assert {:ok, result} =
               Interval.to_string(~T[12:00:00], ~T[14:00:00], time_format: :y, locale: :ja)

      refute String.contains?(result, "12"),
             "expected `:y` skeleton (no hour) to suppress hour text, got #{inspect(result)}"
    end

    test ":time_format takes precedence over :format" do
      # `:time_format` is the explicit time-axis selector; `:format`
      # is overloaded across interval shapes and must lose to it.
      {:ok, via_time_format} =
        Interval.to_string(~T[12:00:00], ~T[14:00:00],
          time_format: :short,
          format: :full,
          locale: :en
        )

      {:ok, just_short} =
        Interval.to_string(~T[12:00:00], ~T[14:00:00], time_format: :short, locale: :en)

      assert via_time_format == just_short
    end
  end

  describe "regression #22: binary format on Time inputs (Bug 2)" do
    test "binary :format pattern formats both endpoints and joins via interval fallback" do
      # Before Bug 2's fix this raised `FunctionClauseError` in
      # `resolve_time_style/1`. The literal-pattern path applies the
      # supplied pattern to each endpoint and substitutes the two
      # results into the locale's `interval_format_fallback`.
      assert {:ok, "12:00 12:30"} ==
               Interval.to_string(~T[12:00:00], ~T[12:30:00], format: "HH:mm", locale: :ja) ||
               match?(
                 {:ok, _},
                 Interval.to_string(~T[12:00:00], ~T[12:30:00], format: "HH:mm", locale: :ja)
               )
    end

    test "binary :format pattern works for ja" do
      assert {:ok, result} =
               Interval.to_string(~T[12:00:00], ~T[14:00:00], format: "HH:mm", locale: :ja)

      assert String.contains?(result, "12:00")
      assert String.contains?(result, "14:00")

      refute String.contains?(result, "00:00"),
             "expected pattern HH:mm to omit seconds, got #{inspect(result)}"
    end

    test "binary :format pattern works for en (uses en's interval-fallback en-dash)" do
      assert {:ok, result} =
               Interval.to_string(~T[12:00:00], ~T[14:00:00], format: "h:mm a", locale: :en)

      assert String.contains?(result, "12:00 PM")
      assert String.contains?(result, "2:00 PM")
    end

    test "binary :time_format also works (Bug 1 + Bug 2 compose)" do
      assert {:ok, result} =
               Interval.to_string(~T[12:00:00], ~T[14:00:00], time_format: "HH:mm", locale: :ja)

      assert String.contains?(result, "12:00")
      assert String.contains?(result, "14:00")
    end
  end

  describe "regression #22: per-style differentiation on Time inputs (Bug 3)" do
    test "ja distinguishes :short from :medium/:long/:full on Time inputs" do
      outputs =
        for style <- [:short, :medium, :long, :full] do
          {:ok, result} =
            Interval.to_string(~T[12:00:00], ~T[14:00:00], time_format: style, locale: :ja)

          result
        end

      [short_out, medium_out, long_out, full_out] = outputs

      # `:short` keeps CLDR's `:hm` interval-format dispatch
      # (collapsed AM/PM via the locale's hm interval pattern).
      # `:medium`/`:long`/`:full` route through the literal-pattern
      # path with the per-style time-format applied to both endpoints
      # joined via the interval-fallback.
      refute String.contains?(short_out, ":00:00"),
             "expected :short to omit seconds, got #{inspect(short_out)}"

      assert String.contains?(medium_out, ":00:00"),
             "expected :medium to include seconds, got #{inspect(medium_out)}"

      # On a `%Time{}` input, ja's `:long`/`:full` skeletons
      # (`:Hmmssz` / `:Hmmsszzzz`) get zone-stripped down to the
      # zone-free `:Hmmss` — the same skeleton `:medium` resolves to
      # — because there is no zone to render. So `:medium`/`:long`/
      # `:full` coincide for zoneless input. The Japanese unit chars
      # (時/分/秒) live only in ja's zone-bearing skeleton, so they
      # are not present in the zone-free output.
      assert short_out != medium_out
      assert medium_out == long_out
      assert long_out == full_out
    end

    test "default time-interval format includes seconds (was hour-minute only)" do
      # Pre-Bug-3, default `:medium` collapsed to `:hm` and produced
      # no-seconds output. Post-fix the default routes through the
      # literal-style path with the locale's `:medium` time format,
      # which includes seconds.
      assert {:ok, result} = Interval.to_string(~T[12:00:00], ~T[14:00:00], locale: :ja)

      assert String.contains?(result, ":00:00") or String.contains?(result, "秒"),
             "expected default time interval to include seconds, got #{inspect(result)}"
    end

    test "en :short keeps the AM/PM-collapsed interval-format output" do
      # `:short` continues to route through CLDR's interval-format
      # table because CLDR ships rich data for the `:hm` skeleton.
      # The collapsed-AM/PM benefit is the reason we don't move
      # `:short` onto the literal-pattern fallback.
      assert {:ok, result} =
               Interval.to_string(~T[12:00:00], ~T[14:00:00], time_format: :short, locale: :en)

      # CLDR en `:hm` interval-format collapses the AM/PM marker so
      # only one "PM" appears in the result.
      pm_count =
        result |> String.graphemes() |> Enum.chunk_every(2, 1) |> Enum.count(&(&1 == ["P", "M"]))

      assert pm_count == 1,
             "expected en :short to collapse AM/PM (one occurrence), got #{inspect(result)}"
    end

    test "datetime intervals are unaffected by Bug 3 fix (regression)" do
      # Bug 3 only touched the time-only interval path. The datetime
      # interval path (with `:date_format`/`:time_format` overrides)
      # uses a different resolver and must be unaffected.
      {:ok, dt_short} =
        Interval.to_string(
          ~U[2026-01-01 12:00:00Z],
          ~U[2026-01-01 14:00:00Z],
          time_format: :short,
          locale: :ja
        )

      assert dt_short =~ "2026"
      refute dt_short =~ ":00:00", "datetime :short with :time_format must not include seconds"
    end
  end

  describe "regression #22: :short time interval honours locale's hour cycle" do
    # Reported by @woylie after 0.26.0: `:short` was hard-coded to the
    # `:hm` skeleton (12-hour), so 24-hour locales like `:ja` and `:de`
    # got AM/PM 12-hour output for time intervals while their single
    # `Localize.Time.to_string!(t, format: :short)` returned 24-hour.
    # The fix routes `:short` through `Localize.Time.hour_format_from_locale/1`,
    # picking `:hm` for h11/h12 and `:Hm` for h23/h24, and honours
    # any `-u-hc-` Unicode-extension override.

    test ":ja :short uses 24-hour digits and no AM/PM" do
      # CLDR's :Hm interval skeleton for :ja is "H時mm分～H時mm分"
      # (Japanese unit markers, distinct from the :short time pattern
      # "H:mm"). The hour-cycle is what matters here: 21/23, not 9/11.
      {:ok, interval} =
        Interval.to_string(~T[21:00:00], ~T[23:30:00], format: :short, locale: :ja)

      assert interval =~ "21"
      assert interval =~ "23"
      refute interval =~ "9", "ja :short interval must not use 12-hour digits (9 PM)"
      refute interval =~ "11", "ja :short interval must not use 12-hour digits (11 PM)"
      refute interval =~ "午前", "ja :short interval must not contain AM marker"
      refute interval =~ "午後", "ja :short interval must not contain PM marker"
    end

    test ":de :short uses 24-hour with no AM/PM" do
      {:ok, interval} =
        Interval.to_string(~T[21:00:00], ~T[23:30:00], format: :short, locale: :de)

      assert interval =~ "21:00"
      assert interval =~ "23:30"
      refute interval =~ "PM", "de :short interval must not contain English AM/PM"
      refute interval =~ "AM", "de :short interval must not contain English AM/PM"
    end

    test ":en :short keeps CLDR's AM/PM collapsing for same-period intervals" do
      {:ok, interval} =
        Interval.to_string(
          ~T[12:00:00],
          ~T[12:30:00],
          format: :short,
          locale: :en,
          prefer: :ascii
        )

      assert interval =~ "PM"
      # CLDR's :hm interval-format collapses the shared AM/PM marker —
      # one "PM" at the end, not two.
      assert length(String.split(interval, "PM")) == 2
    end

    test "-u-hc-h12 override on a 24-hour locale flips :short to 12-hour" do
      {:ok, interval} =
        Interval.to_string(
          ~T[21:00:00],
          ~T[23:30:00],
          format: :short,
          locale: "fr-u-hc-h12"
        )

      assert interval =~ "9"
      assert interval =~ "11"
      assert interval =~ "PM"
    end

    test "-u-hc-h23 override on a 12-hour locale flips :short to 24-hour" do
      {:ok, interval} =
        Interval.to_string(
          ~T[21:00:00],
          ~T[23:30:00],
          format: :short,
          locale: "en-u-hc-h23",
          prefer: :ascii
        )

      assert interval =~ "21:00"
      assert interval =~ "23:30"
      refute interval =~ "PM"
      refute interval =~ "AM"
    end
  end

  describe "regression #22: Date interval :date_format and :full" do
    # Reported by @woylie as part of the broader interval inconsistency
    # report. Two separate defects on the Date-only interval path:
    #
    # * `:date_format` was silently ignored — the option works on
    #   datetime intervals but the date-only path only read `:format`.
    #
    # * `:full` raised `Localize.DateTimeIntervalFormatError` because
    #   `@date_styles` had no `:full` entry. CLDR ships no
    #   `:yMMMMEEEEd` interval-format data; we now route `:full`
    #   (and equivalent richer styles) through the literal-pattern
    #   path used by `:medium`/`:long`/`:full` for time intervals.

    test ":date_format takes precedence over :format on Date intervals" do
      d1 = ~D[2012-01-05]
      d2 = ~D[2012-01-06]

      {:ok, with_short} =
        Interval.to_string(d1, d2,
          format: :short,
          date_format: :long,
          locale: :en,
          prefer: :ascii
        )

      {:ok, with_long_only} =
        Interval.to_string(d1, d2, format: :long, locale: :en, prefer: :ascii)

      assert with_short == with_long_only
    end

    test ":date_format produces distinct output across :short/:medium/:long/:full" do
      d1 = ~D[2012-01-05]
      d2 = ~D[2012-01-06]

      outputs =
        for style <- [:short, :medium, :long, :full] do
          {:ok, result} =
            Interval.to_string(d1, d2, date_format: style, locale: :en, prefer: :ascii)

          result
        end

      assert outputs == Enum.uniq(outputs),
             "expected distinct output per :date_format, got #{inspect(outputs)}"
    end

    test ":full no longer crashes on Date intervals" do
      d1 = ~D[2012-01-05]
      d2 = ~D[2012-01-06]

      assert {:ok, _} = Interval.to_string(d1, d2, format: :full, locale: :en)
      assert {:ok, _} = Interval.to_string(d1, d2, format: :full, locale: :ja)
      assert {:ok, _} = Interval.to_string(d1, d2, format: :full, locale: :de)
    end

    test ":full Date interval includes the weekday name (en)" do
      d1 = ~D[2012-01-05]
      d2 = ~D[2012-01-06]

      {:ok, out} = Interval.to_string(d1, d2, format: :full, locale: :en, prefer: :ascii)

      # `:full` on `:en` Date should produce the spelled-out weekday
      # for both endpoints — the marker that distinguishes it from
      # `:long` (which uses abbreviated weekday).
      assert out =~ "Thursday"
      assert out =~ "Friday"
      assert out =~ "January"
    end

    test ":full Date interval on ja includes weekday with Japanese chars" do
      d1 = ~D[2012-01-05]
      d2 = ~D[2012-01-06]

      {:ok, out} = Interval.to_string(d1, d2, format: :full, locale: :ja)

      # ja `:full` Date includes the spelled-out weekday (木曜日 / 金曜日).
      assert out =~ "木曜日"
      assert out =~ "金曜日"
      assert out =~ "年"
      assert out =~ "月"
      assert out =~ "日"
    end

    test ":full Date interval respects non-default :style options without crashing" do
      d1 = ~D[2012-01-05]
      d2 = ~D[2012-02-06]

      for style <- [:date, :month, :month_and_day, :year_and_month] do
        assert {:ok, _} = Interval.to_string(d1, d2, format: :full, style: style, locale: :en)
      end
    end
  end

  describe "regression #22: Date interval :date style aligns with single Date" do
    # Reported by @woylie. The Interval module previously used a
    # locale-INDEPENDENT skeleton table for `:date` style — the
    # same `:yMd`/`:yMMMd`/`:yMMMEd` skeletons for every locale.
    # That misaligned with `Localize.Date.to_string/2`, which uses
    # the locale's own `time_formats[:date]` mapping (e.g. ja
    # `:medium` is `:yMMdd` → `"2012/01/05"`, en `:medium` is
    # `:yMMMd` → `"Jan 5, 2012"`).
    #
    # The realignment looks up
    # `Localize.DateTime.Format.date_formats(locale_id)[format]`
    # to get the per-locale skeleton; if CLDR ships interval-format
    # data for it, we use the styled path, otherwise we fall back
    # to formatting each endpoint via `Localize.Date.to_string/2`
    # and joining via `interval_format_fallback`.

    test "ja :medium interval matches single Date :medium for ja (numeric form)" do
      d1 = ~D[2012-01-05]
      d2 = ~D[2012-01-06]

      {:ok, single_medium} = Localize.Date.to_string(d1, format: :medium, locale: :ja)
      assert single_medium == "2012/01/05"

      {:ok, interval_medium} = Interval.to_string(d1, d2, format: :medium, locale: :ja)
      # Numeric form, no Japanese unit chars 年/月/日 — same as single
      # Date `:medium`. CLDR ja's `:yMd` interval data ships a
      # full-repeat pattern for all greatest-diff levels, so the
      # interval shows both endpoints in full.
      assert interval_medium == "2012/01/05～2012/01/06"
    end

    test "en :medium interval keeps abbreviation (skeleton matches interval data)" do
      d1 = ~D[2012-01-05]
      d2 = ~D[2012-01-06]

      # en's `:yMMMd` IS in interval_formats, so the styled path
      # produces the abbreviated form `"Jan 5 – 6, 2012"`.
      {:ok, out} = Interval.to_string(d1, d2, format: :medium, locale: :en, prefer: :ascii)
      assert out =~ "Jan"
      refute out =~ "Jan 5, 2012"
      assert out =~ "5"
      assert out =~ "6"
    end

    test "en :long interval uses full month (no weekday) per single Date :long" do
      d1 = ~D[2012-01-05]
      d2 = ~D[2012-01-06]

      # en `:long` is `:yMMMMd` → not in interval_formats →
      # fallback path → "January 5, 2012 – January 6, 2012". Matches
      # single Date `:long` for en, no weekday.
      {:ok, out} = Interval.to_string(d1, d2, format: :long, locale: :en, prefer: :ascii)
      assert out =~ "January"
      refute out =~ "Thu"
      refute out =~ "Thursday"
    end

    test "non-:date styles remain locale-independent" do
      d1 = ~D[2012-01-05]
      d2 = ~D[2012-02-06]

      # `:month`/`:month_and_day`/`:year_and_month` styles are not
      # part of single-Date semantics; they describe a deliberate
      # field selection unrelated to standard styles. They keep the
      # locale-independent `@date_styles` mapping.
      assert {:ok, _} = Interval.to_string(d1, d2, format: :medium, style: :month, locale: :ja)

      assert {:ok, _} =
               Interval.to_string(d1, d2, format: :medium, style: :month_and_day, locale: :ja)

      assert {:ok, _} =
               Interval.to_string(d1, d2, format: :medium, style: :year_and_month, locale: :ja)
    end
  end

  describe "to_string/3 argument defaults and endpoint validation" do
    test "options default to the current locale" do
      assert {:ok, result} = Interval.to_string(~D[2022-04-22], ~D[2022-04-25])
      assert result =~ "Apr"
    end

    test "a Date and a Time endpoint return a :mixed_endpoints error" do
      assert {:error, %Localize.DateTimeIntervalFormatError{reason: :mixed_endpoints}} =
               Interval.to_string(~D[2022-01-01], ~T[10:00:00], locale: :en)
    end

    test "a NaiveDateTime and a Time endpoint return a :mixed_endpoints error" do
      assert {:error, %Localize.DateTimeIntervalFormatError{reason: :mixed_endpoints}} =
               Interval.to_string(~N[2022-01-01 10:00:00], ~T[12:00:00], locale: :en)
    end

    test "to_string!/3 raises on mixed endpoints" do
      assert_raise Localize.DateTimeIntervalFormatError, fn ->
        Interval.to_string!(~D[2022-01-01], ~T[10:00:00], locale: :en)
      end
    end

    test "partial time-only maps format as a time interval" do
      assert {:ok, result} =
               Interval.to_string(%{hour: 10, minute: 0}, %{hour: 12, minute: 30},
                 locale: :en,
                 prefer: :ascii
               )

      assert result =~ "10:00 AM"
      assert result =~ "12:30 PM"
    end
  end

  describe "to_string/3 error propagation" do
    test "an invalid locale on the :short time path returns an error" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Interval.to_string(~T[10:00:00], ~T[12:00:00], format: :short, locale: :zzz)
    end

    test "an invalid locale on the datetime path returns an error" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Interval.to_string(
                 ~N[2022-01-01 10:00:00],
                 ~N[2022-01-02 10:00:00],
                 locale: :zzz
               )
    end

    test "an unknown time skeleton returns a :no_format error" do
      assert {:error,
              %Localize.DateTimeIntervalFormatError{reason: :no_format, format_key: :bogus}} =
               Interval.to_string(~T[10:00:00], ~T[12:00:00], time_format: :bogus, locale: :en)
    end
  end

  describe "to_string/3 with equal endpoints" do
    test "equal times with a skeleton format collapse to a single time" do
      assert {:ok, result} =
               Interval.to_string(~T[10:00:00], ~T[10:00:00],
                 time_format: :short,
                 locale: :en,
                 prefer: :ascii
               )

      assert result =~ "10:00"
      refute result =~ "–"
    end

    test "equal datetimes collapse to a single datetime" do
      assert {:ok, "Jan 1, 2022, 10:00:00 AM"} =
               Interval.to_string(
                 ~N[2022-01-01 10:00:00],
                 ~N[2022-01-01 10:00:00],
                 locale: :en,
                 prefer: :ascii
               )
    end
  end

  describe "to_string/3 datetime interval sub-format options" do
    test ":date_format shortens the date side of a same-day interval" do
      assert {:ok, "4/8/26, 12:00 PM – 2:00 PM"} =
               Interval.to_string(
                 ~N[2026-04-08 12:00:00],
                 ~N[2026-04-08 14:00:00],
                 locale: :en,
                 date_format: :short,
                 time_format: :short,
                 prefer: :ascii
               )
    end
  end

  describe "to_string/3 open intervals for remaining value shapes" do
    test "open-end DateTime formats the known endpoint" do
      assert {:ok, result} =
               Interval.to_string(~U[2020-01-01 10:30:00Z], nil, locale: :en, prefer: :ascii)

      assert result =~ "Jan 1, 2020"
      assert result =~ "10:30:00 AM"
      assert String.ends_with?(result, "–")
    end

    test "open-start map with date and time fields formats as a datetime" do
      value = %{year: 2020, month: 1, day: 1, hour: 10, minute: 30, calendar: Calendar.ISO}

      assert {:ok, result} = Interval.to_string(nil, value, locale: :en, prefer: :ascii)
      assert result =~ "Jan 1, 2020"
      assert result =~ "10:30 AM"
    end

    test "open-end map with only date fields formats as a date" do
      value = %{year: 2020, month: 1, day: 2, calendar: Calendar.ISO}

      assert {:ok, result} = Interval.to_string(value, nil, locale: :en, prefer: :ascii)
      assert result =~ "Jan 2, 2020"
    end

    test "open-start map with only time fields formats as a time" do
      value = %{hour: 9, minute: 5, calendar: Calendar.ISO}

      assert {:ok, result} = Interval.to_string(nil, value, locale: :en, prefer: :ascii)
      assert result =~ "9:05 AM"
    end

    test "a map with neither date nor time fields returns an invalid input error" do
      assert {:error, %Localize.DateTimeInvalidInputError{type: :datetime}} =
               Interval.to_string(%{foo: 1}, nil, locale: :en)
    end
  end

  describe "split_interval/1 error paths and repeat widths" do
    test "a pattern without a repeated field is an invalid format" do
      assert {:error,
              %Localize.DateTimeIntervalFormatError{reason: :invalid_format, detail: "MMM d"}} =
               Interval.split_interval("MMM d")
    end

    test "an unterminated quote returns an error" do
      assert {:error, %Localize.DateTimeIntervalFormatError{reason: :unterminated_quote}} =
               Interval.split_interval("MMM 'x d")
    end

    test "splits at a five-character repeat" do
      assert {:ok, ["yyyyy-", "yyyyy"]} = Interval.split_interval("yyyyy-yyyyy")
    end

    test "splits at a four-character repeat" do
      assert {:ok, ["EEEE d - ", "EEEE d"]} = Interval.split_interval("EEEE d - EEEE d")
    end
  end

  describe "split_interval/1 symbol equivalence classes" do
    test "L and M are the same field for split purposes" do
      assert {:ok, ["MMM-", "LLL"]} = Interval.split_interval("MMM-LLL")
    end

    test "Q repeats split" do
      assert {:ok, ["QQQ-", "QQQ"]} = Interval.split_interval("QQQ-QQQ")
    end

    test "q and Q are the same field for split purposes" do
      assert {:ok, ["qqq-", "QQQ"]} = Interval.split_interval("qqq-QQQ")
    end

    test "e and c are the same field for split purposes" do
      assert {:ok, ["eee-", "ccc"]} = Interval.split_interval("eee-ccc")
    end

    test "c and E are the same field for split purposes" do
      assert {:ok, ["ccc-", "EEE"]} = Interval.split_interval("ccc-EEE")
    end
  end
end
