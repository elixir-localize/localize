defmodule Localize.DateTime.Timezone do
  @moduledoc false

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
    "America/New_York" => "america_eastern",
    "America/Chicago" => "america_central",
    "America/Denver" => "america_mountain",
    "America/Los_Angeles" => "america_pacific",
    "America/Anchorage" => "alaska",
    "Pacific/Honolulu" => "hawaii_aleutian",
    "Europe/London" => "gmt",
    "Europe/Paris" => "europe_central",
    "Europe/Berlin" => "europe_central",
    "Europe/Moscow" => "moscow",
    "Asia/Tokyo" => "japan",
    "Asia/Shanghai" => "china",
    "Asia/Kolkata" => "india",
    "Asia/Dubai" => "gulf",
    "Australia/Sydney" => "australia_eastern",
    "Australia/Melbourne" => "australia_eastern",
    "Australia/Perth" => "australia_western",
    "Etc/UTC" => "gmt",
    "Etc/GMT" => "gmt",
    "UTC" => "gmt"
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

      if offset == 0 do
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

    # For short format, remove ":00" minutes part when minutes == 0
    if format == :short and minutes == 0 do
      result
      |> String.replace(":00", "")
      |> String.replace("00", "", global: false)
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
