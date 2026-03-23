defmodule Localize.Unit do
  @moduledoc """
  Represents and formats CLDR units of measure.

  A `Localize.Unit` struct holds the original unit name string,
  its parsed AST representation, and an optional numeric value.
  Units can be created with `new/3` and formatted with
  `to_string/2`.

  ## Unit names

  Unit names follow the CLDR identifier syntax defined in
  [TR35](https://www.unicode.org/reports/tr35/tr35-general.html#unit-syntax).
  Examples: `"meter"`, `"kilogram"`, `"meter-per-second"`,
  `"square-kilometer"`, `"liter-per-100-kilometer"`.

  ## Formatting

  `to_string/2` produces locale-aware output with plural-sensitive
  patterns (e.g., `"1 kilometer"` vs `"3 kilometers"`) and supports
  `:long`, `:short`, and `:narrow` format styles.

  ## Usage preferences

  CLDR defines measurement usage preferences by territory and
  category (e.g., road distances in the US use miles). The
  `:usage` field on the struct and the `:usage` option on
  `to_string/2` support automatic unit selection based on locale.

  """

  defstruct [
    :name,
    :parsed,
    :value,
    :usage
  ]

  @type value :: number() | Decimal.t() | [number()] | nil

  @type t :: %__MODULE__{
          name: String.t(),
          parsed: tuple(),
          value: value(),
          usage: String.t() | nil
        }

  @valid_usages Localize.Unit.Data.unit_preferences()
                |> Enum.map(& &1.usage)
                |> Enum.uniq()
                |> Enum.sort()

  @doc """
  Creates a new unit with a value and a CLDR unit identifier string.

  ### Arguments

  * `amount` is the numeric value (integer, float, or Decimal).

  * `unit` is a unit identifier string such as `"meter-per-second"`.

  * `options` is an optional keyword list.

  ### Options

  * `:usage` is a string specifying the intended usage context for
    the unit. Valid values include `"default"`, `"person"`,
    `"person-height"`, `"road"`, `"food"`, `"vehicle-fuel"`,
    and others defined in the CLDR unit preference data. The usage
    affects which target unit is selected when calling
    `convert_measurement_system/2`.

  ### Returns

  * `{:ok, unit}` where `unit` is a `%Localize.Unit{}` struct, or

  * `{:error, reason}` if the value is not a valid number, the
    identifier cannot be parsed, or the usage is invalid.

  ### Examples

      iex> {:ok, unit} = Localize.Unit.new(100, "meter")
      iex> unit.value
      100
      iex> unit.name
      "meter"

      iex> {:ok, unit} = Localize.Unit.new(Decimal.new("3.14"), "kilogram")
      iex> unit.value
      Decimal.new("3.14")

      iex> {:ok, unit} = Localize.Unit.new(180, "centimeter", usage: "person-height")
      iex> unit.usage
      "person-height"

  """
  @spec new(number() | Decimal.t(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Exception.t()}

  def new(amount, unit, options \\ []) when is_binary(unit) do
    with {:ok, _} <- validate_value(amount),
         {:ok, parsed} <- Localize.Unit.Parser.parse(unit),
         {:ok, usage} <- validate_usage(Keyword.get(options, :usage)) do
      {canonical_name, normalised_ast} = Localize.Unit.Canonical.canonicalize(parsed)

      {:ok,
       %__MODULE__{
         name: canonical_name,
         parsed: normalised_ast,
         value: amount,
         usage: usage
       }}
    end
  end

  @doc """
  Creates a new unit from a CLDR unit identifier string without a value.

  ### Arguments

  * `name` is a unit identifier string such as `"meter-per-second"`.

  ### Returns

  * `{:ok, unit}` where `unit` is a `%Localize.Unit{}` struct, or

  * `{:error, reason}` if the identifier cannot be parsed.

  ### Examples

      iex> {:ok, unit} = Localize.Unit.new("meter")
      iex> unit.name
      "meter"

  """
  @spec new(String.t()) :: {:ok, t()} | {:error, Exception.t()}

  def new(name) when is_binary(name) do
    case Localize.Unit.Parser.parse(name) do
      {:ok, parsed} ->
        {canonical_name, normalised_ast} = Localize.Unit.Canonical.canonicalize(parsed)
        {:ok, %__MODULE__{name: canonical_name, parsed: normalised_ast}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Creates a new unit with a value and a CLDR unit identifier string,
  raising on error.

  Same as `new/2` but returns the struct directly or raises
  `ArgumentError`.

  ### Arguments

  * `amount` is the numeric value (integer, float, or Decimal).

  * `unit` is a unit identifier string.

  ### Returns

  * A `%Localize.Unit{}` struct.

  ### Examples

      iex> unit = Localize.Unit.new!(42, "kilogram")
      iex> unit.value
      42

  """
  @spec new!(number() | Decimal.t(), String.t(), keyword()) :: t() | no_return()
  @dialyzer {:nowarn_function, new!: 3}
  def new!(amount, unit, options \\ []) when is_binary(unit) do
    case new(amount, unit, options) do
      {:ok, result} -> result
      {:error, %{__exception__: true} = exception} -> raise exception
      {:error, reason} -> raise ArgumentError, Kernel.to_string(reason)
    end
  end

  @doc """
  Creates a new unit from a CLDR unit identifier string, raising on error.

  Same as `new/1` but returns the struct directly or raises
  `ArgumentError`.

  ### Arguments

  * `name` is a unit identifier string.

  ### Returns

  * A `%Localize.Unit{}` struct.

  ### Examples

      iex> unit = Localize.Unit.new!("meter")
      iex> unit.name
      "meter"

  """
  @spec new!(String.t()) :: t() | no_return()
  @dialyzer {:nowarn_function, new!: 1}
  def new!(name) when is_binary(name) do
    case new(name) do
      {:ok, unit} -> unit
      {:error, %{__exception__: true} = exception} -> raise exception
      {:error, reason} -> raise ArgumentError, Kernel.to_string(reason)
    end
  end

  @doc """
  Converts a unit to a different target unit.

  The source and target units must be convertible (same dimensional
  base unit). Returns a new unit struct with the converted value and
  the target unit type.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  * `target` is the target unit identifier string (e.g., `"foot"`).

  ### Returns

  * `{:ok, unit}` where `unit` is a new `%Localize.Unit{}` with
    the converted value and target unit type, or

  * `{:error, reason}` if the unit has no value, the target cannot
    be parsed, or the units are not convertible.

  ### Examples

      iex> {:ok, meters} = Localize.Unit.new(1, "kilometer")
      iex> {:ok, result} = Localize.Unit.convert(meters, "meter")
      iex> result.value
      1000.0
      iex> result.name
      "meter"

  """
  @spec convert(t(), String.t()) :: {:ok, t()} | {:error, Exception.t()}

  def convert(%__MODULE__{value: nil}, _target) do
    {:error,
     Localize.UnitConversionError.exception(
       from: nil,
       to: nil,
       reason: "Cannot convert a unit without a value"
     )}
  end

  def convert(%__MODULE__{value: value, name: from_name} = source, target)
      when is_binary(target) do
    with {:ok, target_parsed} <- Localize.Unit.Parser.parse(target) do
      case target_parsed do
        {:mixed_unit, _units} ->
          convert_to_mixed(source, target, target_parsed)

        _ ->
          # For mixed source units, convert the list of values to a scalar
          # in the primary component, then convert from that component.
          {source_value, effective_from} = effective_source(value, from_name, source.parsed)

          with {:ok, converted} <-
                 Localize.Unit.Conversion.convert(source_value, effective_from, target),
               {:ok, target_unit} <- new(converted, target) do
            {:ok, target_unit}
          end
      end
    end
  end

  # For mixed units, sum all component values into the primary (first) unit.
  # For regular units, pass through unchanged.
  defp effective_source(values, _name, {:mixed_unit, units}) when is_list(values) do
    {:single_unit, first_opts} = hd(units)
    first_name = format_single_unit_name(first_opts)
    {mixed_to_scalar(values, first_name, {:mixed_unit, units}), first_name}
  end

  defp effective_source(value, name, _parsed), do: {value, name}

  # Convert a scalar value from a source unit to a mixed target unit.
  # For example, 180 centimeter → foot-and-inch = [5, 11.024...]
  # Each component gets the integer part except the last which gets the remainder.
  defp convert_to_mixed(source, _target_name, {:mixed_unit, target_units}) do
    source_value = mixed_to_scalar(source.value, source.name, source.parsed)

    # Get the first target component name to check convertibility
    {:single_unit, first_opts} = hd(target_units)
    first_name = format_single_unit_name(first_opts)

    with {:ok, full_in_first} <-
           Localize.Unit.Conversion.convert(source_value, source.name, first_name) do
      values = distribute_mixed_values(full_in_first, target_units)

      {canonical_name, canonical_ast} =
        Localize.Unit.Canonical.canonicalize({:mixed_unit, target_units})

      {:ok,
       %__MODULE__{
         name: canonical_name,
         parsed: canonical_ast,
         value: values
       }}
    end
  end

  # Distribute a value across mixed unit components.
  # Each component except the last gets the integer (floor) part,
  # and the remainder is converted to the next component.
  defp distribute_mixed_values(value, [_last_unit]) do
    [value]
  end

  defp distribute_mixed_values(value, [current_unit | rest]) do
    integer_part = trunc(value)
    remainder = value - integer_part

    # Convert the remainder from the current unit to the next unit
    {:single_unit, current_opts} = current_unit
    {:single_unit, next_opts} = hd(rest)
    current_name = format_single_unit_name(current_opts)
    next_name = format_single_unit_name(next_opts)

    case Localize.Unit.Conversion.convert(remainder, current_name, next_name) do
      {:ok, remainder_in_next} ->
        [integer_part | distribute_mixed_values(remainder_in_next, rest)]

      {:error, _} ->
        # If conversion fails, put the remainder in the current unit
        [value]
    end
  end

  # Convert a mixed unit value (list of values) to a single scalar
  # in the unit's primary (first) component, for use as input to conversions.
  defp mixed_to_scalar(values, _name, {:mixed_unit, units}) when is_list(values) do
    {:single_unit, first_opts} = hd(units)
    first_name = format_single_unit_name(first_opts)

    values
    |> Enum.zip(units)
    |> Enum.reduce(0.0, fn {val, {:single_unit, opts}}, acc ->
      component_name = format_single_unit_name(opts)

      case Localize.Unit.Conversion.convert(val * 1.0, component_name, first_name) do
        {:ok, converted} -> acc + converted
        {:error, _} -> acc
      end
    end)
  end

  defp mixed_to_scalar(value, _name, _parsed) when is_number(value), do: value * 1.0

  defp mixed_to_scalar(%Decimal{} = value, _name, _parsed), do: Decimal.to_float(value)

  defp format_single_unit_name(opts) do
    prefix = Keyword.get(opts, :prefix)
    base = Keyword.get(opts, :base)
    prefix_str = if prefix, do: Atom.to_string(prefix), else: ""
    "#{prefix_str}#{base}"
  end

  @doc """
  Converts a unit to a different target unit, raising on error.

  Same as `convert/2` but returns the unit struct directly or raises
  `ArgumentError`.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  * `target` is the target unit identifier string.

  ### Returns

  * A `%Localize.Unit{}` struct with the converted value.

  ### Examples

      iex> unit = Localize.Unit.new!(1000, "meter")
      iex> result = Localize.Unit.convert!(unit, "kilometer")
      iex> result.value
      1.0

  """
  @spec convert!(t(), String.t()) :: t() | no_return()
  @dialyzer {:nowarn_function, convert!: 2}
  def convert!(%__MODULE__{} = unit, target) when is_binary(target) do
    case convert(unit, target) do
      {:ok, result} -> result
      {:error, %{__exception__: true} = exception} -> raise exception
      {:error, reason} -> raise ArgumentError, Kernel.to_string(reason)
    end
  end

  @doc """
  Converts a unit to the preferred unit for a given measurement system.

  Looks up the CLDR unit preference data for the unit's quantity
  category and the specified measurement system, then converts to
  the first preferred unit for the "default" usage.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  * `system` is the target measurement system: `:metric`, `:us`, or `:uk`.

  ### Returns

  * `{:ok, unit}` where `unit` is a new `%Localize.Unit{}` with the
    converted value and the preferred unit for that system, or

  * `{:error, reason}` if the unit has no value, the measurement
    system is invalid, or no preference is found.

  ### Examples

      iex> {:ok, meters} = Localize.Unit.new(100, "meter")
      iex> {:ok, result} = Localize.Unit.convert_measurement_system(meters, :us)
      iex> result.name
      "mile"

  """
  @spec convert_measurement_system(t(), :metric | :us | :uk) ::
          {:ok, t()} | {:error, String.t()}

  def convert_measurement_system(%__MODULE__{value: nil}, _system) do
    {:error,
     Localize.UnitConversionError.exception(
       from: nil,
       to: nil,
       reason: "Cannot convert a unit without a value"
     )}
  end

  def convert_measurement_system(%__MODULE__{} = unit, system)
      when system in [:metric, :us, :uk] do
    usage = unit.usage || "default"

    with {:ok, target_unit} <- preferred_unit(unit.name, system, usage) do
      convert(unit, target_unit)
    end
  end

  def convert_measurement_system(%__MODULE__{}, system) do
    {:error,
     Localize.InvalidValueError.exception(
       value: system,
       expected: ":metric, :us, or :uk",
       context: "measurement system"
     )}
  end

  # Measurement system to CLDR region code mapping.
  @system_regions %{metric: "001", us: "US", uk: "GB"}

  # Quantity names that differ between unitQuantity and unitPreferences.
  @quantity_to_preference_category %{
    "length" => "length",
    "mass" => "mass",
    "area" => "area",
    "volume" => "volume",
    "speed" => "speed",
    "temperature" => "temperature",
    "pressure" => "pressure",
    "energy" => "energy",
    "power" => "power",
    "duration" => "duration",
    "acceleration" => "acceleration",
    "force" => "force",
    "consumption" => "consumption",
    "mass-density" => "mass-density",
    "concentration" => "concentration",
    "year-duration" => "year-duration"
  }

  @unit_preferences Localize.Unit.Data.unit_preferences()
  @base_unit_to_quantity Localize.Unit.Data.base_unit_to_quantity()

  defp preferred_unit(unit_name, system, usage) do
    region = Map.fetch!(@system_regions, system)

    with {:ok, base_unit} <- Localize.Unit.BaseUnit.base_unit(unit_name),
         {:ok, quantity} <- lookup_quantity(base_unit),
         {:ok, category} <- lookup_category(quantity),
         {:ok, target} <- find_preference(category, region, usage) do
      {:ok, target}
    end
  end

  defp lookup_quantity(base_unit) do
    case Map.get(@base_unit_to_quantity, base_unit) do
      nil ->
        {:error,
         Localize.UnitPreferenceError.exception(
           unit: base_unit,
           region: nil,
           usage: nil,
           reason: "No quantity found for base unit: #{inspect(base_unit)}"
         )}

      quantity ->
        {:ok, quantity}
    end
  end

  defp lookup_category(quantity) do
    case Map.get(@quantity_to_preference_category, quantity) do
      nil ->
        {:error,
         Localize.UnitPreferenceError.exception(
           unit: nil,
           region: nil,
           usage: nil,
           reason: "No unit preferences found for quantity: #{inspect(quantity)}"
         )}

      category ->
        {:ok, category}
    end
  end

  defp find_preference(category, region, usage) do
    # Try the requested usage first, then fall back to "default"
    case find_preference_for_usage(category, region, usage) do
      {:ok, _} = result ->
        result

      {:error, _} when usage != "default" ->
        find_preference_for_usage(category, region, "default")

      error ->
        error
    end
  end

  defp find_preference_for_usage(category, region, usage) do
    case Enum.find(@unit_preferences, &(&1.category == category and &1.usage == usage)) do
      nil ->
        {:error,
         Localize.UnitPreferenceError.exception(
           unit: nil,
           region: nil,
           usage: usage,
           reason:
             "No unit preferences for category #{inspect(category)} and usage #{inspect(usage)}"
         )}

      %{preferences: preferences} ->
        case Enum.find(preferences, fn pref ->
               region in String.split(pref.regions)
             end) do
          nil ->
            {:error,
             Localize.UnitPreferenceError.exception(
               unit: nil,
               region: region,
               usage: nil,
               reason:
                 "No unit preference for region #{inspect(region)} in category #{inspect(category)}"
             )}

          %{unit: unit} ->
            {:ok, unit}
        end
    end
  end

  @doc false
  @spec from_ast(number() | Decimal.t(), String.t(), tuple()) :: t()
  def from_ast(value, name, parsed) do
    %__MODULE__{name: name, parsed: parsed, value: value}
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp validate_value(value) when is_integer(value), do: {:ok, value}
  defp validate_value(value) when is_float(value), do: {:ok, value}

  defp validate_value(%Decimal{} = value), do: {:ok, value}

  defp validate_value(value) do
    {:error,
     Localize.InvalidValueError.exception(
       value: value,
       expected: "a number (integer, float, or Decimal)",
       context: nil
     )}
  end

  defp validate_usage(nil), do: {:ok, nil}

  defp validate_usage(usage) when is_binary(usage) do
    if usage in @valid_usages do
      {:ok, usage}
    else
      {:error,
       Localize.InvalidValueError.exception(
         value: usage,
         expected: "a valid usage (one of: #{Enum.join(@valid_usages, ", ")})",
         context: "usage"
       )}
    end
  end

  defp validate_usage(usage) do
    {:error,
     Localize.InvalidValueError.exception(
       value: usage,
       expected: "a string or nil",
       context: "usage"
     )}
  end

  # ── Formatting ───────────────────────────────────────────────

  @doc """
  Formats a unit as a localized string.

  ### Arguments

  * `unit` is a `t:Localize.Unit.t/0` struct.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`. The default is `:en`.

  * `:style` is `:long`, `:short`, or `:narrow`.
    The default is `:long`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the unit cannot be formatted.

  ### Examples

      iex> {:ok, unit} = Localize.Unit.new(42, "meter")
      iex> Localize.Unit.to_string(unit)
      {:ok, "42 meters"}

      iex> {:ok, unit} = Localize.Unit.new(1, "meter")
      iex> Localize.Unit.to_string(unit)
      {:ok, "1 meter"}

      iex> {:ok, unit} = Localize.Unit.new(42, "meter")
      iex> Localize.Unit.to_string(unit, style: :short)
      {:ok, "42 m"}

  """
  @spec to_string(t(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(%__MODULE__{} = unit, options \\ []) do
    Localize.Unit.Formatter.to_string(unit, options)
  end

  @doc """
  Same as `to_string/2` but raises on error.

  ### Arguments

  * `unit` is a `t:Localize.Unit.t/0` struct.

  * `options` is a keyword list of options.

  ### Returns

  * A formatted string.

  ### Raises

  * Raises an exception if the unit cannot be formatted.

  """
  @spec to_string!(t(), Keyword.t()) :: String.t()
  def to_string!(%__MODULE__{} = unit, options \\ []) do
    case to_string(unit, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end
end
