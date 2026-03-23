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

  """
  @spec number_symbols_for(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, map()} | {:error, Exception.t()}
  def number_symbols_for(locale) do
    locale_id = to_locale_id(locale)
    Localize.Locale.get(locale_id, [:number_symbols])
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

  """
  @spec number_symbols_for(Localize.LanguageTag.t() | atom() | String.t(), atom() | String.t()) ::
          {:ok, t()} | {:error, Exception.t()}
  def number_symbols_for(locale, number_system) do
    system_name = to_system_atom(number_system)

    with {:ok, symbols} <- number_symbols_for(locale) do
      case Map.get(symbols, system_name) do
        nil ->
          locale_id = to_locale_id(locale)

          {:error,
           Localize.InvalidValueError.exception(
             value: number_system,
             expected: "a valid number system for locale #{inspect(locale_id)}",
             context: "Localize.Number.Symbol.number_symbols_for/2"
           )}

        symbol ->
          {:ok, symbol}
      end
    end
  end

  # ── Private helpers ──────────────────────────────────────────

  defp to_locale_id(locale), do: Localize.Locale.to_locale_id(locale)

  defp to_system_atom(system) when is_atom(system), do: system
  defp to_system_atom(system) when is_binary(system), do: String.to_atom(system)

end
