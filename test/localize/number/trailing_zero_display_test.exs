defmodule Localize.Number.TrailingZeroDisplayTest do
  use ExUnit.Case, async: true

  # ECMA-402 `trailingZeroDisplay`. Expected values verified against
  # `Intl.NumberFormat`.

  describe "trailing_zero_display: :strip_if_integer" do
    test "drops the fraction when the value is an integer" do
      assert {:ok, "1,000"} =
               Localize.Number.to_string(1000,
                 fractional_digits: 2,
                 trailing_zero_display: :strip_if_integer
               )
    end

    test "keeps the fraction when the value is not an integer" do
      assert {:ok, "1,000.50"} =
               Localize.Number.to_string(1000.5,
                 fractional_digits: 2,
                 trailing_zero_display: :strip_if_integer
               )
    end

    test "applies after rounding" do
      assert {:ok, "1,000"} =
               Localize.Number.to_string(999.999,
                 fractional_digits: 2,
                 trailing_zero_display: :strip_if_integer
               )
    end

    test "composes with currency formatting" do
      assert {:ok, "$1,000"} =
               Localize.Number.to_string(1000,
                 currency: :USD,
                 trailing_zero_display: :strip_if_integer
               )

      assert {:ok, "$10.50"} =
               Localize.Number.to_string(10.5,
                 currency: :USD,
                 trailing_zero_display: :strip_if_integer
               )
    end

    test ":auto and unset keep the minimum-fraction padding" do
      assert {:ok, "1,000.00"} = Localize.Number.to_string(1000, fractional_digits: 2)

      assert {:ok, "1,000.00"} =
               Localize.Number.to_string(1000, fractional_digits: 2, trailing_zero_display: :auto)
    end

    test "an invalid value is an error" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Number.to_string(1000, trailing_zero_display: :sometimes)
    end
  end
end
