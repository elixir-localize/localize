defmodule Localize.Number.ParserTest do
  use ExUnit.Case, async: true

  doctest Localize.Number.Parser

  alias Localize.Number.Parser

  describe "parse/2" do
    test "parses an integer string" do
      assert {:ok, 1234} = Parser.parse("1234")
    end

    test "parses a float string" do
      assert {:ok, 1234.56} = Parser.parse("1234.56")
    end

    test "parses a negative number" do
      assert {:ok, -1_000_000.34} = Parser.parse("-1_000_000.34")
    end

    test "returns error for non-numeric string" do
      {:error, _} = Parser.parse("not a number")
    end
  end

  describe "scan/2" do
    test "scans a string with a number" do
      result = Parser.scan("The prize is 23")
      assert ["The prize is ", 23] = result
    end

    test "scans a number followed by text" do
      result = Parser.scan("1kg")
      assert [1, "kg"] = result
    end
  end

  describe "resolve_per/2" do
    test "resolves percent symbol" do
      result = Parser.resolve_per("11%")
      assert ["11", :percent] = result
    end
  end
end
