defmodule Mix.Tasks.Localize.VerifyLocales do
  @shortdoc "Verifies locale ETF files against the bundled hash manifest"

  @moduledoc """
  Verifies a directory of locale ETF files against the SHA-256 manifest
  bundled with this release of Localize.

  Localize verifies every downloaded locale file against
  `priv/localize/locale_hashes.etf` before decoding it, so a file whose bytes
  do not match is refused at download time. This task runs the same check
  ahead of time, over files already on disk, and names the ones that differ.

  The manifest pins more than transport integrity: it pins the data to the
  shape this release's accessors were written against. A locale file built
  from a different CLDR release, or by a pipeline from a different Localize
  version, hashes differently even when it decodes cleanly — and loading it
  surfaces much later as a missing key deep inside a formatting call. That is
  why the hashes are not overridable, and why this task reports the CLDR
  repository tag the reference files were generated from: a file that does not
  verify can be rebuilt from, or replaced by, data from that exact tag.

  ## Usage

      mix localize.verify_locales

  Verifies the configured locale cache directory, the one
  `Localize.Locale.Provider.locale_cache_dir/0` returns and
  `mix localize.download_locales` writes to.

      mix localize.verify_locales path/to/locales

  Verifies the given directory instead.

      mix localize.verify_locales --quiet

  Reports only the files that fail, and the summary, which suits a CI step.

  ## Output

  The report opens with the provenance of the manifest it checks against —
  this build's Localize and CLDR versions, the CLDR repository tag the
  reference data was generated from, and the CDN those reference files are
  published to:

      Localize version:  1.3.0
      CLDR version:      49.0.0
      CLDR repo tag:     release-49-beta3
      Reference CDN:     https://elixir-localize.com/locales/v49.0.0

  Each `.etf` file in the directory is then one of:

  * `ok` — the bytes match the manifest entry for that locale.

  * `MISMATCH` — the locale is in the manifest but the bytes differ. The file
    was not produced by the pipeline this release was built from.

  * `NOT IN MANIFEST` — no manifest entry exists for the file's locale, so the
    file is not a locale this release knows.

  Manifest entries with no corresponding file are counted but not listed: a
  cache holding only the locales an application configured is the normal case.

  ## Exit status

  Exits `0` when every file verifies, and non-zero when any file mismatches or
  is absent from the manifest, so the task can gate a build.

  ## Mirroring the reference files

  A deployment that must not reach the Localize CDN at build time can mirror
  the published files rather than rebuild them. `mix localize.download_locales`
  writes verified copies into the cache directory, which can then be committed,
  cached, or served from elsewhere via `:locale_base_url`. Because the bytes are
  the published bytes, this task and the runtime check both pass unchanged.

  """

  use Mix.Task

  alias Localize.Locale.Provider

  @requirements ["compile", "loadconfig"]

  @impl Mix.Task
  def run(args) do
    {:ok, _started} = Application.ensure_all_started(:localize)

    {options, directories} = OptionParser.parse!(args, strict: [quiet: :boolean])
    directory = directory_to_verify(directories)
    hashes = manifest()

    report_provenance()

    results = verify_directory(directory, hashes)
    Enum.each(results, &report_result(&1, Keyword.get(options, :quiet, false)))
    report_summary(results, directory, hashes)
  end

  defp directory_to_verify([]), do: Provider.locale_cache_dir()
  defp directory_to_verify([directory]), do: directory

  defp directory_to_verify(directories) do
    Mix.raise("expected at most one directory, got: #{Enum.join(directories, ", ")}")
  end

  # Verification is only meaningful against a manifest. A build from source has
  # none — it is generated at release time — and the runtime check skips
  # verification in that case. Reporting every file as fine would invert this
  # task's purpose, so refuse instead.
  defp manifest do
    case Provider.locale_hashes() do
      :no_manifest ->
        Mix.raise(
          "no locale hash manifest found at priv/localize/locale_hashes.etf. " <>
            "The manifest is generated at release time and ships with the hex " <>
            "package; it is absent when Localize is built from source as a git " <>
            "or path dependency, and there is nothing to verify against."
        )

      hashes ->
        hashes
    end
  end

  defp report_provenance do
    Mix.shell().info("""
    Localize version:  #{package_version()}
    CLDR version:      #{Localize.version()}
    CLDR repo tag:     #{Localize.cldr_repo_ref() || "not recorded"}
    Reference CDN:     #{Provider.base_url()}/#{Provider.version_segment()}
    """)
  end

  defp package_version do
    case Application.spec(:localize, :vsn) do
      nil -> "unknown"
      vsn -> List.to_string(vsn)
    end
  end

  # The manifest is keyed by locale id atoms. Comparing by file name instead
  # means a directory holding a file named after something that is not a
  # locale never interns an atom for it.
  defp verify_directory(directory, hashes) do
    expected = Map.new(hashes, fn {locale_id, hash} -> {Atom.to_string(locale_id), hash} end)

    directory
    |> locale_files()
    |> Enum.map(&classify(&1, expected))
  end

  defp locale_files(directory) do
    case File.dir?(directory) do
      true ->
        directory
        |> Path.join("*.etf")
        |> Path.wildcard()
        |> Enum.sort()
        |> refuse_empty(directory)

      false ->
        Mix.raise("#{directory} is not a directory")
    end
  end

  defp refuse_empty([], directory) do
    Mix.raise(
      "no .etf files found in #{directory}. " <>
        "Run `mix localize.download_locales` to populate the locale cache."
    )
  end

  defp refuse_empty(files, _directory), do: files

  defp classify(path, expected) do
    name = Path.basename(path, ".etf")
    actual = :crypto.hash(:sha256, File.read!(path))

    {status(Map.get(expected, name), actual), name, path}
  end

  defp status(nil, _actual), do: :not_in_manifest
  defp status(same, same), do: :ok
  defp status(_expected, _actual), do: :mismatch

  defp report_result({:ok, _name, _path}, true), do: :ok

  defp report_result({:ok, name, _path}, _quiet),
    do: Mix.shell().info("  ok               #{name}")

  defp report_result({:mismatch, name, path}, _quiet) do
    Mix.shell().error("  MISMATCH         #{name}  (#{path})")
  end

  defp report_result({:not_in_manifest, name, path}, _quiet) do
    Mix.shell().error("  NOT IN MANIFEST  #{name}  (#{path})")
  end

  defp report_summary(results, directory, hashes) do
    tally = Enum.frequencies_by(results, fn {status, _name, _path} -> status end)
    failures = Map.get(tally, :mismatch, 0) + Map.get(tally, :not_in_manifest, 0)

    Mix.shell().info("""

    #{length(results)} file(s) in #{directory}
      #{Map.get(tally, :ok, 0)} verified
      #{Map.get(tally, :mismatch, 0)} mismatched
      #{Map.get(tally, :not_in_manifest, 0)} not in manifest
    #{absent_count(results, hashes)} of #{map_size(hashes)} manifest entries have no file here\
    """)

    report_outcome(failures, directory)
  end

  defp absent_count(results, hashes) do
    present = MapSet.new(results, fn {_status, name, _path} -> name end)

    Enum.count(hashes, fn {locale_id, _hash} ->
      not MapSet.member?(present, Atom.to_string(locale_id))
    end)
  end

  defp report_outcome(0, _directory) do
    Mix.shell().info("\nAll files verify against the bundled manifest.")
  end

  # The tag is the actionable part of a failure: it names the source the
  # reference bytes came from, so a mismatch can be resolved by replacing the
  # files or by rebuilding from that exact tag.
  defp report_outcome(failures, directory) do
    Mix.raise("""
    #{failures} file(s) in #{directory} do not match the bundled manifest.

    These bytes were not produced by the pipeline this release of Localize was
    built from. The reference files were generated from:

        CLDR repo tag:  #{Localize.cldr_repo_ref() || "(not recorded)"}
        Localize:       #{package_version()}
        Published at:   #{Provider.base_url()}/#{Provider.version_segment()}

    Replace them with the published files:

        mix localize.download_locales --force

    Or, if you generate the data yourself, generate it from that CLDR tag with
    that version of Localize. Data built from any other CLDR tag hashes
    differently, and the hashes are not overridable: the manifest pins the data
    to the shape this release's accessors expect, so a file that hashes
    differently can decode cleanly and still fail much later as a missing key
    inside a formatting call.
    """)
  end
end
