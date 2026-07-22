defmodule Localize.Number.CurrencyFormatTest do
  use ExUnit.Case, async: true

  alias Localize.Number

  describe ":currency_long format" do
    test "applies the currency fraction digits per ECMA-402 currencyDisplay name" do
      assert Number.to_string(123, format: :currency_long, currency: :USD) ==
               {:ok, "123.00 US dollars"}
    end

    test "plural selection follows the displayed value" do
      # "1.00" carries plural operand v=2 and selects :other in en,
      # matching Intl.NumberFormat: "1.00 US dollars".
      assert Number.to_string(1, format: :currency_long, currency: :USD) ==
               {:ok, "1.00 US dollars"}
    end

    test "singular currency name for one with no fraction digits" do
      assert Number.to_string(1, format: :currency_long, currency: :USD, fractional_digits: 0) ==
               {:ok, "1 US dollar"}
    end

    test "a zero-digit currency shows no fraction" do
      assert Number.to_string(1, format: :currency_long, currency: :JPY) ==
               {:ok, "1 Japanese yen"}
    end

    test "explicit fractional digits are honoured" do
      assert Number.to_string(1.5, format: :currency_long, currency: :USD, fractional_digits: 1) ==
               {:ok, "1.5 US dollars"}
    end

    test "German locale with euro" do
      assert Number.to_string(123, format: :currency_long, currency: :EUR, locale: "de") ==
               {:ok, "123,00 Euro"}
    end

    test "French locale with pounds sterling" do
      assert Number.to_string(2, format: :currency_long, currency: :GBP, locale: "fr") ==
               {:ok, "2,00 livres sterling"}
    end

    test "French singular for one with displayed fraction digits" do
      # fr selects :one for "1,00" (the i=1 rule ignores v), unlike en.
      assert Number.to_string(1, format: :currency_long, currency: :GBP, locale: "fr") ==
               {:ok, "1,00 livre sterling"}
    end

    test "Decimal amount is formatted with the currency default digits" do
      assert Number.to_string(Decimal.new("123.45"), format: :currency_long, currency: :USD) ==
               {:ok, "123.45 US dollars"}
    end

    test "string input returns an InvalidValueError" do
      assert {:error, %Localize.InvalidValueError{}} =
               Number.to_string("abc", format: :currency_long, currency: :USD)
    end
  end

  describe "currency_symbol option" do
    test ":iso uses the ISO code joined with a non-breaking space" do
      assert Number.to_string(1234.56, currency: :USD, currency_symbol: :iso) ==
               {:ok, "USD 1,234.56"}
    end

    test ":narrow uses the narrow symbol" do
      assert Number.to_string(1234.56, currency: :USD, currency_symbol: :narrow) ==
               {:ok, "$1,234.56"}
    end

    test ":none switches to the plain decimal format" do
      assert Number.to_string(1234.56, currency: :USD, currency_symbol: :none) ==
               {:ok, "1,234.56"}
    end

    test "default symbol for USD is the dollar sign" do
      assert Number.to_string(1234.56, currency: :USD) == {:ok, "$1,234.56"}
    end
  end

  describe "accounting format" do
    test "negative amounts are wrapped in parentheses" do
      assert Number.to_string(-1234.56, currency: :USD, format: :accounting) ==
               {:ok, "($1,234.56)"}
    end

    test "positive amounts are unaffected" do
      assert Number.to_string(1234.56, currency: :USD, format: :accounting) ==
               {:ok, "$1,234.56"}
    end
  end

  describe "currency_digits option" do
    test "JPY defaults to zero fractional digits" do
      assert Number.to_string(1234.56, currency: :JPY) == {:ok, "¥1,235"}
    end

    test "CHF cash rounding rounds to 0.05" do
      assert Number.to_string(1234.56, currency: :CHF, currency_digits: :cash, locale: "de-CH") ==
               {:ok, "CHF 1'234.55"}
    end

    test "CHF accounting digits keep the exact cents" do
      assert Number.to_string(1234.56, currency: :CHF, locale: "de-CH") ==
               {:ok, "CHF 1'234.56"}
    end

    test "TWD cash digits round to a whole number" do
      assert Number.to_string(1234.56, currency: :TWD, currency_digits: :cash) ==
               {:ok, "NT$1,235"}
    end

    test "TWD iso digits keep two fractional digits" do
      assert Number.to_string(1234.56, currency: :TWD, currency_digits: :iso) ==
               {:ok, "NT$1,234.56"}
    end
  end

  describe "error paths" do
    test "unknown currency returns UnknownCurrencyError" do
      assert {:error, %Localize.UnknownCurrencyError{currency: :XYZ}} =
               Number.to_string(1234, currency: :XYZ)
    end
  end
end
