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
  @spec mf2_format(String.t(), String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def mf2_format(message, locale \\ "en", args \\ %{}) when is_binary(message) do
    nif_mf2_format(message, locale, :json.encode(args))
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

  # ── NIF stubs ───────────────────────────────────────────────────

  @dialyzer {:no_return, nif_mf2_validate: 1}
  defp nif_mf2_validate(_message) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @dialyzer {:no_return, nif_mf2_format: 3}
  defp nif_mf2_format(_message, _locale, _args_json) do
    :erlang.nif_error(:nif_library_not_loaded)
  end
end
