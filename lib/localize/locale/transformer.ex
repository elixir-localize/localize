defmodule Localize.Locale.Transformer do
  @moduledoc """
  Transforms raw CLDR locale data maps into pre-built Elixir structs.

  Called once at locale load time (before storing in `:persistent_term`)
  so that every subsequent access returns ready-to-use structs without
  per-call transformation overhead.

  The transformer handles three data sections:

  * `:number_symbols` — `%{system_atom => Localize.Number.Symbol.t()}`

  * `:number_formats` — `%{system_atom => Localize.Number.Format.t()}`

  * `:currencies` — `%{currency_code_atom => Localize.Currency.t()}`

  All other keys in the locale data map are passed through unchanged.

  """

  alias Localize.Currency
  alias Localize.Number.Format
  alias Localize.Number.Symbol

  @doc """
  Transforms raw locale data, converting maps to structs for
  number symbols, number formats, and currencies.

  ### Arguments

  * `locale_data` is the raw locale data map loaded from CLDR.

  ### Returns

  * The same map with `:number_symbols`, `:number_formats`, and
    `:currencies` values replaced by pre-built structs.

  """
  @spec transform(map()) :: map()
  def transform(locale_data) when is_map(locale_data) do
    locale_data
    |> transform_key(:number_symbols, &transform_number_symbols/1)
    |> transform_key(:number_formats, &transform_number_formats/1)
    |> transform_key(:currencies, &transform_currencies/1)
  end

  @doc """
  Transforms a raw number symbols map into a map of
  `Localize.Number.Symbol` structs keyed by system atom.

  ### Arguments

  * `raw` is a map of `%{system => symbol_data}` where keys
    are atoms or strings and values are maps of symbol fields.

  ### Returns

  * A map of `%{system_atom => Localize.Number.Symbol.t()}`.

  """
  @spec transform_number_symbols(map()) :: map()
  def transform_number_symbols(raw) when is_map(raw) do
    Map.new(raw, fn
      {system, nil} -> {to_atom(system), nil}
      {system, data} -> {to_atom(system), struct(Symbol, data)}
    end)
  end

  @doc """
  Transforms a raw number formats map into a map of
  `Localize.Number.Format` structs keyed by system atom.

  ### Arguments

  * `raw` is a map of `%{system => format_data}` where keys
    are atoms or strings and values are maps of format fields.

  ### Returns

  * A map of `%{system_atom => Localize.Number.Format.t()}`.

  """
  @spec transform_number_formats(map()) :: map()
  def transform_number_formats(raw) when is_map(raw) do
    Map.new(raw, fn {system, data} ->
      {to_atom(system), struct(Format, data)}
    end)
  end

  @doc """
  Transforms a raw currencies map into a map of
  `Localize.Currency` structs keyed by currency code atom.

  ### Arguments

  * `raw` is a map of `%{code => currency_data}` where keys
    are atoms or strings and values are maps of currency fields.

  ### Returns

  * A map of `%{currency_code_atom => Localize.Currency.t()}`.

  """
  @spec transform_currencies(map()) :: map()
  def transform_currencies(raw) when is_map(raw) do
    Map.new(raw, fn {code, data} ->
      code_atom = to_atom(code)

      currency =
        struct(Currency, %{
          data
          | code: code_atom,
            count: atomize_count(data[:count] || data["count"])
        })

      {code_atom, currency}
    end)
  end

  # ── Private helpers ──────────────────────────────────────────

  defp transform_key(locale_data, key, transformer) do
    case Map.get(locale_data, key) do
      nil -> locale_data
      raw -> Map.put(locale_data, key, transformer.(raw))
    end
  end

  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_atom(value)

  defp atomize_count(nil), do: nil

  defp atomize_count(count) when is_map(count) do
    Map.new(count, fn
      {key, value} when is_atom(key) -> {key, value}
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
    end)
  end
end
