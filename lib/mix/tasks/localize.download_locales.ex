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

      mix localize.download_locales

  Downloads the configured `:supported_locales`. When
  `:supported_locales` is not configured (meaning all CLDR
  locales are supported), prompts for confirmation before
  downloading.

      mix localize.download_locales en fr de ja

  Downloads the specified locales.

      mix localize.download_locales --all

  Downloads all CLDR locales without prompting.

      mix localize.download_locales --force

  When `:supported_locales` is not configured, downloads all
  locales without prompting. Useful in CI/Docker where there
  is no interactive terminal.

  ## Output directory

  Files are written to the directory returned by
  `Localize.Locale.Provider.locale_cache_dir/0`, which defaults
  to `Application.app_dir(:localize, "priv/localize/locales")`.

  Override with:

      config :localize, locale_cache_dir: "/path/to/cache"

  ## Examples

  Pre-populate the cache for a Docker build:

      # Dockerfile
      RUN mix localize.download_locales

  Download specific locales for testing:

      mix localize.download_locales en de ja zh

  Download everything in a non-interactive environment:

      mix localize.download_locales --force

  """

  use Mix.Task

  alias Localize.Locale.Provider
  alias Localize.Locale.Provider.Cache

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, locale_args} =
      OptionParser.parse!(args, strict: [all: :boolean, force: :boolean])

    locales = resolve_locales(opts, locale_args)

    if locales == [] do
      # User declined at the confirmation prompt
      :ok
    else
      download_locales(locales)
    end
  end

  defp resolve_locales(opts, locale_args) do
    cond do
      # Explicit locale names on the command line
      locale_args != [] ->
        Enum.map(locale_args, &String.to_atom/1)

      # --all: download everything, no questions asked
      opts[:all] ->
        Localize.SupplementalData.all_locale_ids()

      # Default: download supported locales
      true ->
        resolve_supported(opts)
    end
  end

  defp resolve_supported(opts) do
    all_ids = Localize.SupplementalData.all_locale_ids()
    supported = Localize.supported_locales()

    if supported == all_ids do
      # :supported_locales is not configured — all locales are
      # supported. Confirm with the user before downloading
      # everything, unless --force is set.
      confirm_all_locales(all_ids, opts[:force])
    else
      supported
    end
  end

  defp confirm_all_locales(all_ids, true = _force), do: all_ids

  defp confirm_all_locales(all_ids, _no_force) do
    count = length(all_ids)

    Mix.shell().info(
      ":supported_locales is not configured, so all #{count} CLDR locales " <>
        "will be downloaded.\n\n" <>
        "If this is intentional, enter \"y\" to continue.\n" <>
        "Otherwise, enter \"n\" and configure :supported_locales in your " <>
        "application environment to limit the download to the locales " <>
        "your application needs.\n"
    )

    if Mix.shell().yes?("Download all #{count} locales?") do
      all_ids
    else
      Mix.shell().info("Aborted. Configure :supported_locales and re-run.")
      []
    end
  end

  defp download_locales(locales) do
    cache_dir = Provider.locale_cache_dir()
    count = length(locales)

    {:ok, message} =
      Localize.Message.format(
        ".input {$count :number}\n.match $count\n1 {{Downloading {$count} locale to {$dir}}}\n* {{Downloading {$count} locales to {$dir}}}",
        %{"count" => count, "dir" => cache_dir}
      )

    Mix.shell().info(message)
    Mix.shell().info("Version: #{Localize.version()}\n")

    {downloaded, skipped, failures} =
      locales
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0, 0}, fn {locale_id, index}, {ok, skip, fail} ->
        prefix = "[#{index}/#{length(locales)}]"

        case download_and_store(locale_id) do
          {:ok, path, size} ->
            Mix.shell().info("#{prefix} #{locale_id} (#{format_size(size)}) -> #{path}")
            {ok + 1, skip, fail}

          {:skip, path} ->
            Mix.shell().info("#{prefix} #{locale_id} (current) #{path}")
            {ok, skip + 1, fail}

          {:error, reason} ->
            Mix.shell().error("#{prefix} #{locale_id} FAILED: #{reason}")
            {ok, skip, fail + 1}
        end
      end)

    Mix.shell().info(
      "\nDone. #{downloaded} downloaded, #{skipped} already current, #{failures} failed."
    )

    if failures > 0 do
      System.halt(1)
    end
  end

  defp download_and_store(locale_id) do
    case Cache.get(locale_id) do
      {:ok, _locale_data} ->
        # Already cached and version matches — skip the download.
        {:skip, Cache.path(locale_id)}

      {:error, _stale_or_missing} ->
        # Missing or stale — download a fresh copy.
        do_download(locale_id)
    end
  end

  defp do_download(locale_id) do
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
