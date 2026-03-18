defmodule Localize.Unit.DataTest do
  use ExUnit.Case, async: true

  alias Localize.Unit.Data

  describe "prefix_components/0" do
    test "returns a non-empty list" do
      assert length(Data.prefix_components()) > 0
    end

    test "includes known prefix components" do
      prefixes = Data.prefix_components()
      assert "arc" in prefixes
      assert "british" in prefixes
      assert "fluid" in prefixes
      assert "nautical" in prefixes
      assert "light" in prefixes
    end
  end

  describe "suffix_components/0" do
    test "returns a non-empty list" do
      assert length(Data.suffix_components()) > 0
    end

    test "includes known suffix components" do
      suffixes = Data.suffix_components()
      assert "force" in suffixes
      assert "imperial" in suffixes
      assert "metric" in suffixes
      assert "person" in suffixes
      assert "troy" in suffixes
    end
  end

  describe "power_components/0" do
    test "includes square and cubic" do
      powers = Data.power_components()
      assert "square" in powers
      assert "cubic" in powers
    end

    test "includes pow2 through pow15" do
      powers = Data.power_components()

      for n <- 2..15 do
        assert "pow#{n}" in powers
      end
    end
  end

  describe "si_prefix_names/0" do
    test "returns 32 prefixes (24 decimal + 8 binary)" do
      assert length(Data.si_prefix_names()) == 32
    end

    test "includes common SI prefixes" do
      prefixes = Data.si_prefix_names()
      assert "kilo" in prefixes
      assert "milli" in prefixes
      assert "mega" in prefixes
      assert "nano" in prefixes
      assert "micro" in prefixes
    end

    test "includes binary prefixes" do
      prefixes = Data.si_prefix_names()
      assert "kibi" in prefixes
      assert "mebi" in prefixes
      assert "gibi" in prefixes
    end
  end

  describe "si_prefix_data/0" do
    test "returns maps with type, symbol, and power fields" do
      kilo = Enum.find(Data.si_prefix_data(), &(&1.type == "kilo"))
      assert kilo.symbol == "k"
      assert kilo.power10 == "3"
    end

    test "binary prefix has power2 field" do
      kibi = Enum.find(Data.si_prefix_data(), &(&1.type == "kibi"))
      assert kibi.symbol == "Ki"
      assert kibi.power2 == "10"
    end
  end

  describe "base_units/0" do
    test "returns a non-empty list" do
      assert length(Data.base_units()) > 100
    end

    test "includes common base units" do
      units = Data.base_units()
      assert "meter" in units
      assert "kilogram" in units
      assert "second" in units
      assert "ampere" in units
      assert "kelvin" in units
    end

    test "includes compound base units" do
      units = Data.base_units()
      assert "nautical-mile" in units
      assert "british-thermal-unit" in units
      assert "light-year" in units
      assert "arc-second" in units
    end

    test "includes generic (added manually)" do
      assert "generic" in Data.base_units()
    end
  end

  describe "categories/0" do
    test "includes common categories" do
      categories = Data.categories()
      assert "length" in categories
      assert "mass" in categories
      assert "speed" in categories
      assert "temperature" in categories
      assert "volume" in categories
    end
  end

  describe "valid_unit_identifiers/0" do
    test "returns a large list" do
      assert length(Data.valid_unit_identifiers()) > 200
    end

    test "includes known identifiers" do
      ids = Data.valid_unit_identifiers()
      assert "length-kilometer" in ids
      assert "mass-kilogram" in ids
      assert "speed-meter-per-second" in ids
    end
  end
end
