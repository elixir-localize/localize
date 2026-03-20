defmodule Localize.UnitTest do
  use ExUnit.Case, async: true

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

    test "raises on invalid unit string" do
      assert_raise Localize.ParseError, fn ->
        Unit.new!(100, "not-a-unit")
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
end
