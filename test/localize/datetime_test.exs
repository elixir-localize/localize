defmodule Localize.DateTimeTest do
  use ExUnit.Case, async: true

  doctest Localize.DateTime

  describe "to_string/2 with standard formats" do
    test "medium format (default)" do
      assert {:ok, result} = Localize.DateTime.to_string(~N[2017-07-10 14:30:00], locale: :en)
      assert String.contains?(result, "Jul 10, 2017")
      assert String.contains?(result, "2:30:00")
      assert String.contains?(result, "PM")
    end

    test "short format" do
      assert {:ok, result} =
               Localize.DateTime.to_string(~N[2017-07-10 14:30:00], format: :short, locale: :en)

      assert String.contains?(result, "7/10/17")
      assert String.contains?(result, "2:30")
    end

    test "full format" do
      assert {:ok, result} =
               Localize.DateTime.to_string(~N[2017-07-10 14:30:00], format: :full, locale: :en)

      assert String.contains?(result, "Monday, July 10, 2017")
    end
  end

  describe "to_string/2 with separate date and time formats" do
    test "different date and time formats" do
      assert {:ok, result} =
               Localize.DateTime.to_string(~N[2024-07-07 21:36:00],
                 date_format: :short,
                 time_format: :medium,
                 locale: :en
               )

      assert String.contains?(result, "7/7/24")
      assert String.contains?(result, "9:36:00")
    end
  end

  describe "to_string/2 with locales" do
    test "French locale" do
      assert {:ok, result} = Localize.DateTime.to_string(~N[2017-07-10 14:30:00], locale: :fr)
      assert String.contains?(result, "juil.")
      assert String.contains?(result, "14:30:00")
    end
  end

  describe "to_string/2 with :variant / :standard locales" do
    # en-CA's `:yyMd` skeleton publishes both an ISO standard form
    # ("y-MM-dd") and a CLDR-marked variant form ("d/M/yy").
    # Regression: prior to teaching `:prefer` about variant/standard,
    # asking for `format: :short` on en-CA crashed because the
    # resolver only knew about `:unicode`/`:ascii`.
    test "en-CA short defaults to :standard pattern" do
      assert {:ok, result} =
               Localize.DateTime.to_string(~U[2026-04-30 19:42:26Z],
                 locale: "en-CA",
                 format: :short
               )

      assert String.contains?(result, "2026-04-30")
    end

    test "en-CA short with prefer: :variant returns the variant pattern" do
      assert {:ok, result} =
               Localize.DateTime.to_string(~U[2026-04-30 19:42:26Z],
                 locale: "en-CA",
                 format: :short,
                 prefer: :variant
               )

      assert String.contains?(result, "30/4/26")
    end

    test "en-CA short with prefer list across both alt axes" do
      assert {:ok, result} =
               Localize.DateTime.to_string(~U[2026-04-30 19:42:26Z],
                 locale: "en-CA",
                 format: :short,
                 prefer: [:variant, :ascii]
               )

      assert String.contains?(result, "30/4/26")
    end

    test "en-CA Date.to_string respects :prefer" do
      assert {:ok, "2026-04-30"} =
               Localize.Date.to_string(~D[2026-04-30], locale: "en-CA", format: :short)

      assert {:ok, "30/4/26"} =
               Localize.Date.to_string(~D[2026-04-30],
                 locale: "en-CA",
                 format: :short,
                 prefer: :variant
               )
    end
  end

  describe "to_string/2 with at-style formats" do
    test "long format uses at pattern" do
      {:ok, result} =
        Localize.DateTime.to_string(~N[2017-07-10 14:30:00],
          format: :long,
          locale: :en,
          prefer: :ascii
        )

      assert String.contains?(result, "July 10, 2017")
      assert String.contains?(result, "2:30:00 PM")
    end

    test "full format uses at pattern" do
      {:ok, result} =
        Localize.DateTime.to_string(~N[2017-07-10 14:30:00],
          format: :full,
          locale: :en,
          prefer: :ascii
        )

      assert String.contains?(result, "Monday, July 10, 2017")
    end
  end

  describe "to_string/2 with partial datetime" do
    test "date-only map delegates to Date" do
      assert {:ok, result} =
               Localize.DateTime.to_string(%{year: 2024, month: 6}, locale: :en)

      assert String.contains?(result, "2024")
    end

    test "time-only map delegates to Time" do
      assert {:ok, result} =
               Localize.DateTime.to_string(%{hour: 14, minute: 30},
                 format: :hm,
                 locale: :en,
                 prefer: :ascii
               )

      assert String.contains?(result, "2:30")
    end

    test "hour-only partial datetime renders both date and hour with AM/PM" do
      # Previously this silently dropped the hour by dispatching to
      # Localize.Date.to_string. Now it renders both portions and
      # composes via the locale's datetime wrapper.
      assert {:ok, "Jun 15, 2026, 12 AM"} =
               Localize.DateTime.to_string(
                 %{year: 2026, month: 6, day: 15, hour: 0, calendar: Calendar.ISO},
                 format: :medium,
                 locale: :en,
                 prefer: :ascii
               )

      assert {:ok, "Jun 15, 2026, 2 PM"} =
               Localize.DateTime.to_string(
                 %{year: 2026, month: 6, day: 15, hour: 14, calendar: Calendar.ISO},
                 format: :medium,
                 locale: :en,
                 prefer: :ascii
               )
    end

    test "hour+minute partial datetime omits the empty seconds slot" do
      # Previously the `:medium` full-time pattern `h:mm:ss a` was
      # used, leaving a trailing `:` where seconds should have
      # rendered. The partial path now derives the `:hm` skeleton.
      assert {:ok, "Jun 15, 2026, 2:30 PM"} =
               Localize.DateTime.to_string(
                 %{year: 2026, month: 6, day: 15, hour: 14, minute: 30, calendar: Calendar.ISO},
                 format: :medium,
                 locale: :en,
                 prefer: :ascii
               )
    end
  end

  describe "to_string/2 error handling" do
    test "empty map returns error" do
      assert {:error, %Localize.DateTimeInvalidInputError{}} =
               Localize.DateTime.to_string(%{foo: :bar})
    end
  end

  describe "to_string!/2" do
    test "returns string directly" do
      result = Localize.DateTime.to_string!(~N[2024-01-15 09:00:00], locale: :en)
      assert String.contains?(result, "Jan 15, 2024")
    end

    test "raises on error" do
      assert_raise Localize.DateTimeInvalidInputError, fn ->
        Localize.DateTime.to_string!(%{foo: :bar})
      end
    end
  end
end
