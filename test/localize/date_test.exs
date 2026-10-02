defmodule Localize.DateTest do
  use ExUnit.Case, async: true

  doctest Localize.Date

  describe "to_string/2 with standard formats" do
    test "medium format (default)" do
      assert {:ok, "Jul 10, 2017"} = Localize.Date.to_string(~D[2017-07-10], locale: :en)
    end

    test "full format" do
      assert {:ok, "Monday, July 10, 2017"} =
               Localize.Date.to_string(~D[2017-07-10], format: :full, locale: :en)
    end

    test "short format" do
      assert {:ok, "7/10/17"} =
               Localize.Date.to_string(~D[2017-07-10], format: :short, locale: :en)
    end

    test "long format" do
      assert {:ok, "July 10, 2017"} =
               Localize.Date.to_string(~D[2017-07-10], format: :long, locale: :en)
    end
  end

  describe "to_string/2 with locales" do
    test "German locale" do
      assert {:ok, "12.06.2019"} = Localize.Date.to_string(~D[2019-06-12], locale: :de)
    end

    test "French short format" do
      assert {:ok, "10/07/2017"} =
               Localize.Date.to_string(~D[2017-07-10], format: :short, locale: :fr)
    end

    test "French medium format" do
      assert {:ok, "10 juil. 2017"} =
               Localize.Date.to_string(~D[2017-07-10], locale: :fr)
    end
  end

  describe "to_string/2 with format patterns" do
    test "custom format string" do
      assert {:ok, "2017/7/10"} = Localize.Date.to_string(~D[2017-07-10], format: "y/M/d")
    end

    test "era format" do
      assert {:ok, result} = Localize.Date.to_string(~D[2024-07-06], format: "y/M/d G")
      assert String.contains?(result, "2024/7/6")
      assert String.contains?(result, "AD")
    end

    test "era variant format" do
      assert {:ok, result} =
               Localize.Date.to_string(~D[2024-07-06], format: "y/M/d G", era: :variant)

      assert String.contains?(result, "CE")
    end

    # `Calendar.ISO` has no weeks of its own, so its week numbers are the
    # locale's, numbered as TR35 numbers them from the locale's week data
    # (user, 2026-10-02): en's and ja's weeks begin on Sunday and week 1
    # holds 1 January; de's, fr's and en-GB's are ISO 8601's. The expected
    # values are ICU4C 78.3's, and Erlang's `:calendar.iso_week_number/1`
    # for the ISO 8601 locales. 2023-01-01, a Sunday, begins week 1 of 2023
    # in `en` and ends week 52 of 2022 in `de`.
    test "week fields are the locale's weeks for Calendar.ISO" do
      for locale <- [:en, :ja],
          {date, expected} <- [
            {~D[2023-01-01], "2023 1"},
            {~D[2023-01-02], "2023 1"},
            {~D[2022-12-31], "2022 53"},
            {~D[2024-12-29], "2025 1"},
            {~D[2027-01-01], "2027 1"}
          ] do
        assert Localize.Date.to_string(date, format: "Y w", locale: locale) == {:ok, expected},
               "#{locale} #{date}"
      end

      for locale <- [:de, :"en-GB", :fr],
          {date, expected} <- [
            {~D[2023-01-01], "2022 52"},
            {~D[2023-01-02], "2023 1"},
            {~D[2022-12-31], "2022 52"},
            {~D[2024-12-29], "2024 52"},
            {~D[2027-01-01], "2026 53"}
          ] do
        {year, week} = :calendar.iso_week_number(Date.to_erl(date))

        assert expected == "#{year} #{week}"

        assert Localize.Date.to_string(date, format: "Y w", locale: locale) == {:ok, expected},
               "#{locale} #{date}"
      end
    end

    # TR35 §Week of Year works this example: January 1, 1998 was a Thursday.
    # With weeks beginning on Monday and four days in week 1, "the values
    # reflecting ISO 8601", week 1 of 1998 runs from 29 December 1997 to
    # 4 January 1998. With weeks beginning on Sunday it runs from 4 January to
    # 10 January, and the first three days of 1998 are in week 53 of 1997:
    # Portugal's week data, Sunday and four days.
    test "week numbering follows TR35's worked example" do
      for locale <- [:"en-GB", :de, :fr],
          date <- [~D[1997-12-29], ~D[1998-01-01], ~D[1998-01-04]] do
        assert Localize.Date.to_string(date, format: "Y w", locale: locale) == {:ok, "1998 1"},
               "#{locale} #{date}"
      end

      for {date, expected} <- [
            {~D[1998-01-01], "1997 53"},
            {~D[1998-01-03], "1997 53"},
            {~D[1998-01-04], "1998 1"},
            {~D[1998-01-10], "1998 1"},
            {~D[1998-01-11], "1998 2"}
          ] do
        assert Localize.Date.to_string(date, format: "Y w", locale: :"pt-PT") == {:ok, expected},
               "#{date}"
      end
    end

    # `W` numbers a month's weeks as a year's are numbered, as TR35 says: a
    # week is the month's that holds at least the locale's fewest days of
    # it. February 2016 begins on a Monday. In `de`, whose weeks are ISO
    # 8601's, Monday 29 February's week holds six days of March, so it is
    # week 1 of March. In `en`, whose weeks begin on Sunday and hold one day,
    # 1 February is in the week that began on 31 January, week 1, and Sunday
    # 28 February begins a week holding five days of March, week 1 of March.
    test "week of month is the locale's for Calendar.ISO" do
      for {locale, weeks} <- [
            de: [{~D[2016-02-01], "1"}, {~D[2016-02-15], "3"}, {~D[2016-02-28], "4"}],
            de: [{~D[2016-02-29], "1"}, {~D[2016-03-06], "1"}, {~D[2016-03-07], "2"}],
            en: [{~D[2016-02-01], "1"}, {~D[2016-02-15], "3"}, {~D[2016-02-27], "4"}],
            en: [{~D[2016-02-28], "1"}, {~D[2016-02-29], "1"}, {~D[2016-03-06], "2"}]
          ],
          {date, expected} <- weeks do
        assert Localize.Date.to_string(date, format: "W", locale: locale) == {:ok, expected},
               "#{locale} #{date}"
      end
    end

    test "BCE years render era-relative, not signed proleptic" do
      # TR35: the `y` field is the year of the era. ISO year -1 is
      # 2 BC and ISO year 0 is 1 BC — never "-1 BC" or "0 BC".
      minus_one = %Date{year: -1, month: 6, day: 15, calendar: Calendar.ISO}
      zero = %Date{year: 0, month: 6, day: 15, calendar: Calendar.ISO}

      assert {:ok, "2 BC"} = Localize.Date.to_string(minus_one, format: "y G")
      assert {:ok, "1 BC"} = Localize.Date.to_string(zero, format: "y G")
      assert {:ok, "2023 AD"} = Localize.Date.to_string(~D[2023-06-15], format: "y G")
    end
  end

  describe "to_string/2 with partial dates" do
    test "year and month" do
      # With no format the default, `:medium`, applies: an abbreviated month.
      assert {:ok, "Jun 2024"} = Localize.Date.to_string(%{year: 2024, month: 6}, locale: :en)
    end

    test "year and month with skeleton" do
      assert {:ok, "Jun 2024"} =
               Localize.Date.to_string(%{year: 2024, month: 6}, format: :yMMM, locale: :en)
    end

    test "year and month in French" do
      assert {:ok, "juin 2024"} =
               Localize.Date.to_string(%{year: 2024, month: 6}, format: :yMMM, locale: :fr)
    end

    test "month and day" do
      assert {:ok, "6/15"} =
               Localize.Date.to_string(%{month: 6, day: 15}, format: :Md, locale: :en)
    end

    test "year only" do
      assert {:ok, "2024"} =
               Localize.Date.to_string(%{year: 2024}, format: :y, locale: :en)
    end

    test "a standard format derives the skeleton from the fields present" do
      # en `yM` is "M/y", `yMMM` "MMM y" and `yMMMM` "MMMM y"; de `Md` is
      # "d.M." and `MMMMd` "d. MMMM".
      year_month = %{year: 2024, month: 6}

      assert {:ok, "6/2024"} = Localize.Date.to_string(year_month, format: :short, locale: :en)
      assert {:ok, "Jun 2024"} = Localize.Date.to_string(year_month, format: :medium, locale: :en)
      assert {:ok, "June 2024"} = Localize.Date.to_string(year_month, format: :long, locale: :en)
      assert {:ok, "June 2024"} = Localize.Date.to_string(year_month, format: :full, locale: :en)

      assert {:ok, "15.6."} =
               Localize.Date.to_string(%{month: 6, day: 15}, format: :short, locale: :de)

      assert {:ok, "15. Juni"} =
               Localize.Date.to_string(%{month: 6, day: 15}, format: :long, locale: :de)
    end

    test "derive_format_id/2 produces canonical order with the format's month width" do
      assert :yMMM = Localize.Date.derive_format_id(%{year: 2024, month: 6})
      assert :MMMd = Localize.Date.derive_format_id(%{month: 6, day: 15})
      assert :yMd = Localize.Date.derive_format_id(%{year: 2024, month: 6, day: 15}, :short)
      assert :yMMMMd = Localize.Date.derive_format_id(%{year: 2024, month: 6, day: 15}, :long)
      assert :d = Localize.Date.derive_format_id(%{day: 15}, :full)
    end
  end

  describe "to_string/2 with skeleton formats" do
    test "yMMMd skeleton" do
      assert {:ok, "Jul 10, 2017"} =
               Localize.Date.to_string(~D[2017-07-10], format: :yMMMd, locale: :en)
    end

    test "yMMMEd skeleton" do
      assert {:ok, result} =
               Localize.Date.to_string(~D[2017-07-10], format: :yMMMEd, locale: :en)

      assert String.contains?(result, "Mon")
      assert String.contains?(result, "Jul")
    end

    test "MMMd skeleton" do
      assert {:ok, "Jul 10"} =
               Localize.Date.to_string(~D[2017-07-10], format: :MMMd, locale: :en)
    end

    test "yMd skeleton" do
      assert {:ok, "7/10/2017"} =
               Localize.Date.to_string(~D[2017-07-10], format: :yMd, locale: :en)
    end

    test "Ed skeleton" do
      assert {:ok, result} =
               Localize.Date.to_string(~D[2017-07-10], format: :Ed, locale: :en)

      assert String.contains?(result, "Mon")
      assert String.contains?(result, "10")
    end

    test "skeleton in French" do
      assert {:ok, "10 juil. 2017"} =
               Localize.Date.to_string(~D[2017-07-10], format: :yMMMd, locale: :fr)
    end

    test "skeleton in German" do
      assert {:ok, result} =
               Localize.Date.to_string(~D[2017-07-10], format: :yMMMd, locale: :de)

      assert String.contains?(result, "Juli")
    end
  end

  describe "to_string/2 with Unicode/ASCII preference" do
    test "ascii preference" do
      # Date formats shouldn't differ much between unicode/ascii but test it works
      assert {:ok, _result} =
               Localize.Date.to_string(~D[2017-07-10], locale: :en, prefer: :ascii)
    end
  end

  describe "to_string/2 error handling" do
    test "non-date map returns error" do
      assert {:error, %Localize.DateTimeInvalidInputError{}} =
               Localize.Date.to_string(%{foo: :bar})
    end

    test "string input returns error" do
      assert {:error, %Localize.DateTimeInvalidInputError{}} =
               Localize.Date.to_string("not a date")
    end

    test "invalid skeleton returns error" do
      assert {:error, _} =
               Localize.Date.to_string(~D[2017-07-10], format: :zzzzz, locale: :en)
    end
  end

  describe "to_string!/2" do
    test "returns string directly" do
      assert "Jul 10, 2017" = Localize.Date.to_string!(~D[2017-07-10], locale: :en)
    end

    test "partial date bang" do
      assert "juin 2024" =
               Localize.Date.to_string!(%{year: 2024, month: 6}, format: :yMMM, locale: :fr)
    end

    test "raises on error" do
      # `apply/3` is type-opaque so the Elixir 1.20 type checker does
      # not flag this deliberate contract-violation test.
      assert_raise Localize.DateTimeInvalidInputError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(Localize.Date, :to_string!, [%{foo: :bar}])
      end
    end
  end

  describe "to_string/2 — skeleton fallback for non-Gregorian calendars" do
    # Regression: `:yMMMM` (or any skeleton not in the
    # locale's calendar `available_formats`) used to
    # infinite-loop via `Match.best_match/3` falling back to
    # gregorian patterns and `resolve_skeleton` re-looking-up
    # in the original calendar where the skeleton still
    # wasn't found. `best_match` now receives the calendar
    # explicitly and `resolve_skeleton` carries a `seen` set
    # to terminate any degenerate match cycle. Without the
    # fix this test timed out at 60s.
    test "skeleton :yMMMM under ja-JP locale terminates instead of looping" do
      # Pre-fix this hung indefinitely (60s ExUnit timeout).
      # Locales used by tests are pre-downloaded in
      # `test/test_helper.exs`, so the call here only
      # exercises the formatter / skeleton-resolution path.
      start = System.monotonic_time(:millisecond)
      result = Localize.Date.to_string(~D[2024-07-01], locale: :"ja-JP", format: :yMMMM)
      elapsed = System.monotonic_time(:millisecond) - start

      assert {:ok, _} = result
      # Generous bound: the regression this guards against looped
      # indefinitely (60s ExUnit timeout); slow CI runners have
      # exceeded 1s on the healthy path.
      assert elapsed < 10_000, "expected under 10s, got #{elapsed}ms"
    end

    test "number_system override transliterates numeric fields" do
      # `Localize.DateTime.Format.number_system_overrides/4`
      # extracts the CLDR `:number_system` companion from
      # variant maps; the formatter applies it per-field.
      # Test directly against the formatter with a numeric
      # system (`:arab`) since we control the override map
      # without needing a calendar that ships one.
      opts = %{number_system_overrides: %{"all" => :arab}}

      assert {:ok, "٢٠٢٤ ٠٧ ٠١"} =
               Localize.DateTime.Formatter.format(~D[2024-07-01], "yyyy MM dd", :"ar-SA", opts)
    end

    test "number_system override on one field only" do
      opts = %{number_system_overrides: %{"y" => :arab}}

      # Year transliterated, month/day stay ASCII.
      assert {:ok, "٢٠٢٤ 07 01"} =
               Localize.DateTime.Formatter.format(~D[2024-07-01], "yyyy MM dd", :en, opts)
    end

    test "algorithmic number_system applies via RBNF rule lookup" do
      # `:hebr` resolves to the `hebrew` RBNF rule via
      # `numberingSystems.json` `_rules: "hebrew"`. The
      # `:hebrew` rule lives in `:und`'s NumberingSystemRules.
      opts = %{number_system_overrides: %{"all" => :hebr}}

      # 2024 in Hebrew numerals is ב׳כ״ד; the `y` token plus the
      # override should render Hebrew letters in the year slot.
      assert {:ok, year_string} =
               Localize.DateTime.Formatter.format(~D[2024-07-01], "y", :he, opts)

      assert year_string != "2024"
      assert String.printable?(year_string)
    end

    test "jpanyear renders 元年 for Reiwa year 1" do
      # `:jpanyear` resolves to
      # `ja/SpelloutRules/spellout-numbering-year-latn`. Year 1
      # in this rule set renders as 元 (gan), not "1".
      opts = %{number_system_overrides: %{"y" => :jpanyear}}

      assert {:ok, "元"} =
               Localize.DateTime.Formatter.format(
                 %{year: 1, month: 1, day: 1, calendar: Calendar.ISO},
                 "y",
                 :"ja-JP",
                 opts
               )
    end

    test "Localize.DateTime.Format.number_system_overrides/4 extracts CLDR data" do
      # Hebrew dates carry an "all" → :hebr override.
      assert %{"all" => :hebr} =
               Localize.DateTime.Format.number_system_overrides(
                 :date,
                 :medium,
                 :"he-IL",
                 :hebrew
               )

      # Japanese imperial carries a "y" → :jpanyear override.
      assert %{"y" => :jpanyear} =
               Localize.DateTime.Format.number_system_overrides(
                 :date,
                 :medium,
                 :"ja-JP",
                 :japanese
               )

      # Gregorian formats don't carry any.
      assert %{} ==
               Localize.DateTime.Format.number_system_overrides(
                 :date,
                 :medium,
                 :en,
                 :gregorian
               )
    end

    test "skeleton :yMMMM falls back to gregorian patterns when calendar lacks it" do
      # Japanese calendar's `available_formats` doesn't carry
      # the bare `:yMMMM` skeleton (every Japanese skeleton
      # has the `G` era marker prefix). Falling back to
      # gregorian's `"MMMM y"` pattern is the correct
      # behaviour — the formatter's `y` token still pulls
      # the calendar-correct year from `date.calendar`.
      assert {:ok, "July 2017"} =
               Localize.Date.to_string(~D[2017-07-10], locale: :en, format: :yMMMM)
    end
  end

  describe "to_string/2 with a locale default numbering system" do
    test "numeric date and time fields use the locale's default numbering system" do
      assert {:ok, "१५ मार्च, २०२१"} =
               Localize.Date.to_string(~D[2021-03-15], format: :long, locale: :mr)

      assert {:ok, "३:००:०० AM"} =
               Localize.Time.to_string(~T[03:00:00], format: :medium, locale: :mr)
    end

    test "a caller \"all\" override wins over the locale default" do
      assert {:ok, "15 मार्च, 2021"} =
               Localize.Date.to_string(~D[2021-03-15],
                 format: :long,
                 locale: :mr,
                 number_system_overrides: %{"all" => :latn}
               )
    end

    test "an \"all\" override reaches the time fields" do
      assert {:ok, "०३:०९:०५"} =
               Localize.DateTime.Formatter.format(~T[03:09:05], "HH:mm:ss", :en, %{
                 number_system_overrides: %{"all" => :deva}
               })
    end

    test "a -u-nu- locale extension wins over the locale default" do
      assert {:ok, "15 मार्च, 2021"} =
               Localize.Date.to_string(~D[2021-03-15], format: :long, locale: "mr-u-nu-latn")

      assert {:ok, "3:00:00 AM"} =
               Localize.Time.to_string(~T[03:00:00], format: :medium, locale: "mr-u-nu-latn")
    end

    test "a -u-nu- locale extension applies a non-default numbering system" do
      assert {:ok, "March १५, २०२१"} =
               Localize.Date.to_string(~D[2021-03-15], format: :long, locale: "en-u-nu-deva")
    end

    test "a -u-nu- extension on the process locale is honoured" do
      # The process dictionary is per test process, so the locale
      # set here does not leak into other tests.
      Localize.put_locale("mr-u-nu-latn")

      assert {:ok, "15 मार्च, 2021"} =
               Localize.Date.to_string(~D[2021-03-15], format: :long)
    end
  end
end
