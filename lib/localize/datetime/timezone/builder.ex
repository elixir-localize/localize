defmodule Localize.DateTime.Timezone.Builder do
  @moduledoc false

  # Compile-time helpers for `Localize.DateTime.Timezone`.
  #
  # Lives outside `Localize.SupplementalData` so SupplementalData has
  # no compile- or run-time dependency on `Localize.Validity.*` (which
  # would form a compile-connected cycle).

  # Builds a map of validated territory atoms to lists of timezone
  # zone maps from the raw CLDR timezone data. Each zone map has the
  # original timezone fields plus a `:short_zone` key holding the
  # BCP 47 short zone code. Territories that fail validation or are
  # `nil` are excluded.
  @doc false
  @spec timezones_by_territory(%{String.t() => map()}) :: %{atom() => [map()]}
  def timezones_by_territory(timezones) do
    timezones
    |> Enum.group_by(
      fn {_key, value} -> value.territory end,
      fn {key, value} -> Map.put(value, :short_zone, key) end
    )
    |> Enum.map(fn
      {nil, _} ->
        nil

      {territory, zones} ->
        case Localize.Validity.Territory.validate(territory) do
          {:ok, validated_territory, _status} ->
            {validated_territory, List.flatten(zones)}

          {:error, _} ->
            nil
        end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  # Inverts `timezones_by_territory/1` so that each timezone alias
  # maps to its territory atom. The synthetic `:UT` territory is
  # excluded.
  @doc false
  @spec territories_by_timezone(%{atom() => [map()]}) :: %{String.t() => atom()}
  def territories_by_timezone(timezones_by_territory) do
    timezones_by_territory
    |> Enum.flat_map(fn {territory, zones} -> territory_zone_aliases(territory, zones) end)
    |> Enum.reject(fn {_zone, territory} -> territory == :UT end)
    |> Map.new()
  end

  # Pairs each alias of each zone with its territory.
  defp territory_zone_aliases(territory, zones) do
    Enum.flat_map(zones, fn zone ->
      Enum.map(zone.aliases, fn zone_alias -> {zone_alias, territory} end)
    end)
  end
end
