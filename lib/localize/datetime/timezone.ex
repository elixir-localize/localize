defmodule Localize.DateTime.Timezone do
  @moduledoc """
  Provides timezone data access and timezone formatting for CLDR
  date/time format symbols.

  This module combines CLDR short zone code lookups (mapping between
  BCP 47 timezone identifiers and IANA timezone names) with the format
  symbol handlers for `z`, `Z`, `O`, `v`, `V`, `X`, and `x`.

  """

  alias Localize.DateTime.Timezone.Builder
  alias Localize.SupplementalData

  # The timezone and metazone data is embedded at compile time, so an
  # ETF regeneration must trigger recompilation of this module.
  @external_resource Application.app_dir(
                       :localize,
                       "priv/localize/supplemental_data/timezones.etf"
                     )
  @external_resource Application.app_dir(
                       :localize,
                       "priv/localize/supplemental_data/metazones.etf"
                     )
  @external_resource Application.app_dir(
                       :localize,
                       "priv/localize/supplemental_data/primary_zones.etf"
                     )

  @timezones SupplementalData.timezones()
  @timezones_by_territory Builder.timezones_by_territory(@timezones)
  @territories_by_timezone Builder.territories_by_timezone(@timezones_by_territory)

  # CLDR removed `gmtZeroFormat` from the spec: a known offset is always
  # spelled out, and `gmtUnknownFormat` covers the only other case. These
  # are the root defaults, used when a locale ships no pattern of its own.
  @default_gmt_format ["GMT", 0]
  @default_hour_format "+HH:mm;-HH:mm"
  @default_gmt_unknown_format "GMT+?"

  @primary_zones SupplementalData.primary_zones()

  @metazone_data SupplementalData.metazones()
  @metazone_mapzones @metazone_data.mapzones
  @metazone_info @metazone_data.metazone_info

  # CLDR metazone data keys zones by their canonical IANA name; the
  # first alias of a BCP 47 timezone entry is that canonical name,
  # so map every alias (including the canonical name itself) to it.
  @zone_canonical_names for {_bcp47, %{aliases: aliases}} <- @timezones,
                            is_list(aliases) and aliases != [],
                            canonical = hd(aliases),
                            alias_name <- aliases,
                            into: %{},
                            do: {alias_name, canonical}

  # The reverse of the BCP 47 timezone table: every IANA alias mapped to
  # the short identifier that owns it, which is what the `V` symbol emits.
  @short_zone_ids for {bcp47, %{aliases: aliases}} <- @timezones,
                      is_list(aliases),
                      alias_name <- aliases,
                      into: %{},
                      do: {alias_name, bcp47}

  # TR35: where the short identifier is unavailable, the special short
  # timezone ID `unk` (Unknown Zone) is used.
  @unknown_short_zone_id "unk"

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
  Returns the canonical IANA time zone names known to CLDR.

  The canonical name is the first alias of each BCP 47 short zone in the CLDR timezone data; short zones with no IANA mapping are omitted. This is the inventory backing ECMA-402's `Intl.supportedValuesOf("timeZone")`.

  ### Returns

  * A sorted list of IANA time zone name strings.

  ### Examples

      iex> zones = Localize.DateTime.Timezone.known_timezones()
      iex> "Australia/Sydney" in zones and "America/New_York" in zones
      true

      iex> Localize.DateTime.Timezone.known_timezones() |> hd()
      "Africa/Abidjan"

  """
  @spec known_timezones() :: [String.t(), ...]
  def known_timezones do
    @timezones
    |> Map.values()
    |> Enum.flat_map(fn
      %{aliases: [canonical | _]} -> [canonical]
      _no_aliases -> []
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

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
  Returns the BCP 47 short timezone identifier for an IANA
  timezone name.

  This is the value of the `V` format symbol in TR35. Every alias
  of a zone resolves to the same short identifier, so both
  `"America/New_York"` and its alias `"US/Eastern"` return `"usnyc"`.

  ### Arguments

  * `iana_id` is an IANA timezone name such as `"America/New_York"`.

  ### Returns

  * The BCP 47 short timezone identifier as a string.

  * `"unk"`, the Unknown Zone identifier, if `iana_id` is not a known
    timezone. TR35 specifies this as the fallback for the `V` symbol.

  ### Examples

      iex> Localize.DateTime.Timezone.short_zone_id("America/New_York")
      "usnyc"

      iex> Localize.DateTime.Timezone.short_zone_id("US/Eastern")
      "usnyc"

      iex> Localize.DateTime.Timezone.short_zone_id("Not/AZone")
      "unk"

  """
  @spec short_zone_id(String.t()) :: String.t()
  def short_zone_id(iana_id) when is_binary(iana_id) do
    Map.get(@short_zone_ids, iana_id, @unknown_short_zone_id)
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

  @doc """
  Returns the CLDR metazone for an IANA timezone name.

  Zones move between metazones over time (for example
  `America/Indiana/Knox` has alternated between the central and
  eastern metazones), so the datetime selects the applicable usage
  period.

  ### Arguments

  * `time_zone` is an IANA timezone name (e.g., `"America/New_York"`)
    or any of its CLDR aliases (e.g., `"Asia/Calcutta"`).

  * `datetime` is a map that may carry `:year` .. `:second` fields
    selecting the metazone in effect at that instant. When the fields
    are absent (or `datetime` is `nil`), the currently effective
    metazone is returned. The default is `nil`.

  ### Returns

  * The metazone as an atom (e.g., `:america_eastern`), matching the
    keys of the locale `time_zone_names.metazone` data.

  * `nil` when the zone has no metazone mapping for the instant.

  ### Examples

      iex> Localize.DateTime.Timezone.metazone_for("America/New_York")
      :america_eastern

      iex> Localize.DateTime.Timezone.metazone_for("Asia/Calcutta")
      :india

      iex> Localize.DateTime.Timezone.metazone_for("America/Indiana/Knox", ~N[2000-06-01 00:00:00])
      :america_eastern

      iex> Localize.DateTime.Timezone.metazone_for("America/Indiana/Knox", ~N[2020-06-01 00:00:00])
      :america_central

  """
  @spec metazone_for(String.t(), map() | nil) :: atom() | nil
  def metazone_for(time_zone, datetime \\ nil) do
    canonical = Map.get(@zone_canonical_names, time_zone, time_zone)

    # CLDR assigns no metazone to Etc/UTC, but its conformance data
    # expects the GMT metazone names for it ("Greenwich Mean Time").
    canonical = if canonical == "Etc/UTC", do: "Etc/GMT", else: canonical

    periods = Map.get(@metazone_info, canonical, [])
    instant = metazone_instant(datetime)

    Enum.find_value(periods, fn %{metazone: metazone, from: from, to: to} ->
      if within_period?(instant, from, to), do: metazone
    end)
  end

  @doc """
  Returns the IANA timezone that represents a CLDR metazone.

  ### Arguments

  * `metazone` is a metazone atom as returned by `metazone_for/2`
    (e.g., `:america_pacific`).

  * `territory` is a territory atom used to select a
    territory-specific representative zone (e.g., `:CA` selects
    `"America/Vancouver"` for `:america_pacific`). The default is
    `:"001"`, the metazone's golden zone.

  ### Returns

  * The IANA timezone name for the territory, falling back to the
    metazone's golden zone when the territory has no specific
    mapping.

  * `nil` when the metazone is unknown.

  ### Examples

      iex> Localize.DateTime.Timezone.zone_for_metazone(:america_pacific)
      "America/Los_Angeles"

      iex> Localize.DateTime.Timezone.zone_for_metazone(:america_pacific, :CA)
      "America/Vancouver"

      iex> Localize.DateTime.Timezone.zone_for_metazone(:no_such_metazone)
      nil

  """
  @spec zone_for_metazone(atom(), atom()) :: String.t() | nil
  def zone_for_metazone(metazone, territory \\ :"001") do
    case Map.get(@metazone_mapzones, metazone) do
      nil -> nil
      territories -> Map.get(territories, territory) || Map.get(territories, :"001")
    end
  end

  # A metazone usage period is selected by a UTC instant; when the
  # datetime carries no date fields (or is nil) the open-ended
  # current period matches via the nil instant.
  defp metazone_instant(%{year: year} = datetime) when is_integer(year) do
    {:ok, instant} =
      NaiveDateTime.new(
        year,
        Map.get(datetime, :month, 1),
        Map.get(datetime, :day, 1),
        Map.get(datetime, :hour, 0),
        Map.get(datetime, :minute, 0),
        Map.get(datetime, :second, 0)
      )

    offset = Map.get(datetime, :utc_offset, 0) + Map.get(datetime, :std_offset, 0)
    NaiveDateTime.add(instant, -offset, :second)
  end

  defp metazone_instant(_datetime), do: nil

  defp within_period?(nil, _from, to), do: is_nil(to)

  defp within_period?(instant, from, to) do
    (is_nil(from) or NaiveDateTime.compare(instant, from) != :lt) and
      (is_nil(to) or NaiveDateTime.compare(instant, to) == :lt)
  end

  @doc """
  Returns the specific or generic non-location timezone name.

  Looks up the zone's own name, then its metazone name, in the
  locale's timezone data (e.g., "Eastern Standard Time"). When the
  locale carries neither, falls back to `gmt_format/3`.

  ### Arguments

  * `datetime` is a map with `:time_zone`, `:utc_offset`, and
    `:std_offset` keys (a `t:DateTime.t/0` satisfies this shape).

  * `locale_id` is a **resolved** locale identifier atom (e.g., `:en`),
    such as the `cldr_locale_id` of a validated
    `t:Localize.LanguageTag.t/0`. It is passed directly to
    `Localize.Locale.get/2` and is not validated or canonicalized
    by this function.

  * `options` is a keyword list of options.

  ### Options

  * `:format` is `:short` (e.g., `"EST"`) or `:long` (e.g.,
    `"Eastern Standard Time"`). The default is `:long`.

  * `:type` is `:specific` (standard or daylight name chosen from
    the datetime's `:std_offset`), `:generic`, `:standard`, or
    `:daylight`. The default is `:specific`.

  ### Returns

  * `{:ok, timezone_name}` with the localized non-location name, or
    `{:ok, gmt_offset_string}` when falling back to the GMT format.

  * `{:error, exception}` if the locale's timezone data cannot be
    loaded.

  ### Examples

      iex> datetime = %{time_zone: "America/New_York", utc_offset: -18000, std_offset: 0}
      iex> Localize.DateTime.Timezone.non_location_format(datetime, :en, format: :long)
      {:ok, "Eastern Standard Time"}

      iex> datetime = %{time_zone: "America/New_York", utc_offset: -18000, std_offset: 0}
      iex> Localize.DateTime.Timezone.non_location_format(datetime, :en, format: :short)
      {:ok, "EST"}

  """
  @spec non_location_format(map(), atom(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def non_location_format(datetime, locale_id, options \\ []) do
    time_zone = Map.get(datetime, :time_zone)
    format = Keyword.get(options, :format, :long)
    type = Keyword.get(options, :type, :specific)

    with {:ok, tz_data} <- Localize.Locale.get(locale_id, [:dates, :time_zone_names]) do
      result =
        zone_name(time_zone, tz_data, format, type, datetime) ||
          metazone_name(metazone_for(time_zone, datetime), tz_data, format, type, datetime)

      cond do
        result ->
          {:ok, result}

        # TR35 sends the generic symbols through the generic location format
        # before the localized GMT format; the specific symbols go straight
        # to GMT.
        type == :generic ->
          case generic_location_format(time_zone, locale_id) do
            {:ok, location} -> {:ok, location}
            :error -> gmt_format(datetime, locale_id, format: format)
          end

        true ->
          gmt_format(datetime, locale_id, format: format)
      end
    end
  end

  defp zone_name(time_zone, tz_data, format, type, datetime) when is_binary(time_zone) do
    keys =
      @zone_canonical_names
      |> Map.get(time_zone, time_zone)
      |> String.downcase()
      |> String.split("/")
      |> Enum.map(&existing_atom/1)

    zone_data = get_in(tz_data[:zone], keys)

    metazone_data_name(zone_data, format, type, datetime) ||
      standard_for_generic(zone_data, format, type)
  end

  defp zone_name(_time_zone, _tz_data, _format, _type, _datetime), do: nil

  defp existing_atom(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> nil
  end

  # TR35 **Type Fallback**: a zone or metazone with no daylight type does not
  # require daylight support, so a request for the generic type resolves to the
  # standard name. This is how `Etc/GMT` reaches "Greenwich Mean Time" for
  # `vvvv` — the `gmt` metazone carries a standard name and nothing else.
  defp standard_for_generic(%{} = name_data, format, :generic) do
    unless get_in(name_data, [:long, :daylight]) || get_in(name_data, [:short, :daylight]) do
      format_key = if format == :short, do: :short, else: :long
      get_in(name_data, [format_key, :standard])
    end
  end

  defp standard_for_generic(_name_data, _format, _type), do: nil

  # Look up the non-location name for a metazone. Returns `nil`
  # when the zone has no metazone mapping or the locale has no
  # data for it, triggering the GMT format fallback.
  defp metazone_name(nil, _tz_data, _format, _type, _datetime), do: nil

  defp metazone_name(metazone_key, tz_data, format, type, datetime) do
    metazone_data = tz_data[:metazone][metazone_key]

    metazone_data_name(metazone_data, format, type, datetime) ||
      standard_for_generic(metazone_data, format, type)
  end

  defp metazone_data_name(nil, _format, _type, _datetime), do: nil

  defp metazone_data_name(metazone_data, format, type, datetime) do
    format_key = if format == :short, do: :short, else: :long
    type_key = resolve_type(type, datetime)
    get_in(metazone_data, [format_key, type_key])
  end

  @doc """
  Returns the localized GMT offset format.

  Uses the locale's `gmt_format` pattern (e.g., `["GMT", 0]`) and
  `hour_format` pattern to render the datetime's total UTC offset.

  ### Arguments

  * `datetime` is a map with an integer `:utc_offset` in seconds
    and optionally an integer `:std_offset` in seconds (a
    `t:DateTime.t/0` satisfies this shape).

  * `locale_id` is a **resolved** locale identifier atom (e.g., `:en`),
    such as the `cldr_locale_id` of a validated
    `t:Localize.LanguageTag.t/0`. It is passed directly to
    `Localize.Locale.get/2` and is not validated or canonicalized
    by this function.

  * `options` is a keyword list of options.

  ### Options

  * `:format` is `:long` (e.g., `"GMT+01:00"`) or `:short` (e.g.,
    `"GMT+1"`; minutes are dropped when zero). The default is
    `:long`.

  ### Returns

  * `{:ok, formatted_string}` (e.g., `"GMT+01:00"`). A zero offset is
    spelled out — `"GMT+00:00"` long, `"GMT+0"` short — which is the
    only style TR35 defines for a known offset.

  * `{:ok, unknown}` using the locale's `gmtUnknownFormat` (e.g.
    `"GMT+?"`) when `datetime` carries no offset at all. TR35 makes this
    the second of the two localized GMT styles.

  * `{:error, exception}` if the locale's timezone data cannot be
    loaded.

  ### Examples

      iex> Localize.DateTime.Timezone.gmt_format(%{utc_offset: 3600, std_offset: 0}, :en)
      {:ok, "GMT+01:00"}

      iex> Localize.DateTime.Timezone.gmt_format(%{utc_offset: -28800, std_offset: 0}, :en, format: :short)
      {:ok, "GMT-8"}

  """
  @spec gmt_format(map(), atom(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def gmt_format(datetime, locale_id, options \\ []) do
    with {:ok, tz_data} <- Localize.Locale.get(locale_id, [:dates, :time_zone_names]) do
      case total_offset(datetime) do
        nil -> {:ok, tz_data[:gmt_unknown_format] || @default_gmt_unknown_format}
        offset -> {:ok, offset_format(offset, tz_data, options)}
      end
    end
  end

  defp offset_format(offset, tz_data, options) do
    gmt_pattern = tz_data[:gmt_format] || @default_gmt_format
    hour_format = tz_data[:hour_format] || @default_hour_format
    format = Keyword.get(options, :format, :long)

    offset
    |> format_hour_offset(hour_format, format)
    |> Localize.Substitution.substitute(gmt_pattern)
    |> Enum.join()
  end

  @doc """
  Returns the ISO 8601 timezone offset format.

  This function is locale-independent — ISO 8601 offsets are the
  same in every locale.

  ### Arguments

  * `datetime` is a map with an integer `:utc_offset` in seconds
    and optionally an integer `:std_offset` in seconds (a
    `t:DateTime.t/0` satisfies this shape).

  * `options` is a keyword list of options.

  ### Options

  * `:format` is `:short` (minutes omitted when zero), `:long`
    (hours and minutes), or `:full` (like `:long`, with seconds
    appended when non-zero). The default is `:long`.

  * `:type` is `:basic` (no separator, e.g., `"+0500"`) or
    `:extended` (colon separator, e.g., `"+05:00"`). The default
    is `:basic`.

  * `:z_for_zero` is a boolean controlling whether a zero offset
    renders as `"Z"`. The default is `true`.

  ### Returns

  * `{:ok, formatted_string}` (e.g., `"+0500"`, `"Z"`, `"+05:00"`).

  ### Examples

      iex> Localize.DateTime.Timezone.iso_format(%{utc_offset: 18000, std_offset: 0})
      {:ok, "+0500"}

      iex> Localize.DateTime.Timezone.iso_format(%{utc_offset: 19800, std_offset: 0}, type: :extended)
      {:ok, "+05:30"}

      iex> Localize.DateTime.Timezone.iso_format(%{utc_offset: 0, std_offset: 0})
      {:ok, "Z"}

  """
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

  # TR35's second localized GMT style is for a zone whose offset is not
  # known. Returning zero here would spell "GMT+00:00" — a definite claim
  # about a zone we know nothing about — so the absence is preserved and
  # `gmt_format/3` renders `gmtUnknownFormat`.
  defp total_offset(_no_offset), do: nil

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

  @doc """
  Returns the exemplar city for an IANA timezone identifier.

  CLDR names a representative city for most timezones — the city a
  reader would recognise the zone by — localized, and sometimes
  differing from the city in the identifier: `"America/Godthab"` is
  `"Nuuk"`, which is what the place is now called.

  ### Arguments

  * `iana_id` is an IANA timezone identifier such as
    `"America/Los_Angeles"` or `"America/Indiana/Knox"`.

  * `locale` is a locale identifier or a `t:Localize.LanguageTag.t/0`.
    The default is `Localize.get_locale/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:derive` determines what happens when CLDR names no exemplar city
    for the zone. `true`, the default, derives one from the identifier,
    so `"Pacific/Wallis"` yields `"Wallis"`. `false` returns an error
    instead, which distinguishes a name CLDR vouches for from one this
    library invented.

  ### Returns

  * `{:ok, city}`, or

  * `{:error, exception}` if the locale is unknown, or if the zone has
    no exemplar city and `derive: false` was given.

  ### Examples

      iex> Localize.DateTime.Timezone.exemplar_city("America/Los_Angeles", :en)
      {:ok, "Los Angeles"}

      iex> Localize.DateTime.Timezone.exemplar_city("America/Godthab", :en)
      {:ok, "Nuuk"}

      iex> Localize.DateTime.Timezone.exemplar_city("America/Indiana/Knox", :en)
      {:ok, "Knox, Indiana"}

      iex> Localize.DateTime.Timezone.exemplar_city("Atlantic/Azores", :de)
      {:ok, "Azoren"}

      iex> {:error, exception} =
      ...>   Localize.DateTime.Timezone.exemplar_city("Neverwhere/Nowhere", :en, derive: false)
      iex> exception.__struct__
      Localize.UnknownTimezoneError

  """
  @spec exemplar_city(String.t(), Localize.locale(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def exemplar_city(iana_id, locale \\ Localize.get_locale(), options \\ [])

  def exemplar_city(iana_id, locale, options) when is_binary(iana_id) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      zone =
        case Localize.Locale.get(language_tag, [:dates, :time_zone_names]) do
          {:ok, tz_data} -> Map.get(tz_data, :zone, %{})
          {:error, _reason} -> %{}
        end

      # CLDR keys exemplar cities by canonical zone name, so an alias has to
      # be resolved first: `US/Eastern` would otherwise derive "Eastern" from
      # its own path rather than yielding New York's city. `metazone_for/2`
      # canonicalises for the same reason.
      canonical = Map.get(@zone_canonical_names, iana_id, iana_id)

      case find_exemplar_city(canonical, zone) do
        nil -> derived_exemplar_city(canonical, options)
        city -> {:ok, city}
      end
    end
  end

  defp derived_exemplar_city(iana_id, options) do
    with true <- Keyword.get(options, :derive, true),
         city when is_binary(city) <- derive_city_from_id(iana_id) do
      {:ok, city}
    else
      _no_city -> {:error, Localize.UnknownTimezoneError.exception(timezone: iana_id)}
    end
  end

  # The zone data is structured as
  # %{america: %{los_angeles: %{type: :zone, exemplar_city: "Los Angeles"}}}.
  # A three-part identifier — "America/Indiana/Knox" — nests one level deeper,
  # and CLDR keys that leaf by string rather than by atom.
  defp find_exemplar_city(iana_id, zone) do
    case String.split(iana_id, "/") do
      [region, city] ->
        exemplar_city_name(zone, [zone_key(region), zone_key(city)])

      [region, group, city] ->
        exemplar_city_name(zone, [zone_key(region), zone_key(group), leaf_key(city)])

      _other ->
        nil
    end
  end

  defp exemplar_city_name(zone, keys) do
    if Enum.all?(keys, & &1) do
      case get_in(zone, keys) do
        # A zone CLDR gives no exemplar city for carries only its long and
        # short names.
        %{exemplar_city: city_name} -> city_name
        _other -> nil
      end
    end
  end

  # Gate atomisation on existing-atom membership. The zone data has
  # pre-atomised keys for legitimate IANA components; an attacker-controlled
  # `-u-tz-` extension value with an unknown region or city must not be allowed
  # to grow the atom table.
  defp zone_key(component) do
    component
    |> leaf_key()
    |> Localize.Utils.Helpers.existing_atom()
  end

  defp leaf_key(component) do
    component
    |> String.downcase()
    |> String.replace(" ", "_")
  end

  # "America/Los_Angeles" -> "Los Angeles", "America/Argentina/Salta" -> "Salta"
  defp derive_city_from_id(iana_id) do
    case String.split(iana_id, "/") do
      [_single_component] -> nil
      parts -> parts |> List.last() |> String.replace("_", " ")
    end
  end

  @doc """
  Returns the place named by the generic location format for a timezone.

  TR35 names a country when the zone is the only one in its territory,
  or when CLDR lists it as that territory's primary zone, and names the
  zone's exemplar city otherwise. So `Europe/Rome` is "Italy" — Italy
  keeps one zone — while `Australia/Adelaide` is "Adelaide".

  ### Arguments

  * `iana_id` is an IANA timezone name such as `"Europe/Rome"`.

  * `locale` is any locale returned by `Localize.known_locale_names/0` or a
    `t:Localize.LanguageTag.t/0`. The default is `Localize.get_locale/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:derive` is a boolean determining whether an exemplar city may be
    derived from the timezone identifier when CLDR names none. The
    default is `true`.

  ### Returns

  * `{:ok, place_name}` where the place is a country or a city.

  * `{:error, exception}` if the locale is unknown, or if no city can be
    found or derived for the timezone.

  ### Examples

      iex> Localize.DateTime.Timezone.location_name("Europe/Rome", :en)
      {:ok, "Italy"}

      iex> Localize.DateTime.Timezone.location_name("Europe/Berlin", :en)
      {:ok, "Germany"}

      iex> Localize.DateTime.Timezone.location_name("Australia/Adelaide", :en)
      {:ok, "Adelaide"}

  """
  @spec location_name(String.t(), Localize.locale(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def location_name(iana_id, locale \\ Localize.get_locale(), options \\ [])

  def location_name(iana_id, locale, options) when is_binary(iana_id) do
    canonical = Map.get(@zone_canonical_names, iana_id, iana_id)

    with territory when not is_nil(territory) <- naming_territory(canonical),
         {:ok, name} <- territory_name(territory, locale) do
      {:ok, name}
    else
      _no_territory_name -> exemplar_city(iana_id, locale, options)
    end
  end

  def location_name(iana_id, _locale, _options) do
    {:error, Localize.UnknownTimezoneError.exception(timezone: iana_id)}
  end

  # A zone names its territory when CLDR lists it as that territory's
  # primary zone, or when it is the only zone the territory has.
  defp naming_territory(canonical) do
    case Map.get(@primary_zones, canonical) do
      nil -> sole_zone_territory(canonical)
      territory -> territory
    end
  end

  defp sole_zone_territory(canonical) do
    with territory when not is_nil(territory) <-
           Map.get(@territories_by_timezone, canonical),
         [_the_only_zone] <- Map.get(@timezones_by_territory, territory) do
      territory
    else
      _several_zones_or_none -> nil
    end
  end

  # TR35 prefers the short country name where the locale has one.
  defp territory_name(territory, locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, territories} <- Localize.Locale.get(language_tag, [:territories]),
         %{} = names <- Map.get(territories, territory),
         name when is_binary(name) <- Map.get(names, :short) || Map.get(names, :standard) do
      {:ok, name}
    else
      _no_name -> :error
    end
  end

  @doc """
  Returns the generic location format for a timezone.

  This is the `V` format symbol at width four: the zone's location
  substituted into the locale's generic `regionFormat`, so
  `Australia/Adelaide` in `en` is "Adelaide Time".

  ### Arguments

  * `iana_id` is an IANA timezone name such as `"Australia/Adelaide"`.

  * `locale` is any locale returned by `Localize.known_locale_names/0` or a
    `t:Localize.LanguageTag.t/0`. The default is `Localize.get_locale/0`.

  ### Returns

  * `{:ok, formatted_string}`.

  * `:error` for a zone with no place to name — the `Etc/*` zones, for
    which TR35 falls back to the localized GMT format — or when the
    locale has no `regionFormat`.

  ### Examples

      iex> Localize.DateTime.Timezone.generic_location_format("Australia/Adelaide", :en)
      {:ok, "Adelaide Time"}

      iex> Localize.DateTime.Timezone.generic_location_format("Europe/Rome", :en)
      {:ok, "Italy Time"}

      iex> Localize.DateTime.Timezone.generic_location_format("Etc/GMT", :en)
      :error

  """
  @spec generic_location_format(String.t(), Localize.locale()) :: {:ok, String.t()} | :error
  def generic_location_format(iana_id, locale \\ Localize.get_locale())

  def generic_location_format(iana_id, locale) when is_binary(iana_id) do
    with false <- etc_zone?(iana_id),
         {:ok, place} <- location_name(iana_id, locale),
         {:ok, language_tag} <- Localize.validate_locale(locale),
         {:ok, names} <- Localize.Locale.get(language_tag, [:dates, :time_zone_names]),
         %{generic: template} <- Map.get(names, :region_format, %{}) do
      {:ok, place |> Localize.Substitution.substitute(template) |> IO.iodata_to_binary()}
    else
      _no_place_or_template -> :error
    end
  end

  def generic_location_format(_iana_id, _locale), do: :error

  # `Etc/*` zones are not locations — there is no place to name — so TR35
  # sends them to the localized GMT format instead.
  defp etc_zone?("Etc/" <> _rest), do: true
  defp etc_zone?(_time_zone), do: false

  defp pad(integer, n) when is_integer(integer) do
    str = Integer.to_string(integer)
    padding = n - String.length(str)
    if padding > 0, do: String.duplicate("0", padding) <> str, else: str
  end
end
