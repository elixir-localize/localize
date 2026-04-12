defmodule Localize.Unit.BaseUnitTest do
  use ExUnit.Case, async: true

  doctest Localize.Unit.BaseUnit

  alias Localize.Unit.BaseUnit

  # ── Simple units ────────────────────────────────────────────────────

  describe "simple units" do
    test "foot → meter" do
      assert {:ok, "meter"} = BaseUnit.base_unit("foot")
    end

    test "gram → kilogram" do
      assert {:ok, "kilogram"} = BaseUnit.base_unit("gram")
    end

    test "liter → cubic-meter" do
      assert {:ok, "cubic-meter"} = BaseUnit.base_unit("liter")
    end

    test "candela → candela (identity)" do
      assert {:ok, "candela"} = BaseUnit.base_unit("candela")
    end

    test "meter → meter (identity)" do
      assert {:ok, "meter"} = BaseUnit.base_unit("meter")
    end

    test "kilogram → kilogram (identity)" do
      assert {:ok, "kilogram"} = BaseUnit.base_unit("kilogram")
    end
  end

  # ── Derived units ───────────────────────────────────────────────────

  describe "derived units" do
    test "newton → kilogram-meter-per-square-second" do
      assert {:ok, "kilogram-meter-per-square-second"} = BaseUnit.base_unit("newton")
    end

    test "watt → kilogram-square-meter-per-cubic-second" do
      assert {:ok, "kilogram-square-meter-per-cubic-second"} = BaseUnit.base_unit("watt")
    end

    test "hertz → revolution-per-second" do
      assert {:ok, "revolution-per-second"} = BaseUnit.base_unit("hertz")
    end

    test "volt → kilogram-square-meter-per-cubic-second-ampere" do
      assert {:ok, "kilogram-square-meter-per-cubic-second-ampere"} = BaseUnit.base_unit("volt")
    end

    test "ohm → kilogram-square-meter-per-cubic-second-square-ampere" do
      assert {:ok, "kilogram-square-meter-per-cubic-second-square-ampere"} =
               BaseUnit.base_unit("ohm")
    end

    test "farad → pow4-second-square-ampere-per-kilogram-square-meter" do
      assert {:ok, "pow4-second-square-ampere-per-kilogram-square-meter"} =
               BaseUnit.base_unit("farad")
    end

    test "pascal → kilogram-per-meter-square-second" do
      assert {:ok, "kilogram-per-meter-square-second"} = BaseUnit.base_unit("pascal")
    end
  end

  # ── SI prefixed units ──────────────────────────────────────────────

  describe "SI prefixed units" do
    test "kilometer → meter" do
      assert {:ok, "meter"} = BaseUnit.base_unit("kilometer")
    end

    test "milligram → kilogram" do
      assert {:ok, "kilogram"} = BaseUnit.base_unit("milligram")
    end

    test "megawatt → kilogram-square-meter-per-cubic-second" do
      assert {:ok, "kilogram-square-meter-per-cubic-second"} = BaseUnit.base_unit("megawatt")
    end

    test "gigahertz → revolution-per-second" do
      assert {:ok, "revolution-per-second"} = BaseUnit.base_unit("gigahertz")
    end
  end

  # ── Per units ───────────────────────────────────────────────────────

  describe "per units" do
    test "meter-per-second → meter-per-second" do
      assert {:ok, "meter-per-second"} = BaseUnit.base_unit("meter-per-second")
    end

    test "mile-per-hour → meter-per-second" do
      assert {:ok, "meter-per-second"} = BaseUnit.base_unit("mile-per-hour")
    end

    test "liter-per-kilometer → square-meter (volume/length simplifies)" do
      assert {:ok, "square-meter"} = BaseUnit.base_unit("liter-per-kilometer")
    end

    test "per-second → per-second" do
      assert {:ok, "per-second"} = BaseUnit.base_unit("per-second")
    end
  end

  # ── Power prefix units ─────────────────────────────────────────────

  describe "power prefix units" do
    test "square-meter → square-meter" do
      assert {:ok, "square-meter"} = BaseUnit.base_unit("square-meter")
    end

    test "cubic-meter → cubic-meter" do
      assert {:ok, "cubic-meter"} = BaseUnit.base_unit("cubic-meter")
    end

    test "cubic-foot → cubic-meter" do
      assert {:ok, "cubic-meter"} = BaseUnit.base_unit("cubic-foot")
    end

    test "square-kilometer → square-meter" do
      assert {:ok, "square-meter"} = BaseUnit.base_unit("square-kilometer")
    end
  end

  # ── Complex compound units ─────────────────────────────────────────

  describe "complex compound units" do
    test "kilowatt-hour → energy (kilogram-square-meter-per-square-second)" do
      assert {:ok, "kilogram-square-meter-per-square-second"} =
               BaseUnit.base_unit("kilowatt-hour")
    end

    test "pound-force-per-square-inch → pressure" do
      assert {:ok, "kilogram-per-meter-square-second"} =
               BaseUnit.base_unit("pound-force-per-square-inch")
    end
  end

  # ── Category-prefixed units ─────────────────────────────────────────

  describe "category-prefixed units" do
    test "length-foot → meter" do
      assert {:ok, "meter"} = BaseUnit.base_unit("length-foot")
    end

    test "speed-mile-per-hour → meter-per-second" do
      assert {:ok, "meter-per-second"} = BaseUnit.base_unit("speed-mile-per-hour")
    end

    test "acceleration-g-force → meter-per-square-second" do
      assert {:ok, "meter-per-square-second"} = BaseUnit.base_unit("acceleration-g-force")
    end
  end

  # ── Mixed units ─────────────────────────────────────────────────────

  describe "mixed units" do
    test "foot-and-inch → meter (dimension of first unit)" do
      assert {:ok, "meter"} = BaseUnit.base_unit("foot-and-inch")
    end
  end

  # ── Decompose ───────────────────────────────────────────────────────

  describe "decompose/1" do
    test "returns power map for newton" do
      {:ok, ast} = Localize.Unit.Parser.parse("newton")

      assert {:ok, %{"kilogram" => 1, "meter" => 1, "second" => -2}} =
               BaseUnit.decompose(ast)
    end

    test "returns power map for cubic-meter" do
      {:ok, ast} = Localize.Unit.Parser.parse("cubic-meter")
      assert {:ok, %{"meter" => 3}} = BaseUnit.decompose(ast)
    end

    test "constants contribute no dimensions" do
      {:ok, ast} = Localize.Unit.Parser.parse("liter-per-100-kilometer")

      assert {:ok, powers} = BaseUnit.decompose(ast)
      assert powers == %{"meter" => 2}
    end
  end

  # ── Recompose ───────────────────────────────────────────────────────

  describe "recompose/1" do
    test "force" do
      assert "kilogram-meter-per-square-second" =
               BaseUnit.recompose(%{"kilogram" => 1, "meter" => 1, "second" => -2})
    end

    test "volume" do
      assert "cubic-meter" = BaseUnit.recompose(%{"meter" => 3})
    end

    test "empty map" do
      assert "" = BaseUnit.recompose(%{})
    end

    test "per-only (no numerator)" do
      assert "per-second" = BaseUnit.recompose(%{"second" => -1})
    end

    test "high power" do
      assert "pow4-second" = BaseUnit.recompose(%{"second" => 4})
    end
  end

  # ── Error cases ─────────────────────────────────────────────────────

  describe "error cases" do
    test "unknown unit returns error" do
      assert {:error, _} = BaseUnit.base_unit("foobar")
    end

    test "base_unit! raises on unknown unit" do
      assert_raise Localize.UnknownUnitError, fn ->
        BaseUnit.base_unit!("foobar")
      end
    end
  end
end
