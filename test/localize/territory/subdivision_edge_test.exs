defmodule Localize.Territory.SubdivisionEdgeTest do
  use ExUnit.Case, async: true

  alias Localize.Territory.Subdivision

  describe "display_name/2 code normalization" do
    test "downcases string codes before lookup" do
      assert {:ok, "Ontario"} = Subdivision.display_name("CAON", locale: :en)
      assert {:ok, "Ontario"} = Subdivision.display_name("CaOn", locale: :en)
    end

    test "unknown string codes normalize to nil in the error" do
      # `existing_atom/1` returns nil for unknown binaries, so the
      # error reports the normalized (nil) code rather than the input.
      assert {:error, %Localize.UnknownSubdivisionError{subdivision: nil}} =
               Subdivision.display_name("zzzznotasubdivision", locale: :en)
    end

    test "unknown atom codes are reported in the error" do
      assert {:error, %Localize.UnknownSubdivisionError{subdivision: :zzzzz}} =
               Subdivision.display_name(:zzzzz, locale: :en)
    end

    test "returns the translation for a non-Latin locale" do
      assert {:ok, "オンタリオ州"} = Subdivision.display_name(:caon, locale: :ja)
    end
  end

  describe "display_name/2 locale errors" do
    test "returns an error for an invalid locale" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Subdivision.display_name(:caon, locale: "xx")
    end
  end

  describe "display_name!/2 errors" do
    test "raises for an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Subdivision.display_name!(:caon, locale: "xx")
      end
    end
  end

  describe "subdivision_names_for/1 and subdivisions_for/1 errors" do
    test "subdivision_names_for/1 returns an error for an invalid locale" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Subdivision.subdivision_names_for(locale: "zz-invalid")
    end

    test "subdivisions_for/1 returns an error for an invalid locale" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Subdivision.subdivisions_for(locale: "zz-invalid")
    end
  end

  describe "for_territory/1 input forms" do
    test "accepts a lowercase territory string" do
      assert {:ok, subdivisions} = Subdivision.for_territory("ca")
      assert :caon in subdivisions
    end

    test "derives the territory from a LanguageTag via likely subtags" do
      {:ok, language_tag} = Localize.validate_locale("en-CA")
      assert {:ok, subdivisions} = Subdivision.for_territory(language_tag)
      assert :caon in subdivisions
      assert :cabc in subdivisions
    end

    test "returns an empty list for a territory without subdivisions" do
      assert {:ok, []} = Subdivision.for_territory(:AQ)
    end
  end
end
