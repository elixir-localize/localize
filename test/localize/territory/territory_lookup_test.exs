defmodule Localize.Territory.TerritoryLookupTest do
  use ExUnit.Case, async: true

  alias Localize.Territory

  describe "territory_names_for/1" do
    test "returns localized territory names for a locale" do
      assert {:ok, territories} = Territory.territory_names_for(locale: :en)
      assert territories[:NZ].standard == "New Zealand"
      assert territories[:US].standard == "United States"
    end

    test "returns names in the requested locale" do
      assert {:ok, territories} = Territory.territory_names_for(locale: :de)
      assert territories[:AT] == %{standard: "Österreich"}
    end

    test "returns an error for an invalid locale" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Territory.territory_names_for(locale: "zz-invalid")
    end
  end

  describe "territories_for/1" do
    test "returns a sorted list of territory codes" do
      assert {:ok, codes} = Territory.territories_for(locale: :en)
      assert :US in codes
      assert :"001" in codes
      assert codes == Enum.sort(codes)
    end

    test "returns an error for an invalid locale" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Territory.territories_for(locale: "zz-invalid")
    end
  end
end
