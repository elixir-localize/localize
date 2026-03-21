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

    test "formats with :or format" do
      assert {:ok, "a, b, or c"} =
               ListFormatter.to_string(["a", "b", "c"], locale: :en, format: :or)
    end

    test "formats with :unit_narrow format" do
      assert {:ok, "a b c"} =
               ListFormatter.to_string(["a", "b", "c"], locale: :en, format: :unit_narrow)
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

  describe "intersperse/2" do
    test "intersperses two elements" do
      assert {:ok, [1, " and ", 2]} = ListFormatter.intersperse([1, 2], locale: :en)
    end

    test "intersperses three elements" do
      assert {:ok, ["a", ", ", "b", ", and ", "c"]} =
               ListFormatter.intersperse(["a", "b", "c"], locale: :en)
    end

    test "intersperses with unit_narrow format" do
      assert {:ok, ["a", " ", "b", " ", "c"]} =
               ListFormatter.intersperse(["a", "b", "c"], locale: :en, format: :unit_narrow)
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

  describe "list_formats_for/1" do
    test "returns format names for locale" do
      assert {:ok, formats} = ListFormatter.list_formats_for(:en)
      assert :standard in formats
      assert :or in formats
      assert :unit_narrow in formats
    end
  end

  describe "error handling" do
    test "invalid format returns error" do
      assert {:error, _exception} =
               ListFormatter.to_string(["a"], locale: :en, format: :nonexistent)
    end
  end
end
