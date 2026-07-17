defmodule Localize.Number.Symbol do
  @moduledoc """
  Functions to manage the number symbol definitions for a locale
  and number system.

  Number symbols define the characters used for decimal separators,
  grouping separators, percent signs, and other formatting elements.
  Each locale may define symbols for one or more number systems
  (e.g., `:latn`, `:arab`, `:thai`).

  Symbol data is retrieved at runtime from locale data via the
  configured locale provider.

  """

  defstruct [
    :decimal,
    :group,
    :exponential,
    :infinity,
    :list,
    :minus_sign,
    :nan,
    :per_mille,
    :percent_sign,
    :plus_sign,
    :superscripting_exponent,
    :time_separator,
    :approximately_sign
  ]

  @type t :: %__MODULE__{
          decimal: String.t() | map(),
          group: String.t() | map(),
          exponential: String.t(),
          infinity: String.t(),
          list: String.t(),
          minus_sign: String.t(),
          nan: String.t(),
          per_mille: String.t(),
          percent_sign: String.t(),
          plus_sign: String.t(),
          superscripting_exponent: String.t(),
          time_separator: String.t(),
          approximately_sign: String.t()
        }

  @doc """
  Returns a map of `Localize.Number.Symbol.t()` structs of the
  number symbols for each number system of a locale.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, symbols_map}` where `symbols_map` is a map of
    `%{system_name => Localize.Number.Symbol.t()}`.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> {:ok, symbols} = Localize.Number.Symbol.number_symbols_for(:en)
      iex> symbols[:latn].decimal
      %{standard: "."}

  """
  @spec number_symbols_for(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, map()} | {:error, Exception.t()}
  def number_symbols_for(locale) do
    with {:ok, locale_id} <- cldr_locale_id_from(locale) do
      Localize.Locale.get(locale_id, [:number_symbols])
    end
  end

  @doc """
  Returns the number symbols for a specific locale and number system.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  * `number_system` is a number system name atom or string
    (e.g., `:latn`, `:arab`).

  ### Returns

  * `{:ok, Localize.Number.Symbol.t()}` with the symbols for the
    requested number system.

  * `{:error, exception}` if the locale data cannot be loaded or
    no symbols exist for the number system.

  When the requested number system has no symbol data of its own in
  the locale, the symbols of the locale's default number system are
  returned. This mirrors CLDR inheritance, where root aliases every
  other numbering system's symbols to `latn`, and is what makes a
  `-u-nu-` override such as `en-u-nu-thai` formattable.

  ### Examples

      iex> {:ok, symbols} = Localize.Number.Symbol.number_symbols_for(:en, :latn)
      iex> symbols.percent_sign
      "%"
      iex> symbols.group
      %{standard: ","}

  """
  @spec number_symbols_for(Localize.LanguageTag.t() | atom() | String.t(), atom() | String.t()) ::
          {:ok, t()} | {:error, Exception.t()}
  def number_symbols_for(locale, number_system) do
    system_name = to_system_atom(number_system)

    with {:ok, locale_id} <- cldr_locale_id_from(locale),
         {:ok, symbols} <- number_symbols_for(locale_id) do
      case Map.get(symbols, system_name) ||
             default_system_symbols(symbols, locale_id, system_name) do
        nil ->
          {:error,
           Localize.InvalidValueError.exception(
             value: number_system,
             expected: :number_system,
             allowed_values: Map.keys(symbols),
             context: locale_id
           )}

        symbol ->
          {:ok, symbol}
      end
    end
  end

  # CLDR inheritance: symbols for a numbering system the locale carries
  # no data for inherit from the locale's default numbering system —
  # root aliases them to `latn`. The fallback applies only to systems
  # in the CLDR inventory so an unknown system name still errors, and
  # the default is read from the locale data, not from any `-u-nu-`
  # override on the locale.
  defp default_system_symbols(symbols, locale_id, system_name) do
    with true <- Map.has_key?(Localize.Number.System.number_systems(), system_name),
         {:ok, %{default: default_system}} <-
           Localize.Number.System.number_systems_for(locale_id) do
      Map.get(symbols, default_system)
    else
      _unknown_system_or_error -> nil
    end
  end

  # ── Private helpers ──────────────────────────────────────────

  defp cldr_locale_id_from(locale), do: Localize.Locale.cldr_locale_id_from(locale)

  defp to_system_atom(system) when is_atom(system), do: system

  # Use `existing_atom/1` so attacker-supplied binary system names
  # can't grow the atom table. Known number systems are pre-atomised
  # at startup; unknown binaries return nil and the caller's
  # `Map.get(symbols, nil)` falls through to the existing error path.
  defp to_system_atom(system) when is_binary(system) do
    Localize.Utils.Helpers.existing_atom(system)
  end
end
