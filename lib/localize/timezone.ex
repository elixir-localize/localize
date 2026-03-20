defmodule Localize.Timezone do
  @moduledoc """
  Functions to map between the CLDR short time zone code and the
  IANA timezone names.

  The Unicode [locale](https://unicode.org/reports/tr35/#Locale)
  [extension U](https://unicode.org/reports/tr35/#u_Extension)
  allows the specification of the time zone requested for the provided locale.

  These short timezone codes never change even if the IANA names change
  over time. Therefore these short codes are always stable between CLDR
  releases.

  """

  alias Localize.Locale.Provider
  alias Localize.Validity.Territory

  @timezones Provider.timezones()

  @timezones_by_territory @timezones
                          |> Enum.group_by(
                            fn {_key, value} -> value.territory end,
                            fn {key, value} -> Map.put(value, :short_zone, key) end
                          )
                          |> Enum.map(fn
                            {nil, _} ->
                              nil

                            {territory, zones} ->
                              case Territory.validate(territory) do
                                {:ok, validated_territory, _status} ->
                                  {validated_territory, List.flatten(zones)}

                                {:error, _} ->
                                  nil
                              end
                          end)
                          |> Enum.reject(&is_nil/1)
                          |> Map.new()

  @territories_by_timezone @timezones_by_territory
                           |> Enum.map(fn {territory, zones} ->
                             Enum.map(zones, fn zone ->
                               Enum.map(zone.aliases, fn zone_alias ->
                                 {zone_alias, territory}
                               end)
                             end)
                           end)
                           |> List.flatten()
                           |> Enum.reject(fn {_zone, territory} -> territory == :UT end)
                           |> Map.new()

  @doc """
  Returns a mapping of CLDR short zone codes to
  IANA timezone names.

  Each key is a BCP 47 short timezone identifier string and each
  value is a map with `:aliases`, `:preferred`, and `:territory`
  keys.

  ### Returns

  * A map of `%{String.t() => map()}`.

  ### Examples

      iex> timezones = Localize.Timezone.timezones()
      iex> Map.get(timezones, "ausyd")
      %{preferred: nil, aliases: ["Australia/Sydney", "Australia/ACT", "Australia/Canberra", "Australia/NSW"], territory: :AU}

  """
  @spec timezones() :: %{String.t() => map()}
  def timezones do
    @timezones
  end

  @doc """
  Returns a mapping of territories to their known IANA
  timezone names.

  ### Returns

  * A map where each key is a territory atom and each value is a
    list of timezone maps including `:short_zone`, `:aliases`,
    `:preferred`, and `:territory` keys.

  ### Examples

      iex> {:ok, zones} = Localize.Timezone.timezones_for_territory(:AU)
      iex> Enum.any?(zones, & &1.short_zone == "ausyd")
      true

  """
  @spec timezones_by_territory() :: %{atom() => [map()]}
  def timezones_by_territory do
    @timezones_by_territory
  end

  @doc """
  Returns a mapping of IANA time zone names to their
  known territory.

  A time zone can only belong to one territory in CLDR.

  ### Returns

  * A map where each key is an IANA timezone string and each
    value is a territory atom.

  ### Examples

      iex> territories = Localize.Timezone.territories_by_timezone()
      iex> Map.get(territories, "Australia/Sydney")
      :AU

  """
  @spec territories_by_timezone() :: %{String.t() => atom()}
  def territories_by_timezone do
    @territories_by_timezone
  end

  @doc """
  Returns a list of timezone maps for a given territory.

  ### Arguments

  * `territory` is a territory atom like `:US` or `:AU`.

  ### Returns

  * `{:ok, list}` where list is timezone maps for the territory.

  * `:error` if the territory has no known timezones.

  ### Examples

      iex> {:ok, zones} = Localize.Timezone.timezones_for_territory(:US)
      iex> is_list(zones)
      true

  """
  @spec timezones_for_territory(atom()) :: {:ok, [map()]} | :error
  def timezones_for_territory(territory) do
    timezones_by_territory()
    |> Map.fetch(territory)
  end

  @doc """
  Returns the count of timezones for a given territory.

  ### Arguments

  * `territory` is a territory atom like `:US` or `:AU`.

  ### Returns

  * An integer count of timezones, or `:error` if the territory
    has no known timezones.

  ### Examples

      iex> Localize.Timezone.timezone_count_for_territory(:AU) > 0
      true

  """
  @spec timezone_count_for_territory(atom()) :: non_neg_integer() | :error
  def timezone_count_for_territory(territory) do
    with {:ok, zones} <- timezones_for_territory(territory) do
      Enum.count(zones)
    end
  end

  @doc """
  Returns a timezone map for a given CLDR short zone code,
  or a default value.

  The first timezone name in the `:aliases` list is
  the canonical timezone name.

  ### Arguments

  * `short_zone` is a CLDR short timezone code string.

  * `default` is the value to return if the short zone is not
    found. Defaults to `nil`.

  ### Returns

  * A map with `:aliases`, `:preferred`, and `:territory` keys,
    or the default value.

  ### Examples

      iex> Localize.Timezone.get_short_zone("ausyd")
      %{
        preferred: nil,
        aliases: ["Australia/Sydney", "Australia/ACT", "Australia/Canberra", "Australia/NSW"],
        territory: :AU
      }

      iex> Localize.Timezone.get_short_zone("nope")
      nil

  """
  @spec get_short_zone(String.t(), term()) :: map() | term()
  def get_short_zone(short_zone, default \\ nil) do
    Map.get(timezones(), short_zone, default)
  end

  @doc """
  Returns `{:ok, map}` for a given CLDR short zone code,
  or `:error` if no such short code exists.

  ### Arguments

  * `short_zone` is a CLDR short timezone code string.

  ### Returns

  * `{:ok, map}` where map has `:aliases`, `:preferred`, and
    `:territory` keys.

  * `:error` if the short zone code is not found.

  ### Examples

      iex> Localize.Timezone.fetch_short_zone("ausyd")
      {
        :ok,
        %{
          preferred: nil,
          aliases: ["Australia/Sydney", "Australia/ACT", "Australia/Canberra", "Australia/NSW"],
          territory: :AU
        }
      }

      iex> Localize.Timezone.fetch_short_zone("nope")
      :error

  """
  @spec fetch_short_zone(String.t()) :: {:ok, map()} | :error
  def fetch_short_zone(short_zone) do
    Map.fetch(timezones(), short_zone)
  end

  @doc """
  Validates a CLDR short zone code and returns the canonical
  IANA timezone name.

  ### Arguments

  * `short_zone` is a CLDR short timezone code string.

  ### Returns

  * `{:ok, iana_name}` where `iana_name` is the canonical IANA
    timezone name string.

  * `{:error, "Etc/Unknown"}` if the short zone code is not valid.

  ### Examples

      iex> Localize.Timezone.validate_short_zone("ausyd")
      {:ok, "Australia/Sydney"}

      iex> Localize.Timezone.validate_short_zone("nope")
      {:error, %Localize.UnknownTimezoneError{timezone: "nope"}}

  """
  @spec validate_short_zone(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_short_zone(short_zone) do
    case fetch_short_zone(short_zone) do
      {:ok, %{aliases: [first_zone | _others]}} ->
        {:ok, first_zone}

      :error ->
        {:error, Localize.UnknownTimezoneError.exception(timezone: short_zone)}
    end
  end
end
