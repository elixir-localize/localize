defmodule Localize.Number.FormattingTest do
  use ExUnit.Case, async: true

  # Adapted from ex_cldr_numbers number_format_test.exs
  # Tests ported from backend-based calls to Localize.Number.to_string/2

  describe "basic formatting" do
    test "to_string with no arguments" do
      assert {:ok, "1,234"} = Localize.Number.to_string(1234)
    end

    test "to_string with locale option" do
      {:ok, result} = Localize.Number.to_string(1234, locale: "de")
      # German uses . as group separator and , as decimal
      assert String.contains?(result, "1")
      assert String.contains?(result, "234")
    end

    test "literal-only format returns the literal" do
      assert {:ok, "xxx"} = Localize.Number.to_string(1234, format: "xxx")
    end

    test "formatted float with rounding" do
      assert {:ok, "1.40"} = Localize.Number.to_string(1.4, fractional_digits: 2)
    end

    test "formatted Decimal with rounding matches float output" do
      assert {:ok, "1.40"} =
               Localize.Number.to_string(Decimal.new("1.4"), fractional_digits: 2)

      assert Localize.Number.to_string(1.4, fractional_digits: 2) ==
               Localize.Number.to_string(Decimal.new("1.4"), fractional_digits: 2)
    end

    test "that -0 Decimal formats" do
      number = Decimal.new("-0")
      {:ok, result} = Localize.Number.to_string(number)
      # The result may or may not strip the sign depending on implementation
      assert result in ["0", "-0", "-0.000"]
    end
  end

  describe "format styles" do
    test "percent format" do
      assert {:ok, "56%"} = Localize.Number.to_string(0.56, format: :percent)
    end

    test "percent format matches between Decimal and float" do
      assert {:ok, "56%"} = Localize.Number.to_string(Decimal.new("0.56"), format: :percent)

      assert Localize.Number.to_string(0.56, format: :percent) ==
               Localize.Number.to_string(Decimal.new("0.56"), format: :percent)
    end

    test "percent format with fractional digits" do
      {:ok, result} = Localize.Number.to_string(123.456, format: :percent, fractional_digits: 1)
      assert result == "12,345.6%"
    end

    test "percent format with fractional digits matches between Decimal and float" do
      assert {:ok, "12,345.6%"} =
               Localize.Number.to_string(Decimal.new("123.456"),
                 format: :percent,
                 fractional_digits: 1
               )

      assert Localize.Number.to_string(123.456, format: :percent, fractional_digits: 1) ==
               Localize.Number.to_string(Decimal.new("123.456"),
                 format: :percent,
                 fractional_digits: 1
               )
    end

    test "scientific format" do
      {:ok, result} = Localize.Number.to_string(1234, format: :scientific)
      assert String.contains?(result, "E")
    end
  end

  describe "currency formatting" do
    test "auto-selects currency format when currency is provided" do
      {:ok, result} = Localize.Number.to_string(1234, currency: :USD)
      assert String.contains?(result, "$")
      assert String.contains?(result, "1,234")
    end

    test "explicit currency format with USD" do
      {:ok, result} = Localize.Number.to_string(1234, format: :currency, currency: :USD)
      assert String.contains?(result, "$")
      assert String.contains?(result, "1,234")
    end

    test "currency format with ISO symbol" do
      {:ok, result} = Localize.Number.to_string(123, currency: :USD, currency_symbol: :iso)
      assert String.contains?(result, "USD")
    end

    test "currency symbol falls back to ISO code when locale has no symbol" do
      # CHF has no symbol in the fr locale — should fall back to "CHF"
      {:ok, result} = Localize.Number.to_string(1_000_000_000, locale: :fr, currency: :CHF)
      assert String.contains?(result, "CHF")
    end

    test "fraction digits of 0 with currency" do
      {:ok, result} = Localize.Number.to_string(50.12, fractional_digits: 0, currency: :USD)
      assert String.contains?(result, "$")
      assert String.contains?(result, "50")
    end

    test "fraction digits of 0 with currency matches between Decimal and float" do
      assert Localize.Number.to_string(50.12, fractional_digits: 0, currency: :USD) ==
               Localize.Number.to_string(Decimal.new("50.12"),
                 fractional_digits: 0,
                 currency: :USD
               )
    end
  end

  describe "grouping" do
    test "minimum_grouping_digits for English" do
      assert Localize.Number.Format.minimum_grouping_digits_for!(:en) == 1
    end

    test "format map keys for English" do
      assert Map.has_key?(Localize.Number.Format.all_formats_for!(:en), :latn)
    end
  end

  describe "round_nearest option" do
    test "round_nearest to 5" do
      assert {:ok, "1,235"} = Localize.Number.to_string(1234, round_nearest: 5)
      assert {:ok, "1,230"} = Localize.Number.to_string(1231, round_nearest: 5)
    end

    test "round_nearest to 10" do
      assert {:ok, "1,230"} = Localize.Number.to_string(1234, round_nearest: 10)
      assert {:ok, "1,240"} = Localize.Number.to_string(1235, round_nearest: 10)
    end
  end

  describe "fractional_digits option" do
    test "fraction digits of 0" do
      {:ok, result} = Localize.Number.to_string(50.12, fractional_digits: 0)
      assert result == "50"
    end

    test "fraction digits of 0 matches between Decimal and float" do
      assert {:ok, "50"} =
               Localize.Number.to_string(Decimal.new("50.12"), fractional_digits: 0)

      assert Localize.Number.to_string(50.12, fractional_digits: 0) ==
               Localize.Number.to_string(Decimal.new("50.12"), fractional_digits: 0)
    end

    test "fraction digits of 2" do
      {:ok, result} = Localize.Number.to_string(50.1, fractional_digits: 2)
      assert result == "50.10"
    end

    test "fraction digits of 2 matches between Decimal and float" do
      assert {:ok, "50.10"} =
               Localize.Number.to_string(Decimal.new("50.1"), fractional_digits: 2)

      assert Localize.Number.to_string(50.1, fractional_digits: 2) ==
               Localize.Number.to_string(Decimal.new("50.1"), fractional_digits: 2)
    end
  end

  describe "Decimal and float produce identical output under the standard pattern" do
    test "matching scale: 1234.56" do
      assert Localize.Number.to_string(1234.56) ==
               Localize.Number.to_string(Decimal.new("1234.56"))

      assert {:ok, "1,234.56"} = Localize.Number.to_string(Decimal.new("1234.56"))
    end

    test "fewer fraction digits than max: 1234.5" do
      assert {:ok, "1,234.5"} = Localize.Number.to_string(Decimal.new("1234.5"))
    end

    test "Decimal with synthetic trailing zeros: 1234.50" do
      # Decimal.new("1234.50") has coef 123450, exp -2 — an explicit
      # trailing zero. The standard pattern has max 3 / min 0 fraction
      # digits so that zero should be stripped.
      assert {:ok, "1,234.5"} = Localize.Number.to_string(Decimal.new("1234.50"))
    end

    test "integer-valued Decimal: 1234" do
      assert {:ok, "1,234"} = Localize.Number.to_string(Decimal.new("1234"))
      assert {:ok, "1,234"} = Localize.Number.to_string(Decimal.new("1234.00"))
    end

    test "currency still pads to mandatory minimum fraction digits" do
      # USD requires 2 fraction digits — `adjust_trailing_zeros` pads
      # after normalization strips them.
      assert {:ok, "$1,234.50"} =
               Localize.Number.to_string(Decimal.new("1234.5"),
                 currency: :USD,
                 locale: :en,
                 prefer: :ascii
               )

      assert {:ok, "$1,234.00"} =
               Localize.Number.to_string(Decimal.new("1234"),
                 currency: :USD,
                 locale: :en,
                 prefer: :ascii
               )
    end
  end

  describe "negative number formatting" do
    test "negative integer" do
      {:ok, result} = Localize.Number.to_string(-1234)
      assert String.contains?(result, "1,234")
      assert String.contains?(result, "-")
    end

    test "negative float" do
      {:ok, result} = Localize.Number.to_string(-42.5)
      assert String.contains?(result, "42.5")
      assert String.contains?(result, "-")
    end

    test "negative Decimal matches negative float" do
      {:ok, result} = Localize.Number.to_string(Decimal.new("-42.5"))
      assert String.contains?(result, "42.5")
      assert String.contains?(result, "-")

      assert Localize.Number.to_string(-42.5) ==
               Localize.Number.to_string(Decimal.new("-42.5"))
    end
  end

  describe "special values" do
    test "NaN" do
      {:ok, result} = Localize.Number.to_string(Decimal.new("NaN"))
      assert result == "NaN"
    end

    test "Infinity" do
      {:ok, result} = Localize.Number.to_string(Decimal.new("Inf"))
      assert result == "∞"
    end
  end
end
