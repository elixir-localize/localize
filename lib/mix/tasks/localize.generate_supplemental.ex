defmodule Mix.Tasks.Localize.GenerateSupplemental do
  @shortdoc "Generates CLDR supplemental data ETF files"

  @moduledoc """
  Generates all supplemental data ETF files from raw CLDR source data.

  Reads raw CLDR JSON and XML source files, transforms them into the
  runtime format expected by `Localize.SupplementalData`, and writes
  ETF files to `priv/localize/supplemental_data/`.

  ## Usage

      mix localize.generate_supplemental

  ## Configuration

  The source data directory is read from the `CLDR_PRODUCTION_DATA`
  environment variable, falling back to `../cldr_production_data`.

  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    Localize.Data.generate_all()
  end
end
