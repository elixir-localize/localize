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
      :ok
    end

    def loaded?(_locale), do: false

    def get(locale, keys, _options) do
      notify(locale, {:provider_get, locale, keys})
      {:ok, %{get_locale: locale, keys: keys}}
    end

    defp notify(locale, message) do
      case :ets.lookup(table(), locale) do
        [{^locale, pid}] -> send(pid, message)
        [] -> :ok
      end
    end
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

  test "Localize.Locale.get/3 loads through the requested provider" do
    RecordingProvider.register(:en, self())

    on_exit(fn -> RecordingProvider.unregister(:en) end)

    assert {:ok, result} =
             Localize.Locale.get(:en, [:delimiters], provider: RecordingProvider)

    assert_receive {:provider_load, :en}
    assert_receive {:provider_store, :en, %{loaded_locale: :en}}
    assert_receive {:provider_get, :en, [:delimiters]}
    assert result == %{get_locale: :en, keys: [:delimiters]}
  end
end
