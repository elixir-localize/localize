defmodule Localize.Number.DecimalFormatterCoverageTest do
  use ExUnit.Case, async: true

  alias Localize.Number
  alias Localize.Number.Formatter.Decimal, as: DecimalFormatter

  describe "metadata!/1" do
    test "returns the metadata for a valid format" do
      meta = DecimalFormatter.metadata!("#,##0.##")
      assert meta.integer_digits == %{max: 0, min: 1}
    end

    test "raises ArgumentError for an invalid format" do
      assert_raise ArgumentError, fn ->
        DecimalFormatter.metadata!("0.0.0.0")
      end
    end
  end

  describe "multiplication overflow protection" do
    test "a huge float times the percent factor promotes to Decimal" do
      assert {:ok, formatted} = Number.to_string(1.0e305, format: :percent)
      assert String.ends_with?(formatted, "%")
      assert String.starts_with?(formatted, "10,000")
    end
  end

  describe "round_nearest with Decimal numbers" do
    test "an integer rounding increment" do
      assert Number.to_string(Decimal.new("123.456"), round_nearest: 5) == {:ok, "125"}
    end

    test "a float rounding increment" do
      assert Number.to_string(Decimal.new("123.456"), round_nearest: 0.5) == {:ok, "123.5"}
    end

    test "an integer number with an integer increment" do
      assert Number.to_string(1234, round_nearest: 10) == {:ok, "1,230"}
    end
  end

  describe "grouping" do
    test "Indian-style grouping with different first and rest sizes" do
      assert Number.to_string(1_234_567, format: "#,##,##0") == {:ok, "12,34,567"}
    end

    test "a number smaller than the first group is not grouped" do
      assert Number.to_string(12, format: "#,##,##0") == {:ok, "12"}
    end
  end

  describe "padding" do
    test "pads to the format width with the pad character" do
      assert Number.to_string(12, format: "*x#,##0") == {:ok, "xxx12"}
    end

    test "no padding when the number exceeds the format width" do
      assert Number.to_string(1_234_567, format: "*x#,##0") == {:ok, "1,234,567"}
    end
  end

  describe "literal format parts" do
    test "an explicit plus sign" do
      assert Number.to_string(12, format: "+#,##0") == {:ok, "+12"}
    end

    test "a percent sign in a literal format" do
      assert Number.to_string(0.129, format: "#,##0%") == {:ok, "13%"}
    end

    test "a permille sign in a literal format" do
      assert Number.to_string(0.129, format: "#0‰") == {:ok, "129‰"}
    end

    test "a quoted character" do
      assert Number.to_string(5, format: "'#'0") == {:ok, "#5"}
    end
  end

  describe "wrapper functions" do
    test "a wrapper returning a binary" do
      wrapper = fn string, _tag -> "<span>#{string}</span>" end
      assert Number.to_string(1234, wrapper: wrapper) == {:ok, "<span>1,234</span>"}
    end

    test "a wrapper returning a safe tuple" do
      wrapper = fn string, _tag -> {:safe, [string]} end
      assert Number.to_string(1234, wrapper: wrapper) == {:ok, "1,234"}
    end

    test "a wrapper returning iodata" do
      wrapper = fn string, _tag -> [string] end
      assert Number.to_string(1234, wrapper: wrapper) == {:ok, "1,234"}
    end
  end

  describe "currency digit adjustment" do
    test "cash digits use cash rounding" do
      assert Number.to_string(1234.5678, currency: :CHF, currency_digits: :cash) ==
               {:ok, "CHF\u00A01,234.55"}
    end

    test "iso digits use the iso definition" do
      assert Number.to_string(1234.5678, currency: :CHF, currency_digits: :iso) ==
               {:ok, "CHF\u00A01,234.56"}
    end
  end

  describe "currency spacing" do
    test "a space is inserted between an alphabetic symbol and the number" do
      assert Number.to_string(1234.5, currency: :BAM, locale: :en) == {:ok, "BAM\u00A01,234.50"}
    end

    test "a space is inserted after the number for suffix symbols" do
      assert Number.to_string(1234.5, currency: :BAM, locale: :de) == {:ok, "1.234,50\u00A0BAM"}
    end
  end

  describe "significant digits" do
    test "a significant digits format pattern" do
      assert Number.to_string(1234, format: "@@") == {:ok, "1200"}
    end

    test "minimum and maximum significant digit options" do
      assert Number.to_string(1234.567,
               minimum_significant_digits: 2,
               maximum_significant_digits: 4
             ) == {:ok, "1,235"}
    end
  end

  describe "fractional and integer digit options" do
    test "fractional_digits sets minimum and maximum" do
      assert Number.to_string(1.23456, fractional_digits: 2) == {:ok, "1.23"}
    end

    test "maximum_integer_digits truncates leading digits" do
      assert Number.to_string(12_345, maximum_integer_digits: 3) == {:ok, "345"}
    end
  end

  describe "digit transliteration" do
    test "formats with the thai number system" do
      assert Number.to_string(1234.5, number_system: :thai, locale: "th-TH") ==
               {:ok, "๑,๒๓๔.๕"}
    end
  end

  describe "scientific notation" do
    test "standard scientific format" do
      assert Number.to_string(12_345, format: :scientific) == {:ok, "1.2345E4"}
    end

    test "an explicit exponent sign" do
      assert Number.to_string(12_345, format: "0.0E+0") == {:ok, "1.2E+4"}
    end

    test "a negative exponent" do
      assert Number.to_string(0.00012, format: "0.0E0") == {:ok, "1.2E-4"}
    end

    test "superscript exponent style" do
      assert Number.to_string(12_345, format: "0.0E0", exponent_style: :superscript) ==
               {:ok, "1.2×10⁴"}
    end

    test "superscript exponent style with a negative exponent" do
      assert Number.to_string(0.00012, format: "0.0E0", exponent_style: :superscript) ==
               {:ok, "1.2×10⁻⁴"}
    end

    test "superscript exponent style with a forced plus sign" do
      assert Number.to_string(12_345, format: "0.0E+0", exponent_style: :superscript) ==
               {:ok, "1.2×10⁺⁴"}
    end

    test "engineering-style grouping of the exponent" do
      assert Number.to_string(1234, format: "##0.0E0") == {:ok, "1.234E3"}
    end
  end
end
