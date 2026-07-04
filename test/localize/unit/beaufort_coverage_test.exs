defmodule Localize.Unit.BeaufortCoverageTest do
  use ExUnit.Case, async: true

  alias Localize.Unit
  alias Localize.Unit.Conversion.Beaufort

  describe "forward/1" do
    test "a fractional Beaufort number interpolates between midpoints" do
      assert Beaufort.forward(2.5) == 3.475
    end

    test "the maximum Beaufort number maps to the top midpoint" do
      assert_in_delta Beaufort.forward(17), 58.6, 1.0e-9
    end

    test "values above the maximum are clamped" do
      assert Beaufort.forward(25) == Beaufort.forward(17)
    end
  end

  describe "inverse/1" do
    test "speeds beyond the top band clamp to the maximum Beaufort number" do
      assert Beaufort.inverse(200.0) == 17.0
    end

    test "negative speeds return zero" do
      assert Beaufort.inverse(-3) == 0.0
    end
  end

  describe "conversion through the unit pipeline" do
    test "fractional beaufort to meter-per-second" do
      {:ok, converted} = Unit.convert(Unit.new!(2.5, "beaufort"), "meter-per-second")
      assert_in_delta converted.value, 3.475, 1.0e-9
    end

    test "high wind speed to beaufort clamps at 17" do
      {:ok, converted} = Unit.convert(Unit.new!(100, "meter-per-second"), "beaufort")
      assert converted.value == 17.0
    end
  end
end
