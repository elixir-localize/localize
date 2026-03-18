defmodule Localize.Unit.Data do
  @moduledoc """
  Compile-time extraction of CLDR unit data from XML sources.

  This module reads the CLDR supplemental units XML and validity XML
  at compile time, exposing the extracted data as functions for use
  by the parser combinators.

  """

  import SweetXml

  @units_xml_path Path.join(
                    Application.compile_env(
                      :localize,
                      :cldr_data_dir,
                      "/Users/kip/Development/cldr_repo"
                    ),
                    "common/supplemental/units.xml"
                  )

  @validity_xml_path Path.join(
                       Application.compile_env(
                         :localize,
                         :cldr_data_dir,
                         "/Users/kip/Development/cldr_repo"
                       ),
                       "common/validity/unit.xml"
                     )

  @external_resource @units_xml_path
  @external_resource @validity_xml_path

  @units_xml Regex.replace(~r/<!DOCTYPE[^>]*>/, File.read!(@units_xml_path), "")
             |> parse()

  @validity_xml Regex.replace(~r/<!DOCTYPE[^>]*>/, File.read!(@validity_xml_path), "")
                |> parse()

  # ── Unit ID Components ──────────────────────────────────────────────

  @prefix_components @units_xml
                     |> xpath(~x"//unitIdComponent[@type='prefix']/@values"s)
                     |> String.split()

  @suffix_components @units_xml
                     |> xpath(~x"//unitIdComponent[@type='suffix']/@values"s)
                     |> String.split()

  @power_components @units_xml
                    |> xpath(~x"//unitIdComponent[@type='power']/@values"s)
                    |> String.split()

  # ── SI Prefixes ─────────────────────────────────────────────────────

  @si_prefix_data @units_xml
                  |> xpath(
                    ~x"//unitPrefix"l,
                    type: ~x"./@type"s,
                    symbol: ~x"./@symbol"s,
                    power10: ~x"./@power10"s,
                    power2: ~x"./@power2"s
                  )

  @si_prefix_names @si_prefix_data |> Enum.map(& &1.type)

  # ── Base Units (from convertUnit source attributes) ─────────────────

  @base_units @units_xml
              |> xpath(~x"//convertUnit/@source"ls)
              |> Kernel.++(["generic"])
              |> Enum.uniq()

  # ── Valid Unit Identifiers (from validity XML) ──────────────────────

  @valid_unit_identifiers @validity_xml
                          |> xpath(~x"//id[@type='unit' and @idStatus='regular']/text()"s)
                          |> String.split()

  @deprecated_unit_identifiers @validity_xml
                               |> xpath(~x"//id[@type='unit' and @idStatus='deprecated']/text()"s)
                               |> String.split()

  # ── Categories (derived from valid unit identifiers) ─────────────────

  @categories @valid_unit_identifiers
              |> Enum.map(fn identifier ->
                identifier |> String.split("-", parts: 2) |> hd()
              end)
              |> Enum.uniq()
              |> Enum.sort()

  # ── Public API ──────────────────────────────────────────────────────

  @doc """
  Returns the list of unit ID prefix components.

  ### Returns

  * A list of strings such as `["arc", "british", "dessert", ...]`.

  """
  @spec prefix_components() :: [String.t()]
  def prefix_components, do: @prefix_components

  @doc """
  Returns the list of unit ID suffix components.

  ### Returns

  * A list of strings such as `["force", "imperial", ...]`.

  """
  @spec suffix_components() :: [String.t()]
  def suffix_components, do: @suffix_components

  @doc """
  Returns the list of power components.

  ### Returns

  * A list of strings such as `["square", "cubic", "pow2", ...]`.

  """
  @spec power_components() :: [String.t()]
  def power_components, do: @power_components

  @doc """
  Returns the list of SI prefix names.

  ### Returns

  * A list of strings such as `["kilo", "milli", "mega", ...]`.

  """
  @spec si_prefix_names() :: [String.t()]
  def si_prefix_names, do: @si_prefix_names

  @doc """
  Returns detailed SI prefix data including symbols and powers.

  ### Returns

  * A list of maps with keys `:type`, `:symbol`, `:power10`, and `:power2`.

  """
  @spec si_prefix_data() :: [map()]
  def si_prefix_data, do: @si_prefix_data

  @doc """
  Returns the list of known base unit names from CLDR conversion data.

  ### Returns

  * A list of strings such as `["meter", "kilogram", "second", ...]`.

  """
  @spec base_units() :: [String.t()]
  def base_units, do: @base_units

  @doc """
  Returns all valid CLDR unit identifiers with regular status.

  ### Returns

  * A list of strings such as `["length-kilometer", "mass-kilogram", ...]`.

  """
  @spec valid_unit_identifiers() :: [String.t()]
  def valid_unit_identifiers, do: @valid_unit_identifiers

  @doc """
  Returns all deprecated CLDR unit identifiers.

  ### Returns

  * A list of strings.

  """
  @spec deprecated_unit_identifiers() :: [String.t()]
  def deprecated_unit_identifiers, do: @deprecated_unit_identifiers

  @doc """
  Returns the list of known unit categories.

  ### Returns

  * A list of strings such as `["acceleration", "angle", "area", ...]`.

  """
  @spec categories() :: [String.t()]
  def categories, do: @categories
end
