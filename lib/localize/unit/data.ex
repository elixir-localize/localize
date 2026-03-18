defmodule Localize.Unit.Data do
  @moduledoc """
  Compile-time extraction of CLDR unit data from XML sources.

  This module reads the CLDR supplemental units XML and validity XML
  at compile time, exposing the extracted data as functions for use
  by the parser combinators.

  """

  import SweetXml
  alias Localize.Unit.Data.Expression

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

  # ── Conversion Map (source → base unit string) ──────────────────────

  @conversions @units_xml
               |> xpath(
                 ~x"//convertUnit"l,
                 source: ~x"./@source"s,
                 base_unit: ~x"./@baseUnit"s
               )
               |> Map.new(fn %{source: source, base_unit: base_unit} -> {source, base_unit} end)

  # ── Unit Quantities (for canonical ordering and simple base units) ──

  @unit_quantities @units_xml
                   |> xpath(
                     ~x"//unitQuantity"l,
                     base_unit: ~x"./@baseUnit"s,
                     quantity: ~x"./@quantity"s,
                     status: ~x"./@status"s
                   )

  @simple_base_units @unit_quantities
                     |> Enum.filter(&(&1.status == "simple"))
                     |> Enum.map(& &1.base_unit)

  @base_unit_order @unit_quantities |> Enum.map(& &1.base_unit)

  # ── Unit Constants ───────────────────────────────────────────────────

  @raw_constants @units_xml
                 |> xpath(
                   ~x"//unitConstant"l,
                   constant: ~x"./@constant"s,
                   value: ~x"./@value"s
                 )

  # Evaluate constant expressions into float values. Constants can reference
  # other constants, so we resolve them in dependency order.
  @unit_constants (fn raw ->
                     initial =
                       raw
                       |> Enum.filter(fn %{value: v} ->
                         not String.contains?(v, ["*", "/", " "]) or
                           String.contains?(v, "E")
                       end)
                       |> Map.new(fn %{constant: c, value: v} ->
                         {c, Expression.parse_number(v)}
                       end)

                     all_raw = Map.new(raw, fn %{constant: c, value: v} -> {c, v} end)
                     Expression.resolve_all(all_raw, initial)
                   end).(@raw_constants)

  # ── Conversion Factors and Offsets ──────────────────────────────────

  @raw_convert_units @units_xml
                     |> xpath(
                       ~x"//convertUnit"l,
                       source: ~x"./@source"s,
                       base_unit: ~x"./@baseUnit"s,
                       factor: ~x"./@factor"s,
                       offset: ~x"./@offset"s,
                       special: ~x"./@special"s
                     )

  @conversion_factors (fn raw_units, constants ->
                         Map.new(raw_units, fn %{
                                                 source: source,
                                                 factor: factor,
                                                 offset: offset,
                                                 special: special
                                               } ->
                           factor_value =
                             cond do
                               special != "" -> :special
                               factor == "" -> 1.0
                               true -> Expression.evaluate_expression(factor, constants)
                             end

                           offset_value =
                             if offset == "",
                               do: 0.0,
                               else: Expression.evaluate_expression(offset, constants)

                           {source, %{factor: factor_value, offset: offset_value}}
                         end)
                       end).(@raw_convert_units, @unit_constants)

  # ── SI Prefix Multipliers ──────────────────────────────────────────

  @si_prefix_multipliers Map.new(@si_prefix_data, fn entry ->
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

  @doc """
  Returns a map from source unit name to its CLDR base unit string.

  ### Returns

  * A map such as `%{"foot" => "meter", "newton" => "kilogram-meter-per-square-second", ...}`.

  """
  @spec conversions() :: %{String.t() => String.t()}
  def conversions, do: @conversions

  @doc """
  Returns the list of fundamental (simple) base units.

  These are the units with `status='simple'` in the CLDR `unitQuantities`
  data and form the atoms of the dimensional decomposition system.

  ### Returns

  * A list of strings such as `["candela", "kilogram", "meter", "second", ...]`.

  """
  @spec simple_base_units() :: [String.t()]
  def simple_base_units, do: @simple_base_units

  @doc """
  Returns the canonical ordering of base units from `unitQuantities`.

  This ordering is used to reconstruct canonical base unit strings.

  ### Returns

  * A list of base unit strings in canonical order.

  """
  @spec base_unit_order() :: [String.t()]
  def base_unit_order, do: @base_unit_order

  @doc """
  Returns the resolved unit constants as a map of name to float value.

  ### Returns

  * A map such as `%{"ft_to_m" => 0.3048, "lb_to_kg" => 0.45359237, ...}`.

  """
  @spec unit_constants() :: %{String.t() => float()}
  def unit_constants, do: @unit_constants

  @doc """
  Returns the conversion factor and offset for each source unit.

  The conversion from source to base unit is: `base_value = value * factor + offset`.

  ### Returns

  * A map such as `%{"foot" => %{factor: 0.3048, offset: 0.0}, ...}`.

  """
  @spec conversion_factors() :: %{String.t() => %{factor: float() | :special, offset: float()}}
  def conversion_factors, do: @conversion_factors

  @doc """
  Returns SI prefix multipliers as a map of prefix name to numeric multiplier.

  ### Returns

  * A map such as `%{"kilo" => 1000.0, "milli" => 0.001, ...}`.

  """
  @spec si_prefix_multipliers() :: %{String.t() => float()}
  def si_prefix_multipliers, do: @si_prefix_multipliers
end
