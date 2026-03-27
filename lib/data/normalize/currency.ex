defmodule Localize.Data.Normalize.Currency do
  @moduledoc false

  alias Localize.Utils.Map, as: LMap

  def normalize(content, _locale) do
    currency_data = get_currency_data()["fractions"]
    default = currency_data["DEFAULT"]
    iso_digits = get_iso_currency_digits()
    currencies = get_in(content, ["numbers", "currencies"])

    currencies =
      Enum.map(currencies, fn {code, currency} ->
        code = String.upcase(to_string(code))

        currency_map = %{
          code: code,
          name: currency["display_name"],
          symbol: currency["symbol"],
          narrow_symbol: currency["symbol_alt_narrow"],
          tender: String.to_atom(currency_data[code]["_tender"] || "true"),
          digits: String.to_integer(currency_data[code]["_digits"] || default["_digits"]),
          rounding: String.to_integer(currency_data[code]["_rounding"] || default["_rounding"]),
          cash_digits:
            String.to_integer(
              currency_data[code]["_cash_digits"] || currency_data[code]["_digits"] ||
                default["_digits"]
            ),
          cash_rounding:
            String.to_integer(
              currency_data[code]["_cash_rounding"] || currency_data[code]["_rounding"] ||
                default["_rounding"]
            ),
          count: currency_counts(currency),
          iso_digits: Map.get(iso_digits, String.to_atom(code)),
          decimal_separator: currency["decimal"],
          grouping_separator: currency["group"]
        }

        {code, currency_map}
      end)
      |> Map.new()
      |> LMap.atomize_keys(level: 1)

    Map.put(content, "currencies", currencies)
  end

  @count_types [:zero, :one, :two, :few, :many, :other]

  def currency_counts(currency) do
    Enum.reduce(@count_types, %{}, fn category, counts ->
      if display_count = currency["display_name_count_#{category}"] do
        Map.put(counts, category, display_count)
      else
        counts
      end
    end)
  end

  defp get_currency_data do
    Localize.Data.read_json("currencyData.json")
    |> LMap.underscore_keys()
    |> get_in(["supplemental", "currency_data"])
    |> upcase_currency_codes()
  end

  defp upcase_currency_codes(currencies) do
    fractions =
      currencies["fractions"]
      |> Enum.map(fn {k, v} -> {String.upcase(k), v} end)
      |> Map.new()

    Map.put(currencies, "fractions", fractions)
  end

  defp get_iso_currency_digits do
    import SweetXml

    xml_path = Path.join(Localize.Data.external_sources_dir(), "iso_currencies.xml")

    if File.exists?(xml_path) do
      xml_path
      |> File.read!()
      |> xpath(~x"//CcyNtry"l,
        code: ~x"./Ccy/text()"os,
        digits: ~x"./CcyMnrUnts/text()"os
      )
      |> Enum.reject(fn %{code: code} -> code == nil or code == "" end)
      |> Enum.map(fn %{code: code, digits: digits} ->
        digit_value =
          case Integer.parse(to_string(digits)) do
            {n, _} -> n
            :error -> 0
          end

        {String.to_atom(to_string(code)), digit_value}
      end)
      |> Enum.uniq_by(fn {code, _} -> code end)
      |> Map.new()
    else
      %{}
    end
  end
end
