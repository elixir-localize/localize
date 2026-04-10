defmodule Mix.Tasks.Localize.DownloadLocales do
  @shortdoc "Downloads locale ETF files from the Localize CDN"

  @moduledoc """
  Downloads locale ETF files from the Localize CDN and stores
  them in the configured locale cache directory.

  This task is intended to be run at build time (e.g. in a
  Dockerfile or CI pipeline) so that all required locales are
  available in the cache before the application starts. This
  avoids the need for runtime downloads in production.

  ## Usage

      mix localize.download_locales en fr de ja

  Downloads the specified locales.

      mix localize.download_locales --preload

  Downloads the locales listed in `config :localize, :preload_locales`.
  Wildcard entries (e.g. `"en-*"`) are expanded.

      mix localize.download_locales --all

  Downloads all 766 CLDR locales.

  ## Output directory

  Files are written to the directory returned by
  `Localize.Locale.Provider.locale_cache_dir/0`, which defaults
  to `Application.app_dir(:localize, "priv/localize/locales")`.

  Override with:

      config :localize, locale_cache_dir: "/path/to/cache"

  ## Examples

  Pre-populate the cache for a Docker build:

      # Dockerfile
      RUN mix localize.download_locales --preload

  Download specific locales for testing:

      mix localize.download_locales en de ja zh

  """

  use Mix.Task

  alias Localize.Locale.Provider
  alias Localize.Locale.Provider.Cache

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, locale_args} =
      OptionParser.parse!(args, strict: [preload: :boolean, all: :boolean])

    locales = resolve_locales(opts, locale_args)

    if locales == [] do
      Mix.shell().error("No locales to download. Specify locale names, --preload, or --all.")
      System.halt(1)
    end

    cache_dir = Provider.locale_cache_dir()
    Mix.shell().info("Downloading #{length(locales)} locale(s) to #{cache_dir}")
    Mix.shell().info("Version: #{Localize.version()}\n")

    {successes, failures} =
      locales
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0}, fn {locale_id, index}, {ok, fail} ->
        prefix = "[#{index}/#{length(locales)}]"

        case download_and_store(locale_id) do
          {:ok, path, size} ->
            Mix.shell().info("#{prefix} #{locale_id} (#{format_size(size)}) -> #{path}")
            {ok + 1, fail}

          {:error, reason} ->
            Mix.shell().error("#{prefix} #{locale_id} FAILED: #{reason}")
            {ok, fail + 1}
        end
      end)

    Mix.shell().info("\nDone. #{successes} downloaded, #{failures} failed.")

    if failures > 0 do
      System.halt(1)
    end
  end

  defp resolve_locales(opts, locale_args) do
    cond do
      opts[:all] ->
        Localize.SupplementalData.all_locale_ids()

      opts[:preload] ->
        case Application.get_env(:localize, :preload_locales) do
          nil ->
            Mix.shell().error("No :preload_locales configured.")
            []

          [] ->
            Mix.shell().error("The :preload_locales list is empty.")
            []

          entries ->
            Localize.Locale.expand_locale_list(entries, :preload_locales)
        end

      locale_args != [] ->
        Enum.map(locale_args, &String.to_atom/1)

      true ->
        []
    end
  end

  defp download_and_store(locale_id) do
    case Provider.download_locale(locale_id) do
      {:ok, binary} ->
        case Cache.store(locale_id, binary) do
          {:ok, path} ->
            {:ok, path, byte_size(binary)}

          {:error, exception} ->
            {:error, Exception.message(exception)}
        end

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp format_size(bytes) when bytes >= 1024 do
    kb = Float.round(bytes / 1024, 1)
    "#{kb} KB"
  end

  defp format_size(bytes), do: "#{bytes} B"
end
