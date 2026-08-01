defmodule Localize.Utils.Math.LogTest do
  use ExUnit.Case, async: false

  alias Localize.Utils.Decimal, as: LDecimal
  alias Localize.Utils.Math

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

  # A fixed seed, and `uniform_s/2` rather than `uniform/1`, so the sample
  # is the same on every run and the RNG state of the loading process is
  # left alone. Drawing 500 values from 10_000 collides often enough that
  # `Enum.uniq/1` otherwise left a different number of tests each run.
  random =
    1..500
    |> Enum.map_reduce(:rand.seed_s(:exsss, {101, 102, 103}), fn _i, seed ->
      {value, next_seed} = :rand.uniform_s(10_000, seed)
      {value / 10, next_seed}
    end)
    |> elem(0)
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
