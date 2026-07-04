defmodule Localize.UnitApiCoverageTest do
  use ExUnit.Case, async: true

  alias Localize.Unit

  defp unit!(value, name), do: Unit.new!(value, name)

  describe "convert/2 error and mixed-unit paths" do
    test "a unit without a value cannot be converted" do
      assert {:error, %Localize.UnitNoValueError{operation: :convert}} =
               Unit.convert(Unit.new!("meter"), "foot")
    end

    test "converts a scalar unit to a mixed unit" do
      {:ok, mixed} = Unit.convert(unit!(180, "centimeter"), "foot-and-inch")

      assert mixed.name == "foot-and-inch"
      assert [5, inches] = mixed.value
      assert_in_delta inches, 10.866141732283467, 1.0e-9
    end

    test "converts a mixed unit back to a scalar unit" do
      {:ok, mixed} = Unit.convert(unit!(180, "centimeter"), "foot-and-inch")
      {:ok, back} = Unit.convert(mixed, "centimeter")

      assert back.name == "centimeter"
      assert_in_delta back.value, 180.0, 1.0e-9
    end

    test "mixed to mixed conversion currently returns an error" do
      # BUG (reported): convert_to_mixed/3 passes the mixed source name
      # ("foot-and-inch") to Conversion.convert/3 instead of the effective
      # first-component name, so mixed → mixed conversion always fails.
      {:ok, mixed} = Unit.convert(unit!(180, "centimeter"), "foot-and-inch")

      assert {:error, %Localize.UnitConversionError{reason: :mixed_units}} =
               Unit.convert(mixed, "yard-and-foot-and-inch")
    end

    test "convert!/2 raises when units are not convertible" do
      assert_raise Localize.UnitConversionError, fn ->
        Unit.convert!(unit!(1, "meter"), "kilogram")
      end
    end
  end

  describe "convert_measurement_system/2" do
    test "converts to the UK preference" do
      {:ok, converted} = Unit.convert_measurement_system(unit!(100, "meter"), :uk)

      assert converted.name == "mile"
      assert_in_delta converted.value, 0.0621371192237334, 1.0e-12
    end

    test "converts to the metric preference" do
      {:ok, converted} = Unit.convert_measurement_system(unit!(5000, "meter"), :metric)

      assert converted.name == "kilometer"
      assert converted.value == 5.0
    end

    test "converts temperature to the US preference" do
      {:ok, converted} = Unit.convert_measurement_system(unit!(30, "celsius"), :us)

      assert converted.name == "fahrenheit"
      assert_in_delta converted.value, 86.0, 1.0e-9
    end

    test "an invalid system returns an InvalidValueError" do
      assert {:error, %Localize.InvalidValueError{value: :bogus}} =
               Unit.convert_measurement_system(unit!(100, "meter"), :bogus)
    end

    test "a unit without a value returns a UnitNoValueError" do
      assert {:error, %Localize.UnitNoValueError{}} =
               Unit.convert_measurement_system(Unit.new!("meter"), :us)
    end
  end

  describe "compare/2" do
    test "equal values across unit scales" do
      assert Unit.compare(unit!(1, "kilometer"), unit!(1000, "meter")) == :eq
    end

    test "less than and greater than" do
      assert Unit.compare(unit!(1, "meter"), unit!(2, "meter")) == :lt
      assert Unit.compare(unit!(3, "meter"), unit!(2, "meter")) == :gt
    end

    test "Decimal values are compared numerically" do
      assert Unit.compare(unit!(Decimal.new("1.5"), "meter"), unit!(150, "centimeter")) == :eq
    end

    test "incompatible units return a conversion error" do
      assert {:error, %Localize.UnitConversionError{reason: :not_convertible}} =
               Unit.compare(unit!(1, "meter"), unit!(1, "kilogram"))
    end

    test "a unit without a value returns a UnitNoValueError" do
      assert {:error, %Localize.UnitNoValueError{operation: :compare}} =
               Unit.compare(Unit.new!("meter"), unit!(1, "meter"))
    end
  end

  describe "to_iolist/2 and to_string!/2" do
    test "to_iolist/2 wraps the formatted string" do
      assert Unit.to_iolist(unit!(42, "meter")) == {:ok, ["42 meters"]}
    end

    test "to_iolist/2 propagates errors" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Unit.to_iolist(unit!(42, "meter"), locale: "xx")
    end

    test "to_string!/2 raises on an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Unit.to_string!(unit!(1, "meter"), locale: "xx")
      end
    end

    test "formatting a list passes list_options to the list formatter" do
      units = [unit!(1, "foot"), unit!(3, "inch")]

      assert Unit.to_string(units, list_options: [list_style: :unit_narrow], format: :narrow) ==
               {:ok, "1′ 3″"}
    end

    test "formatting a list halts on the first element error" do
      units = [unit!(1, "foot"), unit!(3, "inch")]

      assert {:error, %Localize.InvalidLocaleError{}} = Unit.to_string(units, locale: "xx")
    end
  end

  describe "new!/1 and usage validation" do
    test "new!/1 raises on an unknown unit" do
      assert_raise Localize.UnknownUnitError, fn ->
        Unit.new!("bogus-unit-name")
      end
    end

    test "an unknown usage string is rejected with the allowed values" do
      assert {:error, %Localize.InvalidValueError{value: "bogus-usage", context: "usage"}} =
               Unit.new(5, "meter", usage: "bogus-usage")
    end

    test "a non-string usage is rejected" do
      assert {:error, %Localize.InvalidValueError{value: :person_height, context: "usage"}} =
               Unit.new(5, "meter", usage: :person_height)
    end

    test "an unknown base name inside a mixed unit is rejected" do
      assert {:error, %Localize.UnknownUnitError{unit: "floop"}} =
               Unit.new(1, "foot-and-floop")
    end

    test "an unknown currency code inside a mixed unit is rejected" do
      assert {:error, %Localize.UnknownCurrencyError{currency: "ZZZ"}} =
               Unit.new(1, "curr-zzz-and-inch")
    end

    test "an unknown currency code in a compound unit is rejected" do
      assert {:error, %Localize.UnknownCurrencyError{}} = Unit.new(5, "curr-xyz-per-hour")
    end
  end

  describe "localize/2 and decompose/3 edge cases" do
    test "localize/2 requires a value" do
      assert {:error, %Localize.UnitNoValueError{operation: :localize}} =
               Unit.localize(Unit.new!("meter"))
    end

    test "decompose/3 requires a value" do
      assert {:error, %Localize.UnitNoValueError{operation: :decompose}} =
               Unit.decompose(Unit.new!("meter"), ["foot"])
    end

    test "decompose/3 with an empty target list returns an empty list" do
      assert Unit.decompose(unit!(1, "meter"), []) == {:ok, []}
    end

    test "decompose/3 propagates conversion errors" do
      assert {:error, %Localize.UnitConversionError{}} =
               Unit.decompose(unit!(1, "meter"), ["kilogram"])
    end

    test "decompose/3 with a single zero-valued target returns an empty list" do
      assert Unit.decompose(unit!(0, "meter"), ["centimeter"]) == {:ok, []}
    end
  end

  describe "introspection" do
    test "zero?/1 with Decimal values" do
      assert Unit.zero?(unit!(Decimal.new(0), "meter"))
      refute Unit.zero?(unit!(Decimal.new("1.5"), "meter"))
    end

    test "unit_category/1 derives the category of compound units" do
      assert Unit.unit_category("mile-per-hour") == {:ok, "speed"}
      assert Unit.unit_category(unit!(1, "meter-per-second")) == {:ok, "speed"}
    end

    test "unit_category/1 returns an error for an unknown unit" do
      assert {:error, %Localize.UnknownUnitError{unit: "bogus"}} = Unit.unit_category("bogus")
    end

    test "compatible?/2 accepts structs on either side" do
      assert Unit.compatible?(unit!(1, "meter"), "foot")
      assert Unit.compatible?("meter", unit!(1, "foot"))
      refute Unit.compatible?(unit!(1, "meter"), unit!(1, "kilogram"))
    end
  end

  describe "display_name/2" do
    test "accepts a unit struct and ignores its value" do
      assert Unit.display_name(unit!(5, "meter")) == {:ok, "meters"}
    end

    test "returns an error for an unknown unit" do
      assert {:error, %Localize.UnknownUnitError{unit: "bogus"}} = Unit.display_name("bogus")
    end

    test "display_name!/2 returns the name directly" do
      assert Unit.display_name!("second", style: :narrow) == "sec"
    end

    test "display_name!/2 raises on an unknown unit" do
      assert_raise Localize.UnknownUnitError, fn ->
        Unit.display_name!("bogus")
      end
    end
  end
end
