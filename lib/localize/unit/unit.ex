defmodule Localize.Unit do
  @moduledoc """
  Represents a CLDR unit of measure with its parsed structure.

  A `Localize.Unit` struct holds the original unit name string,
  its parsed AST representation, and an optional numeric value.

  """

  defstruct [
    :name,
    :parsed,
    :value,
    :usage
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          parsed: tuple(),
          value: number() | Decimal.t() | nil,
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
          {:ok, t()} | {:error, String.t()}

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
  @spec new(String.t()) :: {:ok, t()} | {:error, String.t()}

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

  def new!(amount, unit, options \\ []) when is_binary(unit) do
    case new(amount, unit, options) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
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

  def new!(name) when is_binary(name) do
    case new(name) do
      {:ok, unit} -> unit
      {:error, reason} -> raise ArgumentError, reason
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
  @spec convert(t(), String.t()) :: {:ok, t()} | {:error, String.t()}

  def convert(%__MODULE__{value: nil}, _target) do
    {:error, "Cannot convert a unit without a value"}
  end

  def convert(%__MODULE__{value: value, name: from_name}, target) when is_binary(target) do
    with {:ok, converted_value} <- Localize.Unit.Conversion.convert(value, from_name, target),
         {:ok, target_unit} <- new(converted_value, target) do
      {:ok, target_unit}
    end
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

  def convert!(%__MODULE__{} = unit, target) when is_binary(target) do
    case convert(unit, target) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
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
    {:error, "Cannot convert a unit without a value"}
  end

  def convert_measurement_system(%__MODULE__{} = unit, system)
      when system in [:metric, :us, :uk] do
    usage = unit.usage || "default"

    with {:ok, target_unit} <- preferred_unit(unit.name, system, usage) do
      convert(unit, target_unit)
    end
  end

  def convert_measurement_system(%__MODULE__{}, system) do
    {:error, "Invalid measurement system: #{inspect(system)}. Expected :metric, :us, or :uk"}
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
      nil -> {:error, "No quantity found for base unit: #{inspect(base_unit)}"}
      quantity -> {:ok, quantity}
    end
  end

  defp lookup_category(quantity) do
    case Map.get(@quantity_to_preference_category, quantity) do
      nil -> {:error, "No unit preferences found for quantity: #{inspect(quantity)}"}
      category -> {:ok, category}
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
         "No unit preferences for category #{inspect(category)} and usage #{inspect(usage)}"}

      %{preferences: preferences} ->
        case Enum.find(preferences, fn pref ->
               region in String.split(pref.regions)
             end) do
          nil ->
            {:error,
             "No unit preference for region #{inspect(region)} in category #{inspect(category)}"}

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
    {:error, "Expected a number (integer, float, or Decimal), got: #{inspect(value)}"}
  end

  defp validate_usage(nil), do: {:ok, nil}

  defp validate_usage(usage) when is_binary(usage) do
    if usage in @valid_usages do
      {:ok, usage}
    else
      {:error,
       "Invalid usage: #{inspect(usage)}. Valid usages are: #{Enum.join(@valid_usages, ", ")}"}
    end
  end

  defp validate_usage(usage) do
    {:error, "Expected usage to be a string or nil, got: #{inspect(usage)}"}
  end
end
