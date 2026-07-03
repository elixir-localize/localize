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
      assert {:ok, "6/2024"} = Localize.Date.to_string(%{year: 2024, month: 6}, locale: :en)
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

    test "standard format rejected for partial date" do
      result = Localize.Date.to_string(%{year: 2024, month: 6}, format: :medium, locale: :en)
      assert match?({:error, _}, result)
    end

    test "derive_format_id/1 produces canonical order" do
      assert :yM = Localize.Date.derive_format_id(%{year: 2024, month: 6})
      assert :Md = Localize.Date.derive_format_id(%{month: 6, day: 15})
      assert :yMd = Localize.Date.derive_format_id(%{year: 2024, month: 6, day: 15})
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
      assert elapsed < 1000, "expected under 1s, got #{elapsed}ms"
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
end
