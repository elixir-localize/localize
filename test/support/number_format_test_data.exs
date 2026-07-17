defmodule Localize.Test.Number.FormatData do
  @moduledoc false

  # Adapted test data from ex_cldr_numbers.
  # Each tuple is {input_value, expected_output, options_keyword_list}.
  #
  # Note: French locale uses U+202F (narrow non-breaking space) as
  # grouping separator per CLDR data. Polish locale also uses U+00A0
  # (non-breaking space) as grouping separator.

  # French narrow non-breaking space (U+202F)
  @fr_group "\u202F"
  # Non-breaking space (U+00A0) used by Polish and some other locales
  @nbsp "\u00A0"

  def test_data do
    [
      # Basic formatting
      {1234, "1,234", []},
      {1234, "1#{@fr_group}234", [locale: "fr"]},
      {0.000123456, "0", []},
      {-0.000123456, "0", []},

      # Number patterns from TR35
      {1234.567, "1#{@fr_group}234,57", [format: "#,##0.##", locale: "fr"]},
      {1234.567, "1#{@fr_group}234,567", [format: "#,##0.###", locale: "fr"]},
      {1234.567, "1234,567", [format: "###0.#####", locale: "fr"]},
      {1234.567, "1234,5670", [format: "###0.0000#", locale: "fr"]},
      {1234.567, "01234,5670", [format: "00000.0000", locale: "fr"]},
      {1234.567, "1#{@fr_group}234,57 €", [format: "#,##0.00 ¤", locale: "fr", currency: :EUR]},
      {1234.567, "1#{@fr_group}235 JPY", [format: "#,##0 ¤", locale: "fr", currency: "JPY"]},
      {1234.567, "1#{@fr_group}234,57 JPY",
       [format: "#,##0.00 ¤", locale: "fr", currency: "JPY"]},
      {1234.567, "1#{@fr_group}234,57 JPY",
       [format: "#,##0.## ¤", locale: "fr", currency: "JPY"]},
      {1234.00, "1#{@fr_group}234 JPY", [format: "#,##0.## ¤", locale: "fr", currency: "JPY"]},
      {1234, "1#{@fr_group}234 JPY", [format: "#,##0.## ¤", locale: "fr", currency: "JPY"]},

      # Special pattern characters
      {3.1415, "3,14", [format: "0.00;-0.00", locale: "fr"]},
      {-3.1415, "-3,14", [format: "0.00;-0.00", locale: "fr"]},
      {3.1415, "3,14", [format: "0.00;0.00-", locale: "fr"]},
      {-3.1415, "3,14-", [format: "0.00;0.00-", locale: "fr"]},
      {3.1415, "3,14+", [format: "0.00+;0.00-", locale: "fr"]},
      {-3.1415, "3,14-", [format: "0.00+;0.00-", locale: "fr"]},

      # Minimum grouping digits
      {1000, "1000", [format: "#,##0.##", locale: "pl"]},
      {10_000, "10#{@nbsp}000", [format: "#,##0.##", locale: "pl"]},

      # Secondary grouping
      {1_234_567, "12,34,567", [format: "#,##,###"]},

      # Padding
      {123, "$xx123.00", [format: "$*x#,##0.00"]},
      {123, "xx$123.00", [format: "*x$#,##0.00"]},
      {123, "$123.00xx", [format: "$#,##0.00*x"]},
      {1234, "$1,234.00", [format: "$*x#,##0.00"]},
      {123, "! $xx123.00", [format: "'!' $*x#,##0.00"]},
      {123, "' $xx123.00", [format: "'' $*x#,##0.00"]},

      # Currency with ¤ (standard symbol)
      {123.4, "123.40 A$", [format: "#,##0.00 ¤", currency: :AUD]},
      {1234, "A$1,234.00", [currency: :AUD]},

      # Multi-¤ patterns (¤¤ = ISO, ¤¤¤ = display name, ¤¤¤¤ = narrow)
      # not yet supported
      # {123.4, "123.40 AUD", [format: "#,##0.00 ¤¤", currency: :AUD]},
      # {123.4, "123.40 Australian dollars", [format: "#,##0.00 ¤¤¤", currency: :AUD]},
      # {123.4, "123.40 $", [format: "#,##0.00 ¤¤¤¤", currency: :AUD]},

      {1234, "COP#{@nbsp}1,234.00", [currency: :COP, currency_digits: :iso]},
      {1234, "COP#{@nbsp}1,234", [currency: :COP]},

      # Currency default fractional digits
      {1234, "¥1,234", [currency: :JPY]},
      {1234, "TND#{@nbsp}1,234.000", [currency: :TND]},

      # Currency with varying currency symbol
      {1234, "CUSTOM#{@nbsp}1,234.00", [currency: :AUD, currency_symbol: "CUSTOM"]},
      {1234, "$1,234.00", [currency: :AUD, currency_symbol: :narrow]},
      {1234, "A$1,234.00", [currency: :AUD, currency_symbol: :standard]},
      {1234, "A$1,234.00", [currency: :AUD, currency_symbol: :symbol]},
      {1234, "AUD#{@nbsp}1,234.00", [currency: :AUD, currency_symbol: :iso]},

      # Rounding
      {1234.21, "1,234.20", [format: "#,##0.05"]},
      {1234.22, "1,234.20", [format: "#,##0.05"]},
      {1234.23, "1,234.25", [format: "#,##0.05"]},
      {1234, "1,250", [format: "#,#50"]},

      # Percentage
      {0.1234, "12.34%", [format: "#0.0#%"]},
      {-0.1234, "-12.34%", [format: "#0.0#%"]},
      {0.56, "56 %", [format: "#,##0 %", locale: "fr"]},
      {0.56, "56%", [format: "#,##0%"]},

      # Permille
      {0.1234, "123.4‰", [format: "#0.0#‰"]},
      {-0.1234, "-123.4‰", [format: "#0.0#‰"]},

      # Negative number format
      {-1234, "(1234.00)", [format: "#.00;(#.00)"]},

      # Significant digits format
      {12_345, "12300", [format: "@@#"]},
      {0.12345, "0.123", [format: "@@#"]},
      {3.14159, "3.142", [format: "@@##"]},
      {1.23004, "1.23", [format: "@@##"]},
      {-1.23004, "-1.23", [format: "@@##"]},
      {3.14159, "3,142", [format: "@@##", locale: "fr"]},
      {1.23004, "1,23", [format: "@@##", locale: "fr"]},
      {0.12345, "0,123", [format: "@@@", locale: "fr"]},

      # Test for when padding specified but there is no padding possible
      {123_456_789, "123456789", [format: "*x#"]},

      # Scientific formats
      {0.1234, "1.234E-1", [format: "#E0"]},
      {1.234, "1.234E0", [format: "#E0"]},
      {12.34, "1.234E1", [format: "#E0"]},
      {123.4, "1.234E2", [format: "#E0"]},
      {1234, "1.234E3", [format: "#E0"]},
      {1234, "1.234E3", [format: :scientific]},
      {12_345, "1,2345E4", [format: "0.0000E0", locale: "fr"]},

      # Scientific with exponent sign
      {1234, "1.234E+3", [format: "#E+0"]},
      {0.000012456, "1.2456E-5", [format: "#E+0"]},

      # Maximum and minimum digits
      {1234, "34", [format: "00", maximum_integer_digits: 2]},
      {1, "01.00", [format: "00.00"]},

      # Short/long decimal formats (use :decimal_short/:decimal_long).
      # Expected values verified against ICU (Intl.NumberFormat with
      # notation: :compact): the compact default precision is at most
      # two significant digits on the mantissa, and the plural category
      # is selected from the mantissa as displayed.
      {123, "123", [format: :decimal_short]},
      {1234, "1.2K", [format: :decimal_short]},
      {12_345, "12K", [format: :decimal_short]},
      {1234.5, "1.2K", [format: :decimal_short]},
      {1234.5, "1.234", [format: :decimal_short, locale: "de"]},
      {123_456, "123.456", [format: :decimal_short, locale: "de"]},
      {12_345_678, "12M", [format: :decimal_short]},
      {1_234_567_890, "1.2B", [format: :decimal_short]},
      {1_234_567_890_000, "1.2T", [format: :decimal_short]},
      {1234, "1.2 thousand", [format: :decimal_long]},
      {1_234_567_890, "1.2 billion", [format: :decimal_long]},

      # Short/long currency formats
      {1234, "$1.2K", [format: :currency_short, currency: :USD]},
      {1234, "ZAR#{@nbsp}1.2K", [format: :currency_short, currency: :ZAR]},
      {12_345, "12,345 US dollars", [format: :currency_long, currency: :USD]},
      {123, "A$123", [format: :currency_short, currency: :AUD]},
      {12, "12 Thai baht", [format: :currency_long, currency: :THB]},
      {12, "12 bahts thaïlandais", [format: :currency_long, currency: :THB, locale: "fr"]},
      {2134, "A$2.1K", [format: :currency_short, currency: :AUD]},
      {2134, "2,134 Australian dollars", [format: :currency_long, currency: :AUD]},

      # Short/long formats in French. 1000 and 1001 round to a mantissa
      # of exactly 1 and select the exact-match count-"1" pattern
      # ("mille"), matching ICU.
      {499_999_999, "500 millions", [format: :decimal_long, locale: "fr"]},
      {500_000_000, "500 millions", [format: :decimal_long, locale: "fr"]},
      {9_900_000_000, "9,9 milliards", [format: :decimal_long, locale: "fr"]},
      {1_000, "mille", [format: :decimal_long, locale: "fr"]},
      {1_001, "mille", [format: :decimal_long, locale: "fr"]},
      {1_499, "1,5 millier", [format: :decimal_long, locale: "fr"]},
      {1_500, "1,5 millier", [format: :decimal_long, locale: "fr"]},

      # Negative short formats
      {1_000_000, "1M", [format: :decimal_short]},
      {-1_000_000, "-1M", [format: :decimal_short]},
      {100_000, "100K", [format: :decimal_short]},
      {-100_000, "-100K", [format: :decimal_short]},
      {1_000, "1K", [format: :decimal_short]},
      {-1_000, "-1K", [format: :decimal_short]},

      # Formats with literals
      {123, "This is a 123.00 format", [format: "This is a #,##0.00 format"]},
      {-123, "-This is a 123.00 format", [format: "This is a #,##0.00 format"]},
      {0.1, "This is a 10% format", [format: "This is a #,##0% format"]},
      {-0.1, "-This is a 10% format", [format: "This is a #,##0% format"]},

      # Specify a currency in the locale
      {123.4, "123.40 $", [format: "#,##0.00 ¤", locale: "en-AU-u-cu-aud"]},
      {123.4, "123.40 USD", [format: "#,##0.00 ¤", locale: "en-AU-u-cu-aud", currency: :USD]},

      # Integer formatting
      {1234, "1,234", [format: "#,##0"]},
      {0, "0", [format: "#,##0"]},
      {-1234, "-1,234", [format: "#,##0"]},

      # Various locales
      {12_345, "12#{@fr_group}345", [locale: "fr"]},
      {12_345, "12.345", [locale: "de"]}
    ]
    |> merge_crypto_tests(System.otp_release())
  end

  # BTC (Bitcoin) and other digital tokens are not yet supported.
  # The `digital_token` library (which maps ISO 24165 digital token
  # identifiers to currency data) is not currently integrated.
  # These tests should be re-enabled when digital token support is added.
  #
  # defp merge_crypto_tests(tests, version) when version >= "28" do
  #   tests ++
  #     [
  #       {1_234_545_656.456789, "₿1,234,545,656.456789", [currency: "BTC"]},
  #       {1_234_545_656.456789, "₿1B", [format: :currency_short, currency: "BTC"]},
  #       {1_234_545_656.456789, "1,234,545,656.456789 Bitcoin",
  #        [format: :currency_long, currency: "BTC"]}
  #     ]
  # end
  #
  # defp merge_crypto_tests(tests, _version) do
  #   tests ++
  #     [
  #       {1_234_545_656.456789, "₿ 1,234,545,656.456789", [currency: "BTC"]},
  #       {1_234_545_656.456789, "₿ 1B", [format: :currency_short, currency: "BTC"]},
  #       {1_234_545_656.456789, "1,234,545,656.456789 Bitcoin",
  #        [format: :currency_long, currency: "BTC"]}
  #     ]
  # end
  defp merge_crypto_tests(tests, _version), do: tests
end
