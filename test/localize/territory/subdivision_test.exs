defmodule Localize.Territory.SubdivisionTest do
  use ExUnit.Case, async: true

  alias Localize.Territory.Subdivision

  doctest Localize.Territory.Subdivision

  describe "display_name/2" do
    test "returns localized subdivision name" do
      assert {:ok, "Ontario"} == Subdivision.display_name(:caon, locale: :en)
      assert {:ok, "Cumbria"} == Subdivision.display_name("gbcma", locale: :en)
      assert {:ok, "California"} == Subdivision.display_name("usca", locale: :en)
    end

    test "returns name in another locale" do
      assert {:ok, "Ontário"} == Subdivision.display_name(:caon, locale: :pt)
    end

    test "returns error for unknown subdivision" do
      assert {:error, %Localize.UnknownSubdivisionError{}} =
               Subdivision.display_name(:zzzzz, locale: :en)
    end
  end

  describe "display_name!/2" do
    test "returns name on success" do
      assert "Ontario" == Subdivision.display_name!(:caon, locale: :en)
    end

    test "raises on unknown subdivision" do
      assert_raise Localize.UnknownSubdivisionError, fn ->
        Subdivision.display_name!(:zzzzz, locale: :en)
      end
    end
  end

  describe "known_subdivisions/1" do
    test "returns map of all subdivision code to name pairs for a locale" do
      assert {:ok, subdivisions} = Subdivision.known_subdivisions(locale: :en)
      assert is_map(subdivisions)
      assert Map.get(subdivisions, :caon) == "Ontario"
      assert Map.get(subdivisions, :gbeng) == "England"
    end

    test "returns translations in the requested locale" do
      assert {:ok, subdivisions} = Subdivision.known_subdivisions(locale: :fr)
      assert Map.get(subdivisions, :gbeng) == "Angleterre"
    end
  end

  describe "available_subdivisions/1" do
    test "returns sorted list of subdivision codes for a locale" do
      assert {:ok, codes} = Subdivision.available_subdivisions(locale: :en)
      assert is_list(codes)
      assert :caon in codes
      assert :gbeng in codes
      assert codes == Enum.sort(codes)
    end
  end

  describe "for_territory/1" do
    test "returns subdivisions for a territory atom" do
      assert {:ok, subdivisions} = Subdivision.for_territory(:GB)
      assert :gbeng in subdivisions
      assert :gbsct in subdivisions
    end

    test "returns subdivisions for a territory string" do
      assert {:ok, subdivisions} = Subdivision.for_territory("CA")
      assert :caon in subdivisions
    end

    test "returns subdivisions derived from a LanguageTag" do
      {:ok, tag} = Localize.validate_locale("en-GB")
      assert {:ok, subdivisions} = Subdivision.for_territory(tag)
      assert :gbeng in subdivisions
    end

    test "returns error for unknown territory" do
      assert {:error, %Localize.UnknownTerritoryError{}} =
               Subdivision.for_territory(:NOPE)
    end
  end
end
