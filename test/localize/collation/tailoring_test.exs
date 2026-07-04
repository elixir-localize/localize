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

    test "parses star syntax with a positional anchor" do
      ops = Localize.Collation.Tailoring.parse_rules("&[last regular]<*abc")

      assert [
               {:reset_special, _},
               {:primary, ~c"a"},
               {:primary, ~c"b"},
               {:primary, ~c"c"}
             ] = ops
    end

    test "parses secondary and tertiary star syntax" do
      assert [{:reset, ~c"a"}, {:secondary, ~c"x"}, {:secondary, ~c"y"}] =
               Localize.Collation.Tailoring.parse_rules("&a<<*xy")

      assert [{:reset, ~c"a"}, {:tertiary, ~c"x"}, {:tertiary, ~c"y"}] =
               Localize.Collation.Tailoring.parse_rules("&a<<<*xy")
    end

    test "parses identical (=) rules" do
      assert [{:reset, ~c"a"}, {:identical, ~c"b"}] =
               Localize.Collation.Tailoring.parse_rules("&a=b")
    end

    test "parses expansion rules with slash syntax" do
      assert [{:reset, ~c"x"}, {:primary, ~c"y", ~c"e"}] =
               Localize.Collation.Tailoring.parse_rules("&x<y/e")
    end

    test "parses before resets at levels 2 and 3" do
      assert [{:reset_before, 2, ~c"a"}, {:secondary, _}] =
               Localize.Collation.Tailoring.parse_rules("&[before 2]a<<x")

      assert [{:reset_before, 3, ~c"a"}, {:tertiary, _}] =
               Localize.Collation.Tailoring.parse_rules("&[before 3]a<<<x")
    end

    test "parses strength option directives" do
      assert [{:option, :strength, :primary}] =
               Localize.Collation.Tailoring.parse_rules("[strength 1]")

      assert [{:option, :strength, :secondary}] =
               Localize.Collation.Tailoring.parse_rules("[strength 2]")

      assert [{:option, :strength, :quaternary}] =
               Localize.Collation.Tailoring.parse_rules("[strength 4]")

      assert [] = Localize.Collation.Tailoring.parse_rules("[strength 9]")
    end

    test "parses caseFirst variants" do
      assert [{:option, :case_first, :lower}] =
               Localize.Collation.Tailoring.parse_rules("[caseFirst lower]")

      assert [{:option, :case_first, false}] =
               Localize.Collation.Tailoring.parse_rules("[caseFirst off]")

      assert [] = Localize.Collation.Tailoring.parse_rules("[caseFirst sideways]")
    end

    test "parses the remaining boolean option directives" do
      assert [{:option, :case_level, true}] =
               Localize.Collation.Tailoring.parse_rules("[caseLevel on]")

      assert [{:option, :backwards, true}] =
               Localize.Collation.Tailoring.parse_rules("[backwards 2]")

      assert [{:option, :alternate, :shifted}] =
               Localize.Collation.Tailoring.parse_rules("[alternate shifted]")

      assert [{:option, :normalization, true}] =
               Localize.Collation.Tailoring.parse_rules("[normalization on]")
    end

    test "parses reorder option directives" do
      assert [{:option, :reorder, [:Grek, :latn]}] =
               Localize.Collation.Tailoring.parse_rules("[reorder Grek latn]")
    end

    test "parses suppressContractions with ranges and escapes" do
      assert [{:option, :suppress_contractions, ~c"abxyz"}] =
               Localize.Collation.Tailoring.parse_rules("[suppressContractions [ab x-z]]")

      assert [{:option, :suppress_contractions, [0x0041]}] =
               Localize.Collation.Tailoring.parse_rules("[suppressContractions [\\u0041]]")
    end

    test "malformed suppressContractions yields an empty character list" do
      assert [{:option, :suppress_contractions, []}] =
               Localize.Collation.Tailoring.parse_rules("[suppressContractions")
    end

    test "strips full-line and inline comments" do
      rules = """
      # a full-line comment
      &N<ñ # an inline comment
      """

      assert [{:reset, ~c"N"}, {:primary, [?n, 771]}] =
               Localize.Collation.Tailoring.parse_rules(rules)
    end

    test "joins continuation lines onto the previous rule" do
      rules = "&a<b\n<c"
      ops = Localize.Collation.Tailoring.parse_rules(rules)

      assert [{:reset, ~c"a"}, {:primary, ~c"b"}, {:primary, ~c"c"}] = ops
    end

    test "unknown directives produce no operations" do
      assert [] = Localize.Collation.Tailoring.parse_rules("[import und-u-co-search]")
    end

    test "a reset with no following rules produces only the reset" do
      assert [{:reset, ~c"a"}] = Localize.Collation.Tailoring.parse_rules("&a")
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

    test "walks the parent chain to find a tailoring" do
      # nb (Norwegian Bokmål) has no tailoring of its own; its CLDR
      # parent chain reaches no, which does.
      assert {overlay, _options} = Localize.Collation.Tailoring.get_tailoring("nb", :standard)
      assert is_map(overlay)

      assert {parent_overlay, _} = Localize.Collation.Tailoring.get_tailoring("no", :standard)
      assert overlay == parent_overlay
    end

    test "falls back to the und tailoring for the search type" do
      assert {overlay, _options} = Localize.Collation.Tailoring.get_tailoring("en", :search)
      assert is_map(overlay)
      assert map_size(overlay) > 0
    end

    test "returns nil for a language with no tailoring anywhere in the chain" do
      assert nil == Localize.Collation.Tailoring.get_tailoring("zz", :standard)
    end

    test "returns nil for an invalid language identifier" do
      assert nil == Localize.Collation.Tailoring.get_tailoring("not a language!", :standard)
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
