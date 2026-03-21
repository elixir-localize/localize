defmodule Localize.Test.Number.FormatData do
  @moduledoc false

  # Adapted test data from ex_cldr_numbers.
  # Each tuple is {input_value, expected_output, options_keyword_list}.
  #
  # Note: French locale uses U+202F (narrow non-breaking space) as
  # grouping separator per CLDR data.

  # French narrow non-breaking space (U+202F)
  @fr_group "\u202F"

  def test_data do
    [
      # Basic formatting
      {1234, "1,234", []},
      {1234, "1#{@fr_group}234", [locale: "fr"]},

      # Number patterns from TR35
      {1234.567, "1#{@fr_group}234,57", [format: "#,##0.##", locale: "fr"]},
      {1234.567, "1#{@fr_group}234,567", [format: "#,##0.###", locale: "fr"]},
      {1234.567, "1234,567", [format: "###0.#####", locale: "fr"]},
      {1234.567, "1234,5670", [format: "###0.0000#", locale: "fr"]},
      {1234.567, "01234,5670", [format: "00000.0000", locale: "fr"]},
      {1234.567, "1#{@fr_group}234,57 €", [format: "#,##0.00 ¤", locale: "fr", currency: :EUR]},

      # Special pattern characters
      {3.1415, "3,14", [format: "0.00;-0.00", locale: "fr"]},
      {-3.1415, "-3,14", [format: "0.00;-0.00", locale: "fr"]},
      {3.1415, "3,14", [format: "0.00;0.00-", locale: "fr"]},
      {-3.1415, "3,14-", [format: "0.00;0.00-", locale: "fr"]},

      # Significant digits
      {3.14159, "3,142", [format: "@@##", locale: "fr"]},
      {1.23004, "1,23", [format: "@@##", locale: "fr"]},
      {0.12345, "0,123", [format: "@@@", locale: "fr"]},

      # Various locales
      {12345, "12#{@fr_group}345", [locale: "fr"]},
      {12345, "12.345", [locale: "de"]},

      # Scientific
      {12345, "1,2345E4", [format: "0.0000E0", locale: "fr"]},

      # Percent
      {0.56, "56 %", [format: "#,##0 %", locale: "fr"]},
      {0.56, "56%", [format: "#,##0%"]},

      # Integer formatting
      {1234, "1,234", [format: "#,##0"]},
      {0, "0", [format: "#,##0"]},
      {-1234, "-1,234", [format: "#,##0"]}
    ]
  end
end
