# Script: Extract CLDR unit data from XML to ETF
#
# This script parses the CLDR supplemental units.xml and validity/unit.xml
# files using SweetXml, extracts all unit data needed by Localize.Unit.Data,
# and saves it as an ETF file.
#
# Usage:
#   mix run scripts/extract_unit_data.exs [cldr_repo_path]
#
# Arguments:
#   cldr_repo_path - Path to the CLDR repository (default: ../cldr_repo)
#
# Output:
#   priv/unit/unit_data.etf
#
# Run this script whenever the CLDR data is updated.
# This script requires sweet_xml as a dependency.

import SweetXml
alias Localize.Unit.Data.Expression

cldr_repo =
  case System.argv() do
    [path | _] -> path
    [] -> Path.expand("../cldr_repo", __DIR__)
  end

units_xml_path = Path.join(cldr_repo, "common/supplemental/units.xml")
validity_xml_path = Path.join(cldr_repo, "common/validity/unit.xml")
output_path = Path.join([__DIR__, "..", "priv", "cldr", "supplemental_data", "unit_data.etf"]) |> Path.expand()

unless File.exists?(units_xml_path) do
  IO.puts(:stderr, "Error: #{units_xml_path} not found")
  System.halt(1)
end

unless File.exists?(validity_xml_path) do
  IO.puts(:stderr, "Error: #{validity_xml_path} not found")
  System.halt(1)
end

IO.puts("Parsing #{units_xml_path}...")
IO.puts("Parsing #{validity_xml_path}...")

# ── Parse XML files ──────────────────────────────────────────

parse = fn path ->
  xml = File.read!(path)
  xml = Regex.replace(~r/<!DOCTYPE[^>]*>/, xml, "")
  SweetXml.parse(xml)
end

units_xml = parse.(units_xml_path)
validity_xml = parse.(validity_xml_path)

# ── Unit ID Components ───────────────────────────────────────

prefix_components =
  units_xml
  |> xpath(~x"//unitIdComponent[@type='prefix']/@values"s)
  |> String.split()

suffix_components =
  units_xml
  |> xpath(~x"//unitIdComponent[@type='suffix']/@values"s)
  |> String.split()

power_components =
  units_xml
  |> xpath(~x"//unitIdComponent[@type='power']/@values"s)
  |> String.split()

IO.puts("  Extracted #{length(prefix_components)} prefix components")
IO.puts("  Extracted #{length(suffix_components)} suffix components")
IO.puts("  Extracted #{length(power_components)} power components")

# ── SI Prefixes ──────────────────────────────────────────────

si_prefix_data =
  units_xml
  |> xpath(
    ~x"//unitPrefix"l,
    type: ~x"./@type"s,
    symbol: ~x"./@symbol"s,
    power10: ~x"./@power10"s,
    power2: ~x"./@power2"s
  )

si_prefix_names = Enum.map(si_prefix_data, & &1.type)
IO.puts("  Extracted #{length(si_prefix_data)} SI prefixes")

# SI Prefix Multipliers
si_prefix_multipliers =
  Map.new(si_prefix_data, fn entry ->
    multiplier =
      cond do
        entry.power10 != "" ->
          :math.pow(10, String.to_integer(entry.power10))

        entry.power2 != "" ->
          :math.pow(2, String.to_integer(entry.power2))

        true ->
          1.0
      end

    {entry.type, multiplier}
  end)

# ── Base Units (from convertUnit source attributes) ──────────

raw_convert_units =
  units_xml
  |> xpath(
    ~x"//convertUnit"l,
    source: ~x"./@source"s,
    base_unit: ~x"./@baseUnit"s,
    factor: ~x"./@factor"s,
    offset: ~x"./@offset"s,
    special: ~x"./@special"s
  )

base_units =
  (Enum.map(raw_convert_units, & &1.source) ++ ["generic"])
  |> Enum.uniq()

conversions =
  Map.new(raw_convert_units, fn %{source: source, base_unit: base_unit} ->
    {source, base_unit}
  end)

IO.puts("  Extracted #{length(raw_convert_units)} unit conversions")

# ── Unit Quantities ──────────────────────────────────────────

unit_quantities =
  units_xml
  |> xpath(
    ~x"//unitQuantity"l,
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

IO.puts("  Extracted #{length(unit_quantities)} unit quantities")

# ── Unit Preferences ────────────────────────────────────────

unit_preferences =
  units_xml
  |> xpath(
    ~x"//unitPreferences"l,
    category: ~x"./@category"s,
    usage: ~x"./@usage"s,
    preferences: [
      ~x"./unitPreference"l,
      regions: ~x"./@regions"s,
      unit: ~x"./text()"s,
      geq: ~x"./@geq"os
    ]
  )

IO.puts("  Extracted #{length(unit_preferences)} unit preference groups")

# ── Unit Constants ───────────────────────────────────────────

raw_constants =
  units_xml
  |> xpath(
    ~x"//unitConstant"l,
    constant: ~x"./@constant"s,
    value: ~x"./@value"s
  )

# Resolve constants (some reference others)
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

IO.puts("  Resolved #{map_size(unit_constants)} unit constants")

# ── Conversion Factors and Offsets ───────────────────────────

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

IO.puts("  Computed #{map_size(conversion_factors)} conversion factors")

# ── Valid Unit Identifiers (from validity XML) ───────────────

valid_unit_identifiers =
  validity_xml
  |> xpath(~x"//id[@type='unit' and @idStatus='regular']/text()"s)
  |> String.split()

deprecated_unit_identifiers =
  validity_xml
  |> xpath(~x"//id[@type='unit' and @idStatus='deprecated']/text()"s)
  |> String.split()

IO.puts("  Extracted #{length(valid_unit_identifiers)} valid unit identifiers")
IO.puts("  Extracted #{length(deprecated_unit_identifiers)} deprecated unit identifiers")

# ── Categories (derived from valid identifiers) ─────────────

categories =
  valid_unit_identifiers
  |> Enum.map(fn identifier ->
    identifier |> String.split("-", parts: 2) |> hd()
  end)
  |> Enum.uniq()
  |> Enum.sort()

# ── Build and save ETF ───────────────────────────────────────

data = %{
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

File.write!(output_path, :erlang.term_to_binary(data))
IO.puts("\nSaved to #{output_path} (#{File.stat!(output_path).size} bytes)")
IO.puts("Done!")
