defmodule Mix.Tasks.Localize.DownloadInflection do
  @shortdoc "Downloads inflection data files from the Localize CDN"

  @moduledoc """
  Downloads inflection data files from the Localize CDN into the
  configured inflection data directory.

  Inflection data is optional: nothing is downloaded unless this
  task runs, and inflection functions return
  `{:error, %Localize.InflectionDataNotAvailableError{}}` for a
  locale whose data is absent. Run the task at build time (a
  Dockerfile or CI pipeline), like `mix localize.download_locales`.

  ## Usage

      mix localize.download_inflection

  Downloads the configured `:supported_locales` (intersected with
  the languages the inflection data covers).

      mix localize.download_inflection en fr de ru

  Downloads the specified locales.

      mix localize.download_inflection --all

  Downloads every inflection-supported language.

      mix localize.download_inflection --force

  Re-downloads files that already exist in the data directory.

      mix localize.download_inflection --prune

  Removes the directories of superseded data versions once the
  current version has downloaded.

  ## Output directory

  Files are written to `Localize.Inflection.DataDir.dir/0`; see
  that module for the `:otp_app` / `:inflection_data_dir`
  configuration forms.

  That directory carries the data version, so each version holds its
  own artifacts and a file of an earlier version is never read in
  place of a current one. The directories of superseded versions
  survive an upgrade; the task names them when it finds them, and
  `--prune` removes them.

  Every download is verified against the SHA-256 manifest shipped
  in the package before it is written.

  """

  use Mix.Task

  alias Localize.Inflection.{DataDir, Locale, Provider}

  @requirements ["compile", "loadconfig"]

  # A data version directory, as `Localize.Inflection.Provider.data_version/0`
  # names it: twelve hex digits of the upstream commit and the pipeline
  # revision. Pruning is held to directories of this shape so a data
  # directory shared with anything else keeps it.
  @version_dir ~r/^[0-9a-f]{12}-r\d+$/

  @impl Mix.Task
  def run(args) do
    {:ok, _started} = Application.ensure_all_started(:localize)

    {options, locale_args} =
      OptionParser.parse!(args, strict: [all: :boolean, force: :boolean, prune: :boolean])

    force? = options[:force] || false
    locales = resolve_locales(options, locale_args)

    Mix.shell().info(
      "Downloading inflection data (#{Provider.data_version()}) for #{length(locales)} locales to #{DataDir.dir()}"
    )

    case download_all(locales, force?) do
      0 ->
        report_superseded(options[:prune] || false)
        Mix.shell().info("Done.")

      failures ->
        Mix.shell().error("#{failures} download(s) failed.")
        System.halt(1)
    end
  end

  @doc """
  Downloads inflection data for the inflection-supported languages
  among `locale_names`.

  Accepts locale identifiers in any form; regional locales map to
  their parent language (`en-AU` → `en`) and locales the inflection
  project does not support are skipped. Returns the number of failed
  downloads (0 on success). Shared with
  `mix localize.download_locales`, which downloads inflection data
  alongside the locale data so one command provisions both.

  """
  def download_for(locale_names, force? \\ false) do
    download_all(supported_languages(locale_names), force?)
  end

  defp download_all(languages, force?) do
    File.mkdir_p!(DataDir.dir())

    Enum.count(languages, fn language ->
      download(language <> ".etf", force?) == :error
    end)
  end

  # Each data version takes its own directory, so the directories of
  # earlier versions outlive an upgrade holding artifacts nothing reads.
  # Removing them is explicit: the task names them, and `--prune` is the
  # instruction to delete them.
  defp report_superseded(prune?) do
    case superseded_dirs() do
      [] ->
        :ok

      dirs when prune? ->
        Enum.each(dirs, &File.rm_rf!/1)
        Mix.shell().info("Pruned #{length(dirs)} superseded data version(s).")

      dirs ->
        Mix.shell().info(
          "#{length(dirs)} superseded data version(s) in #{DataDir.base_dir()}: " <>
            Enum.map_join(dirs, ", ", &Path.basename/1) <> ". Remove them with --prune."
        )
    end
  end

  defp superseded_dirs do
    current = DataDir.dir()

    DataDir.base_dir()
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(fn path ->
      path != current and File.dir?(path) and Regex.match?(@version_dir, Path.basename(path))
    end)
    |> Enum.sort()
  end

  defp resolve_locales(options, locale_args) do
    supported = Locale.supported()

    cond do
      locale_args != [] ->
        supported_languages(locale_args)

      options[:all] ->
        supported

      true ->
        configured = Enum.map(Localize.supported_locales(), &to_string/1)

        case Enum.filter(supported, &(&1 in configured)) do
          [] -> supported
          restricted -> restricted
        end
    end
  end

  defp supported_languages(locale_names) do
    supported = Locale.supported()

    locale_names
    |> Enum.map(&Locale.normalize/1)
    |> Enum.map(&language/1)
    |> Enum.uniq()
    |> Enum.filter(&(&1 in supported))
  end

  defp language(internal) do
    internal |> String.split("_") |> List.first()
  end

  defp download(file_name, force?) do
    destination = DataDir.path(file_name)

    if not force? and File.exists?(destination) do
      Mix.shell().info("  #{file_name} (present)")
      :ok
    else
      case Provider.download_file(file_name) do
        {:ok, body} ->
          File.write!(destination, body)
          Mix.shell().info("  #{file_name} (#{format_size(byte_size(body))})")
          :ok

        {:error, exception} ->
          Mix.shell().error("  #{file_name} FAILED: #{Exception.message(exception)}")
          :error
      end
    end
  end

  defp format_size(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_size(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{bytes} B"
end
