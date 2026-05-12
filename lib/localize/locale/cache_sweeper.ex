defmodule Localize.Locale.CacheSweeper do
  @moduledoc false

  use GenServer

  @table :localize_locale_cache
  @sweep_interval_ms 10_000

  # Top 50 languages by native speaker population (lowercase
  # canonical form matching the ETS cache key format). These
  # entries are never evicted during cache sweeps.
  @never_evict MapSet.new([
                 "zh",
                 "es",
                 "en",
                 "hi",
                 "ar",
                 "bn",
                 "pt",
                 "ru",
                 "ja",
                 "pa",
                 "de",
                 "jv",
                 "ko",
                 "fr",
                 "te",
                 "mr",
                 "tr",
                 "ta",
                 "vi",
                 "ur",
                 "it",
                 "th",
                 "gu",
                 "pl",
                 "uk",
                 "ml",
                 "kn",
                 "or",
                 "my",
                 "sw",
                 "su",
                 "ro",
                 "nl",
                 "ha",
                 "az",
                 "si",
                 "hu",
                 "zu",
                 "cs",
                 "el",
                 "sv",
                 "be",
                 "da",
                 "fi",
                 "sk",
                 "no",
                 "he",
                 "id",
                 "ms",
                 "fil"
               ])

  def start_link(_options) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init([]) do
    schedule_sweep()
    {:ok, []}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep()
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end

  defp sweep do
    if :ets.whereis(@table) != :undefined do
      max_entries = Application.get_env(:localize, :locale_cache_max_entries, 1_000)
      size = :ets.info(@table, :size)

      if size > max_entries do
        evict_random(size - max_entries)
      end
    end
  end

  defp evict_random(count) when count <= 0, do: :ok

  defp evict_random(count) do
    key = :ets.first(@table)
    evict_random(key, count)
  end

  defp evict_random(:"$end_of_table", _remaining), do: :ok

  defp evict_random(_key, 0), do: :ok

  defp evict_random(key, remaining) do
    next_key = :ets.next(@table, key)

    if key in @never_evict do
      evict_random(next_key, remaining)
    else
      if :rand.uniform() < 0.5 do
        # Table is `:protected` and owned by `Localize.Locale.Loader`;
        # delete via the owner. Cast (not call) so the sweeper never
        # blocks the owner's load_and_store handler.
        GenServer.cast(Localize.Locale.Loader, {:cache_evict, key})
        evict_random(next_key, remaining - 1)
      else
        evict_random(next_key, remaining)
      end
    end
  end
end
