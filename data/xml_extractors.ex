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
        region = String.slice(name, 0, 2) |> String.upcase() |> String.to_atom()
        {name, %{aliases: String.split(aliases, " "), territory: region, preferred: nil}}

      %{alias: aliases, name: name, region: region, preferred: ""} ->
        region = String.to_atom(region)
        {name, %{aliases: String.split(aliases, " "), territory: region, preferred: nil}}

      %{name: name, preferred: preferred} ->
        {name, %{aliases: nil, territory: nil, preferred: preferred}}
    end)
    |> Map.new()
  end

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

        # Add the BCP 47 name as an alias if it differs from the canonical short name
        aliases_acc =
          if String.to_atom(bcp47_name) != canonical do
            Map.put(aliases_acc, String.to_atom(bcp47_name), canonical)
          else
            aliases_acc
          end

        # Add any explicit aliases from the XML
        aliases_acc =
          if type.alias != "" do
            type.alias
            |> String.split(" ")
            |> Enum.reduce(aliases_acc, fn alias_name, acc ->
              Map.put(acc, String.to_atom(alias_name), canonical)
            end)
          else
            aliases_acc
          end

        {systems_acc, aliases_acc}
      end)

    %{systems: systems, aliases: aliases}
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

  # Maps short names to their local paths under priv/cldr/
  @xml_local_paths %{
    "plural_ranges.xml" => {:supplemental, "pluralRanges.xml"},
    "subdivisions.xml" => {:supplemental, "subdivisions.xml"},
    "bcp47/timezone.xml" => {:bcp47, "timezone.xml"},
    "bcp47/measure.xml" => {:bcp47, "measure.xml"},
    "units.xml" => {:supplemental, "units.xml"},
    "validity/unit.xml" => {:validity, "unit.xml"}
  }

  defp read_xml(short_name) do
    {dir_type, filename} = Map.fetch!(@xml_local_paths, short_name)

    dir =
      case dir_type do
        :supplemental -> Localize.Data.supplemental_source_dir()
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
    parent = :proplists.get_value(territory, territory_parents, nil)

    case parent do
      nil ->
        # Check if it's a top-level territory (2-char code)
        if is_atom(territory) do
          atom_str = Atom.to_string(territory)

          if String.length(atom_str) <= 3 and String.upcase(atom_str) == atom_str do
            [territory]
          else
            # Find parent by prefix matching
            parent_key =
              Enum.find_value(territory_parents, fn {child, p} ->
                child_str = if is_atom(child), do: Atom.to_string(child), else: child
                t_str = Atom.to_string(territory)

                if child_str == t_str do
                  p
                end
              end)

            if parent_key do
              [territory | parents(territory_parents, parent_key)]
            else
              [territory]
            end
          end
        else
          [territory]
        end

      p ->
        [territory | parents(territory_parents, p)]
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
