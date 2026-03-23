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

    # Preload locale data for the preload list
    Enum.each(preload, &Localize.Locale.Loader.load_and_store/1)
  end

  defp expand_config_locales(config_key) do
    case Application.get_env(:localize, config_key) do
      nil -> []
      [] -> []
      locales when is_list(locales) -> expand_locale_list(locales, config_key)
    end
  end

  # ── Shared locale list expansion ────────────────────────────

  # Expands a list of atoms and wildcard strings into a list of
  # known CLDR locale ID atoms. Each entry is either:
  #
  # * An atom that exists in `all_locale_ids()`.
  # * A string with a trailing `*` wildcard (e.g., `"en-*"`)
  #   that expands to all matching locale IDs.
  #
  # Invalid entries log a warning with `:localize` domain metadata.

  defp expand_locale_list(entries, config_key) do
    all_ids = Localize.SupplementalData.all_locale_ids()
    all_strings = MapSet.new(all_ids, &Atom.to_string/1)

    entries
    |> Enum.flat_map(fn entry -> expand_locale_entry(entry, all_ids, all_strings, config_key) end)
    |> Enum.uniq()
  end

  defp expand_locale_entry(entry, all_ids, _all_strings, config_key) when is_atom(entry) do
    if entry in all_ids do
      [entry]
    else
      Logger.warning(
        "Ignoring unknown locale #{inspect(entry)} in #{inspect(config_key)} configuration. " <>
          "Not found in known CLDR locales.",
        domain: [:localize]
      )

      []
    end
  end

  defp expand_locale_entry(entry, all_ids, all_strings, config_key) when is_binary(entry) do
    if String.ends_with?(entry, "*") do
      prefix = String.trim_trailing(entry, "*")
      expand_wildcard(prefix, all_ids)
    else
      if MapSet.member?(all_strings, entry) do
        [String.to_existing_atom(entry)]
      else
        Logger.warning(
          "Ignoring unknown locale #{inspect(entry)} in #{inspect(config_key)} configuration. " <>
            "Not found in known CLDR locales.",
          domain: [:localize]
        )

        []
      end
    end
  end

  defp expand_wildcard(prefix, all_ids) do
    Enum.filter(all_ids, fn id ->
      id |> Atom.to_string() |> String.starts_with?(prefix)
    end)
  end
end
