defmodule Localize.Utils.Math.CoefExponentTest do
  use ExUnit.Case, async: true

  alias Localize.Utils.Decimal, as: LDecimal
  alias Localize.Utils.Math

  @test [
    1.23004,
    12.345,
    645.978,
    0.00345,
    0.0123,
    0.1,
    -0.1,
    -1,
    0.3,
    0.99,
    0,
    0.0,
    1,
    5,
    10,
    17,
    47,
    107,
    507,
    1000,
    1007,
    2345,
    40_000
  ]

  @ten Decimal.new(10)

  Enum.each(@test, fn value ->
    test "Validate coef * 10**exponent == original number of #{inspect(value)}" do
      test_value = value(unquote(Macro.escape(value)))

      # Calculate the mantissa and exponent
      {coef, exponent} = Math.coef_exponent(test_value)

      # And then recalculate the decimal value
      calculated_value =
        @ten
        |> Math.power(exponent)
        |> Decimal.mult(coef)

      # And confirm we made the round trip
      assert LDecimal.compare(calculated_value, test_value) == :eq
    end
  end)

  def value(value) when is_float(value), do: Decimal.new(to_string(value))
  def value(value), do: Decimal.new(value)
end
