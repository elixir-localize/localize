defmodule Localize.DateTime.Timezone do
  @moduledoc """
  Provides timezone data access and timezone formatting for CLDR
  date/time format symbols.

  This module combines CLDR short zone code lookups (mapping between
  BCP 47 timezone identifiers and IANA timezone names) with the format
  symbol handlers for `z`, `Z`, `O`, `v`, `V`, `X`, and `x`.

  """

  alias Localize.SupplementalData
  alias Localize.DateTime.Timezone.Builder

  @timezones SupplementalData.timezones()
  @timezones_by_territory Builder.timezones_by_territory(@timezones)
  @territories_by_timezone Builder.territories_by_timezone(@timezones_by_territory)

  # ── Timezone Data Access ─────────────────────────────────────

  @doc """
  Returns a mapping of CLDR short zone codes to
  IANA timezone names.

  Each key is a BCP 47 short timezone identifier string and each
  value is a map with `:aliases`, `:preferred`, and `:territory`
  keys.

  ### Returns

  * A map of `%{String.t() => map()}`.

  ### Examples

      iex> timezones = Localize.DateTime.Timezone.timezones()
      iex> Map.get(timezones, "ausyd")
      %{preferred: nil, aliases: ["Australia/Sydney", "Australia/ACT", "Australia/Canberra", "Australia/NSW"], territory: :AU}

  """
  @spec timezones() :: %{String.t() => map()}
  def timezones, do: @timezones

  @doc """
  Returns a mapping of territories to their known IANA
  timezone names.

  ### Returns

  * A map where each key is a territory atom and each value is a
    list of timezone maps including `:short_zone`, `:aliases`,
    `:preferred`, and `:territory` keys.

  ### Examples

      iex> {:ok, zones} = Localize.DateTime.Timezone.timezones_for_territory(:AU)
      iex> Enum.any?(zones, & &1.short_zone == "ausyd")
      true

  """
  @spec timezones_by_territory() :: %{
          required(atom()) => [
            %{
              short_zone: String.t(),
              territory: atom(),
              aliases: [term(), ...],
              preferred: nil | String.t()
            },
            ...
          ]
        }
  def timezones_by_territory, do: @timezones_by_territory

  @doc """
  Returns a mapping of IANA time zone names to their
  known territory.

  A time zone can only belong to one territory in CLDR.

  ### Returns

  * A map where each key is an IANA timezone string and each
    value is a territory atom.

  ### Examples

      iex> territories = Localize.DateTime.Timezone.territories_by_timezone()
      iex> Map.get(territories, "Australia/Sydney")
      :AU

  """
  @spec territories_by_timezone() :: %{String.t() => atom()}
  def territories_by_timezone, do: @territories_by_timezone

  @doc """
  Returns a list of timezone maps for a given territory.

  ### Arguments

  * `territory` is a territory atom like `:US` or `:AU`.

  ### Returns

  * `{:ok, list}` where list is timezone maps for the territory.

  * `{:error, exception}` if the territory has no known timezones.

  ### Examples

      iex> {:ok, zones} = Localize.DateTime.Timezone.timezones_for_territory(:US)
      iex> is_list(zones)
      true

  """
  @spec timezones_for_territory(atom()) :: {:ok, [map()]} | {:error, Exception.t()}
  def timezones_for_territory(territory) do
    case Map.fetch(@timezones_by_territory, territory) do
      {:ok, _} = result -> result
      :error -> {:error, Localize.UnknownTerritoryError.exception(territory: territory)}
    end
  end

  @doc """
  Returns the count of timezones for a given territory.

  ### Arguments

  * `territory` is a territory atom like `:US` or `:AU`.

  ### Returns

  * `{:ok, count}` where count is the number of timezones.

  * `{:error, exception}` if the territory has no known timezones.

  ### Examples

      iex> {:ok, count} = Localize.DateTime.Timezone.timezone_count_for_territory(:AU)
      iex> count > 0
      true

  """
  @spec timezone_count_for_territory(atom()) :: {:ok, non_neg_integer()} | {:error, Exception.t()}
  def timezone_count_for_territory(territory) do
    with {:ok, zones} <- timezones_for_territory(territory) do
      {:ok, Enum.count(zones)}
    end
  end

  @doc """
  Returns a timezone map for a given CLDR short zone code,
  or a default value.

  ### Arguments

  * `short_zone` is a CLDR short timezone code string.

  * `default` is the value to return if the short zone is not
    found. Defaults to `nil`.

  ### Returns

  * A map with `:aliases`, `:preferred`, and `:territory` keys,
    or the default value.

  ### Examples

      iex> Localize.DateTime.Timezone.get_short_zone("ausyd")
      %{
        preferred: nil,
        aliases: ["Australia/Sydney", "Australia/ACT", "Australia/Canberra", "Australia/NSW"],
        territory: :AU
      }

      iex> Localize.DateTime.Timezone.get_short_zone("nope")
      nil

  """
  @spec get_short_zone(String.t(), term()) :: map() | term()
  def get_short_zone(short_zone, default \\ nil) do
    Map.get(@timezones, short_zone, default)
  end

  @doc """
  Returns `{:ok, map}` for a given CLDR short zone code,
  or `:error` if no such short code exists.

  ### Arguments

  * `short_zone` is a CLDR short timezone code string.

  ### Returns

  * `{:ok, map}` where map has `:aliases`, `:preferred`, and
    `:territory` keys.

  * `{:error, exception}` if the short zone code is not found.

  ### Examples

      iex> Localize.DateTime.Timezone.fetch_short_zone("ausyd")
      {
        :ok,
        %{
          preferred: nil,
          aliases: ["Australia/Sydney", "Australia/ACT", "Australia/Canberra", "Australia/NSW"],
          territory: :AU
        }
      }

      iex> match?({:error, _}, Localize.DateTime.Timezone.fetch_short_zone("nope"))
      true

  """
  @spec fetch_short_zone(String.t()) :: {:ok, map()} | {:error, Exception.t()}
  def fetch_short_zone(short_zone) do
    case Map.fetch(@timezones, short_zone) do
      {:ok, _} = result -> result
      :error -> {:error, Localize.UnknownTimezoneError.exception(timezone: short_zone)}
    end
  end

  @doc """
  Validates a CLDR short zone code and returns the canonical
  IANA timezone name.

  ### Arguments

  * `short_zone` is a CLDR short timezone code string.

  ### Returns

  * `{:ok, iana_name}` where `iana_name` is the canonical IANA
    timezone name string.

  * `{:error, exception}` if the short zone code is not valid.

  ### Examples

      iex> Localize.DateTime.Timezone.validate_short_zone("ausyd")
      {:ok, "Australia/Sydney"}

      iex> Localize.DateTime.Timezone.validate_short_zone("nope")
      {:error, %Localize.UnknownTimezoneError{timezone: "nope"}}

  """
  @spec validate_short_zone(String.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def validate_short_zone(short_zone) do
    case fetch_short_zone(short_zone) do
      {:ok, %{aliases: [first_zone | _others]}} ->
        {:ok, first_zone}

      {:error, _} = error ->
        error
    end
  end

  # ── Timezone Formatting ──────────────────────────────────────

  # Provides timezone formatting for CLDR date/time format symbols.
  #
  # Supports format symbols:
  #   z (1-4) - Specific non-location format (e.g., "EST", "Eastern Standard Time")
  #   Z (1-5) - ISO8601 basic/extended format (e.g., "+0500", "Z", "+05:00")
  #   O (1,4) - Localized GMT format (e.g., "GMT+1", "GMT+01:00")
  #   v (1,4) - Generic non-location format (e.g., "ET", "Eastern Time")
  #   V (1-4) - Zone ID and location formats
  #   X (1-5) - ISO8601 with Z for zero offset
  #   x (1-5) - ISO8601 without Z for zero offset

  # Mapping from IANA timezone to CLDR metazone
  # This is a simplified mapping covering the most common zones.
  # A full implementation would load this from CLDR supplemental data.
  @zone_to_metazone %{
    "America/New_York" => :america_eastern,
    "America/Chicago" => :america_central,
    "America/Denver" => :america_mountain,
    "America/Los_Angeles" => :america_pacific,
    "America/Anchorage" => :alaska,
    "Pacific/Honolulu" => :hawaii_aleutian,
    "Europe/London" => :gmt,
    "Europe/Paris" => :europe_central,
    "Europe/Berlin" => :europe_central,
    "Europe/Moscow" => :moscow,
    "Asia/Tokyo" => :japan,
    "Asia/Shanghai" => :china,
    "Asia/Kolkata" => :india,
    "Asia/Dubai" => :gulf,
    "Australia/Sydney" => :australia_eastern,
    "Australia/Melbourne" => :australia_eastern,
    "Australia/Perth" => :australia_western,
    "Etc/UTC" => :gmt,
    "Etc/GMT" => :gmt,
    "UTC" => :gmt
  }

  # # non_location_format/3
  #
  # Returns the specific or generic non-location timezone name.
  #
  # ### Arguments
  #
  # * `datetime` is a map with `:time_zone`, `:utc_offset`, `:std_offset` keys.
  #
  # * `locale_id` is a locale identifier atom.
  #
  # * `options` is a keyword list with `:format` (`:short` or `:long`)
  #   and `:type` (`:specific`, `:generic`, or `:standard`).
  #
  # ### Returns
  #
  # * `{:ok, timezone_name}` or `{:ok, gmt_offset_string}` as fallback.
  #
  @spec non_location_format(map(), atom(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def non_location_format(datetime, locale_id, options \\ []) do
    time_zone = Map.get(datetime, :time_zone)
    format = Keyword.get(options, :format, :long)
    type = Keyword.get(options, :type, :specific)

    with {:ok, tz_data} <- Localize.Locale.get(locale_id, [:dates, :time_zone_names]) do
      # Try metazone lookup first
      metazone_key = Map.get(@zone_to_metazone, time_zone)

      result =
        if metazone_key do
          metazone_data = tz_data[:metazone][metazone_key]

          if metazone_data do
            format_key = if format == :short, do: :short, else: :long
            type_key = resolve_type(type, datetime)
            get_in(metazone_data, [format_key, type_key])
          end
        end

      if result do
        {:ok, result}
      else
        # Fallback to GMT format
        gmt_format(datetime, locale_id, format: format)
      end
    end
  end

  # # gmt_format/3
  #
  # Returns the localized GMT offset format.
  #
  # Uses the locale's `gmt_format` pattern (e.g., `["GMT", 0]`)
  # and `hour_format` pattern.
  #
  # ### Arguments
  #
  # * `datetime` is a map with `:utc_offset` and optionally `:std_offset`.
  #
  # * `locale_id` is a locale identifier atom.
  #
  # * `options` is a keyword list with `:format` (`:short` or `:long`).
  #
  # ### Returns
  #
  # * `{:ok, formatted_string}` (e.g., "GMT+01:00" or "GMT").
  #
  @spec gmt_format(map(), atom(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def gmt_format(datetime, locale_id, options \\ []) do
    offset = total_offset(datetime)

    with {:ok, tz_data} <- Localize.Locale.get(locale_id, [:dates, :time_zone_names]) do
      gmt_zero = tz_data[:gmt_zero_format] || "GMT"
      gmt_pattern = tz_data[:gmt_format] || ["GMT", 0]
      hour_format_str = tz_data[:hour_format] || "+HH:mm;-HH:mm"

      zero_format = Keyword.get(options, :zero_format, :gmt_zero)

      if offset == 0 and zero_format == :gmt_zero do
        {:ok, gmt_zero}
      else
        format = Keyword.get(options, :format, :long)
        formatted_offset = format_hour_offset(offset, hour_format_str, format)
        result = Localize.Substitution.substitute(formatted_offset, gmt_pattern) |> Enum.join()
        {:ok, result}
      end
    end
  end

  # # iso_format/2
  #
  # Returns the ISO 8601 timezone offset format.
  #
  # ### Arguments
  #
  # * `datetime` is a map with `:utc_offset` and optionally `:std_offset`.
  #
  # * `options` is a keyword list with:
  #   * `:format` — `:short`, `:long`, or `:full`
  #   * `:type` — `:basic` or `:extended`
  #   * `:z_for_zero` — boolean, whether to use "Z" for zero offset
  #
  # ### Returns
  #
  # * `{:ok, formatted_string}` (e.g., "+0500", "Z", "+05:00").
  #
  @spec iso_format(map(), Keyword.t()) :: {:ok, String.t()}
  def iso_format(datetime, options \\ []) do
    offset = total_offset(datetime)
    format = Keyword.get(options, :format, :long)
    type = Keyword.get(options, :type, :basic)
    z_for_zero = Keyword.get(options, :z_for_zero, true)

    if offset == 0 and z_for_zero do
      {:ok, "Z"}
    else
      {:ok, format_iso_offset(offset, format, type)}
    end
  end

  # ── Offset helpers ─────────────────────────────────────────

  defp total_offset(%{utc_offset: utc, std_offset: std})
       when is_integer(utc) and is_integer(std) do
    utc + std
  end

  defp total_offset(%{utc_offset: utc}) when is_integer(utc), do: utc
  defp total_offset(_), do: 0

  defp resolve_type(:generic, _datetime), do: :generic
  defp resolve_type(:standard, _datetime), do: :standard
  defp resolve_type(:daylight, _datetime), do: :daylight

  defp resolve_type(:specific, %{std_offset: std}) when is_integer(std) and std > 0 do
    :daylight
  end

  defp resolve_type(:specific, _datetime), do: :standard

  # Format offset using CLDR hour_format pattern ("+HH:mm;-HH:mm")
  defp format_hour_offset(offset, hour_format_str, format) do
    {positive_format, negative_format} = parse_hour_format(hour_format_str)

    sign_format = if offset >= 0, do: positive_format, else: negative_format
    abs_offset = abs(offset)
    hours = div(abs_offset, 3600)
    minutes = div(rem(abs_offset, 3600), 60)

    result =
      sign_format
      |> String.replace("HH", pad(hours, 2))
      |> String.replace("H", Integer.to_string(hours))
      |> String.replace("mm", pad(minutes, 2))

    # For short format, remove minutes separator and part when minutes == 0,
    # and strip leading zero from hours (e.g., "+00:00" → "+0", "+05:00" → "+5")
    if format == :short and minutes == 0 do
      Regex.replace(~r/[:.]00$/, result, "")
      |> String.replace(~r/(?<=[\+\-])0(?=\d)/, "")
    else
      result
    end
  end

  defp parse_hour_format(format_string) do
    case String.split(format_string, ";") do
      [positive, negative] -> {positive, negative}
      [combined] -> {combined, "-" <> String.trim_leading(combined, "+")}
    end
  end

  defp format_iso_offset(offset, format, type) do
    sign = if offset >= 0, do: "+", else: "-"
    abs_offset = abs(offset)
    hours = div(abs_offset, 3600)
    minutes = div(rem(abs_offset, 3600), 60)
    seconds = rem(abs_offset, 60)
    separator = if type == :extended, do: ":", else: ""

    case format do
      :short ->
        if minutes == 0 do
          "#{sign}#{pad(hours, 2)}"
        else
          "#{sign}#{pad(hours, 2)}#{separator}#{pad(minutes, 2)}"
        end

      :long ->
        "#{sign}#{pad(hours, 2)}#{separator}#{pad(minutes, 2)}"

      :full ->
        base = "#{sign}#{pad(hours, 2)}#{separator}#{pad(minutes, 2)}"

        if seconds > 0 do
          "#{base}#{separator}#{pad(seconds, 2)}"
        else
          base
        end
    end
  end

  defp pad(integer, n) when is_integer(integer) do
    str = Integer.to_string(integer)
    padding = n - String.length(str)
    if padding > 0, do: String.duplicate("0", padding) <> str, else: str
  end
end
