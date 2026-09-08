defmodule Localize.IntervalClosestMatchTest do
  use ExUnit.Case, async: true

  # TR35 §Interval Formats step 2: where no `intervalFormatItem` matches the
  # requested skeleton exactly, take the closest one, "adjusting the string
  # value field's width". Before this, a style whose skeleton was not a
  # literal key in the interval table fell straight to the final step and
  # glued two whole dates together — 1,814 of 2,628 `(locale, style)` pairs,
  # every one of which had a width-adjusted item available.
  #
  # Expectations here were taken from ICU (Node's
  # `Intl.DateTimeFormat.prototype.formatRange`) and then checked against the
  # CLDR 49 data, since ICU 77 ships older CLDR: where the two disagree on a
  # separator or a pattern, CLDR 49 is what we follow.

  @from ~D[2026-05-03]
  @to_day ~D[2026-05-05]
  @to_month ~D[2026-06-05]
  @to_year ~D[2027-06-05]

  describe "a style skeleton that is a width adjustment away from a shipped item" do
    # de's medium skeleton is `yMMdd`; the interval table has `yMd`, whose
    # `d` difference is "dd.–dd.MM.y". Previously "03.05.2026 – 05.05.2026".
    test "de medium uses the locale's interval pattern" do
      assert Localize.Interval.to_string(@from, @to_day, locale: :de) ==
               {:ok, "03.–05.05.2026"}
    end

    test "de medium across a month boundary" do
      assert Localize.Interval.to_string(@from, @to_month, locale: :de) ==
               {:ok, "03.05. – 05.06.2026"}
    end

    test "fr long compresses the shared month and year" do
      assert Localize.Interval.to_string(@from, @to_day, locale: :fr, format: :long) ==
               {:ok, "3–5 mai 2026"}
    end
  end

  describe "the matched pattern is adjusted to the requested widths" do
    # en long asks for `yMMMMd` and matches `yMMMd`, so the month has to be
    # widened back from "Jun" to "June"; en full asks for `yMMMMEEEEd` and
    # matches `yMMMEd`, widening the day name too.
    test "en long widens the abbreviated month of the matched pattern" do
      assert Localize.Interval.to_string(@from, @to_month, locale: :en, format: :long) ==
               {:ok, "May 3 – June 5, 2026"}
    end

    test "en full widens both the month and the day name" do
      assert Localize.Interval.to_string(@from, @to_day, locale: :en, format: :full) ==
               {:ok, "Sunday, May 3 – Tuesday, May 5, 2026"}
    end

    test "en short narrows the year to two digits" do
      assert Localize.Interval.to_string(@from, @to_day, locale: :en, format: :short) ==
               {:ok, "5/3/26 – 5/5/26"}
    end
  end

  describe "behaviour that must not change" do
    # A skeleton that is a literal key in the table still takes it directly.
    test "en medium is unaffected" do
      assert Localize.Interval.to_string(@from, @to_day, locale: :en) ==
               {:ok, "May 3 – 5, 2026"}
    end

    # The locale's own pattern wins even when it repeats the whole date.
    # CLDR 49 gives vi's `yMd` as "d/M/y – d/M/y" for every difference.
    test "a locale whose interval pattern repeats the date keeps it" do
      assert {:ok, formatted} =
               Localize.Interval.to_string(@from, @to_day, locale: :vi, format: :short)

      assert String.contains?(formatted, "2026 – ")
    end

    # Where the greatest difference is the year, most locales' patterns spell
    # both endpoints in full, so the output is unchanged by the match.
    test "a year difference still spells both endpoints" do
      assert Localize.Interval.to_string(@from, @to_year, locale: :de) ==
               {:ok, "03.05.2026 – 05.06.2027"}
    end
  end

  describe "a genuine miss still falls back" do
    # `best_interval_match/3` only accepts a candidate carrying the same
    # fields, so a skeleton with no field-compatible entry cannot silently
    # match an unrelated pattern; it takes the endpoint-formatting fallback.
    test "no field-compatible entry returns :error rather than a wrong match" do
      assert :error =
               Localize.DateTime.Format.Match.best_interval_match(:yMMMMEEEEdHmsvvvv, :en)
    end

    test "a compatible entry is found for a width-only difference" do
      assert {:ok, :yMd} = Localize.DateTime.Format.Match.best_interval_match(:yMMdd, :de)
    end
  end
end
