defmodule Localize.Data.XmlExtractors do
  @moduledoc """
  Generates supplemental data ETF files from raw CLDR XML source data.

  Uses SweetXml for XML parsing. Source files include BCP47 timezone
  data, plural range rules, subdivision containment, and unit data.

  """

  import SweetXml

  alias Localize.Utils.Map, as: LMap

  @zones_with_no_territory ["gmt", "unk"]

  @doc """
  Generates plural range data from `plural_ranges.xml`.

  Returns a list of maps with `:locales` (list of strings) and
  `:ranges` (list of maps with `:start`, `:end`, `:result` atoms).

  """
  def generate_plural_ranges do
    read_xml("plural_ranges.xml")
    |> xpath(~x"//pluralRanges"l,
      locales: ~x"./@locales"s,
      ranges: [
        ~x"./pluralRange"l,
        start: ~x"./@start"s,
        end: ~x"./@end"s,
        result: ~x"./@result"s
      ]
    )
    |> Enum.map(fn %{locales: locales, ranges: ranges} ->
      %{
        locales: String.split(locales, " "),
        ranges:
          Enum.map(ranges, fn range ->
            LMap.atomize_keys(range) |> LMap.atomize_values()
          end)
      }
    end)
  end

  @doc """
  Generates primary zone data from `metaZones.xml`.

  A primary zone is the timezone that names its whole territory, even
  where the territory has several zones. TR35 uses the list to decide
  whether the generic location format names a country or a city, so
  `Europe/Berlin` renders as "Germany Time" rather than "Berlin Time".

  Returns a map of IANA zone name strings to territory atoms.

  ### Returns

  * A map of `%{String.t() => atom()}`.

  """
  @spec generate_primary_zones() :: %{String.t() => atom()}
  def generate_primary_zones do
    read_xml("meta_zones.xml")
    |> xpath(~x"//primaryZones/primaryZone"l,
      territory: ~x"./@iso3166"s,
      zone: ~x"./text()"s
    )
    |> Map.new(fn %{territory: territory, zone: zone} ->
      {String.trim(zone), String.to_atom(territory)}
    end)
  end

  @doc """
  Generates timezone data from `bcp47/timezone.xml`.

  Returns a map of BCP47 timezone name strings to maps with
  `:aliases` (list of strings), `:territory` (atom or nil),
  and `:preferred` (string or nil).

  """
  def generate_timezones do
    [%{timezones: timezones}] =
      read_xml("bcp47/timezone.xml")
      |> xpath(~x"//key"l,
        timezones: [
          ~x"./type"l,
          name: ~x"./@name"s,
          alias: ~x"./@alias"s,
          region: ~x"./@region"s,
          preferred: ~x"./@preferred"s
        ]
      )

    Enum.map(timezones, fn
      %{alias: aliases, name: "ut" <> _rest = name, preferred: preferred} ->
        preferred = if preferred == "", do: nil, else: preferred
        {name, %{aliases: String.split(aliases, " "), territory: nil, preferred: preferred}}

      %{alias: aliases, name: name, preferred: preferred}
      when name in @zones_with_no_territory ->
        preferred = if preferred == "", do: nil, else: preferred
        {name, %{aliases: String.split(aliases, " "), territory: nil, preferred: preferred}}

      %{alias: aliases, name: name, region: "", preferred: ""} ->
        {name,
         %{aliases: String.split(aliases, " "), territory: implied_region(name), preferred: nil}}

      %{alias: aliases, name: name, region: region, preferred: ""} ->
        region = String.to_atom(region)
        {name, %{aliases: String.split(aliases, " "), territory: region, preferred: nil}}

      %{name: name, preferred: preferred} ->
        {name, %{aliases: nil, territory: nil, preferred: preferred}}
    end)
    |> Map.new()
  end

  # TR35 §Time Zone Identifiers: "The first two letters of a length 5 short
  # identifier double as the time zone's associated region ... Short
  # identifiers of length not equal to 5 are not associated with a region,
  # unless the time zone has an explicit `region` attribute." CLDR 49 makes
  # `pst8pdt` a zone of its own again, and reading its first two letters
  # placed it in Palestine.
  defp implied_region(name) when byte_size(name) == 5 do
    name |> String.slice(0, 2) |> String.upcase() |> String.to_atom()
  end

  defp implied_region(_name), do: nil

  @doc """
  Generates territory subdivision data from `subdivisions.xml`.

  Returns a map of territory/subdivision atoms to lists of
  contained subdivision atoms.

  """
  def generate_territory_subdivisions do
    read_xml("subdivisions.xml")
    |> xpath(~x"//subgroup"l,
      type: ~x"./@type"s,
      contains: ~x"./@contains"s
    )
    |> Enum.map(fn map ->
      key = safe_to_atom(map.type)
      values = String.split(map.contains) |> Enum.map(&safe_to_atom/1)
      {key, values}
    end)
    |> Map.new()
  end

  @doc """
  Generates territory subdivision containment chains derived
  from subdivision data.

  Returns a map of subdivision atoms to their ancestor chain
  as a list of atoms.

  """
  def generate_territory_subdivision_containment do
    subdivisions = generate_territory_subdivisions_raw()

    territory_parents =
      subdivisions
      |> Enum.flat_map(fn {k, v} ->
        Enum.map(v, fn t -> {t, k} end)
      end)

    territory_parents
    |> Enum.map(fn {k, v} ->
      {String.to_atom(k), Enum.map(parents(territory_parents, v), &String.to_atom/1)}
    end)
    |> Map.new()
  end

  @doc """
  Generates unit data from `units.xml` and `validity/unit.xml`.

  Returns a map matching the format produced by the
  `scripts/extract_unit_data.exs` script in the localize library.

  """
  def generate_unit_data do
    alias Localize.Unit.Data.Expression

    units_xml = read_xml("units.xml") |> SweetXml.parse()
    validity_xml = read_xml("validity/unit.xml") |> SweetXml.parse()

    # Unit ID Components
    prefix_components =
      units_xml |> xpath(~x"//unitIdComponent[@type='prefix']/@values"s) |> String.split()

    suffix_components =
      units_xml |> xpath(~x"//unitIdComponent[@type='suffix']/@values"s) |> String.split()

    power_components =
      units_xml |> xpath(~x"//unitIdComponent[@type='power']/@values"s) |> String.split()

    # SI Prefixes
    si_prefix_data =
      units_xml
      |> xpath(~x"//unitPrefix"l,
        type: ~x"./@type"s,
        symbol: ~x"./@symbol"s,
        power10: ~x"./@power10"s,
        power2: ~x"./@power2"s
      )

    si_prefix_names = Enum.map(si_prefix_data, & &1.type)

    si_prefix_multipliers =
      Map.new(si_prefix_data, fn entry ->
        multiplier =
          cond do
            entry.power10 != "" -> :math.pow(10, String.to_integer(entry.power10))
            entry.power2 != "" -> :math.pow(2, String.to_integer(entry.power2))
            true -> 1.0
          end

        {entry.type, multiplier}
      end)

    # Base Units (from convertUnit source attributes)
    raw_convert_units =
      units_xml
      |> xpath(~x"//convertUnit"l,
        source: ~x"./@source"s,
        base_unit: ~x"./@baseUnit"s,
        factor: ~x"./@factor"s,
        offset: ~x"./@offset"s,
        special: ~x"./@special"s
      )

    base_units = (Enum.map(raw_convert_units, & &1.source) ++ ["generic"]) |> Enum.uniq()

    conversions =
      Map.new(raw_convert_units, fn %{source: source, base_unit: base_unit} ->
        {source, base_unit}
      end)

    # Unit Quantities
    unit_quantities =
      units_xml
      |> xpath(~x"//unitQuantity"l,
        base_unit: ~x"./@baseUnit"s,
        quantity: ~x"./@quantity"s,
        status: ~x"./@status"s
      )

    simple_base_units =
      unit_quantities
      |> Enum.filter(&(&1.status == "simple"))
      |> Enum.map(& &1.base_unit)

    base_unit_order = Enum.map(unit_quantities, & &1.base_unit)

    base_unit_to_quantity =
      Map.new(unit_quantities, fn %{base_unit: bu, quantity: q} -> {bu, q} end)

    # Unit Preferences
    unit_preferences =
      units_xml
      |> xpath(~x"//unitPreferences"l,
        category: ~x"./@category"s,
        usage: ~x"./@usage"s,
        preferences: [
          ~x"./unitPreference"l,
          regions: ~x"./@regions"s,
          unit: ~x"./text()"s,
          geq: ~x"./@geq"os,
          skeleton: ~x"./@skeleton"os
        ]
      )

    # Unit Constants
    raw_constants =
      units_xml
      |> xpath(~x"//unitConstant"l,
        constant: ~x"./@constant"s,
        value: ~x"./@value"s
      )

    unit_constants =
      (fn raw ->
         initial =
           raw
           |> Enum.filter(fn %{value: v} ->
             not String.contains?(v, ["*", "/", " "]) or String.contains?(v, "E")
           end)
           |> Map.new(fn %{constant: c, value: v} ->
             {c, Expression.parse_number(v)}
           end)

         all_raw = Map.new(raw, fn %{constant: c, value: v} -> {c, v} end)
         Expression.resolve_all(all_raw, initial)
       end).(raw_constants)

    # Conversion Factors and Offsets
    conversion_factors =
      Map.new(raw_convert_units, fn %{
                                      source: source,
                                      factor: factor,
                                      offset: offset,
                                      special: special
                                    } ->
        factor_value =
          cond do
            special != "" -> :special
            factor == "" -> 1.0
            true -> Expression.evaluate_expression(factor, unit_constants)
          end

        offset_value =
          if offset == "",
            do: 0.0,
            else: Expression.evaluate_expression(offset, unit_constants)

        {source, %{factor: factor_value, offset: offset_value}}
      end)

    # Valid Unit Identifiers (from validity XML)
    valid_unit_identifiers =
      validity_xml
      |> xpath(~x"//id[@type='unit' and @idStatus='regular']/text()"s)
      |> String.split()

    deprecated_unit_identifiers =
      validity_xml
      |> xpath(~x"//id[@type='unit' and @idStatus='deprecated']/text()"s)
      |> String.split()

    # Categories (derived from valid identifiers)
    categories =
      valid_unit_identifiers
      |> Enum.map(fn identifier ->
        identifier |> String.split("-", parts: 2) |> hd()
      end)
      |> Enum.uniq()
      |> Enum.sort()

    %{
      prefix_components: prefix_components,
      suffix_components: suffix_components,
      power_components: power_components,
      si_prefix_data: si_prefix_data,
      si_prefix_names: si_prefix_names,
      si_prefix_multipliers: si_prefix_multipliers,
      base_units: base_units,
      conversions: conversions,
      unit_quantities: unit_quantities,
      simple_base_units: simple_base_units,
      base_unit_order: base_unit_order,
      base_unit_to_quantity: base_unit_to_quantity,
      unit_preferences: unit_preferences,
      unit_constants: unit_constants,
      conversion_factors: conversion_factors,
      valid_unit_identifiers: valid_unit_identifiers,
      deprecated_unit_identifiers: deprecated_unit_identifiers,
      categories: categories
    }
  end

  @doc """
  Generates the compound-unit grammatical-derivation table from
  `grammaticalFeatures.xml`.

  CLDR derives the plural category, grammatical case, and gender of a
  compound unit's components from the compound as a whole (TR35
  "Compound Units"). For example the default "times" derivation makes
  the leading component singular and lets the trailing component carry
  the count (`newton-meters`), while French pluralizes every component
  (`tonnes-kilomètres`). The unit formatter reads this table to compose
  the localized name of a compound unit that has no precomposed pattern.

  Returns a map keyed by the base language subtag string (plus `"root"`
  for the default), each value a map of the form:

      %{
        plural: %{times: {:one, :compound}, per: {:compound, :one}, ...},
        case: %{times: {:nominative, :compound}, ...},
        gender: %{times: 1, per: 0, ...}
      }

  For `deriveComponent` features (`:plural`, `:case`) the value is a
  `{value0, value1}` tuple where `:compound` means "use the compound's
  own category" and any other atom is a fixed category. For the
  `deriveCompound` `:gender` feature the value is the `0`/`1` index of
  the component whose gender the compound inherits. Each locale's block
  is merged over `"root"` so per-feature fallbacks are already resolved.

  """
  def generate_unit_grammatical_derivations do
    raw =
      "grammatical_features.xml"
      |> read_xml()
      |> SweetXml.parse()
      |> xpath(~x"//grammaticalDerivations"l,
        locales: ~x"./@locales"s,
        components: [
          ~x"./deriveComponent"l,
          feature: ~x"./@feature"s,
          structure: ~x"./@structure"s,
          value0: ~x"./@value0"s,
          value1: ~x"./@value1"s
        ],
        compounds: [
          ~x"./deriveCompound"l,
          feature: ~x"./@feature"s,
          structure: ~x"./@structure"s,
          value: ~x"./@value"s
        ]
      )
      |> Map.new(fn %{locales: locales, components: components, compounds: compounds} ->
        {locales, build_derivation_map(components, compounds)}
      end)

    root = Map.get(raw, "root", %{})

    raw
    |> Enum.flat_map(fn {locales, derivations} ->
      merged = deep_merge_derivations(root, derivations)
      for locale <- String.split(locales), do: {locale, merged}
    end)
    |> Map.new()
  end

  # Folds a block's `deriveComponent`/`deriveCompound` rows into the
  # nested `%{feature => %{structure => value}}` shape.
  defp build_derivation_map(components, compounds) do
    from_components =
      Enum.reduce(components, %{}, fn %{feature: feature, structure: structure} = row, acc ->
        value = {derivation_atom(row.value0), derivation_atom(row.value1)}
        put_derivation(acc, feature, structure, value)
      end)

    Enum.reduce(compounds, from_components, fn %{feature: feature, structure: structure} = row,
                                               acc ->
      put_derivation(acc, feature, structure, String.to_integer(row.value))
    end)
  end

  defp put_derivation(acc, feature, structure, value) do
    feature = String.to_atom(feature)
    structure = String.to_atom(structure)
    Map.update(acc, feature, %{structure => value}, &Map.put(&1, structure, value))
  end

  defp derivation_atom(""), do: nil
  defp derivation_atom(value), do: String.to_atom(value)

  # Merges a locale block over `root` at the feature level, so a locale
  # that overrides only some features (French overrides plural but not
  # case) inherits the rest from root.
  defp deep_merge_derivations(root, override) do
    Map.merge(root, override, fn _feature, root_structures, override_structures ->
      Map.merge(root_structures, override_structures)
    end)
  end

  @doc """
  Generates measurement system data from `bcp47/measure.xml`.

  Returns a map with two keys:

  * `:systems` — a map of canonical measurement system atoms to
    description strings. For example, `%{metric: "Metric System"}`.

  * `:aliases` — a map of alias atoms to their canonical
    measurement system atom. For example,
    `%{imperial: :uk, ussystem: :us, uksystem: :uk}`.

  The BCP 47 canonical names `ussystem` and `uksystem` are
  mapped to the short names `:us` and `:uk` respectively.

  """
  def generate_measurement_systems do
    [%{types: types}] =
      read_xml("bcp47/measure.xml")
      |> xpath(~x"//key[@name='ms']"l,
        types: [
          ~x"./type"l,
          name: ~x"./@name"s,
          description: ~x"./@description"s,
          alias: ~x"./@alias"s
        ]
      )

    canonical_name_map = %{
      "metric" => :metric,
      "ussystem" => :us,
      "uksystem" => :uk
    }

    {systems, aliases} =
      Enum.reduce(types, {%{}, %{}}, fn type, {systems_acc, aliases_acc} ->
        bcp47_name = type.name
        canonical = Map.fetch!(canonical_name_map, bcp47_name)
        systems_acc = Map.put(systems_acc, canonical, type.description)

        aliases_acc =
          aliases_acc
          |> add_bcp47_name_alias(bcp47_name, canonical)
          |> add_explicit_aliases(type.alias, canonical)

        {systems_acc, aliases_acc}
      end)

    %{systems: systems, aliases: aliases}
  end

  # Adds the BCP 47 name as an alias if it differs from the canonical short name.
  defp add_bcp47_name_alias(aliases, bcp47_name, canonical) do
    if String.to_atom(bcp47_name) != canonical do
      Map.put(aliases, String.to_atom(bcp47_name), canonical)
    else
      aliases
    end
  end

  # Adds any explicit aliases from the XML.
  defp add_explicit_aliases(aliases, "", _canonical), do: aliases

  defp add_explicit_aliases(aliases, alias_string, canonical) do
    alias_string
    |> String.split(" ")
    |> Enum.reduce(aliases, fn alias_name, acc ->
      Map.put(acc, String.to_atom(alias_name), canonical)
    end)
  end

  @doc """
  Generates measurement data from `measurementData.json`.

  Returns a map with three keys:

  * `:measurement_system` — a map of territory atoms to
    measurement system atoms (`:metric`, `:us`, or `:uk`).

  * `:measurement_system_temperature` — a map of territory atoms
    to measurement system atoms for temperature overrides.

  * `:paper_size` — a map of territory atoms to paper size atoms
    (`:a4` or `:us_letter`).

  """
  def generate_measurement_data do
    raw =
      Localize.Data.read_json("measurementData.json")
      |> get_in(["supplemental", "measurementData"])

    system_map = %{"metric" => :metric, "US" => :us, "UK" => :uk}
    paper_map = %{"A4" => :a4, "US-Letter" => :us_letter}

    measurement_system =
      raw
      |> Map.get("measurementSystem", %{})
      |> Enum.map(fn {territory, system} ->
        {String.to_atom(territory), Map.fetch!(system_map, system)}
      end)
      |> Map.new()

    temperature =
      raw
      |> Map.get("measurementSystem-category-temperature", %{})
      |> Enum.map(fn {territory, system} ->
        {String.to_atom(territory), Map.fetch!(system_map, system)}
      end)
      |> Map.new()

    paper_size =
      raw
      |> Map.get("paperSize", %{})
      |> Enum.map(fn {territory, size} ->
        {String.to_atom(territory), Map.fetch!(paper_map, size)}
      end)
      |> Map.new()

    %{
      measurement_system: measurement_system,
      measurement_system_temperature: temperature,
      paper_size: paper_size
    }
  end

  # ── Private helpers ─────────────────────────────────────────────

  # Maps short names to their directory and file in the CLDR repository.
  @xml_local_paths %{
    "plural_ranges.xml" => {:supplemental, "pluralRanges.xml"},
    "subdivisions.xml" => {:supplemental, "subdivisions.xml"},
    "bcp47/timezone.xml" => {:bcp47, "timezone.xml"},
    "bcp47/measure.xml" => {:bcp47, "measure.xml"},
    "units.xml" => {:supplemental, "units.xml"},
    "grammatical_features.xml" => {:supplemental, "grammaticalFeatures.xml"},
    "meta_zones.xml" => {:supplemental, "metaZones.xml"},
    "validity/unit.xml" => {:validity, "unit.xml"}
  }

  @doc """
  Returns the number symbols and formats root defines for numbering systems
  other than `latn`, from `common/main/root.xml`.

  cldr-json publishes a locale's numbering systems only where the locale
  uses them, so it carries none of root's `arab` and `arabext` data, which
  every locale without its own inherits under CLDR's inheritance. Root
  aliases the rest of a system's data to the locale's `latn`, and an alias
  is left out, for the locale's `latn` data to fill at runtime.

  ### Returns

  * A map keyed as cldr-json keys a locale's `numbers`, such as
    `"symbols-numberSystem-arab"` and `"percentFormats-numberSystem-arab"`.

  """
  @spec root_number_systems() :: %{String.t() => %{String.t() => String.t()}}
  def root_number_systems do
    root =
      Localize.Data.root_locale_source_path()
      |> File.read!()
      |> String.replace(~r/<!DOCTYPE.*>\n/, "")
      |> SweetXml.parse()

    blocks =
      [
        {"symbols", xpath(root, ~x"//numbers/symbols[@numberSystem!='latn']"l)},
        {"decimalFormats", xpath(root, ~x"//numbers/decimalFormats[@numberSystem!='latn']"l)},
        {"scientificFormats",
         xpath(root, ~x"//numbers/scientificFormats[@numberSystem!='latn']"l)},
        {"percentFormats", xpath(root, ~x"//numbers/percentFormats[@numberSystem!='latn']"l)},
        {"currencyFormats", xpath(root, ~x"//numbers/currencyFormats[@numberSystem!='latn']"l)}
      ]

    for {kind, nodes} <- blocks,
        node <- nodes,
        content = root_number_block(kind, node),
        content != %{},
        into: %{},
        do: {"#{kind}-numberSystem-#{xpath(node, ~x"./@numberSystem"s)}", content}
  end

  # A block is its own data, element by element, or an alias to the
  # locale's `latn`, which contributes nothing here. Anything else is a
  # structure this reader does not know, and generation stops rather than
  # drop it.
  defp root_number_block("symbols", node) do
    for element <- xpath(node, ~x"./*"l),
        name = xpath(element, ~x"name(.)"s),
        name != "alias",
        into: %{} do
      if xpath(element, ~x"./@alt"s) != "", do: unknown_root_number_data!(node)
      {name, xpath(element, ~x"./text()"s)}
    end
  end

  defp root_number_block("currencyFormats", node) do
    for element <- xpath(node, ~x"./*"l),
        name = xpath(element, ~x"name(.)"s),
        name not in ["alias", "currencySpacing"] or own_data?(element),
        reduce: %{} do
      patterns when name == "currencyFormatLength" ->
        Map.merge(patterns, currency_patterns(element, node))

      _patterns ->
        unknown_root_number_data!(node)
    end
  end

  defp root_number_block(kind, node) do
    length = String.replace_suffix(kind, "s", "Length")

    for element <- xpath(node, ~x"./*"l),
        name = xpath(element, ~x"name(.)"s),
        name != "alias",
        reduce: %{} do
      patterns when name == length ->
        if xpath(element, ~x"./@type"s) != "", do: unknown_root_number_data!(node)
        Map.merge(patterns, format_patterns(xpath(element, ~x"./*/pattern"l), "standard"))

      _patterns ->
        unknown_root_number_data!(node)
    end
  end

  # The patterns of each currency format type, `standard` and `accounting`,
  # with an alias to another type in the same length resolved to its
  # patterns, as cldr-json resolves it.
  defp currency_patterns(length, node) do
    if xpath(length, ~x"./@type"s) != "", do: unknown_root_number_data!(node)
    formats = xpath(length, ~x"./currencyFormat"l)
    own = Map.new(formats, &{xpath(&1, ~x"./@type"s), xpath(&1, ~x"./pattern"l)})

    for format <- formats, reduce: %{} do
      patterns ->
        type = xpath(format, ~x"./@type"s)

        case xpath(format, ~x"./alias/@path"s) do
          "" ->
            Map.merge(patterns, format_patterns(own[type], type))

          "../currencyFormat[@type='" <> rest ->
            target = String.trim_trailing(rest, "']")
            Map.merge(patterns, format_patterns(Map.fetch!(own, target), type))

          _other ->
            unknown_root_number_data!(node)
        end
    end
  end

  # A pattern is keyed by its type, and one with `alt` by type and alt, as
  # cldr-json keys them: `standard` and `standard-noCurrency`.
  defp format_patterns(patterns, type) do
    Map.new(patterns, fn pattern ->
      case xpath(pattern, ~x"./@alt"s) do
        "" -> {type, xpath(pattern, ~x"./text()"s)}
        alt -> {"#{type}-#{alt}", xpath(pattern, ~x"./text()"s)}
      end
    end)
  end

  defp own_data?(element), do: xpath(element, ~x"./*[name() != 'alias']"l) != []

  @spec unknown_root_number_data!(tuple()) :: no_return()
  defp unknown_root_number_data!(node) do
    raise "root.xml holds number data this pipeline does not read: " <>
            "#{xpath(node, ~x"name(.)"s)} numberSystem=#{xpath(node, ~x"./@numberSystem"s)}"
  end

  defp read_xml(short_name) do
    {dir_type, filename} = Map.fetch!(@xml_local_paths, short_name)

    dir =
      case dir_type do
        :supplemental -> Localize.Data.supplemental_xml_dir()
        :bcp47 -> Localize.Data.bcp47_source_dir()
        :validity -> Localize.Data.validity_source_dir()
      end

    dir
    |> Path.join(filename)
    |> File.read!()
    |> String.replace(~r/<!DOCTYPE.*>\n/, "")
  end

  defp generate_territory_subdivisions_raw do
    read_xml("subdivisions.xml")
    |> xpath(~x"//subgroup"l,
      type: ~x"./@type"s,
      contains: ~x"./@contains"s
    )
    |> Enum.map(fn map -> {map.type, String.split(map.contains)} end)
    |> Map.new()
  end

  defp parents(_territory_parents, nil), do: []

  defp parents(territory_parents, territory) do
    case :proplists.get_value(territory, territory_parents, nil) do
      nil -> parents_without_direct_parent(territory_parents, territory)
      parent -> [territory | parents(territory_parents, parent)]
    end
  end

  # Check if it's a top-level territory (2-char code)
  defp parents_without_direct_parent(territory_parents, territory) when is_atom(territory) do
    atom_string = Atom.to_string(territory)

    if String.length(atom_string) <= 3 and String.upcase(atom_string) == atom_string do
      [territory]
    else
      parents_by_matching_child(territory_parents, territory)
    end
  end

  defp parents_without_direct_parent(_territory_parents, territory) do
    [territory]
  end

  # Find parent by prefix matching
  defp parents_by_matching_child(territory_parents, territory) do
    parent_key = Enum.find_value(territory_parents, &matching_parent(&1, territory))

    if parent_key do
      [territory | parents(territory_parents, parent_key)]
    else
      [territory]
    end
  end

  defp matching_parent({child, parent}, territory) do
    child_string = if is_atom(child), do: Atom.to_string(child), else: child
    territory_string = Atom.to_string(territory)

    if child_string == territory_string do
      parent
    end
  end

  defp safe_to_atom(str) when is_binary(str) do
    if String.match?(str, ~r/^[A-Z]{2}$/) do
      String.to_atom(str)
    else
      String.to_atom(str)
    end
  end
end
