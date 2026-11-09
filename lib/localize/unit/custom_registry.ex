defmodule Localize.Unit.CustomRegistry do
  @moduledoc """
  Runtime registry for user-defined units.

  Custom units are kept in an ETS table keyed by unit name. The registry
  is checked by `Localize.Unit.Data`, `Localize.Unit.BaseUnit`,
  `Localize.Unit.Conversion`, and the unit formatter to overlay
  runtime definitions on top of the compile-time CLDR data.

  ## Supervision

  The table belongs to this module's process, which `Localize.Supervisor`
  starts with Localize's other processes, so an application that adds the
  dependency has it running. A host that starts `Localize.Supervisor` in
  its own tree has the registry with it. Registrations go through the
  process, one at a time, so concurrent registrations are all kept; reads
  go to the table directly. A registration made before the process starts
  returns an error, and the units last as long as the process does.

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
    `locale => style => plural_patterns`, where each pattern is a `"{0}"`
    placeholder string (`%{one: "{0} smoot", other: "{0} smoots"}`).

  Note that the `:inflect` engine fallback of `Localize.Unit.to_string/2`
  applies to CLDR units only; a custom unit renders the pattern it was
  registered with.

  """

  use GenServer

  @table :localize_custom_units

  @name_pattern ~r/^[a-z][a-z0-9_-]*$/

  @not_running "the custom unit registry is not running: start the :localize " <>
                 "application, or Localize.Supervisor in your own supervision tree"

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
    if table?() do
      case :ets.lookup(@table, unit_name) do
        [{_name, definition}] -> definition
        [] -> nil
      end
    end
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
    table?() and :ets.member(@table, unit_name)
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
    if table?() do
      @table
      |> :ets.tab2list()
      |> Map.new()
    else
      %{}
    end
  end

  @doc """
  Registers a custom unit definition.

  ### Arguments

  * `name` — the unit identifier string.

  * `definition` — a map with `:base_unit`, `:factor`, and `:category` keys.

  ### Returns

  * `:ok` on success.

  * `{:error, reason}` if validation fails or the registry's process is
    not running, with `reason` a message.

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
      insert([{name, normalized}])
    end
  end

  @doc """
  Registers multiple custom units at once.

  The units are written together: a reader sees all of them or none.

  ### Arguments

  * `definitions` — a map of `%{name => definition}` where each definition
    has `:base_unit`, `:factor`, and `:category` keys.

  ### Returns

  * `{:ok, count}` with the number of units registered. A definition that
    fails validation is left out and not counted.

  * `{:error, exception}` if `definitions` is not a map, or a
    `RuntimeError` if the registry's process is not running.

  ### Examples

      iex> definitions = %{
      ...>   "smoot" => %{base_unit: "meter", factor: 1.7018, category: "length"},
      ...>   "sheppey" => %{base_unit: "meter", factor: 1400.0, category: "length"}
      ...> }
      iex> Localize.Unit.CustomRegistry.register_batch(definitions)
      {:ok, 2}

  """
  @spec register_batch(%{String.t() => map()}) ::
          {:ok, non_neg_integer()} | {:error, Exception.t()}
  def register_batch(definitions) when is_map(definitions) do
    validated_map =
      Enum.reduce(definitions, %{}, fn {name, definition}, acc ->
        put_validated(acc, name, definition)
      end)

    case insert(Map.to_list(validated_map)) do
      :ok -> {:ok, map_size(validated_map)}
      {:error, message} -> {:error, RuntimeError.exception(message)}
    end
  end

  def register_batch(definitions),
    do: {:error, Localize.Utils.Helpers.invalid_value(definitions, "a map of unit definitions")}

  # A definition the registry will not take is left out of the batch rather
  # than failing the whole of it.
  defp put_validated(acc, name, definition) do
    case validated(name, definition) do
      {:ok, normalized} -> Map.put(acc, name, normalized)
      {:error, _reason} -> acc
    end
  end

  defp validated(name, definition) do
    with :ok <- validate_name(name),
         :ok <- validate_definition(definition),
         :ok <- validate_no_collision(name) do
      normalize_base(definition)
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
  def load_file(path) when is_binary(path) do
    with :ok <- check_runtime_eval_allowed(),
         expanded = Path.expand(path),
         true <- file_exists_or_error(expanded) do
      do_load_file(expanded)
    end
  end

  def load_file(path), do: {:error, "a file path string was expected, got: #{inspect(path)}"}

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

  # The file is code, and code can fail to compile or raise when it runs, so
  # it is evaluated in a process of its own and a failure comes back as an
  # error.
  defp do_load_file(expanded) do
    case Localize.Utils.Helpers.run_isolated(fn -> evaluate_file(expanded) end) do
      {:ok, definitions} -> register_definitions(definitions)
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp evaluate_file(expanded) do
    {definitions, _bindings} = Code.eval_file(expanded)
    definitions
  end

  defp register_definitions(definitions) when is_list(definitions) do
    batch =
      Enum.reduce_while(definitions, {:ok, %{}}, fn
        %{unit: name} = definition, {:ok, acc} ->
          {:cont, {:ok, Map.put(acc, name, Map.delete(definition, :unit))}}

        other, _acc ->
          {:halt,
           {:error, "invalid definition: expected map with :unit key, got #{inspect(other)}"}}
      end)

    case batch do
      {:ok, batch_map} -> loaded(register_batch(batch_map))
      {:error, _} = error -> error
    end
  end

  defp register_definitions(other) do
    {:error, "expected a list of definitions, got #{inspect(other, limit: 50)}"}
  end

  # `load_file/1` reports a failure as a message, as it always has.
  defp loaded({:error, exception}) when is_exception(exception) do
    {:error, Exception.message(exception)}
  end

  defp loaded(result) do
    result
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
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :clear)
    else
      :ok
    end
  end

  # ── The registry's process ──

  @doc """
  Starts the registry's process, which owns the table of custom units.

  `Localize.Supervisor` starts it; a host adds `Localize.Supervisor` to its
  own tree rather than this module.

  ### Arguments

  * `options` is a keyword list. No options are currently honoured.

  ### Returns

  * `{:ok, pid}`, or

  * `{:error, reason}` if the process cannot start, as for
    `GenServer.start_link/3`.

  ### Examples

      iex> {:error, {:already_started, _pid}} = Localize.Unit.CustomRegistry.start_link()

  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl GenServer
  def init(_options) do
    :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:insert, entries}, _from, state) do
    :ets.insert(@table, entries)
    {:reply, :ok, state}
  end

  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  # Writes the entries through the process that owns the table. One
  # `:ets.insert/2` writes them all at once, and the process takes one
  # write at a time, so no registration replaces another.
  defp insert(entries) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:insert, entries})
    else
      {:error, @not_running}
    end
  end

  defp table? do
    :ets.whereis(@table) != :undefined
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
