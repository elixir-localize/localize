defmodule Localize.Collation.TailoringTest do
  use ExUnit.Case, async: true

  doctest Localize.Collation.Tailoring
  doctest Localize.Collation.Tailoring.LocaleDefaults

  # ===================================================================
  # Rule Parser Unit Tests
  # ===================================================================

  describe "parse_rules/1" do
    test "parses simple primary tailoring" do
      ops = Localize.Collation.Tailoring.parse_rules("&N<ñ<<<Ñ")
      # Targets are NFD: ñ = n(110) + combining tilde(771)
      assert [{:reset, [?N]}, {:primary, [110, 771]}, {:tertiary, [78, 771]}] = ops
    end

    test "parses secondary tailoring" do
      ops = Localize.Collation.Tailoring.parse_rules("&AE<<ä<<<Ä")
      # Targets are NFD: ä = a(97) + combining diaeresis(776)
      assert [{:reset, [?A, ?E]}, {:secondary, [97, 776]}, {:tertiary, [65, 776]}] = ops
    end

    test "parses multi-character contraction" do
      ops = Localize.Collation.Tailoring.parse_rules("&C<ch<<<Ch<<<CH")

      assert [
               {:reset, [?C]},
               {:primary, [?c, ?h]},
               {:tertiary, [?C, ?h]},
               {:tertiary, [?C, ?H]}
             ] = ops
    end

    test "parses option override" do
      ops = Localize.Collation.Tailoring.parse_rules("[caseFirst upper]")
      assert [{:option, :case_first, :upper}] = ops
    end

    test "parses before reset" do
      ops = Localize.Collation.Tailoring.parse_rules("&[before 1]ǀ<æ<<<Æ")

      assert [
               {:reset_before, 1, [?ǀ]},
               {:primary, [?æ]},
               {:tertiary, [?Æ]}
             ] = ops
    end

    test "parses multiple lines" do
      rules = "&N<ñ<<<Ñ\n&C<ch<<<Ch<<<CH"
      ops = Localize.Collation.Tailoring.parse_rules(rules)
      assert length(ops) == 7
    end
  end

  # ===================================================================
  # Tailoring overlay unit tests
  # ===================================================================

  describe "get_tailoring/2" do
    setup do
      Localize.Collation.ensure_loaded()
      :ok
    end

    test "returns overlay for Spanish standard" do
      {overlay, options} = Localize.Collation.Tailoring.get_tailoring("es", :standard)
      assert is_map(overlay)
      assert map_size(overlay) > 0
      assert options == []
    end

    test "returns overlay with option overrides for Danish" do
      {overlay, options} = Localize.Collation.Tailoring.get_tailoring("da", :standard)
      assert is_map(overlay)
      assert options == [case_first: :upper]
    end

    test "returns overlay for German phonebook" do
      {overlay, options} = Localize.Collation.Tailoring.get_tailoring("de", :phonebook)
      assert is_map(overlay)
      assert options == []
      # Overlay keys are NFD: ä = {97, 776}, ö = {111, 776}, ü = {117, 776}
      assert Map.has_key?(overlay, {97, 776})
      assert Map.has_key?(overlay, {111, 776})
      assert Map.has_key?(overlay, {117, 776})
    end

    test "returns nil for unsupported locale" do
      assert nil == Localize.Collation.Tailoring.get_tailoring("en", :standard)
    end
  end

  describe "supported_locales/0" do
    test "lists available tailorings" do
      locales = Localize.Collation.Tailoring.supported_locales()
      assert {"es", :standard} in locales
      assert {"de", :phonebook} in locales
      assert {"sv", :standard} in locales
    end
  end
end
