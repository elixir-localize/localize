defmodule Localize.Number.SymbolTest do
  use ExUnit.Case, async: true

  doctest Localize.Number.Symbol

  alias Localize.Number.Symbol

  describe "number_symbols_for/1" do
    test "returns symbols for a locale" do
      {:ok, symbols} = Symbol.number_symbols_for(:en)
      assert %Symbol{} = symbols[:latn]
    end

    test "returns symbols with expected fields for English" do
      {:ok, symbols} = Symbol.number_symbols_for(:en)
      latn = symbols[:latn]
      assert latn.percent_sign == "%"
      assert latn.plus_sign == "+"
      assert latn.minus_sign == "-"
      assert latn.exponential == "E"
      assert latn.infinity == "∞"
      assert latn.nan == "NaN"
    end
  end

  describe "number_symbols_for/2" do
    test "returns symbols for a specific number system" do
      {:ok, symbol} = Symbol.number_symbols_for(:en, :latn)
      assert %Symbol{} = symbol
    end

    test "returns error for unknown number system" do
      {:error, _exception} = Symbol.number_symbols_for(:en, :nope)
    end
  end
end
