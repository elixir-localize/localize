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
