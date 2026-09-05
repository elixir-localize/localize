defmodule Mix.Tasks.Localize.GenerateSupplemental do
  @shortdoc "Generates CLDR supplemental data ETF files"

  @moduledoc """
  Generates all supplemental data ETF files from the vendored CLDR
  source data.

  Reads the vendored CLDR JSON and XML source files from
  `priv/cldr/supplemental_data/` (and related `priv/cldr/` paths),
  transforms them into the runtime format expected by
  `Localize.SupplementalData`, and writes ETF files to
  `priv/localize/supplemental_data/`.

  This task regenerates ETF files from data already vendored in the
  repository; it does not read the external CLDR production data.
  Only `mix localize.copy_sources` (run as part of
  `mix localize.update_cldr`) reads `CLDR_PRODUCTION` to refresh
  the vendored sources when moving to a new CLDR release.

  ## Usage

      mix localize.generate_supplemental

  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:localize)
    Localize.Data.generate_all()
  end
end
