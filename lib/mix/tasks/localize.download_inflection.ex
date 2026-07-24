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

  ## Output directory

  Files are written to `Localize.Inflection.DataDir.dir/0`; see
  that module for the `:otp_app` / `:inflection_data_dir`
  configuration forms.

  Every download is verified against the SHA-256 manifest shipped
  in the package before it is written.

  """

  use Mix.Task

  alias Localize.Inflection.{DataDir, Locale, Provider}

  @requirements ["compile", "loadconfig"]

  @impl Mix.Task
  def run(args) do
    {:ok, _started} = Application.ensure_all_started(:localize)

    {options, locale_args} = OptionParser.parse!(args, strict: [all: :boolean, force: :boolean])
    force? = options[:force] || false
    locales = resolve_locales(options, locale_args)

    Mix.shell().info(
      "Downloading inflection data (#{Provider.data_version()}) for #{length(locales)} locales to #{DataDir.dir()}"
    )

    File.mkdir_p!(DataDir.dir())

    failures =
      Enum.count(locales, fn locale ->
        download(locale <> ".etf", force?) == :error
      end) + if download_pronouns(force?) == :error, do: 1, else: 0

    if failures > 0 do
      Mix.shell().error("#{failures} download(s) failed.")
      System.halt(1)
    else
      Mix.shell().info("Done.")
    end
  end

  defp resolve_locales(options, locale_args) do
    supported = Locale.supported()

    cond do
      locale_args != [] ->
        locale_args
        |> Enum.map(&Locale.normalize/1)
        |> Enum.map(&language/1)
        |> Enum.uniq()
        |> Enum.filter(&(&1 in supported))

      options[:all] ->
        supported

      true ->
        configured = Localize.supported_locales()

        case Enum.filter(supported, &(String.to_atom(&1) in configured)) do
          [] -> supported
          restricted -> restricted
        end
    end
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

  # The pronoun tables travel as a single pack and are unpacked
  # into the individual files the runtime reads.
  defp download_pronouns(force?) do
    if not force? and File.exists?(DataDir.path("pronoun_en.csv")) do
      Mix.shell().info("  pronoun tables (present)")
      :ok
    else
      case Provider.download_file("pronouns.etf") do
        {:ok, body} ->
          body |> :erlang.binary_to_term() |> Provider.unpack_pronouns()
          Mix.shell().info("  pronoun tables (#{format_size(byte_size(body))})")
          :ok

        {:error, exception} ->
          Mix.shell().error("  pronouns.etf FAILED: #{Exception.message(exception)}")
          :error
      end
    end
  end

  defp format_size(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_size(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{bytes} B"
end
