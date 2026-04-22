defmodule Localize.NumberTest do
  use ExUnit.Case, async: true

  doctest Localize.Number

  describe "to_string/2" do
    test "formats an integer with default locale" do
      assert {:ok, "1,234"} = Localize.Number.to_string(1234)
    end

    test "formats a float" do
      assert {:ok, "1,234.5"} = Localize.Number.to_string(1234.5)
    end

    test "formats a Decimal with the same output as the equivalent float" do
      assert {:ok, "1,234.5"} = Localize.Number.to_string(Decimal.new("1234.5"))

      assert Localize.Number.to_string(1234.5) ==
               Localize.Number.to_string(Decimal.new("1234.5"))
    end

    test "formats zero" do
      assert {:ok, "0"} = Localize.Number.to_string(0)
    end

    test "formats negative number" do
      {:ok, result} = Localize.Number.to_string(-1234)
      assert String.contains?(result, "1,234")
    end

    test "formats with percent" do
      assert {:ok, "56%"} = Localize.Number.to_string(0.56, format: :percent)
    end

    test "formats a Decimal with percent identically to the float" do
      assert {:ok, "56%"} = Localize.Number.to_string(Decimal.new("0.56"), format: :percent)

      assert Localize.Number.to_string(0.56, format: :percent) ==
               Localize.Number.to_string(Decimal.new("0.56"), format: :percent)
    end

    test "formats with scientific notation" do
      {:ok, result} = Localize.Number.to_string(1234, format: :scientific)
      assert String.contains?(result, "E")
    end

    test "formats a Decimal" do
      assert {:ok, "1,234.56"} = Localize.Number.to_string(Decimal.new("1234.56"))
    end

    test "formats with specific locale" do
      {:ok, result} = Localize.Number.to_string(1234.5, locale: :de)
      assert String.contains?(result, "1")
    end

    test "formats a Decimal in a specific locale identically to the float" do
      assert Localize.Number.to_string(1234.5, locale: :de) ==
               Localize.Number.to_string(Decimal.new("1234.5"), locale: :de)
    end
  end

  describe "to_string!/2" do
    test "returns formatted string" do
      assert "1,234" = Localize.Number.to_string!(1234)
    end
  end
end
