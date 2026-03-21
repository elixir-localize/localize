defmodule Localize.Number.ShortFormatterTest do
  use ExUnit.Case, async: true

  describe "short decimal formatting" do
    test "short format for thousands" do
      assert {:ok, "1K"} = Localize.Number.to_string(1234, format: :decimal_short)
    end

    test "short format for millions" do
      assert {:ok, "523M"} = Localize.Number.to_string(523_456_789, format: :decimal_short)
    end

    test "short format for billions" do
      assert {:ok, "7B"} = Localize.Number.to_string(7_234_567_890, format: :decimal_short)
    end

    test "short format below 1000 uses standard" do
      assert {:ok, "123"} = Localize.Number.to_string(123, format: :decimal_short)
    end

    test "short format for Decimal" do
      assert {:ok, "1M"} =
               Localize.Number.to_string(Decimal.new(1_000_000), format: :decimal_short)
    end

    test "short format for negative Decimal" do
      assert {:ok, "-1M"} =
               Localize.Number.to_string(Decimal.new(-1_000_000), format: :decimal_short)
    end

    test "short format for negative number" do
      assert {:ok, "-100K"} =
               Localize.Number.to_string(Decimal.new(-100_000), format: :decimal_short)
    end
  end

  describe "long decimal formatting" do
    test "long format for thousands" do
      {:ok, result} = Localize.Number.to_string(1234, format: :decimal_long)
      assert String.contains?(result, "thousand")
    end

    test "long format for millions" do
      {:ok, result} = Localize.Number.to_string(7_000_000, format: :decimal_long)
      assert String.contains?(result, "million")
    end
  end
end
