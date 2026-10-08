defmodule Localize.Locale.ProviderDelegationTest do
  @moduledoc """
  Covers `Localize.Locale` delegation to caller-selected providers.

  These tests use fake providers to observe delegation. They do not
  exercise the default persistent-term provider.
  """

  use ExUnit.Case, async: true

  defmodule LoadOnlyProvider do
    @moduledoc false
    @behaviour Localize.Locale.Provider

    def load(locale), do: {:ok, %{loaded_locale: locale}}
    def store(_locale, _data), do: raise("Localize.Locale.load/2 must not call store/2")
    def loaded?(_locale), do: false
    def get(_locale, _keys, _options), do: {:error, :not_used}
  end

  defmodule RecordingProvider do
    @moduledoc false
    @behaviour Localize.Locale.Provider

    def table, do: __MODULE__

    def register(locale, pid), do: :ets.insert(table(), {locale, pid})
    def unregister(locale), do: :ets.delete(table(), locale)

    def load(locale) do
      notify(locale, {:provider_load, locale})
      {:ok, %{loaded_locale: locale}}
    end

    def store(locale, data) do
      notify(locale, {:provider_store, locale, data})
      :ets.insert(table(), {{:stored, locale}, true})
      :ok
    end

    def loaded?(locale), do: :ets.member(table(), {:stored, locale})

    def get(locale, keys, _options) do
      notify(locale, {:provider_get, locale, keys})

      if loaded?(locale) do
        {:ok, %{get_locale: locale, keys: keys}}
      else
        {:error, Localize.ItemNotFoundError.exception(locale: locale, keys: keys)}
      end
    end

    defp notify(locale, message) do
      case :ets.lookup(table(), locale) do
        [{^locale, pid}] -> send(pid, message)
        [] -> :ok
      end
    end
  end

  defmodule AlwaysReadsProvider do
    @moduledoc false
    @behaviour Localize.Locale.Provider

    def load(_locale), do: raise("Localize.Locale.get/3 must not load when the read succeeds")

    def store(_locale, _data),
      do: raise("Localize.Locale.get/3 must not store when the read succeeds")

    def loaded?(_locale), do: false
    def get(locale, keys, _options), do: {:ok, %{get_locale: locale, keys: keys}}
  end

  setup_all do
    table = RecordingProvider.table()

    if :ets.whereis(table) != :undefined do
      :ets.delete(table)
    end

    :ets.new(table, [:named_table, :public])

    on_exit(fn ->
      if :ets.whereis(table) != :undefined do
        :ets.delete(table)
      end
    end)

    :ok
  end

  test "Localize.Locale.load/2 delegates to provider load/1" do
    assert {:ok, %{loaded_locale: :en}} =
             Localize.Locale.load(:en, provider: LoadOnlyProvider)
  end

  test "Localize.Locale.get/3 loads through the requested provider when the read misses" do
    RecordingProvider.register(:en, self())

    on_exit(fn ->
      RecordingProvider.unregister(:en)
      :ets.delete(RecordingProvider.table(), {:stored, :en})
    end)

    assert {:ok, result} =
             Localize.Locale.get(:en, [:delimiters], provider: RecordingProvider)

    # `get/3` reads optimistically, so the first delegated call is the
    # read. Only when it misses is the locale loaded and stored, and the
    # read repeated.
    assert_receive {:provider_get, :en, [:delimiters]}
    assert_receive {:provider_load, :en}
    assert_receive {:provider_store, :en, %{loaded_locale: :en}}
    assert_receive {:provider_get, :en, [:delimiters]}
    assert result == %{get_locale: :en, keys: [:delimiters]}
  end

  test "Localize.Locale.get/3 does not load when the read succeeds" do
    # `AlwaysReadsProvider` raises from `load/1` and `store/2`, so a
    # successful read that still consulted them would fail here rather
    # than pass silently. Its `loaded?/1` returns `false` to show that
    # the load check is not what decides.
    assert {:ok, %{get_locale: :en, keys: [:delimiters]}} =
             Localize.Locale.get(:en, [:delimiters], provider: AlwaysReadsProvider)
  end
end
