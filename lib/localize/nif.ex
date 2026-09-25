defmodule Localize.Nif do
  @moduledoc """
  Optional NIF interface to ICU4C for high-performance locale operations.

  This module provides NIF bindings for ICU4C functions including
  MessageFormat 2.0 parsing and formatting, number formatting, plural
  rules, unit formatting and collation.

  The stable way to use the NIF backend is the `backend: :nif` option
  on the corresponding public formatting functions (for example
  `Localize.Number.to_string/2` and `Localize.Message.format/3`); the
  individual functions in this module are a low-level surface whose
  signatures may change with the underlying ICU API.

  The NIF is opt-in and requires:

  1. ICU system libraries installed (ICU 75+ with MF2 support).

  2. The `elixir_make` dependency.

  3. Enable the NIF via either:
     * Environment variable: `LOCALIZE_NIF=true mix compile`
     * Application config in `config.exs`: `config :localize, :nif, true`

  The config key must be set in `config.exs` (not `runtime.exs`) because
  it is evaluated at compile time to include the `:elixir_make` compiler.

  If the NIF is not available, `available?/0` returns `false` and the
  pure Elixir implementations are used automatically.

  """

  @on_load :init

  # Whether `init/0` loaded the shared library. The stubs below raise when
  # it is absent, so availability is recorded when the module loads rather
  # than probed by calling one.
  @loaded_key {__MODULE__, :loaded?}

  @doc false
  def init do
    path =
      :localize
      |> Application.app_dir("priv/localize_nif")
      |> String.to_charlist()

    # Size the NIF's collator pool for both regular and dirty CPU
    # schedulers. NIFs tagged `ERL_NIF_DIRTY_JOB_CPU_BOUND` (used by
    # collation, MF2, and number/unit formatting) run on the dirty CPU
    # scheduler pool, which is independent of the regular schedulers.
    # Sizing the collator pool for the sum prevents the bounded stack
    # in `reserve_coll/2` from being exhausted when concurrent calls
    # span both scheduler classes.
    pool_size =
      :erlang.system_info(:schedulers) + :erlang.system_info(:dirty_cpu_schedulers)

    loaded? = :erlang.load_nif(path, pool_size) == :ok
    :persistent_term.put(@loaded_key, loaded?)
    :ok
  end

  @doc """
  Returns whether the NIF backend is available.

  ### Returns

  * `true` if the NIF shared library was loaded successfully.

  * `false` if the NIF is not compiled or ICU libraries are missing.

  ### Examples

      iex> is_boolean(Localize.Nif.available?())
      true

  """
  @spec available?() :: boolean()
  def available? do
    :persistent_term.get(@loaded_key, false)
  end

  # ── MessageFormat 2 ─────────────────────────────────────────────

  @doc """
  Validates a MessageFormat 2 message string using ICU's parser.

  ### Arguments

  * `message` is an MF2 message string.

  ### Returns

  * `{:ok, normalized_pattern}` if the message is valid.

  * `{:error, reason}` if the message is invalid.

  """
  @spec mf2_validate(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def mf2_validate(message) when is_binary(message) do
    nif_mf2_validate(message)
  end

  @doc """
  Formats a MessageFormat 2 message string using ICU.

  The arguments reach ICU as a flat JSON object, so each value must be
  one that crosses unchanged: a string, an integer within 64 bits or a
  float. `Localize.Message.format/3` with `backend: :nif` formats a
  message whose bindings hold anything else with the Elixir interpreter.

  ### Arguments

  * `message` is an MF2 message string.

  * `locale` is a locale identifier string. The default is `"en"`.

  * `args` is a map of argument names to values, or the same map as
    a JSON object. The default is `%{}`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, reason}` if ICU cannot format the message.

  * `{:error, exception}` if an argument the message uses is missing,
    if any argument is not a string, a 64-bit integer or a float, if
    `args` is neither a map nor a JSON object, or if `message` or
    `locale` is not a string.

  """
  @dialyzer {:nowarn_function, mf2_format: 3}

  @spec mf2_format(String.t(), String.t(), map() | String.t()) ::
          {:ok, String.t()} | {:error, String.t() | Exception.t()}
  def mf2_format(message, locale \\ "en", args \\ %{})

  def mf2_format(message, locale, args) when is_binary(message) and is_binary(locale) do
    with {:ok, args_map, args_json} <- mf2_arguments(args) do
      case unbound_variables(message, args_map) do
        [] -> nif_mf2_format(message, locale, args_json)
        unbound -> {:error, Localize.BindError.exception(unbound: unbound)}
      end
    end
  end

  def mf2_format(message, locale, _args) when is_binary(message),
    do: {:error, Localize.Utils.Helpers.invalid_value(locale, "a locale identifier string")}

  def mf2_format(message, _locale, _args),
    do: {:error, Localize.Utils.Helpers.invalid_value(message, "an MF2 message string")}

  @doc false
  # Whether every argument crosses to ICU unchanged: a name that is text,
  # and a string, an integer within 64 bits or a float. The message
  # formatter asks before choosing the NIF for a message.
  @spec mf2_arguments?(map()) :: boolean()
  def mf2_arguments?(args) when is_map(args), do: Enum.all?(args, &mf2_argument?/1)

  # JSON text is checked as the map it decodes to and passed on as written;
  # a map is encoded.
  defp mf2_arguments(json) when is_binary(json) do
    with {:ok, args} <- decode_arguments(json),
         :ok <- check_arguments(args) do
      {:ok, args, json}
    end
  end

  defp mf2_arguments(args) when is_map(args) do
    with :ok <- check_arguments(args) do
      {:ok, args, IO.iodata_to_binary(:json.encode(args))}
    end
  end

  defp mf2_arguments(args) do
    {:error,
     Localize.Utils.Helpers.invalid_value(args, "a map of arguments or a JSON object of them")}
  end

  # `:json.decode/1` raises on text that is not JSON and has no form that
  # returns an error, so it runs in a process of its own.
  defp decode_arguments(json) do
    case Localize.Utils.Helpers.run_isolated(fn -> :json.decode(json) end) do
      {:ok, args} when is_map(args) ->
        {:ok, args}

      _not_an_object ->
        {:error, Localize.Utils.Helpers.invalid_value(json, "a JSON object of arguments")}
    end
  end

  defp check_arguments(args) do
    case Enum.find(args, &(not mf2_argument?(&1))) do
      nil ->
        :ok

      {name, value} ->
        {:error,
         Localize.InvalidValueError.exception(
           value: value,
           expected: "a string, an integer within 64 bits or a float",
           context: "the argument #{inspect(name)}"
         )}
    end
  end

  @min_int64 -0x8000000000000000
  @max_int64 0x7FFFFFFFFFFFFFFF

  defp mf2_argument?({name, value}), do: mf2_name?(name) and mf2_value?(value)

  defp mf2_name?(name) when is_binary(name), do: String.valid?(name)
  defp mf2_name?(name), do: is_atom(name)

  defp mf2_value?(value) when is_binary(value), do: String.valid?(value)
  defp mf2_value?(value) when is_integer(value), do: value >= @min_int64 and value <= @max_int64
  defp mf2_value?(value), do: is_float(value)

  @variable_pattern ~r/\$([a-zA-Z_][a-zA-Z0-9_]*)/
  @local_declaration_pattern ~r/\.(?:local|input)\s+\$([a-zA-Z_][a-zA-Z0-9_]*)/

  @dialyzer {:nowarn_function, unbound_variables: 2}
  defp unbound_variables(message, args) do
    declared =
      @local_declaration_pattern
      |> Regex.scan(message)
      |> Enum.map(fn [_match, name] -> name end)
      |> MapSet.new()

    @variable_pattern
    |> Regex.scan(message)
    |> Enum.map(fn [_match, name] -> name end)
    |> Enum.uniq()
    |> Enum.reject(fn name ->
      Map.has_key?(args, name) || MapSet.member?(declared, name)
    end)
  end

  # ── Collation ───────────────────────────────────────────────────

  @doc """
  Returns whether the collation NIF function is available.

  The collation functions are part of the same shared library as the
  rest of the NIF, so they are available exactly when `available?/0`
  is `true`.

  ### Returns

  * `true` if the collation NIF function was loaded successfully.

  * `false` if the NIF is not compiled or ICU libraries are missing.

  """
  @spec collation_available?() :: boolean()
  def collation_available?, do: available?()

  @doc """
  Compare two strings using ICU collation with full option support.

  This is the raw NIF function. Use `Localize.Collation.compare/3`
  for the public interface that handles option encoding.

  ### Arguments

  * `string_a` - the first string to compare.

  * `string_b` - the second string to compare.

  * `strength` - ICU strength enum value, or -1 for default.

  * `backwards` - ICU backwards enum value, or -1 for default.

  * `alternate` - ICU alternate enum value, or -1 for default.

  * `case_first` - ICU case_first enum value, or -1 for default.

  * `case_level` - ICU case_level enum value, or -1 for default.

  * `normalization` - ICU normalization enum value, or -1 for default.

  * `numeric` - ICU numeric enum value, or -1 for default.

  * `reorder_bin` - binary of packed big-endian int32 reorder codes.

  ### Returns

  An integer: `-1` (less than), `0` (equal), or `1` (greater than).

  """
  @spec nif_collation_cmp(
          binary(),
          binary(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          binary()
        ) :: -1 | 0 | 1
  @dialyzer {:no_return, nif_collation_cmp: 10}
  # The arity mirrors the C NIF signature one-to-one; collapsing the
  # collation options into a map would add per-call marshalling on a
  # hot path.
  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  def nif_collation_cmp(
        _string_a,
        _string_b,
        _strength,
        _backwards,
        _alternate,
        _case_first,
        _case_level,
        _normalization,
        _numeric,
        _reorder_bin
      ) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  # ── Plural Rules ──────────────────────────────────────────────────

  @doc """
  Returns the plural category for a number using ICU's PluralRules.

  ### Arguments

  * `number` is a number (integer, float, or Decimal) to classify.

  * `locale` is a locale identifier string (e.g., `"en"`, `"ar"`).

  * `type` is `:cardinal` or `:ordinal`.

  ### Returns

  * `{:ok, category}` where `category` is one of `:zero`, `:one`,
    `:two`, `:few`, `:many`, or `:other`.

  * `{:error, reason}` if ICU cannot determine the plural category.

  ### Examples

  When the NIF is available:

      Localize.Nif.plural_rule(1, "en", :cardinal)
      #=> {:ok, :one}

      Localize.Nif.plural_rule(2, "en", :ordinal)
      #=> {:ok, :two}

  """
  @spec plural_rule(number() | Decimal.t(), String.t(), :cardinal | :ordinal) ::
          {:ok, atom()} | {:error, String.t()}
  def plural_rule(number, locale, type \\ :cardinal)

  def plural_rule(%Decimal{} = number, locale, type) do
    number_str = Decimal.to_string(number, :normal)
    nif_plural_rule(number_str, locale, to_string(type), 0)
  end

  def plural_rule(number, locale, type) when is_integer(number) do
    nif_plural_rule(Integer.to_string(number), locale, to_string(type), 0)
  end

  def plural_rule(number, locale, type) when is_float(number) do
    nif_plural_rule(Float.to_string(number), locale, to_string(type), 0)
  end

  # ── NIF stubs ───────────────────────────────────────────────────

  @dialyzer {:no_return, nif_mf2_validate: 1}
  defp nif_mf2_validate(_message) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @dialyzer {:no_return, nif_mf2_format: 3}
  defp nif_mf2_format(_message, _locale, _args_json) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @dialyzer {:no_return, nif_plural_rule: 4}
  defp nif_plural_rule(_number, _locale, _type, _rounding) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  # ── Number formatting ───────────────────────────────────────────

  @doc """
  Formats a number using ICU4C's NumberFormatter.

  This provides a reference implementation for cross-validating
  the pure Elixir number formatting in `Localize.Number`.

  ### Arguments

  * `number` is a number (integer, float, or Decimal).

  * `locale` is a locale identifier string (e.g., `"en-US"`, `"de"`).

  * `options` is a keyword list of options.

  ### Options

  * `:currency` is an ISO 4217 currency code string (e.g., `"USD"`).

  * `:min_fraction_digits` is the minimum fractional digits.

  * `:max_fraction_digits` is the maximum fractional digits.

  * `:notation` is one of `"standard"`, `"scientific"`, `"compact"`.

  * `:use_grouping` is a boolean for grouping separators.

  ### Returns

  * `{:ok, formatted_string}` or `{:error, reason}`.

  """
  @spec number_format(number() | Decimal.t(), String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def number_format(number, locale, options \\ []) do
    number_str =
      cond do
        is_integer(number) -> Integer.to_string(number)
        is_float(number) -> Float.to_string(number)
        is_struct(number, Decimal) -> Decimal.to_string(number, :normal)
        true -> to_string(number)
      end

    options_json = encode_number_options(options)
    nif_number_format(number_str, "", locale, options_json)
  end

  defp encode_number_options([]), do: "{}"

  defp encode_number_options(options) do
    pairs =
      options
      |> Enum.map(fn
        {:currency, code} -> "\"currency\":\"#{code}\""
        {:min_fraction_digits, n} -> "\"minFractionDigits\":#{n}"
        {:max_fraction_digits, n} -> "\"maxFractionDigits\":#{n}"
        {:notation, n} -> "\"notation\":\"#{n}\""
        {:use_grouping, false} -> "\"useGrouping\":false"
        {:use_grouping, true} -> "\"useGrouping\":true"
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join(",")

    "{#{pairs}}"
  end

  @dialyzer {:no_return, nif_number_format: 4}
  defp nif_number_format(_number, _pattern, _locale, _options_json) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  # ── Unit formatting ────────────────────────────────────────────

  @doc """
  Formats a number with a unit using ICU4C's NumberFormatter.

  ### Arguments

  * `number` is a number (integer, float, or Decimal).

  * `unit` is an ICU unit identifier string (e.g., `"meter"`,
    `"mile-per-hour"`).

  * `locale` is a locale identifier string.

  * `options` is a keyword list of options.

  ### Options

  * `:style` is `"long"`, `"short"`, or `"narrow"`. Default is `"long"`.

  ### Returns

  * `{:ok, formatted_string}` or `{:error, reason}`.

  """
  @spec unit_format(number() | Decimal.t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def unit_format(number, unit, locale, options \\ []) do
    number_str =
      cond do
        is_integer(number) -> Integer.to_string(number)
        is_float(number) -> Float.to_string(number)
        is_struct(number, Decimal) -> Decimal.to_string(number, :normal)
        true -> Kernel.to_string(number)
      end

    style = Keyword.get(options, :style, "long")
    style_str = if is_atom(style), do: Atom.to_string(style), else: style

    # Convert Localize unit name to ICU format (underscores to hyphens)
    icu_unit = String.replace(unit, "_", "-")

    nif_unit_format(number_str, icu_unit, locale, style_str)
  end

  @dialyzer {:no_return, nif_unit_format: 4}
  defp nif_unit_format(_number, _unit, _locale, _style) do
    :erlang.nif_error(:nif_library_not_loaded)
  end
end
