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

    test "raises on invalid style" do
      assert_raise Localize.InvalidValueError, fn ->
        Script.display_name(:Latn, style: :invalid)
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

  describe "available_scripts/1" do
    test "returns sorted list of script codes" do
      assert {:ok, codes} = Script.available_scripts()
      assert is_list(codes)
      assert :Latn in codes
      assert :Cyrl in codes
      assert :Arab in codes
    end

    test "returns scripts for a specific locale" do
      assert {:ok, codes} = Script.available_scripts(locale: :de)
      assert :Latn in codes
    end
  end

  describe "known_scripts/1" do
    test "returns map of script codes to name maps" do
      assert {:ok, scripts} = Script.known_scripts()
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
end
