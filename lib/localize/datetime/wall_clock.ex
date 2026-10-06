defmodule Localize.DateTime.WallClock do
  @moduledoc false

  # What a clock reads where a date-time is, and when a clock there reads a
  # given time. Relative time and durations measure two date-times in time
  # zones on one wall clock, that of one of the two: the other is moved to
  # it, days and longer periods are counted on it, and a wall-clock time
  # between the two is resolved in its time zone, where the clocks can skip
  # an hour or repeat one.
  #
  # A time zone is known through Elixir's time zone database
  # (`Calendar.get_time_zone_database/0`). Localize brings none, so without
  # one that knows the zone a date-time keeps the UTC offset it carries.

  @typedoc false
  @type zone :: {Calendar.time_zone(), offset :: integer(), Calendar.time_zone_database()} | nil

  @doc false
  # A date-time built by hand need not hold what a moment is counted from:
  # its offsets from UTC, in seconds, and its time zone.
  @spec validate(term()) :: :ok | {:error, Exception.t()}
  def validate(%DateTime{utc_offset: utc_offset, std_offset: std_offset, time_zone: time_zone})
      when is_integer(utc_offset) and is_integer(std_offset) and is_binary(time_zone),
      do: :ok

  def validate(datetime) do
    {:error,
     Localize.InvalidValueError.exception(
       value: datetime,
       expected: "a date and a time in a time zone, with its offsets from UTC"
     )}
  end

  @doc false
  # A date-time's wall clock where `place` is: shifted into its time zone by
  # the time zone database, or, for a fixed offset or where no database can,
  # taken to its offset.
  @spec at_place_of(DateTime.t(), DateTime.t()) :: NaiveDateTime.t()
  def at_place_of(%DateTime{} = datetime, %DateTime{} = place) do
    shifted =
      if fixed_offset?(place),
        do: :fixed_offset,
        else: DateTime.shift_zone(datetime, place.time_zone, Calendar.get_time_zone_database())

    case shifted do
      {:ok, there} -> DateTime.to_naive(there)
      _no_shift -> at_offset(datetime, offset(place))
    end
  end

  @doc false
  # A date-time's clock at a UTC offset, in seconds.
  @spec at_offset(DateTime.t(), integer()) :: NaiveDateTime.t()
  def at_offset(%DateTime{} = datetime, offset) do
    NaiveDateTime.add(DateTime.to_naive(datetime), offset - offset(datetime))
  end

  @doc false
  # A fixed offset's time zone is the offset itself, "-05:00", as parsing a
  # localized GMT format gives it (`Localize.DateTime.Timezone.offset_zone/1`).
  # One under `Etc/UTC` with an offset, as it was carried and as a caller
  # may still give it, is a fixed offset too.
  @spec fixed_offset?(DateTime.t()) :: boolean()
  def fixed_offset?(%DateTime{time_zone: "Etc/UTC"} = datetime), do: offset(datetime) != 0

  def fixed_offset?(%DateTime{time_zone: time_zone}),
    do: match?({:ok, _offset}, Localize.DateTime.Timezone.zone_offset(time_zone))

  @doc false
  # A date-time's offset from UTC, in seconds.
  @spec offset(DateTime.t()) :: integer()
  def offset(%DateTime{utc_offset: utc_offset, std_offset: std_offset})
      when is_integer(utc_offset) and is_integer(std_offset),
      do: utc_offset + std_offset

  @doc false
  # The time zone a wall-clock time near a date-time is resolved in, with the
  # date-time's own offset: `nil` for a fixed offset, where every wall-clock
  # time is at that offset.
  @spec zone(DateTime.t()) :: zone()
  def zone(%DateTime{} = datetime) do
    if fixed_offset?(datetime),
      do: nil,
      else: {datetime.time_zone, offset(datetime), Calendar.get_time_zone_database()}
  end

  @doc false
  # The UTC offset at which a time zone's clocks read `wall`, resolved as RFC
  # 5545 and ECMA-262 Temporal resolve a local time: a time the clocks repeat
  # at its first occurrence, and a time they skip at the offset before the
  # gap. An error where the database cannot resolve the time.
  @spec offset_at(NaiveDateTime.t(), Calendar.time_zone(), Calendar.time_zone_database()) ::
          {:ok, integer()} | {:error, term()}
  def offset_at(%NaiveDateTime{} = wall, time_zone, database) do
    case DateTime.from_naive(wall, time_zone, database) do
      {:ok, datetime} -> {:ok, offset(datetime)}
      {:ambiguous, first, _second} -> {:ok, offset(first)}
      {:gap, before, _after} -> {:ok, offset(before)}
      {:error, _reason} = error -> error
    end
  end
end
