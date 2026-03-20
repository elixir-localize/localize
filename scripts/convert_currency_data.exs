# Script to convert currency JSON data to ETF format
# Run with: mix run scripts/convert_currency_data.exs

cldr_priv = Path.join(["..", "cldr", "priv", "cldr"])
out_dir = Path.join(["priv", "cldr"])

# 1. Convert currencies.json (list of currency code strings -> sorted list of atoms)
currencies_json = File.read!(Path.join(cldr_priv, "currencies.json"))
currency_codes = currencies_json |> :json.decode() |> Enum.map(&String.to_atom/1) |> Enum.sort()

etf_path = Path.join(out_dir, "currency_codes.etf")
File.write!(etf_path, :erlang.term_to_binary(currency_codes))
IO.puts("Wrote #{length(currency_codes)} currency codes to #{etf_path}")

# 2. Convert territory_currencies.json
# Source format: %{"US" => [%{"USD" => %{"from" => "1792-01-01"}}, ...]}
# Target format: %{US: %{USD: %{from: ~D[1792-01-01], to: nil}, USN: %{tender: false}, ...}}
territory_json = File.read!(Path.join(cldr_priv, "territory_currencies.json"))
territory_data = :json.decode(territory_json)

parse_date = fn
  nil -> nil
  date_string when is_binary(date_string) -> Date.from_iso8601!(date_string)
end

territory_currencies =
  territory_data
  |> Enum.map(fn {territory_code, currency_list} ->
    currencies =
      currency_list
      |> Enum.reduce(%{}, fn currency_entry, acc ->
        [{code_string, info}] = Map.to_list(currency_entry)
        code_atom = String.to_atom(code_string)

        date_info =
          info
          |> Enum.reject(fn {k, _v} -> String.starts_with?(k, "_") end)
          |> Enum.map(fn
            {"from", v} -> {:from, parse_date.(v)}
            {"to", v} -> {:to, parse_date.(v)}
            {"tender", "false"} -> {:tender, false}
            {"tender", "true"} -> {:tender, true}
          end)
          |> Map.new()

        Map.put(acc, code_atom, date_info)
      end)

    {String.to_atom(territory_code), currencies}
  end)
  |> Map.new()

etf_path = Path.join(out_dir, "territory_currencies.etf")
File.write!(etf_path, :erlang.term_to_binary(territory_currencies))
IO.puts("Wrote #{map_size(territory_currencies)} territories to #{etf_path}")

# Verify
sample = Map.get(territory_currencies, :US)
IO.inspect(sample, label: "US currencies")
