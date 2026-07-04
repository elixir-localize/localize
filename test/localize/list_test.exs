defmodule Localize.ListTest do
  use ExUnit.Case, async: true

  doctest Localize.List

  alias Localize.List, as: ListFormatter

  describe "to_string/2" do
    test "formats empty list" do
      assert {:ok, ""} = ListFormatter.to_string([], locale: :en)
    end

    test "formats single element" do
      assert {:ok, "a"} = ListFormatter.to_string(["a"], locale: :en)
    end

    test "formats two elements" do
      assert {:ok, "a and b"} = ListFormatter.to_string(["a", "b"], locale: :en)
    end

    test "formats three elements" do
      assert {:ok, "a, b, and c"} = ListFormatter.to_string(["a", "b", "c"], locale: :en)
    end

    test "formats many elements" do
      assert {:ok, "1, 2, 3, 4, 5, and 6"} =
               ListFormatter.to_string([1, 2, 3, 4, 5, 6], locale: :en)
    end

    test "formats with :or list_style" do
      assert {:ok, "a, b, or c"} =
               ListFormatter.to_string(["a", "b", "c"], locale: :en, list_style: :or)
    end

    test "formats with :unit_narrow list_style" do
      assert {:ok, "a b c"} =
               ListFormatter.to_string(["a", "b", "c"], locale: :en, list_style: :unit_narrow)
    end

    test "formats in French" do
      assert {:ok, "a, b et c"} = ListFormatter.to_string(["a", "b", "c"], locale: :fr)
    end

    test "treat_middle_as_end option" do
      # With 2 elements and treat_middle_as_end: true, uses :start pattern
      assert {:ok, result} =
               ListFormatter.to_string([1, 2], locale: :en, treat_middle_as_end: true)

      # Should use comma format instead of "and"
      assert result == "1, 2"
    end
  end

  describe "to_string/2 — locale-aware element formatting" do
    test "large integers get locale-appropriate grouping in :en" do
      assert {:ok, "1,234 and 5,678"} = ListFormatter.to_string([1234, 5678], locale: :en)
    end

    test "large integers get locale-appropriate grouping in :de" do
      assert {:ok, "1.234 und 5.678"} = ListFormatter.to_string([1234, 5678], locale: :de)
    end

    test "floats are formatted with the locale's decimal separator" do
      assert {:ok, "1,234.5 and 5,678.9"} =
               ListFormatter.to_string([1234.5, 5678.9], locale: :en)

      assert {:ok, "1.234,5 und 5.678,9"} =
               ListFormatter.to_string([1234.5, 5678.9], locale: :de)
    end

    test "Date elements are formatted with the locale's calendar pattern" do
      assert {:ok, "Jul 10, 2025 and Aug 15, 2025"} =
               ListFormatter.to_string([~D[2025-07-10], ~D[2025-08-15]], locale: :en)
    end

    test "Localize.Unit elements are formatted with the locale" do
      {:ok, km} = Localize.Unit.new(42, "kilometer")
      {:ok, kg} = Localize.Unit.new(3, "kilogram")

      assert {:ok, "42 kilometers and 3 kilograms"} =
               ListFormatter.to_string([km, kg], locale: :en)
    end

    test "atoms fall through to Kernel.to_string for backwards compatibility" do
      assert {:ok, "foo and bar"} = ListFormatter.to_string([:foo, :bar], locale: :en)
    end

    test "currency option propagates to numeric elements" do
      assert {:ok, "$1,234.56 and $5,678.90"} =
               ListFormatter.to_string([1234.56, 5678.90], locale: :en, currency: :USD)
    end

    test "list-specific options (:list_style, :treat_middle_as_end) are stripped before per-element formatting" do
      # `:list_style` selects the `:or` list pattern. It is not
      # forwarded to per-element formatters because it has no
      # meaning to `Localize.Number.to_string/2`.
      assert {:ok, "1,234, 5,678, or 9,012"} =
               ListFormatter.to_string([1234, 5678, 9012], locale: :en, list_style: :or)
    end

    test ":format option propagates to per-element date formatting" do
      # After the :format -> :list_style rename, `:format` is no
      # longer a list option and is forwarded to per-element
      # formatters. A list of dates with `format: :long` produces
      # the locale's long date pattern for every element.
      dates = [~D[2025-07-10], ~D[2025-08-15]]

      assert {:ok, "July 10, 2025 and August 15, 2025"} =
               ListFormatter.to_string(dates, locale: :en, format: :long)
    end

    test "strings still pass through unchanged" do
      assert {:ok, "a, b, and c"} = ListFormatter.to_string(["a", "b", "c"], locale: :en)
    end

    test "mixed list of types is formatted with one locale" do
      {:ok, unit} = Localize.Unit.new(42, "kilometer")

      assert {:ok, formatted} =
               ListFormatter.to_string([1234.5, ~D[2025-07-10], unit], locale: :de)

      # The exact German output combines `:de`-formatted number,
      # date, and unit with the German list conjunction "und".
      # Default date format is `:medium` which renders as "10.07.2025".
      assert String.contains?(formatted, "1.234,5")
      assert String.contains?(formatted, "10.07.2025")
      assert String.contains?(formatted, "Kilometer")
      assert String.contains?(formatted, "und")
    end
  end

  describe "intersperse/2" do
    test "intersperses two elements" do
      assert {:ok, [1, " and ", 2]} = ListFormatter.intersperse([1, 2], locale: :en)
    end

    test "intersperses three elements" do
      assert {:ok, ["a", ", ", "b", ", and ", "c"]} =
               ListFormatter.intersperse(["a", "b", "c"], locale: :en)
    end

    test "intersperses with unit_narrow list_style" do
      assert {:ok, ["a", " ", "b", " ", "c"]} =
               ListFormatter.intersperse(["a", "b", "c"], locale: :en, list_style: :unit_narrow)
    end
  end

  describe "to_string!/2" do
    test "returns string directly" do
      assert "a, b, and c" =
               ListFormatter.to_string!(["a", "b", "c"], locale: :en)
    end
  end

  describe "intersperse!/2" do
    test "returns list directly" do
      assert ["a", ", ", "b", ", and ", "c"] =
               ListFormatter.intersperse!(["a", "b", "c"], locale: :en)
    end
  end

  describe "list_patterns_for/1" do
    test "returns patterns for locale" do
      {:ok, patterns} = ListFormatter.list_patterns_for(:en)
      assert is_map(patterns)
      assert Map.has_key?(patterns, :standard)
      assert %Localize.List.Pattern{} = patterns.standard
    end
  end

  describe "list_styles_for/1" do
    test "returns list style names for locale" do
      assert {:ok, styles} = ListFormatter.list_styles_for(:en)
      assert :standard in styles
      assert :or in styles
      assert :unit_narrow in styles
    end
  end

  describe "error handling" do
    test "invalid list_style returns error" do
      assert {:error, _exception} =
               ListFormatter.to_string(["a"], locale: :en, list_style: :nonexistent)
    end

    test "invalid list_style error identifies the value and context" do
      assert {:error, %Localize.InvalidValueError{} = exception} =
               ListFormatter.to_string(["a"], locale: :en, list_style: :nonexistent)

      assert exception.value == :nonexistent
      assert exception.context == "Localize.List"
    end

    test "invalid locale returns error from to_string/2" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               ListFormatter.to_string(["a"], locale: "no-such-locale-xx")
    end

    test "invalid locale returns error from intersperse/2" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               ListFormatter.intersperse(["a", "b"], locale: "no-such-locale-xx")
    end

    test "invalid locale returns error from list_patterns_for/1" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               ListFormatter.list_patterns_for("qq-ZX")
    end

    test "invalid locale returns error from list_styles_for/1" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               ListFormatter.list_styles_for(12_345)
    end

    test "to_string!/2 raises on an invalid list_style" do
      assert_raise Localize.InvalidValueError, fn ->
        ListFormatter.to_string!(["a"], locale: :en, list_style: :nonexistent)
      end
    end

    test "intersperse!/2 raises on an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        ListFormatter.intersperse!(["a", "b"], locale: "no-such-locale-xx")
      end
    end

    test "an empty list skips option validation" do
      # `intersperse/2` short-circuits on `[]` before options are
      # normalized, so even an invalid style formats successfully.
      assert {:ok, ""} = ListFormatter.to_string([], locale: :en, list_style: :nonexistent)
      assert {:ok, []} = ListFormatter.intersperse([], locale: :en, list_style: :nonexistent)
    end
  end

  describe "intersperse/2 element counts and options" do
    test "intersperses an empty list" do
      assert {:ok, []} = ListFormatter.intersperse([], locale: :en)
    end

    test "intersperses a single element unchanged" do
      assert {:ok, ["a"]} = ListFormatter.intersperse(["a"], locale: :en)
    end

    test "intersperses four elements" do
      assert {:ok, ["a", ", ", "b", ", ", "c", ", and ", "d"]} =
               ListFormatter.intersperse(["a", "b", "c", "d"], locale: :en)
    end

    test "treat_middle_as_end uses the start pattern for two elements" do
      assert {:ok, ["a", ", ", "b"]} =
               ListFormatter.intersperse(["a", "b"], locale: :en, treat_middle_as_end: true)

      assert {:ok, "a, b"} =
               ListFormatter.to_string(["a", "b"], locale: :en, treat_middle_as_end: true)
    end

    test "treat_middle_as_end uses the middle pattern for the last pair of three" do
      assert {:ok, ["a", ", ", "b", ", ", "c"]} =
               ListFormatter.intersperse(["a", "b", "c"], locale: :en, treat_middle_as_end: true)
    end
  end

  describe "custom Localize.List.Pattern as list_style" do
    test "formats using a caller-supplied pattern" do
      {:ok, pattern} =
        Localize.List.Pattern.new(
          two: "{0}+{1}",
          start: "{0};{1}",
          middle: "{0};{1}",
          end: "{0}+{1}"
        )

      assert {:ok, "a;b+c"} =
               ListFormatter.to_string(["a", "b", "c"], locale: :en, list_style: pattern)

      assert {:ok, "a+b"} =
               ListFormatter.to_string(["a", "b"], locale: :en, list_style: pattern)
    end
  end

  describe "known_list_styles/0" do
    test "returns the full sorted set of styles" do
      assert ListFormatter.known_list_styles() == [
               :or,
               :or_narrow,
               :or_short,
               :standard,
               :standard_narrow,
               :standard_short,
               :unit,
               :unit_narrow,
               :unit_short
             ]
    end
  end
end
