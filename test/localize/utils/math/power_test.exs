defmodule Localize.Utils.Math.PowerTest do
  use ExUnit.Case, async: true

  alias Localize.Utils.Decimal, as: LDecimal
  alias Localize.Utils.Math

  @significance 15

  # On my machine, iterations over 12 bring bad karma
  @iterations 12

  Enum.each(-10..@iterations, fn n ->
    test "Confirm Math.power(5, n) for #{inspect(n)} returns the same result as :math.pow" do
      p =
        Math.power(5, unquote(n))
        |> Math.round_significant(@significance)

      q =
        :math.pow(5, unquote(n))
        |> Math.round_significant(@significance)

      assert p == q
    end

    # Decimal number, decimal power
    test "Confirm Decimal Math.power(5, n) for Decimal #{inspect(n)} returns the same result as :math.pow" do
      p =
        Math.power(Decimal.new(5), Decimal.new(unquote(n)))
        |> Math.round_significant(10)
        |> Decimal.to_float()

      q =
        :math.pow(5, unquote(n))
        |> Math.round_significant(10)

      assert p == q
    end
  end)

  test "Short cut decimal power of 10 for a positive number" do
    p = Math.power(Decimal.new(10), 2)
    assert LDecimal.compare(p, Decimal.new(100)) == :eq

    p = Math.power(Decimal.new(10), 3)
    assert LDecimal.compare(p, Decimal.new(1000)) == :eq

    p = Math.power(Decimal.new(10), 4)
    assert LDecimal.compare(p, Decimal.new(10_000)) == :eq
  end

  test "Short cut decimal power of 10 for a negative number" do
    p = Math.power(Decimal.new(10), -2)
    assert LDecimal.compare(p, Decimal.new("0.01")) == :eq

    p = Math.power(Decimal.new(10), -3)
    assert LDecimal.compare(p, Decimal.new("0.001")) == :eq

    p = Math.power(Decimal.new(10), -4)
    assert LDecimal.compare(p, Decimal.new("0.0001")) == :eq
  end

  test "A specific bug fix" do
    a = Decimal.new("0.00001232")
    b = Decimal.new("0.00001242")
    x = Decimal.sub(a, b)

    assert LDecimal.compare(Math.power(x, 2), Decimal.new("0.00000000000001")) == :eq
  end
end
