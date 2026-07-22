defmodule Localize.Number.MinimumIntegerDigitsTest do
  use ExUnit.Case, async: true

  # ECMA-402 `minimumIntegerDigits`: zero-pad the integer part to
  # the requested width. Expected values verified against
  # `Intl.NumberFormat`.

  describe ":minimum_integer_digits" do
    test "zero-pads and groups the padding digits" do
      assert {:ok, "00,123"} = Localize.Number.to_string(123, minimum_integer_digits: 5)
    end

    test "preserves the fraction" do
      assert {:ok, "00,123.45"} = Localize.Number.to_string(123.45, minimum_integer_digits: 5)
    end

    test "is a no-op when the number is already wider" do
      assert {:ok, "1,234,567"} = Localize.Number.to_string(1_234_567, minimum_integer_digits: 3)
    end

    test "applies locale grouping and symbols" do
      assert {:ok, "01"} = Localize.Number.to_string(1, minimum_integer_digits: 2, locale: :de)

      assert {:ok, "00.123,45"} =
               Localize.Number.to_string(123.45, minimum_integer_digits: 5, locale: :de)
    end

    test "composes with currency formatting" do
      assert {:ok, "$00,001,234.50"} =
               Localize.Number.to_string(1234.5, minimum_integer_digits: 8, currency: :USD)
    end

    test "applies to negative numbers inside the sign" do
      assert {:ok, "-0,042"} = Localize.Number.to_string(-42, minimum_integer_digits: 4)
    end

    test "rejects values outside 1..21" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Number.to_string(1, minimum_integer_digits: 0)

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Number.to_string(1, minimum_integer_digits: 22)

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Number.to_string(1, minimum_integer_digits: 1.5)
    end
  end
end
