defmodule Localize.Number.CurrencySeparatorTest do
  use ExUnit.Case, async: true

  alias Localize.Number

  # CLDR gives fr-CH the currency decimal "." and de-AT the currency
  # group ".". Plain numbers keep the standard separators. The expected
  # strings match ICU 78.3.

  test "fr-CH CHF 1234.56 formats as 1'234.56 CHF, the plain number as 1'234,56" do
    assert Number.to_string(1234.56, locale: "fr-CH", currency: :CHF) ==
             {:ok, "1'234.56 CHF"}

    assert Number.to_string(1234.56, locale: "fr-CH") == {:ok, "1'234,56"}
  end

  test "de-AT EUR 1234.56 formats as € 1.234,56, the plain number as 1 234,56" do
    assert Number.to_string(1234.56, locale: "de-AT", currency: :EUR) ==
             {:ok, "€ 1.234,56"}

    assert Number.to_string(1234.56, locale: "de-AT") == {:ok, "1 234,56"}
  end

  test "fr-CH CHF 1234.56 as parts has the decimal part \".\"" do
    assert {:ok, parts} = Number.to_parts(1234.56, locale: "fr-CH", currency: :CHF)
    assert %{type: :decimal, value: "."} in parts
    assert Enum.map_join(parts, & &1.value) == "1'234.56 CHF"
  end

  test "fr-CH CHF 1234.56 keeps the decimal dot in the long, accounting, and symbol-free formats" do
    options = [locale: "fr-CH", currency: :CHF]

    assert Number.to_string(1234.56, [format: :currency_long] ++ options) ==
             {:ok, "1'234.56 francs suisses"}

    assert Number.to_string(-1234.56, [format: :accounting] ++ options) ==
             {:ok, "(1'234.56 CHF)"}

    assert Number.to_string(1234.56, [currency_symbol: :none] ++ options) == {:ok, "1'234.56"}
  end

  test "de-AT EUR 1234.56 in a :currency message formats as € 1.234,56" do
    assert Localize.Message.format("{$amount :currency currency=EUR}", %{"amount" => 1234.56},
             locale: "de-AT"
           ) == {:ok, "€ 1.234,56"}
  end
end
