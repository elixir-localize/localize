defmodule Localize.SupplementalDataTest do
  use ExUnit.Case, async: true

  alias Localize.SupplementalData

  describe "likely_subtags/0" do
    test "returns a map with string keys" do
      subtags = SupplementalData.likely_subtags()
      assert is_map(subtags)
      assert Map.has_key?(subtags, "en")
    end
  end

  describe "aliases/0" do
    test "returns a map with alias categories" do
      aliases = SupplementalData.aliases()
      assert is_map(aliases)
      assert Map.has_key?(aliases, :language)
    end
  end

  describe "language_matching/0" do
    test "returns a map with matching data" do
      matching = SupplementalData.language_matching()
      assert is_map(matching)
    end
  end

  describe "all_locale_ids/0" do
    test "returns a list of atoms" do
      ids = SupplementalData.all_locale_ids()
      assert is_list(ids)
      assert :en in ids
    end
  end

  describe "validity/1" do
    test "returns validity data for each type" do
      for type <- [:u, :t, :languages, :scripts, :territories, :variants, :subdivisions, :units] do
        data = SupplementalData.validity(type)
        assert is_map(data), "Expected map for validity type #{type}"
      end
    end
  end

  describe "parent_locales/0" do
    test "returns a map of parent locale overrides" do
      parents = SupplementalData.parent_locales()
      assert is_map(parents)
    end
  end

  describe "timezones/0" do
    test "returns a map of timezone data" do
      timezones = SupplementalData.timezones()
      assert is_map(timezones)
    end
  end

  describe "unicode_script_to_subtag_mapping/0" do
    test "returns a map" do
      mapping = SupplementalData.unicode_script_to_subtag_mapping()
      assert is_map(mapping)
    end
  end

  describe "plural_rules/1" do
    test "returns cardinal plural rules" do
      rules = SupplementalData.plural_rules(:cardinal)
      assert is_map(rules)
    end

    test "returns ordinal plural rules" do
      rules = SupplementalData.plural_rules(:ordinal)
      assert is_map(rules)
    end
  end

  describe "plural_ranges/0" do
    test "returns a list of range data" do
      ranges = SupplementalData.plural_ranges()
      assert is_list(ranges)
    end
  end

  describe "currency_codes/0" do
    test "returns a sorted list of currency code atoms" do
      codes = SupplementalData.currency_codes()
      assert is_list(codes)
      assert :USD in codes
    end
  end

  describe "territory_currencies/0" do
    test "returns a map of territory to currency data" do
      currencies = SupplementalData.territory_currencies()
      assert is_map(currencies)
    end
  end
end
