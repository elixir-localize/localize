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
      {1234.567, "1#{@fr_group}234,57#{@nbsp}€", [format: "#,##0.00 ¤", locale: "fr", currency: :EUR]},
      {1234.567, "1#{@fr_group}235#{@nbsp}JPY", [format: "#,##0 ¤", locale: "fr", currency: "JPY"]},
      {1234.567, "1#{@fr_group}234,57#{@nbsp}JPY", [format: "#,##0.00 ¤", locale: "fr", currency: "JPY"]},
      {1234.567, "1#{@fr_group}234,57#{@nbsp}JPY", [format: "#,##0.## ¤", locale: "fr", currency: "JPY"]},
      {1234.00, "1#{@fr_group}234#{@nbsp}JPY", [format: "#,##0.## ¤", locale: "fr", currency: "JPY"]},
      {1234, "1#{@fr_group}234#{@nbsp}JPY", [format: "#,##0.## ¤", locale: "fr", currency: "JPY"]},

      # Fraction grouping
      # {1234.4353244565, "1234,435 324 456 5", [format: "#,###.###,#########", locale: "pl"]},

      # Special pattern characters
      {3.1415, "3,14", [format: "0.00;-0.00", locale: "fr"]},
      {-3.1415, "-3,14", [format: "0.00;-0.00", locale: "fr"]},
      {3.1415, "3,14", [format: "0.00;0.00-", locale: "fr"]},
      {-3.1415, "3,14-", [format: "0.00;0.00-", locale: "fr"]},
      {3.1415, "3,14+", [format: "0.00+;0.00-", locale: "fr"]},
      {-3.1415, "3,14-", [format: "0.00+;0.00-", locale: "fr"]},

      # Minimum grouping digits
      {1000, "1000", [format: "#,##0.##", locale: "pl"]},
      {10000, "10#{@nbsp}000", [format: "#,##0.##", locale: "pl"]},

      # Secondary grouping
      {1_234_567, "12,34,567", [format: "#,##,###"]},

      # Padding
      {123, "$xx123.00", [format: "$*x#,##0.00"]},
      {123, "xx$123.00", [format: "*x$#,##0.00"]},
      {123, "$123.00xx", [format: "$#,##0.00*x"]},
      {1234, "$1,234.00", [format: "$*x#,##0.00"]},
      {123, "! $xx123.00", [format: "'!' $*x#,##0.00"]},
      {123, "' $xx123.00", [format: "'' $*x#,##0.00"]},

      # Currency
      {123.4, "123.40 A$", [format: "#,##0.00 ¤", currency: :AUD]},
      {123.4, "123.40 AUD", [format: "#,##0.00 ¤¤", currency: :AUD]},
      {123.4, "123.40 Australian dollars", [format: "#,##0.00 ¤¤¤", currency: :AUD]},
      {123.4, "123.40 $", [format: "#,##0.00 ¤¤¤¤", currency: :AUD]},
      {1234, "A$1,234.00", [currency: :AUD]},
      {1234, "COP#{@nbsp}1,234.00", [currency: :COP, currency_digits: :iso]},
      {1234, "COP#{@nbsp}1,234", [currency: :COP]},

      # Currency where the symbol replaces the decimal separator
      # {1234, "1234$00", [currency: :CVE, locale: "pt-CV"]},

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

      # Permille
      {0.1234, "123.4‰", [format: "#0.0#‰"]},
      {-0.1234, "-123.4‰", [format: "#0.0#‰"]},

      # Negative number format
      {-1234, "(1234.00)", [format: "#.00;(#.00)"]},

      # Significant digits format
      {12345, "12300", [format: "@@#"]},
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
      {12345, "1,2345E4", [format: "0.0000E0", locale: "fr"]},

      # Scientific with exponent sign
      {1234, "1.234E+3", [format: "#E+0"]},
      {0.000012456, "1.2456E-5", [format: "#E+0"]},

      # Maximum and minimum digits
      {1234, "34", [format: "00", maximum_integer_digits: 2]},
      {1, "01.00", [format: "00.00"]},

      # Short formats
      {123, "123", [format: :short]},
      {1234, "1K", [format: :short]},
      {12345, "12K", [format: :short]},
      {1234.5, "1K", [format: :short]},
      {1234.5, "1.234", [format: :short, locale: "de"]},
      {123_456, "123.456", [format: :short, locale: "de"]},
      {12_345_678, "12M", [format: :short]},
      {1_234_567_890, "1B", [format: :short]},
      {1_234_567_890_000, "1T", [format: :short]},
      {1234, "1 thousand", [format: :long]},
      {1_234_567_890, "1 billion", [format: :long]},
      {1234, "$1K", [format: :short, currency: :USD]},
      {1234, "ZAR#{@nbsp}1K", [format: :short, currency: :ZAR]},
      {12345, "12,345 US dollars", [format: :long, currency: :USD]},
      {123, "A$123", [format: :short, currency: :AUD]},
      {12, "12 Thai baht", [format: :long, currency: :THB]},
      {12, "12 bahts thaïlandais", [format: :long, currency: :THB, locale: "fr"]},
      {2134, "A$2K", [format: :currency_short, currency: :AUD]},
      {2134, "2,134 Australian dollars", [format: :currency_long, currency: :AUD]},

      # Short formats in French
      {499_999_999, "500#{@nbsp}millions", [format: :long, locale: "fr"]},
      {500_000_000, "500#{@nbsp}millions", [format: :long, locale: "fr"]},
      {9_900_000_000, "10#{@nbsp}milliards", [format: :long, locale: "fr"]},
      {1_000, "mille", [format: :long, locale: "fr"]},
      {1_001, "1#{@nbsp}millier", [format: :long, locale: "fr"]},
      {1_499, "1#{@nbsp}millier", [format: :long, locale: "fr"]},
      {1_500, "2#{@nbsp}mille", [format: :long, locale: "fr"]},

      # Negative short formats
      {1_000_000, "1M", [format: :short]},
      {-1_000_000, "-1M", [format: :short]},
      {100_000, "100K", [format: :short]},
      {-100_000, "-100K", [format: :short]},
      {1_000, "1K", [format: :short]},
      {-1_000, "-1K", [format: :short]},

      # Formats with literals
      {123, "This is a 123.00 format", [format: "This is a #,##0.00 format"]},
      {-123, "This is a -123.00 format", [format: "This is a #,##0.00 format"]},
      {0.1, "This is a 10% format", [format: "This is a #,##0% format"]},
      {-0.1, "This is a -10% format", [format: "This is a #,##0% format"]},

      # Specify a currency in the locale
      {123.4, "123.40 $", [format: "#,##0.00 ¤", locale: "en-AU-u-cu-aud"]},
      {123.4, "123.40 USD", [format: "#,##0.00 ¤", locale: "en-AU-u-cu-aud", currency: :USD]},

      # Percent
      {0.56, "56#{@fr_group}%", [format: "#,##0 %", locale: "fr"]},
      {0.56, "56%", [format: "#,##0%"]},

      # Integer formatting
      {1234, "1,234", [format: "#,##0"]},
      {0, "0", [format: "#,##0"]},
      {-1234, "-1,234", [format: "#,##0"]},

      # Various locales
      {12345, "12#{@fr_group}345", [locale: "fr"]},
      {12345, "12.345", [locale: "de"]}
    ]
    |> merge_crypto_tests(System.otp_release())
  end

  # Formatting digital tokens (Crypto currencies)
  # Because OTP 28 introduces a new re module, OTP 28 will correctly
  # detect that "₿" is a symbol whereas earlier versions do not.
  defp merge_crypto_tests(tests, version) when version >= "28" do
    tests ++
      [
        {1_234_545_656.456789, "₿1,234,545,656.456789", [currency: "BTC"]},
        {1_234_545_656.456789, "₿1B", [format: :short, currency: "BTC"]},
        {1_234_545_656.456789, "1,234,545,656.456789 Bitcoin", [format: :long, currency: "BTC"]}
      ]
  end

  defp merge_crypto_tests(tests, _version) do
    tests ++
      [
        {1_234_545_656.456789, "₿#{@nbsp}1,234,545,656.456789", [currency: "BTC"]},
        {1_234_545_656.456789, "₿#{@nbsp}1B", [format: :short, currency: "BTC"]},
        {1_234_545_656.456789, "1,234,545,656.456789 Bitcoin", [format: :long, currency: "BTC"]}
      ]
  end
end
