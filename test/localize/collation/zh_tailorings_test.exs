defmodule Localize.Collation.ZhTailoringsTest do
  use ExUnit.Case

  alias Localize.Collation

  setup_all do
    Localize.Collation.ensure_loaded()
    :ok
  end

  # These tests are differential: they assert that each Chinese tailoring
  # produces a DIFFERENT output from the root (codepoint-ordered)
  # collation for specific character pairs. Without `refute equal` +
  # specific expected orderings, earlier versions of the tailoring
  # parser were trivially satisfied by falling through to codepoint
  # ordering — the broken state went undetected for a long time.

  describe "zh-u-co-pinyin" do
    test "orders Han chars by pinyin syllable (alphabetical by romanisation)" do
      # 白 (bai) < 北 (bei) under pinyin alphabetical order.
      # Codepoint: 0x767D (白) > 0x5317 (北), so root puts 北 first.
      assert Collation.compare("白", "北", locale: "zh-u-co-pinyin") == :lt
      assert Collation.compare("白", "北", locale: :root) == :gt
    end

    test "北京 < 上海 under pinyin (bei_jing < shang_hai)" do
      # Pinyin: b-starting < s-starting.
      # Codepoint: 上 (0x4E0A) < 北 (0x5317), so root puts 上海 first.
      assert Collation.compare("北京", "上海", locale: "zh-u-co-pinyin") == :lt
      assert Collation.compare("北京", "上海", locale: :root) == :gt
    end

    test "sort differs from root for common Chinese words" do
      chars = ["京", "北", "爱", "白"]
      pinyin = Collation.sort(chars, locale: "zh-u-co-pinyin")
      root = Collation.sort(chars, locale: :root)
      refute pinyin == root
      # Pinyin expected: 爱(ai), 白(bai), 北(bei), 京(jing) — alphabetical.
      assert pinyin == ["爱", "白", "北", "京"]
    end
  end

  describe "zh-u-co-stroke" do
    test "orders Han chars by stroke count (inverted from codepoint)" do
      # 乙 (U+4E59, 1 stroke) < 丁 (U+4E01, 2 strokes) by strokes.
      # Codepoint: 丁 (0x4E01) < 乙 (0x4E59) — the opposite order.
      assert Collation.compare("乙", "丁", locale: "zh-u-co-stroke") == :lt
      assert Collation.compare("乙", "丁", locale: :root) == :gt
    end

    test "sort by stroke count differs from codepoint order" do
      chars = ["丁", "乙", "一", "二"]
      stroke = Collation.sort(chars, locale: "zh-u-co-stroke")
      root = Collation.sort(chars, locale: :root)
      refute stroke == root
    end
  end

  describe "zh-u-co-zhuyin" do
    test "produces an ordering distinct from both pinyin and root" do
      chars = ["京", "北", "爱", "白"]
      zhuyin = Collation.sort(chars, locale: "zh-u-co-zhuyin")
      pinyin = Collation.sort(chars, locale: "zh-u-co-pinyin")
      root = Collation.sort(chars, locale: :root)

      refute zhuyin == root
      refute zhuyin == pinyin
    end
  end

  describe "tailoring cache" do
    # First-use parse is expensive (~70ms for zh-pinyin), subsequent
    # lookups must be ~microsecond-scale persistent_term reads.
    test "second and subsequent get_tailoring calls are cached" do
      # Warm the cache.
      _ = Localize.Collation.Tailoring.get_tailoring("zh", :pinyin)

      {time_us, _} =
        :timer.tc(fn ->
          Localize.Collation.Tailoring.get_tailoring("zh", :pinyin)
        end)

      # Cached hit should be well under 1ms.
      assert time_us < 1_000, "cached get_tailoring took #{time_us}µs"
    end
  end
end
