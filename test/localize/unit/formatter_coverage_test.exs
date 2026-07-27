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

    test "Russian prepositional differs from nominative" do
      # Regression: Localize.Data.Normalize.Units.process_formats/1 had no
      # clause for prepositional_count_* keys, so they stayed flat in the
      # locale data and :prepositional silently fell back to :nominative.
      {:ok, prepositional} =
        Unit.to_string(unit!(1, "kilometer"), locale: "ru", grammatical_case: :prepositional)

      {:ok, nominative} = Unit.to_string(unit!(1, "kilometer"), locale: "ru")

      assert prepositional == "1 километре"
      assert nominative == "1 километр"
    end

    test "Finnish partitive differs from nominative" do
      # Regression: Localize.Data.Normalize.Units.process_formats/1 only
      # recognised seven grammatical cases, so partitive (and eight other
      # CLDR cases) stayed flat in the locale data and silently fell back
      # to nominative.
      {:ok, partitive} =
        Unit.to_string(unit!(1, "kilometer"), locale: "fi", grammatical_case: :partitive)

      {:ok, nominative} = Unit.to_string(unit!(1, "kilometer"), locale: "fi")

      assert partitive == "1 kilometriä"
      assert nominative == "1 kilometri"
    end

    test "Hungarian terminative differs from nominative" do
      {:ok, terminative} =
        Unit.to_string(unit!(1, "kilometer"), locale: "hu", grammatical_case: :terminative)

      {:ok, nominative} = Unit.to_string(unit!(1, "kilometer"), locale: "hu")

      assert terminative == "1 kilométerig"
      assert nominative == "1 kilométer"
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

    # A denominator constant was silently dropped in :short, because the
    # denominator's precomposed `per_unit_pattern` ("{0}/d") states "per
    # one day" and has nowhere to put the count. The count is now composed
    # through the locale's `compound.per` pattern in every width.
    test "denominator constant survives every width" do
      unit = unit!(10, "curr-usd-per-30-day")

      assert Unit.to_string(unit, format: :long) == {:ok, "$10.00 per 30 days"}
      assert Unit.to_string(unit, format: :short) == {:ok, "$10.00/30 days"}
      assert Unit.to_string(unit, format: :narrow) == {:ok, "$10.00/30 d"}
    end

    test "denominator constant survives every width in de" do
      unit = unit!(10, "curr-usd-per-30-day")

      assert Unit.to_string(unit, locale: "de", format: :long) ==
               {:ok, "10,00 $ pro 30 Tage"}

      assert Unit.to_string(unit, locale: "de", format: :short) == {:ok, "10,00 $/30 Tg."}
      assert Unit.to_string(unit, locale: "de", format: :narrow) == {:ok, "10,00 $/30 T"}
    end

    # The count used to be spliced in with a blind `String.replace/3` of the
    # denominator noun over the whole composed string, so a numerator whose
    # own symbol contained that noun was corrupted: "candela" is "cd" in
    # narrow, and replacing "d" with "30 d" produced "10c30 d/30 d".
    test "a numerator symbol containing the denominator noun is not corrupted" do
      assert Unit.to_string(unit!(10, "candela-per-30-day"), format: :narrow) ==
               {:ok, "10cd/30 d"}
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
