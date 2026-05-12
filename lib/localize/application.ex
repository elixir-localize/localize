defmodule Localize.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type \\ :normal, _args \\ []) do
    children = [
      Localize.DataLoader,
      # `Localize.Locale.Loader` owns the `:localize_locale_cache`
      # ETS table (created in its `init/1`); it must start before any
      # supervisor child that may need the table.
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

  # ── Supported locales ───────────────────────────────────────────

  defp resolve_supported_locales do
    maybe_warn_deprecated_preload()
    _ = Localize.supported_locales()
    :ok
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
