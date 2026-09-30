defmodule Mix.Tasks.Localize.PrepareSources do
  @shortdoc "Builds the CLDR JSON, records the CLDR ref to generate from and copies CLDR's test data"

  @moduledoc """
  Adopts the CLDR repository in `CLDR_REPO`, as it is checked out, for data
  generation.

  The generation tasks read the sources where they sit rather than from a
  copy in the project: the repository itself, and the JSON built from it
  into `CLDR_PRODUCTION`. This task builds the JSON with
  `mix localize.build_cldr_json` unless it is already the repository's, and
  records the repository's ref in `priv/localize/cldr_repo_ref`; the
  generation tasks refuse a repository at another ref, or JSON not built
  from it. It also writes the CLDR version to `priv/localize/version`,
  fetches the matching Unicode Character Database files and copies CLDR's
  conformance test data into `test/support/data/`.

  `mix localize.update_cldr` runs it first.

  ## Usage

      mix localize.prepare_sources

  ## Configuration

  * `CLDR_REPO` — path to the Unicode CLDR repository checkout. Without it,
    the first of `../cldr_repo` and `../../cldr/cldr_repo` that exists is
    used.

  * `CLDR_PRODUCTION` — where the JSON is built. Without it, the first of
    `../cldr_production_data` and `../../cldr/cldr_production_data` that
    exists is used, or the former when neither does.

  `CLDR_REPO` pointing at a directory that does not exist stops the task
  before it changes anything.

  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:localize)

    verify_repository_dir!(Localize.Data.cldr_repo_dir())

    if Localize.Data.json_built_from_repository?() do
      Mix.shell().info(
        "The CLDR JSON in #{Localize.Data.cldr_source_dir()} is already built from the repository"
      )
    else
      Mix.Task.run("localize.build_cldr_json")
    end

    case Localize.Data.record_sources() do
      {:ok, ref} -> Mix.shell().info("Recorded the CLDR repository ref #{ref}")
      {:error, message} -> Mix.raise(message)
    end

    Localize.Data.write_version()

    case Localize.Data.UnicodeData.ensure_ucd_files() do
      {:ok, _} -> :ok
      {:error, reason} -> Mix.raise(to_string(reason))
    end

    Localize.Data.copy_test_data()
    Localize.Data.copy_rbnf_test_data()

    Mix.shell().info("Done.")
  end

  # Generation reads thousands of files, so a wrong repository directory
  # otherwise surfaces partway through, naming a file rather than the
  # setting that sent it there.
  defp verify_repository_dir!(path) do
    unless File.dir?(path) do
      Mix.raise("""
      CLDR_REPO directory not found at #{path}

      Set CLDR_REPO to a checkout of the CLDR repository, or place one where
      the defaults look for it: beside this project, or in a `cldr` directory
      beside it. For example:

          CLDR_REPO=$HOME/Development/cldr/cldr_repo mix localize.prepare_sources

      `mix localize.fetch_sources` checks out the recorded ref.
      """)
    end
  end
end
