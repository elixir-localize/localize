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
      assert 12_300 == Math.round_significant(12_345, 3)
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
      result = Math.round_significant(Decimal.new(12_345), 3)
      assert Decimal.equal?(result, Decimal.new(12_300))
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

  describe "round_significant zero-handling regression" do
    # `:math.log10(0)` raises `ArithmeticError`. Pre-fix this also
    # crashed the public `Localize.Number.to_string/2` for any
    # input of `0` paired with a significant-digit pattern or
    # option.
    test "zero integer is its own significant-digit form" do
      assert 0 == Math.round_significant(0, 3)
      assert 0 == Math.round_significant(0, 1)
    end

    test "zero float is its own significant-digit form" do
      assert +0.0 === Math.round_significant(+0.0, 3)
    end

    test "negative zero float is its own significant-digit form" do
      assert -0.0 === Math.round_significant(-0.0, 3)
    end
  end

  describe "minimum/maximum_significant_digits options on Localize.Number.to_string/2" do
    # ECMA-402 / TR35 expose `:minimumSignificantDigits` and
    # `:maximumSignificantDigits` as caller-supplied options. The
    # internal mechanism (the `significant_digits` field on the
    # format Meta struct, plus
    # `Localize.Utils.Math.round_significant/2`) was already
    # present for pattern-based usage (`@@##`); this exposes it
    # via the Options API.

    test "maximum_significant_digits truncates a fractional number" do
      assert {:ok, "0.0012"} =
               Localize.Number.to_string(0.001234, maximum_significant_digits: 2)
    end

    test "maximum_significant_digits rounds a large integer to trailing zeros" do
      assert {:ok, "1,230,000"} =
               Localize.Number.to_string(1_234_567, maximum_significant_digits: 3)
    end

    test "maximum_significant_digits applied to a small decimal" do
      assert {:ok, "0.000123"} =
               Localize.Number.to_string(0.00012345, maximum_significant_digits: 3)
    end

    test "minimum and maximum together — exactly 5 significant digits" do
      assert {:ok, "123.46"} =
               Localize.Number.to_string(
                 123.456,
                 minimum_significant_digits: 5,
                 maximum_significant_digits: 5
               )
    end

    test "minimum_significant_digits without maximum lets a high-precision input through" do
      # min: 5, max defaults to 21 (ECMA-402 ceiling). 123.456
      # already has 6 sig digits which is in range — output as-is.
      assert {:ok, "123.456"} =
               Localize.Number.to_string(123.456, minimum_significant_digits: 5)
    end

    test "zero formats cleanly with significant-digit options (no crash)" do
      # Pre-fix this crashed with ArithmeticError because
      # `:math.log10(0)` is undefined. Integer and float zero both
      # render "0" per ECMA-402/ICU: with only a maximum set, the
      # minimum significant digits default to 1 and zero carries no
      # forced fraction. A minimum forces trailing zeros instead.
      assert {:ok, "0"} = Localize.Number.to_string(0, maximum_significant_digits: 3)
      assert {:ok, "0"} = Localize.Number.to_string(0.0, maximum_significant_digits: 3)
      assert {:ok, "0.00"} = Localize.Number.to_string(0.0, minimum_significant_digits: 3)
    end

    test "no significant-digit option leaves output identical to default" do
      assert Localize.Number.to_string(1234.5678) ==
               Localize.Number.to_string(1234.5678, [])
    end

    test "no fraction digit is forced when rounding yields an integral value" do
      # ICU renders 1234.567 at 3 significant digits as "1,230" — the
      # significant digits are satisfied by the integer part, so no
      # trailing ".0" may be forced (TR35; previously "1,230.0").
      assert {:ok, "1,230"} = Localize.Number.to_string(1234.567, maximum_significant_digits: 3)

      assert {:ok, "1,230"} =
               Localize.Number.to_string(Decimal.new("1234.567"), maximum_significant_digits: 3)
    end

    test "minimum significant digits force trailing fraction zeros" do
      assert {:ok, "1.00"} = Localize.Number.to_string(1.0, minimum_significant_digits: 3)
      assert {:ok, "1.00"} = Localize.Number.to_string(1, minimum_significant_digits: 3)
      assert {:ok, "12.3"} = Localize.Number.to_string(12.3, minimum_significant_digits: 3)
      assert {:ok, "0.500"} = Localize.Number.to_string(0.5, minimum_significant_digits: 3)
    end

    test "Decimal input honours significant-digit options" do
      assert {:ok, "0.0012"} =
               Localize.Number.to_string(
                 Decimal.new("0.001234"),
                 maximum_significant_digits: 2
               )
    end

    test "rejects minimum_significant_digits below 1" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Number.to_string(123, minimum_significant_digits: 0)
    end

    test "rejects minimum_significant_digits above 21" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Number.to_string(123, minimum_significant_digits: 22)
    end

    test "rejects negative maximum_significant_digits" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Number.to_string(123, maximum_significant_digits: -1)
    end

    test "rejects non-integer significant-digit options" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Number.to_string(123, maximum_significant_digits: 2.5)
    end

    test "rejects maximum < minimum" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Number.to_string(
                 123,
                 minimum_significant_digits: 5,
                 maximum_significant_digits: 3
               )
    end

    test "options struct can be reused across calls" do
      {:ok, opts} =
        Localize.Number.Format.Options.validate_options(0, maximum_significant_digits: 3)

      assert {:ok, "1,230"} = Localize.Number.to_string(1234, opts)
      assert {:ok, "12,300"} = Localize.Number.to_string(12_345, opts)
    end
  end
end
