defmodule Localize.AtomInterningTest do
  use ExUnit.Case, async: true

  # Integration coverage for the class of "atom doesn't exist yet"
  # bugs that fall out of the 0.30.0 atom-DOS hardening (see
  # `Localize.Application.intern_supplemental_atoms/0`).
  #
  # A note on scope: these tests don't — and *can't* — assert that an
  # atom exists at app start in isolation, because referencing the
  # atom as a literal anywhere in a test file interns it at module
  # load time, defeating the probe. Instead, each test below
  # exercises a public lookup path that takes a **binary** input and
  # routes through `binary_to_existing_atom` internally; if the
  # corresponding atom collection is not interned at app start, the
  # lookup returns a spurious error and the test fails. The atom
  # collection is loaded once at app start by
  # `intern_supplemental_atoms/0`, which reads each bundled `.etf`
  # via `:erlang.binary_to_term/1` and so interns every constituent
  # atom as a side-effect.
  #
  # The MF2 `numberingSystem=arab` test in
  # `test/localize/message/number_options_test.exs:127` is the
  # original surface of the bug class. The tests below add coverage
  # for the underlying lookup primitives so a regression in any one
  # eager-load surfaces in this file rather than only as a CI
  # flake somewhere downstream.

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
      assert {:ok, formatted} = Localize.Number.System.to_system(12345, "arab")
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
end
