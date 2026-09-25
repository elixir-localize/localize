defmodule Mix.Tasks.Localize.GenerateLocales do
  @shortdoc "Generates CLDR locale data ETF files"

  @moduledoc """
  Generates locale data ETF files from raw CLDR source data.

  Consolidates locale-specific JSON and XML files, normalizes the
  data, applies struct transforms, and writes ETF files to
  `priv/localize/locales/`.

  The JSON is read from the cldr-json release bundle in `CLDR_PRODUCTION`
  and the subdivision XML from the CLDR repository in `CLDR_REPO`, which
  must be the sources recorded in `priv/localize/cldr_json_version` and
  `priv/localize/cldr_repo_ref`. `mix localize.fetch_sources` fetches them.

  ## Usage

      mix localize.generate_locales

  Generates all locale files.

      mix localize.generate_locales en fr de

  Generates only the specified locales.

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:localize)

    with {:error, message} <- Localize.Data.verify_sources() do
      Mix.raise(message)
    end

    case args do
      [] ->
        Localize.Data.generate_all_locales()

      locale_names ->
        output = Localize.Data.locales_output_dir()
        File.mkdir_p!(output)

        Enum.each(locale_names, fn locale ->
          Mix.shell().info("Generating #{locale}...")
          Localize.Data.Locale.generate_and_save_locale(locale)
        end)

        Mix.shell().info("Generated #{length(locale_names)} locale ETF files.")
    end
  end
end
