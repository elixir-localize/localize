defmodule Localize.SupplementalData do
  @moduledoc """
  Provides access to CLDR supplemental data.

  Supplemental data is locale-independent reference data used across
  the Localize system. It includes likely subtags, aliases, validity
  data, plural rules, timezone mappings, currency codes, and other
  datasets defined by the Unicode CLDR project.

  All data is stored as pre-compiled ETF (Erlang Term Format) files
  in `priv/localize/` and deserialized on first access, then cached in
  `:persistent_term` for subsequent lookups. Supplemental data files
  are stored in `priv/localize/supplemental_data/`.

  """

  # ── Private helpers ─────────────────────────────────────────────

  defp localize_dir do
    :localize
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("localize")
  end

  defp load_data(filename) do
    key = {:localize, :data, filename}

    Localize.DataLoader.load(key, fn ->
      localize_dir()
      |> Path.join(filename)
      |> File.read!()
      |> :erlang.binary_to_term()
    end)
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

  @doc """
  Returns the likely subtags data as a map.

  Each key is a string like `"en"` or `"und-Latn"` and each
  value is a map with `:language`, `:script`, and `:territory`
  keys.

  """
  @spec likely_subtags() :: %{String.t() => map()}
  def likely_subtags do
    load_supplemental("likely_subtags.etf")
  end

  @doc """
  Returns the alias data as a map with keys `:language`,
  `:script`, `:region`, `:variant`, `:subdivision`, and `:zone`.

  """
  @spec aliases() :: map()
  def aliases do
    load_supplemental("aliases.etf")
  end

  @doc """
  Returns the language matching data as a map with keys
  `:language_match`, `:match_variables`, and `:paradigm_locales`.

  """
  @spec language_matching() :: map()
  def language_matching do
    load_supplemental("language_matching.etf")
  end

  @doc """
  Returns the list of all known locale identifier atoms.

  """
  @spec all_locale_ids() :: [atom()]
  def all_locale_ids do
    load_data("all_locale_names.etf")
  end

  @doc """
  Returns locale coverage level data as a map.

  The map has three keys — `:basic`, `:moderate`, and `:modern` —
  each containing a sorted list of locale ID atoms at that
  coverage level or above.

  """
  @spec coverage_levels() :: %{basic: [atom()], moderate: [atom()], modern: [atom()]}
  def coverage_levels do
    load_supplemental("coverage_levels.etf")
  end

  @doc """
  Returns validity data for the given type.

  ### Arguments

  * `type` is one of `:languages`, `:scripts`, `:territories`,
    `:variants`, `:u`, or `:t`.

  ### Returns

  * A map of validity data for the given type.

  """
  @spec validity(atom()) :: map()
  def validity(:u), do: load_validity("validity_u.etf")
  def validity(:t), do: load_validity("validity_t.etf")
  def validity(:languages), do: load_validity("validity_languages.etf")
  def validity(:scripts), do: load_validity("validity_scripts.etf")
  def validity(:territories), do: load_validity("validity_territories.etf")
  def validity(:variants), do: load_validity("validity_variants.etf")
  def validity(:subdivisions), do: load_validity("validity_subdivisions.etf")
  def validity(:units), do: load_validity("validity_units.etf")

  @doc """
  Returns the parent locales data as a map.

  Each key is a locale identifier string (e.g., `"en-AU"`) and
  each value is the parent locale identifier string (e.g., `"en-001"`).
  These override the default subtag-stripping inheritance chain
  defined by CLDR supplemental data.

  """
  @spec parent_locales() :: %{String.t() => String.t()}
  def parent_locales do
    load_supplemental("parent_locales.etf")
  end

  @doc """
  Returns the timezone data as a map.

  Each key is a BCP 47 timezone identifier string and each
  value is a map with `:preferred`, `:aliases`, and `:territory`
  keys.

  """
  @spec timezones() :: map()
  def timezones do
    load_supplemental("timezones.etf")
  end

  @doc """
  Returns a mapping from Unicode script names to BCP 47
  script subtag atoms.

  """
  @spec unicode_script_to_subtag_mapping() :: map()
  def unicode_script_to_subtag_mapping do
    load_data("unicode_script_to_subtag_mapping.etf")
  end

  @doc """
  Returns the compiled plural rules for the given type.

  The rules are pre-parsed into AST form so they can be
  used directly by the plural rule compiler at compile time.

  ### Arguments

  * `type` is either `:cardinal` or `:ordinal`.

  ### Returns

  * A map of locale name atoms to their parsed plural rule
    keyword lists.

  """
  @spec plural_rules(:cardinal | :ordinal) :: map()
  def plural_rules(:cardinal), do: load_supplemental("plural_rules_cardinal.etf")
  def plural_rules(:ordinal), do: load_supplemental("plural_rules_ordinal.etf")

  @doc """
  Returns the plural ranges data.

  Each entry contains a list of locales and a list of range
  mappings that determine the final plural category when
  formatting a number range.

  ### Returns

  * A list of maps with `:locales` and `:ranges` keys.

  """
  @spec plural_ranges() :: [map()]
  def plural_ranges do
    load_supplemental("plural_ranges.etf")
  end

  @doc """
  Returns a sorted list of all known ISO 4217 currency code atoms.

  """
  @spec currency_codes() :: [atom()]
  def currency_codes do
    load_supplemental("currency_codes.etf")
  end

  @doc """
  Returns a map of territory atoms to their currency history.

  Each territory maps to a map of currency code atoms to date
  information with `:from`, `:to`, and `:tender` keys.

  """
  @spec territory_currencies() :: %{atom() => map()}
  def territory_currencies do
    load_supplemental("territory_currencies.etf")
  end

  @doc """
  Returns the week information data for all territories.

  The returned map has keys `:first_day`, `:min_days`,
  `:weekend_start`, and `:weekend_end`. Each maps a territory
  atom to an integer day-of-week value (1 = Monday, 7 = Sunday).

  """
  @spec weeks() :: map()
  def weeks do
    load_supplemental("weeks.etf")
  end

  @doc """
  Returns the calendar preferences per territory.

  Each key is a territory atom and each value is a list of
  preferred calendar type atoms (e.g., `[:gregorian]` or
  `[:persian, :gregorian]`).

  """
  @spec calendar_preferences() :: %{atom() => [atom()]}
  def calendar_preferences do
    load_supplemental("calendar_preferences.etf")
  end

  @doc """
  Returns the CLDR calendar definitions including era data.

  Each key is a calendar type atom (e.g., `:gregorian`, `:japanese`)
  and each value is a map containing `:eras` (list of era definitions),
  optional `:calendar_system` (`:solar`, `:lunar`, `:lunisolar`, `:other`),
  and optional `:inherit_eras`.

  """
  @spec calendars() :: map()
  def calendars do
    load_supplemental("calendars.etf")
  end

  @doc """
  Returns the list of all known territory atoms.

  """
  @spec known_territories() :: [atom()]
  def known_territories do
    load_data("known_territories.etf")
  end

  @doc """
  Returns a map of each territory to its containment chain.

  Each key is a territory atom and each value is a list of
  parent territory atoms in order of increasing scope, ending
  with `:"001"` (the world).

  """
  @spec territory_containment() :: %{atom() => [atom()]}
  def territory_containment do
    load_supplemental("territory_containment.etf")
  end

  @doc """
  Returns a map of container territories to the territories
  they contain.

  For example, `:"001"` (the world) contains `:"019"` (Americas),
  `:"002"` (Africa), `:"150"` (Europe), `:"142"` (Asia), and
  `:"009"` (Oceania).

  """
  @spec territory_containers() :: %{atom() => [atom()]}
  def territory_containers do
    load_supplemental("territory_containers.etf")
  end

  @doc """
  Returns a map of territories and subdivisions to their
  child subdivision codes.

  """
  @spec territory_subdivisions() :: %{atom() => [atom()]}
  def territory_subdivisions do
    load_supplemental("territory_subdivisions.etf")
  end

  @doc """
  Returns a map of subdivision codes to their containment
  chain (parent subdivision and territory).

  """
  @spec territory_subdivision_containment() :: %{atom() => [atom()]}
  def territory_subdivision_containment do
    load_supplemental("territory_subdivision_containment.etf")
  end

  @doc """
  Returns a map of territory information including GDP,
  population, currency, measurement system, and language
  population data.

  """
  @spec territories() :: %{atom() => map()}
  def territories do
    load_supplemental("territories.etf")
  end

  @doc """
  Returns a map of territory codes (ISO 3166 Alpha-2) to
  their Alpha-3, FIPS 10, and numeric code equivalents.

  """
  @spec territory_codes() :: %{atom() => map()}
  def territory_codes do
    load_supplemental("territory_codes.etf")
  end

  @doc """
  Returns measurement system data parsed from `bcp47/measure.xml`.

  The returned map has two keys:

  * `:systems` — a map of canonical measurement system atoms
    (`:metric`, `:us`, `:uk`) to description strings.

  * `:aliases` — a map of alias atoms to their canonical
    measurement system atom (e.g., `%{imperial: :uk}`).

  """
  @spec measurement_systems() :: %{systems: map(), aliases: map()}
  def measurement_systems do
    load_supplemental("measurement_systems.etf")
  end

  @doc """
  Returns measurement data parsed from `measurementData.json`.

  The returned map has three keys:

  * `:measurement_system` — a map of territory atoms to
    measurement system atoms.

  * `:measurement_system_temperature` — a map of territory atoms
    to measurement system atoms for temperature overrides.

  * `:paper_size` — a map of territory atoms to paper size atoms.

  """
  @spec measurement_data() :: %{
          measurement_system: map(),
          measurement_system_temperature: map(),
          paper_size: map()
        }
  def measurement_data do
    load_supplemental("measurement_data.etf")
  end

  # ── Derived supplemental data ──────────────────────────────────

  # Returns a map of validated territory atoms to lists of
  # timezone zone maps.
  #
  # Each timezone zone map includes the original timezone data
  # plus a `:short_zone` key with the BCP 47 short zone code.
  # Territories that fail validation or are `nil` are excluded.
  #
  # ### Returns
  #
  # * A map where each key is a validated territory atom and
  #   each value is a list of zone maps.
  #
  @doc false
  @spec timezones_by_territory() :: %{atom() => [map()]}
  def timezones_by_territory do
    timezones()
    |> Enum.group_by(
      fn {_key, value} -> value.territory end,
      fn {key, value} -> Map.put(value, :short_zone, key) end
    )
    |> Enum.map(fn
      {nil, _} ->
        nil

      {territory, zones} ->
        case Localize.Validity.Territory.validate(territory) do
          {:ok, validated_territory, _status} ->
            {validated_territory, List.flatten(zones)}

          {:error, _} ->
            nil
        end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  # Returns a map of IANA timezone name strings to their
  # territory atoms.
  #
  # Built by inverting `timezones_by_territory/0` so that
  # each timezone alias maps to the territory it belongs to.
  # The synthetic `:UT` territory is excluded.
  #
  # ### Returns
  #
  # * A map where each key is an IANA timezone name string
  #   and each value is a territory atom.
  #
  @doc false
  @spec territories_by_timezone() :: %{String.t() => atom()}
  def territories_by_timezone do
    timezones_by_territory()
    |> Enum.map(fn {territory, zones} ->
      Enum.map(zones, fn zone ->
        Enum.map(zone.aliases, fn zone_alias ->
          {zone_alias, territory}
        end)
      end)
    end)
    |> List.flatten()
    |> Enum.reject(fn {_zone, territory} -> territory == :UT end)
    |> Map.new()
  end

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
