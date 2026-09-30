defmodule Mix.Tasks.Localize.BuildCldrJson do
  @shortdoc "Builds the CLDR JSON from the CLDR repository"

  @moduledoc """
  Builds the CLDR JSON that data generation reads, from the CLDR
  repository in `CLDR_REPO` into `CLDR_PRODUCTION`, with CLDR's own tools.

  The repository is built as it is checked out, and never moved:
  `mix localize.fetch_sources` checks the recorded ref out first, and
  `mix localize.prepare_sources` runs the build when the JSON is not the
  repository's. `Localize.Data.CldrJson` describes the steps and the
  options. A build takes about ten minutes.

  ## Usage

      mix localize.build_cldr_json

  ## Requirements

  * Maven, running a JDK at least as recent as the `<java-release>` in the
    repository's `tools/pom.xml` (21 for CLDR 49). `JAVA_HOME` selects the
    JDK Maven runs.

  * Read access to the GitHub Packages registry CLDR takes ICU4J from: a
    server with the id `githubicu` in `~/.m2/settings.xml`, whose password
    is a GitHub token with the `read:packages` scope.

  ## Configuration

  * `CLDR_REPO` — the CLDR repository checkout. Without it, the first of
    `../cldr_repo` and `../../cldr/cldr_repo` that exists is used.

  * `CLDR_PRODUCTION` — where to write the JSON. Without it, the first of
    `../cldr_production_data` and `../../cldr/cldr_production_data` that
    exists is used, or the former when neither does. It is cleared first,
    and must be empty or hold CLDR JSON.

  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    repository = Localize.Data.cldr_repo_dir()
    output = Localize.Data.cldr_source_dir()

    Mix.shell().info("Building the CLDR JSON from #{repository} into #{output}")

    case Localize.Data.CldrJson.build(repository, output) do
      {:ok, stamp} ->
        Mix.shell().info(
          "Built the CLDR JSON from #{stamp["describe"]} (#{stamp["commit"]}) into #{output}"
        )

      {:error, message} ->
        Mix.raise(message)
    end
  end
end
