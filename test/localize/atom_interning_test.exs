defmodule Localize.AtomInterningTest do
  use ExUnit.Case, async: true

  # Integration coverage for the class of "atom doesn't exist yet" bugs
  # that fall out of the atom-DOS hardening: a binary input is never made
  # an atom, so a lookup either matches it against data it has read, or
  # asks `binary_to_existing_atom` whether the VM has the atom already.
  # The second is only sound when the data that interns the atom has been
  # read first. Matched before that read, `"en-US"` took the world's hour
  # cycle, `"ussystem"` was an unknown measurement system and `"TA"` had
  # no currency — each until something else had loaded the data (#70).
  #
  # A note on scope: these tests cannot reproduce that fresh-BEAM failure,
  # because naming an atom as a literal anywhere in a test file interns
  # it at module load, and reading the data to iterate it interns every
  # atom in it. They assert the contract instead — a binary and the atom
  # it names answer alike — which the fixes make true whatever the VM has
  # seen. `mix run -e` from a cold VM, the binary call first, shows the
  # failure itself.
  #
  # The MF2 `numberingSystem=arab` test in
  # `test/localize/message/number_options_test.exs:127` is the original
  # surface of the bug class.

  describe "Localize.Number.System lookups with binary input" do
    test "system_name_from/2 resolves a binary system name in a foreign locale" do
      # This is the exact call sequence the MF2 `:number` function
      # makes for `{$n :number numberingSystem=arab}`. Before the
      # eager-load it returned {:error, ...} on a fresh BEAM because
      # `to_atom_key("arab")` could not find `:arab` interned.
      assert {:ok, system} = Localize.Number.System.system_name_from("arab", "ar")
      assert Atom.to_string(system) == "arab"
    end

    test "number_system_digits/1 resolves a binary system name" do
      assert {:ok, digits} = Localize.Number.System.number_system_digits("arab")
      assert is_binary(digits)
    end

    test "to_system/2 resolves a binary system name" do
      assert {:ok, formatted} = Localize.Number.System.to_system(12_345, "arab")
      assert is_binary(formatted)
    end
  end

  describe "Localize.Currency lookups with binary input" do
    test "validate_currency/1 resolves a known binary currency code" do
      # Same shape: relies on currency code atoms being interned at
      # app start so `existing_atom` succeeds for legitimate codes.
      assert {:ok, currency} = Localize.Currency.validate_currency("USD")
      assert Atom.to_string(currency) == "USD"
    end
  end

  describe "Localize.Calendar lookups with binary input" do
    test "validate_calendar/1 resolves a known binary calendar id" do
      assert {:ok, calendar} = Localize.validate_calendar("gregorian")
      assert Atom.to_string(calendar) == "gregorian"
    end
  end

  describe "Localize.Territory lookups with binary input" do
    test "validate_territory/1 resolves a known binary territory code" do
      assert {:ok, territory} = Localize.validate_territory("US")
      assert Atom.to_string(territory) == "US"
    end
  end

  describe "Localize.Script lookups with binary input" do
    test "validate_script/1 resolves a known binary script code" do
      assert {:ok, script} = Localize.validate_script("Latn")
      assert Atom.to_string(script) == "Latn"
    end
  end

  describe "a binary and the atom it names answer alike" do
    test "Localize.validate_measurement_system/1, for every system and alias" do
      %{systems: systems, aliases: aliases} = Localize.SupplementalData.measurement_systems()

      for name <- Map.keys(systems) ++ Map.keys(aliases) do
        assert Localize.validate_measurement_system(Atom.to_string(name)) ==
                 Localize.validate_measurement_system(name),
               "#{name} answers differently as a binary"
      end
    end

    # A deprecated code validates to its replacement — "AN" to :CW — so the
    # atom compared with is the validated one.
    test "Localize.Currency territory lookups, for every known territory" do
      for territory <- Localize.SupplementalData.known_territories() do
        code = Atom.to_string(territory)
        assert {:ok, canonical} = Localize.validate_territory(territory)

        assert Localize.Currency.territory_currencies(code) ==
                 Localize.Currency.territory_currencies(canonical),
               "territory_currencies(#{inspect(code)}) differs from its atom"

        assert Localize.Currency.territory_currencies(String.downcase(code)) ==
                 Localize.Currency.territory_currencies(canonical)

        assert Localize.Currency.current_currency_for_territory(code) ==
                 Localize.Currency.current_currency_for_territory(canonical),
               "current_currency_for_territory(#{inspect(code)}) differs from its atom"
      end
    end

    test "Localize.Territory.Subdivision.display_name/2, for a binary code" do
      assert {:ok, "Cumbria"} = Localize.Territory.Subdivision.display_name("gbcma", locale: :en)

      assert Localize.Territory.Subdivision.display_name("gbcma", locale: :en) ==
               Localize.Territory.Subdivision.display_name(:gbcma, locale: :en)
    end
  end
end
