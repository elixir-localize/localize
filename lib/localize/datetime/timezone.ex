defmodule Localize.DateTime.Timezone do
  @moduledoc """
  Provides timezone data access and timezone formatting for CLDR
  date/time format symbols.

  This module combines CLDR short zone code lookups (mapping between
  BCP 47 timezone identifiers and IANA timezone names) with the format
  symbol handlers for `z`, `Z`, `O`, `v`, `V`, `X`, and `x`.

  """

  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

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

  # The ASCII spellings TR35 allows for the localized GMT format,
  # longest first so `UTC` is not read as `UT` followed by a stray `C`.
  @gmt_literals ["GMT", "UTC", "UT"]

  # CLDR spells the negative sign three ways across the locales that ship
  # an `hour_format`: ASCII hyphen, U+2212 MINUS SIGN (`sv`, `fa`) and
  # U+2013 EN DASH (`eu`).
  @minus_signs ["-", "\u2212", "\u2013"]

  # Bidi controls that CLDR embeds in the `hour_format` of `fa` and `he`,
  # and that travel with an offset pasted out of rendered text. They carry
  # no numeric meaning, so they come off before parsing.
  @bidi_marks ["\u200E", "\u200F", "\u061C"]

  # Every digit CLDR's numbering systems write other than 0 to 9, by its
  # value. TR35's parsing has the localized GMT format read with "non-Latin
  # numbers", and the format is written in the locale's digits or in those
  # asked for: "غرينتش+٥:٣٠" in `ar-EG`, "GMT+५:३०" in `ne`. The digits of
  # any system are read in any locale, as ICU reads them, and in an ISO 8601
  # offset too, where ICU reads 0 to 9 alone: the date and time parsers read
  # all of a time in the locale's digits, its offset with it.
  @ascii_digits for {_system, %{digits: digits}} <- Localize.Number.System.numeric_systems(),
                    {digit, value} <- Enum.with_index(String.graphemes(digits)),
                    digit not in ~w(0 1 2 3 4 5 6 7 8 9),
                    into: %{},
                    do: {digit, Integer.to_string(value)}

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

  # Every IANA name CLDR knows, aliases included, by its lowercase form: a
  # zone ID is read whatever its case.
  @zone_ids_by_key for {alias_name, canonical} <- @zone_canonical_names,
                       into: %{},
                       do: {String.downcase(alias_name), canonical}

  # Every IANA name by the path the locale data keys a zone with: the parts
  # of its name in snake case, as the data build writes every key, so
  # `America/Blanc-Sablon` is "america/blanc_sablon" and
  # `Antarctica/DumontDUrville` "antarctica/dumont_d_urville".
  @zone_ids_by_data_key for {alias_name, canonical} <- @zone_canonical_names,
                            into: %{},
                            do:
                              {alias_name
                               |> String.split("/")
                               |> Enum.map_join("/", &Localize.Utils.Map.underscore/1), canonical}

  # The zone each BCP 47 short identifier stands for, as `V` writes it.
  @zones_by_short_id for {short_id, %{aliases: [canonical | _aliases]}} <- @timezones,
                         into: %{},
                         do: {short_id, canonical}

  # The zone of each territory that has one zone, the only countries whose
  # zone TR35's parse returns for the country alone.
  @sole_zones for {territory, [%{aliases: [canonical | _aliases]}]} <- @timezones_by_territory,
                  into: %{},
                  do: {territory, canonical}

  # The zone a location format names by its territory, the reverse of
  # `naming_territory/1`: the territory's primary zone, else its only one.
  @territory_zones Map.merge(
                     @sole_zones,
                     for({zone, territory} <- @primary_zones, into: %{}, do: {territory, zone})
                   )

  # The zone named for no place, which a parse cannot resolve.
  @unknown_zone "Etc/Unknown"

  # The apostrophes CLDR's names use, read as one another.
  @apostrophes Enum.map([0x2019, 0x02BC, 0x2018], &<<&1::utf8>>)

  # A name that stands for several types of one place stands for the
  # first of them here: a generic name follows the zone's own clock.
  @zone_name_types [:generic, :standard, :daylight]

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

  def short_zone_id(_iana_id), do: @unknown_short_zone_id

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
    selecting the metazone in effect at that instant. The fields are
    read in the map's `:calendar`, `Calendar.ISO` when it has none.
    When the fields are absent (or `datetime` is `nil`), or name no
    day of the calendar, the currently effective metazone is
    returned. The default is `nil`.

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
    case metazone_period(time_zone, datetime) do
      %{metazone: metazone} -> metazone
      nil -> nil
    end
  end

  # The zone's metazone usage period at the datetime's instant: its
  # metazone, and the offsets it names as standard and daylight time, if
  # any.
  defp metazone_period(time_zone, datetime) do
    canonical = Map.get(@zone_canonical_names, time_zone, time_zone)

    # CLDR assigns no metazone to Etc/UTC, but its conformance data
    # expects the GMT metazone names for it ("Greenwich Mean Time").
    canonical = if canonical == "Etc/UTC", do: "Etc/GMT", else: canonical

    periods = Map.get(@metazone_info, canonical, [])
    instant = metazone_instant(datetime)

    Enum.find(periods, fn %{from: from, to: to} -> within_period?(instant, from, to) end)
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
  # The UTC instant a map stands for, which selects its metazone period. A map
  # whose fields name no real date and time has none, and then only the zone's
  # current metazone applies, as for a map with no year.
  defp metazone_instant(%{year: year} = datetime) when is_integer(year) do
    case iso_wall_time(datetime) do
      {:ok, wall} -> NaiveDateTime.add(wall, -(total_offset(datetime) || 0), :second)
      _no_instant -> nil
    end
  end

  defp metazone_instant(_datetime), do: nil

  # The date and time a map's fields name, as an ISO date and time. The
  # fields are its calendar's, so its calendar says which day they are: the
  # Persian 25 Dey 1404 is 15 January 2026, not a day of the year 1404. A
  # map without a calendar is an ISO date and time, and one whose calendar
  # does not answer, or does not have the date, names none.
  defp iso_wall_time(%{year: year} = datetime) do
    month = Map.get(datetime, :month, 1)
    day = Map.get(datetime, :day, 1)
    hour = Map.get(datetime, :hour, 0)
    minute = Map.get(datetime, :minute, 0)
    second = Map.get(datetime, :second, 0)

    if Enum.all?([month, day, hour, minute, second], &is_integer/1),
      do: iso_wall_time(datetime, {year, month, day}, {hour, minute, second}),
      else: :error
  end

  defp iso_wall_time(datetime, {year, month, day}, {hour, minute, second}) do
    case Map.get(datetime, :calendar, Calendar.ISO) do
      Calendar.ISO ->
        NaiveDateTime.new(year, month, day, hour, minute, second)

      calendar ->
        with :ok <- Localize.Calendar.validate_calendar(datetime),
             {:ok, wall} <-
               NaiveDateTime.new(year, month, day, hour, minute, second, {0, 0}, calendar) do
          NaiveDateTime.convert(wall, Calendar.ISO)
        end
    end
  end

  # A map in another calendar with its date and time as `Calendar.ISO`'s for
  # the same day, so that the instant its fields name is asked of its
  # calendar once, however often it is needed. A map that names no day is
  # left as it is.
  defp with_iso_wall_time(%{calendar: calendar, year: year} = datetime)
       when calendar != Calendar.ISO and is_integer(year) do
    case iso_wall_time(datetime) do
      {:ok, %NaiveDateTime{} = wall} ->
        Map.merge(
          datetime,
          Map.take(wall, [:calendar, :year, :month, :day, :hour, :minute, :second])
        )

      _no_wall_time ->
        datetime
    end
  end

  defp with_iso_wall_time(datetime), do: datetime

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

  A metazone's name is shared by every zone that keeps it, so it is
  qualified as TR35 gives for the non-location formats, generic and
  specific alike: written as it is for the metazone's preferred zone
  for the locale's country, with the zone's country where it is that
  country's preferred zone ("Pacific Standard Time (Canada)" for
  Vancouver in `en`), and with its city otherwise ("Mountain Standard
  Time (Phoenix)"). A zone's own name is not qualified.

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

  * `:number_system` is the numbering system whose digits write the
    offset where the name falls back to `gmt_format/3`. The default is
    the locale's default numbering system.

  ### Returns

  * `{:ok, timezone_name}` with the localized non-location name, or
    `{:ok, gmt_offset_string}` when falling back to the GMT format.

  * `{:error, exception}` if the locale's timezone data cannot be
    loaded or `:type` is not one of the values above.

  ### Examples

      iex> datetime = %{time_zone: "America/New_York", utc_offset: -18000, std_offset: 0}
      iex> Localize.DateTime.Timezone.non_location_format(datetime, :en, format: :long)
      {:ok, "Eastern Standard Time"}

      iex> datetime = %{time_zone: "America/New_York", utc_offset: -18000, std_offset: 0}
      iex> Localize.DateTime.Timezone.non_location_format(datetime, :en, format: :short)
      {:ok, "EST"}

      iex> datetime = %{time_zone: "America/Vancouver", utc_offset: -28800, std_offset: 0}
      iex> Localize.DateTime.Timezone.non_location_format(datetime, :en)
      {:ok, "Pacific Standard Time (Canada)"}

  """
  @spec non_location_format(map(), atom(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def non_location_format(datetime, locale_id, options \\ [])

  def non_location_format(datetime, locale_id, options)
      when is_map(datetime) and is_keyword_list(options) do
    datetime = with_iso_wall_time(datetime)
    time_zone = datetime |> Map.get(:time_zone) |> named_zone(datetime)
    format = Keyword.get(options, :format, :long)

    with {:ok, type} <- non_location_type(Keyword.get(options, :type, :specific)),
         {:ok, tz_data} <- Localize.Locale.get(locale_id, [:dates, :time_zone_names]) do
      result =
        if type == :generic do
          generic_name(time_zone, tz_data, format, datetime, locale_id)
        else
          type = specific_type(type, time_zone, datetime)
          specific_name(time_zone, tz_data, format, type, datetime, locale_id)
        end

      cond do
        result ->
          {:ok, result}

        # TR35 sends the generic symbols through the generic location format
        # before the localized GMT format; the specific symbols go straight
        # to GMT.
        type == :generic ->
          generic_location_or_gmt(datetime, time_zone, locale_id, gmt_options(options))

        true ->
          gmt_format(datetime, locale_id, gmt_options(options))
      end
    end
  end

  def non_location_format(_datetime, _locale_id, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  def non_location_format(datetime, _locale_id, _options),
    do: {:error, Localize.Utils.Helpers.invalid_value(datetime, "a map with a :time_zone")}

  @non_location_types [:specific, :generic, :standard, :daylight]

  defp non_location_type(type) when type in @non_location_types, do: {:ok, type}

  defp non_location_type(type) do
    {:error,
     Localize.InvalidValueError.exception(
       value: type,
       expected: :time_zone_name_type,
       allowed_values: @non_location_types
     )}
  end

  # A UTC zone names the zero offset and no other. A struct carrying another
  # offset under a UTC identifier — the fixed offset an ISO 8601 parse of
  # `15:04-05:00` gives — is an offset with no name, which TR35 renders in
  # the localized GMT format rather than as "UTC".
  defp named_zone(time_zone, datetime) when is_binary(time_zone) do
    canonical = Map.get(@zone_canonical_names, time_zone, time_zone)

    if canonical in ["Etc/UTC", "Etc/GMT"] and (total_offset(datetime) || 0) != 0,
      do: nil,
      else: time_zone
  end

  defp named_zone(time_zone, _datetime), do: time_zone

  defp generic_location_or_gmt(datetime, time_zone, locale_id, gmt_options) do
    case generic_location_format(time_zone, locale_id) do
      {:ok, location} -> {:ok, location}
      :error -> gmt_format(datetime, locale_id, gmt_options)
    end
  end

  defp gmt_options(options) do
    [format: Keyword.get(options, :format, :long)] ++ Keyword.take(options, [:number_system])
  end

  defp zone_name(time_zone, tz_data, format, type, datetime) when is_binary(time_zone) do
    time_zone
    |> zone_data(tz_data)
    |> metazone_data_name(format, type, datetime)
  end

  defp zone_name(_time_zone, _tz_data, _format, _type, _datetime), do: nil

  defp zone_data(time_zone, tz_data) do
    case zone_path(Map.get(@zone_canonical_names, time_zone, time_zone)) do
      nil -> nil
      keys -> get_in(tz_data[:zone], keys)
    end
  end

  # Look up the non-location name for a metazone. Returns `nil`
  # when the zone has no metazone mapping or the locale has no
  # data for it, triggering the GMT format fallback.
  defp metazone_name(nil, _tz_data, _format, _type, _datetime), do: nil

  defp metazone_name(metazone_key, tz_data, format, type, datetime) do
    metazone_data_name(tz_data[:metazone][metazone_key], format, type, datetime)
  end

  defp metazone_data_name(nil, _format, _type, _datetime), do: nil

  defp metazone_data_name(metazone_data, format, type, datetime) do
    format_key = if format == :short, do: :short, else: :long
    type_key = resolve_type(type, datetime)
    get_in(metazone_data, [format_key, type_key])
  end

  # TR35's specific non-location format, by the steps it gives for "the
  # non-location formats (generic or specific)" and as CLDR's own
  # `TimezoneFormatter` gives it: the zone's own name for the type; else its
  # metazone's, qualified as a generic name is (`qualified_metazone_name/5`)
  # — "Pacific Standard Time" for Los Angeles in `en`, "Pacific Standard Time
  # (Canada)" for Vancouver, "Mountain Standard Time (Phoenix)" for Phoenix.
  # ICU never qualifies a specific name. Without either name the caller
  # falls back to the localized GMT format.
  defp specific_name(time_zone, tz_data, format, type, datetime, locale_id) do
    case zone_name(time_zone, tz_data, format, type, datetime) do
      nil ->
        metazone = metazone_for(time_zone, datetime)

        case metazone_name(metazone, tz_data, format, type, datetime) do
          nil -> nil
          name -> qualified_metazone_name(name, metazone, time_zone, tz_data, locale_id)
        end

      name ->
        name
    end
  end

  # TR35's generic non-location format, as CLDR's own `TimezoneFormatter`
  # gives it: the zone's own generic name; else its metazone's, qualified in
  # the locale's fallback format by the zone's country, or else its city,
  # unless the zone is the metazone's preferred zone for the locale's
  # country — "Pacific Time" for Los Angeles in `en`, "Pacific Time (Canada)"
  # for Vancouver, "Mountain Time (Phoenix)" for Phoenix. Without either
  # name the caller falls back to the location format.
  defp generic_name(time_zone, tz_data, format, datetime, locale_id)
       when is_binary(time_zone) do
    metazone = metazone_for(time_zone, datetime)

    case generic_or_standard(zone_data(time_zone, tz_data), format, time_zone, datetime) do
      nil ->
        metazone_names = metazone && tz_data[:metazone][metazone]

        case generic_or_standard(metazone_names, format, time_zone, datetime) do
          nil -> nil
          name -> qualified_metazone_name(name, metazone, time_zone, tz_data, locale_id)
        end

      name ->
        name
    end
  end

  defp generic_name(_time_zone, _tz_data, _format, _datetime, _locale_id), do: nil

  # A generic name, or where there is none the standard one when the zone
  # keeps a single offset for 184 days either side of the time, as TR35's
  # type fallback has it: `Etc/GMT` is "Greenwich Mean Time". London's
  # summer, which a locale with no British daylight name gives no generic
  # name either, is not.
  defp generic_or_standard(%{} = names, format, time_zone, datetime) do
    width = if format == :short, do: :short, else: :long

    cond do
      name = get_in(names, [width, :generic]) -> name
      keeps_one_offset?(names, time_zone, datetime) -> get_in(names, [width, :standard])
      true -> nil
    end
  end

  defp generic_or_standard(_names, _format, _time_zone, _datetime), do: nil

  # Whether the zone keeps one offset for 184 days either side of the time,
  # as the time zone database the application configures says. Without a
  # database that can say, TR35's own test stands: names with no daylight
  # time are for a zone that keeps none.
  defp keeps_one_offset?(names, time_zone, datetime) do
    case offset_changes_near(time_zone, datetime) do
      {:ok, changes?} ->
        not changes?

      :unknown ->
        is_nil(get_in(names, [:long, :daylight])) and is_nil(get_in(names, [:short, :daylight]))
    end
  end

  # The zone's offsets from 184 days before the time to 184 days after it,
  # read a week apart and at either end.
  @offset_sample_days Enum.to_list(-184..184//7) ++ [184]

  defp offset_changes_near(time_zone, datetime) do
    with %NaiveDateTime{} = instant <- metazone_instant(datetime),
         {:ok, offsets} <- sampled_offsets(instant, time_zone, Calendar.get_time_zone_database()) do
      {:ok, match?([_, _ | _], Enum.uniq(offsets))}
    else
      _no_offsets -> :unknown
    end
  end

  defp sampled_offsets(instant, time_zone, database) do
    Enum.reduce_while(@offset_sample_days, {:ok, []}, fn days, {:ok, offsets} ->
      with {:ok, utc} <- DateTime.from_naive(NaiveDateTime.add(instant, days * 86_400), "Etc/UTC"),
           {:ok, local} <- DateTime.shift_zone(utc, time_zone, database) do
        {:cont, {:ok, [{local.utc_offset, local.std_offset} | offsets]}}
      else
        _no_offset -> {:halt, :error}
      end
    end)
  end

  # TR35's steps for a metazone name: bare for the metazone's preferred zone
  # in the locale's country (else its golden zone), and for a zone with no
  # place to name; with the zone's country when it is that country's
  # preferred zone; with its exemplar city otherwise.
  defp qualified_metazone_name(name, metazone, time_zone, tz_data, locale_id) do
    canonical = Map.get(@zone_canonical_names, time_zone, time_zone)
    zones = Map.get(@metazone_mapzones, metazone, %{})
    golden_zone = Map.get(zones, :"001")
    country = Map.get(@territories_by_timezone, canonical)

    cond do
      is_nil(country) ->
        name

      canonical == (Map.get(zones, locale_territory_id(locale_id)) || golden_zone) ->
        name

      canonical == (Map.get(zones, country) || golden_zone) ->
        with_place(name, country_name(country, locale_id), tz_data)

      true ->
        with_place(name, city_name(canonical, locale_id), tz_data)
    end
  end

  defp locale_territory_id(locale_id) do
    case Localize.Territory.territory_from_locale(locale_id) do
      {:ok, territory} -> territory
      _no_territory -> :"001"
    end
  end

  # The country a metazone name is qualified with, by its full name as
  # CLDR's formatter and ICU write it ("Eastern Time (United States)"); by
  # TR35's composition, a country the locale does not name is its code.
  defp country_name(country, locale_id) do
    with {:ok, language_tag} <- Localize.validate_locale(locale_id),
         {:ok, territories} <- Localize.Locale.get(language_tag, [:territories]),
         %{standard: name} when is_binary(name) <- Map.get(territories, country) do
      name
    else
      _no_name -> Atom.to_string(country)
    end
  end

  defp city_name(time_zone, locale_id) do
    case exemplar_city(time_zone, locale_id) do
      {:ok, city} -> city
      {:error, _reason} -> derive_city_from_id(time_zone) || time_zone
    end
  end

  defp with_place(name, place, tz_data) do
    template = Map.get(tz_data, :fallback_format) || [1, " (", 0, ")"]
    [place, name] |> Localize.Substitution.substitute(template) |> IO.iodata_to_binary()
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
    `:long`. TR35 gives the long format a two-digit hour and the short
    format an hour with no leading zero, whichever the locale's
    `hourFormat` writes: `"UTC+05.30"` and `"UTC+5.30"` in `fi`, whose
    pattern is `"+H.mm"`.

  * `:number_system` is the numbering system whose digits write the
    offset, as TR35 has it written in the locale's digits (`"GMT-४"` in
    `ne`). The default is the locale's default numbering system. A system
    without digits of its own writes 0 to 9.

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

      iex> Localize.DateTime.Timezone.gmt_format(%{utc_offset: -14400, std_offset: 0}, :ne, format: :short)
      {:ok, "GMT-४"}

  """
  @spec gmt_format(map(), atom(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def gmt_format(datetime, locale_id, options \\ [])

  def gmt_format(datetime, locale_id, options) when is_keyword_list(options) do
    with {:ok, tz_data} <- Localize.Locale.get(locale_id, [:dates, :time_zone_names]) do
      case total_offset(datetime) do
        nil -> {:ok, tz_data[:gmt_unknown_format] || @default_gmt_unknown_format}
        offset -> {:ok, offset_format(offset, tz_data, locale_id, options)}
      end
    end
  end

  def gmt_format(_datetime, _locale_id, options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  defp offset_format(offset, tz_data, locale_id, options) do
    gmt_pattern = tz_data[:gmt_format] || @default_gmt_format
    hour_format = tz_data[:hour_format] || @default_hour_format
    format = Keyword.get(options, :format, :long)

    offset
    |> format_hour_offset(hour_format, format)
    |> offset_digits(locale_id, Keyword.get(options, :number_system))
    |> Localize.Substitution.substitute(gmt_pattern)
    |> Enum.join()
  end

  # The offset in the digits of the numbering system asked for, or of the
  # locale's (TR35, "Time Zone Format Terminology"): "GMT-४" in `ne`,
  # "غرينتش-٤" in `ar-EG`, as ICU writes them. A system without digits of its
  # own, or one that is not known, leaves 0 to 9.
  defp offset_digits(offset, locale_id, number_system) do
    with {:ok, system} <- offset_number_system(locale_id, number_system),
         {:ok, digits} <- Localize.Number.System.number_system_digits(system),
         %{} = map <- Localize.Number.System.generate_transliteration_map("0123456789", digits) do
      Localize.Number.Transliterate.transliterate_digits(offset, map)
    else
      _no_digits -> offset
    end
  end

  defp offset_number_system(locale_id, nil),
    do: Localize.Number.System.number_system_from_locale(locale_id)

  defp offset_number_system(_locale_id, number_system), do: {:ok, number_system}

  @doc """
  Parses a fixed UTC offset from a time zone string.

  This is the inverse of `gmt_format/3` and `iso_format/2`. It resolves
  only offsets that are pure arithmetic — an ISO 8601 offset, or the
  localized GMT format in the locale's own spelling. A named zone
  (`"PST"`, `"Asia/Tokyo"`) carries no offset of its own and needs a
  time-zone database to resolve; it is rejected here.

  The offset is read in the digits of any numbering system, whatever the
  locale, as TR35's parsing reads the localized GMT format with "non-Latin
  numbers": `gmt_format/3` writes it in the locale's digits.

  ### Arguments

  * `zone_string` is the zone portion of a parsed time, such as `"Z"`,
    `"+05:30"`, `"GMT+10:30"` or a locale's own GMT spelling.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier, used to recognise that locale's
    GMT format. The default is the locale returned by
    `Localize.get_locale/0`.

  ### Returns

  * `{:ok, offset}` where `offset` is the number of seconds east of
    UTC, negative for offsets west of it.

  * `{:error, exception}`, a `t:Localize.UnknownTimezoneError.t/0`, when
    the string carries no fixed offset.

  ### Examples

      iex> Localize.DateTime.Timezone.parse_offset("+05:30")
      {:ok, 19800}

      iex> Localize.DateTime.Timezone.parse_offset("Z")
      {:ok, 0}

      iex> Localize.DateTime.Timezone.parse_offset("GMT-8")
      {:ok, -28800}

      iex> Localize.DateTime.Timezone.parse_offset("GMT+५:३०", locale: :ne)
      {:ok, 19800}

      iex> Localize.DateTime.Timezone.parse_offset("Asia/Tokyo")
      {:error, %Localize.UnknownTimezoneError{timezone: "Asia/Tokyo"}}

  """
  @spec parse_offset(String.t(), Keyword.t()) :: {:ok, integer()} | {:error, Exception.t()}
  def parse_offset(zone_string, options \\ [])

  def parse_offset(zone_string, options)
      when is_binary(zone_string) and is_keyword_list(options) do
    normalized = zone_string |> strip_bidi_marks() |> ascii_digits()

    attempts = [
      fn -> parse_iso_offset(normalized) end,
      fn -> parse_ascii_gmt_offset(normalized) end,
      fn -> parse_localized_gmt_offset(normalized, options) end
    ]

    Enum.reduce_while(attempts, :error, fn attempt, _no_match ->
      case attempt.() do
        {:ok, _offset} = ok -> {:halt, ok}
        :error -> {:cont, :error}
      end
    end)
    |> case do
      {:ok, _offset} = ok -> ok
      :error -> {:error, Localize.UnknownTimezoneError.exception(timezone: zone_string)}
    end
  end

  def parse_offset(_zone_string, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  def parse_offset(zone_string, _options) do
    {:error, Localize.UnknownTimezoneError.exception(timezone: zone_string)}
  end

  defp strip_bidi_marks(zone_string) do
    @bidi_marks
    |> Enum.reduce(zone_string, &String.replace(&2, &1, ""))
    |> String.trim()
  end

  # The string with each digit of another numbering system as the digit of
  # its value. A string that is not text is left as it is, and is no
  # offset.
  defp ascii_digits(zone_string) do
    if String.valid?(zone_string) do
      for <<character::utf8 <- zone_string>>, into: "" do
        Map.get(@ascii_digits, <<character::utf8>>, <<character::utf8>>)
      end
    else
      zone_string
    end
  end

  # ── ISO 8601 offsets ─────────────────────────────────────────

  defp parse_iso_offset(zone) when zone in ["Z", "z"], do: {:ok, 0}

  # ISO 8601 requires a two-digit hour, so `+5` is not an ISO offset.
  defp parse_iso_offset(zone), do: parse_signed_offset(zone, :two_digit_hour)

  # ── Localized GMT format, ASCII spellings ────────────────────

  defp parse_ascii_gmt_offset(zone) do
    case strip_gmt_literal(zone) do
      :error -> :error
      "" -> {:ok, 0}
      remainder -> parse_signed_offset(remainder, :short_hour)
    end
  end

  defp strip_gmt_literal(zone) do
    Enum.find_value(@gmt_literals, &strip_leading_literal(zone, &1)) ||
      Enum.find_value(@gmt_literals, &strip_trailing_literal(zone, &1)) ||
      :error
  end

  defp strip_leading_literal(zone, literal) do
    size = byte_size(literal)

    case zone do
      <<head::binary-size(^size), rest::binary>> ->
        if String.upcase(head) == literal, do: String.trim(rest)

      _too_short ->
        nil
    end
  end

  # The trailing form covers the 15 locales whose `gmtFormat` puts the
  # literal after the offset (`pt-TL`, `se-FI`) and anyone who types it
  # that way. A zone that merely ends in these letters — `Asia/Beirut`
  # ends in `ut` — survives because the remainder must still parse as a
  # signed offset.
  defp strip_trailing_literal(zone, literal) do
    size = byte_size(literal)
    head_size = byte_size(zone) - size

    if head_size > 0 do
      <<head::binary-size(^head_size), tail::binary-size(^size)>> = zone

      if String.upcase(tail) == literal, do: String.trim(head)
    end
  end

  # ── Localized GMT format, the locale's own spelling ──────────

  defp parse_localized_gmt_offset(zone, options) do
    with {:ok, locale_id} <- offset_locale(options),
         {:ok, tz_data} <- Localize.Locale.get(locale_id, [:dates, :time_zone_names]),
         {:ok, remainder} <-
           strip_gmt_pattern(zone, tz_data[:gmt_format] || @default_gmt_format) do
      # A bare localized literal is deliberately not read as a zero
      # offset. Several locales spell the GMT format with a string that
      # is also a real zone abbreviation — `yo` uses "WAT", `ga` uses
      # "MAG" — and resolving those to UTC would be wrong, so only a
      # literal carrying an actual offset resolves here.
      parse_signed_offset(remainder, :short_hour)
    else
      _no_offset -> :error
    end
  end

  defp offset_locale(options) do
    case Localize.validate_locale(Keyword.get(options, :locale) || Localize.get_locale()) do
      {:ok, locale} -> {:ok, locale.cldr_locale_id}
      _invalid_locale -> :error
    end
  end

  defp strip_gmt_pattern(zone, pattern) when is_list(pattern) do
    prefix = pattern |> Enum.take_while(&(&1 != 0)) |> pattern_literal()
    suffix = pattern |> Enum.drop_while(&(&1 != 0)) |> Enum.drop(1) |> pattern_literal()

    with {:ok, without_prefix} <- strip_leading(zone, prefix),
         {:ok, remainder} <- strip_trailing(without_prefix, suffix) do
      {:ok, String.trim(remainder)}
    end
  end

  defp strip_gmt_pattern(_zone, _pattern), do: :error

  defp pattern_literal(parts) do
    parts
    |> Enum.filter(&is_binary/1)
    |> Enum.join()
    |> strip_bidi_marks()
  end

  defp strip_leading(string, ""), do: {:ok, string}

  defp strip_leading(string, prefix) do
    if String.starts_with?(string, prefix) do
      size = byte_size(prefix)
      {:ok, binary_part(string, size, byte_size(string) - size)}
    else
      :error
    end
  end

  defp strip_trailing(string, ""), do: {:ok, string}

  defp strip_trailing(string, suffix) do
    if String.ends_with?(string, suffix) do
      {:ok, binary_part(string, 0, byte_size(string) - byte_size(suffix))}
    else
      :error
    end
  end

  # ── Signed offset digits ─────────────────────────────────────

  defp parse_signed_offset(offset, hour_digits) do
    with {multiplier, digits} <- split_offset_sign(offset),
         {:ok, seconds} <- offset_seconds(digits, hour_digits) do
      {:ok, multiplier * seconds}
    else
      _no_offset -> :error
    end
  end

  defp split_offset_sign("+" <> rest), do: {1, rest}

  defp split_offset_sign(offset) do
    case Enum.find(@minus_signs, &String.starts_with?(offset, &1)) do
      nil ->
        :error

      minus ->
        size = byte_size(minus)
        {-1, binary_part(offset, size, byte_size(offset) - size)}
    end
  end

  # `:two_digit_hour` is ISO 8601, which writes `+05`. `:short_hour` also
  # accepts the one-digit hour of the localized GMT format — `GMT-8` is
  # exactly what `gmt_format/3` emits with `format: :short`, and `cs` and
  # `fi` write `+H:mm` and `+H.mm` respectively.
  defp offset_seconds(digits, hour_digits) do
    digits
    |> String.replace([":", "."], "")
    |> String.trim()
    |> offset_digit_groups(hour_digits)
  end

  defp offset_digit_groups(<<h::binary-size(2), m::binary-size(2), s::binary-size(2)>>, _hours) do
    offset_total(h, m, s)
  end

  defp offset_digit_groups(<<h::binary-size(2), m::binary-size(2)>>, _hours) do
    offset_total(h, m, "00")
  end

  defp offset_digit_groups(<<h::binary-size(1), m::binary-size(2)>>, :short_hour) do
    offset_total(h, m, "00")
  end

  defp offset_digit_groups(<<h::binary-size(2)>>, _hours) do
    offset_total(h, "00", "00")
  end

  defp offset_digit_groups(<<h::binary-size(1)>>, :short_hour) do
    offset_total(h, "00", "00")
  end

  defp offset_digit_groups(_digits, _hours), do: :error

  defp offset_total(hours, minutes, seconds) do
    with {hh, ""} when hh <= 14 <- Integer.parse(hours),
         {mm, ""} when mm < 60 <- Integer.parse(minutes),
         {ss, ""} when ss < 60 <- Integer.parse(seconds) do
      {:ok, hh * 3600 + mm * 60 + ss}
    else
      _invalid -> :error
    end
  end

  # ── Parsing a zone ───────────────────────────────────────────

  @doc """
  Parses a time zone written in any of the forms a locale formats one in.

  TR35's time zone parsing reads a zone as an ISO 8601 offset, the
  localized GMT format in the locale's spelling or the global one, in the
  digits of any numbering system ("GMT-4", "UTC−4", "غرينتش-4",
  "غرينتش-٤"), a zone ID ("America/New_York") or its short form
  ("usnyc"), an exemplar city ("New York"), a location ("New York Time",
  "heure : New York"), or a zone or metazone name, long or short, generic,
  standard or daylight ("Eastern Time", "EDT", "heure d’été de l’Est
  nord-américain"), alone or with a city or country in the locale's
  fallback format ("Pacific Time (Canada)").

  A country with one zone stands for that zone, and a city or a zone's own
  name is read before a metazone's, as TR35 orders them: "Chile Time (Punta
  Arenas)" is `America/Punta_Arenas`. A metazone name stands for the
  metazone's zone in the country the string names, else in the locale's
  country, else its golden zone, so "Mitteleuropäische Zeit" is
  `Europe/Berlin` in `de` and `Europe/Vienna` in `de-AT`, as ICU reads it.
  Where several metazones share a name ("Greenwich Mean Time") the one with
  a zone in that country is read, else the one with zones in the most
  countries. A country with several zones stands for its primary zone, as
  its location is written ("Germany Time"), where the string names no other
  zone.

  ### Arguments

  * `zone_string` is the zone as written.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is the locale whose names are read, any locale returned by
    `Localize.all_locale_ids/0` or a `t:Localize.LanguageTag.t/0`. The
    default is `Localize.get_locale/0`.

  ### Returns

  * `{:ok, {:offset, offset}}` for a fixed offset, in seconds east of UTC.

  * `{:ok, {:zone, time_zone, type}}` for a time zone, by CLDR's canonical
    IANA name, where `type` is `:standard` or `:daylight` for a name of that
    time and `:generic` for every other form.

  * `{:error, exception}` when the string is not a zone the locale writes.

  ### Examples

      iex> Localize.DateTime.Timezone.parse_zone("Eastern Daylight Time", locale: :en)
      {:ok, {:zone, "America/New_York", :daylight}}

      iex> Localize.DateTime.Timezone.parse_zone("heure : New York", locale: :fr)
      {:ok, {:zone, "America/New_York", :generic}}

      iex> Localize.DateTime.Timezone.parse_zone("Pacific Time (Canada)", locale: :en)
      {:ok, {:zone, "America/Vancouver", :generic}}

      iex> Localize.DateTime.Timezone.parse_zone("GMT-4", locale: :en)
      {:ok, {:offset, -14400}}

  """
  @spec parse_zone(String.t(), Keyword.t()) ::
          {:ok, {:offset, integer()} | {:zone, String.t(), :generic | :standard | :daylight}}
          | {:error, Exception.t()}
  def parse_zone(zone_string, options \\ [])

  def parse_zone(zone_string, options)
      when is_binary(zone_string) and is_keyword_list(options) do
    with {:ok, language_tag} <-
           Localize.validate_locale(Keyword.get(options, :locale) || Localize.get_locale()) do
      case parse_offset(zone_string, locale: language_tag) do
        {:ok, offset} -> {:ok, {:offset, offset}}
        {:error, _not_an_offset} -> parse_named_zone(zone_string, language_tag)
      end
    end
  end

  def parse_zone(_zone_string, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  def parse_zone(zone_string, _options),
    do: {:error, Localize.UnknownTimezoneError.exception(timezone: zone_string)}

  @doc """
  Resolves a time zone written in any form `parse_zone/2` reads, at a date
  and time, to the `t:DateTime.t/0` it names.

  A fixed offset resolves on its own, as a `t:DateTime.t/0` at that offset.
  A time zone's offset depends on the date, so it needs the time zone
  database the application configures, such as `:tz`
  (`config :elixir, :time_zone_database, Tz.TimeZoneDatabase`).

  A name of standard or daylight time is the zone's own `t:DateTime.t/0` on
  a date the zone keeps that time, as the formatter names it: by the offsets
  CLDR names standard and daylight for the zone's metazone where it gives
  them (Punta Arenas keeps Chile's summer time all year), and else as the
  time zone database says. On any other date the name keeps its own offset,
  as ICU reads it: "10:00 EST" in July is 10:00 at -05:00, a fixed offset,
  since New York keeps daylight time then. A standard name whose zone and
  metazone have no daylight name in the locale stands for every type, as
  TR35's type fallback has it, and follows the zone's clock.

  Any other form follows the zone's clock, and a wall time its clocks pass
  twice is read in standard time, one they skip at the offset before the
  change, as ICU reads them.

  ### Arguments

  * `zone_string` is the zone as written.

  * `naive_datetime` is the date and time written with it, a
    `t:NaiveDateTime.t/0` in any calendar.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is the locale whose names are read. The default is
    `Localize.get_locale/0`.

  ### Returns

  * `{:ok, datetime}`.

  * `{:error, exception}` when the string is not a zone the locale writes,
    or names a time zone the configured database does not resolve, as
    Elixir's default database resolves none but UTC.

  ### Examples

      iex> {:ok, datetime} =
      ...>   Localize.DateTime.Timezone.resolve("UTC−4", ~N[2023-07-15 10:05:00], locale: :fr)
      iex> {datetime.utc_offset, DateTime.to_naive(datetime)}
      {-14400, ~N[2023-07-15 10:05:00]}

  """
  @spec resolve(String.t(), NaiveDateTime.t(), Keyword.t()) ::
          {:ok, DateTime.t()} | {:error, Exception.t()}
  def resolve(zone_string, naive_datetime, options \\ [])

  def resolve(zone_string, %NaiveDateTime{} = naive_datetime, options)
      when is_binary(zone_string) and is_keyword_list(options) do
    with {:ok, language_tag} <-
           Localize.validate_locale(Keyword.get(options, :locale) || Localize.get_locale()),
         {:ok, zone} <- parse_zone(zone_string, Keyword.put(options, :locale, language_tag)) do
      resolve_parsed_zone(zone, naive_datetime, Calendar.get_time_zone_database(), language_tag)
    end
  end

  def resolve(_zone_string, _naive_datetime, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  def resolve(zone_string, _naive_datetime, _options),
    do: {:error, Localize.UnknownTimezoneError.exception(timezone: zone_string)}

  @doc false
  # A date and time at a fixed offset, carried as Localize and Calendrical
  # carry one: under `Etc/UTC` with the offset as its `utc_offset` and
  # spelled as its `zone_abbr`, so the wall time is kept as written.
  @spec offset_datetime(map(), integer()) :: DateTime.t()
  def offset_datetime(naive_datetime, offset) do
    struct(DateTime, Map.merge(Map.from_struct(naive_datetime), offset_zone_fields(offset)))
  end

  @doc false
  # The zone fields of a fixed offset, as `offset_datetime/2` carries them.
  @spec offset_zone_fields(integer()) :: map()
  def offset_zone_fields(offset) do
    %{
      time_zone: "Etc/UTC",
      utc_offset: offset,
      std_offset: 0,
      zone_abbr: offset_abbreviation(offset)
    }
  end

  defp offset_abbreviation(0), do: "UTC"

  defp offset_abbreviation(offset) do
    sign = if offset < 0, do: "-", else: "+"
    absolute = abs(offset)
    hours = absolute |> div(3600) |> pad(2)
    minutes = absolute |> rem(3600) |> div(60) |> pad(2)
    "#{sign}#{hours}:#{minutes}"
  end

  # A name or place comes before a zone ID, which TR35's process does not
  # read at all: "EST" is Eastern Standard Time in `en`, as ICU reads it,
  # though the time zone database also keeps it as a link to Panama.
  #
  # Bytes that are not text name no zone, and are not put to the names'
  # patterns, which raise on them.
  defp parse_named_zone(zone_string, language_tag) do
    with true <- String.valid?(zone_string),
         key = name_key(zone_string),
         {time_zone, type} when time_zone != @unknown_zone <-
           place_zone(key, zone_name_index(language_tag), language_tag) || zone_id(key) do
      {:ok, {:zone, time_zone, type}}
    else
      _no_zone -> {:error, Localize.UnknownTimezoneError.exception(timezone: zone_string)}
    end
  end

  # `VV` and `V`: a zone ID or its BCP 47 short form.
  defp zone_id(key) do
    case Map.get(@zone_ids_by_key, key) || Map.get(@zones_by_short_id, key) do
      nil -> nil
      time_zone -> {time_zone, :generic}
    end
  end

  # TR35's sample process. A string in the shape of the locale's fallback
  # format whose part in parentheses is a place is read as a name N and that
  # place P ("Pacific Time (Canada)"), and else, or when that reading names
  # no zone, as a name alone. A string that is itself a name is read as that
  # name first, as ICU takes the longest match: `uk` names Eastern time "за
  # східним часом (ET)", and `he` a standard time "… (חורף)", "(winter)".
  # So is one that is itself a place, alone or in a region format: `fr-CA`
  # names a country "Saint-Martin (France)", whose zone is not Paris.
  #
  # A name or a place may hold the format's own punctuation, so the string
  # is split both at the last place it can be and at the first: `pt-AO`
  # names a country "Côte d’Ivoire (Costa do Marfim)", and "Hora de
  # Greenwich (Côte d’Ivoire (Costa do Marfim))" is that country's Greenwich
  # time.
  defp place_zone(key, index, language_tag) do
    splits =
      index.fallback_formats
      |> Enum.flat_map(fn regex ->
        case Regex.named_captures(regex, key) do
          %{"name" => name, "place" => place} -> [{name, place}]
          nil -> []
        end
      end)
      |> Enum.uniq()

    readings =
      if whole_reading?(key, index) do
        [{key, nil} | splits]
      else
        Enum.filter(splits, fn {_name, place} ->
          qualifier_country(place, index) || Map.has_key?(index.cities, place)
        end) ++ [{key, nil}]
      end

    Enum.find_value(readings, fn {name, place} ->
      reading_zone(name, place, index, language_tag)
    end)
  end

  # Whether the whole string is one of the locale's names, or a country or
  # a city it names, alone or in a region format.
  defp whole_reading?(key, index) do
    {located, _region_type} = region_place(key, index)

    Map.has_key?(index.names, key) or named_place?(key, index) or named_place?(located, index)
  end

  defp named_place?(nil, _index), do: false

  defp named_place?(place, index),
    do: Map.has_key?(index.countries, place) or Map.has_key?(index.cities, place)

  # One reading: N may be a place in a region format ("Italy Time"), M,
  # and a country among P, N and M is C. In TR35's order: C's zone where C
  # has one zone; P as a city; N or M as a zone's own name, or a city; then
  # N or M as a metazone's name, whose zone is C's, else the locale's
  # country's. So "Chile Time (Punta Arenas)" is Punta Arenas, a city of a
  # country with several zones, as ICU reads it.
  #
  # After them comes what TR35's sample leaves out, the primary zone of a
  # country with several: its location format writes Berlin "Germany Time".
  # It is last, since a name qualified by a country is the metazone's zone
  # for that country, which need not be the primary one: `fo` writes the
  # Canary Islands' zone "Vesturevropa tíð (Spania)". Last of all a
  # metazone's name stands for its zone whatever country is named with it.
  #
  # The type of time is the name's own where the locale has the name, and
  # else the region format's it is written in: `ko` names Central European
  # Summer Time "중부유럽 하계 표준시", which is also the shape of its
  # standard region format, "{0} 표준시".
  defp reading_zone(name, place, index, language_tag) do
    {located, region_type} = named_region_place(name, index)
    type = name_type(name, index) || region_type || :generic

    country =
      qualifier_country(place, index) ||
        Enum.find_value([name, located], &Map.get(index.countries, &1)) ||
        unnamed_country(located, index)

    [
      fn -> sole_zone(country, type) end,
      fn -> city_zone(place, type, index) end,
      fn -> own_name_zone(name, index) end,
      fn -> own_name_zone(located, index) end,
      fn -> city_zone(located, type, index) end,
      fn -> city_zone(name, type, index) end,
      fn -> metazone_name_zone(name, country, index, language_tag) end,
      fn -> metazone_name_zone(located, country, index, language_tag) end,
      fn -> country_zone(country, type) end,
      fn -> country && metazone_name_zone(name, nil, index, language_tag) end,
      fn -> country && metazone_name_zone(located, nil, index, language_tag) end
    ]
    |> Enum.find_value(fn step -> step.() end)
  end

  # The place a string names in a region format, and that format's type of
  # time. A string the locale has as a name is no standard or daylight
  # region format, which no pattern writes: `af`'s "Samoa-standaardtyd" is
  # American Samoa's standard time, as ICU reads it, not the standard time
  # of the country Samoa.
  defp named_region_place(name, index) do
    case region_place(name, index) do
      {_place, type} when type != :generic and is_map_key(index.names, name) -> {nil, nil}
      located -> located
    end
  end

  # The country a region format's place names by its code. The location
  # format writes a code only for a country the locale does not name ("ZA
  # Time", and "LR" where the region format is the place alone), so a code
  # is read only for those: where the locale names Saint Pierre and
  # Miquelon, "PM" is never its zone.
  defp unnamed_country(nil, _index), do: nil
  defp unnamed_country(located, index), do: Map.get(index.unnamed_countries, located)

  # The country the fallback format's qualifier names, by the locale's name
  # for it or by its code.
  defp qualifier_country(nil, _index), do: nil

  defp qualifier_country(place, index),
    do: Map.get(index.countries, place) || Map.get(index.country_codes, place)

  # The place a region format ("{0} Time", "heure : {0}") names, and the
  # type of time that format is for.
  defp region_place(name, index) do
    Enum.find_value(index.region_formats, {nil, nil}, fn {type, regex} ->
      case Regex.named_captures(regex, name) do
        %{"place" => place} -> {place, type}
        nil -> nil
      end
    end)
  end

  defp name_type(name, index) do
    case Map.get(index.names, name) do
      %{zones: [{_zone, type} | _rest]} -> type
      %{metazones: [{_metazone, type} | _rest]} -> type
      _no_name -> nil
    end
  end

  defp sole_zone(nil, _type), do: nil

  defp sole_zone(country, type) do
    case Map.get(@sole_zones, country) do
      nil -> nil
      time_zone -> {time_zone, type}
    end
  end

  defp country_zone(nil, _type), do: nil

  defp country_zone(country, type) do
    case Map.get(@territory_zones, country) do
      nil -> nil
      time_zone -> {time_zone, type}
    end
  end

  defp city_zone(nil, _type, _index), do: nil

  defp city_zone(city, type, index) do
    case Map.get(index.cities, city) do
      nil -> nil
      time_zone -> {time_zone, type}
    end
  end

  defp own_name_zone(nil, _index), do: nil

  defp own_name_zone(name, index) do
    case Map.get(index.names, name) do
      %{zones: [{time_zone, type} | _rest]} -> {time_zone, type}
      _no_zone_name -> nil
    end
  end

  # The metazone's zone in the country the string names: the zone CLDR maps
  # to that country, or the metazone's golden zone where that is in the
  # country, the two zones the formatter qualifies by a country. "Eastern
  # Time (United States)" is New York in `en-JM`, as ICU reads it, though
  # Jamaica keeps Eastern time too. With no country named, the zone is the
  # locale's country's, else the golden zone, which stands for every country
  # CLDR maps no zone of its own to.
  defp metazone_name_zone(nil, _country, _index, _language_tag), do: nil

  defp metazone_name_zone(name, country, index, language_tag) do
    case Map.get(index.names, name) do
      %{metazones: [_first | _rest] = metazones} ->
        territory = country || locale_territory(language_tag)
        {metazone, type} = preferred_metazone(metazones, territory)
        zones = Map.get(@metazone_mapzones, metazone, %{})
        golden_zone = Map.get(zones, :"001")

        cond do
          time_zone = Map.get(zones, territory) -> {time_zone, type}
          is_nil(golden_zone) -> nil
          is_nil(country) -> {golden_zone, type}
          Map.get(@territories_by_timezone, golden_zone) == country -> {golden_zone, type}
          true -> nil
        end

      _no_metazone_name ->
        nil
    end
  end

  # Of metazones sharing a name, the one with a zone in the territory, else
  # the one with zones in the most territories, else the first by name: ICU
  # reads "Greenwich Mean Time", which names the GMT, British and Irish
  # metazones, as `Atlantic/Reykjavik` in `en`, `Europe/London` in `en-GB`
  # and `Europe/Dublin` in `en-IE`.
  defp preferred_metazone(metazones, territory) do
    Enum.min_by(metazones, fn {metazone, type} ->
      zones = Map.get(@metazone_mapzones, metazone, %{})

      {not metazone_in_territory?(zones, territory), -map_size(zones), metazone,
       Enum.find_index(@zone_name_types, &(&1 == type))}
    end)
  end

  defp metazone_in_territory?(zones, territory) do
    Map.has_key?(zones, territory) or
      Enum.any?(zones, fn {_territory, zone} ->
        Map.get(@territories_by_timezone, zone) == territory
      end)
  end

  defp locale_territory(language_tag) do
    case Localize.Territory.territory_from_locale(language_tag) do
      {:ok, territory} -> territory
      _no_territory -> :"001"
    end
  end

  # Names are matched without regard to case, spacing, bidi marks or the
  # apostrophe used.
  defp name_key(string), do: string |> literal_key() |> String.trim()

  defp literal_key(string) do
    string
    |> String.replace(@bidi_marks, "")
    |> String.replace(@apostrophes, "'")
    |> String.replace(~r/\s+/u, " ")
    |> String.downcase()
  end

  # ── The names a locale writes zones with ─────────────────────

  # The names are the locale's, so its index is built once and kept.
  defp zone_name_index(%Localize.LanguageTag{cldr_locale_id: locale_id} = language_tag) do
    key = {__MODULE__, :zone_name_index, locale_id}

    case :persistent_term.get(key, nil) do
      nil ->
        index = build_zone_name_index(language_tag)
        :persistent_term.put(key, index)
        index

      index ->
        index
    end
  end

  defp build_zone_name_index(language_tag) do
    names =
      case Localize.Locale.get(language_tag, [:dates, :time_zone_names]) do
        {:ok, %{} = names} -> names
        _no_names -> %{}
      end

    territories =
      case Localize.Locale.get(language_tag, [:territories]) do
        {:ok, %{} = territories} -> territories
        _no_territories -> %{}
      end

    zones = zone_leaves(Map.get(names, :zone, %{}), [])

    %{
      names: zone_names(zones, Map.get(names, :metazone, %{})),
      cities: city_names(zones),
      countries: country_names(territories),
      country_codes: country_codes(),
      unnamed_countries: unnamed_countries(territories),
      region_formats: region_format_regexes(Map.get(names, :region_format, %{})),
      fallback_formats: fallback_format_regexes(Map.get(names, :fallback_format))
    }
  end

  # Each zone in the locale's data, by its canonical name, with its names.
  # The data keys a zone by the parts of its name in snake case
  # (`@zone_ids_by_data_key`), and nests a three-part name one level deeper.
  defp zone_leaves(%{} = data, path) do
    Enum.flat_map(data, fn
      {part, %{type: :zone} = zone} ->
        case Map.get(@zone_ids_by_data_key, Enum.join(path ++ [to_string(part)], "/")) do
          nil -> []
          time_zone -> [{time_zone, zone}]
        end

      {part, %{} = nested} ->
        zone_leaves(nested, path ++ [to_string(part)])

      _other ->
        []
    end)
  end

  # Every long and short name of every zone and metazone, each to the
  # places it stands for, in order: a name standing for several types of
  # one place stands for the first in `@zone_name_types`.
  defp zone_names(zones, metazones) do
    zone_entries =
      for {time_zone, zone} <- zones,
          {name, type} <- names_of(zone),
          do: {name_key(name), :zones, {time_zone, type}}

    metazone_entries =
      for {metazone, forms} <- metazones,
          {name, type} <- names_of(forms),
          do: {name_key(name), :metazones, {metazone, type}}

    (zone_entries ++ metazone_entries)
    |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})
    |> Map.new(fn {key, places} ->
      {key,
       places
       |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
       |> Map.new(fn {kind, kind_places} -> {kind, Enum.sort_by(kind_places, &place_order/1)} end)}
    end)
  end

  defp names_of(%{} = forms) do
    for width <- [:long, :short],
        type <- @zone_name_types,
        name = get_in(forms, [width, type]),
        is_binary(name),
        do: {name, type}
  end

  defp names_of(_forms), do: []

  defp place_order({place, type}),
    do: {Enum.find_index(@zone_name_types, &(&1 == type)), place}

  # The exemplar cities the locale names, and the city every other zone's
  # name gives ("Los Angeles"), which the locale writes where it names none.
  # Of zones whose cities share a name, the alphabetically first is taken,
  # where inverting them kept whichever the map yielded last.
  defp city_names(zones) do
    derived =
      for {_short_id, %{aliases: [time_zone | _aliases]}} <- @timezones,
          not String.starts_with?(time_zone, "Etc/"),
          city = derive_city_from_id(time_zone),
          is_binary(city),
          do: {name_key(city), time_zone}

    named =
      for {time_zone, %{exemplar_city: city}} <- zones,
          is_binary(city),
          do: {name_key(city), time_zone}

    Map.merge(first_by_name(derived, &Enum.min/1), first_by_name(named, &Enum.min/1))
  end

  # Of territories that share a name, the one `Localize.Territory`'s
  # names pick: a country before a region that contains others, then the
  # alphabetically first code.
  defp country_names(territories) do
    for(
      {territory, names} <- territories,
      is_map(names),
      {_form, name} <- names,
      is_binary(name),
      do: {name_key(name), territory}
    )
    |> first_by_name(&Localize.Territory.preferred_territory/1)
  end

  defp first_by_name(entries, choose) do
    entries
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {key, values} -> {key, values |> Enum.uniq() |> choose.()} end)
  end

  # The code of every country with a zone, which TR35's composition writes
  # as the qualifier for a country the locale does not name ("Pacific Time
  # (CA)"). It is read only there: "MT" alone is Mountain Time, not Malta.
  defp country_codes do
    for territory <- Map.values(@territories_by_timezone),
        into: %{},
        do: {name_key(Atom.to_string(territory)), territory}
  end

  # The codes of the countries the location format writes by their code in
  # this locale, having no name for them.
  defp unnamed_countries(territories) do
    for {code, territory} <- country_codes(),
        is_nil(location_country_name(Map.get(territories, territory))),
        into: %{},
        do: {code, territory}
  end

  defp region_format_regexes(region_formats) do
    for type <- @zone_name_types,
        regex = template_regex(Map.get(region_formats, type)),
        regex != nil,
        do: {type, regex}
  end

  # The fallback format as two regexes, one taking the longest first part a
  # string allows and one the shortest, so that a string is split at the
  # last and at the first place the format's punctuation is found.
  defp fallback_format_regexes(template) do
    [template_regex(template), template_regex(template, "+?")]
    |> Enum.reject(&is_nil/1)
  end

  # A region or fallback format ("{0} Time", "{1} ({0})") as a regex over
  # the forms `name_key/1` makes, capturing {0} as the place and {1} as the
  # name.
  defp template_regex(template, quantifier \\ "+")

  defp template_regex([_ | _] = template, quantifier) do
    source =
      Enum.map_join(template, fn
        0 -> "(?<place>." <> quantifier <> ")"
        1 -> "(?<name>." <> quantifier <> ")"
        literal when is_binary(literal) -> literal |> literal_key() |> Regex.escape()
        _other -> ""
      end)

    case Regex.compile("\\A" <> source <> "\\z", "u") do
      {:ok, regex} -> regex
      {:error, _reason} -> nil
    end
  end

  defp template_regex(_template, _quantifier), do: nil

  # ── Resolving a parsed zone ──────────────────────────────────

  defp resolve_parsed_zone({:offset, offset}, naive_datetime, _database, _language_tag),
    do: {:ok, offset_datetime(naive_datetime, offset)}

  defp resolve_parsed_zone({:zone, time_zone, :generic}, naive_datetime, database, _language_tag) do
    case DateTime.from_naive(naive_datetime, time_zone, database) do
      {:ok, datetime} ->
        {:ok, datetime}

      {:ambiguous, first, second} ->
        {:ok, Enum.min_by([first, second], &total_offset/1)}

      {:gap, just_before, _just_after} ->
        across_gap(naive_datetime, time_zone, total_offset(just_before), database)

      {:error, _reason} ->
        {:error, Localize.UnknownTimezoneError.exception(timezone: time_zone)}
    end
  end

  # A name of standard or daylight time is the zone's own reading of the
  # wall clock where the zone keeps that time then: the reading the
  # formatter names so (`specific_type/3`), which is how the name came to be
  # written. Punta Arenas keeps -03:00 all year and CLDR names that Chile's
  # summer time; Knox, Indiana kept Eastern Standard Time through 1991's
  # winter and Central time after it. Of two such readings, a wall time the
  # clocks pass twice, the later is taken, as a generic name's is.
  #
  # Where the zone keeps another time then, the name keeps its own offset,
  # as ICU reads it: "10:00 EST" in July is 10:00 at -05:00. A standard name
  # that stands for every type (`stands_for_every_type?/4`) has no offset of
  # its own, and follows the zone's clock as a generic name does.
  defp resolve_parsed_zone({:zone, time_zone, type}, naive_datetime, database, language_tag) do
    case DateTime.from_naive(naive_datetime, time_zone, database) do
      {:error, _reason} ->
        {:error, Localize.UnknownTimezoneError.exception(timezone: time_zone)}

      reading ->
        {candidates, reference} = wall_readings(reading)
        named = Enum.filter(candidates, &(specific_type(:specific, time_zone, &1) == type))

        cond do
          named != [] ->
            {:ok, Enum.min_by(named, &total_offset/1)}

          stands_for_every_type?(type, time_zone, reference, language_tag) ->
            generic = {:zone, time_zone, :generic}
            resolve_parsed_zone(generic, naive_datetime, database, language_tag)

          true ->
            nearby = nearby_readings(naive_datetime, time_zone, database)
            offset = named_offset(type, time_zone, reference, nearby)
            {:ok, offset_datetime(naive_datetime, offset)}
        end
    end
  end

  # TR35's type fallback: where the locale has no daylight name for a zone
  # or its metazone they need none, and the standard name stands for all
  # three types. "Kyrgyzstan Time", the only name `en` has for that metazone
  # and its location format too, is Bishkek's time in the summers it kept
  # daylight time as in its winters.
  defp stands_for_every_type?(:standard, time_zone, reference, language_tag) do
    case Localize.Locale.get(language_tag, [:dates, :time_zone_names]) do
      {:ok, %{} = tz_data} ->
        metazone = metazone_for(time_zone, reference)
        metazone_names = metazone && get_in(tz_data, [:metazone, metazone])

        not daylight_name?(zone_data(time_zone, tz_data)) and not daylight_name?(metazone_names)

      _no_names ->
        false
    end
  end

  defp stands_for_every_type?(_daylight, _time_zone, _reference, _language_tag), do: false

  defp daylight_name?(%{} = names) do
    is_binary(get_in(names, [:long, :daylight])) or is_binary(get_in(names, [:short, :daylight]))
  end

  defp daylight_name?(_no_names), do: false

  # A wall time the clocks skip is read at the offset before the change,
  # as ICU reads it: New York's 02:30 on the day it springs forward is 03:30
  # daylight time.
  defp across_gap(naive_datetime, time_zone, offset, database) do
    with {:ok, utc} <- DateTime.from_naive(NaiveDateTime.add(naive_datetime, -offset), "Etc/UTC"),
         {:ok, datetime} <- DateTime.shift_zone(utc, time_zone, database) do
      {:ok, datetime}
    else
      _no_datetime -> {:error, Localize.UnknownTimezoneError.exception(timezone: time_zone)}
    end
  end

  # The readings of the wall clock that can be the answer — one, or both
  # sides of a fall-back overlap, or none in a spring-forward gap — and a
  # reading the zone's time is known by there: the first of them, or the one
  # before the gap.
  defp wall_readings({:ok, datetime}), do: {[datetime], datetime}
  defp wall_readings({:ambiguous, first, second}), do: {[first, second], first}
  defp wall_readings({:gap, just_before, _just_after}), do: {[], just_before}

  defp nearby_readings(naive_datetime, time_zone, database) do
    case NaiveDateTime.convert(naive_datetime, Calendar.ISO) do
      {:ok, iso} ->
        for months <- [-9, -6, -3, 3, 6, 9],
            reading <- nearby_reading(iso, months, time_zone, database),
            do: reading

      {:error, _reason} ->
        []
    end
  end

  defp nearby_reading(iso, months, time_zone, database) do
    case DateTime.from_naive(NaiveDateTime.shift(iso, month: months), time_zone, database) do
      {:ok, datetime} -> [datetime]
      {:ambiguous, first, _second} -> [first]
      {:gap, _just_before, just_after} -> [just_after]
      {:error, _reason} -> []
    end
  end

  # The offset a name of standard or daylight time stands for in a zone
  # keeping another time: the one its metazone period names (TR35's
  # `stdOffset` and `dstOffset`), and else the zone's standard offset then,
  # with, for daylight time, the most the zone saves within nine months
  # either side, or an hour where it saves none, as ICU reads it.
  defp named_offset(type, time_zone, reference, nearby) do
    case metazone_period(time_zone, reference) do
      %{std_offset: std, dst_offset: dst} when is_integer(std) and is_integer(dst) ->
        if type == :daylight, do: dst, else: std

      _no_named_offsets ->
        if type == :daylight,
          do: reference.utc_offset + daylight_saving(nearby),
          else: reference.utc_offset
    end
  end

  defp daylight_saving(readings) do
    case readings |> Enum.map(& &1.std_offset) |> Enum.max(fn -> 0 end) do
      saving when saving > 0 -> saving
      _no_saving -> 3600
    end
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
  @spec iso_format(map(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def iso_format(datetime, options \\ [])

  def iso_format(datetime, options) when is_keyword_list(options) do
    format = Keyword.get(options, :format, :long)
    type = Keyword.get(options, :type, :basic)
    z_for_zero = Keyword.get(options, :z_for_zero, true)

    case total_offset(datetime) do
      nil ->
        {:error,
         Localize.Utils.Helpers.invalid_value(datetime, "a map with an integer :utc_offset")}

      _offset when format not in [:short, :long, :full] ->
        {:error,
         Localize.InvalidValueError.exception(
           value: format,
           expected: :format,
           allowed_values: [:short, :long, :full]
         )}

      0 when z_for_zero not in [false, nil] ->
        {:ok, "Z"}

      offset ->
        {:ok, format_iso_offset(offset, format, type)}
    end
  end

  def iso_format(_datetime, options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

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

  # Where the zone's metazone period names which offset is standard time
  # and which daylight (TR35's `stdOffset` and `dstOffset`), the offset
  # decides, the time zone database's flag being unreliable there:
  # `Europe/Dublin`'s summer time is daylight time to CLDR, whatever
  # `std_offset` says, and `America/Winnipeg`'s -05:00 is Central Daylight
  # Time. Elsewhere the flag decides.
  defp specific_type(:specific, time_zone, datetime) do
    with %{std_offset: std, dst_offset: dst} when is_integer(std) and is_integer(dst) <-
           metazone_period(time_zone, datetime),
         offset when is_integer(offset) <- total_offset(datetime) do
      cond do
        offset == dst -> :daylight
        offset == std -> :standard
        true -> resolve_type(:specific, datetime)
      end
    else
      _no_offsets -> resolve_type(:specific, datetime)
    end
  end

  defp specific_type(type, _time_zone, _datetime), do: type

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

    # TR35: the long format always has two-digit hours and minutes; the
    # short format has hours without a leading zero and two-digit minutes
    # only when they are non-zero, so "GMT-8" and "GMT+5:30". The format
    # decides the hour's digits, not the pattern's hour field: `cs`, `fi`
    # and `vmw` write it `H` ("+H:mm", "+H.mm"), and their long format is
    # "GMT+05:30" and "UTC+05.30" all the same, as ICU writes it.
    {sign_format, hour_digits} =
      case format do
        :short when minutes == 0 ->
          {hour_field_pattern(sign_format), Integer.to_string(hours)}

        :short ->
          {sign_format, Integer.to_string(hours)}

        _long ->
          {sign_format, pad(hours, 2)}
      end

    sign_format
    |> String.replace(~r/H+/, hour_digits, global: false)
    |> String.replace("mm", pad(minutes, 2))
  end

  # The short format of a whole hour is the pattern up to its hour field, as
  # ICU's `truncateOffsetPattern` derives it: the minutes, their separator and
  # anything after them go. That drops the left-to-right mark `he` ends its
  # negative pattern with, which its GMT format then repeated after the
  # offset. A pattern without minutes or hours is kept as it is.
  defp hour_field_pattern(sign_format) do
    with {minutes_at, _length} <- :binary.match(sign_format, "mm"),
         [_ | _] = hours <- :binary.matches(binary_part(sign_format, 0, minutes_at), "H") do
      {hour_at, _length} = List.last(hours)
      binary_part(sign_format, 0, hour_at + 1)
    else
      _no_minutes_or_hours -> sign_format
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

  def exemplar_city(iana_id, locale, options)
      when is_binary(iana_id) and is_keyword_list(options) do
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

  def exemplar_city(_iana_id, _locale, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  def exemplar_city(iana_id, _locale, _options),
    do: {:error, Localize.UnknownTimezoneError.exception(timezone: iana_id)}

  defp derived_exemplar_city(iana_id, options) do
    with true <- Keyword.get(options, :derive, true),
         city when is_binary(city) <- derive_city_from_id(iana_id) do
      {:ok, city}
    else
      _no_city -> {:error, Localize.UnknownTimezoneError.exception(timezone: iana_id)}
    end
  end

  defp find_exemplar_city(iana_id, zone) do
    with [_ | _] = keys <- zone_path(iana_id),
         # A zone CLDR gives no exemplar city for carries only its long and
         # short names.
         %{exemplar_city: city_name} <- get_in(zone, keys) do
      city_name
    else
      _no_city -> nil
    end
  end

  # Where a zone's data is in a locale's time zone names, structured as
  # %{america: %{los_angeles: %{type: :zone, exemplar_city: "Los Angeles"}}}.
  # A three-part identifier — "America/Indiana/Knox" — nests one level deeper,
  # and CLDR keys that leaf by string rather than by atom. `nil` for a name
  # of another shape, or one with a part that is no key of the data.
  defp zone_path(zone_id) do
    keys =
      case String.split(zone_id, "/") do
        [region, city] -> [zone_key(region), zone_key(city)]
        [region, group, city] -> [zone_key(region), zone_key(group), leaf_key(city)]
        _other -> [nil]
      end

    if Enum.all?(keys, & &1), do: keys
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

  # A part of a zone's name as the locale data keys it: in snake case, as the
  # data build writes every key, so "Blanc-Sablon" is `blanc_sablon`,
  # "DumontDUrville" `dumont_d_urville` and "McMurdo" `mc_murdo`.
  defp leaf_key(component) do
    component
    |> String.replace(" ", "_")
    |> Localize.Utils.Map.underscore()
  end

  # "America/Los_Angeles" -> "Los Angeles", "America/Argentina/Salta" -> "Salta"
  @doc false
  # The exemplar city the `VVV` symbol renders: CLDR's, else one derived from
  # the identifier as `exemplar_city/3` derives it, except for an `Etc/` zone.
  # That names an offset or a time scale rather than a place, so TR35 falls
  # back to the exemplar city of `Etc/Unknown`, "Unknown Location" in `en`,
  # as ICU renders `Etc/UTC`.
  @spec location_exemplar_city(String.t(), Localize.locale()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def location_exemplar_city(iana_id, locale) when is_binary(iana_id) do
    canonical = Map.get(@zone_canonical_names, iana_id, iana_id)
    exemplar_city(iana_id, locale, derive: not String.starts_with?(canonical, "Etc/"))
  end

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

  * `locale` is any locale returned by `Localize.all_locale_ids/0` or a
    `t:Localize.LanguageTag.t/0`. The default is `Localize.get_locale/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:derive` is a boolean determining whether an exemplar city may be
    derived from the timezone identifier when CLDR names none. The
    default is `true`.

  ### Returns

  * `{:ok, place_name}` where the place is a country or a city. A country
    the locale has no name for is its code, as TR35 composes a location.

  * `{:error, exception}` if the locale is unknown, or if no city can be
    found or derived for the timezone.

  ### Examples

      iex> Localize.DateTime.Timezone.location_name("Europe/Rome", :en)
      {:ok, "Italy"}

      iex> Localize.DateTime.Timezone.location_name("Europe/Berlin", :en)
      {:ok, "Germany"}

      iex> Localize.DateTime.Timezone.location_name("Australia/Adelaide", :en)
      {:ok, "Adelaide"}

      iex> Localize.DateTime.Timezone.location_name("America/Havana", :su)
      {:ok, "CU"}

  """
  @spec location_name(String.t(), Localize.locale(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def location_name(iana_id, locale \\ Localize.get_locale(), options \\ [])

  def location_name(iana_id, locale, options)
      when is_binary(iana_id) and is_keyword_list(options) do
    canonical = Map.get(@zone_canonical_names, iana_id, iana_id)

    case naming_territory(canonical) do
      nil -> exemplar_city(iana_id, locale, options)
      territory -> territory_name(territory, locale)
    end
  end

  def location_name(_iana_id, _locale, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

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

  # A country the locale does not name is its code, as TR35's composition
  # has it and its example writes Havana's zone: "Hora de CU".
  defp territory_name(territory, locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      names =
        case Localize.Locale.get(language_tag, [:territories]) do
          {:ok, %{} = territories} -> Map.get(territories, territory)
          _no_territories -> nil
        end

      {:ok, location_country_name(names) || Atom.to_string(territory)}
    end
  end

  # The name the location format writes a country by: TR35 prefers the
  # short name where the locale has one.
  defp location_country_name(%{short: name}) when is_binary(name), do: name
  defp location_country_name(%{standard: name}) when is_binary(name), do: name
  defp location_country_name(_no_name), do: nil

  @doc """
  Returns the generic location format for a timezone.

  This is the `V` format symbol at width four: the zone's location
  substituted into the locale's generic `regionFormat`, so
  `Australia/Adelaide` in `en` is "Adelaide Time".

  ### Arguments

  * `iana_id` is an IANA timezone name such as `"Australia/Adelaide"`.

  * `locale` is any locale returned by `Localize.all_locale_ids/0` or a
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
