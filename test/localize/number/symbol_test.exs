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

    # Regression: `to_system_atom/1` used to call `String.to_atom/1`
    # on unknown binary system names, growing the atom table on each
    # call. Now gated by `Helpers.existing_atom/1`.
    test "does not create an atom for unknown binary system name" do
      bogus = "ZZZ_sym_#{Elixir.System.unique_integer([:positive])}"
      assert {:error, _} = Symbol.number_symbols_for(:en, bogus)
      assert nil == Localize.Utils.Helpers.existing_atom(bogus)
    end
  end
end
