defmodule Localize.Data do
  @moduledoc """
  Generates CLDR data files for consumption by the `Localize` library.

  This module provides reproducible generation of all ETF files used by
  `Localize` at runtime. It reads raw CLDR JSON and XML source files,
  transforms them into the expected runtime format, and writes ETF
  (Erlang Term Format) files.

  ## Sources

  The sources are read where they sit, never copied into the project:

  * `CLDR_PRODUCTION` — the cldr-json release bundle: locale and
    supplemental JSON, and the RBNF rule files.

  * `CLDR_REPO` — the CLDR repository: supplemental, bcp47, validity,
    collation and subdivision XML, `FractionalUCA.txt` and
    `Script_Metadata.csv`.

  `priv/localize/cldr_json_version` and `priv/localize/cldr_repo_ref`
  record the release and the ref the committed data was generated from,
  and generation refuses sources that disagree with them. See
  `cldr_source_dir/0` and `cldr_repo_dir/0` for where the two are looked
  for.

  ## Outputs

  * `priv/localize/supplemental_data/` — generated ETF supplemental
    data files.

  * `priv/localize/locales/` — generated ETF locale files.

  * `priv/localize/version` — plain text file with the CLDR version.

  """

  @dialyzer {:nowarn_function, write_version: 0}
  @dialyzer {:nowarn_function, cldr_source_dir: 0}
  @dialyzer {:nowarn_function, cldr_repo_dir: 0}
  @dialyzer {:nowarn_function, read_json: 1}

  @supplemental_etf_dir "priv/localize/supplemental_data"
  @external_sources_dir "priv/external_sources"
  @version_file "priv/localize/version"
  @cldr_json_version_file "priv/localize/cldr_json_version"
  @cldr_repo_ref_file "priv/localize/cldr_repo_ref"

  # Supplemental JSON is read from the bundle's `cldr-core/supplemental/`,
  # except for the files named here, which sit elsewhere in it.
  @supplemental_json_paths %{
    "coverageLevels.json" => "cldr-core/coverageLevels.json"
  }

  # Test data files from CLDR_REPO → test/support/data/
  @test_data_dir "test/support/data"
  @test_data_files [
    {"common/testData/localeIdentifiers/localeCanonicalization.txt",
     "locale_canonicalization.txt"},
    {"common/testData/localeIdentifiers/likelySubtags.txt", "likely_subtags_test_data.txt"},
    {"common/testData/localeIdentifiers/localeDisplayName.txt", "locale_display_names.txt"},
    {"tools/cldr-code/src/test/resources/org/unicode/cldr/unittest/data/localeDistanceTest.txt",
     "locale_distance_test_data.txt"},
    {"tools/cldr-code/src/test/resources/org/unicode/cldr/unittest/data/localeMatcherTest.txt",
     "locale_matching_test_data.txt"},
    {"common/testData/datetime/datetime.json", "date_time_formatting.json"},
    {"common/testData/datetime/skeletons.tsv", "skeleton_test_data.tsv"},
    {"common/testData/datetime/skeletons_all_locales.tsv", "skeleton_all_locales_test_data.tsv"},
    {"common/testData/datetime/skeletons_all_skeletons.tsv",
     "skeleton_all_skeletons_test_data.tsv"},
    {"common/testData/datetime/skeletons_random_5percent.tsv",
     "skeleton_random_5percent_test_data.tsv"},
    {"common/testData/decimal/decimals.tsv", "decimal_test_data.tsv"},
    {"common/testData/decimal/decimals_modern_locales.tsv",
     "decimal_modern_locales_test_data.tsv"},
    {"common/testData/decimal/decimals_extended_numbers.tsv",
     "decimal_extended_numbers_test_data.tsv"},
    {"common/testData/units/unitsTest.txt", "conversion_test_data.txt"},
    {"common/testData/units/unitPreferencesTest.txt", "preference_test_data.txt"},
    {"common/testData/units/unitLocalePreferencesTest.txt",
     "unit_locale_preference_test_data.txt"},
    {"common/uca/CollationTest_CLDR_NON_IGNORABLE_SHORT.txt",
     "CollationTest_CLDR_NON_IGNORABLE_SHORT.txt"},
    {"common/uca/CollationTest_CLDR_SHIFTED_SHORT.txt", "CollationTest_CLDR_SHIFTED_SHORT.txt"}
  ]

  # Fixtures we deliberately diverge from upstream on, and must therefore
  # never overwrite. CLDR's own conformance files disagree with CLDR's own
  # data in a handful of places — `nn`/`no` is expected at 10 where the
  # distance rules plainly yield 20 — and the vendored copies carry those
  # corrections with the reasoning written beside them, ticket references
  # included. A blind copy reverts every one of them, and because it happens
  # during a CLDR update the resulting test failures read as upstream churn
  # rather than as our own pipeline undoing our own decisions. Copy skips
  # these; when upstream moves, `copy_test_data/0` says so and the merge is
  # made by hand.
  @curated_test_data ["locale_distance_test_data.txt", "locale_matching_test_data.txt"]

  # Upstream hashes the curated fixtures were last reconciled against; see
  # `report_curated/3`.
  @curated_baseline_file "curated_upstream_baseline.txt"

  @generators [
    {"aliases.etf", &Localize.Data.Supplemental.generate_aliases/0},
    {"calendar_preferences.etf", &Localize.Data.Supplemental.generate_calendar_preferences/0},
    {"currency_codes.etf", &Localize.Data.Supplemental.generate_currency_codes/0},
    {"likely_subtags.etf", &Localize.Data.Supplemental.generate_likely_subtags/0},
    {"number_systems.etf", &Localize.Data.Supplemental.generate_number_systems/0},
    {"parent_locales.etf", &Localize.Data.Supplemental.generate_parent_locales/0},
    {"day_periods.etf", &Localize.Data.Supplemental.generate_day_periods/0},
    {"territories.etf", &Localize.Data.Supplemental.generate_territories/0},
    {"territory_codes.etf", &Localize.Data.Supplemental.generate_territory_codes/0},
    {"territory_containers.etf", &Localize.Data.Supplemental.generate_territory_containers/0},
    {"territory_containment.etf", &Localize.Data.Supplemental.generate_territory_containment/0},
    {"territory_currencies.etf", &Localize.Data.Supplemental.generate_territory_currencies/0},
    # language_matching must come after territory_containers (it needs container data)
    {"language_matching.etf", &Localize.Data.Supplemental.generate_language_matching/0},
    {"metazones.etf", &Localize.Data.Supplemental.generate_metazones/0},
    {"time_preferences.etf", &Localize.Data.Supplemental.generate_time_preferences/0},
    {"weeks.etf", &Localize.Data.Supplemental.generate_weeks/0},
    {"plural_rules_cardinal.etf", &Localize.Data.PluralRules.generate_plural_rules_cardinal/0},
    {"plural_rules_ordinal.etf", &Localize.Data.PluralRules.generate_plural_rules_ordinal/0},
    {"plural_ranges.etf", &Localize.Data.XmlExtractors.generate_plural_ranges/0},
    {"calendars.etf", &Localize.Data.Calendars.generate_calendars/0},
    {"timezones.etf", &Localize.Data.XmlExtractors.generate_timezones/0},
    {"primary_zones.etf", &Localize.Data.XmlExtractors.generate_primary_zones/0},
    {"territory_subdivisions.etf",
     &Localize.Data.XmlExtractors.generate_territory_subdivisions/0},
    {"territory_subdivision_containment.etf",
     &Localize.Data.XmlExtractors.generate_territory_subdivision_containment/0},
    {"unit_data.etf", &Localize.Data.XmlExtractors.generate_unit_data/0},
    {"unit_grammatical_derivations.etf",
     &Localize.Data.XmlExtractors.generate_unit_grammatical_derivations/0},
    {"collation_tailoring.etf", &Localize.Data.Collation.generate_collation_tailoring/0},
    {"coverage_levels.etf", &Localize.Data.Supplemental.generate_coverage_levels/0},
    {"measurement_systems.etf", &Localize.Data.XmlExtractors.generate_measurement_systems/0},
    {"measurement_data.etf", &Localize.Data.XmlExtractors.generate_measurement_data/0}
  ]

  # ── Sources ─────────────────────────────────────────────────────
  #
  # Everything is read where it sits: JSON from the cldr-json release bundle
  # in `CLDR_PRODUCTION`, XML and text from the CLDR repository in
  # `CLDR_REPO`. The sources used to be copied into `priv/cldr` first; each
  # path here is the one its copy was taken from, so the generated data is
  # unchanged.

  @doc """
  Returns the path to a supplemental JSON source file.

  ### Arguments

  * `filename` is the file's name, such as `"aliases.json"`.

  ### Returns

  * The path to the file in the bundle's `cldr-core/supplemental/`, or in
    the one other place the bundle publishes it.

  """
  @spec supplemental_json_path(String.t()) :: String.t()
  def supplemental_json_path(filename) do
    relative =
      Map.get_lazy(@supplemental_json_paths, filename, fn ->
        Path.join(["cldr-core", "supplemental", filename])
      end)

    Path.join(cldr_source_dir(), relative)
  end

  @doc """
  Returns a locale's JSON source files in the order they are merged.

  A locale's data is spread across the bundle's `-full` packages. The files
  are ordered by `<package>__<file>`, with the locale's RBNF source taken as
  `rbnf.json`: the names and the order the copy into `priv/cldr` produced,
  which the merged data depends on.

  ### Arguments

  * `locale` is a CLDR locale name such as `"en-AU"`.

  ### Returns

  * A list of paths, empty for a locale the bundle has no data for.

  """
  @spec locale_source_files(String.t()) :: [String.t()]
  def locale_source_files(locale) do
    root = cldr_source_dir()

    package_files =
      for package <- full_packages(root),
          directory = Path.join([root, package, "main", locale]),
          file <- json_files(directory),
          do: {"#{package}__#{file}", Path.join(directory, file)}

    rbnf_file =
      for path <- [rbnf_source_path(locale)], File.exists?(path), do: {"rbnf.json", path}

    (package_files ++ rbnf_file)
    |> Enum.sort()
    |> Enum.map(fn {_name, path} -> path end)
  end

  @doc """
  Returns the path to a locale's source file in one cldr-json package.

  ### Arguments

  * `locale` is a CLDR locale name.

  * `package` is a package in the bundle, such as `"cldr-units-full"`.

  * `file` is the file's name in the package's `main/<locale>/`.

  ### Returns

  * The path, whether or not the file exists.

  """
  @spec locale_source_path(String.t(), String.t(), String.t()) :: String.t()
  def locale_source_path(locale, package, file) do
    Path.join([cldr_source_dir(), package, "main", locale, file])
  end

  @doc """
  Returns the path to a locale's RBNF source.

  The rule files it names sit beside it in the bundle's `cldr-rbnf/rbnf/`.

  ### Arguments

  * `locale` is a CLDR locale name.

  ### Returns

  * The path, whether or not the file exists.

  """
  @spec rbnf_source_path(String.t()) :: String.t()
  def rbnf_source_path(locale) do
    Path.join([cldr_source_dir(), "cldr-rbnf", "rbnf", "#{locale}.json"])
  end

  @doc """
  Returns the path to a locale's subdivision names.

  cldr-json does not publish them, so they are read from the repository's
  XML.

  ### Arguments

  * `locale` is a CLDR locale name.

  ### Returns

  * The path, whether or not the file exists.

  """
  @spec subdivisions_source_path(String.t()) :: String.t()
  def subdivisions_source_path(locale) do
    Path.join([cldr_repo_dir(), "common", "subdivisions", "#{locale}.xml"])
  end

  @doc """
  Returns the name of every locale the bundle has data for.

  ### Returns

  * A sorted list of locale name strings.

  """
  @spec source_locale_names() :: [String.t()]
  def source_locale_names do
    root = cldr_source_dir()

    for package <- full_packages(root),
        main = Path.join([root, package, "main"]),
        entry <- directory_entries(main),
        File.dir?(Path.join(main, entry)),
        uniq: true do
      entry
    end
    |> Enum.sort()
  end

  defp full_packages(root) do
    root
    |> directory_entries()
    |> Enum.filter(&String.ends_with?(&1, "-full"))
    |> Enum.sort()
  end

  defp json_files(directory) do
    directory
    |> directory_entries()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
  end

  defp directory_entries(directory) do
    case File.ls(directory) do
      {:ok, entries} -> entries
      {:error, _absent} -> []
    end
  end

  # ── Source versions ─────────────────────────────────────────────
  #
  # The bundle and the repository are two halves of one release with nothing
  # tying them together, and neither names the other: cldr-json re-spins a
  # release under a new name (`48.2.0-BETA0b`) and publishes packaging-only
  # patches such as 48.2.1 that CLDR never tags. So the pair the committed
  # data was generated from is recorded, in the way
  # `priv/localize/localize_inflection_sha` pins the inflection sources.

  @doc """
  Returns the sources the committed data was generated from.

  ### Returns

  * `{cldr_json_version, cldr_repo_ref}` as recorded in
    `priv/localize/cldr_json_version` and `priv/localize/cldr_repo_ref`,
    either `nil` when it has not been recorded.

  """
  @spec pinned_sources() :: {String.t() | nil, String.t() | nil}
  def pinned_sources do
    {read_pin(@cldr_json_version_file), read_pin(@cldr_repo_ref_file)}
  end

  @doc """
  Returns the sources in `CLDR_PRODUCTION` and `CLDR_REPO`.

  ### Returns

  * `{cldr_json_version, cldr_repo_ref}`: the release named in the bundle's
    `cldr-core/package.json`, and the repository's `release-*` tag at `HEAD`,
    another tag there, or the commit. Either is `nil` when it cannot be read.

  """
  @spec current_sources() :: {String.t() | nil, String.t() | nil}
  def current_sources do
    {bundle_version(), repository_ref()}
  end

  @doc """
  Records the sources in `CLDR_PRODUCTION` and `CLDR_REPO` as the ones the
  data is generated from.

  ### Returns

  * `{:ok, {cldr_json_version, cldr_repo_ref}}` when both were written.

  * `{:error, message}` when either source cannot be read.

  """
  @spec record_sources() :: {:ok, {String.t(), String.t()}} | {:error, String.t()}
  def record_sources do
    case current_sources() do
      {version, ref} when is_binary(version) and is_binary(ref) ->
        File.write!(Path.join(File.cwd!(), @cldr_json_version_file), version)
        File.write!(Path.join(File.cwd!(), @cldr_repo_ref_file), ref)
        {:ok, {version, ref}}

      {version, ref} ->
        {:error, sources_message("Cannot read the CLDR sources to record them.", {version, ref})}
    end
  end

  @doc """
  Checks that `CLDR_PRODUCTION` and `CLDR_REPO` hold the recorded sources.

  ### Returns

  * `:ok` when both match what is recorded.

  * `{:error, message}` otherwise, saying which differs and how to fix it.

  """
  @spec verify_sources() :: :ok | {:error, String.t()}
  def verify_sources do
    current = current_sources()

    case pinned_sources() do
      ^current ->
        :ok

      {nil, _ref} ->
        {:error, sources_message("No CLDR sources are recorded.", current)}

      {version, ref} ->
        {:error,
         sources_message(
           "The CLDR sources are not the recorded ones, cldr-json #{version} " <>
             "with the CLDR repository at #{ref}.",
           current
         )}
    end
  end

  @doc """
  Returns whether the recorded sources are present, so that locale data
  can be generated from them.

  ### Returns

  * `true` when `CLDR_PRODUCTION` and `CLDR_REPO` hold the recorded sources.

  * `false` otherwise.

  """
  @spec sources_available?() :: boolean()
  def sources_available? do
    File.dir?(cldr_source_dir()) and File.dir?(cldr_repo_dir()) and verify_sources() == :ok
  end

  defp sources_message(problem, {version, ref}) do
    """
    #{problem}

      CLDR_PRODUCTION #{cldr_source_dir()} holds cldr-json #{version || "(unreadable)"}
      CLDR_REPO #{cldr_repo_dir()} is at #{ref || "(unreadable)"}

    `mix localize.fetch_sources` fetches the recorded pair. To generate from
    new sources instead, run `mix localize.update_cldr`, which records them.
    """
  end

  defp read_pin(file) do
    case File.read(Application.app_dir(:localize, file)) do
      {:ok, contents} -> String.trim(contents)
      {:error, _absent} -> nil
    end
  end

  defp bundle_version do
    path = Path.join([cldr_source_dir(), "cldr-core", "package.json"])

    with {:ok, contents} <- File.read(path),
         %{"version" => version} when is_binary(version) <- :json.decode(contents) do
      version
    else
      _unreadable -> nil
    end
  end

  # A release tag names the ref most readably, so one is preferred when HEAD
  # carries several tags; a checkout between tags is recorded by its commit.
  defp repository_ref do
    directory = cldr_repo_dir()

    with true <- File.dir?(directory),
         {:ok, tags} <- git(directory, ["tag", "--points-at", "HEAD"]) do
      tags = tags |> String.split("\n", trim: true) |> Enum.sort()

      Enum.find(tags, &String.starts_with?(&1, "release-")) || List.first(tags) ||
        head_commit(directory)
    else
      _no_repository -> nil
    end
  end

  defp head_commit(directory) do
    case git(directory, ["rev-parse", "HEAD"]) do
      {:ok, commit} -> String.trim(commit)
      :error -> nil
    end
  end

  defp git(directory, arguments) do
    case System.cmd("git", arguments, cd: directory, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {_output, _status} -> :error
    end
  end

  # ── Test fixtures ───────────────────────────────────────────────

  @doc """
  Copies CLDR's RBNF conformance data from `CLDR_REPO` into
  `test/support/data/rbnf_conformance/`.

  CLDR 49 added `common/testData/rbnf`: one `.ssv` file per locale, around
  53,000 cases, exercising every public rule set. Unlike the other test data
  this is a whole directory rather than a handful of named files, so it is
  copied wholesale and stale locales are cleared first — a locale that leaves
  CLDR should leave the fixtures with it.

  ### Returns

  * `:ok` on success.

  """
  @spec copy_rbnf_test_data() :: :ok
  def copy_rbnf_test_data do
    dest = Path.join([File.cwd!(), @test_data_dir, "rbnf_conformance"])
    src = Path.join(cldr_repo_dir(), "common/testData/rbnf")

    if File.dir?(src) do
      File.rm_rf!(dest)
      File.mkdir_p!(dest)

      count =
        src
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".ssv"))
        |> Enum.map(&File.cp!(Path.join(src, &1), Path.join(dest, &1)))
        |> length()

      IO.puts("Copied #{count} RBNF conformance files to #{dest}")
    else
      IO.puts("  Warning: common/testData/rbnf not found, skipping")
    end

    :ok
  end

  @doc """
  Copies CLDR test data files from `CLDR_REPO` into
  `test/support/data/`.

  These files include conformance test data for locale
  canonicalization, likely subtags, locale display names,
  locale matching, datetime formatting, unit conversions,
  and collation.

  ### Returns

  * `:ok` on success.

  """
  @spec copy_test_data() :: :ok
  def copy_test_data do
    dest = Path.join(File.cwd!(), @test_data_dir)
    File.mkdir_p!(dest)

    repo_root = cldr_repo_dir()
    _copied = 0

    count =
      Enum.reduce(@test_data_files, 0, fn {src_path, dst_name}, acc ->
        src = Path.join(repo_root, src_path)
        dst = Path.join(dest, dst_name)

        cond do
          not File.exists?(src) ->
            IO.puts("  Warning: #{src_path} not found, skipping")
            acc

          dst_name in @curated_test_data ->
            report_curated(src, dst, dst_name)
            acc

          true ->
            File.cp!(src, dst)
            acc + 1
        end
      end)

    IO.puts("Copied #{count} test data files to #{dest}")
    :ok
  end

  # A curated fixture is left alone, but silence would be its own trap: were
  # upstream to add coverage we would never pick it up. Compare instead, and
  # say whether there is a merge waiting.
  #
  # Differing does not mean upstream moved — our copies carry cases upstream
  # does not have, so they differ permanently and this prints on every run.
  # Saying "upstream has changed" sends the reader looking for a change that
  # is usually not there, so the message states the difference and leaves the
  # cause to the diff.
  # A curated fixture carries cases upstream does not, so it differs from
  # upstream permanently — reporting that difference fires on every run and
  # asks a question nobody can act on. What is worth saying is that *upstream
  # itself* has moved since the fixture was last reconciled, which happens
  # once or twice a CLDR cycle and may bring coverage worth taking.
  #
  # The baseline records the upstream hash at that reconciliation, the same
  # way `priv/localize/localize_inflection_sha` pins its upstream commit.
  # Both sides of the suggested `diff` are absolute: it previously printed the
  # repo-relative source path, so the command only ran from inside CLDR_REPO.
  defp report_curated(src, dst, dst_name) do
    upstream_hash = :crypto.hash(:sha256, File.read!(src)) |> Base.encode16(case: :lower)

    case Map.fetch(curated_baselines(), dst_name) do
      {:ok, ^upstream_hash} ->
        :ok

      {:ok, recorded} ->
        IO.puts("""
          Upstream #{dst_name} has changed since it was last reconciled.
            recorded #{String.slice(recorded, 0, 12)}, now #{String.slice(upstream_hash, 0, 12)}
            diff #{dst} #{src}
            After merging, record the new hash in #{@curated_baseline_file}:
              #{dst_name} #{upstream_hash}
        """)

      :error ->
        IO.puts("""
          No upstream baseline recorded for curated fixture #{dst_name}.
            Reconcile it against upstream, then add to #{@curated_baseline_file}:
              #{dst_name} #{upstream_hash}
        """)
    end
  end

  defp curated_baselines do
    path = Path.join([File.cwd!(), @test_data_dir, @curated_baseline_file])

    case File.read(path) do
      {:ok, contents} -> parse_curated_baselines(contents)
      {:error, _absent} -> %{}
    end
  end

  defp parse_curated_baselines(contents) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.flat_map(&curated_baseline_entry/1)
    |> Map.new()
  end

  defp curated_baseline_entry(line) do
    case String.split(line, ~r/\s+/, parts: 2, trim: true) do
      [name, hash] -> [{name, String.trim(hash)}]
      _malformed -> []
    end
  end

  # ── Version management ──────────────────────────────────────────

  @doc """
  Writes the CLDR version to `priv/localize/version`.

  Reads the version from the CLDR source data's `aliases.json`
  supplemental file.

  ### Returns

  * The version string that was written.

  """
  @spec write_version() :: String.t()
  def write_version do
    version_json = read_json("aliases.json")
    json_cldr_version = get_in(version_json, ["supplemental", "version", "_cldrVersion"])

    path = Path.join(File.cwd!(), @version_file)
    File.mkdir_p!(Path.dirname(path))

    previous_cldr_version = cldr_version()

    cond do
      is_nil(previous_cldr_version) ->
        File.write!(path, json_cldr_version)
        reset_patch_version(json_cldr_version)
        :persistent_term.erase({:localize, :version})
        IO.puts("Wrote CLDR version #{json_cldr_version} to #{path}")
        json_cldr_version

      # CLDR's `aliases.json` only records the major version
      # (e.g. `"48"`), not sub-releases like `"48.2"`. When a
      # more-specific version is already on disk and shares the
      # same major release, leave it alone — that finer value
      # was set intentionally to record a CLDR sub-release.
      same_major_version?(previous_cldr_version, json_cldr_version) ->
        IO.puts(
          "CLDR version #{previous_cldr_version} on disk is at least as " <>
            "specific as #{json_cldr_version} from aliases.json; " <>
            "leaving #{path} unchanged."
        )

        previous_cldr_version

      true ->
        # Real CLDR major-version change — overwrite the version
        # file and reset the Localize patch counter to `0`. The
        # patch counter tracks Localize-side data-pipeline changes
        # within a single CLDR release; a fresh CLDR release starts
        # a new patch series. Subsequent explicit
        # `bump_patch_version/0` calls then increment from `0` to
        # `1`, `2`, etc.
        File.write!(path, json_cldr_version)
        reset_patch_version(json_cldr_version)
        :persistent_term.erase({:localize, :version})

        IO.puts(
          "Updated CLDR version #{previous_cldr_version} -> " <>
            "#{json_cldr_version} in #{path}"
        )

        json_cldr_version
    end
  end

  defp same_major_version?(a, b) do
    major_component(a) == major_component(b)
  end

  defp major_component(version) when is_binary(version) do
    version |> String.split(".") |> hd()
  end

  defp major_component(_), do: nil

  defp reset_patch_version(cldr_version) do
    File.write!(patch_version_path(), "#{cldr_version}:0")
    IO.puts("Reset Localize patch version to #{cldr_version}:0")
  end

  @doc """
  Reads the CLDR version from `priv/localize/version`.

  ### Returns

  * The version string, or `nil` if the file does not exist.

  """
  @spec cldr_version() :: String.t() | nil
  def cldr_version do
    case File.read(Application.app_dir(:localize, @version_file)) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> nil
    end
  end

  # ── Supplemental ETF generation ─────────────────────────────────

  @doc """
  Generates all 22 supplemental data ETF files.

  Reads raw CLDR source data, transforms it, and writes ETF files
  to `priv/localize/supplemental_data/`.

  ### Returns

  * `:ok` on success.

  """
  @spec generate_all() :: :ok
  def generate_all do
    File.mkdir_p!(output_dir())

    Enum.each(@generators, fn {filename, generator} ->
      IO.puts("Generating #{filename}...")
      data = generator.()
      save_etf(filename, data)
    end)

    IO.puts("All #{length(@generators)} supplemental ETF files generated.")

    # Generate validity ETF files
    Localize.Data.Validity.generate_all()

    # Generate script-to-subtag mapping ETF
    IO.puts("Generating unicode_script_to_subtag_mapping.etf...")
    script_data = Localize.Data.ScriptMetadata.generate_unicode_script_to_subtag_mapping()
    path = Path.join(output_dir(), "unicode_script_to_subtag_mapping.etf")
    File.write!(path, :erlang.term_to_binary(script_data, [:deterministic]))

    # Generate all_locale_names.etf — list of all locale name atoms
    IO.puts("Generating all_locale_names.etf...")
    locale_names = derive_all_locale_names()
    save_etf("all_locale_names.etf", locale_names)

    # Generate known_territories.etf — list of all territory atoms
    IO.puts("Generating known_territories.etf...")
    territories = derive_known_territories()
    save_etf("known_territories.etf", territories)

    # Rebuild the UCA collation table from the repository's FractionalUCA.txt.
    # Not in @generators because it writes its own files rather than
    # returning data for save_etf/2, but it belongs to the same pass: the
    # table is derived data and leaving it out is what let it sit at
    # Unicode 17 while the conformance fixtures moved to 18.
    IO.puts("Generating collation_table.etf...")
    Localize.Data.Collation.generate_collation_table()

    # Generate Unicode collation data ETFs
    unicode_dir = Path.join(File.cwd!(), "priv/unicode")

    if File.dir?(unicode_dir) do
      IO.puts("Generating combining_classes.etf...")
      combining = Localize.Data.UnicodeData.generate_combining_classes()
      save_etf("combining_classes.etf", combining)
      IO.puts("  #{map_size(combining)} codepoint entries")

      IO.puts("Generating decimal_digit_ranges.etf...")
      digits = Localize.Data.UnicodeData.generate_decimal_digit_ranges()
      save_etf("decimal_digit_ranges.etf", digits)
      IO.puts("  #{length(digits)} ranges")
    end

    :ok
  end

  # Locale names come from the bundle's own directory names, a closed set,
  # so converting them to atoms cannot grow the atom table without bound.
  defp derive_all_locale_names do
    Enum.map(source_locale_names(), &String.to_atom/1)
  end

  defp derive_known_territories do
    # Known territories are the keys from the territory_containers data
    # plus all leaf territories contained within them
    containers = Localize.Data.Supplemental.generate_territory_containers()

    container_atoms = Map.keys(containers)

    contained_atoms =
      containers
      |> Map.values()
      |> List.flatten()

    (container_atoms ++ contained_atoms)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # ── Locale ETF generation ──────────────────────────────────────

  @doc """
  Returns the output directory for generated locale ETF files.

  Delegates to `Localize.Locale.Provider.locale_cache_dir/0` so
  that `mix localize.generate_locales` writes to the same
  directory that the runtime cache reads from.

  By default the value is
  `Application.app_dir(:localize, "priv/localize/locales")`.

  End users can redirect generated output to a persistent
  location by configuring it in their application environment:

      config :localize, locale_cache_dir: "/var/lib/myapp/localize_cache"

  With that set, regenerating locales from a dependent project
  populates the configured path, and Localize's runtime cache
  reads from the same place on the next request.

  """
  @spec locales_output_dir() :: String.t()
  def locales_output_dir do
    Localize.Locale.Provider.locale_cache_dir()
  end

  @doc """
  Generates all locale ETF files.

  Reads the list of all locale names from supplemental data,
  generates each locale, transforms it into struct form, and
  saves it as an ETF file in `priv/localize/locales/`.

  ### Returns

  * `:ok` on success.

  """
  @spec generate_all_locales() :: :ok
  def generate_all_locales do
    output = locales_output_dir()
    File.rm_rf!(output)
    File.mkdir_p!(output)

    # Generation does NOT bump the patch version. The patch
    # counter is only advanced explicitly by a developer running
    # `mix localize.bump_patch_version` when they have changed
    # the data pipeline (normalizers, transforms, etc.). This
    # makes generation safe to run from CI without producing
    # phantom version bumps.
    #
    # Clear any cached `Localize.version/0` so the generated ETF
    # files reflect the current on-disk patch version, which may
    # have been changed externally between Mix runs.
    :persistent_term.erase({:localize, :version})

    locales =
      Localize.SupplementalData.all_locale_ids()
      |> Enum.map(&Atom.to_string/1)

    total = length(locales)
    IO.puts("Generating #{total} locale ETF files with version #{Localize.version()}...")

    locales
    |> Enum.with_index(1)
    |> Enum.each(fn {locale, index} ->
      if rem(index, 50) == 0 or index == total do
        IO.puts("  #{index}/#{total}...")
      end

      Localize.Data.Locale.generate_and_save_locale(locale)
    end)

    IO.puts("All #{total} locale ETF files generated.")

    # Regenerate the download-integrity manifest so it always matches
    # the freshly generated data — a CLDR refresh cannot leave stale
    # hashes behind.
    generate_locale_hashes(output)

    :ok
  end

  @doc """
  Generates the locale hash manifest from the bytes currently served
  by the CDN rather than from locally generated files.

  This exists to (re)establish the manifest baseline when the local
  generation predates or postdates the uploaded data — for example
  when a newer OTP re-encodes value-identical ETF files with
  different bytes. The published data for a version is immutable, so
  hashing what the CDN serves pins exactly what consumers download.

  Every locale must download successfully; any failure raises and no
  manifest is written.

  ### Returns

  * `:ok`.

  """
  @spec generate_locale_hashes_from_cdn() :: :ok
  def generate_locale_hashes_from_cdn do
    locale_ids = Localize.SupplementalData.all_locale_ids()
    total = length(locale_ids)
    IO.puts("Hashing #{total} locales from #{Localize.Locale.Provider.base_url()}...")

    hashes =
      locale_ids
      |> Task.async_stream(
        fn locale_id ->
          url = Localize.Locale.Provider.locale_url(locale_id)

          case Localize.Utils.Http.get(url) do
            {:ok, body} when is_binary(body) ->
              {locale_id, :crypto.hash(:sha256, body)}

            other ->
              raise "download failed for #{inspect(locale_id)} from #{url}: #{inspect(other)}"
          end
        end,
        max_concurrency: 8,
        timeout: 120_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, pair} -> pair end)
      |> Map.new()

    write_locale_hashes(hashes, "the CDN at #{Localize.Locale.Provider.base_url()}")
  end

  @doc """
  Generates `priv/localize/locale_hashes.etf`, the SHA-256 manifest
  used by `Localize.Locale.Provider.download_locale/1` to verify
  locale files downloaded from the CDN.

  Called automatically at the end of `generate_all_locales/0`, and
  directly by `mix localize.generate_locale_hashes`.

  ### Arguments

  * `locales_dir` is the directory containing the generated locale
    `.etf` files.

  ### Returns

  * `:ok`. Raises if the directory contains no locale files.

  """
  @spec generate_locale_hashes(String.t()) :: :ok
  def generate_locale_hashes(locales_dir) do
    etf_files =
      locales_dir
      |> Path.join("*.etf")
      |> Path.wildcard()
      |> Enum.sort()

    if etf_files == [] do
      raise ArgumentError,
            "no locale .etf files found in #{inspect(locales_dir)}. " <>
              "Run `mix localize.generate_locales` first."
    end

    hashes =
      Map.new(etf_files, fn path ->
        locale_id =
          path
          |> Path.basename(".etf")
          |> String.to_atom()

        {locale_id, :crypto.hash(:sha256, File.read!(path))}
      end)

    write_locale_hashes(hashes, inspect(locales_dir))
  end

  defp write_locale_hashes(hashes, source_description) do
    manifest_path = Path.join(File.cwd!(), "priv/localize/locale_hashes.etf")
    File.write!(manifest_path, :erlang.term_to_binary(hashes, [:deterministic]))

    IO.puts(
      "Wrote #{map_size(hashes)} locale hashes to priv/localize/locale_hashes.etf " <>
        "from #{source_description}"
    )

    :ok
  end

  @doc """
  Returns the current CLDR data version string, including the
  Localize patch version.

  The format is `"v{cldr_version}.{patch_version}"`, for example
  `"v48.2.1"`.

  """
  @spec data_version() :: String.t()
  def data_version do
    "v#{cldr_version()}.#{patch_version()}"
  end

  @doc """
  Returns the Localize patch version from
  `priv/localize/localize_patch_version`.

  The file stores the version in `"{cldr_version}:{patch}"` format
  (for example `"48.2:3"`). The returned value is the patch
  component as a string. If the stored CLDR version does not match
  the current `cldr_version/0`, the patch is considered to be `"0"`
  since the recorded patch applies to a different CLDR release.

  ### Returns

  * The patch version as a string.

  """
  @spec patch_version() :: String.t()
  def patch_version do
    case read_patch_version() do
      {cldr_version, patch} ->
        if cldr_version == cldr_version(), do: patch, else: "0"

      :not_found ->
        "0"
    end
  end

  defp read_patch_version do
    patch_path = patch_version_path()

    case File.read(patch_path) do
      {:ok, content} ->
        case String.trim(content) |> String.split(":", parts: 2) do
          [cldr_version, patch] -> {cldr_version, patch}
          [patch] -> {nil, patch}
        end

      {:error, _} ->
        :not_found
    end
  end

  defp patch_version_path do
    Application.app_dir(:localize, "priv/localize/localize_patch_version")
  end

  @doc """
  Bumps the Localize patch version for the current CLDR release.

  Reads the current CLDR version from `priv/localize/version` and
  increments the patch counter associated with that version.

  This function is intended to be called explicitly by a developer
  via `mix localize.bump_patch_version` when they have changed
  the locale data generation pipeline (normalizers, transforms,
  etc.). It is **not** called automatically by
  `generate_all_locales/0` so that CI runs do not produce phantom
  version bumps.

  When the upstream CLDR release version changes,
  `write_version/0` resets the patch counter to `0`. The first
  bump after a CLDR upgrade therefore takes the patch from `0` to
  `1`. If the patch file is in some unexpected state (missing,
  malformed, or recorded against a different CLDR version), the
  next patch is set to `1` as a safe default.

  After bumping, any cached `Localize.version/0` value is cleared
  from `:persistent_term`.

  ### Returns

  * The new patch version as a string.

  """
  @spec bump_patch_version() :: String.t()
  def bump_patch_version do
    patch_path = patch_version_path()
    current_cldr = cldr_version()

    next_patch =
      case read_patch_version() do
        {^current_cldr, patch} -> String.to_integer(patch) + 1
        _other -> 1
      end

    File.write!(patch_path, "#{current_cldr}:#{next_patch}")
    :persistent_term.erase({:localize, :version})
    IO.puts("Patch version updated to #{current_cldr}:#{next_patch}")
    Integer.to_string(next_patch)
  end

  # ── Path helpers ────────────────────────────────────────────────

  @doc """
  Returns the path to the CLDR production data directory.

  Reads from the `CLDR_PRODUCTION` environment variable. Without it,
  the first of the known checkout layouts that exists is used — see
  `cldr_repo_dir/0`.

  """
  @spec cldr_source_dir() :: String.t()
  def cldr_source_dir do
    System.get_env("CLDR_PRODUCTION") || default_cldr_dir("cldr_production_data")
  end

  @doc """
  Returns the path to the CLDR repository checkout.

  Reads from the `CLDR_REPO` environment variable. Without it, the
  first of these that exists is used:

  * `../cldr_repo`, a sibling of this project.

  * `../../cldr/cldr_repo`, the layout `scripts/build_cldr_production_data`
    defaults to, where the CLDR checkouts sit in their own family
    directory beside this one.

  Neither existing returns the sibling path, so the caller reports a
  path rather than `nil`.

  """
  @spec cldr_repo_dir() :: String.t()
  def cldr_repo_dir do
    System.get_env("CLDR_REPO") || default_cldr_dir("cldr_repo")
  end

  # The CLDR checkouts live either beside this project or in a `cldr`
  # family directory beside it. The shell script defaults to the latter
  # while these defaulted to the former, so a copy run that took the
  # defaults failed partway through on a missing file.
  defp default_cldr_dir(name) do
    root = File.cwd!()

    candidates = [
      Path.expand(Path.join([root, "..", name])),
      Path.expand(Path.join([root, "..", "..", "cldr", name]))
    ]

    Enum.find(candidates, hd(candidates), &File.dir?/1)
  end

  @doc """
  Returns the output directory for generated supplemental ETF files.

  """
  @spec output_dir() :: String.t()
  def output_dir do
    Application.app_dir(:localize, @supplemental_etf_dir)
  end

  @doc """
  Returns the path to the external sources directory.

  External sources are non-CLDR data files (such as the ISO 4217
  currency list) that supplement the CLDR data. They are vendored in
  `priv/external_sources/`.

  """
  @spec external_sources_dir() :: String.t()
  def external_sources_dir do
    Application.app_dir(:localize, @external_sources_dir)
  end

  @doc """
  Returns the repository directory holding the supplemental XML.

  """
  @spec supplemental_xml_dir() :: String.t()
  def supplemental_xml_dir do
    Path.join([cldr_repo_dir(), "common", "supplemental"])
  end

  @doc """
  Returns the repository directory holding the collation XML.

  """
  @spec collation_source_dir() :: String.t()
  def collation_source_dir do
    Path.join([cldr_repo_dir(), "common", "collation"])
  end

  @doc """
  Returns the repository directory holding the validity XML.

  """
  @spec validity_source_dir() :: String.t()
  def validity_source_dir do
    Path.join([cldr_repo_dir(), "common", "validity"])
  end

  @doc """
  Returns the repository directory holding the BCP 47 XML.

  """
  @spec bcp47_source_dir() :: String.t()
  def bcp47_source_dir do
    Path.join([cldr_repo_dir(), "common", "bcp47"])
  end

  @doc """
  Returns the path to the repository's `FractionalUCA.txt`, the UCA
  weight table the collation implementation is built from.

  """
  @spec uca_table_path() :: String.t()
  def uca_table_path do
    Path.join([cldr_repo_dir(), "common", "uca", "FractionalUCA.txt"])
  end

  @doc """
  Returns the path to the repository's `Script_Metadata.csv`.

  """
  @spec script_metadata_path() :: String.t()
  def script_metadata_path do
    Path.join(
      cldr_repo_dir(),
      "tools/cldr-code/src/main/resources/org/unicode/cldr/util/data/Script_Metadata.csv"
    )
  end

  @doc """
  Reads and decodes a supplemental JSON source file.

  ### Arguments

  * `filename` is the JSON filename (e.g., `"aliases.json"`).

  ### Returns

  * The decoded JSON data as a map.

  """
  @spec read_json(String.t()) :: map()
  def read_json(filename) do
    filename
    |> supplemental_json_path()
    |> File.read!()
    |> :json.decode()
  end

  @doc """
  Saves a term as an ETF file in the supplemental output directory.

  ### Arguments

  * `filename` is the ETF filename (e.g., `"aliases.etf"`).

  * `data` is the Erlang term to serialize.

  ### Returns

  * `:ok`.

  """
  @spec save_etf(String.t(), term()) :: :ok
  def save_etf(filename, data) do
    path = Path.join(output_dir(), filename)
    File.write!(path, :erlang.term_to_binary(data, [:deterministic]))
    :ok
  end
end
