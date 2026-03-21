defmodule Localize.Number.SignificantDigitsTest do
  use ExUnit.Case, async: true

  alias Localize.Utils.Math

  describe "integer significant digit rounding" do
    test "round 1,239,451 to 3 significant digits" do
      assert 1_240_000 == Math.round_significant(1_239_451, 3)
    end

    test "round 5 to 3 significant digits" do
      assert 5 == Math.round_significant(5, 3)
    end

    test "round 12345 to 3 significant digits" do
      assert 12300 == Math.round_significant(12345, 3)
    end
  end

  describe "float significant digit rounding" do
    test "round 12.1257 to 3 significant digits" do
      assert 12.1 == Math.round_significant(12.1257, 3)
    end

    test "round .0681 to 3 significant digits" do
      assert 0.0681 == Math.round_significant(0.0681, 3)
    end

    test "round 0.12345 to 3 significant digits" do
      assert 0.123 == Math.round_significant(0.12345, 3)
    end

    test "round 3.14159 to 4 significant digits" do
      assert 3.142 == Math.round_significant(3.14159, 4)
    end

    test "round 1.23004 to 4 significant digits" do
      assert 1.23 == Math.round_significant(1.23004, 4)
    end
  end

  describe "Decimal significant digit rounding" do
    test "round decimal 12345 to 3 significant digits" do
      result = Math.round_significant(Decimal.new(12345), 3)
      assert Decimal.equal?(result, Decimal.new(12300))
    end

    test "round decimal 0.12345 to 3 significant digits" do
      assert Decimal.new("0.123") == Math.round_significant(Decimal.new("0.12345"), 3)
    end

    test "round decimal 3.14159 to 4 significant digits" do
      assert Decimal.new("3.142") == Math.round_significant(Decimal.new("3.14159"), 4)
    end

    test "round decimal 1.23004 to 4 significant digits" do
      assert Decimal.new("1.23") == Math.round_significant(Decimal.new("1.23004"), 4)
    end

    test "round negative decimal -1.23004 to 4 significant digits" do
      assert Decimal.new("-1.23") == Math.round_significant(Decimal.new("-1.23004"), 4)
    end
  end
end
