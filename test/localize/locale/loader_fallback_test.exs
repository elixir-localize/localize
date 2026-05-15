defmodule Localize.Locale.LoaderFallbackTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  # Regression test for issue #26.
  #
  # Symptom on 0.30.x:
  #
  #     ** (MatchError) no match of right hand side value:
  #     {:error,
  #      %Localize.FormatError{
  #        reason: "The key path [:number_systems] was not found in locale :\"en-ZA\"."
  #      }}
  #
  # Root cause:
  #
  # When `Localize.Locale.Provider.load_with_fallback/2` returns
  # `{:ok, locale_data, resolved_locale_id}` because the requested
  # locale was unavailable and the loader fell back to a parent or
  # to `:en`, the GenServer in `Localize.Locale.Loader` stored the
  # data under `resolved_locale_id` instead of under the originally
  # requested locale. Subsequent `provider.get(requested_locale, ...)`
  # calls then missed entirely, even though the fallback data was
  # already in memory.
  #
  # 0.29 stored under the requested locale (ignoring the resolved
  # id), so subsequent lookups under the requested locale_id always
  # found the fallback data. This test restores and locks down that
  # behaviour.

  alias Localize.Locale.Loader

  # A provider where requesting `:en-ZA` (and any of its parent
  # walk targets) fails, but `:en` succeeds with realistic data.
  # State is kept in an Agent so we can introspect what was stored.
  defmodule FallbackProvider do
    @behaviour Localize.Locale.Provider

    # Started via `start_supervised!/1` so ExUnit owns the process
    # lifetime. Previously this used `Agent.start_link` linked to the
    # test process plus an `{:already_started, _}` reset branch — a
    # race where the named registration outlived the dead linked pid
    # surfaced as a 5-second `no process` GenServer call timeout in
    # CI.
    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, []}, restart: :temporary}
    end

    def start_link do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def stored_keys do
      Agent.get(__MODULE__, &Map.keys/1)
    end

    @impl true
    def load(:en), do: {:ok, %{number_systems: %{default: :latn}, source: :en}}
    def load(_other), do: {:error, :missing}

    @impl true
    def allow_download?, do: false

    @impl true
    def get(locale_id, keys, _options) do
      case Agent.get(__MODULE__, &Map.get(&1, locale_id)) do
        nil ->
          {:error, Localize.ItemNotFoundError.exception(locale: locale_id, keys: keys)}

        data ->
          case get_in(data, keys) do
            nil ->
              {:error, Localize.ItemNotFoundError.exception(locale: locale_id, keys: keys)}

            value ->
              {:ok, value}
          end
      end
    end

    @impl true
    def loaded?(locale_id) do
      Agent.get(__MODULE__, &Map.has_key?(&1, locale_id))
    end

    @impl true
    def store(locale_id, locale_data) do
      Agent.update(__MODULE__, &Map.put(&1, locale_id, locale_data))
      :ok
    end
  end

  setup do
    start_supervised!(FallbackProvider)
    :ok
  end

  test "Loader stores fallback data under the *requested* locale id, not the resolved id" do
    # Requesting `:en-ZA` against FallbackProvider triggers
    # `load_with_fallback/2` to walk parents and eventually fall back
    # to `:en`. In 0.29 the loader stored the resulting `:en` data
    # under the requested locale (`:en-ZA`); in 0.30.0–0.30.1 it
    # stored under the resolved id (`:en`), breaking subsequent
    # lookups for the requested locale.

    capture_log(fn ->
      :ok = Loader.load_and_store(:"en-ZA", provider: FallbackProvider)

      stored = FallbackProvider.stored_keys()

      assert :"en-ZA" in stored,
             "loader did not store fallback data under the requested locale " <>
               ":\"en-ZA\". Stored keys: #{inspect(stored)}. " <>
               "This is the regression that caused issue #26 — `mix " <>
               "localize.download_locales` crashed because subsequent " <>
               "lookups for the requested locale missed."
    end)
  end

  test "subsequent provider.get for the requested locale finds the fallback data" do
    # End-to-end check: after `load_and_store`, asking the provider
    # for the requested locale's data must succeed even though the
    # requested locale itself was never available — because the
    # fallback data is cached under the requested key.

    capture_log(fn ->
      :ok = Loader.load_and_store(:"en-ZA", provider: FallbackProvider)

      assert {:ok, %{default: :latn}} =
               FallbackProvider.get(:"en-ZA", [:number_systems], [])
    end)
  end

  test "loaded?/1 reports true for the requested locale after fallback" do
    capture_log(fn ->
      :ok = Loader.load_and_store(:"en-ZA", provider: FallbackProvider)
      assert FallbackProvider.loaded?(:"en-ZA")
    end)
  end
end
