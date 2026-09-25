defmodule Mix.Tasks.Localize.FetchSources do
  @shortdoc "Fetches the CLDR sources the committed data was generated from"

  @moduledoc """
  Fetches the CLDR sources recorded in `priv/localize/cldr_json_version`
  and `priv/localize/cldr_repo_ref`.

  The generation tasks read the sources where they sit, in
  `CLDR_PRODUCTION` and `CLDR_REPO`. This task puts the recorded pair there
  on a machine that lacks them, such as CI or a new development machine:

  * the cldr-json release zip, from the release of that name on
    `unicode-org/cldr-json`, unpacked into `CLDR_PRODUCTION`;

  * the paths the pipeline reads from the CLDR repository, at the recorded
    tag or commit, as a sparse and blobless checkout in `CLDR_REPO`.

  A source already present at the recorded version is left alone. A
  directory holding anything else is never replaced — it may be a
  maintainer's own checkout — and the task stops and says so.

  ## Usage

      mix localize.fetch_sources

  ## Configuration

  * `CLDR_PRODUCTION` — where to unpack the release. Without it, the first
    of `../cldr_production_data` and `../../cldr/cldr_production_data`
    that exists is used, or the former when neither does.

  * `CLDR_REPO` — where to check the repository out. Without it, the first
    of `../cldr_repo` and `../../cldr/cldr_repo` that exists is used, or
    the former when neither does.

  """

  use Mix.Task

  @cldr_json_releases "https://github.com/unicode-org/cldr-json/releases/download"
  @cldr_repository "https://github.com/unicode-org/cldr.git"

  # Everything generation and `mix localize.prepare_sources` read from the
  # repository, as sparse-checkout patterns.
  @repository_paths [
    "/common/bcp47/",
    "/common/collation/",
    "/common/subdivisions/",
    "/common/supplemental/",
    "/common/testData/",
    "/common/uca/",
    "/common/validity/",
    "/tools/cldr-code/src/main/resources/org/unicode/cldr/util/data/Script_Metadata.csv",
    "/tools/cldr-code/src/test/resources/org/unicode/cldr/unittest/data/localeDistanceTest.txt",
    "/tools/cldr-code/src/test/resources/org/unicode/cldr/unittest/data/localeMatcherTest.txt"
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:localize)

    case Localize.Data.pinned_sources() do
      {version, ref} when is_binary(version) and is_binary(ref) ->
        fetch_bundle(version)
        fetch_repository(ref)

        case Localize.Data.verify_sources() do
          :ok ->
            Mix.shell().info(
              "CLDR sources ready: cldr-json #{version}, CLDR repository at #{ref}"
            )

          {:error, message} ->
            Mix.raise(message)
        end

      _unrecorded ->
        Mix.raise("""
        No CLDR sources are recorded in priv/localize/cldr_json_version and
        priv/localize/cldr_repo_ref. `mix localize.update_cldr` records them.
        """)
    end
  end

  # ── The cldr-json release ──────────────────────────────────────

  defp fetch_bundle(version) do
    directory = Localize.Data.cldr_source_dir()
    {present, _ref} = Localize.Data.current_sources()

    cond do
      present == version ->
        Mix.shell().info("cldr-json #{version} is already in #{directory}")

      occupied?(directory) ->
        Mix.raise("""
        #{directory} holds #{present || "something other than a cldr-json release"}, \
        not cldr-json #{version}.

        Move it aside, or point CLDR_PRODUCTION at an empty directory, and run
        this again.
        """)

      true ->
        download_bundle(version, directory)
    end
  end

  # GitHub serves a release asset through a redirect to its asset host, which
  # `Localize.Utils.Http` deliberately never follows — it fetches only fixed
  # CDN locations. curl follows it with the right certificate checks for each
  # host, retries, and streams the 75 MB to disk rather than into memory.
  defp download_bundle(version, directory) do
    validate!(version, ~r/^\d+\.\d+\.\d+(-[A-Za-z0-9]+)?$/, "cldr-json version")
    url = "#{@cldr_json_releases}/#{version}/cldr-#{version}-json-full.zip"
    zip = Path.join(Path.dirname(directory), "cldr-#{version}-json-full.zip")

    unless System.find_executable("curl") do
      Mix.raise("curl is needed to download #{url}")
    end

    Mix.shell().info("Downloading #{url}")
    File.mkdir_p!(directory)

    arguments = ["--fail", "--location", "--silent", "--show-error", "--retry", "3"]

    case System.cmd("curl", arguments ++ ["--output", zip, url], stderr_to_stdout: true) do
      {_output, 0} ->
        unpack(zip, url, directory)
        File.rm!(zip)

      {output, status} ->
        _ = File.rm(zip)
        Mix.raise("Could not download #{url} (curl exited #{status}):\n#{output}")
    end
  end

  defp unpack(zip, url, directory) do
    case :zip.unzip(String.to_charlist(zip), cwd: String.to_charlist(directory)) do
      {:ok, files} ->
        Mix.shell().info("Unpacked #{length(files)} files into #{directory}")

      {:error, reason} ->
        Mix.raise("Could not unpack #{url}: #{inspect(reason)}")
    end
  end

  # ── The CLDR repository ────────────────────────────────────────

  defp fetch_repository(ref) do
    directory = Localize.Data.cldr_repo_dir()
    {_version, present} = Localize.Data.current_sources()

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

  # ── Helpers ────────────────────────────────────────────────────

  defp occupied?(directory) do
    case File.ls(directory) do
      {:ok, entries} -> entries != []
      {:error, _absent} -> false
    end
  end

  # The recorded values are interpolated into a URL and a refspec, so a
  # malformed one stops here rather than reaching either.
  defp validate!(value, pattern, description) do
    unless Regex.match?(pattern, value) do
      Mix.raise("The recorded #{description} #{inspect(value)} is not well formed")
    end
  end
end
