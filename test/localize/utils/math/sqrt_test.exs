defmodule Localize.Utils.Math.SqrtTest do
  use ExUnit.Case, async: false

  alias Localize.Utils.Math
  alias Localize.Utils.Decimal, as: LDecimal

  # Each of these is validated to return the original number when squared.
  # Computed at a fixed Decimal.Context precision of 28 so the expected values
  # are stable across Decimal versions whose default context precision differs.
  @precision 28
  @roots [
    {9, 3},
    {11, "3.316624790355399849114932737"},
    {465, "21.56385865284782467473394180"},
    {11.321, "3.364669374544845230862071572"},
    {0.1, "0.3162277660168379331998893544"}
  ]

  setup do
    original = Decimal.Context.get()
    Decimal.Context.set(%{original | precision: @precision})
    on_exit(fn -> Decimal.Context.set(original) end)
    :ok
  end

  Enum.each(@roots, fn {value, root} ->
    test "square root of #{inspect(value)} should be #{root}" do
      assert LDecimal.compare(
               Math.sqrt(Decimal.new(unquote(to_string(value)))),
               Decimal.new(unquote(to_string(root)))
             ) == :eq
    end
  end)

  test "result respects Decimal.Context.get/0 precision" do
    Decimal.Context.with(%{Decimal.Context.get() | precision: 20}, fn ->
      result = Math.sqrt(Decimal.new("0.1"))
      digits = result.coef |> Integer.to_string() |> byte_size()
      assert digits <= 20
    end)
  end

  test "result with default context precision is round-trippable" do
    Decimal.Context.with(%{Decimal.Context.get() | precision: 33}, fn ->
      result = Math.sqrt(Decimal.new("0.1"))
      assert {%Decimal{}, ""} = Decimal.parse(Decimal.to_string(result))
    end)
  end

  test "sqrt of a negative number raises" do
    assert_raise ArgumentError, ~r/bad argument in arithmetic expression/, fn ->
      Math.sqrt(Decimal.new(-5))
    end
  end
end
