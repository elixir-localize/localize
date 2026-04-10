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
      Localize.Collation.Table,
      Localize.Collation.Han,
      Localize.Currency.Store
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

  # ── Supported and preload locales ─────────────────────────────

  defp resolve_supported_locales do
    supported = expand_config_locales(:supported_locales)
    preload = expand_config_locales(:preload_locales)

    # Store the union of supported and preload locales, but only
    # if :supported_locales was explicitly configured.
    case Application.get_env(:localize, :supported_locales) do
      nil ->
        :ok

      _configured ->
        merged =
          (supported ++ preload)
          |> Enum.uniq()

        :persistent_term.put({:localize, :supported_locales}, merged)
    end

    # Preload locale data for the preload list. Failures are
    # logged as warnings rather than crashing the supervisor —
    # the locale will be loaded on first access (or the user
    # will get a clear error if downloads are disabled and the
    # locale is not in the cache).
    Enum.each(preload, fn locale ->
      case Localize.Locale.Loader.load_and_store(locale) do
        :ok ->
          :ok

        {:error, exception} ->
          Logger.warning(
            "Failed to preload locale #{inspect(locale)}: #{Exception.message(exception)}",
            domain: [:localize]
          )
      end
    end)
  end

  defp expand_config_locales(config_key) do
    case Application.get_env(:localize, config_key) do
      nil -> []
      [] -> []
      locales when is_list(locales) -> Localize.Locale.expand_locale_list(locales, config_key)
    end
  end
end
