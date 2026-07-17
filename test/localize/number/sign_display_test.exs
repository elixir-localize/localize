defmodule Localize.Number.SignDisplayTest do
  use ExUnit.Case, async: true

  describe "sign_display: :auto (default)" do
    test "negative numbers show the minus sign" do
      assert {:ok, "-1,234"} = Localize.Number.to_string(-1234)
      assert {:ok, "-1,234"} = Localize.Number.to_string(-1234, sign_display: :auto)
    end

    test "positive numbers and zero show no sign" do
      assert {:ok, "1,234"} = Localize.Number.to_string(1234, sign_display: :auto)
      assert {:ok, "0"} = Localize.Number.to_string(0, sign_display: :auto)
    end

    test "a negative number rounding to a bare zero drops the minus sign" do
      assert {:ok, "0"} = Localize.Number.to_string(-0.2, fractional_digits: 0)
    end
  end

  describe "sign_display: :always" do
    test "positive numbers and zero show the plus sign" do
      assert {:ok, "+1,234"} = Localize.Number.to_string(1234, sign_display: :always)
      assert {:ok, "+0"} = Localize.Number.to_string(0, sign_display: :always)
    end

    test "negative numbers show the minus sign" do
      assert {:ok, "-1,234"} = Localize.Number.to_string(-1234, sign_display: :always)
    end

    test "a negative number rounding to zero keeps the minus sign" do
      assert {:ok, "-0"} =
               Localize.Number.to_string(-0.2, sign_display: :always, fractional_digits: 0)
    end

    test "the plus sign comes from the locale symbols" do
      assert {:ok, "+1.234"} = Localize.Number.to_string(1234, locale: :de, sign_display: :always)
    end

    test "Decimal input" do
      assert {:ok, "+12.5"} =
               Localize.Number.to_string(Decimal.new("12.5"), sign_display: :always)
    end
  end

  describe "sign_display: :except_zero" do
    test "positive numbers show the plus sign" do
      assert {:ok, "+12"} = Localize.Number.to_string(12, sign_display: :except_zero)
    end

    test "negative numbers show the minus sign" do
      assert {:ok, "-12"} = Localize.Number.to_string(-12, sign_display: :except_zero)
    end

    test "zero shows no sign" do
      assert {:ok, "0"} = Localize.Number.to_string(0, sign_display: :except_zero)
    end

    test "a number rounding to zero shows no sign" do
      assert {:ok, "0"} =
               Localize.Number.to_string(0.0004, sign_display: :except_zero)

      assert {:ok, "0"} =
               Localize.Number.to_string(-0.2, sign_display: :except_zero, fractional_digits: 0)
    end
  end

  describe "sign_display: :negative" do
    test "positive numbers and zero show no sign" do
      assert {:ok, "12"} = Localize.Number.to_string(12, sign_display: :negative)
      assert {:ok, "0"} = Localize.Number.to_string(0, sign_display: :negative)
    end

    test "negative numbers show the minus sign" do
      assert {:ok, "-12"} = Localize.Number.to_string(-12, sign_display: :negative)
    end

    test "a negative number rounding to zero shows no sign" do
      assert {:ok, "0"} =
               Localize.Number.to_string(-0.2, sign_display: :negative, fractional_digits: 0)
    end
  end

  describe "sign_display: :never" do
    test "negative numbers show no sign" do
      assert {:ok, "1,234"} = Localize.Number.to_string(-1234, sign_display: :never)
      assert {:ok, "12.5"} = Localize.Number.to_string(Decimal.new("-12.5"), sign_display: :never)
    end

    test "positive numbers are unchanged" do
      assert {:ok, "1,234"} = Localize.Number.to_string(1234, sign_display: :never)
    end
  end

  describe "sign display with formats" do
    test "percent" do
      assert {:ok, "+50%"} =
               Localize.Number.to_string(0.5, format: :percent, sign_display: :always)
    end

    test "currency places the plus where the derived negative pattern places the minus" do
      assert {:ok, "-$1.00"} = Localize.Number.to_string(-1, currency: :USD)

      assert {:ok, "+$1.00"} =
               Localize.Number.to_string(1, currency: :USD, sign_display: :always)

      assert {:ok, "$1.00"} =
               Localize.Number.to_string(-1, currency: :USD, sign_display: :never)
    end

    test "accounting keeps parentheses for negatives and prefixes plus for positives" do
      assert {:ok, "+$1.00"} =
               Localize.Number.to_string(1,
                 currency: :USD,
                 format: :accounting,
                 sign_display: :always
               )

      assert {:ok, "($1.00)"} =
               Localize.Number.to_string(-1,
                 currency: :USD,
                 format: :accounting,
                 sign_display: :always
               )

      assert {:ok, "$1.00"} =
               Localize.Number.to_string(-1,
                 currency: :USD,
                 format: :accounting,
                 sign_display: :never
               )
    end

    test "compact formats" do
      assert {:ok, "+1.2K"} =
               Localize.Number.to_string(1234, format: :decimal_short, sign_display: :always)

      assert {:ok, "1.2K"} =
               Localize.Number.to_string(-1234, format: :decimal_short, sign_display: :never)
    end

    test "scientific format" do
      assert {:ok, "+1.2345E4"} =
               Localize.Number.to_string(12345, format: "#E0", sign_display: :always)
    end
  end

  describe "sign display with non-finite Decimals" do
    test "NaN takes a plus sign only under :always" do
      assert {:ok, "+NaN"} =
               Localize.Number.to_string(Decimal.new("NaN"), sign_display: :always)

      assert {:ok, "NaN"} =
               Localize.Number.to_string(Decimal.new("NaN"), sign_display: :except_zero)
    end

    test "infinity is signed like any non-zero number" do
      assert {:ok, "+∞"} =
               Localize.Number.to_string(Decimal.new("Infinity"), sign_display: :always)

      assert {:ok, "∞"} =
               Localize.Number.to_string(Decimal.new("-Infinity"), sign_display: :never)
    end
  end

  describe "validation" do
    test "an invalid sign_display returns an error" do
      assert {:error, %Localize.InvalidValueError{} = error} =
               Localize.Number.to_string(1, sign_display: :sometimes)

      assert Exception.message(error) =~ ":sometimes"
    end

    test "a pre-validated options struct carries sign_display" do
      {:ok, options} =
        Localize.Number.Format.Options.validate_options(0, sign_display: :always)

      assert {:ok, "+12"} = Localize.Number.to_string(12, options)
      assert {:ok, "+0"} = Localize.Number.to_string(0, options)
    end
  end
end
