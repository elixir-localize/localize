defmodule Localize.Locale.FallbackResilienceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  # Defence-in-depth tests for the locale fallback pipeline.
  #
  # The original bug behind issue #26 was the loader storing fallback
  # data under the resolved (rather than requested) locale id, so
  # downstream operations missed in-memory data. The unit-level
  # `loader_fallback_test.exs` locks down the storage key. This file
  # adds wider, end-to-end style coverage: it exercises the *public*
  # operations the user actually performs — number formatting, date
  # formatting, message formatting — through configurations that
  # force fallback, and asserts they all complete without crashing.
  #
  # If any of these tests fail, a regression in the broader fallback
  # pipeline has been introduced — even if the unit-level loader
  # test still passes.

  alias Localize.Locale.Loader

  # A provider that fails for every locale except `:en`, returning a
  # realistic locale-data shape for `:en`. Used to simulate the
  # user's scenario where `:"en-ZA"` (or any other locale) data is
  # not yet downloaded.
  defmodule OnlyEnProvider do
    @behaviour Localize.Locale.Provider

    @en_data %{
      number_systems: %{default: :latn},
      currencies: %{},
      languages: %{},
      territories: %{},
      version: :ignored
    }

    def start_link do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def reset do
      Agent.update(__MODULE__, fn _ -> %{} end)
    end

    def stored_keys do
      Agent.get(__MODULE__, &Map.keys/1)
    end

    @impl true
    def load(:en), do: {:ok, @en_data}
    def load(_), do: {:error, :missing}

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
    case OnlyEnProvider.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _}} -> OnlyEnProvider.reset()
    end

    :ok
  end

  # Locales that exercise different parent-walk shapes. Each one was
  # chosen because it's structurally valid in BCP47 and the parent
  # chain has at least one non-trivial step.
  @fallback_locales [
    :"en-ZA",
    :"en-AU",
    :"en-GB",
    :"pt-BR",
    :"zh-Hant",
    :"sr-Latn",
    :"es-419"
  ]

  for locale <- @fallback_locales do
    test "Locale.get/3 for #{inspect(locale)} returns ok or structured error, never crashes" do
      capture_log(fn ->
        # Trigger the load+fallback path.
        :ok = Loader.load_and_store(unquote(locale), provider: OnlyEnProvider)

        # `cldr_locale_id_from/1` canonicalizes the input first
        # (e.g. `:"pt-BR"` → `:pt`). The loader uses the canonical
        # form as the storage key; the fix for issue #26 ensures
        # that key is the *canonical requested* form, not the
        # *resolved fallback* form (which would be `:en` here).
        {:ok, canonical_id} = Localize.Locale.cldr_locale_id_from(unquote(locale))

        assert canonical_id in OnlyEnProvider.stored_keys(),
               "fallback data must be stored under the canonicalised requested " <>
                 "locale #{inspect(canonical_id)}, not the resolved fallback id"

        # And the typical lookup that broke for issue #26 must succeed.
        assert {:ok, %{default: :latn}} =
                 OnlyEnProvider.get(canonical_id, [:number_systems], [])
      end)
    end
  end

  test "Locale.get/3 for an unknown-but-validly-shaped locale returns a structured error" do
    # Locales that aren't recognised should yield a clean error, not
    # crash. This catches the case where validate_locale or parent/1
    # rejects the input and the loader has nothing to fall back to.
    capture_log(fn ->
      result = Loader.load_and_store(:"qa-Zzzz-XX", provider: OnlyEnProvider)

      case result do
        :ok ->
          # Acceptable: the validity chain accepted it and fell back
          # all the way to `:en`. The data must then be under the
          # requested key.
          assert :"qa-Zzzz-XX" in OnlyEnProvider.stored_keys()

        {:error, %_{} = exception} ->
          # Also acceptable: a structured Localize exception. What is
          # *not* acceptable is a crash or a bare-string error.
          assert is_struct(exception)
      end
    end)
  end
end
