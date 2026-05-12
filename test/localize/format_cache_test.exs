defmodule Localize.FormatCacheTest do
  @moduledoc """
  Security regression tests for the format cache. The cache used to
  be `:public` (any process could write), bounded only by a 10-second
  sweeper using biased-random eviction. Both invariants are now
  stricter: the table is `:protected` (writes go through the GenServer)
  and the size cap is enforced synchronously on each insert.
  """

  # async: false because we mutate the global cache.
  use ExUnit.Case, async: false

  alias Localize.FormatCache

  setup do
    # Each test starts from an empty cache (cleared via the
    # GenServer, which owns the protected table). The size cap is
    # global; tests that change it must restore it.
    :ok = FormatCache.clear()

    original = Application.get_env(:localize, :format_cache_max_entries)

    on_exit(fn ->
      if original do
        Application.put_env(:localize, :format_cache_max_entries, original)
      else
        Application.delete_env(:localize, :format_cache_max_entries)
      end

      FormatCache.clear()
    end)

    :ok
  end

  describe "trust model" do
    test "the ETS table is :protected, not :public" do
      assert :protected == :ets.info(:localize_format_cache, :protection)
    end

    test "non-owner processes cannot write directly" do
      assert_raise ArgumentError, fn ->
        :ets.insert(:localize_format_cache, {:cannot_write_directly, :nope})
      end
    end
  end

  describe "bounded eviction" do
    test "synchronously evicts when an insert would exceed the cap" do
      Application.put_env(:localize, :format_cache_max_entries, 5)

      for i <- 1..5 do
        :ok = FormatCache.store({:test, i}, :compiled)
      end

      assert FormatCache.size() == 5

      # Inserting a sixth must evict one entry, keeping size at the cap.
      :ok = FormatCache.store({:test, 6}, :compiled)
      assert FormatCache.size() == 5

      # And subsequent inserts hold the bound.
      for i <- 7..15 do
        :ok = FormatCache.store({:test, i}, :compiled)
      end

      assert FormatCache.size() == 5
    end

    test "updating an existing key does not grow the cache" do
      Application.put_env(:localize, :format_cache_max_entries, 3)

      :ok = FormatCache.store({:dup, 1}, :v1)
      :ok = FormatCache.store({:dup, 1}, :v2)
      :ok = FormatCache.store({:dup, 1}, :v3)

      assert FormatCache.size() == 1
      assert {:ok, :v3} = FormatCache.lookup({:dup, 1})
    end

    test "1000 unique inserts at cap=10 leave exactly 10 entries" do
      Application.put_env(:localize, :format_cache_max_entries, 10)

      for i <- 1..1000 do
        :ok = FormatCache.store({:bulk, i}, :compiled)
      end

      assert FormatCache.size() == 10
    end
  end
end
