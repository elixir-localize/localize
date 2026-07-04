defmodule Localize.Unit.OperatorsTest do
  use ExUnit.Case, async: true
  use Localize.Unit.Operators

  alias Localize.Unit

  defp unit!(value, name) do
    {:ok, unit} = Unit.new(value, name)
    unit
  end

  describe "unit + unit" do
    test "adds same-typed units" do
      result = unit!(5, "meter") + unit!(3, "meter")
      assert result.name == "meter"
      assert result.value == 8.0
    end

    test "adds convertible units in the left operand's type" do
      result = unit!(5, "meter") + unit!(2, "foot")
      assert result.name == "meter"
      assert_in_delta result.value, 5.6096, 1.0e-9
    end

    test "raises for incompatible units" do
      assert_raise Localize.UnitConversionError, fn ->
        unit!(5, "meter") + unit!(2, "second")
      end
    end

    test "falls through to Kernel.+/2 for plain numbers" do
      assert 1 + 2 == 3
      assert 1.5 + 2.5 == 4.0
    end
  end

  describe "unit - unit" do
    test "subtracts same-typed units" do
      result = unit!(5, "meter") - unit!(3, "meter")
      assert result.name == "meter"
      assert result.value == 2.0
    end

    test "raises for incompatible units" do
      assert_raise Localize.UnitConversionError, fn ->
        unit!(5, "meter") - unit!(2, "second")
      end
    end

    test "falls through to Kernel.-/2 for plain numbers" do
      assert 5 - 3 == 2
    end
  end

  describe "unit * scalar" do
    test "multiplies by an integer" do
      result = unit!(5, "meter") * 2
      assert result.name == "meter"
      assert result.value == 10
    end

    test "scalar on the left is commutative" do
      result = 2 * unit!(5, "meter")
      assert result.name == "meter"
      assert result.value == 10
    end

    test "multiplies by a Decimal" do
      result = unit!(5, "meter") * Decimal.new(2)
      assert Decimal.equal?(result.value, Decimal.new(10))
    end

    test "Decimal on the left is commutative" do
      result = Decimal.new(3) * unit!(5, "meter")
      assert Decimal.equal?(result.value, Decimal.new(15))
    end

    test "falls through to Kernel.*/2 for plain numbers" do
      assert 4 * 4 == 16
    end
  end

  describe "unit * unit" do
    test "produces a compound unit" do
      result = unit!(5, "meter") * unit!(2, "second")
      assert result.name == "meter-second"
      assert result.value == 10
    end
  end

  describe "unit / scalar and unit / unit" do
    test "divides by an integer" do
      result = unit!(5, "meter") / 2
      assert result.name == "meter"
      assert result.value == 2.5
    end

    test "divides by a Decimal" do
      result = unit!(5, "meter") / Decimal.new(2)
      assert Decimal.equal?(result.value, Decimal.new("2.5"))
    end

    test "unit / unit produces a per-unit" do
      result = unit!(5, "meter") / unit!(2, "second")
      assert result.name == "meter-per-second"
      assert result.value == 2.5
    end

    test "falls through to Kernel.//2 for plain numbers" do
      assert 7 / 2 == 3.5
    end
  end
end
