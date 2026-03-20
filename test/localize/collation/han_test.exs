defmodule Localize.Collation.HanTest do
  use ExUnit.Case

  doctest Localize.Collation.Han

  setup_all do
    Localize.Collation.ensure_loaded()
    Localize.Collation.Han.ensure_loaded()
    :ok
  end

  describe "Han character ordering" do
    test "CJK Unified Ideographs are recognized as unified ideographs" do
      # 一 (U+4E00) - "one", radical 1
      assert Localize.Collation.ImplicitWeights.unified_ideograph?(0x4E00)
      # 龥 (U+9FA5) - last common CJK character
      assert Localize.Collation.ImplicitWeights.unified_ideograph?(0x9FA5)
    end

    test "CJK characters get implicit weights" do
      # Characters not in allkeys should get implicit weights
      key_a = Localize.Collation.sort_key("一")
      key_b = Localize.Collation.sort_key("二")
      assert is_binary(key_a)
      assert is_binary(key_b)
      # Both should have sort keys (non-empty)
      assert byte_size(key_a) > 0
      assert byte_size(key_b) > 0
    end

    test "CJK characters sort after Latin" do
      assert Localize.Collation.compare("a", "一") == :lt
    end

    test "basic Han character comparison works" do
      # Should be able to compare any two Han characters
      result = Localize.Collation.compare("一", "二")
      assert result in [:lt, :gt, :eq]
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
end
