defmodule Localize.Unit.CustomRegistry do
  @moduledoc """
  Runtime registry for user-defined units backed by `:persistent_term`.

  Custom units are stored in a single map keyed by unit name. The registry
  is checked by `Localize.Unit.Data`, `Localize.Unit.BaseUnit`,
  `Localize.Unit.Conversion`, and the unit formatter to overlay
  runtime definitions on top of the compile-time CLDR data.

  ## Definition structure

  Each definition is a map with the following keys:

  * `:base_unit` (required) — the CLDR base unit this custom unit converts to
    (e.g., `"meter"`, `"kilogram"`, `"second"`).

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

  """
  @spec get(String.t()) :: map() | nil
  def get(unit_name) do
    all() |> Map.get(unit_name)
  end

  @doc """
  Returns whether a unit name is registered in the custom registry.

  """
  @spec registered?(String.t()) :: boolean()
  def registered?(unit_name) do
    all() |> Map.has_key?(unit_name)
  end

  @doc """
  Returns all registered custom units as a map of name to definition.

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

  """
  @spec register(String.t(), map()) :: :ok | {:error, String.t()}
  def register(name, definition) do
    with :ok <- validate_name(name),
         :ok <- validate_definition(definition),
         :ok <- validate_no_collision(name) do
      current = all()
      :persistent_term.put(@persistent_term_key, Map.put(current, name, definition))
      :ok
    end
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

  ### Arguments

  * `path` — path to the `.exs` file.

  ### Returns

  * `{:ok, count}` with the number of units loaded.

  * `{:error, reason}` on failure.

  """
  @spec load_file(String.t()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def load_file(path) do
    expanded = Path.expand(path)

    case File.exists?(expanded) do
      false ->
        {:error, "file not found: #{expanded}"}

      true ->
        try do
          {definitions, _bindings} = Code.eval_file(expanded)

          case definitions do
            defs when is_list(defs) ->
              results =
                Enum.map(defs, fn
                  %{unit: name} = definition ->
                    register(name, Map.delete(definition, :unit))

                  other ->
                    {:error,
                     "invalid definition: expected map with :unit key, got #{inspect(other)}"}
                end)

              errors = Enum.filter(results, &match?({:error, _}, &1))

              case errors do
                [] -> {:ok, length(results)}
                _ -> {:error, Enum.map_join(errors, "; ", fn {:error, msg} -> msg end)}
              end

            other ->
              {:error, "expected a list of definitions, got #{inspect(other, limit: 50)}"}
          end
        rescue
          error -> {:error, Exception.message(error)}
        end
    end
  end

  @doc """
  Removes all custom unit registrations. Primarily for testing.

  """
  @spec clear() :: :ok
  def clear do
    :persistent_term.put(@persistent_term_key, %{})
    :ok
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

  defp validate_definition(definition) when is_map(definition) do
    with :ok <- validate_required_key(definition, :base_unit, &is_binary/1),
         :ok <- validate_required_key(definition, :factor, &is_number/1),
         :ok <- validate_required_key(definition, :category, &is_binary/1),
         :ok <- validate_base_unit(definition.base_unit),
         :ok <- validate_category(definition.category),
         :ok <- validate_positive_factor(definition.factor) do
      :ok
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

  defp validate_category(category) do
    if category in Localize.Unit.Data.categories() do
      :ok
    else
      {:error,
       "unknown category: #{inspect(category)}. Known categories: #{inspect(Localize.Unit.Data.categories())}"}
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
