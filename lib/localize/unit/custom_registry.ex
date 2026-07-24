defmodule Localize.Unit.CustomRegistry do
  @moduledoc """
  Runtime registry for user-defined units backed by `:persistent_term`.

  Custom units are stored in a single map keyed by unit name. The registry
  is checked by `Localize.Unit.Data`, `Localize.Unit.BaseUnit`,
  `Localize.Unit.Conversion`, and the unit formatter to overlay
  runtime definitions on top of the compile-time CLDR data.

  ## Definition structure

  Each definition is a map with the following keys:

  * `:base_unit` (required) — the CLDR unit this custom unit converts to
    (e.g., `"meter"`, `"kilogram"`, `"second"`). It need not be a
    fundamental base unit: a derived unit such as `"day"` is accepted and
    folded down to its fundamental base (`"second"`) at registration, with
    the factor and offset adjusted accordingly, so the custom unit stays
    convertible against every CLDR unit in the same category.

  * `:factor` (required) — the conversion factor:
    `1 custom_unit = factor * base_unit`.

  * `:offset` (optional) — additive offset for the conversion. Defaults to `0.0`.

  * `:category` (required) — the unit category (e.g., `"length"`, `"mass"`).

  * `:display` (optional) — locale-specific display patterns. A nested map of
    `locale => style => plural_patterns`.

  """

  @persistent_term_key :localize_custom_units

  @doc """
  Returns the definition for a custom unit, or `nil` if not registered.

  ### Arguments

  * `unit_name` — the unit identifier string.

  ### Returns

  * A definition map or `nil`.

  ### Examples

      iex> :ok = Localize.Unit.CustomRegistry.register("smoot", %{base_unit: "meter", factor: 1.7018, category: "length"})
      iex> Localize.Unit.CustomRegistry.get("smoot").base_unit
      "meter"

      iex> Localize.Unit.CustomRegistry.get("no-such-unit")
      nil

  """
  @spec get(String.t()) :: map() | nil
  def get(unit_name) do
    all() |> Map.get(unit_name)
  end

  @doc """
  Returns whether a unit name is registered in the custom registry.

  ### Arguments

  * `unit_name` — the unit identifier string.

  ### Returns

  * `true` if the unit is registered, otherwise `false`.

  ### Examples

      iex> Localize.Unit.CustomRegistry.registered?("no-such-unit")
      false

      iex> :ok = Localize.Unit.CustomRegistry.register("smoot", %{base_unit: "meter", factor: 1.7018, category: "length"})
      iex> Localize.Unit.CustomRegistry.registered?("smoot")
      true

  """
  @spec registered?(String.t()) :: boolean()
  def registered?(unit_name) do
    all() |> Map.has_key?(unit_name)
  end

  @doc """
  Returns all registered custom units as a map of name to definition.

  ### Returns

  * A map of unit name to definition map. Empty when no custom units
    are registered.

  ### Examples

      iex> :ok = Localize.Unit.CustomRegistry.register("smoot", %{base_unit: "meter", factor: 1.7018, category: "length"})
      iex> Localize.Unit.CustomRegistry.all()["smoot"].factor
      1.7018

  """
  @spec all() :: %{String.t() => map()}
  def all do
    :persistent_term.get(@persistent_term_key, %{})
  end

  @doc """
  Registers a custom unit definition.

  ### Arguments

  * `name` — the unit identifier string.

  * `definition` — a map with `:base_unit`, `:factor`, and `:category` keys.

  ### Returns

  * `:ok` on success.

  * `{:error, reason}` if validation fails.

  ### Examples

      iex> Localize.Unit.CustomRegistry.register("smoot", %{base_unit: "meter", factor: 1.7018, category: "length"})
      :ok

      iex> {:error, message} = Localize.Unit.CustomRegistry.register("123bad", %{base_unit: "meter", factor: 1.0, category: "length"})
      iex> message =~ "invalid unit name"
      true

  """
  @spec register(String.t(), map()) :: :ok | {:error, String.t()}
  def register(name, definition) do
    with :ok <- validate_name(name),
         :ok <- validate_definition(definition),
         :ok <- validate_no_collision(name),
         {:ok, normalized} <- normalize_base(definition) do
      current = all()
      :persistent_term.put(@persistent_term_key, Map.put(current, name, normalized))
      :ok
    end
  end

  @doc """
  Registers multiple custom units in a single `persistent_term` update.

  This is significantly more memory-efficient than calling `register/2`
  in a loop, because it avoids creating intermediate `persistent_term`
  snapshots for each unit. Each snapshot is stored in the BEAM's literal
  area and is not freed until a global garbage collection sweep, so
  bulk registration via `register/2` can exhaust literal memory.

  ### Arguments

  * `definitions` — a map of `%{name => definition}` where each definition
    has `:base_unit`, `:factor`, and `:category` keys.

  ### Returns

  * `{:ok, count}` with the number of units registered.

  * `{:error, reason}` if any validation fails. No units are registered
    on error (the operation is atomic).

  ### Examples

      iex> definitions = %{
      ...>   "smoot" => %{base_unit: "meter", factor: 1.7018, category: "length"},
      ...>   "sheppey" => %{base_unit: "meter", factor: 1400.0, category: "length"}
      ...> }
      iex> Localize.Unit.CustomRegistry.register_batch(definitions)
      {:ok, 2}

  """
  @spec register_batch(%{String.t() => map()}) :: {:ok, non_neg_integer()}
  def register_batch(definitions) when is_map(definitions) do
    validated_map =
      Enum.reduce(definitions, %{}, fn {name, definition}, acc ->
        with :ok <- validate_name(name),
             :ok <- validate_definition(definition),
             :ok <- validate_no_collision(name),
             {:ok, normalized} <- normalize_base(definition) do
          Map.put(acc, name, normalized)
        else
          {:error, _reason} -> acc
        end
      end)

    current = all()
    :persistent_term.put(@persistent_term_key, Map.merge(current, validated_map))
    {:ok, map_size(validated_map)}
  end

  @doc """
  Loads custom unit definitions from an `.exs` file.

  The file must evaluate to a list of maps, each with a `:unit` key
  and the standard definition fields.

  > #### Security {: .warning}
  >
  > This function uses `Code.eval_file/1` to evaluate the given
  > file, which executes arbitrary Elixir code. Only load files
  > from trusted sources. Never call this function with unsanitised
  > user input or paths derived from external data.
  >
  > In a `:prod` Mix environment this function additionally requires
  > the `:localize, :allow_runtime_unit_files` config flag to be
  > explicitly set to `true`. The flag exists so that an unintended
  > feature switch in a production deployment cannot accidentally
  > surface arbitrary code execution. Set it in `config/runtime.exs`
  > (not `config/config.exs`) so the decision is visible at the same
  > layer as other deployment-time policy.

  ### Arguments

  * `path` — path to the `.exs` file.

  ### Returns

  * `{:ok, count}` with the number of units loaded.

  * `{:error, reason}` on failure, including a refusal in `:prod`
    when the flag is not set.

  ### Examples

      iex> {:error, message} = Localize.Unit.CustomRegistry.load_file("no/such/file.exs")
      iex> message =~ "file not found"
      true

  """
  @spec load_file(String.t()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def load_file(path) do
    with :ok <- check_runtime_eval_allowed(),
         expanded = Path.expand(path),
         true <- file_exists_or_error(expanded) do
      do_load_file(expanded)
    end
  end

  defp file_exists_or_error(expanded) do
    if File.exists?(expanded) do
      true
    else
      {:error, "file not found: #{expanded}"}
    end
  end

  # Refuse to evaluate the file in `:prod` unless the operator has
  # explicitly opted in via `config :localize, :allow_runtime_unit_files,
  # true`. Outside `:prod` (development, test, runtime helpers) the
  # function works as before — operators wiring custom units in dev
  # don't need a flag to do so.
  defp check_runtime_eval_allowed do
    if production_env?() and
         Application.get_env(:localize, :allow_runtime_unit_files, false) != true do
      {:error,
       "Localize.Unit.CustomRegistry.load_file/1 is disabled in :prod by default. " <>
         "Set `config :localize, :allow_runtime_unit_files, true` in config/runtime.exs " <>
         "to enable it explicitly."}
    else
      :ok
    end
  end

  # `Mix` is generally not available at runtime in a release. Treat
  # "no Mix module" as production-equivalent — releases that bundle
  # Mix (rare) keep their declared env, otherwise the safest default
  # applies.
  defp production_env? do
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
      # Mix is absent at runtime in releases; a direct call trips the
      # missing-:mix-dependency compiler warning.
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Mix, :env, []) == :prod
    else
      true
    end
  end

  defp do_load_file(expanded) do
    {definitions, _bindings} = Code.eval_file(expanded)

    case definitions do
      defs when is_list(defs) ->
        batch =
          Enum.reduce_while(defs, {:ok, %{}}, fn
            %{unit: name} = definition, {:ok, acc} ->
              {:cont, {:ok, Map.put(acc, name, Map.delete(definition, :unit))}}

            other, _acc ->
              {:halt,
               {:error, "invalid definition: expected map with :unit key, got #{inspect(other)}"}}
          end)

        case batch do
          {:ok, batch_map} -> register_batch(batch_map)
          {:error, _} = error -> error
        end

      other ->
        {:error, "expected a list of definitions, got #{inspect(other, limit: 50)}"}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  @doc """
  Removes all custom unit registrations. Primarily for testing.

  ### Returns

  * `:ok`.

  ### Examples

      iex> :ok = Localize.Unit.CustomRegistry.register("smoot", %{base_unit: "meter", factor: 1.7018, category: "length"})
      iex> Localize.Unit.CustomRegistry.clear()
      :ok
      iex> Localize.Unit.CustomRegistry.registered?("smoot")
      false

  """
  @spec clear() :: :ok
  def clear do
    :persistent_term.put(@persistent_term_key, %{})
    :ok
  end

  # ── Base-unit normalization ──

  # A custom unit's `:base_unit` must be a fundamental CLDR base unit,
  # because compatibility and conversion compare fully-reduced base
  # units: `compatible?/2` succeeds only when both units reduce to the
  # same base. When a definition is expressed in terms of a *derived*
  # unit (e.g. `%{base_unit: "day", factor: 1}`), storing "day"
  # verbatim leaves the custom unit reducing to "day" while every CLDR
  # unit reduces "day" to "second" — so the two never match.
  #
  # Fold the derived unit's own conversion into the custom factor and
  # offset so the stored base becomes the fundamental base with an
  # equivalent factor: `guestnight` given as `base_unit: "day",
  # factor: 1` is stored as `base_unit: "second", factor: 86400.0`.
  # A definition already expressed against a fundamental base is stored
  # unchanged, and `:special` (function-based) definitions — which do
  # not convert via a linear factor — are left untouched.
  defp normalize_base(%{factor: factor} = definition) when is_number(factor) do
    base = definition.base_unit

    case Localize.Unit.BaseUnit.base_unit(base) do
      {:ok, ^base} ->
        {:ok, definition}

      {:ok, true_base} ->
        with {:ok, base_factor, base_offset} <- base_conversion(base, true_base) do
          offset = Map.get(definition, :offset, 0.0)

          {:ok,
           definition
           |> Map.put(:base_unit, true_base)
           |> Map.put(:factor, factor * base_factor)
           |> Map.put(:offset, offset * base_factor + base_offset)}
        end

      {:error, _reason} ->
        {:error, "unknown base unit: #{inspect(base)}"}
    end
  end

  defp normalize_base(definition), do: {:ok, definition}

  # The linear parameters `{factor, offset}` that convert one unit of
  # `base` into `true_base`, such that
  # `value_in_true_base = value_in_base * factor + offset`. For a simple
  # derived unit CLDR stores these directly; for a compound derived unit
  # they are recovered from two reference conversions (the offset is the
  # image of zero, the factor the difference across one unit).
  defp base_conversion(base, true_base) do
    case Localize.Unit.Data.conversion_factor_raw(base) do
      %{factor: factor, offset: offset} when is_number(factor) ->
        {:ok, factor, offset}

      _other ->
        with {:ok, at_zero} <- Localize.Unit.Conversion.convert(0, base, true_base),
             {:ok, at_one} <- Localize.Unit.Conversion.convert(1, base, true_base) do
          {:ok, at_one - at_zero, at_zero}
        end
    end
  end

  # ── Validation ──

  @name_pattern ~r/^[a-z][a-z0-9_-]*$/

  defp validate_name(name) when is_binary(name) do
    if Regex.match?(@name_pattern, name) do
      :ok
    else
      {:error,
       "invalid unit name #{inspect(name)}: must start with a lowercase letter and contain only lowercase letters, digits, and hyphens"}
    end
  end

  defp validate_name(name) do
    {:error, "unit name must be a string, got #{inspect(name)}"}
  end

  defp validate_definition(%{factor: :special} = definition) do
    with :ok <- validate_required_key(definition, :base_unit, &is_binary/1),
         :ok <- validate_required_key(definition, :category, &is_binary/1),
         :ok <- validate_base_unit(definition.base_unit),
         :ok <- validate_category(definition.category),
         :ok <- validate_conversion_fun(definition, :forward) do
      validate_conversion_fun(definition, :inverse)
    end
  end

  defp validate_definition(definition) when is_map(definition) do
    with :ok <- validate_required_key(definition, :base_unit, &is_binary/1),
         :ok <- validate_required_key(definition, :factor, &is_number/1),
         :ok <- validate_required_key(definition, :category, &is_binary/1),
         :ok <- validate_base_unit(definition.base_unit),
         :ok <- validate_category(definition.category) do
      validate_positive_factor(definition.factor)
    end
  end

  defp validate_definition(_definition) do
    {:error, "definition must be a map"}
  end

  defp validate_required_key(map, key, validator) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        if validator.(value) do
          :ok
        else
          {:error, "#{key} has invalid type: #{inspect(value)}"}
        end

      :error ->
        {:error, "missing required key: #{key}"}
    end
  end

  defp validate_base_unit(base_unit) do
    case Localize.Unit.BaseUnit.base_unit(base_unit) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "unknown base unit: #{inspect(base_unit)}"}
    end
  end

  defp validate_category(category) when is_binary(category) and category != "", do: :ok

  defp validate_category(category) do
    {:error, "invalid category: #{inspect(category)}, expected a non-empty string"}
  end

  defp validate_conversion_fun(definition, key) do
    case Map.fetch(definition, key) do
      {:ok, {module, function}} when is_atom(module) and is_atom(function) ->
        Code.ensure_loaded(module)

        if function_exported?(module, function, 1) do
          :ok
        else
          {:error, "#{key}: #{inspect(module)}.#{function}/1 is not exported"}
        end

      {:ok, other} ->
        {:error, "#{key}: expected {module, function} tuple, got #{inspect(other)}"}

      :error ->
        {:error, "missing required key: #{key} (required for special conversions)"}
    end
  end

  defp validate_positive_factor(factor) when factor > 0, do: :ok

  defp validate_positive_factor(factor) do
    {:error, "factor must be positive, got #{inspect(factor)}"}
  end

  defp validate_no_collision(name) do
    known = Localize.Unit.Data.conversions()

    if Map.has_key?(known, name) do
      {:error, "unit #{inspect(name)} already exists as a CLDR unit"}
    else
      :ok
    end
  end
end
