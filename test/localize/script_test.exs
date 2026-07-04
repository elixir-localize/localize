defmodule Localize.ScriptTest do
  use ExUnit.Case, async: true

  doctest Localize.Script

  alias Localize.Script

  describe "display_name/2" do
    test "returns standard display name for a script atom" do
      assert {:ok, "Latin"} = Script.display_name(:Latn)
      assert {:ok, "Cyrillic"} = Script.display_name(:Cyrl)
      assert {:ok, "Arabic"} = Script.display_name(:Arab)
    end

    test "accepts string script codes" do
      assert {:ok, "Latin"} = Script.display_name("Latn")
      assert {:ok, "Cyrillic"} = Script.display_name("Cyrl")
    end

    test "returns short style when available" do
      assert {:ok, "UCAS"} = Script.display_name(:Cans, style: :short)
    end

    test "returns stand_alone style when available" do
      assert {:ok, "Simplified Han"} = Script.display_name(:Hans, style: :stand_alone)
      assert {:ok, "Traditional Han"} = Script.display_name(:Hant, style: :stand_alone)
    end

    test "returns variant style when available" do
      assert {:ok, "Perso-Arabic"} = Script.display_name(:Arab, style: :variant)
    end

    test "falls back to standard when requested style is unavailable" do
      assert {:ok, "Latin"} = Script.display_name(:Latn, style: :short)
      assert {:ok, "Latin"} = Script.display_name(:Latn, style: :variant)
    end

    test "returns display name in a different locale" do
      assert {:ok, "Lateinisch"} = Script.display_name(:Latn, locale: :de)
      assert {:ok, "Kyrillisch"} = Script.display_name(:Cyrl, locale: :de)
    end

    test "returns error for genuinely unknown script code" do
      assert {:error, %Localize.UnknownScriptError{}} =
               Script.display_name(:ZZZZZZ)
    end

    test "falls back to default locale when fallback is true" do
      assert {:ok, _name} = Script.display_name(:Latn, locale: :de, fallback: true)
    end

    test "returns an error tuple on invalid style" do
      assert {:error, %Localize.InvalidValueError{value: :invalid}} =
               Script.display_name(:Latn, style: :invalid)
    end

    test "display_name! raises on invalid style" do
      assert_raise Localize.InvalidValueError, fn ->
        Script.display_name!(:Latn, style: :invalid)
      end
    end
  end

  describe "display_name!/2" do
    test "returns name on success" do
      assert "Latin" = Script.display_name!(:Latn)
      assert "Simplified Han" = Script.display_name!(:Hans, style: :stand_alone)
    end

    test "raises on unknown script" do
      assert_raise Localize.UnknownScriptError, fn ->
        Script.display_name!(:ZZZZZZ)
      end
    end
  end

  describe "scripts_for/1" do
    test "returns sorted list of script codes" do
      assert {:ok, codes} = Script.scripts_for()
      assert is_list(codes)
      assert :Latn in codes
      assert :Cyrl in codes
      assert :Arab in codes
    end

    test "returns scripts for a specific locale" do
      assert {:ok, codes} = Script.scripts_for(locale: :de)
      assert :Latn in codes
    end
  end

  describe "script_names_for/1" do
    test "returns map of script codes to name maps" do
      assert {:ok, scripts} = Script.script_names_for()
      assert %{standard: "Latin"} = scripts[:Latn]
      assert %{standard: "Simplified", stand_alone: "Simplified Han"} = scripts[:Hans]
    end
  end

  # Regression: `display_name/2` used to atomise binary script codes
  # before checking the validity set, so unknown binaries grew the
  # atom table. Atomisation is now gated on `Helpers.existing_atom/1`.
  describe "atom-table bound on unknown binary input" do
    test "display_name does not create an atom for unknown script code" do
      bogus = "ZZZ_script_#{System.unique_integer([:positive])}"
      assert {:error, %Localize.UnknownScriptError{}} = Script.display_name(bogus)
      assert nil == Localize.Utils.Helpers.existing_atom(bogus)
    end
  end

  describe "fallback option" do
    test "fallback: true resolves through the default locale" do
      assert {:error, %Localize.UnknownScriptError{script: :Dupl}} =
               Script.display_name(:Dupl, locale: "agq")

      assert Script.display_name(:Dupl, locale: "agq", fallback: true) ==
               {:ok, "Duployan shorthand"}
    end

    test "a non-boolean fallback is an invalid value" do
      assert {:error, %Localize.InvalidValueError{value: "yes", expected: :fallback}} =
               Script.display_name(:Latn, fallback: "yes")
    end
  end

  describe "deprecated wrappers" do
    # Deprecated names called via apply/3 to avoid the deprecation warning.
    test "available_scripts/1 delegates to scripts_for/1" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert {:ok, scripts} = apply(Script, :available_scripts, [])
      assert :Latn in scripts
    end

    test "known_scripts/1 delegates to script_names_for/1" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert {:ok, names} = apply(Script, :known_scripts, [])
      assert is_map(names)
    end
  end
end
