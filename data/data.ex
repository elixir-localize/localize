defmodule Localize.Data do
  @moduledoc """
  Generates CLDR data files for consumption by the `Localize` library.

  This module provides reproducible generation of all ETF files used by
  `Localize` at runtime. It reads raw CLDR JSON and XML source files,
  transforms them into the expected runtime format, and writes ETF
  (Erlang Term Format) files.

  ## Directory layout

  * `priv/cldr/supplemental_data/` — raw CLDR JSON and XML source
    files for supplemental data, copied from `CLDR_PRODUCTION_DATA`.

  * `priv/cldr/locales/` — raw CLDR JSON locale files, copied from
    the `-full` directories in `CLDR_PRODUCTION_DATA`.

  * `priv/localize/supplemental_data/` — generated ETF supplemental
    data files.

  * `priv/localize/locales/` — generated ETF locale files.

  * `priv/localize/version` — plain text file with the CLDR version.

  The source data directory is configurable via the `CLDR_PRODUCTION_DATA`
  environment variable, falling back to `../cldr_production_data`.

  """

  @dialyzer {:nowarn_function, write_version: 0}
  @dialyzer {:nowarn_function, cldr_source_dir: 0}
  @dialyzer {:nowarn_function, cldr_repo_dir: 0}
  @dialyzer {:nowarn_function, read_json: 1}
  @dialyzer {:nowarn_function, read_json_path: 1}

  @supplemental_etf_dir "priv/localize/supplemental_data"
  @cldr_supplemental_dir "priv/cldr/supplemental_data"
  @cldr_locales_dir "priv/cldr/locales"
  @cldr_collation_dir "priv/cldr/collation"
  @cldr_validity_dir "priv/cldr/validity"
  @cldr_bcp47_dir "priv/cldr/bcp47"
  @cldr_external_sources_dir "priv/cldr/external_sources"
  @version_file "priv/localize/version"

  # JSON files from cldr-core/supplemental/ (in CLDR_PRODUCTION_DATA)
  @supplemental_json_files [
    "aliases.json",
    "calendarPreferenceData.json",
    "codeMappings.json",
    "currencyData.json",
    "languageMatching.json",
    "likelySubtags.json",
    "measurementData.json",
    "numberingSystems.json",
    "ordinals.json",
    "parentLocales.json",
    "plurals.json",
    "territoryContainment.json",
    "territoryInfo.json",
    "timeData.json",
    "weekData.json"
  ]

  # XML files from CLDR_REPO (common/supplemental/ and common/bcp47/)
  @supplemental_xml_files [
    {"common/supplemental/pluralRanges.xml", "pluralRanges.xml"},
    {"common/supplemental/subdivisions.xml", "subdivisions.xml"},
    {"common/supplemental/units.xml", "units.xml"},
    {"common/bcp47/timezone.xml", "bcp47_timezone.xml"}
  ]

  # Non-supplemental files needed from other paths in CLDR_PRODUCTION_DATA
  @supplemental_extra_files [
    {"cldr-numbers-full/main/en/currencies.json", "currencies_en.json"},
    {"cldr-core/coverageLevels.json", "coverageLevels.json"}
  ]

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
    {"common/testData/units/unitsTest.txt", "conversion_test_data.txt"},
    {"common/testData/units/unitPreferencesTest.txt", "preference_test_data.txt"},
    {"common/uca/CollationTest_CLDR_NON_IGNORABLE_SHORT.txt",
     "CollationTest_CLDR_NON_IGNORABLE_SHORT.txt"},
    {"common/uca/CollationTest_CLDR_SHIFTED_SHORT.txt", "CollationTest_CLDR_SHIFTED_SHORT.txt"}
  ]

  @generators [
    {"aliases.etf", &Localize.Data.Supplemental.generate_aliases/0},
    {"calendar_preferences.etf", &Localize.Data.Supplemental.generate_calendar_preferences/0},
    {"currency_codes.etf", &Localize.Data.Supplemental.generate_currency_codes/0},
    {"likely_subtags.etf", &Localize.Data.Supplemental.generate_likely_subtags/0},
    {"number_systems.etf", &Localize.Data.Supplemental.generate_number_systems/0},
    {"parent_locales.etf", &Localize.Data.Supplemental.generate_parent_locales/0},
    {"territories.etf", &Localize.Data.Supplemental.generate_territories/0},
    {"territory_codes.etf", &Localize.Data.Supplemental.generate_territory_codes/0},
    {"territory_containers.etf", &Localize.Data.Supplemental.generate_territory_containers/0},
    {"territory_containment.etf", &Localize.Data.Supplemental.generate_territory_containment/0},
    {"territory_currencies.etf", &Localize.Data.Supplemental.generate_territory_currencies/0},
    # language_matching must come after territory_containers (it needs container data)
    {"language_matching.etf", &Localize.Data.Supplemental.generate_language_matching/0},
    {"time_preferences.etf", &Localize.Data.Supplemental.generate_time_preferences/0},
    {"weeks.etf", &Localize.Data.Supplemental.generate_weeks/0},
    {"plural_rules_cardinal.etf", &Localize.Data.PluralRules.generate_plural_rules_cardinal/0},
    {"plural_rules_ordinal.etf", &Localize.Data.PluralRules.generate_plural_rules_ordinal/0},
    {"plural_ranges.etf", &Localize.Data.XmlExtractors.generate_plural_ranges/0},
    {"timezones.etf", &Localize.Data.XmlExtractors.generate_timezones/0},
    {"territory_subdivisions.etf",
     &Localize.Data.XmlExtractors.generate_territory_subdivisions/0},
    {"territory_subdivision_containment.etf",
     &Localize.Data.XmlExtractors.generate_territory_subdivision_containment/0},
    {"unit_data.etf", &Localize.Data.XmlExtractors.generate_unit_data/0},
    {"collation_tailoring.etf", &Localize.Data.Collation.generate_collation_tailoring/0},
    {"coverage_levels.etf", &Localize.Data.Supplemental.generate_coverage_levels/0},
    {"measurement_systems.etf", &Localize.Data.XmlExtractors.generate_measurement_systems/0},
    {"measurement_data.etf", &Localize.Data.XmlExtractors.generate_measurement_data/0}
  ]

  # ── Source data copying ─────────────────────────────────────────

  @doc """
  Copies supplemental JSON and XML source files from
  `CLDR_PRODUCTION_DATA` into `priv/cldr/supplemental_data/`.

  This makes the raw source data available in the project for
  reproducible builds without requiring the external data directory.

  ### Returns

  * `:ok` on success.

  """
  @spec copy_supplemental_sources() :: :ok
  def copy_supplemental_sources do
    dest = Path.join(File.cwd!(), @cldr_supplemental_dir)
    File.rm_rf!(dest)
    File.mkdir_p!(dest)

    # Copy JSON files from CLDR_PRODUCTION_DATA/cldr-core/supplemental/
    source_supplemental = Path.join([cldr_source_dir(), "cldr-core", "supplemental"])

    for filename <- @supplemental_json_files do
      src = Path.join(source_supplemental, filename)
      dst = Path.join(dest, filename)
      File.cp!(src, dst)
    end

    # Copy extra JSON files from other paths in CLDR_PRODUCTION_DATA
    source_root = cldr_source_dir()

    for {src_path, dst_name} <- @supplemental_extra_files do
      src = Path.join(source_root, src_path)
      dst = Path.join(dest, dst_name)
      File.cp!(src, dst)
    end

    # Copy XML files from CLDR_REPO
    repo_root = cldr_repo_dir()

    for {src_path, dst_name} <- @supplemental_xml_files do
      src = Path.join(repo_root, src_path)
      dst = Path.join(dest, dst_name)
      File.cp!(src, dst)
    end

    count =
      length(@supplemental_json_files) +
        length(@supplemental_xml_files) +
        length(@supplemental_extra_files)

    IO.puts("Copied #{count} supplemental source files to #{dest}")
    :ok
  end

  @doc """
  Copies collation XML files from `CLDR_REPO` into
  `priv/cldr/collation/`.

  ### Returns

  * `:ok` on success.

  """
  @spec copy_collation_sources() :: :ok
  def copy_collation_sources do
    dest = Path.join(File.cwd!(), @cldr_collation_dir)
    File.rm_rf!(dest)
    File.mkdir_p!(dest)

    src_dir = Path.join(cldr_repo_dir(), "common/collation")

    xml_files =
      src_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".xml"))

    for file <- xml_files do
      File.cp!(Path.join(src_dir, file), Path.join(dest, file))
    end

    IO.puts("Copied #{length(xml_files)} collation XML files to #{dest}")
    :ok
  end

  @doc """
  Copies validity XML files from `CLDR_REPO` into
  `priv/cldr/validity/`.

  ### Returns

  * `:ok` on success.

  """
  @spec copy_validity_sources() :: :ok
  def copy_validity_sources do
    dest = Path.join(File.cwd!(), @cldr_validity_dir)
    File.rm_rf!(dest)
    File.mkdir_p!(dest)

    src_dir = Path.join(cldr_repo_dir(), "common/validity")

    xml_files =
      src_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".xml"))

    for file <- xml_files do
      File.cp!(Path.join(src_dir, file), Path.join(dest, file))
    end

    IO.puts("Copied #{length(xml_files)} validity XML files to #{dest}")
    :ok
  end

  @doc """
  Copies BCP47 XML files from `CLDR_REPO` into
  `priv/cldr/bcp47/`.

  ### Returns

  * `:ok` on success.

  """
  @spec copy_bcp47_sources() :: :ok
  def copy_bcp47_sources do
    dest = Path.join(File.cwd!(), @cldr_bcp47_dir)
    File.rm_rf!(dest)
    File.mkdir_p!(dest)

    src_dir = Path.join(cldr_repo_dir(), "common/bcp47")

    xml_files =
      src_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".xml"))

    for file <- xml_files do
      File.cp!(Path.join(src_dir, file), Path.join(dest, file))
    end

    IO.puts("Copied #{length(xml_files)} BCP47 XML files to #{dest}")
    :ok
  end

  @doc """
  Copies `Script_Metadata.csv` from `CLDR_REPO` into
  `priv/cldr/external_sources/`.

  ### Returns

  * `:ok` on success.

  """
  @spec copy_script_metadata() :: :ok
  def copy_script_metadata do
    dest = external_sources_dir()
    File.mkdir_p!(dest)

    src =
      Path.join(
        cldr_repo_dir(),
        "tools/cldr-code/src/main/resources/org/unicode/cldr/util/data/Script_Metadata.csv"
      )

    File.cp!(src, Path.join(dest, "Script_Metadata.csv"))
    IO.puts("Copied Script_Metadata.csv to #{dest}")
    :ok
  end

  @doc """
  Copies locale JSON files from `CLDR_PRODUCTION_DATA` into
  `priv/cldr/locales/`.

  Copies all JSON files from each `-full` directory's `main/`
  subdirectory, plus subdivision XML files. The output is organized
  as `priv/cldr/locales/<locale>/<file>`.

  ### Returns

  * `:ok` on success.

  """
  @spec copy_locale_sources() :: :ok
  def copy_locale_sources do
    dest_root = Path.join(File.cwd!(), @cldr_locales_dir)
    File.rm_rf!(dest_root)
    File.mkdir_p!(dest_root)

    source_root = cldr_source_dir()

    # Per-locale subdivision XML files are read directly from
    # `CLDR_REPO/common/subdivisions/`. CLDR's `ldml2json` does not
    # convert these files to JSON, and the published `cldr-json`
    # release artifacts do not include them, so they are sourced
    # from the CLDR repository in their original XML form. This
    # mirrors the way the global supplemental subdivisions, the
    # validity, BCP 47, and collation XML files are also sourced
    # directly from `CLDR_REPO`.
    repo_subdivisions_dir = Path.join(cldr_repo_dir(), "common/subdivisions")

    # Find all -full directories
    full_dirs =
      source_root
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, "-full"))
      |> Enum.sort()

    # Collect all locale names across all -full dirs
    all_locales =
      full_dirs
      |> Enum.flat_map(fn dir ->
        main_dir = Path.join([source_root, dir, "main"])

        case File.ls(main_dir) do
          {:ok, entries} -> entries
          {:error, _} -> []
        end
      end)
      |> Enum.uniq()
      |> Enum.sort()

    total = length(all_locales)
    IO.puts("Copying #{total} locale source directories...")

    for {locale, index} <- Enum.with_index(all_locales, 1) do
      if rem(index, 100) == 0, do: IO.puts("  #{index}/#{total}...")

      locale_dest = Path.join(dest_root, locale)
      File.mkdir_p!(locale_dest)

      # Copy JSON files from each -full dir
      for dir <- full_dirs do
        locale_src = Path.join([source_root, dir, "main", locale])

        case File.ls(locale_src) do
          {:ok, files} ->
            for file <- files, String.ends_with?(file, ".json") do
              File.cp!(
                Path.join(locale_src, file),
                Path.join(locale_dest, "#{dir}__#{file}")
              )
            end

          {:error, _} ->
            :skip
        end
      end

      # Copy per-locale subdivision XML directly from CLDR_REPO if
      # one exists. Not every locale has subdivision data.
      sub_xml = Path.join(repo_subdivisions_dir, "#{locale}.xml")

      if File.exists?(sub_xml) do
        File.cp!(sub_xml, Path.join(locale_dest, "subdivisions.xml"))
      end

      # Copy RBNF JSON if it exists
      rbnf_json = Path.join([source_root, "cldr-rbnf", "rbnf", "#{locale}.json"])

      if File.exists?(rbnf_json) do
        File.cp!(rbnf_json, Path.join(locale_dest, "rbnf.json"))
      end
    end

    IO.puts("Copied locale sources for #{total} locales to #{dest_root}")
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

        if File.exists?(src) do
          File.cp!(src, Path.join(dest, dst_name))
          acc + 1
        else
          IO.puts("  Warning: #{src_path} not found, skipping")
          acc
        end
      end)

    IO.puts("Copied #{count} test data files to #{dest}")
    :ok
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
    path = priv_relative_path(@version_file)

    case File.read(path) do
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
    File.write!(path, :erlang.term_to_binary(script_data))

    # Generate all_locale_names.etf — list of all locale name atoms
    IO.puts("Generating all_locale_names.etf...")
    locale_names = derive_all_locale_names()
    save_etf("all_locale_names.etf", locale_names)

    # Generate known_territories.etf — list of all territory atoms
    IO.puts("Generating known_territories.etf...")
    territories = derive_known_territories()
    save_etf("known_territories.etf", territories)

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

  defp derive_all_locale_names do
    locales_dir = locales_source_dir()

    locales_dir
    |> File.ls!()
    |> Enum.filter(fn entry ->
      Path.join(locales_dir, entry) |> File.dir?()
    end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&String.to_atom/1)
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
  `Application.app_dir(:localize, "priv/localize/locales")`
  (equivalent to `:code.priv_dir(:localize) |> Path.join("localize/locales")`).

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
    @version_file
    |> priv_relative_path()
    |> Path.dirname()
    |> Path.join("localize_patch_version")
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

  Reads from the `CLDR_PRODUCTION_DATA` environment variable,
  falling back to `../cldr_production_data` relative to the
  project root.

  """
  @spec cldr_source_dir() :: String.t()
  def cldr_source_dir do
    System.get_env("CLDR_PRODUCTION_DATA") ||
      Path.join([File.cwd!(), "..", "cldr_production_data"])
      |> Path.expand()
  end

  @doc """
  Returns the path to the CLDR repository checkout.

  Reads from the `CLDR_REPO` environment variable, falling back
  to `../cldr_repo` relative to the project root.

  """
  @spec cldr_repo_dir() :: String.t()
  def cldr_repo_dir do
    System.get_env("CLDR_REPO") ||
      Path.join([File.cwd!(), "..", "cldr_repo"])
      |> Path.expand()
  end

  @doc """
  Returns the path to the local CLDR supplemental JSON directory.

  This returns the path to locally copied supplemental source
  files in `priv/cldr/supplemental_data/`, not the external
  CLDR production data directory.

  """
  @spec supplemental_dir() :: String.t()
  def supplemental_dir do
    priv_relative_path(@cldr_supplemental_dir)
  end

  @doc """
  Returns the output directory for generated supplemental ETF files.

  """
  @spec output_dir() :: String.t()
  def output_dir do
    priv_relative_path(@supplemental_etf_dir)
  end

  @doc """
  Returns the path to the external sources directory.

  External sources are non-CLDR data files (such as the ISO 4217
  currency list) that supplement the CLDR data.

  """
  @spec external_sources_dir() :: String.t()
  def external_sources_dir do
    priv_relative_path(@cldr_external_sources_dir)
  end

  @doc """
  Returns the local path to the copied CLDR locale source data.

  After `copy_locale_sources/0`, locale JSON and XML files are
  stored in `priv/cldr/locales/<locale>/`.

  """
  @spec locales_source_dir() :: String.t()
  def locales_source_dir do
    priv_relative_path(@cldr_locales_dir)
  end

  @doc """
  Returns the local path to the copied CLDR supplemental source data.

  After `copy_supplemental_sources/0`, supplemental JSON and XML
  files are stored in `priv/cldr/supplemental_data/`.

  """
  @spec supplemental_source_dir() :: String.t()
  def supplemental_source_dir do
    priv_relative_path(@cldr_supplemental_dir)
  end

  @doc """
  Returns the local path to the copied CLDR collation XML data.

  """
  @spec collation_source_dir() :: String.t()
  def collation_source_dir do
    priv_relative_path(@cldr_collation_dir)
  end

  @doc """
  Returns the local path to the copied CLDR validity XML data.

  """
  @spec validity_source_dir() :: String.t()
  def validity_source_dir do
    priv_relative_path(@cldr_validity_dir)
  end

  @doc """
  Returns the local path to the copied BCP47 XML data.

  """
  @spec bcp47_source_dir() :: String.t()
  def bcp47_source_dir do
    priv_relative_path(@cldr_bcp47_dir)
  end

  # Resolves a project-relative path (e.g. `"priv/cldr/locales"`)
  # against the `:localize` application's own root directory,
  # rather than the current working directory.
  #
  # When Localize is used as a dependency and a task such as
  # `mix localize.generate_locales` is run from the dependent
  # project, `File.cwd!/0` returns the dependent project's root
  # and the data-pipeline helpers would look in the wrong place.
  # `:code.priv_dir(:localize)` returns `.../localize/priv` for
  # both the Localize repo itself and for any project that pulls
  # Localize in as a dep, so paths resolved relative to it are
  # stable across both scenarios.
  #
  # The input path always starts with `"priv/"` (the on-disk
  # layout), so we strip that prefix before joining to
  # `:code.priv_dir(:localize)`.
  defp priv_relative_path("priv/" <> rest) do
    :localize |> :code.priv_dir() |> Path.join(rest)
  end

  defp priv_relative_path(path) do
    :localize |> :code.priv_dir() |> Path.join(path)
  end

  @doc """
  Reads and decodes a JSON file from the CLDR supplemental directory.

  ### Arguments

  * `filename` is the JSON filename (e.g., `"aliases.json"`).

  ### Returns

  * The decoded JSON data as a map.

  """
  @spec read_json(String.t()) :: map()
  def read_json(filename) do
    supplemental_dir()
    |> Path.join(filename)
    |> File.read!()
    |> :json.decode()
  end

  @doc """
  Reads and decodes a JSON file from an arbitrary path
  under the CLDR production data directory.

  ### Arguments

  * `path` is the path relative to the CLDR production data root.

  ### Returns

  * The decoded JSON data as a map.

  """
  @spec read_json_path(String.t()) :: map()
  def read_json_path(path) do
    supplemental_source_dir()
    |> Path.join(path)
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
    File.write!(path, :erlang.term_to_binary(data))
    :ok
  end
end
