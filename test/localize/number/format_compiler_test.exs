defmodule Localize.Number.Format.CompilerTest do
  use ExUnit.Case, async: true

  doctest Localize.Number.Format.Compiler

  alias Localize.Number.Format.Compiler

  describe "parse/1" do
    test "parses a standard format" do
      assert {:ok, parsed} = Compiler.parse("#,##0.###")
      assert is_list(parsed)
      assert Keyword.has_key?(parsed, :positive)
      assert Keyword.has_key?(parsed, :negative)
    end

    test "parses a currency format" do
      assert {:ok, parsed} = Compiler.parse("¤#,##0.00")
      assert is_list(parsed)
    end

    test "parses a percent format" do
      assert {:ok, parsed} = Compiler.parse("#,##0%")
      positive = parsed[:positive]
      assert Keyword.has_key?(positive, :percent)
    end

    test "parses a format with positive and negative subpatterns" do
      assert {:ok, parsed} = Compiler.parse("¤ #,##0.00;¤-#,##0.00")
      assert parsed[:negative] != nil
    end

    test "returns error for empty string" do
      assert {:error, _} = Compiler.parse("")
    end

    test "returns error for nil" do
      assert {:error, _} = Compiler.parse(nil)
    end
  end

  describe "compile/1" do
    test "compiles a standard format to metadata" do
      assert {:ok, meta} = Compiler.compile("#,##0.###")
      assert meta.grouping.integer == %{first: 3, rest: 3}
      assert meta.fractional_digits == %{min: 0, max: 3}
    end

    test "compiles a percent format with multiplier" do
      assert {:ok, meta} = Compiler.compile("#,##0%")
      assert meta.multiplier == 100
    end

    test "compiles a scientific format" do
      assert {:ok, meta} = Compiler.compile("#E0")
      assert meta.exponent_digits > 0
    end
  end

  # TR35 scientific notation analysis. Engineering grouping is the count
  # of mantissa integer digits the exponent must be a multiple of, and
  # only applies when the pattern's max integer-digit count exceeds its
  # min. Phase 2 consumes these fields to do the actual mantissa shift.
  describe "compile/1 with scientific patterns" do
    test "0.###E0 is pure scientific (min == max == 1, no engineering grouping)" do
      assert {:ok, meta} = Compiler.compile("0.###E0")
      assert meta.exponent_digits == 1
      assert meta.integer_digits == %{min: 1, max: 1}
      assert meta.engineering_grouping == 0
    end

    test "##0.###E0 is engineering with grouping = 3" do
      assert {:ok, meta} = Compiler.compile("##0.###E0")
      assert meta.exponent_digits == 1
      assert meta.integer_digits == %{min: 1, max: 3}
      assert meta.engineering_grouping == 3
    end

    test "#0.###E0 is engineering with grouping = 2" do
      assert {:ok, meta} = Compiler.compile("#0.###E0")
      assert meta.integer_digits == %{min: 1, max: 2}
      assert meta.engineering_grouping == 2
    end

    test "00.###E0 is fixed-width mantissa (min == max == 2, no engineering grouping)" do
      assert {:ok, meta} = Compiler.compile("00.###E0")
      assert meta.integer_digits == %{min: 2, max: 2}
      assert meta.engineering_grouping == 0
    end

    test "min-exponent-digits flows through (E00 → 2)" do
      assert {:ok, meta} = Compiler.compile("##0.###E00")
      assert meta.exponent_digits == 2
      assert meta.engineering_grouping == 3
    end

    test "forced exponent sign flows through (E+0)" do
      assert {:ok, meta} = Compiler.compile("##0.###E+0")
      assert meta.exponent_sign == true
      assert meta.engineering_grouping == 3
    end

    test "significant-digit scientific patterns leave max_integer_digits at 0" do
      # TR35 forces these to a 1-integer-digit mantissa; the @ count is
      # not engineering grouping. The full transformation lands in Phase 5.
      assert {:ok, meta} = Compiler.compile("@@###E0")
      assert meta.integer_digits.max == 0
      assert meta.engineering_grouping == 0
    end

    test "non-scientific patterns keep max_integer_digits at 0 (no clipping)" do
      assert {:ok, meta} = Compiler.compile("##0.###")
      assert meta.integer_digits == %{min: 1, max: 0}
      assert meta.engineering_grouping == 0
    end
  end

  describe "format_to_metadata/1" do
    test "extracts metadata from a format string" do
      assert {:ok, meta} = Compiler.format_to_metadata("#,##0.###")
      assert meta.integer_digits.min == 1
      assert meta.fractional_digits.max == 3
    end

    test "extracts grouping from Indian format" do
      assert {:ok, meta} = Compiler.format_to_metadata("#,##,##0.###")
      assert meta.grouping.integer == %{first: 3, rest: 2}
    end
  end

  describe "number_match_regex/0" do
    test "returns a regex" do
      regex = Compiler.number_match_regex()
      assert is_struct(regex, Regex)
    end

    test "matches standard number formats" do
      regex = Compiler.number_match_regex()
      assert Regex.match?(regex, "#,##0.###")
    end
  end
end
