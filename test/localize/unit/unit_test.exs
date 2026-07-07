defmodule Localize.UnitTest do
  use ExUnit.Case, async: true

  doctest Localize.Unit

  alias Localize.Unit

  describe "new/2" do
    test "creates a unit with an integer value" do
      assert {:ok, unit} = Unit.new(100, "meter")
      assert unit.value == 100
      assert unit.name == "meter"
      assert unit.parsed != nil
    end

    test "creates a unit with a float value" do
      assert {:ok, unit} = Unit.new(3.14, "kilogram")
      assert unit.value == 3.14
      assert unit.name == "kilogram"
    end

    test "creates a unit with a Decimal value" do
      decimal = Decimal.new("99.99")
      assert {:ok, unit} = Unit.new(decimal, "liter")
      assert unit.value == decimal
      assert unit.name == "liter"
    end

    test "creates a unit with a compound unit string" do
      assert {:ok, unit} = Unit.new(60, "mile-per-hour")
      assert unit.value == 60
      assert unit.name == "mile-per-hour"
    end

    test "creates a unit with zero" do
      assert {:ok, unit} = Unit.new(0, "celsius")
      assert unit.value == 0
    end

    test "creates a unit with a negative value" do
      assert {:ok, unit} = Unit.new(-40, "fahrenheit")
      assert unit.value == -40
    end

    test "returns error for invalid unit string" do
      assert {:error, _reason} = Unit.new(100, "foobar")
    end

    test "returns error for non-numeric value" do
      assert {:error, _reason} = Unit.new("hello", "meter")
    end

    test "returns error for list value" do
      assert {:error, _reason} = Unit.new([1, 2], "meter")
    end

    test "returns error for nil value" do
      assert {:error, _reason} = Unit.new(nil, "meter")
    end
  end

  describe "new!/2" do
    test "returns unit directly on success" do
      unit = Unit.new!(42, "kilogram")
      assert unit.value == 42
      assert unit.name == "kilogram"
    end

    test "raises on unknown unit string" do
      assert_raise Localize.UnknownUnitError, fn ->
        Unit.new!(100, "notaunit")
      end
    end

    test "raises on invalid value" do
      assert_raise Localize.InvalidValueError, fn ->
        Unit.new!("bad", "meter")
      end
    end
  end

  describe "new/1 (without value)" do
    test "creates a unit without a value" do
      assert {:ok, unit} = Unit.new("meter")
      assert unit.value == nil
      assert unit.name == "meter"
    end
  end

  describe "humanize/2" do
    test "scales bytes with SI prefixes" do
      assert {:ok, unit} = Unit.new(1_500, "byte")
      assert {:ok, humanized} = Unit.humanize(unit)
      assert humanized.name == "kilobyte"
      assert humanized.value == 1.5

      assert {:ok, unit} = Unit.new(2_750_000_000, "byte")
      assert {:ok, humanized} = Unit.humanize(unit)
      assert humanized.name == "gigabyte"
      assert humanized.value == 2.75

      assert {:ok, unit} = Unit.new(3_100_000_000_000, "byte")
      assert {:ok, humanized} = Unit.humanize(unit)
      assert humanized.name == "terabyte"
      assert humanized.value == 3.1
    end

    test "scales with IEC binary prefixes" do
      assert {:ok, unit} = Unit.new(1_048_576, "byte")
      assert {:ok, humanized} = Unit.humanize(unit, system: :iec)
      assert humanized.name == "mebibyte"
      assert humanized.value == 1.0

      assert {:ok, unit} = Unit.new(2048, "byte")
      assert {:ok, humanized} = Unit.humanize(unit, system: :iec)
      assert humanized.name == "kibibyte"
      assert humanized.value == 2.0
    end

    test "scales bit-based units" do
      assert {:ok, unit} = Unit.new(2_000_000, "bit")
      assert {:ok, humanized} = Unit.humanize(unit)
      assert humanized.name == "megabit"
      assert humanized.value == 2.0
    end

    test "scales hertz- and watt-based units" do
      assert {:ok, unit} = Unit.new(2_500_000_000, "hertz")
      assert {:ok, humanized} = Unit.humanize(unit)
      assert humanized.name == "gigahertz"
      assert humanized.value == 2.5

      assert {:ok, unit} = Unit.new(1_500, "watt")
      assert {:ok, humanized} = Unit.humanize(unit)
      assert humanized.name == "kilowatt"
      assert humanized.value == 1.5
    end

    test "rejects IEC prefixes for hertz- and watt-based units" do
      assert {:ok, unit} = Unit.new(1_500, "watt")
      assert {:error, %Localize.InvalidValueError{}} = Unit.humanize(unit, system: :iec)

      assert {:ok, unit} = Unit.new(1_500, "hertz")
      assert {:error, %Localize.InvalidValueError{}} = Unit.humanize(unit, system: :iec)
    end

    test "leaves values below one kilobyte unchanged" do
      assert {:ok, unit} = Unit.new(512, "byte")
      assert {:ok, humanized} = Unit.humanize(unit)
      assert humanized.name == "byte"
      assert humanized.value == 512

      assert {:ok, unit} = Unit.new(0, "byte")
      assert {:ok, humanized} = Unit.humanize(unit)
      assert humanized.name == "byte"
    end

    test "rescales an already-prefixed unit" do
      assert {:ok, unit} = Unit.new(2_500, "kilobyte")
      assert {:ok, humanized} = Unit.humanize(unit)
      assert humanized.name == "megabyte"
      assert humanized.value == 2.5
    end

    test "scales negative values by magnitude" do
      assert {:ok, unit} = Unit.new(-3_500_000_000, "byte")
      assert {:ok, humanized} = Unit.humanize(unit)
      assert humanized.name == "gigabyte"
      assert humanized.value == -3.5
    end

    test "preserves Decimal values" do
      assert {:ok, unit} = Unit.new(Decimal.new(1_500_000), "byte")
      assert {:ok, humanized} = Unit.humanize(unit)
      assert humanized.name == "megabyte"
      assert Decimal.equal?(humanized.value, Decimal.new("1.5"))
    end

    test "clamps at the largest prefix" do
      assert {:ok, unit} = Unit.new(5_000_000_000_000_000_000_000_000_000, "byte")
      assert {:ok, humanized} = Unit.humanize(unit)
      assert humanized.name == "yottabyte"
      assert humanized.value == 5000.0
    end

    test "returns an error for non-digital units" do
      assert {:ok, unit} = Unit.new(5, "meter")
      assert {:error, %Localize.InvalidValueError{}} = Unit.humanize(unit)
    end

    test "returns an error for compound digital units" do
      assert {:ok, unit} = Unit.new(100, "byte-per-second")
      assert {:error, %Localize.InvalidValueError{}} = Unit.humanize(unit)
    end

    test "returns an error for an invalid prefix system" do
      assert {:ok, unit} = Unit.new(1_500, "byte")
      assert {:error, %Localize.InvalidValueError{}} = Unit.humanize(unit, system: :decimal)
    end

    test "returns an error for a unit without a value" do
      assert {:ok, unit} = Unit.new("byte")
      assert {:error, %Localize.UnitNoValueError{}} = Unit.humanize(unit)
    end

    test "formats as a compact file size with narrow width" do
      assert {:ok, unit} = Unit.new(1_500_000, "byte")
      assert {:ok, humanized} = Unit.humanize(unit)
      assert Unit.to_string(humanized, format: :narrow, locale: :en) == {:ok, "1.5MB"}
    end
  end

  describe "to_string/2 with humanize: true" do
    test "scales digital units through the prefix ladder" do
      unit = Unit.new!(1_500_000, "byte")

      assert Unit.to_string(unit, humanize: true, format: :narrow, locale: :en) ==
               {:ok, "1.5MB"}
    end

    test "honours the :system option for digital units" do
      unit = Unit.new!(1_048_576, "byte")

      assert Unit.to_string(unit, humanize: true, system: :iec, locale: :en) ==
               {:ok, "1 mebibyte"}
    end

    test "scales hertz and watts through the prefix ladder" do
      assert Unit.new!(2_500_000, "hertz")
             |> Unit.to_string(humanize: true, format: :narrow, locale: :en) ==
               {:ok, "2.5MHz"}

      assert Unit.new!(3_200_000_000, "watt") |> Unit.to_string(humanize: true, locale: :en) ==
               {:ok, "3.2 gigawatts"}
    end

    test "renders physical units through usage-based preferences" do
      assert Unit.new!(1_500, "meter") |> Unit.to_string(humanize: true, locale: :de) ==
               {:ok, "1,5 Kilometer"}

      assert Unit.new!(1_500_000, "gram") |> Unit.to_string(humanize: true, locale: :en) ==
               {:ok, "1.653 tons"}
    end

    test "an explicit :usage option wins for physical units" do
      assert Unit.new!(1_500, "meter")
             |> Unit.to_string(humanize: true, usage: :road, locale: "en-US") ==
               {:ok, "0.932 miles"}
    end

    test "the struct usage field is used when set" do
      assert Unit.new!(1.83, "meter", usage: "person-height")
             |> Unit.to_string(humanize: true, locale: "en-US") ==
               {:ok, "6 feet and 0.047 inches"}
    end

    test "a non-true value is ignored" do
      assert Unit.new!(1_500, "meter") |> Unit.to_string(humanize: "yes", locale: :de) ==
               {:ok, "1.500 Meter"}
    end

    test "an invalid :system returns an error tuple" do
      assert {:error, %Localize.InvalidValueError{}} =
               Unit.new!(1_500, "byte") |> Unit.to_string(humanize: true, system: :bogus)
    end
  end

  describe "humanize!/2" do
    test "returns the scaled unit directly on success" do
      unit = Unit.new!(1_500_000, "byte") |> Unit.humanize!()
      assert unit.name == "megabyte"
      assert unit.value == 1.5
    end

    test "raises on a non-digital unit" do
      assert_raise Localize.InvalidValueError, fn ->
        Unit.new!(5, "meter") |> Unit.humanize!()
      end
    end
  end
end
