defmodule Localize.Number.ExponentTest do
  use ExUnit.Case, async: true

  describe "integer exponent formatting" do
    test "integer with precision" do
      assert {:ok, "1.2E3"} = Localize.Number.to_string(1234, format: "0.0E0")
      assert {:ok, "1.23E3"} = Localize.Number.to_string(1234, format: "0.00E0")
      assert {:ok, "1.234E3"} = Localize.Number.to_string(1234, format: "0.000E0")
    end
  end

  describe "float exponent formatting" do
    test "float with precision" do
      assert {:ok, "1.2E3"} = Localize.Number.to_string(1234.5678, format: "0.0E0")
      assert {:ok, "1.23E3"} = Localize.Number.to_string(1234.5678, format: "0.00E0")
      assert {:ok, "1.235E3"} = Localize.Number.to_string(1234.5678, format: "0.000E0")
    end
  end

  describe "Decimal exponent formatting" do
    test "Decimal with precision" do
      assert {:ok, "1.2E3"} =
               Localize.Number.to_string(Decimal.new("1234.5678"), format: "0.0E0")

      assert {:ok, "1.23E3"} =
               Localize.Number.to_string(Decimal.new("1234.5678"), format: "0.00E0")

      assert {:ok, "1.235E3"} =
               Localize.Number.to_string(Decimal.new("1234.5678"), format: "0.000E0")
    end

    test "Decimal and float produce identical scientific output" do
      for format <- ["0.0E0", "0.00E0", "0.000E0"] do
        assert Localize.Number.to_string(1234.5678, format: format) ==
                 Localize.Number.to_string(Decimal.new("1234.5678"), format: format)
      end
    end
  end

  describe "exponent precision" do
    test "integer with exponent precision padding" do
      assert {:ok, "1.2E03"} = Localize.Number.to_string(1234, format: "0.0E00")
      assert {:ok, "1.23E003"} = Localize.Number.to_string(1234, format: "0.00E000")
      assert {:ok, "1.234E0003"} = Localize.Number.to_string(1234, format: "0.000E0000")
    end
  end

  # TR35 engineering notation: the exponent is forced to a multiple of
  # the pattern's maximum integer-digit count and the mantissa shifts
  # right to absorb the difference. The two TR35-spec examples are:
  #
  #     ##0.#####E0  on 12345   → 12.345E3
  #     ##0.#####E0  on 123456  → 123.456E3
  #
  # We additionally test mantissa-precision interaction, negative
  # exponents, the multiple-of-grouping fast path (no shift), and the
  # fixed-width-mantissa variant (`00.###E0`, `min == max`, shift =
  # `min - 1`).
  describe "engineering notation (##0.#####E0)" do
    test "TR35 example: 12345 → 12.345E3" do
      assert {:ok, "12.345E3"} = Localize.Number.to_string(12345, format: "##0.#####E0")
    end

    test "TR35 example: 123456 → 123.456E3" do
      assert {:ok, "123.456E3"} = Localize.Number.to_string(123_456, format: "##0.#####E0")
    end

    test "value already at a grouping boundary: 1234567 → 1.234567E6 (no shift)" do
      assert {:ok, "1.234567E6"} = Localize.Number.to_string(1_234_567, format: "##0.#####E0")
    end

    test "negative number: -12345 → -12.345E3" do
      assert {:ok, "-12.345E3"} = Localize.Number.to_string(-12345, format: "##0.#####E0")
    end

    test "small value: 0.000123 → 123E-6 (engineering, mantissa shifted)" do
      assert {:ok, "123E-6"} = Localize.Number.to_string(0.000123, format: "##0.###E0")
    end

    test "Decimal precision preserved exactly through engineering shift" do
      assert {:ok, "12.345E3"} =
               Localize.Number.to_string(Decimal.new("12345"), format: "##0.#####E0")

      assert {:ok, "123E-6"} =
               Localize.Number.to_string(Decimal.new("0.000123"), format: "##0.###E0")
    end

    test "Decimal and float produce identical engineering output" do
      for value <- [12345, 123_456, 1_234_567, 0.000123] do
        decimal_value =
          if is_float(value), do: Decimal.from_float(value), else: Decimal.new(value)

        assert Localize.Number.to_string(value, format: "##0.#####E0") ==
                 Localize.Number.to_string(decimal_value, format: "##0.#####E0")
      end
    end

    test "zero formats without shift: 0 → 0E0" do
      assert {:ok, "0E0"} = Localize.Number.to_string(0, format: "##0.###E0")
      assert {:ok, "0E0"} = Localize.Number.to_string(0.0, format: "##0.###E0")
      assert {:ok, "0E0"} = Localize.Number.to_string(Decimal.new(0), format: "##0.###E0")
    end

    test "every engineering exponent is a multiple of 3" do
      # Cover a range of magnitudes; the rendered exponent (after `E`)
      # must always be divisible by 3.
      for power <- -10..10 do
        value = :math.pow(10, power) * 1.5
        assert {:ok, output} = Localize.Number.to_string(value, format: "##0.###E0")
        [_mantissa, exp_str] = String.split(output, "E")
        assert rem(String.to_integer(exp_str), 3) == 0, "power #{power} → #{output}"
      end
    end
  end

  # `00.###E0` is the fixed-width mantissa form: mantissa always has
  # exactly `min_integer_digits` (= 2) integer digits, exponent shifts
  # by `min - 1` (= 1) regardless of value.
  describe "fixed-width mantissa (00.###E0)" do
    test "0.00123 → 12.3E-4" do
      assert {:ok, "12.3E-4"} = Localize.Number.to_string(0.00123, format: "00.###E0")
    end

    test "1.23 → 12.3E-1" do
      assert {:ok, "12.3E-1"} = Localize.Number.to_string(1.23, format: "00.###E0")
    end

    test "123 → 12.3E1" do
      assert {:ok, "12.3E1"} = Localize.Number.to_string(123, format: "00.###E0")
    end
  end
end
