defmodule Localize.Number.CurrencyParseTest do
  use ExUnit.Case, async: true

  alias Localize.Number

  # Amounts as `Localize.Number.to_string/2` formats them with
  # `currency_symbol: :none`.
  @amounts [
    {"de-CH", :CHF, 1234.56, "1'234.56"},
    {"de-CH", :CHF, -1234.56, "-1'234.56"},
    {"fr-CH", :CHF, 1234.56, "1'234.56"},
    {"fr-CH", :CHF, -1234.56, "-1'234.56"},
    {"de-AT", :EUR, 1234.56, "1.234,56"},
    {"de-AT", :EUR, -1234.56, "-1.234,56"},
    {"en", :USD, 1234.56, "1,234.56"},
    {"en", :USD, -1234.56, "-1,234.56"},
    {"sv", :SEK, 1234.56, "1 234,56"},
    {"sv", :SEK, -1234.56, "−1 234,56"},
    {"ar", :EGP, 1234.56, "‏1,234.56"},
    {"ar", :EGP, -1234.56, "‏‎-1,234.56"},
    {"pt-CV", :CVE, 1_234_567.5, "1 234 567$50"}
  ]

  for {locale, currency, amount, string} <- @amounts do
    test "#{locale} #{currency} #{amount} formats as #{inspect(string)} and parses back" do
      options = [locale: unquote(locale), currency: unquote(currency)]

      assert Number.to_string(unquote(amount), [currency_symbol: :none] ++ options) ==
               {:ok, unquote(string)}

      assert Number.parse(unquote(string), options) == {:ok, unquote(amount)}
    end
  end

  test "de-AT reads 1.234 as 1234 as an EUR amount and as 1.234 as a plain number" do
    assert Number.parse("1.234", locale: "de-AT", currency: :EUR) == {:ok, 1234}
    assert Number.parse("1.234", locale: "de-AT") == {:ok, 1.234}
  end

  test "fr-CH reads 1'234.56 as a CHF amount but not as a plain number" do
    assert Number.parse("1'234.56", locale: "fr-CH", currency: :CHF) == {:ok, 1234.56}
    assert {:error, _} = Number.parse("1'234.56", locale: "fr-CH")
  end

  test "de-AT scans € 1.234,56 as one EUR amount and as two plain numbers" do
    assert Number.scan("€ 1.234,56", locale: "de-AT", currency: :EUR) == ["€ ", 1234.56]
    assert Number.scan("€ 1.234,56", locale: "de-AT") == ["€ ", 1, ".", 234.56]
  end

  test "parses with a currency struct as with its code" do
    {:ok, currency} = Localize.Currency.currency_for_code(:EUR, locale: "de-AT")
    assert Number.parse("1.234,56", locale: "de-AT", currency: currency) == {:ok, 1234.56}
  end

  test "an unknown currency is an error" do
    assert Number.parse("1.234,56", locale: "de-AT", currency: :XYZ) ==
             {:error, %Localize.UnknownCurrencyError{currency: :XYZ}}

    assert Number.scan("€ 1.234,56", locale: "de-AT", currency: :XYZ) ==
             {:error, %Localize.UnknownCurrencyError{currency: :XYZ}}
  end
end
