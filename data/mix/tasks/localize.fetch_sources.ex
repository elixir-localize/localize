defmodule Mix.Tasks.Localize.FetchSources do
  @shortdoc "Fetches the CLDR repository at the recorded ref and builds the CLDR JSON"

  @moduledoc """
  Puts the CLDR sources recorded in `priv/localize/cldr_repo_ref` in place:
  the CLDR repository at that ref in `CLDR_REPO`, and the CLDR JSON built
  from it in `CLDR_PRODUCTION`.

  The generation tasks read the sources where they sit. This task puts
  them there on a machine that lacks them, such as a new development
  machine:

  * the paths the build and generation read from the repository, at the
    recorded tag or commit, as a sparse and blobless checkout in
    `CLDR_REPO`;

  * the CLDR JSON, built from that checkout by `mix localize.build_cldr_json`
    into `CLDR_PRODUCTION`, which needs Maven and a JDK (see that task).

  A repository already at the recorded ref, and JSON already built from it
  with the current options, are left alone. A repository directory holding
  anything else is never replaced — it may be a maintainer's own checkout —
  and the task stops and says so.

  ## Usage

      mix localize.fetch_sources

  ## Configuration

  * `CLDR_REPO` — where to check the repository out. Without it, the first
    of `../cldr_repo` and `../../cldr/cldr_repo` that exists is used, or
    the former when neither does.

  * `CLDR_PRODUCTION` — where to build the JSON. Without it, the first of
    `../cldr_production_data` and `../../cldr/cldr_production_data` that
    exists is used, or the former when neither does.

  """

  use Mix.Task

  @cldr_repository "https://github.com/unicode-org/cldr.git"

  # Everything the JSON build and generation read from the repository, as
  # sparse-checkout patterns: the data under `common/`; the keyboard, seed
  # and exemplar data beside it, which CLDR's tools open at startup (a
  # missing `seed/main` stops the production step); and CLDR's tools.
  # Maven loads every module of `tools/pom.xml` into the reactor, so the
  # other modules' POMs are needed to build `cldr-code`; `cldr-code` also
  # holds `Script_Metadata.csv` and the locale matching test data.
  @repository_paths [
    "/common/",
    "/exemplars/",
    "/keyboards/",
    "/seed/",
    "/tools/pom.xml",
    "/tools/cldr-apps/pom.xml",
    "/tools/cldr-code/",
    "/tools/cldr-rdf/pom.xml"
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:localize)

    case Localize.Data.pinned_ref() do
      ref when is_binary(ref) ->
        fetch_repository(ref)
        build_json()

        case Localize.Data.verify_sources() do
          :ok ->
            Mix.shell().info(
              "CLDR sources ready: the CLDR repository at #{ref} and the JSON built from it"
            )

          {:error, message} ->
            Mix.raise(message)
        end

      nil ->
        Mix.raise("""
        No CLDR repository ref is recorded in priv/localize/cldr_repo_ref.
        `mix localize.update_cldr` records one.
        """)
    end
  end

  # ── The CLDR repository ────────────────────────────────────────

  defp fetch_repository(ref) do
    directory = Localize.Data.cldr_repo_dir()
    present = Localize.Data.repository_ref()

    cond do
      present == ref ->
        Mix.shell().info("The CLDR repository in #{directory} is already at #{ref}")

      occupied?(directory) ->
        Mix.raise("""
        #{directory} is at #{present || "no readable ref"}, not #{ref}.

        Check #{ref} out there, or point CLDR_REPO at an empty directory and run
        this again.
        """)

      true ->
        sparse_checkout(ref, directory)
    end
  end

  # A tag is fetched as a tag, so that the checkout reports it as its ref
  # just as a full clone would; a commit is fetched by its hash.
  defp sparse_checkout(ref, directory) do
    validate!(ref, ~r/^[A-Za-z0-9][A-Za-z0-9._\/-]*$/, "CLDR repository ref")
    refspec = if commit?(ref), do: ref, else: "refs/tags/#{ref}:refs/tags/#{ref}"

    Mix.shell().info("Fetching #{ref} from #{@cldr_repository}")
    File.mkdir_p!(directory)
    git!(directory, ["init", "--quiet"])
    git!(directory, ["remote", "add", "origin", @cldr_repository])
    git!(directory, ["sparse-checkout", "set", "--no-cone" | @repository_paths])
    git!(directory, ["fetch", "--quiet", "--depth", "1", "--filter=blob:none", "origin", refspec])
    git!(directory, ["checkout", "--quiet", ref])
  end

  defp commit?(ref), do: Regex.match?(~r/^[0-9a-f]{40}$/, ref)

  defp git!(directory, arguments) do
    case System.cmd("git", arguments, cd: directory, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        Mix.raise("git #{Enum.join(arguments, " ")} failed (#{status}):\n#{output}")
    end
  end

  # ── The CLDR JSON ──────────────────────────────────────────────

  defp build_json do
    directory = Localize.Data.cldr_source_dir()

    if Localize.Data.verify_sources() == :ok do
      Mix.shell().info("The CLDR JSON in #{directory} is already built from the repository")
    else
      Mix.Task.run("localize.build_cldr_json")
    end
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp occupied?(directory) do
    case File.ls(directory) do
      {:ok, entries} -> entries != []
      {:error, _absent} -> false
    end
  end

  # The recorded ref is interpolated into a refspec, so a malformed one
  # stops here rather than reaching it.
  defp validate!(value, pattern, description) do
    unless Regex.match?(pattern, value) do
      Mix.raise("The recorded #{description} #{inspect(value)} is not well formed")
    end
  end
end
