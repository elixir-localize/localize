defmodule Localize.Number.ShortFormatterTest do
  use ExUnit.Case, async: true

  describe "short decimal formatting" do
    test "short format for thousands" do
      # ICU compact default: at most two significant digits on the
      # mantissa, so 1234 renders "1.2K" (not "1K").
      assert {:ok, "1.2K"} = Localize.Number.to_string(1234, format: :decimal_short)
    end

    test "short format for millions" do
      assert {:ok, "523M"} = Localize.Number.to_string(523_456_789, format: :decimal_short)
    end

    test "short format for billions" do
      assert {:ok, "7.2B"} = Localize.Number.to_string(7_234_567_890, format: :decimal_short)
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

  describe ":short and :long format aliases" do
    test ":short resolves to :decimal_short without a currency" do
      assert Localize.Number.to_string(1234, format: :short) ==
               Localize.Number.to_string(1234, format: :decimal_short)
    end

    test ":long resolves to :decimal_long without a currency" do
      assert Localize.Number.to_string(1234, format: :long) ==
               Localize.Number.to_string(1234, format: :decimal_long)
    end

    test ":short resolves to :currency_short with a currency" do
      assert Localize.Number.to_string(1234, format: :short, currency: :USD) ==
               Localize.Number.to_string(1234, format: :currency_short, currency: :USD)

      assert {:ok, "$1.2K"} = Localize.Number.to_string(1234, format: :short, currency: :USD)
    end

    test ":long resolves to :currency_long with a currency" do
      assert Localize.Number.to_string(1234, format: :long, currency: :USD) ==
               Localize.Number.to_string(1234, format: :currency_long, currency: :USD)

      assert {:ok, "1,234 US dollars"} =
               Localize.Number.to_string(1234, format: :long, currency: :USD)
    end

    test "aliases honour number format options" do
      assert {:ok, "1.2K"} =
               Localize.Number.to_string(1234.5,
                 format: :short,
                 rounding_mode: :floor,
                 fractional_digits: 1
               )
    end
  end
end
