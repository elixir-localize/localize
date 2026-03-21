defmodule Localize.Number.ExponentTest do
  use ExUnit.Case, async: true

  describe "integer exponent formatting" do
    test "integer with precision" do
      assert {:ok, "1.2E3"} = Localize.Number.to_string(1234, format: "0.0E0")
      assert {:ok, "1.23E3"} = Localize.Number.to_string(1234, format: "0.00E0")
      assert {:ok, "1.234E3"} = Localize.Number.to_string(1234, format: "0.000E0")
    end
  end

  describe "float exponent formatting" do
    test "float with precision" do
      assert {:ok, "1.2E3"} = Localize.Number.to_string(1234.5678, format: "0.0E0")
      assert {:ok, "1.23E3"} = Localize.Number.to_string(1234.5678, format: "0.00E0")
      assert {:ok, "1.235E3"} = Localize.Number.to_string(1234.5678, format: "0.000E0")
    end
  end

  describe "Decimal exponent formatting" do
    test "Decimal with precision" do
      assert {:ok, "1.2E3"} =
               Localize.Number.to_string(Decimal.new("1234.5678"), format: "0.0E0")

      assert {:ok, "1.23E3"} =
               Localize.Number.to_string(Decimal.new("1234.5678"), format: "0.00E0")

      assert {:ok, "1.235E3"} =
               Localize.Number.to_string(Decimal.new("1234.5678"), format: "0.000E0")
    end
  end

  describe "exponent precision" do
    test "integer with exponent precision padding" do
      assert {:ok, "1.2E03"} = Localize.Number.to_string(1234, format: "0.0E00")
      assert {:ok, "1.23E003"} = Localize.Number.to_string(1234, format: "0.00E000")
      assert {:ok, "1.234E0003"} = Localize.Number.to_string(1234, format: "0.000E0000")
    end
  end
end
