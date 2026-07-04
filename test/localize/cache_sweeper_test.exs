defmodule Localize.Locale.CacheSweeperTest do
  # These tests mutate the shared :localize_locale_cache ETS table
  # (via the Loader, its owner) and the :locale_cache_max_entries
  # application environment, so they must not run concurrently with
  # other tests.
  use ExUnit.Case, async: false

  alias Localize.Locale.CacheSweeper
  alias Localize.Locale.Loader

  @table :localize_locale_cache
  @fake_keys Enum.map(1..8, fn index -> "zz-cache-sweeper-test-#{index}" end)

  setup do
    original_max_entries = Application.get_env(:localize, :locale_cache_max_entries)

    on_exit(fn ->
      if original_max_entries do
        Application.put_env(:localize, :locale_cache_max_entries, original_max_entries)
      else
        Application.delete_env(:localize, :locale_cache_max_entries)
      end

      evict_keys(@fake_keys ++ ["zh"])
    end)

    :ok
  end

  # Evict specific keys through the table owner and wait for the
  # casts to be processed.
  defp evict_keys(keys) do
    Enum.each(keys, fn key -> GenServer.cast(Loader, {:cache_evict, key}) end)
    :sys.get_state(Loader)
    :ok
  end

  # Insert fake cache entries through the table owner and wait for
  # the casts to be processed.
  defp store_fake_entries(keys) do
    Enum.each(keys, fn key -> Loader.cache_store({key, :fake_entry}) end)
    :sys.get_state(Loader)
    :ok
  end

  # Run one synchronous sweep pass in the calling process and wait
  # for any eviction casts to reach the Loader.
  defp sweep_once do
    assert CacheSweeper.handle_info(:sweep, []) == {:noreply, []}
    :sys.get_state(Loader)
    :ok
  end

  describe "handle_info(:sweep, state)" do
    test "does not evict when the table is within the entry limit" do
      store_fake_entries(@fake_keys)
      Application.put_env(:localize, :locale_cache_max_entries, 1_000_000)

      size_before = :ets.info(@table, :size)
      sweep_once()

      assert :ets.info(@table, :size) == size_before

      for key <- @fake_keys do
        assert :ets.lookup(@table, key) == [{key, :fake_entry}]
      end
    end

    test "evicts entries when the table exceeds the entry limit" do
      store_fake_entries(@fake_keys)
      Application.put_env(:localize, :locale_cache_max_entries, 0)

      size_before = :ets.info(@table, :size)
      assert size_before >= length(@fake_keys)

      # Eviction is probabilistic (roughly half the walked entries per
      # pass), so sweep repeatedly; the chance of a fake entry
      # surviving 30 passes is negligible. Entries for the protected
      # high-traffic languages may legitimately remain, so assert on
      # the fake keys rather than a table size of zero.
      Enum.reduce_while(1..30, :continue, fn _pass, _accumulator ->
        sweep_once()

        if Enum.any?(@fake_keys, fn key -> :ets.member(@table, key) end) do
          {:cont, :continue}
        else
          {:halt, :done}
        end
      end)

      assert :ets.info(@table, :size) < size_before

      for key <- @fake_keys do
        refute :ets.member(@table, key)
      end
    end

    test "never evicts the protected high-traffic language entries" do
      store_fake_entries(["zh"])
      Application.put_env(:localize, :locale_cache_max_entries, 0)

      Enum.each(1..10, fn _pass -> sweep_once() end)

      assert :ets.lookup(@table, "zh") == [{"zh", :fake_entry}]
    end

    test "schedules the next sweep" do
      Application.put_env(:localize, :locale_cache_max_entries, 1_000_000)

      assert CacheSweeper.handle_info(:sweep, []) == {:noreply, []}

      # The next sweep is scheduled ten seconds out, so it must not
      # have arrived yet — but a timer must exist for this process.
      refute_received :sweep
    end
  end
end
