defmodule Localize.Utils.MathCoverageTest do
  use ExUnit.Case, async: true

  alias Localize.Utils.Math

  describe "decimal-to-decimal arithmetic" do
    test "add/2 with two decimals" do
      assert Math.add(Decimal.new(1), Decimal.new(2)) == Decimal.new(3)
    end

    test "sub/2 with two decimals" do
      assert Math.sub(Decimal.new(3), Decimal.new(1)) == Decimal.new(2)
    end

    test "mult/2 with two decimals" do
      assert Math.mult(Decimal.new(3), Decimal.new(2)) == Decimal.new(6)
    end

    test "div/2 with two decimals" do
      assert Math.div(Decimal.new(6), Decimal.new(2)) == Decimal.new(3)
    end

    test "div/2 with a decimal and a float" do
      assert Math.div(Decimal.new(5), 2.5) == Decimal.new(2)
    end

    test "div/2 with a float and a decimal" do
      assert Math.div(5.0, Decimal.new(2)) == Decimal.new("2.5")
    end
  end

  describe "pow/2" do
    test "delegates to power/2" do
      assert Math.pow(2, 10) == 1024
    end
  end

  describe "sqrt/2" do
    test "of a number returns a float" do
      assert Math.sqrt(9) == 3.0
    end

    test "of a decimal with an integer precision" do
      assert Math.sqrt(Decimal.new(16), 4) == Decimal.new("4.0")
    end

    test "of a decimal with a float precision" do
      assert Math.sqrt(Decimal.new(16), 1.0e-10) == Decimal.new("4.0")
    end

    test "of a decimal with a decimal precision" do
      assert Math.sqrt(Decimal.new(16), Decimal.new("0.0000000001")) == Decimal.new("4.0")
    end
  end

  describe "root/2" do
    test "of a number" do
      assert Math.root(8, 3) == 2.0
      assert Math.root(27, 3) == 3.0
    end

    test "of a large decimal iterates towards the root" do
      big = Math.power(Decimal.new(10), 40)
      root = Math.root(big, 3)

      assert Decimal.compare(root, Decimal.new("21544346900318")) == :gt
      assert Decimal.compare(root, Decimal.new("21544346900320")) == :lt
    end
  end

  describe "round/3" do
    test "an integer returns an integer" do
      assert Math.round(7, 0, :half_even) == 7
      assert Math.round(12, 0, :half_up) == 12
    end

    test "a float with decimals: true is returned unchanged" do
      assert Math.round(1.2345, true, :half_even) == 1.2345
    end

    test "a float that rolls over increments the place" do
      assert Math.round(9.9, 0, :half_up) == 10.0
    end

    test "half_down rounds ties towards zero" do
      assert Math.round(1.5, 0, :half_down) == 1.0
      assert Math.round(2.6, 0, :half_down) == 3.0
      assert Math.round(2.4, 0, :half_down) == 2.0
      assert Math.round(1.55, 1, :half_down) == 1.5
    end
  end

  describe "round_scientific/3" do
    test "rounds significant digits of a float" do
      assert Math.round_scientific(1.2345, 2, :half_even) == 1.23
    end

    test "with scientific: true is returned unchanged" do
      assert Math.round_scientific(1.2345, true, :half_even) == 1.2345
    end
  end

  describe "convergents/1" do
    test "of an empty coefficient list" do
      assert Math.convergents([]) == []
    end

    test "of a single coefficient" do
      assert Math.convergents([3]) == [{3, 1}]
    end
  end

  describe "float_to_ratio/2" do
    test "a whole number with a max_denominator limit" do
      assert Math.float_to_ratio(3.0, max_denominator: 10) == {3, 1}
    end
  end
end
