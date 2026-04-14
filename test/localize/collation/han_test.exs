defmodule Localize.Collation.HanTest do
  use ExUnit.Case

  doctest Localize.Collation.Han

  alias Localize.Collation

  setup_all do
    Localize.Collation.ensure_loaded()
    :ok
  end

  describe "Han character recognition" do
    test "CJK Unified Ideographs are recognized as unified ideographs" do
      # 一 (U+4E00) - "one", radical 1
      assert Localize.Collation.ImplicitWeights.unified_ideograph?(0x4E00)
      # 龥 (U+9FA5) - last common CJK character
      assert Localize.Collation.ImplicitWeights.unified_ideograph?(0x9FA5)
    end
  end

  describe "block_index/1" do
    test "core CJK unified block" do
      assert Localize.Collation.Han.block_index(0x4E00) == 0
      assert Localize.Collation.Han.block_index(0x9FFF) == 0
    end

    test "extension A" do
      assert Localize.Collation.Han.block_index(0x3400) == 1
    end

    test "extension B" do
      assert Localize.Collation.Han.block_index(0x20000) == 2
    end
  end

  describe "collation_elements/1" do
    test "returns collation elements for a loaded core CJK character" do
      assert [_ce1, _ce2] = Localize.Collation.Han.collation_elements(0x4E00)
    end

    test "returns collation elements for a loaded Ext-A character" do
      assert [_ce1, _ce2] = Localize.Collation.Han.collation_elements(0x3400)
    end

    test "returns nil for a non-Han codepoint" do
      assert Localize.Collation.Han.collation_elements(?A) == nil
    end
  end

  describe "radical-stroke ordering vs codepoint ordering" do
    # These are the differential tests — they verify that radical-stroke
    # ordering actually produces DIFFERENT output from codepoint order
    # for pairs where the two orderings disagree. Without this, earlier
    # versions of the Han module were trivially satisfied by codepoint
    # ordering and the feature was broken without any test failing.

    test "Ext-A character sorts AFTER core CJK under radical-stroke ordering" do
      # U+3400 (Ext-A, block 1) has a lower codepoint than U+4E00 (core, block 0).
      # Codepoint order puts Ext-A first; radical-stroke puts core first
      # because block 0 < block 1 in the compute_key encoding.
      core = <<0x4E00::utf8>>
      ext_a = <<0x3400::utf8>>

      assert Collation.compare(ext_a, core, locale: :root) == :lt
      assert Collation.compare(ext_a, core, locale: "zh-u-co-unihan") == :gt
      assert Collation.sort([ext_a, core], locale: "zh-u-co-unihan") == [core, ext_a]
    end

    test "root collation of Han characters is unchanged (UCA implicit weights)" do
      chars = 0x4E00..0x4E10 |> Enum.map(&<<&1::utf8>>)
      # Under root, Han characters sort by codepoint (implicit weights).
      # This invariant must hold because CLDR's reference root collation
      # does not use radical-stroke ordering.
      assert Collation.sort(chars, locale: :root) == chars
    end
  end

  describe "zh-u-co-unihan locale" do
    test "sorts core CJK characters using radical-stroke ordering" do
      # Within radical 1, member list order matches character position:
      # 一 (rank 0) < 丁 (rank 2) — agrees with codepoint too, but
      # confirms radical-stroke is active.
      assert Collation.compare("一", "丁", locale: "zh-u-co-unihan") == :lt
    end

    test "Ext-A ideographs sort after core ideographs of the same radical" do
      # Radical 1 contains both core (U+4E00..) and Ext-A (U+3400..) chars.
      # Radical-stroke puts core block first regardless of codepoint.
      assert Collation.compare("一", <<0x3400::utf8>>, locale: "zh-u-co-unihan") == :lt
    end

    test "compare is transitive for multiple characters" do
      # A < B and B < C should imply A < C.
      chars = ["一", "丁", <<0x3400::utf8>>]

      [a, b, c] = chars

      ab = Collation.compare(a, b, locale: "zh-u-co-unihan")
      bc = Collation.compare(b, c, locale: "zh-u-co-unihan")
      ac = Collation.compare(a, c, locale: "zh-u-co-unihan")

      assert ab == :lt
      assert bc == :lt
      assert ac == :lt
    end

    test "unihan and root produce different output for block-inverted pairs" do
      pair = [<<0x3400::utf8>>, <<0x4E00::utf8>>]
      refute Collation.sort(pair, locale: "zh-u-co-unihan") == Collation.sort(pair, locale: :root)
    end
  end
end
