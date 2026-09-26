defmodule Localize.Data.LocaleTransformerTest do
  use ExUnit.Case, async: true

  alias Localize.Data.LocaleTransformer
  alias Localize.Number.Symbol

  test "generating nb leaves out only its alternative time separator \".\"" do
    %{number_symbols: %{latn: symbols}} = Localize.Data.Locale.generate_and_transform("nb")

    assert %Symbol{time_separator: ":", approximately_sign: "ca.", decimal: %{standard: ","}} =
             symbols
  end

  test "a number symbol that CLDR adds and the struct does not know fails the generation" do
    assert_raise KeyError, ~r/key :digit_marker not found/, fn ->
      LocaleTransformer.transform(%{number_symbols: %{latn: %{decimal: ".", digit_marker: "#"}}})
    end
  end

  test "a number format that the struct does not know fails the generation" do
    assert_raise KeyError, ~r/key :currency_with_iso not found/, fn ->
      LocaleTransformer.transform(%{
        number_formats: %{latn: %{standard: "#,##0.###", currency_with_iso: [0, " ¤¤"]}}
      })
    end
  end

  test "a currency field that the struct does not know fails the generation" do
    assert_raise KeyError, ~r/key :symbol_alt_formal not found/, fn ->
      LocaleTransformer.transform(%{
        currencies: %{CHF: %{code: "CHF", count: %{}, symbol_alt_formal: "SFr."}}
      })
    end
  end
end
