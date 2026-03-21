defmodule Localize.Number.SystemTest do
  use ExUnit.Case, async: true

  doctest Localize.Number.System

  alias Localize.Number.System

  describe "number_systems/0" do
    test "returns a map of all number systems" do
      systems = System.number_systems()
      assert is_map(systems)
      assert Map.has_key?(systems, :latn)
      assert systems[:latn].type == :numeric
      assert systems[:latn].digits == "0123456789"
    end
  end

  describe "number_systems_for/1" do
    test "returns number system types for a locale" do
      {:ok, systems} = System.number_systems_for(:en)
      assert systems.default == :latn
      assert systems.native == :latn
    end
  end

  describe "number_system_from_locale/1" do
    test "returns default system for a string locale" do
      {:ok, system} = System.number_system_from_locale("en-US")
      assert system == :latn
    end

    test "returns default system for an atom locale" do
      {:ok, system} = System.number_system_from_locale(:en)
      assert system == :latn
    end
  end

  describe "system_name_from/2" do
    test "resolves a type to a system name" do
      {:ok, name} = System.system_name_from(:default, :en)
      assert name == :latn
    end

    test "passes through a direct system name" do
      {:ok, name} = System.system_name_from(:latn, :en)
      assert name == :latn
    end
  end

  describe "number_system_digits/1" do
    test "returns digits for latn" do
      {:ok, digits} = System.number_system_digits(:latn)
      assert digits == "0123456789"
    end

    test "returns error for unknown system" do
      {:error, _exception} = System.number_system_digits(:nope)
    end
  end

  describe "to_system/2" do
    test "transliterates to a numeric system" do
      {:ok, result} = System.to_system(123, :deva)
      assert is_binary(result)
    end

    test "formats using algorithmic system (RBNF)" do
      {:ok, result} = System.to_system(123, :roman)
      assert result == "CXXIII"
    end
  end

  describe "generate_transliteration_map/2" do
    test "creates a correct mapping" do
      map = System.generate_transliteration_map("abc", "xyz")
      assert map == %{"a" => "x", "b" => "y", "c" => "z"}
    end

    test "returns error for different length strings" do
      {:error, _exception} = System.generate_transliteration_map("abc", "xy")
    end
  end
end
