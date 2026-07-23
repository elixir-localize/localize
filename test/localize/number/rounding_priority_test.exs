defmodule Localize.Number.RoundingPriorityTest do
  use ExUnit.Case, async: true

  # ECMA-402 `roundingPriority`. Expected values verified against
  # `Intl.NumberFormat`, including the MDN reference example
  # (1.23456 with maximumFractionDigits 3 and
  # maximumSignificantDigits 2).

  @bounds [max_fractional_digits: 3, maximum_significant_digits: 2]

  describe ":rounding_priority" do
    test "the default lets significant digits win" do
      assert {:ok, "1.2"} = Localize.Number.to_string(1.23456, @bounds)

      assert {:ok, "1.2"} =
               Localize.Number.to_string(1.23456, @bounds ++ [rounding_priority: :auto])
    end

    test "the default ignores a binding fraction bound when significant digits are set" do
      bounds = [max_fractional_digits: 1, maximum_significant_digits: 3]

      assert {:ok, "4.32"} = Localize.Number.to_string(4.321, bounds)

      assert {:ok, "4.32"} =
               Localize.Number.to_string(4.321, bounds ++ [rounding_priority: :auto])

      assert {:ok, "1.00"} =
               Localize.Number.to_string(1,
                 max_fractional_digits: 1,
                 minimum_significant_digits: 3
               )
    end

    test ":more_precision picks the bound yielding more digits" do
      assert {:ok, "1.235"} =
               Localize.Number.to_string(1.23456, @bounds ++ [rounding_priority: :more_precision])
    end

    test ":less_precision picks the bound yielding fewer digits" do
      assert {:ok, "1.2"} =
               Localize.Number.to_string(1.23456, @bounds ++ [rounding_priority: :less_precision])
    end

    test "the winner depends on the value's magnitude" do
      bounds = [max_fractional_digits: 2, maximum_significant_digits: 3]

      assert {:ok, "12,345.68"} =
               Localize.Number.to_string(
                 12_345.678,
                 bounds ++ [rounding_priority: :more_precision]
               )

      assert {:ok, "12,300"} =
               Localize.Number.to_string(
                 12_345.678,
                 bounds ++ [rounding_priority: :less_precision]
               )
    end

    test "no-op unless both bound groups are present" do
      assert {:ok, "1"} = Localize.Number.to_string(1, rounding_priority: :more_precision)

      assert {:ok, "1.23"} =
               Localize.Number.to_string(1.23456,
                 max_fractional_digits: 2,
                 rounding_priority: :less_precision
               )
    end

    test "works with Decimal input" do
      assert {:ok, "1.235"} =
               Localize.Number.to_string(
                 Decimal.new("1.23456"),
                 @bounds ++ [rounding_priority: :more_precision]
               )
    end

    test "an invalid value is an error" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Number.to_string(1, rounding_priority: :sometimes)
    end
  end
end
