defmodule Localize.Unit.FormatterCoverageTest do
  use ExUnit.Case, async: true

  alias Localize.Unit

  defp unit!(value, name) do
    {:ok, unit} = Unit.new(value, name)
    unit
  end

  describe "grammatical case" do
    test "German dative plural" do
      assert Unit.to_string(unit!(3, "meter"), locale: "de", grammatical_case: :dative) ==
               {:ok, "3 Metern"}
    end

    test "German genitive singular" do
      assert Unit.to_string(unit!(1, "meter"), locale: "de", grammatical_case: :genitive) ==
               {:ok, "1 Meters"}
    end

    test "German nominative is the default" do
      assert Unit.to_string(unit!(3, "meter"), locale: "de") == {:ok, "3 Meter"}

      assert Unit.to_string(unit!(3, "meter"), locale: "de", grammatical_case: :nominative) ==
               {:ok, "3 Meter"}
    end

    test "Ukrainian locative differs from nominative" do
      {:ok, locative} =
        Unit.to_string(unit!(3, "meter"), locale: "uk", grammatical_case: :locative)

      {:ok, nominative} = Unit.to_string(unit!(3, "meter"), locale: "uk")

      assert locative == "3 метрах"
      assert nominative == "3 метри"
    end

    test "unknown grammatical case falls back to nominative" do
      assert Unit.to_string(unit!(3, "meter"), locale: "de", grammatical_case: :vocative) ==
               {:ok, "3 Meter"}
    end
  end

  describe "currency units" do
    test "plain currency unit formats as a currency" do
      assert Unit.to_string(unit!(2, "curr-usd")) == {:ok, "$2.00"}
    end

    test "currency-per-unit formats with a per pattern" do
      assert Unit.to_string(unit!(3.5, "curr-usd-per-hour")) == {:ok, "$3.50 per hour"}
    end

    test "currency-per-unit localizes both parts" do
      assert Unit.to_string(unit!(10, "curr-eur-per-day"), locale: "de") ==
               {:ok, "10,00 € pro Tag"}
    end

    test "currency-per-unit includes the SI prefix of the denominator" do
      # Regression: extract_denominator_parts/1 dropped the :prefix of
      # the denominator single unit, rendering "per meter".
      assert Unit.to_string(unit!(1, "curr-usd-per-kilometer")) ==
               {:ok, "$1.00 per kilometer"}
    end

    test "currency-per-unit includes the power of the denominator" do
      assert Unit.to_string(unit!(5, "curr-usd-per-square-kilometer")) ==
               {:ok, "$5.00 per square kilometer"}
    end

    test "currency-per-unit with a denominator constant pluralizes the unit" do
      # Regression: rendered "per 100 meter" — the prefix was dropped and
      # the noun stayed singular. With a constant the denominator noun is
      # plural in en, as in ICU's "liter-per-100-kilometer" pattern.
      assert Unit.to_string(unit!(5, "curr-usd-per-100-kilometer")) ==
               {:ok, "$5.00 per 100 kilometers"}
    end

    test "currency-per-unit with a denominator constant localizes the plural noun" do
      assert Unit.to_string(unit!(5, "curr-usd-per-100-kilometer"), locale: "de") ==
               {:ok, "5,00 $ pro 100 Kilometer"}
    end
  end

  describe "styles and style aliases" do
    test "the removed :style alias is ignored like any unknown option" do
      assert Unit.to_string(unit!(2, "meter"), style: :short) == {:ok, "2 meters"}
    end

    test "invalid style returns an InvalidValueError" do
      assert {:error, %Localize.InvalidValueError{value: :bogus}} =
               Unit.to_string(unit!(2, "meter"), format: :bogus)
    end

    test "French narrow style joins the number and symbol" do
      assert Unit.to_string(unit!(3, "meter"), locale: "fr", format: :narrow) == {:ok, "3m"}
    end
  end

  describe "number format options pass through" do
    test "fractional_digits is applied to the number" do
      assert Unit.to_string(unit!(3, "meter"), fractional_digits: 2) == {:ok, "3.00 meters"}
    end
  end

  describe "compound and denominator-constant units" do
    test "per-100-kilometer denominator constant is spelled out" do
      assert Unit.to_string(unit!(7, "liter-per-100-kilometer")) ==
               {:ok, "7 liters per 100 kilometers"}
    end

    test "meter-per-square-second uses the CLDR compound pattern" do
      assert Unit.to_string(unit!(9.8, "meter-per-square-second")) ==
               {:ok, "9.8 meters per second squared"}
    end
  end

  describe "display names and fallbacks" do
    test "unit without a value formats as its display name" do
      unit = %Unit{name: "meter", value: nil, parsed: nil}
      assert Unit.to_string(unit) == {:ok, "meters"}
    end

    test "unknown unit falls back to value plus name" do
      unit = %Unit{name: "flurble", value: 3, parsed: nil}
      assert Localize.Unit.Formatter.to_string(unit) == {:ok, "3 flurble"}
    end
  end

  describe "error paths" do
    test "invalid locale returns an InvalidLocaleError" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Unit.to_string(unit!(2, "meter"), locale: "zz")
    end
  end
end
