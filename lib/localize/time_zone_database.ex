defmodule Localize.TimeZoneDatabase do
  @moduledoc """
  A time zone database that knows the time zone of a fixed offset, such as `"-05:00"`, and asks another database for every other zone.

  Localize reads a date and time written with an offset, "10:00 GMT-5" or "2026-06-16T10:00:00-05:00", as a `t:DateTime.t/0` whose time zone is the offset itself, `"-05:00"`, as ECMA-262 Temporal and RFC 9557 name the zone of a fixed offset. The functions of `DateTime` that need only a value's own offsets work with it as it is: `DateTime.to_unix/2`, `DateTime.to_iso8601/3`, `DateTime.compare/2`, `DateTime.diff/3` and `DateTime.shift_zone/3` into another zone. The ones that look the value's own zone up in a time zone database, `DateTime.add/4`, `DateTime.shift/3` and `DateTime.from_naive/3`, return an error, or raise, with a database that knows IANA's zones alone.

  This database answers for the zone of a fixed offset, whose clock never changes, and passes every other zone to the database it wraps. Configure it as Elixir's database, and name the one it wraps:

  ```elixir
  config :elixir, :time_zone_database, Localize.TimeZoneDatabase
  config :localize, :time_zone_database, Tz.TimeZoneDatabase
  ```

  Without `:time_zone_database` it wraps `Tz.TimeZoneDatabase` or `Tzdata.TimeZoneDatabase`, whichever is loaded, and else Elixir's own database of UTC alone. It may also be given to one call, as `DateTime.add(datetime, 1, :hour, Localize.TimeZoneDatabase)`.

  """

  @behaviour Calendar.TimeZoneDatabase

  alias Localize.DateTime.Timezone

  @known_databases [Tz.TimeZoneDatabase, Tzdata.TimeZoneDatabase]

  @doc """
  Returns the time zone database this one asks about a zone that is no fixed offset.

  ### Returns

  * The module named by `config :localize, :time_zone_database`, or

  * `Tz.TimeZoneDatabase` or `Tzdata.TimeZoneDatabase`, whichever is loaded, or

  * `Calendar.UTCOnlyTimeZoneDatabase`.

  ### Examples

      iex> Localize.TimeZoneDatabase.wrapped()
      Tz.TimeZoneDatabase

  """
  @spec wrapped() :: module()
  def wrapped do
    case Application.get_env(:localize, :time_zone_database) do
      database when is_atom(database) and database not in [nil, __MODULE__] ->
        database

      _none_configured ->
        Enum.find(@known_databases, Calendar.UTCOnlyTimeZoneDatabase, &Code.ensure_loaded?/1)
    end
  end

  @doc """
  Returns the offset of a time zone that is a fixed offset's.

  ### Arguments

  * `time_zone` is a time zone, as a `t:DateTime.t/0` holds one.

  ### Returns

  * `{:ok, offset}`, the offset from UTC in seconds, where the time zone is an offset as ISO 8601 writes one between colons, such as `"+05:30"`, `"-05:00"` or `"-07:52:58"`, or

  * `:error` for any other time zone, `"Etc/UTC"` and `"America/New_York"` among them, and for anything that is no time zone.

  ### Examples

      iex> Localize.TimeZoneDatabase.fixed_offset("+05:30")
      {:ok, 19800}

      iex> Localize.TimeZoneDatabase.fixed_offset("America/New_York")
      :error

  """
  @spec fixed_offset(term()) :: {:ok, integer()} | :error
  defdelegate fixed_offset(time_zone), to: Timezone, as: :zone_offset

  @doc """
  Returns the time zone of a fixed offset.

  ### Arguments

  * `offset` is an offset from UTC in seconds.

  ### Returns

  * The offset as ISO 8601 writes it between colons, with its seconds where it has them, which is the time zone of a `t:DateTime.t/0` at that offset. No offset at all is `"Etc/UTC"`.

  ### Examples

      iex> Localize.TimeZoneDatabase.fixed_offset_zone(-18000)
      "-05:00"

      iex> Localize.TimeZoneDatabase.fixed_offset_zone(0)
      "Etc/UTC"

  """
  @spec fixed_offset_zone(integer()) :: String.t()
  def fixed_offset_zone(0), do: "Etc/UTC"
  def fixed_offset_zone(offset) when is_integer(offset), do: Timezone.offset_zone(offset)

  @doc """
  Returns the period of a time zone at a moment, given as ISO days in UTC.

  ### Arguments

  * `iso_days` is the moment, as `t:Calendar.iso_days/0`.

  * `time_zone` is a time zone: a fixed offset's, such as `"+05:30"`, or any the wrapped database knows.

  ### Returns

  * `{:ok, period}`, the offset itself for a fixed offset's zone, or

  * whatever the wrapped database returns for any other zone.

  ### Examples

      iex> Localize.TimeZoneDatabase.time_zone_period_from_utc_iso_days({739_418, {0, 86_400}}, "+05:30")
      {:ok, %{utc_offset: 19800, std_offset: 0, zone_abbr: "+05:30"}}

  """
  @impl Calendar.TimeZoneDatabase
  def time_zone_period_from_utc_iso_days(iso_days, time_zone) do
    case Timezone.zone_offset(time_zone) do
      {:ok, offset} -> {:ok, period(offset, time_zone)}
      :error -> wrapped().time_zone_period_from_utc_iso_days(iso_days, time_zone)
    end
  end

  @doc """
  Returns the period, or periods, of a time zone at a wall-clock time.

  ### Arguments

  * `naive_datetime` is the wall-clock time, a `t:Calendar.naive_datetime/0`.

  * `time_zone` is a time zone: a fixed offset's, such as `"-05:00"`, or any the wrapped database knows.

  ### Returns

  * `{:ok, period}`, the offset itself for a fixed offset's zone, whose clock neither skips a time nor repeats one, or

  * whatever the wrapped database returns for any other zone.

  ### Examples

      iex> Localize.TimeZoneDatabase.time_zone_periods_from_wall_datetime(~N[2026-06-16 10:00:00], "-05:00")
      {:ok, %{utc_offset: -18000, std_offset: 0, zone_abbr: "-05:00"}}

  """
  @impl Calendar.TimeZoneDatabase
  def time_zone_periods_from_wall_datetime(naive_datetime, time_zone) do
    case Timezone.zone_offset(time_zone) do
      {:ok, offset} -> {:ok, period(offset, time_zone)}
      :error -> wrapped().time_zone_periods_from_wall_datetime(naive_datetime, time_zone)
    end
  end

  defp period(offset, time_zone),
    do: %{utc_offset: offset, std_offset: 0, zone_abbr: time_zone}
end
