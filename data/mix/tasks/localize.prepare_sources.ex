defmodule Mix.Tasks.Localize.PrepareSources do
  @shortdoc "Records the CLDR sources to generate from and copies CLDR's test data"

  @moduledoc """
  Adopts the CLDR sources in `CLDR_PRODUCTION` and `CLDR_REPO` for data
  generation.

  The generation tasks read the sources where they sit rather than from a
  copy in the project. This task records which cldr-json release and which
  CLDR repository ref they are, in `priv/localize/cldr_json_version` and
  `priv/localize/cldr_repo_ref`, and the generation tasks refuse sources
  that differ from what is recorded. It also writes the CLDR version to
  `priv/localize/version`, fetches the matching Unicode Character Database
  files and copies CLDR's conformance test data into `test/support/data/`.

  `mix localize.update_cldr` runs it first.

  ## Usage

      mix localize.prepare_sources

  ## Configuration

  * `CLDR_PRODUCTION` — path to the cldr-json release bundle. Without it,
    the first of `../cldr_production_data` and
    `../../cldr/cldr_production_data` that exists is used.

  * `CLDR_REPO` — path to the Unicode CLDR repository checkout. Without it,
    the first of `../cldr_repo` and `../../cldr/cldr_repo` that exists is
    used.

  Either variable pointing at a directory that does not exist stops the
  task before it changes anything, and so does a pre-release bundle beside
  a repository that is not at that release's tag.

  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:localize)

    verify_source_dir!("CLDR_PRODUCTION", Localize.Data.cldr_source_dir())
    verify_source_dir!("CLDR_REPO", Localize.Data.cldr_repo_dir())
    verify_pre_release_halves_agree!()

    case Localize.Data.record_sources() do
      {:ok, {version, ref}} ->
        Mix.shell().info("Recorded CLDR sources: cldr-json #{version}, CLDR repository at #{ref}")

      {:error, message} ->
        Mix.raise(message)
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

  # Generation reads thousands of files, so a wrong source directory
  # otherwise surfaces partway through, naming a file rather than the
  # setting that sent it there.
  defp verify_source_dir!(variable, path) do
    unless File.dir?(path) do
      Mix.raise("""
      #{variable} directory not found at #{path}

      Set #{variable} to the directory holding the CLDR sources, or place the
      checkouts where the defaults look for them: beside this project, or in
      a `cldr` directory beside it. For example:

          #{variable}=$HOME/Development/cldr/#{Path.basename(path)} mix localize.prepare_sources

      `mix localize.fetch_sources` fetches a recorded pair, and
      `scripts/build_cldr_production_data` builds production data from a
      CLDR commit that has no published release.
      """)
    end
  end

  # The JSON half of the sources comes from CLDR_PRODUCTION and the XML half
  # from CLDR_REPO, and nothing ties the two together. `aliases.json` records
  # only the major version — "49" for alpha2, beta1 and final alike — so a
  # beta1 zip unpacked beside a repo checkout sitting on some other commit
  # produces a silently mixed build that is very hard to explain later.
  #
  # The cldr-json packages carry the precise pre-release in their
  # `package.json`, which is the discriminator that makes the check possible.
  # It is enforced only for a pre-release, where the data churns between tags
  # and the halves can diverge meaningfully; a locally built SNAPSHOT already
  # had its checkout positioned by `scripts/build_cldr_production_data`, and
  # cldr-json also publishes packaging-only patches such as 48.2.1 that have
  # no corresponding CLDR tag at all.
  defp verify_pre_release_halves_agree! do
    {version, ref} = Localize.Data.current_sources()

    case expected_tag(version) do
      nil ->
        report_source_halves(version, ref)

      ^ref ->
        :ok

      expected ->
        Mix.raise("""
        CLDR source halves disagree.

          CLDR_PRODUCTION is #{version}, so CLDR_REPO should be at #{expected}
          CLDR_REPO is at #{ref || "an unknown commit"}

        The JSON locale data would be #{version} while the collation, validity,
        bcp47 and subdivision XML came from somewhere else. Check the tag out:

            git -C #{Localize.Data.cldr_repo_dir()} checkout #{expected}
        """)
    end
  end

  # `49.0.0-BETA1` is tagged `release-49-beta1`, and a point release's
  # `48.2.0-BETA2` is tagged `release-48-2-beta2`. A re-spin repackages the
  # same data under a trailing letter, so `48.2.0-BETA0b` pairs with
  # `release-48-2-beta0`.
  defp expected_tag(version) when is_binary(version) do
    case Regex.run(~r/^(\d+)\.(\d+)\.\d+-([A-Za-z]+\d+)[a-z]?$/, version) do
      [_match, major, "0", qualifier] ->
        "release-#{major}-#{String.downcase(qualifier)}"

      [_match, major, minor, qualifier] ->
        "release-#{major}-#{minor}-#{String.downcase(qualifier)}"

      nil ->
        nil
    end
  end

  defp expected_tag(_version), do: nil

  # A locally built SNAPSHOT carries no precise version to check against, and
  # the checkout it was built from can move afterwards — so the pairing is
  # reported rather than silently accepted.
  defp report_source_halves(version, ref) do
    Mix.shell().info(
      "CLDR sources: #{version || "unknown"} JSON from " <>
        "#{Localize.Data.cldr_source_dir()}, XML from " <>
        "#{Localize.Data.cldr_repo_dir()} at #{ref || "an unknown commit"}"
    )
  end
end
