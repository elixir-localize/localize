defmodule Localize.Number.FormattingOptionsTest do
  use ExUnit.Case, async: true

  alias Localize.Number

  describe "permille patterns" do
    test "permille multiplies by 1000 and appends the permille sign" do
      assert Number.to_string(0.125, format: "#0‰") == {:ok, "125‰"}
    end

    test "permille in German uses the same sign" do
      assert Number.to_string(0.125, format: "#0‰", locale: "de") == {:ok, "125‰"}
    end
  end

  describe "percent pattern multiplier" do
    test "explicit percent pattern multiplies by 100" do
      assert Number.to_string(0.25, format: "#0%") == {:ok, "25%"}
    end
  end

  describe "explicit negative subpatterns" do
    test "negative values use the parenthesised subpattern" do
      assert Number.to_string(-1234.567, format: "#,##0.00;(#,##0.00)") ==
               {:ok, "(1,234.57)"}
    end

    test "positive values use the positive subpattern" do
      assert Number.to_string(1234.567, format: "#,##0.00;(#,##0.00)") ==
               {:ok, "1,234.57"}
    end

    test "negative subpattern respects the locale separators" do
      assert Number.to_string(-1234.567, format: "#,##0.00;(#,##0.00)", locale: "de") ==
               {:ok, "(1.234,57)"}
    end
  end

  describe "rounding modes" do
    test ":half_even rounds ties to the even neighbour" do
      assert Number.to_string(2.5, fractional_digits: 0, rounding_mode: :half_even) ==
               {:ok, "2"}

      assert Number.to_string(3.5, fractional_digits: 0, rounding_mode: :half_even) ==
               {:ok, "4"}
    end

    test ":half_up rounds ties away from zero" do
      assert Number.to_string(2.5, fractional_digits: 0, rounding_mode: :half_up) == {:ok, "3"}
    end

    test ":floor rounds toward negative infinity" do
      assert Number.to_string(2.9, fractional_digits: 0, rounding_mode: :floor) == {:ok, "2"}
    end

    test ":ceiling rounds toward positive infinity" do
      assert Number.to_string(2.1, fractional_digits: 0, rounding_mode: :ceiling) == {:ok, "3"}
    end

    test ":down truncates toward zero" do
      assert Number.to_string(-2.9, fractional_digits: 0, rounding_mode: :down) == {:ok, "-2"}
    end

    test ":up rounds away from zero" do
      assert Number.to_string(2.1, fractional_digits: 0, rounding_mode: :up) == {:ok, "3"}
    end

    test "invalid rounding mode returns an error listing the valid modes" do
      assert {:error, %Localize.InvalidValueError{expected: :rounding_mode}} =
               Number.to_string(2.1, rounding_mode: :bogus)
    end
  end

  describe "round_nearest option" do
    test "rounds to the nearest 25" do
      assert Number.to_string(1234, round_nearest: 25) == {:ok, "1,225"}
    end
  end

  describe "minimum_grouping_digits option" do
    test "suppresses grouping when the leading group is too small" do
      assert Number.to_string(1234, minimum_grouping_digits: 2) == {:ok, "1234"}
      assert Number.to_string(12_345, minimum_grouping_digits: 2) == {:ok, "12,345"}
    end

    test "Polish locale data uses minimum grouping digits of 2" do
      assert Number.to_string(1234, locale: "pl") == {:ok, "1234"}
      assert Number.to_string(12_345, locale: "pl") == {:ok, "12 345"}
    end
  end

  describe "pattern padding" do
    test "pads with the declared character to the pattern width" do
      assert Number.to_string(42, format: "*x#####0") == {:ok, "xxxx42"}
    end

    test "padding counts literal characters in the pattern" do
      assert Number.to_string(42, format: "*x #,##0") == {:ok, "xxx 42"}
    end
  end

  describe "locale-specific grouping" do
    test "Indian grouping uses 3 then 2" do
      assert Number.to_string(12_345_678, locale: "en-IN") == {:ok, "1,23,45,678"}
    end
  end

  describe "number systems" do
    test "arab number system transliterates the digits" do
      assert Number.to_string(123, locale: "ar", number_system: :arab) == {:ok, "١٢٣"}
    end
  end

  describe "invalid input" do
    test "unparseable format pattern returns an InvalidValueError" do
      assert {:error, %Localize.InvalidValueError{expected: "a valid number format"}} =
               Number.to_string(123, format: "0.0.0.0")
    end

    test "non-string non-atom format returns an InvalidValueError" do
      assert {:error, %Localize.InvalidValueError{}} = Number.to_string(123, format: 42)
    end

    test "string number input returns an InvalidValueError" do
      assert {:error, %Localize.InvalidValueError{}} = Number.to_string("123")
    end
  end
end
