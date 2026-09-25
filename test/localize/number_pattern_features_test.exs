defmodule Localize.NumberPatternFeaturesTest do
  @moduledoc """
  Number pattern features beyond digits and grouping: per-mille, secondary
  grouping, padding, explicit negative subpatterns, ISO currency codes,
  scientific notation and significant digits.

  Expected values come from ICU4C 78.3's `DecimalFormat` with each pattern
  and the locale's symbols, and from TR35's own examples where it gives one
  (`"$*x#,##0.00"` formats 123 as "$xx123.00" and 1234 as "$1,234.00"). ICU
  rounds half-even, TR35's default, so ties show the even digit: "@@@"
  renders 12250 as "12200". A scientific mantissa shows the significant
  digits TR35 §Scientific Notation derives from its pattern, so "##0.##E0"
  renders 12345 as "12.3E3". Every case goes through `to_string/2` and
  `to_parts/2`, whose parts must join to the same string.

  """

  use ExUnit.Case, async: true

  @patterns [
    {:en, "#,##0‰", 0.5, "500‰"},
    {:en, "#,##,##0", 1_234_567, "12,34,567"},
    {:hi, "#,##,##0.###", 1_234_567.891, "12,34,567.891"},
    {:en, "$*x#,##0.00", 123, "$xx123.00"},
    {:en, "$*x#,##0.00", 1234, "$1,234.00"},
    {:en, "* #0 o''clock", 5, " 5 o'clock"},
    {:en, "#,##0.00;(#,##0.00)", -1234.5, "(1,234.50)"},
    {:en, "0.###E0", 12_345, "1.234E4"},
    {:en, "0.###E0", 12_355, "1.236E4"},
    {:en, "0.###E0", -12_345, "-1.234E4"},
    {:en, "0.###E0", 0.00012345, "1.234E-4"},
    {:en, "0.###E0", 0.00012, "1.2E-4"},
    {:en, "0.###E0", 99_995, "1E5"},
    {:en, "0.###E0", 9.9995, "1E1"},
    {:en, "0.###E+0", 12_345, "1.234E+4"},
    {:en, "##0.###E0", 12_345, "12.34E3"},
    {:en, "##0.###E0", 123_456, "123.5E3"},
    {:en, "##0.###E0", 999_950, "1E6"},
    {:en, "##0.##E0", 12_345, "12.3E3"},
    {:en, "##0.##E0", 1234, "1.23E3"},
    {:en, "#.0#E0", 12_345, "1.2E4"},
    {:en, "#.##E0", 12_345, "1.23E4"},
    {:en, "0E0", 15_000, "2E4"},
    {:en, "0E0", 25_000, "2E4"},
    {:en, "0.00E0", 12_250, "1.22E4"},
    {:en, "@@@", 12_250, "12200"},
    {:en, "@@@", 0.0001225, "0.000122"},
    {:en, "@@##", 0.0012345, "0.001234"},
    {:en, "@@#", 1.245, "1.24"},
    {:en, "@#", 99.5, "100"}
  ]

  test "patterns match ICU" do
    for {locale, pattern, number, expected} <- @patterns do
      options = [format: pattern, locale: locale]

      assert {pattern, number, Localize.Number.to_string(number, options)} ==
               {pattern, number, {:ok, expected}}

      assert {pattern, number, joined(Localize.Number.to_parts(number, options))} ==
               {pattern, number, {:ok, expected}}
    end
  end

  test "an ISO currency code is spaced from the digits" do
    for {currency, number, expected} <- [
          {:USD, 1234, "USD 1,234.00"},
          {:EUR, -1234.5, "-EUR 1,234.50"}
        ] do
      options = [currency: currency, currency_symbol: :iso, locale: :en]

      assert {currency, Localize.Number.to_string(number, options)} ==
               {currency, {:ok, expected}}

      assert {currency, joined(Localize.Number.to_parts(number, options))} ==
               {currency, {:ok, expected}}
    end
  end

  defp joined({:ok, parts}), do: {:ok, Enum.map_join(parts, & &1.value)}
  defp joined(other), do: other
end
