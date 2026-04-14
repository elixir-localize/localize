defmodule Localize.Collation.JaTailoringsTest do
  use ExUnit.Case

  alias Localize.Collation

  setup_all do
    Localize.Collation.ensure_loaded()
    :ok
  end

  describe "ja tailoring availability" do
    test "ja/standard produces a substantial overlay" do
      {overlay, opts} = Localize.Collation.Tailoring.get_tailoring("ja", :standard)
      # The Japanese standard tailoring has thousands of entries covering
      # kana ordering, small-kana handling, and script-specific rules.
      assert map_size(overlay) > 5000
      assert Keyword.get(opts, :strength) == :tertiary
      assert Keyword.get(opts, :reorder) |> is_list()
    end

    test "ja/unihan tailoring loads" do
      {overlay, _opts} = Localize.Collation.Tailoring.get_tailoring("ja", :unihan)
      assert map_size(overlay) > 0
    end
  end

  describe "ja-u-co-unihan — radical-stroke ordering" do
    test "applies radical-stroke ordering to Han characters" do
      # 乙 (U+4E59, radical 5, rank 0) vs 丁 (U+4E01, radical 1, rank 2).
      # Radical-stroke: 丁 (rad 1) < 乙 (rad 5), so 乙 > 丁.
      # Codepoint: 丁 (0x4E01) < 乙 (0x4E59).
      # Since both agree on the direction here, ja-unihan gives :gt
      # (matching radical-stroke ordering) — same as zh-unihan.
      assert Collation.compare("乙", "丁", locale: "ja-u-co-unihan") == :gt
      assert Collation.compare("乙", "丁", locale: "zh-u-co-unihan") == :gt
    end

    test "produces Ext-A / core inversion under radical-stroke" do
      # Ext-A (U+3400) codepoint is BEFORE core CJK (U+4E00) numerically,
      # but radical-stroke ordering puts core first (block 0 < block 1).
      core = <<0x4E00::utf8>>
      ext_a = <<0x3400::utf8>>

      assert Collation.compare(ext_a, core, locale: "ja-u-co-unihan") == :gt
      assert Collation.compare(ext_a, core, locale: :root) == :lt
    end
  end

  describe "ja script reorder" do
    test "orders Latin before Kana before Han as CLDR ja specifies" do
      # CLDR ja has [reorder Latn Kana Hani]: Latin comes first, then
      # kana, then kanji.
      chars = ["一", "あ", "a"]
      sorted = Collation.sort(chars, locale: :ja)
      assert sorted == ["a", "あ", "一"]
    end
  end

  describe "ja base tailoring" do
    test "compare output is not all :eq (overlay is active for base locale)" do
      # At minimum, the overlay being applied means comparisons
      # produce the same totals as primary-only codepoint ordering
      # for chars without overrides, but produce DIFFERENT sort
      # keys for chars with overrides (in terms of secondary/tertiary
      # bytes).
      #
      # We demonstrate the overlay is active by checking that at
      # least one pair of entries differs between ja and root sort
      # keys somewhere in the tailoring range.
      {overlay, _} = Localize.Collation.Tailoring.get_tailoring("ja", :standard)
      [some_key | _] = Map.keys(overlay)

      some_char =
        case some_key do
          cp when is_integer(cp) -> <<cp::utf8>>
          cps when is_list(cps) -> IO.iodata_to_binary(Enum.map(cps, &<<&1::utf8>>))
        end

      ja_key = Collation.sort_key(some_char, locale: :ja)
      root_key = Collation.sort_key(some_char, locale: :root)
      refute ja_key == root_key
    end
  end
end
