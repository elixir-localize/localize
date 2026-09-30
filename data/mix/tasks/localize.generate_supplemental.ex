defmodule Mix.Tasks.Localize.GenerateSupplemental do
  @shortdoc "Generates CLDR supplemental data ETF files"

  @moduledoc """
  Generates all supplemental data ETF files from the CLDR sources.

  Reads the supplemental JSON from `CLDR_PRODUCTION` and the XML from the
  CLDR repository in `CLDR_REPO`, transforms them into the runtime format
  expected by the supplemental data accessors, and writes ETF files to
  `priv/localize/supplemental_data/`.

  The repository must be at the ref recorded in
  `priv/localize/cldr_repo_ref`, and the JSON built from it with the
  current options: `mix localize.fetch_sources` puts both in place, and
  `mix localize.update_cldr` records a new ref when moving to a new CLDR
  release.

  ## Usage

      mix localize.generate_supplemental

  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:localize)

    case Localize.Data.verify_sources() do
      :ok -> Localize.Data.generate_all()
      {:error, message} -> Mix.raise(message)
    end
  end
end
