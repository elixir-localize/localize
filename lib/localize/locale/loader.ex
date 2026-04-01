defmodule Localize.Locale.Loader do
  @moduledoc """
  A GenServer that serializes locale data loading to prevent
  race conditions.

  When multiple processes request the same locale concurrently,
  the first request triggers the load and subsequent requests
  wait for it to complete. This avoids duplicate loads and
  redundant `:persistent_term.put/2` calls (each of which
  triggers a global GC).

  The server is started as part of the `Localize` supervision
  tree. All locale loading goes through `load_and_store/2` which
  delegates to this server.

  """

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

    if provider.loaded?(locale) do
      :ok
    else
      GenServer.call(__MODULE__, {:load_and_store, locale, provider}, :infinity)
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
    {:ok, %{}}
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
          case provider.load(locale) do
            {:ok, locale_data} ->
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
end
