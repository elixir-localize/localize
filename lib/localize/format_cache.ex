defmodule Localize.FormatCache do
  # An ETS-backed cache for compiled format patterns and data
  # derived from locale data.
  #
  # Number format metadata, datetime format tokens and the
  # currency strings of a locale are cached here after they are
  # first built. `Localize.Locale.store/3` clears the cache, so no
  # entry outlives the locale data it came from. The cache is
  # hard-bounded: when
  # inserting an entry would exceed the configured maximum, an
  # existing entry is evicted synchronously, keeping the cache at
  # or below the cap at all times.
  #
  # The maximum number of entries defaults to 2,000 and can be
  # overridden with:
  #
  #     config :localize, :format_cache_max_entries, 5_000
  #
  # ## Trust model
  #
  # The ETS table is `:protected` — only the cache GenServer can
  # write to it; any process can read directly. This keeps the
  # cache from being polluted by other libraries running in the
  # same BEAM, and ensures the size invariant cannot be violated
  # by a non-owner write.
  #
  # Writes go through `store/2`, which is a `GenServer.call` to the
  # owner. A miss-then-store pattern from a hot path therefore pays
  # one gen-server round-trip per *first-time* format compilation;
  # subsequent lookups are direct ETS reads with no synchronisation
  # cost.
  #
  @moduledoc false

  use GenServer

  @table :localize_format_cache
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

  Routed through the cache GenServer so the size cap can be
  enforced synchronously. If the table doesn't exist (e.g. during
  a bare unit test), the call is a no-op.

  ### Arguments

  * `key` is the cache key.

  * `value` is the compiled artifact to cache.

  * `generation` is the value `generation/0` returned before the
    value was built from locale data. The value is dropped when
    `clear/0` ran since then, so it cannot outlive the data it came
    from. The default `:any` always stores.

  ### Returns

  * `:ok`.

  """
  @spec store(term(), term(), non_neg_integer() | :any) :: :ok
  def store(key, value, generation \\ :any) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:store, key, value, generation})
    else
      :ok
    end
  end

  @doc """
  Returns the number of times the cache was cleared, for `store/3`.

  """
  @spec generation() :: non_neg_integer()
  def generation do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :generation)
    else
      0
    end
  end

  @doc """
  Returns the current number of entries in the cache.

  Primarily useful in tests; production callers should not need
  to inspect the size directly.

  """
  @spec size() :: non_neg_integer()
  def size do
    if :ets.whereis(@table) != :undefined do
      :ets.info(@table, :size)
    else
      0
    end
  end

  @doc """
  Returns the configured maximum number of cache entries.

  """
  @spec max_entries() :: pos_integer()
  def max_entries do
    Application.get_env(:localize, :format_cache_max_entries, @default_max_entries)
  end

  @doc """
  Clears all entries from the cache.

  Routed through the GenServer so the operation respects the
  table's `:protected` ownership. Intended for tests and
  maintenance; production callers should not need this.

  """
  @spec clear() :: :ok
  def clear do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :clear)
    else
      :ok
    end
  end

  # ── GenServer ──────────────────────────────────────────────

  @doc false
  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl true
  def init(_options) do
    ensure_table()
    {:ok, 0}
  end

  @impl true
  def handle_call({:store, key, value, generation}, _from, current)
      when generation in [:any, current] do
    cap = max_entries()
    size = :ets.info(@table, :size)

    # If the key already exists, this is an update — no growth.
    # Otherwise, evict to stay at or below the cap before insert.
    cond do
      :ets.member(@table, key) ->
        :ets.insert(@table, {key, value})

      size >= cap ->
        evict(size - cap + 1)
        :ets.insert(@table, {key, value})

      true ->
        :ets.insert(@table, {key, value})
    end

    {:reply, :ok, current}
  end

  def handle_call({:store, _key, _value, _stale_generation}, _from, current) do
    {:reply, :ok, current}
  end

  def handle_call(:generation, _from, current) do
    {:reply, current, current}
  end

  def handle_call(:clear, _from, current) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    {:reply, :ok, current + 1}
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [
        :set,
        :protected,
        :named_table,
        read_concurrency: true
      ])
    end
  end

  # Synchronous bounded eviction. Removes `count` entries by
  # walking the table; ETS `:set` doesn't preserve insertion order,
  # but the deterministic `:ets.first/1` traversal gives us a
  # bounded eviction strategy without per-entry bookkeeping.
  # True LRU would require an access-order index whose write cost
  # exceeds the cache's protection benefit.
  defp evict(count) when count <= 0, do: :ok

  defp evict(count) do
    case :ets.first(@table) do
      :"$end_of_table" ->
        :ok

      key ->
        :ets.delete(@table, key)
        evict(count - 1)
    end
  end
end
