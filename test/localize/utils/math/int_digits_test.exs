defmodule Localize.Utils.Math.IntDigitsTest do
  use ExUnit.Case, async: true

  alias Localize.Utils.Digits

  @digits [
    {1, 1},
    {12, 2},
    {1.0, 1},
    {12.0, 2},
    {0.1, 0},
    {0.001, 0},
    {1234, 4},
    {1234.5678, 4}
  ]

  Enum.each(@digits, fn {num, digits} ->
    test "that #{inspect(num)} has #{inspect(digits)} digits" do
      assert Digits.number_of_integer_digits(unquote(num)) == unquote(digits)
    end
  end)
end
