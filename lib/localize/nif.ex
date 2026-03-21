defmodule Localize.Nif do
  @moduledoc """
  Optional NIF interface to ICU4C for high-performance locale operations.

  This module provides NIF bindings for ICU4C functions including
  MessageFormat 2.0 parsing and formatting. Additional functions for
  number, date/time, and unit formatting will be added as the library
  grows.

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

  @doc false
  def init do
    path = :code.priv_dir(:localize) ++ ~c"/localize_nif"

    case :erlang.load_nif(path, :erlang.system_info(:schedulers)) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
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
    match?({:ok, _}, nif_mf2_validate(""))
  rescue
    _ -> false
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

  Arguments are passed as a map of `%{name => value}` and
  encoded to JSON for the NIF.

  ### Arguments

  * `message` is an MF2 message string.

  * `locale` is a locale identifier string. The default is `"en"`.

  * `args` is a map of variable bindings. The default is `%{}`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, reason}` on failure.

  """
  @spec mf2_format(String.t(), String.t(), map() | String.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def mf2_format(message, locale \\ "en", args \\ %{}) when is_binary(message) do
    args_map =
      case args do
        json when is_binary(json) -> :json.decode(json)
        map when is_map(map) -> map
      end

    case unbound_variables(message, args_map) do
      [] ->
        args_json = IO.iodata_to_binary(:json.encode(args_map))
        nif_mf2_format(message, locale, args_json)

      unbound ->
        {:error, Localize.BindError.exception(unbound: unbound)}
    end
  end

  @variable_pattern ~r/\$([a-zA-Z_][a-zA-Z0-9_]*)/
  @local_declaration_pattern ~r/\.(?:local|input)\s+\$([a-zA-Z_][a-zA-Z0-9_]*)/

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

  ### Returns

  * `true` if the collation NIF function was loaded successfully.

  * `false` if the NIF is not compiled or ICU libraries are missing.

  """
  @spec collation_available?() :: boolean()
  def collation_available? do
    match?(
      result when is_integer(result),
      nif_collation_cmp("", "", -1, -1, -1, -1, -1, -1, -1, <<>>)
    )
  rescue
    _ -> false
  end

  @doc """
  Compare two strings using ICU collation with full option support.

  This is the raw NIF function. Use `Localize.Collation.Nif.nif_compare/3`
  for the higher-level interface that handles option encoding.

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
  @dialyzer {:no_return, nif_collation_cmp: 10}
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

      iex> Localize.Nif.plural_rule(1, "en", :cardinal)
      {:ok, :one}

      iex> Localize.Nif.plural_rule(2, "en", :ordinal)
      {:ok, :two}

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
end
