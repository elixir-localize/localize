defmodule Localize.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type \\ :normal, _args \\ []) do
    ensure_locale_cache_table()

    children = [
      Localize.DataLoader,
      Localize.Locale.Loader,
      Localize.Locale.CacheSweeper,
      Localize.FormatCache,
      Localize.Collation.Table
    ]

    options = [strategy: :one_for_one, name: Localize.Supervisor]

    case Supervisor.start_link(children, options) do
      {:ok, pid} ->
        resolve_supported_locales()
        {:ok, pid}

      error ->
        error
    end
  end

  defp ensure_locale_cache_table do
    if :ets.whereis(:localize_locale_cache) == :undefined do
      :ets.new(:localize_locale_cache, [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])
    end
  end

  # ── Supported locales ───────────────────────────────────────────

  defp resolve_supported_locales do
    maybe_warn_deprecated_preload()

    case Application.get_env(:localize, :supported_locales) do
      nil ->
        :ok

      locales when is_list(locales) ->
        expanded = Localize.Locale.expand_locale_list(locales, :supported_locales)
        :persistent_term.put({:localize, :supported_locales}, expanded)
    end
  end

  defp maybe_warn_deprecated_preload do
    case Application.get_env(:localize, :preload_locales) do
      nil ->
        :ok

      _configured ->
        Logger.warning(
          "The :preload_locales configuration key is deprecated and ignored. " <>
            "Use :supported_locales to declare your locale set, and " <>
            "`mix localize.download_locales` to pre-populate the cache " <>
            "at build time. Locale data is loaded lazily into " <>
            ":persistent_term on first access.",
          domain: [:localize]
        )
    end
  end
end
