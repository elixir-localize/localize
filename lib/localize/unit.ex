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

  defstruct name: nil,
            parsed: nil,
            value: nil,
            usage: nil,
            format_options: []

  @type value :: number() | Decimal.t() | [number()] | nil

  @type t :: %__MODULE__{
          name: String.t(),
          parsed: tuple(),
          value: value(),
          usage: String.t() | nil,
          format_options: Keyword.t()
        }

  defp valid_usages do
    cached(:valid_usages, fn ->
      Localize.Unit.Data.unit_preferences()
      |> Enum.map(& &1.usage)
      |> Enum.uniq()
      |> Enum.sort()
    end)
  end

  @compile {:inline, cached: 2}
  defp cached(key, build_fn) do
    pt_key = {__MODULE__, key}

    case :persistent_term.get(pt_key, :__not_loaded__) do
      :__not_loaded__ ->
        value = build_fn.()
        :persistent_term.put(pt_key, value)
        value

      value ->
        value
    end
  end

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

  * `options` is a keyword list of options.

  ### Options

  See `new/3` for the supported options.

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
  Parses a string containing a number and a unit name into a unit.

  The number is parsed with the locale's number symbols and the unit name is matched against the locale's unit names — display names and the text of the long, short and narrow patterns — as well as the canonical CLDR identifiers and any units registered with `define_unit/2`. Matching is case-insensitive; when a name is ambiguous ("2 w" matches both watt and week via their narrow forms) the candidates are filtered by the `:only`/`:except` options and the first remaining unit in alphabetical order is chosen.

  ### Arguments

  * `unit_string` is a string containing a number and a unit name, in either order (e.g., `"1kg"`, `"1 kilogram"`, `"2,5 kg"` in a locale with comma decimals).

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom, string, or a `t:Localize.LanguageTag.t/0`. The default is `Localize.get_locale()`. Both the number symbols and the unit names follow this locale.

  * `:only` is a category, a unit name, or a list of either (atoms or strings). Only matching candidates are considered: `only: :duration` resolves `"2w"` to weeks rather than watts.

  * `:except` is the complement of `:only`: matching candidates are excluded.

  ### Returns

  * `{:ok, unit}` where `unit` is a `t:t/0` with the parsed value.

  * `{:error, exception}` if no number is found, the unit name is unknown, or the filters exclude every candidate.

  ### Examples

      iex> Localize.Unit.parse("1kg")
      Localize.Unit.new(1, "kilogram")

      iex> Localize.Unit.parse("1 kilogram")
      Localize.Unit.new(1, "kilogram")

      iex> Localize.Unit.parse("2w", only: :duration)
      Localize.Unit.new(2, "week")

      iex> Localize.Unit.parse("2 Tage", locale: :de)
      Localize.Unit.new(2, "day")

      iex> {:error, %Localize.UnknownUnitError{}} = Localize.Unit.parse("1 blorb")

  """
  @spec parse(String.t(), Keyword.t()) :: {:ok, t()} | {:error, Exception.t()}
  def parse(unit_string, options \\ []) when is_binary(unit_string) and is_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, value, name_token} <- split_value_and_name(unit_string, language_tag),
         {:ok, unit_name} <- resolve_unit_name(name_token, language_tag, options) do
      new(value, unit_name)
    end
  end

  @doc """
  Same as `parse/2` but raises on error.

  ### Arguments

  * `unit_string` is a string containing a number and a unit name.

  * `options` is a keyword list of options. See `parse/2`.

  ### Returns

  * A `t:t/0` with the parsed value.

  ### Raises

  * Raises an exception if the string cannot be parsed.

  ### Examples

      iex> Localize.Unit.parse!("1kg").name
      "kilogram"

  """
  @spec parse!(String.t(), Keyword.t()) :: t() | no_return()
  def parse!(unit_string, options \\ []) do
    case parse(unit_string, options) do
      {:ok, unit} -> unit
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Parses a unit name string into its canonical unit identifier.

  Like `parse/2` but for a bare unit name with no numeric value: `"kg"` resolves to `"kilogram"`. The same locale-aware matching and `:only`/`:except` disambiguation apply.

  ### Arguments

  * `unit_name_string` is a unit name string (e.g., `"kg"`, `"kilograms"`, `"Tage"`).

  * `options` is a keyword list of options. See `parse/2`.

  ### Returns

  * `{:ok, unit_name}` where `unit_name` is the canonical unit identifier string.

  * `{:error, exception}` if the name is unknown or the filters exclude every candidate.

  ### Examples

      iex> Localize.Unit.parse_unit_name("kg")
      {:ok, "kilogram"}

      iex> Localize.Unit.parse_unit_name("w", only: :duration)
      {:ok, "week"}

      iex> Localize.Unit.parse_unit_name("Tage", locale: :de)
      {:ok, "day"}

  """
  @spec parse_unit_name(String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def parse_unit_name(unit_name_string, options \\ [])
      when is_binary(unit_name_string) and is_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())

    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      resolve_unit_name(unit_name_string, language_tag, options)
    end
  end

  @doc """
  Same as `parse_unit_name/2` but raises on error.

  ### Arguments

  * `unit_name_string` is a unit name string.

  * `options` is a keyword list of options. See `parse_unit_name/2`.

  ### Returns

  * The canonical unit identifier string.

  ### Raises

  * Raises an exception if the name cannot be resolved.

  ### Examples

      iex> Localize.Unit.parse_unit_name!("kg")
      "kilogram"

  """
  @spec parse_unit_name!(String.t(), Keyword.t()) :: String.t() | no_return()
  def parse_unit_name!(unit_name_string, options \\ []) do
    case parse_unit_name(unit_name_string, options) do
      {:ok, unit_name} -> unit_name
      {:error, exception} -> raise exception
    end
  end

  # The scan yields interleaved text and number tokens; a parseable
  # unit string has exactly one number and one non-empty text token,
  # in either order ("1kg", "kg 1").
  defp split_value_and_name(unit_string, language_tag) do
    tokens = Localize.Number.Parser.scan(unit_string, locale: language_tag)

    numbers = Enum.filter(tokens, &is_number/1)

    texts =
      tokens |> Enum.filter(&is_binary/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    case {numbers, texts} do
      {[value], [name]} ->
        {:ok, value, name}

      _other ->
        {:error,
         Localize.InvalidValueError.exception(
           value: unit_string,
           expected: "a string containing one number and one unit name"
         )}
    end
  end

  defp resolve_unit_name(name_token, language_tag, options) do
    with {:ok, locale_id} <- Localize.Locale.cldr_locale_id_from(language_tag) do
      only = List.wrap(Keyword.get(options, :only, [])) |> Enum.map(&Kernel.to_string/1)
      except = List.wrap(Keyword.get(options, :except, [])) |> Enum.map(&Kernel.to_string/1)

      candidates =
        name_token
        |> Localize.Unit.NameIndex.candidates(locale_id)
        |> apply_unit_filter(only, except)

      case candidates do
        [%{unit: unit} | _rest] ->
          {:ok, unit}

        [] ->
          canonical_fallback(name_token, only, except)
      end
    end
  end

  defp apply_unit_filter(candidates, only, except) do
    candidates
    |> Enum.filter(fn candidate ->
      only == [] or candidate.unit in only or candidate.category in only
    end)
    |> Enum.reject(fn candidate ->
      candidate.unit in except or candidate.category in except
    end)
  end

  # Compound identifiers such as "kilometer-per-hour" have no single
  # display name; when the index misses, the canonical unit grammar
  # is the fallback. The filters still apply — by name only, since a
  # compound has no single category.
  defp canonical_fallback(name_token, only, except) do
    trimmed = String.trim(name_token)

    case new(trimmed) do
      {:ok, %__MODULE__{name: name}} ->
        cond do
          name in except ->
            {:error, Localize.UnknownUnitError.exception(unit: trimmed)}

          only != [] and name not in only ->
            {:error, Localize.UnknownUnitError.exception(unit: trimmed)}

          true ->
            {:ok, name}
        end

      {:error, _} ->
        {:error, Localize.UnknownUnitError.exception(unit: trimmed)}
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

  ### Value type

  The converted value is a `Decimal` when the source value is a `Decimal`
  (results stay exact) and a float otherwise. Integer and float values
  both yield a float, because unit conversion is real-valued — an integer
  input cannot represent a converted quantity such as `1` mile in
  kilometers, so promoting to float is preferred over integer arithmetic,
  which would silently lose precision. Pass a `Decimal` value when you
  need an exact result.

  ### Examples

      iex> {:ok, meters} = Localize.Unit.new(1, "kilometer")
      iex> {:ok, result} = Localize.Unit.convert(meters, "meter")
      iex> result.value
      1000.0
      iex> result.name
      "meter"

      iex> {:ok, tonnes} = Localize.Unit.new(Decimal.new(1), "tonne")
      iex> {:ok, result} = Localize.Unit.convert(tonnes, "kilogram")
      iex> match?(%Decimal{}, result.value)
      true

  """
  @spec convert(t(), String.t()) :: {:ok, t()} | {:error, Exception.t()}

  def convert(%__MODULE__{value: nil}, _target) do
    {:error, Localize.UnitNoValueError.exception(operation: :convert)}
  end

  def convert(%__MODULE__{} = source, target) when is_binary(target) do
    with {:ok, target_parsed} <- Localize.Unit.Parser.parse(target) do
      convert_parsed(source, target, target_parsed)
    end
  end

  defp convert_parsed(source, target, {:mixed_unit, _units} = target_parsed) do
    convert_to_mixed(source, target, target_parsed)
  end

  defp convert_parsed(%__MODULE__{value: value, name: from_name} = source, target, _target_parsed) do
    {source_value, effective_from} = effective_source(value, from_name, source.parsed)

    with {:ok, converted} <-
           Localize.Unit.Conversion.convert(source_value, effective_from, target) do
      new(converted, target)
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

  # The unit name conversions should be performed in: the first (primary)
  # component for a mixed unit, otherwise the unit's own name. The scalar
  # produced by `mixed_to_scalar/3` for a mixed unit is denominated in
  # this first component, so conversions must use it rather than the
  # mixed name (which `Conversion.convert/3` rejects with :mixed_units).
  defp effective_source_name(_name, {:mixed_unit, units}) do
    {:single_unit, first_opts} = hd(units)
    format_single_unit_name(first_opts)
  end

  defp effective_source_name(name, _parsed), do: name

  # Convert a scalar value from a source unit to a mixed target unit.
  # For example, 180 centimeter → foot-and-inch = [5, 11.024...]
  # Each component gets the integer part except the last which gets the remainder.
  defp convert_to_mixed(source, _target_name, {:mixed_unit, target_units}) do
    source_value = mixed_to_scalar(source.value, source.name, source.parsed)
    effective_from = effective_source_name(source.name, source.parsed)

    # Get the first target component name to check convertibility
    {:single_unit, first_opts} = hd(target_units)
    first_name = format_single_unit_name(first_opts)

    with {:ok, full_in_first} <-
           Localize.Unit.Conversion.convert(source_value, effective_from, first_name) do
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

  defp preferred_unit(unit_name, system, usage) do
    region = Map.fetch!(@system_regions, system)

    with {:ok, base_unit} <- Localize.Unit.BaseUnit.base_unit(unit_name),
         {:ok, quantity} <- lookup_quantity(base_unit),
         {:ok, category} <- lookup_category(quantity) do
      find_preference(category, region, usage)
    end
  end

  defp lookup_quantity(base_unit) do
    case Map.get(Localize.Unit.Data.base_unit_to_quantity(), base_unit) do
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
    case Enum.find(
           Localize.Unit.Data.unit_preferences(),
           &(&1.category == category and &1.usage == usage)
         ) do
      nil ->
        {:error,
         Localize.UnitPreferenceError.exception(
           reason: :no_preference_for_usage,
           category: category,
           usage: usage
         )}

      %{preferences: preferences} ->
        find_preference_for_region(preferences, category, region)
    end
  end

  defp find_preference_for_region(preferences, category, region) do
    case Enum.find(preferences, fn pref -> region in String.split(pref.regions) end) do
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

  # Base units humanize/2 scales through the prefix ladder: the
  # locale-invariant SI-prefixed quantities that CLDR's unit
  # preference data does not cover. IEC binary prefixes are
  # meaningful only for the digital bases.
  @si_humanize_bases ~w(bit byte hertz watt)
  @iec_humanize_bases ~w(bit byte)

  # Prefix ladders for humanize/2, largest factor first so the first
  # match is the prefix that scales the value into [1, 1000) or [1, 1024).
  @si_humanize_prefixes ~w(kilo mega giga tera peta exa zetta yotta)
  @iec_humanize_prefixes ~w(kibi mebi gibi tebi pebi exbi zebi yobi)

  @si_humanize_ladder @si_humanize_prefixes
                      |> Enum.with_index(1)
                      |> Enum.map(fn {prefix, index} -> {prefix, Integer.pow(1000, index)} end)
                      |> Enum.reverse()

  @iec_humanize_ladder @iec_humanize_prefixes
                       |> Enum.with_index(1)
                       |> Enum.map(fn {prefix, index} -> {prefix, Integer.pow(1024, index)} end)
                       |> Enum.reverse()

  @doc """
  Converts a bit-, byte-, hertz- or watt-based unit to the prefixed
  unit that best fits its magnitude — human-readable file sizes,
  frequencies and power figures.

  Selects the largest SI prefix (kilobyte, megahertz, gigawatt, ...)
  or, for bits and bytes, IEC binary prefix (kibibyte, mebibyte, ...)
  such that the converted value is at least `1`. Values smaller than
  one kilo-unit (or kibi-unit) are returned unchanged.

  These bases are the locale-invariant SI-prefixed quantities that
  CLDR's unit preference data does not cover. For physical
  quantities such as length or mass, use the `:usage` option on
  `to_string/2` instead — CLDR preferences pick the display unit by
  territory and magnitude.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value, based on
    `"bit"`, `"byte"`, `"hertz"` or `"watt"` (a bare or
    already-prefixed unit such as `"byte"`, `"kilobyte"` or
    `"megahertz"`).

  * `options` is a keyword list of options.

  ### Options

  * `:system` is the prefix system to scale with: `:si` (powers of
    1000, the default) or `:iec` (powers of 1024, bit- and
    byte-based units only). Note that CLDR provides compact display
    patterns (like `"MB"`) only for SI-prefixed units; IEC units
    format with their full names in all format widths.

  ### Returns

  * `{:ok, unit}` where `unit` is a new `%Localize.Unit{}` with the
    scaled value and prefixed unit name, or

  * `{:error, reason}` if the unit has no value, has an unsupported
    base unit, or the prefix system is invalid or does not apply to
    the base unit.

  ### Examples

      iex> {:ok, unit} = Localize.Unit.new(1_500_000, "byte")
      iex> {:ok, humanized} = Localize.Unit.humanize(unit)
      iex> {humanized.name, humanized.value}
      {"megabyte", 1.5}
      iex> Localize.Unit.to_string(humanized, format: :narrow, locale: :en)
      {:ok, "1.5MB"}

      iex> {:ok, unit} = Localize.Unit.new(2_500_000_000, "hertz")
      iex> {:ok, humanized} = Localize.Unit.humanize(unit)
      iex> {humanized.name, humanized.value}
      {"gigahertz", 2.5}

      iex> {:ok, unit} = Localize.Unit.new(1_048_576, "byte")
      iex> {:ok, humanized} = Localize.Unit.humanize(unit, system: :iec)
      iex> {humanized.name, humanized.value}
      {"mebibyte", 1.0}

  """
  @spec humanize(t(), Keyword.t()) :: {:ok, t()} | {:error, Exception.t()}
  def humanize(unit, options \\ [])

  def humanize(%__MODULE__{value: nil}, _options) do
    {:error, Localize.UnitNoValueError.exception(operation: :humanize)}
  end

  def humanize(%__MODULE__{} = unit, options) do
    system = Keyword.get(options, :system, :si)

    with :ok <- validate_prefix_system(system),
         {:ok, base_name} <- humanizable_base_unit(unit),
         :ok <- validate_system_for_base(system, base_name),
         {:ok, base_unit} <- convert_unless_same(unit, base_name) do
      target_name = humanized_unit_name(base_unit.value, system, base_name)
      convert_unless_same(base_unit, target_name)
    end
  end

  @doc """
  Converts a bit-, byte-, hertz- or watt-based unit to the prefixed
  unit that best fits its magnitude, raising on error.

  See `humanize/2` for details.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value, based on
    `"bit"`, `"byte"`, `"hertz"` or `"watt"`.

  * `options` is a keyword list of options. See `humanize/2`.

  ### Returns

  * A new `%Localize.Unit{}` with the scaled value and prefixed
    unit name, or

  * raises an exception if the unit has no value, has an unsupported
    base unit, or the prefix system is invalid.

  ### Examples

      iex> Localize.Unit.new!(2_750_000_000, "byte")
      ...> |> Localize.Unit.humanize!()
      ...> |> Localize.Unit.to_string!(format: :narrow, fractional_digits: 1, locale: :en)
      "2.8GB"

  """
  @spec humanize!(t(), Keyword.t()) :: t() | no_return()
  def humanize!(%__MODULE__{} = unit, options \\ []) do
    case humanize(unit, options) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  defp validate_prefix_system(system) when system in [:si, :iec], do: :ok

  defp validate_prefix_system(system) do
    {:error,
     Localize.InvalidValueError.exception(
       value: system,
       expected: ":si or :iec",
       context: "prefix system"
     )}
  end

  defp validate_system_for_base(:iec, base_name) when base_name not in @iec_humanize_bases do
    {:error,
     Localize.InvalidValueError.exception(
       value: base_name,
       expected: "a bit- or byte-based unit when system: :iec"
     )}
  end

  defp validate_system_for_base(_system, _base_name), do: :ok

  defp humanizable_base_unit(%__MODULE__{parsed: {:unit, parts}} = unit) do
    with [single_unit: single_unit] <- Keyword.get(parts, :numerator),
         [] <- Keyword.get(parts, :denominator),
         base when base in @si_humanize_bases <- Keyword.get(single_unit, :base),
         power when power in [nil, 1] <- Keyword.get(single_unit, :power) do
      {:ok, base}
    else
      _other -> not_humanizable_error(unit)
    end
  end

  defp humanizable_base_unit(%__MODULE__{} = unit), do: not_humanizable_error(unit)

  defp not_humanizable_error(unit) do
    {:error,
     Localize.InvalidValueError.exception(
       value: unit.name,
       expected: "a bit-, byte-, hertz- or watt-based unit",
       context: "humanize"
     )}
  end

  defp convert_unless_same(%__MODULE__{name: name} = unit, name), do: {:ok, unit}
  defp convert_unless_same(unit, target_name), do: convert(unit, target_name)

  defp humanized_unit_name(value, system, base_name) do
    ladder = if system == :si, do: @si_humanize_ladder, else: @iec_humanize_ladder

    case Enum.find(ladder, fn {_prefix, factor} -> value_gte?(value, factor) end) do
      {prefix, _factor} -> prefix <> base_name
      nil -> base_name
    end
  end

  defp value_gte?(%Decimal{} = value, factor) do
    Decimal.compare(Decimal.abs(value), Decimal.new(factor)) != :lt
  end

  defp value_gte?(value, factor) when is_number(value), do: abs(value) >= factor

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

  ### Examples

      iex> {:error, message} = Localize.Unit.load_custom_units("no/such/file.exs")
      iex> message =~ "file not found"
      true

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
    valid = valid_usages()

    if usage in valid do
      {:ok, usage}
    else
      {:error,
       Localize.InvalidValueError.exception(
         value: usage,
         expected: :usage,
         allowed_values: valid,
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
      {:single_unit, keyword}, :ok ->
        validate_single_unit_currency(Keyword.fetch!(keyword, :base))

      _, :ok ->
        {:cont, :ok}
    end)
  end

  defp validate_single_unit_currency("curr-" <> code) do
    case Localize.Currency.validate_currency(code) do
      {:ok, _} -> {:cont, :ok}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp validate_single_unit_currency(_base) do
    {:cont, :ok}
  end

  defp known_base_units do
    cached(:known_base_units, fn -> MapSet.new(Localize.Unit.Data.base_units()) end)
  end

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

        if valid_base_unit?(base) do
          {:cont, :ok}
        else
          {:halt, {:error, Localize.UnknownUnitError.exception(unit: base)}}
        end

      _, :ok ->
        {:cont, :ok}
    end)
  end

  # A base name is valid if it's a currency placeholder, a known CLDR
  # base unit, or a runtime-registered custom unit.
  defp valid_base_unit?(base) do
    String.starts_with?(base, "curr-") or
      MapSet.member?(known_base_units(), base) or
      Localize.Unit.CustomRegistry.registered?(base)
  end

  # ── Formatting ───────────────────────────────────────────────

  @doc """
  Formats a unit together with its value as a localized string.

  Accepts either a single `t:Localize.Unit.t/0` struct or a list of them.
  A single unit is rendered inline with its value using the locale's
  pluralised pattern (e.g., `"5 meters"`). A list is rendered by
  formatting each element and joining via `Localize.List.to_string/2`,
  which is what produces mixed-unit output like `"6 feet, 0.047 inches"`.

  When `:usage` is supplied for a *single* unit — or the unit's struct
  carries a non-`nil` `:usage` field set at `new/3` time — this function
  first calls `localize/2` to convert the value into the locale-preferred
  unit set, then formats the resulting list. This is the one-call
  shortcut for the
  preference-resolution → conversion → decomposition → format pipeline.

  The territory used for preference resolution is derived from the
  `:locale` option (via `Localize.Territory.territory_from_locale/1`).
  There is no `:territory` option on `to_string/2`; if you need to
  override the territory independently of the locale, call
  `localize/2` directly and pipe the result back into `to_string/2`.

  For the bare stand-alone unit label without a value, use `display_name/2`.

  ### Arguments

  * `unit_or_units` is a `t:Localize.Unit.t/0` struct or a non-empty
    list of `t:Localize.Unit.t/0` structs.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`. The default is the current process
    locale.

  * `:format` is `:long`, `:short`, or `:narrow`.
    The default is `:long`.

  * `:humanize` (single unit only) when `true` renders the unit in
    the unit people expect for its magnitude: bit-, byte-, hertz-
    and watt-based units are scaled through `humanize/2` (honouring
    the `:system` option for `:si` or `:iec` prefixes), and all
    other units are rendered through the usage-based preference
    pipeline using the struct's `:usage` field or `:default`. An
    explicit `:usage` option takes precedence for preference-scaled
    units. The default is `false`.

  * `:usage` (single unit only) is the unit's intended usage. When
    given, triggers `localize/2` before formatting. Accepts an atom
    (`:person_height`) or a CLDR-style string (`"person-height"`). If
    the option is omitted but the struct's `:usage` field is set,
    `localize/2` is still triggered using that value.

  * `:list_options` is a keyword list passed to `Localize.List.to_string/2`
    when rendering a unit list. Use it to pick a unit-specific list style
    (e.g. `list_options: [list_style: :unit_short]`).

  * `:grammatical_case` selects a case-keyed pattern variant for the
    unit (e.g. `:nominative`, `:dative`, `:genitive`). Defaults to
    `:nominative`.

  * `:grammatical_gender` is accepted on the public API for cldr_units
    parity. Only meaningful for compound-unit patterns
    (`compound_unit_pattern` keyed by gender); for simple units the
    gender is a fixed property of the unit in CLDR data and the option
    has no effect on output.

  * `:backend` is `:nif` or `:elixir`. When `:nif` is specified and the
    NIF is available, ICU4C is used for formatting. Otherwise falls
    back to the pure-Elixir formatter. The default is `:elixir`.

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

      iex> unit = Localize.Unit.new!(1.83, "meter")
      iex> Localize.Unit.to_string(unit, usage: :person_height, locale: "en-US")
      {:ok, "6 feet and 0.047 inches"}

      iex> unit = Localize.Unit.new!(2_000, "meter")
      iex> Localize.Unit.to_string(unit, usage: :road, locale: "de-DE")
      {:ok, "2 Kilometer"}

      iex> Localize.Unit.new!(1_500_000, "byte")
      ...> |> Localize.Unit.to_string(humanize: true, format: :narrow)
      {:ok, "1.5MB"}

      iex> Localize.Unit.new!(1_500, "meter")
      ...> |> Localize.Unit.to_string(humanize: true, locale: :de)
      {:ok, "1,5 Kilometer"}

  """
  @spec to_string(t() | [t(), ...], Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(unit_or_units, options \\ [])

  def to_string([%__MODULE__{} | _] = units, options) do
    format_unit_list(units, options)
  end

  def to_string(%__MODULE__{} = unit, options) do
    with {:ok, unit, options} <- maybe_humanize(unit, options) do
      format_single_unit(unit, options)
    end
  end

  defp format_single_unit(unit, options) do
    if Keyword.has_key?(options, :usage) or not is_nil(unit.usage) do
      preference_options = Keyword.take(options, [:usage, :locale])
      list_options = Keyword.drop(options, [:usage])

      with {:ok, parts} <- localize(unit, preference_options) do
        format_unit_list(parts, list_options)
      end
    else
      Localize.Unit.Formatter.to_string(unit, merge_struct_format_options(unit, options))
    end
  end

  # `humanize: true` renders the unit the way people expect for its
  # kind: bit-, byte-, hertz- and watt-based units scale through the
  # `humanize/2` prefix ladder, every other unit goes through the
  # usage-based preference pipeline with the struct's usage or
  # `:default`. An explicit `:usage` option still wins for
  # preference-scaled units.
  defp maybe_humanize(unit, options) do
    {humanize?, options} = Keyword.pop(options, :humanize, false)

    cond do
      humanize? != true ->
        {:ok, unit, options}

      match?({:ok, _base}, humanizable_base_unit(unit)) ->
        with {:ok, humanized} <- humanize(unit, Keyword.take(options, [:system])) do
          {:ok, humanized, options}
        end

      true ->
        {:ok, unit, Keyword.put_new(options, :usage, unit.usage || :default)}
    end
  end

  # The unit's struct may carry `:format_options` — typically `[round_nearest: N]`
  # stamped on by `localize/2` from CLDR's unitPreferenceData skeleton. Caller-
  # supplied options on `to_string/2` win, so the struct's options act as a
  # default that the caller can override.
  defp merge_struct_format_options(%__MODULE__{format_options: []}, options), do: options

  defp merge_struct_format_options(%__MODULE__{format_options: struct_options}, options) do
    Keyword.merge(struct_options, options)
  end

  defp format_unit_list(units, options) do
    {list_options, element_options} = Keyword.pop(options, :list_options, [])

    list_options =
      list_options
      |> Keyword.put_new(:locale, Keyword.get(element_options, :locale, Localize.get_locale()))

    Enum.reduce_while(units, {:ok, []}, fn unit, {:ok, acc} ->
      case Localize.Unit.Formatter.to_string(
             unit,
             merge_struct_format_options(unit, element_options)
           ) do
        {:ok, formatted} -> {:cont, {:ok, [formatted | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, formatted_reversed} ->
        Localize.List.to_string(Enum.reverse(formatted_reversed), list_options)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Same as `to_string/2` but raises on error.

  ### Arguments

  * `unit_or_units` is a `t:Localize.Unit.t/0` struct or a non-empty
    list of `t:Localize.Unit.t/0` structs.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * A formatted string.

  ### Raises

  * Raises an exception if the unit cannot be formatted.

  ### Examples

      iex> unit = Localize.Unit.new!(42, "meter")
      iex> Localize.Unit.to_string!(unit)
      "42 meters"

      iex> unit = Localize.Unit.new!(42, "meter")
      iex> Localize.Unit.to_string!(unit, format: :short)
      "42 m"

  """
  @spec to_string!(t() | [t(), ...], Keyword.t()) :: String.t()
  def to_string!(unit_or_units, options \\ []) do
    case to_string(unit_or_units, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats two units of the same kind as a localized range.

  The unit pattern is applied once to the formatted numeric range per TR35: the pattern's plural category comes from the TR35 plural-range rules (`Localize.Number.PluralRule.Range`), so "0–1 jour" is singular in French while "1–2 jours" is plural.

  ### Arguments

  * `unit_start` is a `t:Localize.Unit.t/0` struct for the range start.

  * `unit_end` is a `t:Localize.Unit.t/0` struct for the range end. Must have the same unit name as `unit_start`.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `Localize.get_locale/0`.

  * `:format` is `:long`, `:short`, or `:narrow`. The default is `:long`.

  * The number-formatting options of `to_string/2` (`:fractional_digits`, `:rounding_mode`, and friends) apply to both endpoints.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the units differ, the unit has no direct CLDR pattern, or the options are invalid.

  ### Examples

      iex> {:ok, unit_start} = Localize.Unit.new(2, "kilometer")
      iex> {:ok, unit_end} = Localize.Unit.new(5, "kilometer")
      iex> Localize.Unit.to_range_string(unit_start, unit_end, locale: :en)
      {:ok, "2–5 kilometers"}

      iex> {:ok, unit_start} = Localize.Unit.new(2, "kilometer")
      iex> {:ok, unit_end} = Localize.Unit.new(5, "kilometer")
      iex> Localize.Unit.to_range_string(unit_start, unit_end, locale: :en, format: :short)
      {:ok, "2–5 km"}

  """
  @spec to_range_string(t(), t(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_range_string(%__MODULE__{} = unit_start, %__MODULE__{} = unit_end, options \\ []) do
    Localize.Unit.Formatter.to_range_string(unit_start, unit_end, options)
  end

  @doc """
  Same as `to_range_string/3` but raises on error.

  ### Arguments

  * `unit_start` is a `t:Localize.Unit.t/0` struct for the range start.

  * `unit_end` is a `t:Localize.Unit.t/0` struct for the range end.

  * `options` is a keyword list of options. See `to_range_string/3`.

  ### Returns

  * A formatted string.

  ### Raises

  * Raises an exception if the range cannot be formatted.

  ### Examples

      iex> Localize.Unit.to_range_string!(Localize.Unit.new!(2, "kilometer"), Localize.Unit.new!(5, "kilometer"), locale: :en)
      "2–5 kilometers"

  """
  @spec to_range_string!(t(), t(), Keyword.t()) :: String.t()
  def to_range_string!(%__MODULE__{} = unit_start, %__MODULE__{} = unit_end, options \\ []) do
    case to_range_string(unit_start, unit_end, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats two units of the same kind into typed range parts, mirroring ECMA-402's `formatRangeToParts` for unit style.

  The parts concatenate to exactly the string `to_range_string/3` produces with the same options. The numeric range's parts keep their `:start_range` / `:end_range` / `:shared` sources; the unit pattern's text carries source `:shared` with the unit name tagged `:unit`.

  ### Arguments

  * `unit_start` is a `t:Localize.Unit.t/0` struct for the range start.

  * `unit_end` is a `t:Localize.Unit.t/0` struct for the range end. Must have the same unit name as `unit_start`.

  * `options` is a keyword list of options. See `to_range_string/3`.

  ### Returns

  * `{:ok, parts}` where `parts` is a list of `%{type: atom(), value: String.t(), source: atom()}` maps.

  * `{:error, exception}` if the units differ, the unit has no direct CLDR pattern, or the options are invalid.

  ### Examples

      iex> {:ok, unit_start} = Localize.Unit.new(2, "kilometer")
      iex> {:ok, unit_end} = Localize.Unit.new(5, "kilometer")
      iex> Localize.Unit.to_range_parts(unit_start, unit_end, locale: :en)
      {:ok,
       [
         %{type: :integer, value: "2", source: :start_range},
         %{type: :literal, value: "–", source: :shared},
         %{type: :integer, value: "5", source: :end_range},
         %{type: :literal, value: " ", source: :shared},
         %{type: :unit, value: "kilometers", source: :shared}
       ]}

  """
  @spec to_range_parts(t(), t(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t(), source: atom()}]} | {:error, Exception.t()}
  def to_range_parts(%__MODULE__{} = unit_start, %__MODULE__{} = unit_end, options \\ []) do
    Localize.Unit.Formatter.to_range_parts(unit_start, unit_end, options)
  end

  @doc """
  Same as `to_range_parts/3` but raises on error.

  ### Arguments

  * `unit_start` is a `t:Localize.Unit.t/0` struct for the range start.

  * `unit_end` is a `t:Localize.Unit.t/0` struct for the range end.

  * `options` is a keyword list of options. See `to_range_parts/3`.

  ### Returns

  * A list of `%{type: atom(), value: String.t(), source: atom()}` maps.

  ### Raises

  * Raises an exception if the range cannot be decomposed into parts.

  ### Examples

      iex> Localize.Unit.to_range_parts!(Localize.Unit.new!(2, "kilometer"), Localize.Unit.new!(5, "kilometer"), locale: :en) |> length()
      5

  """
  @spec to_range_parts!(t(), t(), Keyword.t()) ::
          [%{type: atom(), value: String.t(), source: atom()}]
  def to_range_parts!(%__MODULE__{} = unit_start, %__MODULE__{} = unit_end, options \\ []) do
    case to_range_parts(unit_start, unit_end, options) do
      {:ok, parts} -> parts
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats a unit into a list of typed parts, mirroring ECMA-402's `formatToParts` for unit style.

  The parts concatenate to exactly the string `to_string/2` produces with the same options. The number's segments come from `Localize.Number.to_parts/2`; the unit pattern text is tagged `:unit` with its surrounding whitespace as `:literal` parts.

  ### Arguments

  * `unit` is a `t:Localize.Unit.t/0` struct.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `Localize.get_locale/0`.

  * `:format` is `:long`, `:short`, or `:narrow`. The default is `:long`.

  * The number-formatting options of `to_string/2` apply to the numeric segments.

  ### Returns

  * `{:ok, parts}` where `parts` is a list of `%{type: atom(), value: String.t()}` maps.

  * `{:error, exception}` if the unit has no direct CLDR pattern or the options are invalid.

  ### Examples

      iex> {:ok, unit} = Localize.Unit.new(42, "meter")
      iex> Localize.Unit.to_parts(unit, locale: :en)
      {:ok,
       [
         %{type: :integer, value: "42"},
         %{type: :literal, value: " "},
         %{type: :unit, value: "meters"}
       ]}

  """
  @spec to_parts(t(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(%__MODULE__{} = unit, options \\ []) do
    Localize.Unit.Formatter.to_parts(unit, options)
  end

  @doc """
  Same as `to_parts/2` but raises on error.

  ### Arguments

  * `unit` is a `t:Localize.Unit.t/0` struct.

  * `options` is a keyword list of options. See `to_parts/2`.

  ### Returns

  * A list of `%{type: atom(), value: String.t()}` maps.

  ### Raises

  * Raises an exception if the unit cannot be decomposed into parts.

  ### Examples

      iex> Localize.Unit.to_parts!(Localize.Unit.new!(42, "meter"), locale: :en) |> length()
      3

  """
  @spec to_parts!(t(), Keyword.t()) :: [%{type: atom(), value: String.t()}]
  def to_parts!(%__MODULE__{} = unit, options \\ []) do
    case to_parts(unit, options) do
      {:ok, parts} -> parts
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

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * `{:ok, iolist}` or `{:error, exception}`.

  ### Examples

      iex> {:ok, unit} = Localize.Unit.new(42, "meter")
      iex> Localize.Unit.to_iolist(unit)
      {:ok, ["42 meters"]}

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

  ### Examples

      iex> {:ok, m} = Localize.Unit.new(10, "meter")
      iex> {:ok, negated} = Localize.Unit.negate(m)
      iex> negated.value
      -10

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

  # ── Localize ──────────────────────────────────────────────────

  @doc """
  Converts a unit into the locale-preferred unit set for a given usage.

  Resolves the preferred unit list with `Localize.Unit.Preference.preferred_units/2`
  (driven by `:usage` and `:territory`), then decomposes the value across
  that list. The result is a list of `t:Localize.Unit.t/0` structs ready
  to be rendered with `to_string/2`.

  This is the convenience wrapper for the common
  preference-resolution → conversion → decomposition pipeline. Pass the
  returned list straight to `Localize.Unit.to_string/2` to render it as
  a localized unit list (e.g. `"6 feet, 0.047 inches"`).

  ### Arguments

  * `unit` is a `t:Localize.Unit.t/0` struct with a value.

  * `options` is a keyword list of options.

  ### Options

  * `:usage` is the unit's intended usage. Accepts an atom
    (`:person_height`) or a CLDR-style string (`"person-height"`).
    If omitted, falls back to the struct's `:usage` field, then to
    `:default`.

  * `:territory` is a territory code atom (e.g. `:US`, `:DE`). If
    omitted, derived from the current locale.

  * `:locale` is a locale identifier used to derive `:territory` when
    `:territory` is not given.

  ### Returns

  * `{:ok, units}` where `units` is a list of `t:Localize.Unit.t/0`
    structs, in preference order (largest unit first).

  * `{:error, exception}` if preferences cannot be resolved or the
    decomposition fails.

  ### Examples

      iex> unit = Localize.Unit.new!(1.83, "meter")
      iex> {:ok, parts} = Localize.Unit.localize(unit, usage: :person_height, territory: :US)
      iex> Enum.map(parts, fn u -> u.name end)
      ["foot", "inch"]

      iex> unit = Localize.Unit.new!(2_000, "meter")
      iex> {:ok, [km]} = Localize.Unit.localize(unit, usage: :road, territory: :DE)
      iex> {km.name, km.value}
      {"kilometer", 2.0}

  """
  @spec localize(t(), Keyword.t()) :: {:ok, [t()]} | {:error, Exception.t()}
  def localize(unit, options \\ [])

  def localize(%__MODULE__{value: nil}, _options) do
    {:error, Localize.UnitNoValueError.exception(operation: :localize)}
  end

  def localize(%__MODULE__{} = unit, options) do
    with {:ok, target_atoms, format_options} <-
           Localize.Unit.Preference.preferred_units(unit, options) do
      resolved_usage = resolved_usage_string(options, unit)
      target_strings = Enum.map(target_atoms, &unit_name_string/1)

      with {:ok, parts} <- decompose(unit, target_strings, format_options) do
        {:ok, Enum.map(parts, &%{&1 | usage: resolved_usage})}
      end
    end
  end

  # `Localize.Unit.Preference.preferred_units/2` reports units as atoms with
  # underscores (`:cubic_inch`), while every CLDR identifier — and so the
  # parser — spells them with hyphens (`"cubic-inch"`). `Atom.to_string/1`
  # alone leaves the underscores in place, which parses only for the
  # single-word preferences (`:liter`, `:foot`) and fails for the 35 that are
  # not, taking the default usage of speed, volume, area, energy and pressure
  # with it.
  defp unit_name_string(name) when is_atom(name) do
    name |> Atom.to_string() |> String.replace("_", "-")
  end

  # Mirror cldr_units: stamp the resolved usage onto each decomposed child so
  # downstream formatting (or struct comparisons in tests) can see it. The
  # struct stores usage as the canonical CLDR-style hyphenated string
  # (e.g. "person-height"), so atoms passed via the options keyword list
  # are converted accordingly.
  defp resolved_usage_string(options, %__MODULE__{usage: struct_usage}) do
    case Keyword.get(options, :usage) do
      nil -> struct_usage
      explicit when is_atom(explicit) -> explicit |> Atom.to_string() |> String.replace("_", "-")
      explicit when is_binary(explicit) -> explicit
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

  When the input value is a `Decimal`, the truncate/remainder math runs
  in `Decimal` arithmetic (not float), so precision is preserved
  through the decomposition.

  Intermediate units whose integer part rounds to zero are skipped (so
  decomposing 1.5 m into `["meter", "kilometer", "centimeter"]` skips
  the kilometer entry). The trailing unit is also skipped if its value
  is zero.

  When `format_options` is given, those options are attached to the
  final (trailing) unit's `:format_options` field — typically a
  `[round_nearest: N]` skeleton lifted from CLDR's preference data.
  `Localize.Unit.localize/2` uses this to thread CLDR's skeletons
  through to `to_string/2`.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct with a value.

  * `target_units` is a list of unit name strings, ordered from
    largest to smallest (e.g., `["foot", "inch"]`).

  * `format_options` is an optional keyword list attached to the final
    unit's `:format_options`. Defaults to `[]`.

  ### Options

  The options are not interpreted by this function; they are attached
  verbatim to the trailing unit's `:format_options` field and merged
  into any later `to_string/2` call for that unit. The typical content
  is `[round_nearest: n]` lifted from CLDR's unit preference skeletons.
  See `to_string/2` for the options that formatting supports.

  ### Returns

  * `{:ok, units}` where `units` is a list of `%Localize.Unit{}` structs.

  * `{:error, exception}` if conversion fails.

  ### Examples

      iex> {:ok, m} = Localize.Unit.new(1.75, "meter")
      iex> {:ok, parts} = Localize.Unit.decompose(m, ["meter", "centimeter"])
      iex> Enum.map(parts, fn u -> {u.name, u.value} end)
      [{"meter", 1}, {"centimeter", 75.0}]

      iex> {:ok, m} = Localize.Unit.new(Decimal.new("1.75"), "meter")
      iex> {:ok, parts} = Localize.Unit.decompose(m, ["meter", "centimeter"])
      iex> Enum.map(parts, fn u -> {u.name, u.value} end)
      [{"meter", 1}, {"centimeter", Decimal.new("75.0")}]

      iex> {:ok, m} = Localize.Unit.new(2.0, "meter")
      iex> {:ok, parts} = Localize.Unit.decompose(m, ["meter", "centimeter"])
      iex> Enum.map(parts, fn u -> u.name end)
      ["meter"]

      iex> {:ok, m} = Localize.Unit.new(0.5, "meter")
      iex> {:ok, parts} = Localize.Unit.decompose(m, ["meter", "centimeter"])
      iex> Enum.map(parts, fn u -> u.name end)
      ["centimeter"]

      iex> {:ok, m} = Localize.Unit.new(1.83, "meter")
      iex> {:ok, parts} = Localize.Unit.decompose(m, ["foot", "inch"], round_nearest: 1)
      iex> List.last(parts).format_options
      [round_nearest: 1]

  """
  @spec decompose(t(), [String.t()], Keyword.t()) :: {:ok, [t()]} | {:error, Exception.t()}
  def decompose(unit, target_units, format_options \\ [])

  def decompose(%__MODULE__{value: nil}, _targets, _format_options) do
    {:error, Localize.UnitNoValueError.exception(operation: :decompose)}
  end

  def decompose(%__MODULE__{} = unit, [single], format_options) do
    case convert(unit, single) do
      {:ok, converted} ->
        if zero?(converted) do
          {:ok, []}
        else
          {:ok, [%{converted | format_options: format_options}]}
        end

      error ->
        error
    end
  end

  def decompose(%__MODULE__{} = unit, [target | rest], format_options) do
    case convert(unit, target) do
      {:ok, converted} -> split_for_decompose(converted, target, rest, format_options)
      error -> error
    end
  end

  def decompose(%__MODULE__{}, [], _format_options) do
    {:ok, []}
  end

  defp split_for_decompose(
         %__MODULE__{value: %Decimal{} = d} = converted,
         target,
         rest,
         format_options
       ) do
    # Truncate toward zero; Decimal.round/3 with :down is the equivalent
    # of `trunc/1` for floats. The remainder stays in Decimal so any
    # subsequent recursion preserves precision instead of round-tripping
    # through float.
    trunc_decimal = Decimal.round(d, 0, :down)
    integer_part = Decimal.to_integer(trunc_decimal)
    remainder = Decimal.sub(d, trunc_decimal)

    cons_part(converted, integer_part, remainder, target, rest, format_options)
  end

  defp split_for_decompose(%__MODULE__{value: value} = converted, target, rest, format_options) do
    float_value = to_float(value)
    integer_part = trunc(float_value)
    remainder = float_value - integer_part

    cons_part(converted, integer_part, remainder, target, rest, format_options)
  end

  # Build the [head | rest] result while skipping intermediate units whose
  # integer part rounded to zero. Mirrors cldr_units' decompose behaviour.
  defp cons_part(converted, integer_part, remainder, target, rest, format_options) do
    with {:ok, remainder_unit} <- new(remainder, target),
         {:ok, rest_parts} <- decompose(remainder_unit, rest, format_options) do
      if integer_part == 0 do
        {:ok, rest_parts}
      else
        {:ok, [%{converted | value: integer_part} | rest_parts]}
      end
    end
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
      nil -> derived_unit_category(name, btq)
      category -> {:ok, category}
    end
  end

  defp derived_unit_category(name, base_unit_to_quantity) do
    with {:ok, parsed} <- Localize.Unit.Parser.parse(name),
         {:ok, base} <- Localize.Unit.BaseUnit.base_unit(parsed) do
      case Map.get(base_unit_to_quantity, base) do
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
  Returns the localized stand-alone display name of a unit.

  This is the CLDR `<displayName>` form — a bare label like
  "meters" or "Meter", suitable for headings, form-field labels,
  or column titles. It is distinct from the value-bearing inline
  forms returned by `to_string/2`, which are pluralised and
  grammatical-case aware (e.g., "5 meters"). If a
  `t:Localize.Unit.t/0` struct carrying a value is passed, the
  value is ignored.

  ### Arguments

  * `unit` is a `%Localize.Unit{}` struct or a unit name string.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is `Localize.get_locale()`.

  * `:style` is `:long`, `:short`, or `:narrow`. The default is `:long`.

  ### Returns

  * `{:ok, name}` or `{:error, exception}`.

  ### Examples

      iex> Localize.Unit.display_name("meter", locale: :en)
      {:ok, "meters"}

      iex> Localize.Unit.display_name("meter", locale: :en, style: :short)
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
        Localize.Unit.Formatter.to_string(unit, translate_style_option(options))

      error ->
        error
    end
  end

  @doc """
  Same as `display_name/2` but raises on error.

  ### Arguments

  * `unit_or_name` is a `t:Localize.Unit.t/0` or a unit name string.

  * `options` is a keyword list of options.

  ### Options

  See `display_name/2` for the supported options.

  ### Returns

  * The localized display name string.

  * Raises an exception if the display name cannot be produced.

  ### Examples

      iex> Localize.Unit.display_name!("meter", locale: :en)
      "meters"

      iex> Localize.Unit.display_name!("meter", locale: :en, style: :short)
      "m"

  """
  @spec display_name!(t() | String.t(), Keyword.t()) :: String.t()
  def display_name!(unit_or_name, options \\ []) do
    case display_name(unit_or_name, options) do
      {:ok, name} -> name
      {:error, exception} -> raise exception
    end
  end

  # `display_name` names a thing, so its width option is `:style` in
  # line with the other display-name functions (Territory, Language,
  # Script, Calendar); the underlying formatter takes `:format`. The
  # caller's `:format` (a deprecated alias removed in 1.0) is
  # overwritten so it is an unknown option like any other.
  defp translate_style_option(options) do
    {style, options} = Keyword.pop(options, :style, :long)
    Keyword.put(options, :format, style)
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
    valid_usages()
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

      iex> Localize.Unit.measurement_system_for_territory(:US, :temperature)
      :us

      iex> Localize.Unit.measurement_system_for_territory(:LR, :temperature)
      :metric

      iex> Localize.Unit.measurement_system_for_territory(:US, :paper_size)
      :us_letter

      iex> Localize.Unit.measurement_system_for_territory(:FR, :paper_size)
      :a4

  """
  @spec measurement_system_for_territory(atom(), :default | :temperature | :paper_size) :: atom()
  def measurement_system_for_territory(territory, category \\ :default)

  def measurement_system_for_territory(territory, :default) when is_atom(territory) do
    default_system_for(territory)
  end

  # Per CLDR's measurementData.json, the category-specific maps list
  # only the *exceptions* — territories whose temperature/paper-size
  # system differs from their default measurement system. So for any
  # territory not in the category map, the answer is the territory's
  # default system (e.g. US/temperature isn't listed because Fahrenheit
  # falls out naturally from US/default = :us).
  def measurement_system_for_territory(territory, :temperature) when is_atom(territory) do
    lookup_with_default_fallback(:measurement_system_temperature, territory)
  end

  def measurement_system_for_territory(territory, :paper_size) when is_atom(territory) do
    case category_lookup(:paper_size, territory) do
      nil -> Map.get(category_map(:paper_size), :"001", :a4)
      explicit -> explicit
    end
  end

  defp default_system_for(territory) do
    Map.get(category_map(:measurement_system), territory) ||
      Map.get(category_map(:measurement_system), :"001", :metric)
  end

  defp lookup_with_default_fallback(category_key, territory) do
    case category_lookup(category_key, territory) do
      nil -> default_system_for(territory)
      explicit -> explicit
    end
  end

  defp category_lookup(category_key, territory) do
    Map.get(category_map(category_key), territory)
  end

  defp category_map(key) do
    Map.fetch!(Localize.SupplementalData.measurement_data(), key)
  end

  # ── Private helpers ───────────────────────────────────────────

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n * 1.0
  defp to_float(n), do: n
end
