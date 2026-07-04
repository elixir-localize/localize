defmodule Localize.DataLoader do
  # A GenServer that serializes ETF data file loading to prevent
  # race conditions.
  #
  # When multiple processes request the same data concurrently,
  # the first request triggers the load and subsequent requests
  # wait for it to complete. This avoids duplicate file reads and
  # redundant `:persistent_term.put/2` calls (each of which
  # triggers a global GC).
  #
  # The server is started as part of the `Localize` supervision
  # tree. All ETF file loading goes through `load/2`.
  #
  @moduledoc false

  use GenServer

  # ── Public API ────────────────────────────────────────────────

  @doc """
  Starts the data loader GenServer.

  """
  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc """
  Loads an ETF data file, serialized through the GenServer.

  If the data is already cached in `:persistent_term`, returns
  it immediately without contacting the server. Otherwise,
  delegates to the GenServer which ensures only one load per
  key occurs.

  ### Arguments

  * `key` is the `:persistent_term` key (e.g.,
    `{:localize, :supplemental, "aliases.etf"}`).

  * `load_fn` is a zero-arity function that reads and decodes
    the file, returning the data to be cached.

  ### Returns

  * The loaded data.

  """
  @spec load(term(), (-> term())) :: term()
  def load(key, load_fn) do
    case :persistent_term.get(key, :not_loaded) do
      :not_loaded ->
        if server_running?() do
          GenServer.call(__MODULE__, {:load, key, load_fn}, :infinity)
        else
          # Compile time or before app start — load directly
          data = load_fn.()
          :persistent_term.put(key, data)
          data
        end

      data ->
        data
    end
  end

  defp server_running? do
    pid = Process.whereis(__MODULE__)
    pid && Process.alive?(pid)
  end

  # ── GenServer callbacks ───────────────────────────────────────

  @impl GenServer
  def init(_options) do
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:load, key, load_fn}, _from, state) do
    data =
      case :persistent_term.get(key, :not_loaded) do
        :not_loaded ->
          data = load_fn.()
          :persistent_term.put(key, data)
          data

        data ->
          data
      end

    {:reply, data, state}
  end
end
