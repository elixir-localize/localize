defmodule Localize.Locale.Loader do
  # A GenServer that serializes locale data loading to prevent
  # race conditions.
  #
  # When multiple processes request the same locale concurrently,
  # the first request triggers the load and subsequent requests
  # wait for it to complete. This avoids duplicate loads and
  # redundant `:persistent_term.put/2` calls (each of which
  # triggers a global GC).
  #
  # The server is started as part of the `Localize` supervision
  # tree. All locale loading goes through `load_and_store/2` which
  # delegates to this server.
  #
  @moduledoc false

  use GenServer

  # ── Public API ────────────────────────────────────────────────

  @doc """
  Starts the loader GenServer.

  """
  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc """
  Loads and stores locale data, serialized through the GenServer.

  If the locale is already loaded, returns `:ok` immediately
  without contacting the server. Otherwise, delegates to the
  GenServer which ensures only one load per locale occurs.

  ### Arguments

  * `locale` is a locale identifier atom or a
    `t:Localize.LanguageTag.t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:provider` is the module implementing `Localize.Locale.Provider`
    to use. The default is `Localize.Locale.default_provider/0`.

  ### Returns

  * `:ok` on success.

  * `{:error, exception}` if the locale data could not be loaded.

  """
  @spec load_and_store(Localize.Locale.Provider.locale(), Keyword.t()) ::
          :ok | {:error, Exception.t()}
  def load_and_store(locale, options \\ []) do
    provider = Keyword.get(options, :provider, Localize.Locale.default_provider())

    case Localize.Locale.cldr_locale_id_from(locale) do
      {:ok, locale_id} ->
        if provider.loaded?(locale_id) do
          :ok
        else
          GenServer.call(__MODULE__, {:load_and_store, locale_id, provider}, :infinity)
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Clears the locale validation cache.

  This is called when the supported locales change to ensure
  stale resolutions are not returned.

  """
  @spec clear_locale_cache() :: :ok
  def clear_locale_cache do
    GenServer.call(__MODULE__, :clear_locale_cache)
  end

  # ── GenServer callbacks ───────────────────────────────────────

  @impl GenServer
  def init(_options) do
    # Own the locale-validation cache so non-owner processes cannot
    # write to or delete from it. The table is `:protected`: any
    # process can read directly via `:ets.lookup/2`, but writes go
    # through this GenServer (see `cache_store/1` and `clear_cache/0`).
    if :ets.whereis(:localize_locale_cache) == :undefined do
      :ets.new(:localize_locale_cache, [
        :set,
        :protected,
        :named_table,
        read_concurrency: true
      ])
    end

    {:ok, %{}}
  end

  @doc """
  Inserts a `{cache_key, value}` pair into the locale-validation cache
  via the owner GenServer.

  Sent as a `cast/2` so the hot path never blocks on the owner's
  mailbox, and so a write originating *inside* the owner (e.g. when
  `validate_locale/1` is called transitively from
  `handle_call({:load_and_store, ...})`) cannot deadlock. Eventual-
  consistency is acceptable for a cache: a write that hasn't landed
  yet just looks like a miss, which triggers a recompute.

  """
  @spec cache_store({term(), term()}) :: :ok
  def cache_store({_key, _value} = entry) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:cache_store, entry})
    else
      :ok
    end
  end

  @doc """
  Clears all entries from the locale-validation cache via the owner.

  """
  @spec clear_cache() :: :ok
  def clear_cache do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :clear_locale_cache)
    else
      :ok
    end
  end

  @impl GenServer
  def handle_call(:clear_locale_cache, _from, state) do
    table = :localize_locale_cache

    if :ets.whereis(table) != :undefined do
      :ets.delete_all_objects(table)
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:load_and_store, locale, provider}, _from, state) do
    # Double-check inside the serialized context — another
    # request may have loaded it while we were queued.
    #
    # The try/rescue here is a system boundary guard: provider.load/1
    # may call into external data generation code that can raise for
    # invalid locales. Without this protection the GenServer would
    # crash and become unavailable for subsequent valid requests.
    result =
      if provider.loaded?(locale) do
        :ok
      else
        try do
          case Localize.Locale.Provider.load_with_fallback(provider, locale) do
            {:ok, locale_data, _resolved_locale_id} ->
              # Store under the *requested* locale id, not the resolved
              # fallback id. This is the behaviour of 0.29 — see
              # `test/localize/locale/loader_fallback_test.exs` and
              # issue #26. Storing under the resolved id meant that
              # subsequent `provider.get(requested_locale, _)` calls
              # missed the in-memory fallback data, surfacing as a
              # spurious `ItemNotFoundError` even though the data was
              # already loaded.
              provider.store(locale, locale_data)

            {:error, _reason} = error ->
              error
          end
        rescue
          exception ->
            {:error, exception}
        end
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_cast({:cache_store, {key, value}}, state) do
    if :ets.whereis(:localize_locale_cache) != :undefined do
      :ets.insert(:localize_locale_cache, {key, value})
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:cache_evict, key}, state) do
    if :ets.whereis(:localize_locale_cache) != :undefined do
      :ets.delete(:localize_locale_cache, key)
    end

    {:noreply, state}
  end
end
