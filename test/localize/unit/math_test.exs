defmodule Localize.Unit.MathTest do
  use ExUnit.Case, async: true

  alias Localize.Unit
  alias Localize.Unit.Math

  defp unit!(value, name), do: Unit.new!(value, name)

  # ── negate/1 ────────────────────────────────────────────────────────

  describe "negate/1" do
    test "negates a positive integer" do
      assert {:ok, result} = Math.negate(unit!(5, "meter"))
      assert result.value == -5
      assert result.name == "meter"
    end

    test "negates a negative float" do
      assert {:ok, result} = Math.negate(unit!(-3.5, "kilogram"))
      assert result.value == 3.5
    end

    test "negates a Decimal" do
      assert {:ok, result} = Math.negate(unit!(Decimal.new("7"), "second"))
      assert result.value == Decimal.new("-7")
    end

    test "negates zero" do
      assert {:ok, result} = Math.negate(unit!(0, "meter"))
      assert result.value == 0
    end

    test "returns error for unit without value" do
      {:ok, no_value} = Unit.new("meter")
      assert {:error, _} = Math.negate(no_value)
    end
  end

  # ── add/2 ───────────────────────────────────────────────────────────

  describe "add/2" do
    test "adds same units" do
      assert {:ok, result} = Math.add(unit!(3, "meter"), unit!(2, "meter"))
      assert result.value == 5.0
      assert result.name == "meter"
    end

    test "adds convertible units, result in unit_1's type" do
      assert {:ok, result} = Math.add(unit!(1, "kilometer"), unit!(500, "meter"))
      assert_in_delta result.value, 1.5, 0.0001
      assert result.name == "kilometer"
    end

    test "adds with Decimal value in unit_1" do
      assert {:ok, result} = Math.add(unit!(Decimal.new("10"), "meter"), unit!(5, "meter"))
      assert Decimal.equal?(result.value, Decimal.from_float(15.0))
    end

    test "returns error for incompatible units" do
      assert {:error, _} = Math.add(unit!(1, "meter"), unit!(1, "kilogram"))
    end

    test "returns error when unit has no value" do
      {:ok, no_value} = Unit.new("meter")
      assert {:error, _} = Math.add(no_value, unit!(1, "meter"))
    end
  end

  # ── sub/2 ───────────────────────────────────────────────────────────

  describe "sub/2" do
    test "subtracts same units" do
      assert {:ok, result} = Math.sub(unit!(10, "meter"), unit!(3, "meter"))
      assert result.value == 7.0
      assert result.name == "meter"
    end

    test "subtracts convertible units, result in unit_1's type" do
      assert {:ok, result} = Math.sub(unit!(1, "kilometer"), unit!(200, "meter"))
      assert_in_delta result.value, 0.8, 0.0001
      assert result.name == "kilometer"
    end

    test "can produce negative result" do
      assert {:ok, result} = Math.sub(unit!(1, "meter"), unit!(3, "meter"))
      assert result.value == -2.0
    end

    test "returns error for incompatible units" do
      assert {:error, _} = Math.sub(unit!(1, "meter"), unit!(1, "second"))
    end
  end

  # ── invert/1 ────────────────────────────────────────────────────────

  describe "invert/1" do
    test "inverts a simple unit" do
      assert {:ok, result} = Math.invert(unit!(4, "meter"))
      assert result.name == "per-meter"
      assert result.value == 0.25
    end

    test "inverts a per-unit (swaps numerator and denominator)" do
      assert {:ok, result} = Math.invert(unit!(4, "meter-per-second"))
      assert result.name == "second-per-meter"
      assert result.value == 0.25
    end

    test "inverts a per-only unit" do
      assert {:ok, result} = Math.invert(unit!(2, "per-second"))
      assert result.name == "second"
      assert result.value == 0.5
    end

    test "inverts a Decimal value" do
      assert {:ok, result} = Math.invert(unit!(Decimal.new("5"), "meter"))
      assert Decimal.equal?(result.value, Decimal.from_float(0.2))
    end

    test "returns error for unit without value" do
      {:ok, no_value} = Unit.new("meter")
      assert {:error, _} = Math.invert(no_value)
    end
  end

  # ── mult/2 with scalar ─────────────────────────────────────────────

  describe "mult/2 with scalar" do
    test "multiplies by integer" do
      assert {:ok, result} = Math.mult(unit!(5, "meter"), 3)
      assert result.value == 15
      assert result.name == "meter"
    end

    test "multiplies by float" do
      assert {:ok, result} = Math.mult(unit!(10, "kilogram"), 0.5)
      assert result.value == 5.0
    end

    test "multiplies by Decimal" do
      assert {:ok, result} = Math.mult(unit!(4, "second"), Decimal.new("2.5"))
      assert result.value == Decimal.new("10.0")
    end

    test "multiplies Decimal value by integer" do
      assert {:ok, result} = Math.mult(unit!(Decimal.new("3"), "meter"), 4)
      assert Decimal.equal?(result.value, Decimal.new("12"))
    end

    test "multiplies by zero" do
      assert {:ok, result} = Math.mult(unit!(5, "meter"), 0)
      assert result.value == 0
    end
  end

  # ── mult/2 with unit ───────────────────────────────────────────────

  describe "mult/2 with unit" do
    test "multiplies different-dimension units to create compound unit" do
      assert {:ok, result} = Math.mult(unit!(10, "meter"), unit!(5, "second"))
      assert result.value == 50
      assert result.name == "meter-second"
    end

    test "multiplies same units consolidates to square" do
      assert {:ok, result} = Math.mult(unit!(3, "meter"), unit!(4, "meter"))
      assert result.value == 12
      assert result.name == "square-meter"
    end

    test "multiplies per-unit by simple unit consolidates denominator" do
      assert {:ok, result} = Math.mult(unit!(10, "meter-per-second"), unit!(5, "second"))
      assert result.value == 50
      assert result.name == "meter-second-per-second"
    end

    test "multiplies two per-units consolidates repeated denominators" do
      assert {:ok, result} =
               Math.mult(unit!(6, "meter-per-second"), unit!(2, "kilogram-per-second"))

      assert result.value == 12
      assert result.name == "meter-kilogram-per-square-second"
    end

    test "multiplies with SI-prefixed unit" do
      assert {:ok, result} = Math.mult(unit!(5, "kilogram"), unit!(3, "meter"))
      assert result.value == 15
      assert result.name == "kilogram-meter"
    end
  end

  # ── div/2 with scalar ──────────────────────────────────────────────

  describe "div/2 with scalar" do
    test "divides by integer" do
      assert {:ok, result} = Math.div(unit!(10, "meter"), 2)
      assert result.value == 5.0
      assert result.name == "meter"
    end

    test "divides by float" do
      assert {:ok, result} = Math.div(unit!(9, "kilogram"), 0.5)
      assert result.value == 18.0
    end

    test "divides by Decimal" do
      assert {:ok, result} = Math.div(unit!(Decimal.new("10"), "meter"), Decimal.new("4"))
      assert Decimal.equal?(result.value, Decimal.new("2.5"))
    end
  end

  # ── div/2 with unit ────────────────────────────────────────────────

  describe "div/2 with unit" do
    test "divides different-dimension units to create per-unit" do
      assert {:ok, result} = Math.div(unit!(100, "meter"), unit!(10, "second"))
      assert result.value == 10.0
      assert result.name == "meter-per-second"
    end

    test "divides same units (dimensionless result)" do
      assert {:ok, result} = Math.div(unit!(10, "meter"), unit!(5, "meter"))
      assert result.value == 2.0
      assert result.name == "meter-per-meter"
    end

    test "divides per-unit by simple unit consolidates denominator" do
      assert {:ok, result} = Math.div(unit!(10, "meter-per-second"), unit!(2, "meter"))
      assert result.value == 5.0
      assert result.name == "meter-per-second-meter"
    end

    test "divides simple unit by per-unit consolidates numerator" do
      # meter / (meter-per-second) = meter * (second / meter) = meter-second / meter
      assert {:ok, result} = Math.div(unit!(10, "meter"), unit!(2, "meter-per-second"))
      assert result.value == 5.0
      assert result.name == "meter-second-per-meter"
    end

    test "divides with SI-prefixed units" do
      assert {:ok, result} = Math.div(unit!(10, "kilogram"), unit!(2, "second"))
      assert result.value == 5.0
      assert result.name == "kilogram-per-second"
    end
  end

  # ── power consolidation ──────────────────────────────────────────────

  describe "power consolidation" do
    test "meter * meter = square-meter" do
      assert {:ok, result} = Math.mult(unit!(2, "meter"), unit!(3, "meter"))
      assert result.name == "square-meter"
      assert result.value == 6
    end

    test "square-meter * meter = cubic-meter" do
      assert {:ok, result} = Math.mult(unit!(2, "square-meter"), unit!(3, "meter"))
      assert result.name == "cubic-meter"
      assert result.value == 6
    end

    test "cubic-meter * meter = pow4-meter" do
      assert {:ok, result} = Math.mult(unit!(2, "cubic-meter"), unit!(3, "meter"))
      assert result.name == "pow4-meter"
      assert result.value == 6
    end

    test "square-meter * square-meter = pow4-meter" do
      assert {:ok, result} = Math.mult(unit!(2, "square-meter"), unit!(3, "square-meter"))
      assert result.name == "pow4-meter"
      assert result.value == 6
    end

    test "consolidation in denominator: second * second = square-second" do
      assert {:ok, result} =
               Math.div(unit!(10, "meter"), unit!(2, "second"))
               |> elem(1)
               |> Math.div(unit!(1, "second"))

      assert result.name == "meter-per-square-second"
    end

    test "different units are not consolidated" do
      assert {:ok, result} = Math.mult(unit!(2, "meter"), unit!(3, "kilogram"))
      assert result.name == "meter-kilogram"
    end

    test "SI-prefixed units only consolidate with same prefix" do
      assert {:ok, result} = Math.mult(unit!(2, "kilometer"), unit!(3, "meter"))
      assert result.name == "kilometer-meter"
    end

    test "same SI-prefixed units consolidate" do
      assert {:ok, result} = Math.mult(unit!(2, "kilometer"), unit!(3, "kilometer"))
      assert result.name == "square-kilometer"
    end
  end

  # ── round-trip consistency ──────────────────────────────────────────

  describe "round-trip consistency" do
    test "add then sub returns original value" do
      a = unit!(10, "meter")
      b = unit!(3, "meter")
      {:ok, added} = Math.add(a, b)
      {:ok, result} = Math.sub(added, b)
      assert_in_delta result.value, 10.0, 0.0001
    end

    test "mult then div by scalar returns original value" do
      u = unit!(7, "kilogram")
      {:ok, multiplied} = Math.mult(u, 3)
      {:ok, result} = Math.div(multiplied, 3)
      assert_in_delta result.value, 7.0, 0.0001
    end

    test "double invert returns same unit type" do
      u = unit!(4, "meter-per-second")
      {:ok, inv1} = Math.invert(u)
      {:ok, inv2} = Math.invert(inv1)
      assert inv2.name == "meter-per-second"
      assert_in_delta inv2.value, 4.0, 0.0001
    end
  end
end
