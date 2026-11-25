defmodule Localize.Collation.TailoredLookupTest do
  # A tailored locale's overlay is cached with a contraction index, so a
  # longest-match lookup reads one entry rather than every key of the
  # overlay, and with the mapping of its `[reorder]` codes, so a sort key
  # does not build it again. Numeric collation reads the tailoring too.
  use ExUnit.Case, async: true

  alias Localize.Collation
  alias Localize.Collation.{Options, Table}

  setup_all do
    Collation.ensure_loaded()
    :ok
  end

  describe "the contraction index" do
    test "gives each first code point the length of the longest key it begins" do
      overlay = %{
        ?a => [],
        {?c, ?s} => [],
        {?d, ?z} => [],
        {?d, ?z, ?s} => [],
        {} => []
      }

      assert Table.contraction_index(overlay) == %{?a => 1, ?c => 2, ?d => 3}
    end

    test "finds the same longest match as one built for the call" do
      %Options{tailoring: overlay, contractions: contractions} = Options.from_locale("hu")

      for word <- ["dzsungel", "ccs", "gyógy", "abc", "ty"] do
        codepoints = String.to_charlist(:unicode.characters_to_nfd_binary(word))

        assert Table.longest_match_with_overlay(codepoints, overlay, contractions) ==
                 Table.longest_match_with_overlay(codepoints, overlay)
      end
    end
  end

  describe "options resolved for a tailored locale" do
    test "carry the contraction index and the tailoring's reorder mapping" do
      for locale <- ["ja", "zh", "zh-Hant"] do
        options = Options.from_locale(locale)

        assert {locale, is_map(options.contractions)} == {locale, true}
        assert {locale, is_function(options.reorder_mapping, 1)} == {locale, true}
      end
    end

    test "give the same keys as options built by hand without them" do
      for locale <- ["ja", "zh-Hant", "hu"], word <- ["日本", "北京", "ccs", "abc"] do
        resolved = Options.from_locale(locale)
        by_hand = %{resolved | contractions: nil, reorder_mapping: nil}

        assert {locale, word, Collation.sort_key(word, by_hand)} ==
                 {locale, word, Collation.sort_key(word, resolved)}
      end
    end
  end

  describe "the tailoring cache" do
    test "holds one copy of a tailoring for every locale that inherits it" do
      # zh-Hant, zh-Hant-HK and yue take zh's stroke rules; caching a copy
      # for each ran the VM out of literal memory.
      # The call that builds an entry returns the copy it built; later
      # calls read the one kept in `:persistent_term`.
      stroke = fn locale ->
        {:ok, tag} = Localize.validate_locale(locale)
        {overlay, _options} = Localize.Collation.Tailoring.get_tailoring(tag, :stroke)
        overlay
      end

      _warm = stroke.("zh-Hant")
      overlays = Enum.map(["zh-Hant", "zh-Hant-HK", "yue"], stroke)

      [first | rest] = overlays
      assert Enum.all?(rest, &:erts_debug.same(&1, first))
    end

    test "shares the standard copy for a preference the type has no form for" do
      {:ok, tag} = Localize.validate_locale("es")
      _warm = Localize.Collation.Tailoring.get_tailoring(tag, :standard, :standard)
      {standard, _} = Localize.Collation.Tailoring.get_tailoring(tag, :standard, :standard)
      {short, _} = Localize.Collation.Tailoring.get_tailoring(tag, :standard, :short)

      assert :erts_debug.same(standard, short)
    end
  end

  describe "numeric collation" do
    test "keeps the locale's tailoring" do
      # Swedish sorts å and ö after z; ICU gives this order.
      assert Collation.sort(["å2", "a10", "å10", "z1", "a2", "ö3"], locale: "sv", numeric: true) ==
               ["a2", "a10", "z1", "å2", "å10", "ö3"]
    end
  end
end
