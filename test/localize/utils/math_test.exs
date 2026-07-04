defmodule Localize.Utils.MathTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Localize.Utils.Digits
  alias Localize.Utils.Math

  doctest Localize.Utils.Math

  property "check rounding for decimals is the same as Decimal.round/3" do
    check all(decimal <- GenerateNumber.decimal(), max_runs: 1_000) do
      assert Decimal.round(decimal, 0, :half_up) == Math.round(decimal, 0, :half_up)
    end
  end

  property "check rounding to zero places for floats is the same as Kernel.round/1" do
    check all(float <- GenerateNumber.float(), max_runs: 1_000) do
      assert Kernel.round(float) == Math.round(float, 0, :half_up)
    end
  end

  property "check rounding to zero places for floats is the same as Float.round/1" do
    check all(float <- GenerateNumber.float(), max_runs: 1_000) do
      assert Float.round(float) == Math.round(float, 0, :half_up)
    end
  end

  test "integer number of digits for a decimal integer" do
    decimal = Decimal.new(1234)
    assert Digits.number_of_integer_digits(decimal) == 4
  end

  test "rounding floats" do
    assert Math.round(1.401, 2, :half_even) == 1.4
    assert Math.round(1.404, 2, :half_even) == 1.4
    assert Math.round(1.405, 2, :half_even) == 1.4
    assert Math.round(1.406, 2, :half_even) == 1.41
  end

  test "rounding floats with zero decimals" do
    assert Math.round(3.6000000000000085) == 4.0
  end

  test "rounding a float < 0 with zero decimals" do
    assert Math.round(0.959999999999809) == 1.0
  end

  test "integer number of digits for a decimal fixnum" do
    decimal = Decimal.from_float(1234.5678)
    assert Digits.number_of_integer_digits(decimal) == 4
  end

  test "rounding decimal number" do
    decimal = Decimal.new("0.1111") |> Math.round()
    assert Decimal.equal?(decimal, Decimal.new(0))
    assert decimal.sign == 1
  end

  @decimals [Decimal.new("0.9876"), Decimal.new("1.9876"), Decimal.new("0.4"), Decimal.new("0.6")]
  @places [0, 1, 2, 3]
  @rounding [:half_even, :floor, :ceiling, :half_up, :half_down]
  for d <- @decimals, p <- @places, r <- @rounding do
    test "default rounding is the same as Decimal.round for #{inspect(d)}, places: #{inspect(p)}, mode: #{inspect(r)}" do
      assert Math.round(unquote(Macro.escape(d)), unquote(p), unquote(r)) ==
               Decimal.round(unquote(Macro.escape(d)), unquote(p), unquote(r))
    end
  end

  test "round significant digits for a decimal integer" do
    decimal = Decimal.new(1234)
    assert Math.round_significant(decimal, 2) == Decimal.normalize(Decimal.new(1200))
  end

  test "round significant digits for a decimal" do
    decimal = Decimal.from_float(1234.45)
    assert Math.round_significant(decimal, 4) == Decimal.normalize(Decimal.new(1234))
  end

  test "round significant digits for a decimal to 5 digits" do
    decimal = Decimal.from_float(1234.45)
    assert Math.round_significant(decimal, 5) == Decimal.normalize(Decimal.from_float(1234.5))
  end

  test "power of 0 == 1" do
    assert Math.power(Decimal.new(123), 0) == Decimal.new(1)
  end

  test "power of decimal where n > 1" do
    assert Math.power(Decimal.new(12), 3) == Decimal.new(1728)
  end

  test "power of decimal where n < 0" do
    assert Math.power(Decimal.new(4), -2) == Decimal.from_float(0.0625)
  end

  test "power of decimal where number < 0" do
    assert Math.power(Decimal.new(-4), 2) == Decimal.new(16)
  end

  test "power of integer when n = 0" do
    assert Math.power(3, 0) === 1
  end

  test "power of float when n == 0" do
    assert Math.power(3.0, 0) === 1.0
  end

  test "power of integer when n < 1" do
    assert Math.power(4, -2) == 0.0625
  end

  test "amod returns the divisor when it the remainder would be zero and test that dividend is one less" do
    {div, amod} = Math.div_amod(24, 12)
    assert amod == 12
    assert div == 1
  end

  test "amod returns the zero for the remainder" do
    {div, mod} = Math.div_mod(24, 12)
    assert mod == 0
    assert div == 2
  end

  describe "arithmetic with mixed number and Decimal arguments" do
    test "add/2 coerces mixed arguments to Decimal" do
      assert Math.add(Decimal.new(1), 2) == Decimal.new(3)
      assert Math.add(Decimal.new(1), 1.5) == Decimal.new("2.5")
      assert Math.add(2, Decimal.new(1)) == Decimal.new(3)
      assert Math.add(1.5, Decimal.new(1)) == Decimal.new("2.5")
      assert Math.add(1, 2) == 3
    end

    test "sub/2 coerces mixed arguments to Decimal" do
      assert Math.sub(Decimal.new(3), 1) == Decimal.new(2)
      assert Math.sub(Decimal.new(3), 1.5) == Decimal.new("1.5")
      assert Math.sub(3, Decimal.new(1)) == Decimal.new(2)
      assert Math.sub(3.5, Decimal.new(1)) == Decimal.new("2.5")
      assert Math.sub(3, 1) == 2
    end

    test "mult/2 coerces mixed arguments to Decimal" do
      assert Math.mult(Decimal.new(2), 3) == Decimal.new(6)
      assert Math.mult(Decimal.new(2), 1.5) == Decimal.new("3.0")
      assert Math.mult(2, Decimal.new(3)) == Decimal.new(6)
      assert Math.mult(1.5, Decimal.new(2)) == Decimal.new("3.0")
      assert Math.mult(2, 3) == 6
    end

    test "div/2 coerces mixed arguments to Decimal" do
      assert Math.div(Decimal.new(3), 2) == Decimal.new("1.5")
      assert Math.div(3, Decimal.new(2)) == Decimal.new("1.5")
      assert Math.div(3, 2) == Decimal.new("1.5")
    end
  end

  describe "maybe_integer/1" do
    test "returns an integer for integral Decimal values" do
      assert Math.maybe_integer(Decimal.new(3)) === 3
    end

    test "returns the Decimal unchanged when it has a fraction" do
      assert Math.maybe_integer(Decimal.new("2.5")) == Decimal.new("2.5")
    end

    test "returns an integer for integral floats" do
      assert Math.maybe_integer(4.0) === 4
    end

    test "returns the float unchanged when it has a fraction" do
      assert Math.maybe_integer(4.5) === 4.5
    end

    test "returns integers unchanged" do
      assert Math.maybe_integer(7) === 7
    end
  end

  describe "defaults and range membership" do
    test "default_rounding/0 and default_rounding_mode/0" do
      assert Math.default_rounding() == 3
      assert Math.default_rounding_mode() == :half_even
    end

    test "within/2 for integers" do
      assert Math.within(5, 1..10)
      refute Math.within(11, 1..10)
    end

    test "within/2 for floats requires an integral value" do
      assert Math.within(5.0, 1..10)
      refute Math.within(5.5, 1..10)
    end
  end

  describe "mod/2 and amod/2" do
    test "mod of floats uses floored division" do
      assert Math.mod(7.5, 2) == 1.5
      assert Math.mod(1234.0, 5) == 4.0
    end

    test "mod of a negative integer is floored" do
      assert Math.mod(-7, 3) == 2
    end

    test "mod of an integer with a float modulus" do
      assert Math.mod(7, 2.5) == 2.0
    end

    test "mod of Decimals in all modulus types" do
      assert Math.mod(Decimal.new(7), Decimal.new(3)) == Decimal.new(1)
      assert Math.mod(Decimal.new("7.5"), 2) == Decimal.new("1.5")
      assert Math.mod(Decimal.new("7.5"), 2.5) == Decimal.new("0.0")
    end

    test "amod returns the modulus when the remainder is zero" do
      assert Math.amod(24, 12) == 12
      assert Math.amod(25, 12) == 1
    end

    test "amod for Decimal values returns the modulus when the remainder is zero" do
      assert Math.amod(Decimal.new(24), Decimal.new(12)) == Decimal.new(12)
    end
  end

  describe "to_float/1" do
    test "converts positive and negative Decimals" do
      assert Math.to_float(Decimal.new("1.5")) == 1.5
      assert Math.to_float(Decimal.new("-25")) == -25.0
    end
  end

  describe "log/1 and log10/1" do
    test "log of e is 1.0" do
      assert_in_delta Math.log(:math.exp(1)), 1.0, 1.0e-12
    end

    test "log of a Decimal approximates the natural log" do
      result = Math.log(Decimal.new(10))
      assert_in_delta Decimal.to_float(result), :math.log(10), 1.0e-9
    end

    test "log10 of numbers and Decimals" do
      assert Math.log10(1000) == 3.0
      assert Decimal.equal?(Math.log10(Decimal.new(1000)), Decimal.new(3))
    end
  end

  describe "power_of_10/1 and coef_exponent/1" do
    test "positive powers are precomputed integers" do
      assert Math.power_of_10(0) == 1
      assert Math.power_of_10(3) == 1000
    end

    test "negative powers return the reciprocal" do
      assert Math.power_of_10(-2) == 0.01
    end

    test "coef_exponent decomposes an integer" do
      assert Math.coef_exponent(1234) == {1.234, 3}
    end
  end

  describe "round_significant/2 edge cases" do
    test "zero and non-positive digit counts are returned unchanged" do
      assert Math.round_significant(0, 3) == 0
      assert Math.round_significant(1234, -1) == 1234
      assert Math.round_significant(Decimal.new("1.5"), 0) == Decimal.new("1.5")
    end

    test "a zero Decimal is returned unchanged" do
      assert Math.round_significant(Decimal.new(0), 2) == Decimal.new(0)
    end

    test "fractional floats round to significant digits" do
      assert Math.round_significant(0.001234, 2) == 0.0012
    end

    test "negative Decimals round preserving sign" do
      result = Math.round_significant(Decimal.new(-1234), 2)
      assert Decimal.equal?(result, Decimal.new(-1200))
      assert result.sign == -1
    end
  end

  describe "power/2 with Decimal exponents" do
    test "Decimal number and Decimal exponent" do
      assert Math.power(Decimal.new(2), Decimal.new(10)) == Decimal.new(1024)
      assert Math.power(Decimal.new(2), Decimal.new(0)) == Decimal.new(1)
      assert Math.power(Decimal.new(2), Decimal.new(1)) == Decimal.new(2)
      assert Math.power(Decimal.new(2), Decimal.new(-2)) == Decimal.new("0.25")
    end

    test "integer and float bases with integer exponents" do
      assert Math.power(2, 10) == 1024
      assert Math.power(2.0, 2) == 4.0
      assert Math.power(3, 1) == 3
    end
  end

  describe "power/2 with fractional and negative exponents" do
    test "an exponent between 0 and 1 is a root, not a reciprocal" do
      # Regression: power(4, 0.5) used to return 0.5 (the reciprocal
      # path applied to every n < 1) instead of 2.0.
      assert Math.power(4, 0.5) == 2.0
      assert Math.power(9, 0.5) == 3.0
      assert_in_delta Math.power(8, 1 / 3), 2.0, 1.0e-12
    end

    test "a negative exponent returns the reciprocal" do
      assert Math.power(4, -2) == 0.0625
      assert Math.power(4, -0.5) == 0.5
      assert Math.power(2.0, -1) == 0.5
    end

    test "a Decimal base with a fractional exponent returns a Decimal" do
      # Regression: the fractional-exponent escape hatch returned a
      # bare float for a Decimal base.
      result = Math.power(Decimal.new(4), 0.5)
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new("2.0"))
    end

    test "a Decimal base with a negative fractional exponent returns a Decimal" do
      result = Math.power(Decimal.new(4), -0.5)
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new("0.5"))
    end

    test "a Decimal base with a non-integer exponent greater than one" do
      # Previously crashed: Decimal.mult/2 received the float produced
      # by the fractional-exponent escape hatch.
      result = Math.power(Decimal.new(2), 2.5)
      assert %Decimal{} = result
      assert_in_delta Decimal.to_float(result), :math.pow(2, 2.5), 1.0e-9
    end
  end
end
