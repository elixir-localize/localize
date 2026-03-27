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
  @locales_etf_dir "priv/localize/locales"
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
    {"cldr-numbers-full/main/en/currencies.json", "currencies_en.json"}
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
    {"collation_tailoring.etf", &Localize.Data.Collation.generate_collation_tailoring/0}
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

      # Copy subdivision XML if it exists
      sub_xml = Path.join([source_root, "subdivisions", "#{locale}.xml"])

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
    cldr_version = get_in(version_json, ["supplemental", "version", "_cldrVersion"])

    path = Path.join(File.cwd!(), @version_file)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, cldr_version)

    IO.puts("Wrote CLDR version #{cldr_version} to #{path}")
    cldr_version
  end

  @doc """
  Reads the CLDR version from `priv/localize/version`.

  ### Returns

  * The version string, or `nil` if the file does not exist.

  """
  @spec cldr_version() :: String.t() | nil
  def cldr_version do
    path = Path.join(File.cwd!(), @version_file)

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

  """
  @spec locales_output_dir() :: String.t()
  def locales_output_dir do
    Path.join(File.cwd!(), @locales_etf_dir)
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

    locales =
      Localize.SupplementalData.all_locale_ids()
      |> Enum.map(&Atom.to_string/1)

    total = length(locales)
    IO.puts("Generating #{total} locale ETF files...")

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
    Path.join(File.cwd!(), @cldr_supplemental_dir)
  end

  @doc """
  Returns the output directory for generated supplemental ETF files.

  """
  @spec output_dir() :: String.t()
  def output_dir do
    Path.join(File.cwd!(), @supplemental_etf_dir)
  end

  @doc """
  Returns the path to the external sources directory.

  External sources are non-CLDR data files (such as the ISO 4217
  currency list) that supplement the CLDR data.

  """
  @spec external_sources_dir() :: String.t()
  def external_sources_dir do
    Path.join(File.cwd!(), @cldr_external_sources_dir)
  end

  @doc """
  Returns the local path to the copied CLDR locale source data.

  After `copy_locale_sources/0`, locale JSON and XML files are
  stored in `priv/cldr/locales/<locale>/`.

  """
  @spec locales_source_dir() :: String.t()
  def locales_source_dir do
    Path.join(File.cwd!(), @cldr_locales_dir)
  end

  @doc """
  Returns the local path to the copied CLDR supplemental source data.

  After `copy_supplemental_sources/0`, supplemental JSON and XML
  files are stored in `priv/cldr/supplemental_data/`.

  """
  @spec supplemental_source_dir() :: String.t()
  def supplemental_source_dir do
    Path.join(File.cwd!(), @cldr_supplemental_dir)
  end

  @doc """
  Returns the local path to the copied CLDR collation XML data.

  """
  @spec collation_source_dir() :: String.t()
  def collation_source_dir do
    Path.join(File.cwd!(), @cldr_collation_dir)
  end

  @doc """
  Returns the local path to the copied CLDR validity XML data.

  """
  @spec validity_source_dir() :: String.t()
  def validity_source_dir do
    Path.join(File.cwd!(), @cldr_validity_dir)
  end

  @doc """
  Returns the local path to the copied BCP47 XML data.

  """
  @spec bcp47_source_dir() :: String.t()
  def bcp47_source_dir do
    Path.join(File.cwd!(), @cldr_bcp47_dir)
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
