defmodule Localize.TerritoryTest do
  use ExUnit.Case, async: true

  alias Localize.Territory

  doctest Localize.Territory

  # ── known_styles / known_territories ──────────────────────────

  test "known_territories/0 returns all CLDR territory codes" do
    territories = Territory.known_territories()
    assert :US in territories
    assert :EU in territories
    assert :"001" in territories
  end

  test "deprecated available_styles/0 delegates to known_styles/0" do
    assert apply(Territory, :available_styles, []) == Territory.known_styles()
  end

  test "known_styles/0 returns the CLDR style set" do
    assert [:short, :standard, :variant] == Territory.known_styles()
  end

  # ── display_name ──────────────────────────────────────────────

  describe "display_name/2" do
    test "returns localized territory name with default style" do
      assert {:ok, "United States"} == Territory.display_name(:US)
      assert {:ok, "United Kingdom"} == Territory.display_name(:GB)
    end

    test "accepts string territory codes" do
      assert {:ok, "United States"} == Territory.display_name("US")
    end

    test "returns short style" do
      assert {:ok, "US"} == Territory.display_name(:US, style: :short)
      assert {:ok, "UK"} == Territory.display_name(:GB, style: :short)
    end

    test "returns name in another locale" do
      assert {:ok, "Reino Unido"} == Territory.display_name(:GB, locale: :pt)
      assert {:ok, "Estados Unidos"} == Territory.display_name(:US, locale: :pt)
    end

    test "returns error for unknown territory" do
      assert {:error, %Localize.UnknownTerritoryError{}} =
               Territory.display_name(:ZZZZ)
    end

    test "returns error for unknown style" do
      assert {:error, %Localize.UnknownStyleError{}} =
               Territory.display_name(:US, style: :zzz)
    end
  end

  describe "display_name!/2" do
    test "returns name on success" do
      assert "United States" == Territory.display_name!(:US)
      assert "UK" == Territory.display_name!(:GB, style: :short)
      assert "Reino Unido" == Territory.display_name!(:GB, locale: :pt)
    end

    test "raises on unknown territory" do
      assert_raise Localize.UnknownTerritoryError, fn ->
        Territory.display_name!(:ZZZZ)
      end
    end

    test "raises on unknown style" do
      assert_raise Localize.UnknownStyleError, fn ->
        Territory.display_name!(:US, style: :zzz)
      end
    end
  end

  # ── translate_territory ───────────────────────────────────────

  describe "translate_territory/3" do
    test "translates from one locale to another" do
      assert {:ok, "Reino Unido"} ==
               Territory.translate_territory("United Kingdom", :en, to: :pt)

      assert {:ok, "United Kingdom"} ==
               Territory.translate_territory("Reino Unido", :pt, to: :en)
    end

    test "translates short names" do
      assert {:ok, "Estados Unidos"} ==
               Territory.translate_territory("US", :en, to: :pt)
    end

    test "returns error for unknown territory name" do
      assert {:error, %Localize.UnknownTerritoryError{}} =
               Territory.translate_territory("Unknown Country", :en, to: :pt)
    end
  end

  describe "translate_territory!/3" do
    test "returns translated name on success" do
      assert "Reino Unido" ==
               Territory.translate_territory!("United Kingdom", :en, to: :pt)

      assert "United Kingdom" ==
               Territory.translate_territory!("Reino Unido", :pt, to: :en)
    end

    test "raises on unknown territory name" do
      assert_raise Localize.UnknownTerritoryError, fn ->
        Territory.translate_territory!("Unknown Country", :en, to: :pt)
      end
    end
  end

  # ── to_territory_code ─────────────────────────────────────────

  describe "to_territory_code/2" do
    test "finds territory code from display name" do
      assert {:ok, :GB} == Territory.to_territory_code("United Kingdom", :en)
      assert {:ok, :GB} == Territory.to_territory_code("Reino Unido", :pt)
      assert {:ok, :US} == Territory.to_territory_code("United States", :en)
      assert {:ok, :US} == Territory.to_territory_code("Estados Unidos", :pt)
    end

    test "finds territory code from short name" do
      assert {:ok, :GB} == Territory.to_territory_code("UK", :en)
    end

    test "returns error for unknown name" do
      assert {:error, %Localize.UnknownTerritoryError{}} =
               Territory.to_territory_code("Unknown Country", :en)
    end
  end

  describe "to_territory_code!/2" do
    test "returns code on success" do
      assert :GB == Territory.to_territory_code!("United Kingdom", :en)
      assert :GB == Territory.to_territory_code!("Reino Unido", :pt)
    end

    test "raises on unknown name" do
      assert_raise Localize.UnknownTerritoryError, fn ->
        Territory.to_territory_code!("Unknown Country", :en)
      end
    end
  end

  # ── parent ────────────────────────────────────────────────────

  describe "parent/1" do
    test "returns parent territories" do
      assert {:ok, parents} = Territory.parent(:GB)
      assert :"154" in parents
      assert :UN in parents
    end

    test "returns parents for FR including EU and EZ" do
      assert {:ok, parents} = Territory.parent(:FR)
      assert :"155" in parents
      assert :EU in parents
      assert :EZ in parents
      assert :UN in parents
    end

    test "returns error for unknown territory" do
      assert {:error, %Localize.UnknownTerritoryError{}} = Territory.parent(:ZZZZ)
    end

    test "returns error for territory with no parents" do
      assert {:error, %Localize.NoParentTerritoryError{territory: :"001"}} =
               Territory.parent(:"001")
    end
  end

  describe "parent!/1" do
    test "returns parents on success" do
      parents = Territory.parent!(:DK)
      assert :"154" in parents
      assert :UN in parents
    end

    test "GB is no longer in EU" do
      parents = Territory.parent!(:GB)
      refute :EU in parents
    end

    test "raises on unknown territory" do
      assert_raise Localize.UnknownTerritoryError, fn ->
        Territory.parent!(:ZZZZ)
      end
    end
  end

  # ── children ──────────────────────────────────────────────────

  describe "children/1" do
    test "returns child territories" do
      assert {:ok, children} = Territory.children(:EU)
      assert :FR in children
      assert :DE in children
      assert :DK in children
    end

    test "returns error for territory with no children" do
      assert {:error, %Localize.UnknownTerritoryError{}} = Territory.children(:DK)
    end

    test "returns error for unknown territory" do
      assert {:error, %Localize.UnknownTerritoryError{}} = Territory.children(:ZZZZ)
    end
  end

  describe "children!/1" do
    test "returns children on success" do
      children = Territory.children!(:EU)
      assert :FR in children
    end

    test "raises on territory with no children" do
      assert_raise Localize.UnknownTerritoryError, fn ->
        Territory.children!(:DK)
      end
    end
  end

  # ── contains? ─────────────────────────────────────────────────

  describe "contains?/2" do
    test "returns true when parent contains child" do
      assert Territory.contains?(:EU, :DK)
      assert Territory.contains?(:"001", :"019")
    end

    test "returns false when not a containment relationship" do
      refute Territory.contains?(:DK, :EU)
      refute Territory.contains?(:US, :GB)
    end

    test "string and atom territories are equivalent" do
      assert Territory.contains?("EU", "DK") == Territory.contains?(:EU, :DK)
      assert Territory.contains?("eu", "dk")
      refute Territory.contains?("DK", "EU")
    end

    test "returns false for an invalid territory instead of raising" do
      refute Territory.contains?("not-a-territory", :DK)
      refute Territory.contains?(:EU, "not-a-territory")
    end
  end

  # ── info ──────────────────────────────────────────────────────

  describe "info/1" do
    test "returns territory metadata" do
      assert {:ok, info} = Territory.info(:US)
      assert info.gdp == 24_660_000_000_000
      assert info.population == 341_963_000
      assert info.literacy_percent == 99
      assert is_list(info.currency)
      assert is_map(info.measurement_system)
      assert is_map(info.language_population)
    end

    test "accepts string territory codes" do
      assert {:ok, info} = Territory.info("US")
      assert info.gdp == 24_660_000_000_000
    end

    test "returns error for unknown territory" do
      assert {:error, %Localize.UnknownTerritoryError{}} = Territory.info(:ZZZZ)
    end

    test "returns error for region without info" do
      assert {:error, %Localize.UnknownTerritoryError{}} = Territory.info(:"155")
    end
  end

  describe "info!/1" do
    test "returns info on success" do
      info = Territory.info!(:US)
      assert info.gdp == 24_660_000_000_000
    end

    test "raises on unknown territory" do
      assert_raise Localize.UnknownTerritoryError, fn ->
        Territory.info!(:ZZZZ)
      end
    end
  end

  # ── territory_codes ───────────────────────────────────────────

  describe "territory_codes/1" do
    test "returns map of territory codes with alpha3 and numeric" do
      codes = Territory.territory_codes()
      assert %{alpha3: "USA", numeric: "840"} = Map.get(codes, :US)
      assert %{alpha3: "GBR", numeric: "826"} = Map.get(codes, :GB)
    end

    test "iso_3166: true filters out CLDR-only and exceptional codes" do
      codes = Territory.territory_codes(iso_3166: true)
      assert Map.has_key?(codes, :US)
      assert Map.has_key?(codes, :GB)
      assert Map.has_key?(codes, :DE)
      # CLDR-only / user-assigned codes are excluded.
      refute Map.has_key?(codes, :IC)
      refute Map.has_key?(codes, :EA)
      refute Map.has_key?(codes, :XK)
      # Exceptional reservations are excluded.
      refute Map.has_key?(codes, :AC)
      refute Map.has_key?(codes, :DG)
      refute Map.has_key?(codes, :TA)
    end

    test "the ISO 3166 subset is smaller than the full territory map" do
      assert map_size(Territory.territory_codes(iso_3166: true)) <
               map_size(Territory.territory_codes())
    end
  end

  # ── to_currency_code ──────────────────────────────────────────

  describe "to_currency_code/1" do
    test "returns current currency for territory" do
      assert {:ok, :USD} == Territory.to_currency_code(:US)
      assert {:ok, :GBP} == Territory.to_currency_code(:GB)
    end

    test "accepts string territory codes" do
      assert {:ok, :DKK} == Territory.to_currency_code("DK")
    end

    test "returns error for unknown territory" do
      assert {:error, %Localize.UnknownTerritoryError{}} =
               Territory.to_currency_code(:ZZZZ)
    end
  end

  describe "to_currency_code!/1" do
    test "returns currency code on success" do
      assert :USD == Territory.to_currency_code!(:US)
      assert :GBP == Territory.to_currency_code!(:GB)
    end

    test "raises on unknown territory" do
      assert_raise Localize.UnknownTerritoryError, fn ->
        Territory.to_currency_code!(:ZZZZ)
      end
    end
  end

  # ── to_currency_codes ─────────────────────────────────────────

  describe "to_currency_codes/1" do
    test "returns active currency codes sorted by start date" do
      assert {:ok, [:USD]} == Territory.to_currency_codes(:US)
    end

    test "returns error for unknown territory" do
      assert {:error, %Localize.UnknownTerritoryError{}} =
               Territory.to_currency_codes(:ZZZZ)
    end
  end

  describe "to_currency_codes!/1" do
    test "returns codes on success" do
      assert [:USD] == Territory.to_currency_codes!(:US)
    end

    test "raises on unknown territory" do
      assert_raise Localize.UnknownTerritoryError, fn ->
        Territory.to_currency_codes!(:ZZZZ)
      end
    end
  end

  # ── individual_territories ────────────────────────────────────

  describe "individual_territories/0" do
    test "returns sorted list of individual territory codes" do
      codes = Territory.individual_territories()
      assert :US in codes
      assert :GB in codes
      assert :FR in codes
    end

    test "does not include region codes" do
      codes = Territory.individual_territories()
      refute :"001" in codes
      refute :"019" in codes
    end
  end

  # ── normalize_name ────────────────────────────────────────────

  describe "normalize_name/1" do
    test "downcases and normalizes" do
      assert "united states" == Territory.normalize_name("United States")
      assert "congo - brazzaville" == Territory.normalize_name("Congo - Brazzaville")
    end

    test "removes & and ." do
      assert "trinidadtobago" == Territory.normalize_name("Trinidad & Tobago")
      assert "st helena" == Territory.normalize_name("St. Helena")
    end
  end
end
