defmodule Mix.Tasks.Localize.CopySources do
  @shortdoc "Copies CLDR source files into the project for reproducible builds"

  @moduledoc """
  Copies raw CLDR source files into `priv/cldr/` so that the project
  contains all data needed for reproducible ETF generation.

  JSON files are copied from `CLDR_PRODUCTION_DATA`. XML files
  (supplemental and collation) are copied from `CLDR_REPO`.

  ## Usage

      mix localize.copy_sources

  Copies supplemental, collation, and locale source files.

      mix localize.copy_sources --supplemental

  Copies only supplemental and collation source files.

      mix localize.copy_sources --locales

  Copies only locale source files.

  ## Output

  * `priv/cldr/supplemental_data/` — supplemental JSON and XML files.

  * `priv/cldr/collation/` — collation XML files from CLDR_REPO.

  * `priv/cldr/locales/<locale>/` — per-locale JSON and XML files.

  * `priv/localize/version` — CLDR version string.

  ## Configuration

  * `CLDR_PRODUCTION_DATA` — path to the CLDR production data
    directory (default: `../cldr_production_data`).

  * `CLDR_REPO` — path to the Unicode CLDR repository checkout
    (default: `../cldr_repo`).

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest} =
      OptionParser.parse!(args, strict: [supplemental: :boolean, locales: :boolean])

    do_supplemental = opts[:supplemental] || (!opts[:supplemental] && !opts[:locales])
    do_locales = opts[:locales] || (!opts[:supplemental] && !opts[:locales])

    if do_supplemental do
      Localize.Data.copy_supplemental_sources()
      Localize.Data.copy_collation_sources()
      Localize.Data.copy_validity_sources()
      Localize.Data.copy_bcp47_sources()
      Localize.Data.copy_script_metadata()
    end

    if do_locales do
      Localize.Data.copy_locale_sources()
    end

    Localize.Data.write_version()
    Mix.shell().info("Done.")
  end
end
