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
         :ok <- validate_currency_codes(parsed),
         :ok <- validate_base_names(parsed),
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
  @dialyzer {:nowarn_function, new: 1}

  def new(name) when is_binary(name) do
    with {:ok, parsed} <- Localize.Unit.Parser.parse(name),
         :ok <- validate_currency_codes(parsed),
         :ok <- validate_base_names(parsed) do
      {canonical_name, normalised_ast} = Localize.Unit.Canonical.canonicalize(parsed)
      {:ok, %__MODULE__{name: canonical_name, parsed: normalised_ast}}
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
      {:error, exception} -> raise exception
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
      {:error, exception} -> raise exception
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
    {:error, Localize.UnitNoValueError.exception(operation: :convert)}
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
      {:error, exception} -> raise exception
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
    {:error, Localize.UnitNoValueError.exception(operation: :convert)}
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
           reason: :unknown_quantity,
           unit: base_unit
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
           reason: :unknown_category,
           quantity: quantity
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
           reason: :no_preference_for_usage,
           category: category,
           usage: usage
         )}

      %{preferences: preferences} ->
        case Enum.find(preferences, fn pref ->
               region in String.split(pref.regions)
             end) do
          nil ->
            {:error,
             Localize.UnitPreferenceError.exception(
               reason: :no_preference_for_region,
               category: category,
               region: region
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

  # ── Custom unit registration ────────────────────────────────────────

  @doc """
  Registers a custom unit definition at runtime.

  Custom units extend the built-in CLDR unit database with user-defined
  units. Each custom unit must specify a base unit it converts to, a
  conversion factor, and a category.

  ### Arguments

  * `name` is a string unit identifier (e.g., `"smoot"`). Must start with
    a lowercase letter and contain only lowercase letters, digits, and hyphens.

  * `definition` is a map with the following keys:

  ### Options

  * `:base_unit` (required) — the CLDR base unit this custom unit converts
    to (e.g., `"meter"`, `"kilogram"`).

  * `:factor` (required) — conversion multiplier:
    `1 custom_unit = factor * base_unit`.

  * `:offset` (optional) — additive offset for temperature-like conversions.
    Defaults to `0.0`.

  * `:category` (required) — the unit category (e.g., `"length"`, `"mass"`).

  * `:display` (optional) — locale-specific display patterns. A nested map
    of `locale => style => plural_patterns`.

  ### Returns

  * `:ok` on success.

  * `{:error, reason}` if validation fails.

  ### Examples

      iex> Localize.Unit.define_unit("smoot", %{
      ...>   base_unit: "meter",
      ...>   factor: 1.7018,
      ...>   category: "length",
      ...>   display: %{en: %{long: %{one: "{0} smoot", other: "{0} smoots"}}}
      ...> })
      :ok

  """
  @spec define_unit(String.t(), map()) :: :ok | {:error, String.t()}
  def define_unit(name, definition) do
    Localize.Unit.CustomRegistry.register(name, definition)
  end

  @doc """
  Loads custom unit definitions from an Elixir term file (`.exs`).

  The file must evaluate to a list of maps, each with a `:unit` key
  and the standard definition fields (`:base_unit`, `:factor`,
  `:category`, and optionally `:display`).

  > #### Security {: .warning}
  >
  > This function uses `Code.eval_file/1` to evaluate the given
  > file, which executes arbitrary Elixir code. Only load files
  > from trusted sources. Never call this function with unsanitised
  > user input or paths derived from external data.

  ### Arguments

  * `path` is the path to the `.exs` file.

  ### Returns

  * `{:ok, count}` with the number of units loaded.

  * `{:error, reason}` on failure.

  """
  @spec load_custom_units(String.t()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def load_custom_units(path) do
    Localize.Unit.CustomRegistry.load_file(path)
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

  defp validate_currency_codes({:unit, keyword}) do
    units = Keyword.get(keyword, :numerator, []) ++ Keyword.get(keyword, :denominator, [])
    validate_currency_codes_in_list(units)
  end

  defp validate_currency_codes({:mixed_unit, units}) do
    validate_currency_codes_in_list(units)
  end

  defp validate_currency_codes_in_list(units) do
    Enum.reduce_while(units, :ok, fn
      {:single_unit, kw}, :ok ->
        case Keyword.fetch!(kw, :base) do
          "curr-" <> code ->
            case Localize.Currency.validate_currency(code) do
              {:ok, _} -> {:cont, :ok}
              {:error, _} = error -> {:halt, error}
            end

          _ ->
            {:cont, :ok}
        end

      _, :ok ->
        {:cont, :ok}
    end)
  end

  @known_base_units MapSet.new(Localize.Unit.Data.base_units())

  defp validate_base_names({:unit, keyword}) do
    units = Keyword.get(keyword, :numerator, []) ++ Keyword.get(keyword, :denominator, [])
    validate_base_names_in_list(units)
  end

  defp validate_base_names({:mixed_unit, units}) do
    validate_base_names_in_list(units)
  end

  defp validate_base_names_in_list(units) do
    Enum.reduce_while(units, :ok, fn
      {:single_unit, kw}, :ok ->
        base = Keyword.fetch!(kw, :base)

        cond do
          # Currency units are validated separately
          String.starts_with?(base, "curr-") ->
            {:cont, :ok}

          # Known CLDR base unit
          MapSet.member?(@known_base_units, base) ->
            {:cont, :ok}

          # Registered custom unit
          Localize.Unit.CustomRegistry.registered?(base) ->
            {:cont, :ok}

          true ->
            {:halt, {:error, Localize.UnknownUnitError.exception(unit: base)}}
        end

      {:constant, _}, :ok ->
        {:cont, :ok}

      _, :ok ->
        {:cont, :ok}
    end)
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

  * `:format` is `:long`, `:short`, or `:narrow`.
    The default is `:long`.

  * `:backend` is `:nif` or `:elixir`. When `:nif` is
    specified and the NIF is available, ICU4C is used for
    formatting. Otherwise falls back to the pure-Elixir
    formatter. The default is `:elixir`.

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
      iex> Localize.Unit.to_string(unit, format: :short)
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

  @doc """
  Formats a unit as an iolist.

  Same as `to_string/2` but returns an iolist for efficient
  IO operations without an intermediate binary allocation.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct.

  * `options` is a keyword list of formatting options (same as `to_string/2`).

  ### Returns

  * `{:ok, iolist}` or `{:error, exception}`.

  """
  @spec to_iolist(t(), Keyword.t()) :: {:ok, iolist()} | {:error, Exception.t()}
  def to_iolist(%__MODULE__{} = unit, options \\ []) do
    case to_string(unit, options) do
      {:ok, string} -> {:ok, [string]}
      error -> error
    end
  end

  # ── Arithmetic ────────────────────────────────────────────────

  @doc """
  Adds two convertible units.

  The value of `unit_2` is converted to the unit type of `unit_1`
  before addition. The result retains the unit type of `unit_1`.

  ### Arguments

  * `unit_1` is a `%Localize.Unit{}` struct with a value.

  * `unit_2` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, unit}` or `{:error, exception}`.

  ### Examples

      iex> {:ok, a} = Localize.Unit.new(1, "kilometer")
      iex> {:ok, b} = Localize.Unit.new(500, "meter")
      iex> {:ok, result} = Localize.Unit.add(a, b)
      iex> result.value
      1.5

  """
  @spec add(t(), t()) :: {:ok, t()} | {:error, Exception.t() | String.t()}
  defdelegate add(unit_1, unit_2), to: Localize.Unit.Math

  @doc """
  Subtracts `unit_2` from `unit_1`.

  The value of `unit_2` is converted to the unit type of `unit_1`.

  ### Arguments

  * `unit_1` is a `%Localize.Unit{}` struct with a value.

  * `unit_2` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, unit}` or `{:error, exception}`.

  ### Examples

      iex> {:ok, a} = Localize.Unit.new(5, "kilometer")
      iex> {:ok, b} = Localize.Unit.new(2000, "meter")
      iex> {:ok, result} = Localize.Unit.sub(a, b)
      iex> result.value
      3.0

  """
  @spec sub(t(), t()) :: {:ok, t()} | {:error, Exception.t() | String.t()}
  defdelegate sub(unit_1, unit_2), to: Localize.Unit.Math

  @doc """
  Multiplies a unit by a scalar or another unit.

  When multiplied by a number, the value is scaled. When multiplied
  by another unit, a compound unit is produced (e.g., meter × second).

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct.

  * `multiplier` is a number or a `%Localize.Unit{}` struct.

  ### Returns

  * `{:ok, unit}` or `{:error, exception}`.

  ### Examples

      iex> {:ok, m} = Localize.Unit.new(5, "meter")
      iex> {:ok, result} = Localize.Unit.mult(m, 3)
      iex> result.value
      15

  """
  @spec mult(t(), number() | t()) :: {:ok, t()} | {:error, Exception.t()}
  defdelegate mult(unit, multiplier), to: Localize.Unit.Math

  @doc """
  Divides a unit by a scalar or another unit.

  When divided by a number, the value is scaled. When divided by
  another unit, a per-unit compound is produced (e.g., meter ÷ second).

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct.

  * `divisor` is a number or a `%Localize.Unit{}` struct.

  ### Returns

  * `{:ok, unit}` or `{:error, exception}`.

  ### Examples

      iex> {:ok, m} = Localize.Unit.new(10, "meter")
      iex> {:ok, result} = Localize.Unit.div(m, 2)
      iex> result.value
      5.0

  """
  @spec div(t(), number() | t()) :: {:ok, t()} | {:error, Exception.t()}
  defdelegate div(unit, divisor), to: Localize.Unit.Math

  @doc """
  Negates a unit's value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `{:ok, unit}` or `{:error, exception}`.

  """
  @spec negate(t()) :: {:ok, t()} | {:error, Exception.t()}
  defdelegate negate(unit), to: Localize.Unit.Math

  @doc """
  Compares two convertible units.

  The value of `unit_2` is converted to the unit type of `unit_1`
  before comparison.

  ### Arguments

  * `unit_1` is a `%Localize.Unit{}` struct with a value.

  * `unit_2` is a `%Localize.Unit{}` struct with a value.

  ### Returns

  * `:lt`, `:eq`, or `:gt`.

  * `{:error, exception}` if the units are not convertible.

  ### Examples

      iex> {:ok, a} = Localize.Unit.new(1, "kilometer")
      iex> {:ok, b} = Localize.Unit.new(500, "meter")
      iex> Localize.Unit.compare(a, b)
      :gt

  """
  @spec compare(t(), t()) :: :lt | :eq | :gt | {:error, Exception.t()}
  def compare(%__MODULE__{value: v1} = _unit_1, %__MODULE__{value: v2} = _unit_2)
      when is_nil(v1) or is_nil(v2) do
    {:error, Localize.UnitNoValueError.exception(operation: :compare)}
  end

  def compare(%__MODULE__{} = unit_1, %__MODULE__{} = unit_2) do
    case Localize.Unit.Conversion.convert(unit_2.value, unit_2.name, unit_1.name) do
      {:ok, converted} ->
        v1 = to_float(unit_1.value)
        v2 = to_float(converted)

        cond do
          v1 < v2 -> :lt
          v1 > v2 -> :gt
          true -> :eq
        end

      {:error, _} = error ->
        error
    end
  end

  # ── Decompose ─────────────────────────────────────────────────

  @doc """
  Decomposes a unit into a list of units with the given target units.

  This is used for mixed-unit formatting, for example converting
  1.75 meters into `[1 meter, 75 centimeters]` or 5.25 feet into
  `[5 feet, 3 inches]`.

  Each target unit receives the integer part of the remaining value,
  except the last unit which receives the remainder.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  * `target_units` is a list of unit name strings, ordered from
    largest to smallest (e.g., `["foot", "inch"]`).

  ### Returns

  * `{:ok, units}` where `units` is a list of `%Localize.Unit{}` structs.

  * `{:error, exception}` if conversion fails.

  ### Examples

      iex> {:ok, m} = Localize.Unit.new(1.75, "meter")
      iex> {:ok, parts} = Localize.Unit.decompose(m, ["meter", "centimeter"])
      iex> Enum.map(parts, fn u -> {u.name, u.value} end)
      [{"meter", 1}, {"centimeter", 75.0}]

  """
  @spec decompose(t(), [String.t()]) :: {:ok, [t()]} | {:error, Exception.t()}
  def decompose(%__MODULE__{value: nil}, _targets) do
    {:error, Localize.UnitNoValueError.exception(operation: :decompose)}
  end

  def decompose(%__MODULE__{} = unit, [single]) do
    case convert(unit, single) do
      {:ok, converted} -> {:ok, [converted]}
      error -> error
    end
  end

  def decompose(%__MODULE__{} = unit, [target | rest]) do
    case convert(unit, target) do
      {:ok, converted} ->
        float_value = to_float(converted.value)
        integer_part = trunc(float_value)
        remainder = float_value - integer_part

        with {:ok, remainder_unit} <- new(remainder, target),
             {:ok, rest_parts} <- decompose(remainder_unit, rest) do
          {:ok, [%{converted | value: integer_part} | rest_parts]}
        end

      error ->
        error
    end
  end

  def decompose(%__MODULE__{}, []) do
    {:ok, []}
  end

  # ── Accessors ─────────────────────────────────────────────────

  @doc """
  Returns the numeric value of a unit.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct.

  ### Returns

  * The value (number, Decimal, or nil).

  ### Examples

      iex> {:ok, m} = Localize.Unit.new(42, "meter")
      iex> Localize.Unit.value(m)
      42

  """
  @spec value(t()) :: value()
  def value(%__MODULE__{value: value}), do: value

  @doc """
  Returns a zero-valued unit of the same type.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct.

  ### Returns

  * A new `%Localize.Unit{}` with value `0`.

  ### Examples

      iex> {:ok, m} = Localize.Unit.new(42, "meter")
      iex> z = Localize.Unit.zero(m)
      iex> z.value
      0

  """
  @spec zero(t()) :: t()
  def zero(%__MODULE__{} = unit), do: %{unit | value: 0}

  @doc """
  Returns true if the unit has a zero value.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> {:ok, m} = Localize.Unit.new(0, "meter")
      iex> Localize.Unit.zero?(m)
      true

  """
  @spec zero?(t()) :: boolean()
  def zero?(%__MODULE__{value: value}) when is_number(value) and value == 0, do: true
  def zero?(%__MODULE__{value: %Decimal{coef: 0}}), do: true
  def zero?(%__MODULE__{}), do: false

  # ── Introspection ─────────────────────────────────────────────

  @doc """
  Returns the CLDR category for a unit.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct or a unit name string.

  ### Returns

  * `{:ok, category}` where category is a string like `"length"`, or

  * `{:error, exception}`.

  ### Examples

      iex> {:ok, m} = Localize.Unit.new(1, "meter")
      iex> Localize.Unit.unit_category(m)
      {:ok, "length"}

      iex> Localize.Unit.unit_category("kilogram")
      {:ok, "mass"}

  """
  @spec unit_category(t() | String.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def unit_category(%__MODULE__{name: name}), do: unit_category(name)

  def unit_category(name) when is_binary(name) do
    btq = Localize.Unit.Data.base_unit_to_quantity()

    case Map.get(btq, name) do
      nil ->
        with {:ok, parsed} <- Localize.Unit.Parser.parse(name),
             {:ok, base} <- Localize.Unit.BaseUnit.base_unit(parsed) do
          case Map.get(btq, base) do
            nil ->
              {:error,
               Localize.InvalidValueError.exception(
                 value: name,
                 expected: "a unit with a known category"
               )}

            category ->
              {:ok, category}
          end
        end

      category ->
        {:ok, category}
    end
  end

  @doc """
  Returns whether two units are convertible (same category).

  ### Arguments

  * `unit_1` is a `%Localize.Unit{}` struct or a unit name string.

  * `unit_2` is a `%Localize.Unit{}` struct or a unit name string.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> Localize.Unit.compatible?("meter", "foot")
      true

      iex> Localize.Unit.compatible?("meter", "kilogram")
      false

  """
  @spec compatible?(t() | String.t(), t() | String.t()) :: boolean()
  def compatible?(%__MODULE__{name: name_1}, unit_2), do: compatible?(name_1, unit_2)
  def compatible?(unit_1, %__MODULE__{name: name_2}), do: compatible?(unit_1, name_2)

  def compatible?(name_1, name_2) when is_binary(name_1) and is_binary(name_2) do
    with {:ok, parsed_1} <- Localize.Unit.Parser.parse(name_1),
         {:ok, base_1} <- Localize.Unit.BaseUnit.base_unit(parsed_1),
         {:ok, parsed_2} <- Localize.Unit.Parser.parse(name_2),
         {:ok, base_2} <- Localize.Unit.BaseUnit.base_unit(parsed_2) do
      base_1 == base_2
    else
      _ -> false
    end
  end

  @doc """
  Returns the localized display name for a unit.

  This returns the unit name as it would appear in the locale,
  without any numeric value (e.g., "meters", "kilograms").

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct or a unit name string.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `Localize.get_locale()`.

  * `:format` is `:long`, `:short`, or `:narrow`. The default is `:long`.

  ### Returns

  * `{:ok, name}` or `{:error, exception}`.

  ### Examples

      iex> Localize.Unit.display_name("meter", locale: :en)
      {:ok, "meters"}

      iex> Localize.Unit.display_name("meter", locale: :en, format: :short)
      {:ok, "m"}

  """
  @spec display_name(t() | String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  @dialyzer {:nowarn_function, display_name: 2}
  def display_name(unit_or_name, options \\ [])

  def display_name(%__MODULE__{} = unit, options) do
    display_name(unit.name, options)
  end

  def display_name(name, options) when is_binary(name) do
    case new(name) do
      {:ok, unit} ->
        Localize.Unit.Formatter.to_string(unit, options)

      error ->
        error
    end
  end

  @doc """
  Returns a list of all known unit categories.

  ### Returns

  * A list of category name strings.

  ### Examples

      iex> cats = Localize.Unit.known_categories()
      iex> "length" in cats
      true

  """
  @spec known_categories() :: [String.t()]
  def known_categories do
    Localize.Unit.Data.categories()
  end

  @doc """
  Returns a map of unit categories to their member units.

  ### Returns

  * A map of `%{category_string => [unit_name_string]}`.

  ### Examples

      iex> by_cat = Localize.Unit.known_units_by_category()
      iex> is_list(by_cat["length"])
      true

  """
  @spec known_units_by_category() :: %{String.t() => [String.t()]}
  def known_units_by_category do
    btq = Localize.Unit.Data.base_unit_to_quantity()

    Localize.Unit.Data.conversions()
    |> Enum.group_by(
      fn {_unit, base} -> Map.get(btq, base, "unknown") end,
      fn {unit, _base} -> unit end
    )
  end

  @doc """
  Returns a list of valid usage types for unit preferences.

  ### Returns

  * A sorted list of usage atoms.

  ### Examples

      iex> usages = Localize.Unit.known_usages()
      iex> "default" in usages
      true

  """
  @spec known_usages() :: [String.t()]
  def known_usages do
    @valid_usages
  end

  @doc """
  Returns the preferred measurement system for a territory.

  ### Arguments

  * `territory` is a territory code atom (e.g., `:US`, `:GB`).

  ### Returns

  * `:metric`, `:us`, or `:uk`.

  ### Examples

      iex> Localize.Unit.measurement_system_for_territory(:US)
      :us

      iex> Localize.Unit.measurement_system_for_territory(:FR)
      :metric

  """
  @spec measurement_system_for_territory(atom()) :: atom()
  def measurement_system_for_territory(territory) when is_atom(territory) do
    measurement_data = Localize.SupplementalData.measurement_data()

    Map.get(measurement_data.measurement_system, territory) ||
      Map.get(measurement_data.measurement_system, :"001", :metric)
  end

  # ── Private helpers ───────────────────────────────────────────

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n * 1.0
  defp to_float(n), do: n
end
