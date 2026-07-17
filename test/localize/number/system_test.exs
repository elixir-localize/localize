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

  describe "system_name_from/2 error cases" do
    test "accepts a globally-known system the locale does not list" do
      # :arab IS a known CLDR number system globally even though it
      # is NOT in the numbering systems available for the :en locale.
      # Per TR35/ICU an explicit numbering-system request is honoured
      # for any CLDR system — formats and symbols inherit from the
      # locale's default system while digits come from the requested
      # system.
      assert {:ok, :arab} = System.system_name_from(:arab, :en)
      assert {:ok, :thai} = System.system_name_from(:thai, :en)
    end

    test "returns not-known error for a completely unknown system" do
      assert {:error, %Localize.UnknownNumberSystemError{} = err} =
               System.system_name_from(:nonsense_xyz, :en)

      assert err.reason == nil
      assert err.number_system == :nonsense_xyz
      assert Exception.message(err) =~ "is not known"
    end

    test "accepts a system that IS valid for the locale" do
      assert {:ok, :arab} = System.system_name_from(:arab, :ar)
      assert {:ok, :latn} = System.system_name_from(:latn, :en)
    end
  end

  describe "Localize.Number.to_string with a number system the locale does not list" do
    test "formats with the requested system's digits" do
      assert {:ok, "١,٢٣٤"} = Localize.Number.to_string(1234, locale: :en, number_system: :arab)
    end

    test "returns UnknownNumberSystemError for an unknown system" do
      assert {:error, %Localize.UnknownNumberSystemError{}} =
               Localize.Number.to_string(1234, locale: :en, number_system: :nonsense_xyz)
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

  # Regression: the three public APIs that accept a binary number-system
  # name used to call `String.to_atom/1` on it before checking validity.
  # Atomisation is now gated on `Helpers.existing_atom/1`.
  describe "atom-table bound on unknown binary number-system name" do
    test "system_name_from does not create an atom for unknown system" do
      bogus = "ZZZ_system_name_from_#{Elixir.System.unique_integer([:positive])}"

      assert {:error, %Localize.UnknownNumberSystemError{}} =
               System.system_name_from(bogus, :en)

      assert nil == Localize.Utils.Helpers.existing_atom(bogus)
    end

    test "number_system_digits does not create an atom for unknown system" do
      bogus = "ZZZ_digits_#{Elixir.System.unique_integer([:positive])}"
      assert {:error, _} = System.number_system_digits(bogus)
      assert nil == Localize.Utils.Helpers.existing_atom(bogus)
    end

    test "to_system does not create an atom for unknown system" do
      bogus = "ZZZ_to_system_#{Elixir.System.unique_integer([:positive])}"
      assert {:error, _} = System.to_system(42, bogus)
      assert nil == Localize.Utils.Helpers.existing_atom(bogus)
    end
  end

  describe "bang variants raise on error" do
    test "number_systems_for!/1 raises for an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        System.number_systems_for!("zz-invalid")
      end
    end

    test "number_system_names_for!/1 raises for an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        System.number_system_names_for!("zz-invalid")
      end
    end

    test "system_name_from!/2 raises for an unknown system" do
      assert_raise Localize.UnknownNumberSystemError, fn ->
        System.system_name_from!(:nosuch, :en)
      end
    end

    test "number_system_digits!/1 raises for an unknown system" do
      assert_raise Localize.InvalidValueError, fn ->
        System.number_system_digits!(:nosuch)
      end
    end

    test "to_system!/2 raises for an unknown system" do
      assert_raise Localize.InvalidValueError, fn ->
        System.to_system!(123, :nosuch)
      end
    end
  end

  describe "number_system_from_locale/1 with a -u-nu- override" do
    test "returns the nu extension system" do
      {:ok, tag} = Localize.validate_locale("en-u-nu-thai")
      assert System.number_system_from_locale(tag) == {:ok, :thai}
    end
  end
end
