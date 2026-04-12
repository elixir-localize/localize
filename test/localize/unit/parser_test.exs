defmodule Localize.Unit.ParserTest do
  use ExUnit.Case, async: true

  doctest Localize.Unit.Parser

  alias Localize.Unit.Parser

  # ── Simple base units ─────────────────────────────────────────────

  describe "simple base units" do
    test "parses meter" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("meter")

      assert single == {:single_unit, prefix: nil, power: nil, base: "meter"}
    end

    test "parses second" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("second")

      assert single == {:single_unit, prefix: nil, power: nil, base: "second"}
    end

    test "parses kilogram as base unit" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("kilogram")

      assert single == {:single_unit, prefix: nil, power: nil, base: "kilogram"}
    end
  end

  # ── SI prefix decomposition ──────────────────────────────────────

  describe "SI prefixed units" do
    test "parses kilometer" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("kilometer")

      assert single == {:single_unit, prefix: :kilo, power: nil, base: "meter"}
    end

    test "parses milligram" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("milligram")

      assert single == {:single_unit, prefix: :milli, power: nil, base: "gram"}
    end

    test "parses megawatt" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("megawatt")

      assert single == {:single_unit, prefix: :mega, power: nil, base: "watt"}
    end

    test "parses gigahertz" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("gigahertz")

      assert single == {:single_unit, prefix: :giga, power: nil, base: "hertz"}
    end

    test "parses kilobyte" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("kilobyte")

      assert single == {:single_unit, prefix: :kilo, power: nil, base: "byte"}
    end
  end

  # ── Power prefixed units ────────────────────────────────────────

  describe "power prefixed units" do
    test "parses square-meter" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("square-meter")

      assert single == {:single_unit, prefix: nil, power: :square, base: "meter"}
    end

    test "parses cubic-centimeter" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("cubic-centimeter")

      assert single == {:single_unit, prefix: :centi, power: :cubic, base: "meter"}
    end

    test "parses square-kilometer" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("square-kilometer")

      assert single == {:single_unit, prefix: :kilo, power: :square, base: "meter"}
    end
  end

  # ── Per units ───────────────────────────────────────────────────

  describe "per units" do
    test "parses meter-per-second" do
      assert {:ok, {:unit, type: nil, numerator: [num], denominator: [den]}} =
               Parser.parse("meter-per-second")

      assert num == {:single_unit, prefix: nil, power: nil, base: "meter"}
      assert den == {:single_unit, prefix: nil, power: nil, base: "second"}
    end

    test "parses kilogram-per-cubic-meter" do
      assert {:ok, {:unit, type: nil, numerator: [num], denominator: [den]}} =
               Parser.parse("kilogram-per-cubic-meter")

      assert num == {:single_unit, prefix: nil, power: nil, base: "kilogram"}
      assert den == {:single_unit, prefix: nil, power: :cubic, base: "meter"}
    end

    test "parses liter-per-kilometer" do
      assert {:ok, {:unit, type: nil, numerator: [num], denominator: [den]}} =
               Parser.parse("liter-per-kilometer")

      assert num == {:single_unit, prefix: nil, power: nil, base: "liter"}
      assert den == {:single_unit, prefix: :kilo, power: nil, base: "meter"}
    end
  end

  # ── Leading per ─────────────────────────────────────────────────

  describe "leading per" do
    test "parses per-second" do
      assert {:ok, {:unit, type: nil, numerator: [], denominator: [den]}} =
               Parser.parse("per-second")

      assert den == {:single_unit, prefix: nil, power: nil, base: "second"}
    end
  end

  # ── Long form (with category) ──────────────────────────────────

  describe "long form with category" do
    test "parses length-kilometer" do
      assert {:ok, {:unit, type: "length", numerator: [single], denominator: []}} =
               Parser.parse("length-kilometer")

      assert single == {:single_unit, prefix: :kilo, power: nil, base: "meter"}
    end

    test "parses mass-kilogram" do
      assert {:ok, {:unit, type: "mass", numerator: [single], denominator: []}} =
               Parser.parse("mass-kilogram")

      assert single == {:single_unit, prefix: nil, power: nil, base: "kilogram"}
    end

    test "parses speed-meter-per-second" do
      assert {:ok, {:unit, type: "speed", numerator: [num], denominator: [den]}} =
               Parser.parse("speed-meter-per-second")

      assert num == {:single_unit, prefix: nil, power: nil, base: "meter"}
      assert den == {:single_unit, prefix: nil, power: nil, base: "second"}
    end

    test "parses acceleration-meter-per-square-second" do
      assert {:ok, {:unit, type: "acceleration", numerator: [num], denominator: [den]}} =
               Parser.parse("acceleration-meter-per-square-second")

      assert num == {:single_unit, prefix: nil, power: nil, base: "meter"}
      assert den == {:single_unit, prefix: nil, power: :square, base: "second"}
    end
  end

  # ── Mixed units ─────────────────────────────────────────────────

  describe "mixed units" do
    test "parses foot-and-inch" do
      assert {:ok, {:mixed_unit, units}} = Parser.parse("foot-and-inch")
      assert length(units) == 2

      assert Enum.at(units, 0) ==
               {:single_unit, prefix: nil, power: nil, base: "foot"}

      assert Enum.at(units, 1) ==
               {:single_unit, prefix: nil, power: nil, base: "inch"}
    end

    test "parses degree-and-arc-minute-and-arc-second" do
      assert {:ok, {:mixed_unit, units}} =
               Parser.parse("degree-and-arc-minute-and-arc-second")

      assert length(units) == 3
    end
  end

  # ── Product units ───────────────────────────────────────────────

  describe "complex product units" do
    test "parses kilogram-square-meter-per-cubic-second (power)" do
      assert {:ok, {:unit, type: nil, numerator: numerator, denominator: denominator}} =
               Parser.parse("kilogram-square-meter-per-cubic-second")

      assert length(numerator) == 2
      assert length(denominator) == 1
    end

    test "parses kilogram-meter-per-square-second (force)" do
      assert {:ok, {:unit, type: nil, numerator: numerator, denominator: denominator}} =
               Parser.parse("kilogram-meter-per-square-second")

      assert length(numerator) == 2
      assert length(denominator) == 1
    end
  end

  # ── Compound base units ─────────────────────────────────────────

  describe "compound base units" do
    test "parses nautical-mile" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("nautical-mile")

      assert single == {:single_unit, prefix: nil, power: nil, base: "nautical-mile"}
    end

    test "parses british-thermal-unit" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("british-thermal-unit")

      assert single == {:single_unit, prefix: nil, power: nil, base: "british-thermal-unit"}
    end

    test "parses light-year" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("light-year")

      assert single == {:single_unit, prefix: nil, power: nil, base: "light-year"}
    end

    test "parses arc-second" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("arc-second")

      assert single == {:single_unit, prefix: nil, power: nil, base: "arc-second"}
    end
  end

  # ── Units with constants ────────────────────────────────────────

  describe "units with constants" do
    test "parses liter-per-100-kilometer" do
      assert {:ok, {:unit, type: nil, numerator: [_num], denominator: denominator}} =
               Parser.parse("liter-per-100-kilometer")

      assert {:constant, "100"} in denominator
    end

    test "parses concentr-part-per-1e6" do
      assert {:ok, {:unit, type: "concentr", numerator: [_num], denominator: denominator}} =
               Parser.parse("concentr-part-per-1e6")

      assert {:constant, "1e6"} in denominator
    end

    test "parses concentr-part-per-1e9" do
      assert {:ok, {:unit, type: "concentr", numerator: [_num], denominator: denominator}} =
               Parser.parse("concentr-part-per-1e9")

      assert {:constant, "1e9"} in denominator
    end
  end

  # ── Suffix-containing base units ────────────────────────────────

  describe "suffix-containing base units" do
    test "parses pound-force" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("pound-force")

      assert single == {:single_unit, prefix: nil, power: nil, base: "pound-force"}
    end

    test "parses gallon-imperial" do
      assert {:ok, {:unit, type: nil, numerator: [single], denominator: []}} =
               Parser.parse("gallon-imperial")

      assert single == {:single_unit, prefix: nil, power: nil, base: "gallon-imperial"}
    end

    test "parses kilogram-force (force-kilogram-force with category)" do
      assert {:ok, {:unit, type: "force", numerator: [single], denominator: []}} =
               Parser.parse("force-kilogram-force")

      assert single == {:single_unit, prefix: nil, power: nil, base: "kilogram-force"}
    end
  end

  # ── Error cases ─────────────────────────────────────────────────

  describe "error cases" do
    test "returns error for empty string" do
      assert {:error, _reason} = Parser.parse("")
    end

    test "parser accepts unknown identifiers (validation is in Unit.new)" do
      # The parser accepts any lowercase identifier. Validation of
      # whether the base name is a known unit happens in Unit.new/2.
      assert {:ok, _ast} = Parser.parse("foobar")
    end

    test "parser rejects empty input" do
      assert {:error, _reason} = Parser.parse("")
    end

    test "Unit.new rejects unknown unit names" do
      assert {:error, _reason} = Localize.Unit.new("foobar")
      assert {:error, _reason} = Localize.Unit.new(1, "foobar")
    end
  end

  # ── Comprehensive validation ────────────────────────────────────

  describe "comprehensive CLDR validation" do
    test "parses all valid CLDR unit identifiers" do
      for unit_id <- Localize.Unit.Data.valid_unit_identifiers() do
        assert {:ok, _} = Parser.parse(unit_id),
               "Failed to parse valid unit identifier: #{unit_id}"
      end
    end
  end
end
