defmodule Localize.Unit.ParseTest do
  use ExUnit.Case, async: true

  # `Localize.Unit.parse/2` and `parse_unit_name/2` — localized
  # unit-string parsing, mirroring ex_cldr_units' `Cldr.Unit.parse/2`
  # including the :only/:except disambiguation and alphabetical
  # resolution of ambiguous names.

  describe "parse/2" do
    test "parses number and unit with or without whitespace" do
      assert {:ok, unit} = Localize.Unit.parse("1kg")
      assert unit.value == 1
      assert unit.name == "kilogram"

      assert {:ok, unit} = Localize.Unit.parse("1 kilogram")
      assert unit.name == "kilogram"

      assert {:ok, unit} = Localize.Unit.parse("23 km")
      assert {unit.value, unit.name} == {23, "kilometer"}
    end

    test "an ambiguous name resolves alphabetically" do
      # "w" matches watt (narrow "W") and week (narrow "w")
      # case-insensitively; watt sorts first.
      assert {:ok, unit} = Localize.Unit.parse("2w")
      assert unit.name == "watt"
    end

    test ":only and :except disambiguate by category or unit name" do
      assert {:ok, unit} = Localize.Unit.parse("2w", only: :duration)
      assert unit.name == "week"

      assert {:ok, unit} = Localize.Unit.parse("2w", except: :duration)
      assert unit.name == "watt"

      assert {:ok, unit} = Localize.Unit.parse("2w", only: ["week"])
      assert unit.name == "week"

      assert {:error, %Localize.UnknownUnitError{}} =
               Localize.Unit.parse("2w", only: :mass)
    end

    test "parses localized unit names and numbers" do
      assert {:ok, unit} = Localize.Unit.parse("2 Tage", locale: :de)
      assert unit.name == "day"

      assert {:ok, unit} = Localize.Unit.parse("2,5 kg", locale: :de)
      assert {unit.value, unit.name} == {2.5, "kilogram"}
    end

    test "canonical compound identifiers parse via the unit grammar" do
      assert {:ok, unit} = Localize.Unit.parse("100 kilometer-per-hour")
      assert unit.name == "kilometer-per-hour"
    end

    test "unit symbols resolving to compound names parse (issue #42)" do
      # The locale name index keys compound units with underscores
      # (:meter_per_second); resolving a symbol must yield the canonical
      # hyphenated identifier the grammar accepts, not the raw key.
      assert {:ok, %{name: "meter-per-second"}} = Localize.Unit.parse("1 m/s")
      assert {:ok, %{name: "kilowatt-hour"}} = Localize.Unit.parse("3 kWh")
      assert {:ok, %{name: "kilometer-per-hour"}} = Localize.Unit.parse("5 km/h")
      assert {:ok, %{name: "mile-per-hour"}} = Localize.Unit.parse("2 mph")
    end

    test "parses units registered at runtime" do
      :ok =
        Localize.Unit.define_unit("cubit", %{
          base_unit: "meter",
          factor: 0.4572,
          category: "length",
          display: %{en: %{long: %{one: "{0} cubit", other: "{0} cubits"}}}
        })

      assert {:ok, unit} = Localize.Unit.parse("5 cubits")
      assert unit.name == "cubit"
    end

    test "unknown names and numberless strings are errors" do
      assert {:error, %Localize.UnknownUnitError{unit: "blorb"}} =
               Localize.Unit.parse("1 blorb")

      assert {:error, %Localize.InvalidValueError{}} = Localize.Unit.parse("no number here")
      assert {:error, %Localize.InvalidValueError{}} = Localize.Unit.parse("42")
    end

    test "an invalid locale is an error" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Localize.Unit.parse("1kg", locale: "zz-invalid!")
    end

    test "parse!/2 returns the unit or raises" do
      assert Localize.Unit.parse!("1kg").name == "kilogram"

      assert_raise Localize.UnknownUnitError, fn ->
        Localize.Unit.parse!("1 blorb")
      end
    end
  end

  describe "parse_unit_name/2" do
    test "resolves localized names to canonical identifiers" do
      assert Localize.Unit.parse_unit_name("kg") == {:ok, "kilogram"}
      assert Localize.Unit.parse_unit_name("kilograms") == {:ok, "kilogram"}
      assert Localize.Unit.parse_unit_name("Tage", locale: :de) == {:ok, "day"}
    end

    test "applies the same disambiguation options" do
      assert Localize.Unit.parse_unit_name("w") == {:ok, "watt"}
      assert Localize.Unit.parse_unit_name("w", only: :duration) == {:ok, "week"}
    end

    test "unknown names are errors" do
      assert {:error, %Localize.UnknownUnitError{}} = Localize.Unit.parse_unit_name("blorb")
    end

    test "parse_unit_name!/2 returns the name or raises" do
      assert Localize.Unit.parse_unit_name!("kg") == "kilogram"

      assert_raise Localize.UnknownUnitError, fn ->
        Localize.Unit.parse_unit_name!("blorb")
      end
    end
  end
end
