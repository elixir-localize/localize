defmodule Localize.Unit.MathCoverageTest do
  use ExUnit.Case, async: true

  alias Localize.Unit
  alias Localize.Unit.Math

  defp unit!(value, name), do: Unit.new!(value, name)

  describe "sqrt/1 and cbrt/1" do
    test "square root of a square unit" do
      {:ok, result} = Math.sqrt(unit!(9, "square-meter"))
      assert result.name == "meter"
      assert result.value == 3.0
    end

    test "cube root of a cubic unit" do
      {:ok, result} = Math.cbrt(unit!(27, "cubic-meter"))
      assert result.name == "meter"
      assert result.value == 3.0
    end

    test "square root of pow6 produces a cubic unit" do
      {:ok, result} = Math.sqrt(unit!(64, "pow6-meter"))
      assert result.name == "cubic-meter"
      assert result.value == 8.0
    end

    test "square root of pow8 produces a pow4 unit" do
      {:ok, result} = Math.sqrt(unit!(16, "pow8-meter"))
      assert result.name == "pow4-meter"
      assert result.value == 4.0
    end

    test "square root of an odd power is an error" do
      assert {:error, "cannot take square root of meter with power 1"} =
               Math.sqrt(unit!(9, "meter"))
    end

    test "sqrt/1 and cbrt/1 require a value" do
      assert {:error, %Localize.UnitNoValueError{operation: "sqrt"}} =
               Math.sqrt(Unit.new!("meter"))

      assert {:error, %Localize.UnitNoValueError{operation: "cbrt"}} =
               Math.cbrt(Unit.new!("meter"))
    end
  end

  describe "no-value errors" do
    test "each unary function reports its operation" do
      no_value = Unit.new!("meter")

      assert {:error, %Localize.UnitNoValueError{operation: "abs"}} = Math.abs(no_value)
      assert {:error, %Localize.UnitNoValueError{operation: "round"}} = Math.round(no_value)
      assert {:error, %Localize.UnitNoValueError{operation: "ceil"}} = Math.ceil(no_value)
      assert {:error, %Localize.UnitNoValueError{operation: "floor"}} = Math.floor(no_value)
      assert {:error, %Localize.UnitNoValueError{operation: "trunc"}} = Math.trunc(no_value)
    end

    test "sub/2 requires values on both sides" do
      assert {:error, %Localize.UnitNoValueError{operation: :subtract}} =
               Math.sub(Unit.new!("meter"), unit!(1, "meter"))
    end
  end

  describe "rounding, ceiling, floor, and truncation" do
    test "round/3 rounds a Decimal to the given places" do
      {:ok, result} = Math.round(unit!(Decimal.new("2.567"), "meter"), 1)
      assert Decimal.equal?(result.value, Decimal.new("2.6"))
    end

    test "round/3 applies :half_even to floats" do
      {:ok, result} = Math.round(unit!(2.5, "meter"), 0, :half_even)
      assert result.value == 2.0
    end

    test "round/3 passes integers through unchanged" do
      {:ok, result} = Math.round(unit!(7, "meter"))
      assert result.value == 7
    end

    test "ceil/1 for Decimal and integer values" do
      {:ok, decimal_result} = Math.ceil(unit!(Decimal.new("2.1"), "meter"))
      assert decimal_result.value == 3

      {:ok, integer_result} = Math.ceil(unit!(3, "meter"))
      assert integer_result.value == 3
    end

    test "floor/1 for Decimal and integer values" do
      {:ok, decimal_result} = Math.floor(unit!(Decimal.new("2.9"), "meter"))
      assert decimal_result.value == 2

      {:ok, integer_result} = Math.floor(unit!(3, "meter"))
      assert integer_result.value == 3
    end

    test "trunc/1 truncates a negative Decimal toward zero" do
      {:ok, decimal_result} = Math.trunc(unit!(Decimal.new("-2.9"), "meter"))
      assert decimal_result.value == -2

      {:ok, integer_result} = Math.trunc(unit!(3, "meter"))
      assert integer_result.value == 3
    end
  end

  describe "apply_dimensionless/2" do
    test "trigonometry on a dimensionless (angle) unit" do
      {:ok, result} = Math.apply_dimensionless(:sin, unit!(0.5, "radian"))
      assert_in_delta result, 0.479425538604203, 1.0e-12
    end

    test "logarithm on a revolution" do
      assert Math.apply_dimensionless(:ln, unit!(1, "revolution")) == {:ok, 0.0}
    end

    test "a dimensioned unit is rejected" do
      assert {:error, "cos requires a dimensionless value, got unit with base: meter"} =
               Math.apply_dimensionless(:cos, unit!(1, "meter"))
    end

    test "a unit without a value is rejected" do
      assert {:error, "function requires a unit with a value"} =
               Math.apply_dimensionless(:sin, Unit.new!("meter"))
    end

    test "an unknown function name is rejected" do
      assert {:error, "unknown dimensionless function: bogus"} =
               Math.apply_dimensionless(:bogus, unit!(1, "radian"))
    end
  end

  describe "mixed numeric type arithmetic" do
    test "adding a Decimal unit to an integer unit promotes to Decimal" do
      {:ok, result} = Unit.add(unit!(1, "meter"), unit!(Decimal.new("0.5"), "meter"))
      assert Decimal.equal?(result.value, Decimal.new("1.5"))
    end

    test "dividing an integer unit by a Decimal scalar promotes to Decimal" do
      {:ok, result} = Unit.div(unit!(10, "meter"), Decimal.new(4))
      assert Decimal.equal?(result.value, Decimal.new("2.5"))
    end
  end
end
