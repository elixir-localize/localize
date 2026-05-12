defmodule Localize.Unit.FormatterTest do
  use ExUnit.Case, async: true

  doctest Localize.Unit

  alias Localize.Unit

  describe "to_string/2 with simple units" do
    test "formats meter in long style" do
      {:ok, unit} = Unit.new(42, "meter")
      assert {:ok, "42 meters"} = Unit.to_string(unit)
    end

    test "formats singular meter" do
      {:ok, unit} = Unit.new(1, "meter")
      assert {:ok, "1 meter"} = Unit.to_string(unit)
    end

    test "formats in short style" do
      {:ok, unit} = Unit.new(42, "meter")
      assert {:ok, "42 m"} = Unit.to_string(unit, format: :short)
    end

    test "formats in narrow style" do
      {:ok, unit} = Unit.new(42, "meter")
      {:ok, result} = Unit.to_string(unit, format: :narrow)
      assert String.contains?(result, "42")
      assert String.contains?(result, "m")
    end

    test "formats kilogram" do
      {:ok, unit} = Unit.new(2.5, "kilogram")
      {:ok, result} = Unit.to_string(unit)
      assert String.contains?(result, "kilogram")
    end

    test "formats celsius" do
      {:ok, unit} = Unit.new(100, "celsius")
      {:ok, result} = Unit.to_string(unit, format: :short)
      assert String.contains?(result, "°C")
    end
  end

  describe "to_string/2 with compound units" do
    test "formats mile-per-hour in long style" do
      {:ok, unit} = Unit.new(60, "mile-per-hour")
      assert {:ok, "60 miles per hour"} = Unit.to_string(unit)
    end

    test "formats mile-per-hour in short style" do
      {:ok, unit} = Unit.new(60, "mile-per-hour")
      assert {:ok, "60 mph"} = Unit.to_string(unit, format: :short)
    end
  end

  describe "to_string/2 with locales" do
    test "formats in German" do
      {:ok, unit} = Unit.new(2.5, "kilogram")
      {:ok, result} = Unit.to_string(unit, locale: :de)
      assert String.contains?(result, "Kilogramm")
    end

    test "formats in French" do
      {:ok, unit} = Unit.new(42, "meter")
      {:ok, result} = Unit.to_string(unit, locale: :fr)
      assert String.contains?(result, "mètre")
    end
  end

  describe "to_string/2 with zero and fractional values" do
    test "formats zero" do
      {:ok, unit} = Unit.new(0, "meter")
      {:ok, result} = Unit.to_string(unit)
      assert String.contains?(result, "0")
      assert String.contains?(result, "meter")
    end

    test "formats fractional value" do
      {:ok, unit} = Unit.new(1.5, "meter")
      {:ok, result} = Unit.to_string(unit)
      assert String.contains?(result, "1.5")
    end
  end

  describe "to_string!/2" do
    test "returns string directly" do
      {:ok, unit} = Unit.new(42, "meter")
      assert "42 meters" = Unit.to_string!(unit)
    end
  end

  describe "to_string/2 without value" do
    test "returns display name when no value" do
      {:ok, unit} = Unit.new("meter")
      {:ok, result} = Unit.to_string(unit)
      assert result == "meters"
    end
  end
end
