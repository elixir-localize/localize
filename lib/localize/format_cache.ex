defmodule Localize.FormatCache do
  @moduledoc """
  An ETS-backed cache for compiled format patterns.

  Number format metadata and datetime format tokens are cached
  here after first compilation. A built-in sweeper periodically
  evicts random entries when the cache exceeds its configured
  maximum size.

  The maximum number of entries defaults to 2,000 and can be
  overridden with:

      config :localize, :format_cache_max_entries, 5_000

  """

  use GenServer

  @table :localize_format_cache
  @sweep_interval_ms 10_000
  @default_max_entries 2_000

  # ── Client API ──────────────────────────────────────────────

  @doc """
  Look up a compiled format pattern by its cache key.

  ### Arguments

  * `key` is the cache key, typically a tuple like
    `{:localize, :number_format_meta, format_string}`.

  ### Returns

  * `{:ok, value}` if the key is present.

  * `:miss` if not cached or the table does not exist.

  """
  @spec lookup(term()) :: {:ok, term()} | :miss
  def lookup(key) do
    if :ets.whereis(@table) != :undefined do
      case :ets.lookup(@table, key) do
        [{^key, value}] -> {:ok, value}
        [] -> :miss
      end
    else
      :miss
    end
  end

  @doc """
  Store a compiled format pattern in the cache.

  ### Arguments

  * `key` is the cache key.

  * `value` is the compiled artifact to cache.

  ### Returns

  * `:ok`.

  """
  @spec store(term(), term()) :: :ok
  def store(key, value) do
    if :ets.whereis(@table) != :undefined do
      :ets.insert(@table, {key, value})
    end

    :ok
  end

  # ── GenServer (sweeper) ─────────────────────────────────────

  @doc false
  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl true
  def init(_options) do
    ensure_table()
    schedule_sweep()
    {:ok, []}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep()
    schedule_sweep()
    {:noreply, state}
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])
    end
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end

  defp sweep do
    if :ets.whereis(@table) != :undefined do
      max_entries = Application.get_env(:localize, :format_cache_max_entries, @default_max_entries)
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

    if :rand.uniform() < 0.5 do
      :ets.delete(@table, key)
      evict_random(next_key, remaining - 1)
    else
      evict_random(next_key, remaining)
    end
  end
end
