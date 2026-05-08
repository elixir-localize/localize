defmodule Localize.Utils.Math.LogTest do
  use ExUnit.Case, async: false

  alias Localize.Utils.Math
  alias Localize.Utils.Decimal, as: LDecimal

  # Pin tests to a fixed Decimal.Context precision so high-precision fixtures
  # remain stable across Decimal versions whose default precision differs
  # (Decimal 2.x defaults to 28; Decimal 3.0 defaults to 34).
  @precision 28

  setup do
    original = Decimal.Context.get()
    Decimal.Context.set(%{original | precision: @precision})
    on_exit(fn -> Decimal.Context.set(original) end)
    :ok
  end

  @round 2
  @samples [
    {1, 0},
    {10, 2.30258509299},
    {1.23004, 0.20704668918075508}
  ]

  Enum.each(@samples, fn {sample, result} ->
    test "that decimal log(e) is correct for #{inspect(sample)}" do
      calc = Math.log(Decimal.new(unquote(to_string(sample)))) |> Decimal.round(@round)
      sample = Decimal.new(unquote(to_string(result))) |> Decimal.round(@round)
      assert LDecimal.compare(calc, sample) == :eq
    end
  end)

  random =
    for _i <- 1..500 do
      :rand.uniform(10000) / 10
    end
    |> Enum.uniq()

  @diff 0.005
  Enum.each(random, fn x ->
    test "that decimal log(e) is more or less the same as bif log(e) for #{inspect(x)}" do
      assert :math.log(unquote(x)) -
               Math.to_float(Math.log(Decimal.new(unquote(to_string(x))))) <
               @diff
    end
  end)

  # Testing large decimals that are beyond the precision of a float
  test "log Decimal.new(\"1.33333333333333333333333333333333\")" do
    assert LDecimal.compare(
             Math.log(Decimal.new("1.33333333333333333333333333333333")),
             Decimal.new("0.2876820724291554672132526174")
           ) == :eq
  end
end
