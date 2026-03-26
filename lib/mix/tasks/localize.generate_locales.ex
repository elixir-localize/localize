defmodule Mix.Tasks.Localize.GenerateLocales do
  @shortdoc "Generates CLDR locale data ETF files"

  @moduledoc """
  Generates locale data ETF files from raw CLDR source data.

  Consolidates locale-specific JSON and XML files, normalizes the
  data, applies struct transforms, and writes ETF files to
  `priv/localize/locales/`.

  ## Usage

      mix localize.generate_locales

  Generates all locale files.

      mix localize.generate_locales en fr de

  Generates only the specified locales.

  ## Configuration

  The source data directory is read from the `CLDR_PRODUCTION_DATA`
  environment variable, falling back to `../cldr_production_data`.

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

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
