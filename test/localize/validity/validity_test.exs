defmodule Localize.ValidityTest do
  use ExUnit.Case, async: true

  alias Localize.Validity

  describe "partition/1" do
    test "separates range codes from simple codes" do
      assert Validity.partition(["aa", "qaa~z", "bb"]) == {["qaa~z"], ["bb", "aa"]}
    end

    test "returns empty lists for an empty input" do
      assert Validity.partition([]) == {[], []}
    end

    test "handles input with only simple codes" do
      assert Validity.partition(["en", "fr"]) == {[], ["fr", "en"]}
    end

    test "handles input with only ranges" do
      assert Validity.partition(["qaa~z"]) == {["qaa~z"], []}
    end
  end

  describe "range_from/1" do
    test "splits a range into base, start and end codepoints" do
      assert Validity.range_from("qaa~z") == {"qa", ?a, ?z}
    end

    test "handles a capitalized script range" do
      assert Validity.range_from("Qaaa~x") == {"Qaa", ?a, ?x}
    end
  end

  describe "all_valid/1" do
    test "includes simple script codes" do
      assert "Latn" in Validity.all_valid(:scripts)
    end

    test "expands ranges to include private use scripts" do
      all_scripts = Validity.all_valid(:scripts)
      assert "Qaaa" in all_scripts
      assert "Qabx" in all_scripts
    end

    test "includes reserved language codes from ranges" do
      assert "qaa" in Validity.all_valid(:languages)
      assert "en" in Validity.all_valid(:languages)
    end

    test "includes deprecated unit codes" do
      all_units = Validity.all_valid(:units)
      assert "g_force" in all_units
      assert "inch_hg" in all_units
    end
  end

  describe "known/1" do
    test "excludes private use scripts" do
      known_scripts = Validity.known(:scripts)
      assert "Latn" in known_scripts
      refute "Qaaa" in known_scripts
    end

    test "excludes reserved language codes" do
      known_languages = Validity.known(:languages)
      assert "en" in known_languages
      refute "qaa" in known_languages
    end

    test "excludes deprecated variants" do
      known_variants = Validity.known(:variants)
      assert "1901" in known_variants
      refute "heploc" in known_variants
    end

    test "excludes deprecated units" do
      known_units = Validity.known(:units)
      assert "g_force" in known_units
      refute "inch_hg" in known_units
    end

    test "is a subset of all_valid for the same type" do
      known = MapSet.new(Validity.known(:variants))
      all_valid = MapSet.new(Validity.all_valid(:variants))
      assert MapSet.subset?(known, all_valid)
    end
  end
end
