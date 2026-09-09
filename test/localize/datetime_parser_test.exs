defmodule Localize.DateTime.ParserTest do
  use ExUnit.Case, async: true

  doctest Localize.DateTime.Parser

  describe "Localize.DateTime.Parser.parse/2 — dispatch" do
    test "ISO date returns a Date" do
      assert {:ok, ~D[2026-05-16]} = Localize.DateTime.Parser.parse("2026-05-16", locale: :en)
    end

    test "locale-formatted date returns a Date" do
      assert {:ok, ~D[2026-05-16]} = Localize.DateTime.Parser.parse("5/16/26", locale: :en)
    end

    test "ISO time returns a Time" do
      assert {:ok, ~T[14:30:00]} = Localize.DateTime.Parser.parse("14:30:00", locale: :en)
    end

    test "12-hour time returns a Time" do
      assert {:ok, ~T[14:30:00]} = Localize.DateTime.Parser.parse("2:30 PM", locale: :en)
    end

    test "ISO datetime returns a NaiveDateTime" do
      assert {:ok, ~N[2026-05-16 14:30:00]} =
               Localize.DateTime.Parser.parse("2026-05-16T14:30:00", locale: :en)
    end

    test "locale-formatted datetime returns a NaiveDateTime" do
      assert {:ok, ~N[2026-05-16 14:30:00]} =
               Localize.DateTime.Parser.parse("May 16, 2026, 2:30 PM", locale: :en)
    end

    test "ISO datetime with Z offset returns a DateTime" do
      assert {:ok, %DateTime{}} =
               Localize.DateTime.Parser.parse("2026-05-16T14:30:00Z", locale: :en)
    end

    test "ISO range returns a Date.Range" do
      assert {:ok, %Date.Range{} = range} =
               Localize.DateTime.Parser.parse("2026-05-05 – 2026-05-10", locale: :en)

      assert range.first == ~D[2026-05-05]
      assert range.last == ~D[2026-05-10]
    end

    test "locale-formatted range returns a Date.Range" do
      assert {:ok, %Date.Range{} = range} =
               Localize.DateTime.Parser.parse("May 5, 2026 – May 10, 2026", locale: :en)

      assert range.first == ~D[2026-05-05]
      assert range.last == ~D[2026-05-10]
    end

    test "range with 'to' separator returns a Date.Range" do
      assert {:ok, %Date.Range{} = range} =
               Localize.DateTime.Parser.parse("May 5, 2026 to May 10, 2026", locale: :en)

      assert range.first == ~D[2026-05-05]
      assert range.last == ~D[2026-05-10]
    end
  end

  # Only the Gregorian half of the `:calendar` option can be exercised here.
  # The non-Gregorian cases need calendar modules that ship with
  # `calendrical`, and are covered by that package's own suite.
  describe "Localize.DateTime.Parser.parse/2 — calendar option" do
    test "calendar option accepts Calendar.ISO as alias for :gregorian" do
      assert {:ok, ~D[2026-05-16]} =
               Localize.DateTime.Parser.parse("2026-05-16", locale: :en, calendar: Calendar.ISO)
    end

    # A calendar whose module is not installed silently resolves to
    # `Calendar.ISO` — the behaviour this code has always had, since the
    # original mapping fell back the same way for any calendar it could not
    # resolve. Worth knowing: asking for `:hebrew` without `calendrical`
    # yields a Gregorian date rather than an error.
    test "a calendar whose module is absent falls back to Calendar.ISO" do
      assert {:ok, %Date{calendar: Calendar.ISO}} =
               Localize.DateTime.Parser.parse("2026-05-16", locale: :en, calendar: :hebrew)
    end
  end
end
