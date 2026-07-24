defmodule Localize.SupplementalData do
  @moduledoc false

  # ── Private helpers ─────────────────────────────────────────────

  defp localize_dir do
    Application.app_dir(:localize, "priv/localize")
  end

  defp load_supplemental(filename) do
    key = {:localize, :supplemental, filename}

    Localize.DataLoader.load(key, fn ->
      localize_dir()
      |> Path.join("supplemental_data")
      |> Path.join(filename)
      |> File.read!()
      |> :erlang.binary_to_term()
    end)
  end

  defp load_validity(filename) do
    key = {:localize, :validity, filename}

    Localize.DataLoader.load(key, fn ->
      localize_dir()
      |> Path.join("validity")
      |> Path.join(filename)
      |> File.read!()
      |> :erlang.binary_to_term()
    end)
  end

  # ── Public API ──────────────────────────────────────────────────

  @doc false
  @spec likely_subtags() :: %{String.t() => map()}
  def likely_subtags do
    load_supplemental("likely_subtags.etf")
  end

  @doc false
  # The CLDR compound-unit grammatical-derivation table, keyed by base
  # language subtag string (with `"root"` as the default). Read by the
  # unit formatter to derive each component's plural/case when composing
  # a compound unit that has no precomposed pattern.
  @spec unit_grammatical_derivations() :: %{String.t() => map()}
  def unit_grammatical_derivations do
    load_supplemental("unit_grammatical_derivations.etf")
  end

  @doc false
  @spec aliases() :: map()
  def aliases do
    load_supplemental("aliases.etf")
  end

  @doc false
  @spec language_matching() :: map()
  def language_matching do
    load_supplemental("language_matching.etf")
  end

  @doc false
  @spec all_locale_ids() :: [atom()]
  def all_locale_ids do
    load_supplemental("all_locale_names.etf")
  end

  @doc false
  @spec coverage_levels() :: %{basic: [atom()], moderate: [atom()], modern: [atom()]}
  def coverage_levels do
    load_supplemental("coverage_levels.etf")
  end

  @doc false
  @spec validity(atom()) :: map()
  def validity(:u), do: load_validity("validity_u.etf")
  def validity(:t), do: load_validity("validity_t.etf")
  def validity(:languages), do: load_validity("validity_languages.etf")
  def validity(:scripts), do: load_validity("validity_scripts.etf")
  def validity(:territories), do: load_validity("validity_territories.etf")
  def validity(:variants), do: load_validity("validity_variants.etf")
  def validity(:subdivisions), do: load_validity("validity_subdivisions.etf")
  def validity(:units), do: load_validity("validity_units.etf")

  @doc false
  @spec parent_locales() :: %{String.t() => String.t()}
  def parent_locales do
    load_supplemental("parent_locales.etf")
  end

  # Day-period rules from CLDR dayPeriods.xml, keyed by rule-set type
  # (:format for the B/b format symbols, :selection for name
  # selection), then by language code string. Times are minutes since
  # midnight; a rule is either %{at: t} or %{from: t, before: t}.
  @doc false
  @spec day_periods() :: %{format: map(), selection: map()}
  def day_periods do
    load_supplemental("day_periods.etf")
  end

  @doc false
  @spec timezones() :: map()
  def timezones do
    load_supplemental("timezones.etf")
  end

  # Metazone data with :mapzones (metazone → territory → IANA zone)
  # and :metazone_info (IANA zone → metazone usage periods).
  @doc false
  @spec metazones() :: %{mapzones: map(), metazone_info: map()}
  def metazones do
    load_supplemental("metazones.etf")
  end

  @doc false
  @spec unicode_script_to_subtag_mapping() :: map()
  def unicode_script_to_subtag_mapping do
    load_supplemental("unicode_script_to_subtag_mapping.etf")
  end

  @doc false
  @spec plural_rules(:cardinal | :ordinal) :: map()
  def plural_rules(:cardinal), do: load_supplemental("plural_rules_cardinal.etf")
  def plural_rules(:ordinal), do: load_supplemental("plural_rules_ordinal.etf")

  @doc false
  @spec plural_ranges() :: [map()]
  def plural_ranges do
    load_supplemental("plural_ranges.etf")
  end

  @doc false
  @spec currency_codes() :: [atom()]
  def currency_codes do
    load_supplemental("currency_codes.etf")
  end

  @doc false
  @spec territory_currencies() :: %{atom() => map()}
  def territory_currencies do
    load_supplemental("territory_currencies.etf")
  end

  @doc false
  @spec weeks() :: map()
  def weeks do
    load_supplemental("weeks.etf")
  end

  @doc false
  @spec calendar_preferences() :: %{atom() => [atom()]}
  def calendar_preferences do
    load_supplemental("calendar_preferences.etf")
  end

  @doc false
  @spec calendars() :: map()
  def calendars do
    load_supplemental("calendars.etf")
  end

  @doc false
  @spec known_territories() :: [atom()]
  def known_territories do
    load_supplemental("known_territories.etf")
  end

  @doc false
  @spec territory_containment() :: %{atom() => [atom()]}
  def territory_containment do
    load_supplemental("territory_containment.etf")
  end

  @doc false
  @spec territory_containers() :: %{atom() => [atom()]}
  def territory_containers do
    load_supplemental("territory_containers.etf")
  end

  @doc false
  @spec territory_subdivisions() :: %{atom() => [atom()]}
  def territory_subdivisions do
    load_supplemental("territory_subdivisions.etf")
  end

  @doc false
  @spec territory_subdivision_containment() :: %{atom() => [atom()]}
  def territory_subdivision_containment do
    load_supplemental("territory_subdivision_containment.etf")
  end

  @doc false
  @spec territories() :: %{atom() => map()}
  def territories do
    load_supplemental("territories.etf")
  end

  @doc false
  @spec territory_codes() :: %{atom() => map()}
  def territory_codes do
    load_supplemental("territory_codes.etf")
  end

  @doc false
  @spec measurement_systems() :: %{systems: map(), aliases: map()}
  def measurement_systems do
    load_supplemental("measurement_systems.etf")
  end

  @doc false
  @spec measurement_data() :: %{
          measurement_system: map(),
          measurement_system_temperature: map(),
          paper_size: map()
        }
  def measurement_data do
    load_supplemental("measurement_data.etf")
  end

  # ── Derived supplemental data ──────────────────────────────────

  # Returns a sorted list of locale identifier atoms for which
  # plural rules of the given type are defined.
  #
  # ### Arguments
  #
  # * `type` is either `:cardinal` or `:ordinal`.
  #
  # ### Returns
  #
  # * A sorted list of locale identifier atoms.
  #
  @doc false
  @spec plural_rules_locales(:cardinal | :ordinal) :: [atom()]
  def plural_rules_locales(type) when type in [:cardinal, :ordinal] do
    type
    |> plural_rules()
    |> Map.keys()
    |> Enum.sort()
  end
end
