defmodule Localize.Duration do
  @moduledoc """
  Functions to create and format durations — the difference
  between two dates, times, or datetimes expressed in calendar
  units.

  A duration is represented as years, months, days, hours,
  minutes, seconds, and microseconds. This is useful for
  producing human-readable strings like "11 months and 30 days"
  or numeric patterns like "37:48:12".

  ## Creating durations

  * `new/2` — calculates the duration between two dates, times,
    or datetimes.

  * `new_from_seconds/1` — creates a duration from a number of
    seconds.

  ## Formatting durations

  * `to_string/2` — formats a duration as a localized string
    using unit names (e.g., "11 months and 30 days") via
    `Localize.Unit` and `Localize.List`.

  * `to_time_string/2` — formats the time portion of a duration
    using a pattern like `"hh:mm:ss"`. Hours are unbounded
    (e.g., "37:48:12" for 37 hours).

  """

  import Kernel, except: [to_string: 1]

  @struct_list [year: 0, month: 0, day: 0, hour: 0, minute: 0, second: 0, microsecond: {0, 6}]
  @keys Keyword.keys(@struct_list)
  defstruct @struct_list

  @typedoc "Duration in calendar units."
  @type t :: %__MODULE__{
          year: non_neg_integer(),
          month: non_neg_integer(),
          day: non_neg_integer(),
          hour: non_neg_integer(),
          minute: non_neg_integer(),
          second: non_neg_integer(),
          microsecond: {integer(), 1..6}
        }

  @typedoc "A date, time, naive datetime, or datetime."
  @type date_or_time_or_datetime ::
          Calendar.date()
          | Calendar.time()
          | Calendar.datetime()
          | Calendar.naive_datetime()

  @microseconds_in_second 1_000_000
  @microseconds_in_day 86_400_000_000

  # ── Creating durations ──────────────────────────────────────────

  @doc """
  Calculates the calendar duration between two dates, times, or
  datetimes.

  ### Arguments

  * `from` is a date, time, or datetime representing the start.

  * `to` is a date, time, or datetime representing the end.

  ### Returns

  * `{:ok, duration}` where `duration` is a `t:t/0` struct.

  * `{:error, exception}` if the arguments are incompatible.

  ### Examples

      iex> {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2019-12-31])
      iex> d.month
      11

      iex> {:ok, d} = Localize.Duration.new(~T[10:00:00], ~T[12:30:45])
      iex> {d.hour, d.minute, d.second}
      {2, 30, 45}

  """
  @spec new(from :: date_or_time_or_datetime(), to :: date_or_time_or_datetime()) ::
          {:ok, t()} | {:error, Exception.t()}

  def new(%{__struct__: _, year: _, month: _, day: _, hour: _, minute: _, second: _} = from,
          %{__struct__: _, year: _, month: _, day: _, hour: _, minute: _, second: _} = to) do
    with :ok <- confirm_same_calendar(from, to),
         :ok <- confirm_same_time_zone(from, to),
         :ok <- confirm_date_order(from, to) do
      time_diff = time_duration(from, to)
      date_diff = date_duration(from, to)
      apply_time_diff_to_duration(date_diff, time_diff, from)
    end
  end

  def new(%{__struct__: _, year: _, month: _, day: _} = from,
          %{__struct__: _, year: _, month: _, day: _} = to) do
    with {:ok, from_dt} <- cast_to_datetime(from),
         {:ok, to_dt} <- cast_to_datetime(to) do
      new(from_dt, to_dt)
    end
  end

  def new(%{__struct__: _, hour: _, minute: _, second: _} = from,
          %{__struct__: _, hour: _, minute: _, second: _} = to) do
    with {:ok, from_dt} <- cast_to_datetime(from),
         {:ok, to_dt} <- cast_to_datetime(to) do
      time_diff = time_duration(from_dt, to_dt)
      {seconds, microseconds} = div_mod(time_diff, @microseconds_in_second)
      {minutes, seconds} = div_mod(seconds, 60)
      {hours, minutes} = div_mod(minutes, 60)

      {:ok,
       struct(__MODULE__,
         hour: hours,
         minute: minutes,
         second: seconds,
         microsecond: microsecond_precision(microseconds)
       )}
    end
  end

  def new(%Date.Range{first: first, last: last}) do
    new(first, last)
  end

  @doc """
  Same as `new/2` but raises on error.

  ### Examples

      iex> d = Localize.Duration.new!(~D[2019-01-01], ~D[2019-12-31])
      iex> d.month
      11

  """
  @spec new!(from :: date_or_time_or_datetime(), to :: date_or_time_or_datetime()) ::
          t() | no_return()
  def new!(from, to) do
    case new(from, to) do
      {:ok, duration} -> duration
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Creates a duration from a number of seconds.

  The duration will contain only hours, minutes, seconds,
  and microseconds (year/month/day will be zero).

  ### Arguments

  * `seconds` is a number of seconds (integer or float).

  ### Returns

  * A `t:t/0` struct.

  ### Examples

      iex> d = Localize.Duration.new_from_seconds(136_092)
      iex> {d.hour, d.minute, d.second}
      {37, 48, 12}

      iex> d = Localize.Duration.new_from_seconds(90.5)
      iex> {d.minute, d.second}
      {1, 30}

  """
  @spec new_from_seconds(seconds :: number()) :: t()
  def new_from_seconds(seconds) when is_number(seconds) do
    microseconds = microseconds_from_fraction(seconds)
    seconds = trunc(seconds)
    hours = div(seconds, 3600)
    remainder = rem(seconds, 3600)
    minutes = div(remainder, 60)
    seconds = rem(remainder, 60)

    %__MODULE__{
      hour: hours,
      minute: minutes,
      second: seconds,
      microsecond: microseconds
    }
  end

  # ── Formatting ──────────────────────────────────────────────────

  @doc """
  Formats a duration as a localized string using unit names.

  Non-zero duration parts are formatted as units and joined
  with the locale's list conjunction (e.g., "11 months and
  30 days").

  ### Arguments

  * `duration` is a `t:t/0` struct.

  * `options` is a keyword list of options.

  ### Options

  * `:except` is a list of time unit atoms to omit from
    the output (e.g., `[:microsecond]`). The default is
    `[:microsecond]`.

  * `:locale` is a locale identifier. The default is
    `Localize.get_locale()`.

  * `:style` is one of `:long`, `:short`, or `:narrow`.
    The default is `:long`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if formatting fails.

  ### Examples

      iex> {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2019-12-31])
      iex> Localize.Duration.to_string(d, locale: :en)
      {:ok, "11 months and 30 days"}

  """
  @spec to_string(t(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(%__MODULE__{} = duration, options \\ []) do
    except = Keyword.get(options, :except, [:microsecond])
    locale = Keyword.get(options, :locale, Localize.get_locale())
    style = Keyword.get(options, :style, :long)

    units =
      for key <- @keys,
          value = Map.get(duration, key),
          extract_microseconds(key, value) != 0 && key not in except do
        value = extract_microseconds(key, value)
        Localize.Unit.new!(value, Atom.to_string(key))
      end

    case units do
      [] ->
        # All parts are zero — format as "0 seconds"
        unit = Localize.Unit.new!(0, "second")

        with {:ok, formatted} <- Localize.Unit.to_string(unit, locale: locale, style: style) do
          {:ok, formatted}
        end

      units ->
        formatted_parts =
          Enum.map(units, fn unit ->
            {:ok, str} = Localize.Unit.to_string(unit, locale: locale, style: style)
            str
          end)

        Localize.List.to_string(formatted_parts, locale: locale, style: :and)
    end
  end

  @doc """
  Same as `to_string/2` but raises on error.

  """
  @spec to_string!(t(), Keyword.t()) :: String.t() | no_return()
  def to_string!(%__MODULE__{} = duration, options \\ []) do
    case to_string(duration, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats the time portion of a duration using a numeric
  pattern like `"hh:mm:ss"`.

  Hours are unbounded — a duration of 37 hours, 48 minutes,
  and 12 seconds formats as `"37:48:12"`.

  ### Arguments

  * `duration` is a `t:t/0` struct.

  * `options` is a keyword list of options.

  ### Options

  * `:format` is a format pattern string. The default is
    `"hh:mm:ss"`. Use `"h:mm:ss"` for no zero-padding on
    hours, or `"mm:ss"` for minutes and seconds only.

  ### Returns

  * `{:ok, formatted_string}` on success.

  ### Examples

      iex> d = Localize.Duration.new_from_seconds(136_092)
      iex> Localize.Duration.to_time_string(d)
      {:ok, "37:48:12"}

      iex> d = Localize.Duration.new_from_seconds(65)
      iex> Localize.Duration.to_time_string(d, format: "m:ss")
      {:ok, "1:05"}

  """
  @spec to_time_string(t(), Keyword.t()) :: {:ok, String.t()}
  def to_time_string(%__MODULE__{} = duration, options \\ []) do
    format = Keyword.get(options, :format, "hh:mm:ss")
    {:ok, format_time_pattern(duration, format)}
  end

  @doc """
  Same as `to_time_string/2` but raises on error.

  """
  @spec to_time_string!(t(), Keyword.t()) :: String.t()
  def to_time_string!(%__MODULE__{} = duration, options \\ []) do
    case to_time_string(duration, options) do
      {:ok, string} -> string
    end
  end

  # ── Time pattern formatting ─────────────────────────────────────

  defp format_time_pattern(duration, format) do
    format
    |> String.graphemes()
    |> chunk_pattern()
    |> Enum.map(fn
      {:field, "hh"} -> pad(duration.hour, 2)
      {:field, "h"} -> Integer.to_string(duration.hour)
      {:field, "mm"} -> pad(duration.minute, 2)
      {:field, "m"} -> Integer.to_string(duration.minute)
      {:field, "ss"} -> pad(duration.second, 2)
      {:field, "s"} -> Integer.to_string(duration.second)
      {:literal, text} -> text
    end)
    |> IO.iodata_to_binary()
  end

  defp chunk_pattern(graphemes) do
    graphemes
    |> Enum.chunk_by(fn g -> g in ~w(h m s) end)
    |> Enum.map(fn
      [c | _] = chars when c in ~w(h m s) -> {:field, Enum.join(chars)}
      chars -> {:literal, Enum.join(chars)}
    end)
  end

  defp pad(number, width) do
    number
    |> Integer.to_string()
    |> String.pad_leading(width, "0")
  end

  # ── Private: duration calculation ───────────────────────────────

  defp apply_time_diff_to_duration(date_diff, time_diff, from) do
    duration =
      if time_diff < 0 do
        back_one_day(date_diff, from)
        |> merge(@microseconds_in_day + time_diff)
      else
        date_diff |> merge(time_diff)
      end

    {:ok, duration}
  end

  defp time_duration(from, to) do
    Time.diff(to, from, :microsecond)
  end

  @doc false
  def date_duration(
        %{year: year, month: month, day: day, calendar: calendar},
        %{year: year, month: month, day: day, calendar: calendar}
      ) do
    %__MODULE__{}
  end

  def date_duration(%{calendar: calendar} = from, %{calendar: calendar} = to) do
    increment =
      if from.day > to.day do
        calendar.days_in_month(from.year, from.month)
      else
        0
      end

    {day_diff, increment} =
      if increment != 0 do
        {increment + to.day - from.day, 1}
      else
        {to.day - from.day, 0}
      end

    {month_diff, increment} =
      if from.month + increment > to.month do
        {to.month + calendar.months_in_year(to.year) - from.month - increment, 1}
      else
        {to.month - from.month - increment, 0}
      end

    year_diff = to.year - from.year - increment

    %__MODULE__{year: year_diff, month: month_diff, day: day_diff}
  end

  defp merge(duration, microseconds) do
    {seconds, microseconds} = div_mod(microseconds, @microseconds_in_second)
    {hours, minutes, seconds} = :calendar.seconds_to_time(seconds)

    duration
    |> Map.put(:hour, hours)
    |> Map.put(:minute, minutes)
    |> Map.put(:second, seconds)
    |> Map.put(:microsecond, microsecond_precision(microseconds))
  end

  defp back_one_day(%{day: 0} = date_diff, from) do
    previous_month = Integer.mod(from.month - 2, from.calendar.months_in_year(from.year)) + 1
    days_in_month = from.calendar.days_in_month(from.year, previous_month)
    back_one_month(%{date_diff | day: days_in_month})
  end

  defp back_one_day(%{day: day} = date_diff, _from) do
    %{date_diff | day: day - 1}
  end

  defp back_one_month(%{month: 0} = date_diff) do
    %{date_diff | month: 11, year: date_diff.year - 1}
  end

  defp back_one_month(%{month: month} = date_diff) do
    %{date_diff | month: month - 1}
  end

  # ── Private: type casting ───────────────────────────────────────

  defp cast_to_datetime(%{__struct__: _, year: _, month: _, day: _, hour: _} = dt) do
    {:ok, dt}
  end

  defp cast_to_datetime(%{__struct__: _, year: y, month: m, day: d, calendar: calendar}) do
    {:ok, naive} = NaiveDateTime.new(y, m, d, 0, 0, 0, {0, 6}, calendar)
    DateTime.from_naive(naive, "Etc/UTC")
  end

  defp cast_to_datetime(%{__struct__: _, year: y, month: m, day: d}) do
    {:ok, naive} = NaiveDateTime.new(y, m, d, 0, 0, 0, {0, 6})
    DateTime.from_naive(naive, "Etc/UTC")
  end

  defp cast_to_datetime(%{__struct__: _, hour: h, minute: m, second: s, microsecond: us}) do
    {:ok, naive} = NaiveDateTime.new(1, 1, 1, h, m, s, us)
    DateTime.from_naive(naive, "Etc/UTC")
  end

  defp cast_to_datetime(%{__struct__: _, hour: h, minute: m, second: s}) do
    {:ok, naive} = NaiveDateTime.new(1, 1, 1, h, m, s, {0, 6})
    DateTime.from_naive(naive, "Etc/UTC")
  end

  # ── Private: validation ─────────────────────────────────────────

  defp confirm_same_calendar(%{calendar: c}, %{calendar: c}), do: :ok

  defp confirm_same_calendar(from, to) do
    {:error,
     ArgumentError.exception(
       "The two values must use the same calendar. " <>
         "Found #{inspect(from)} and #{inspect(to)}"
     )}
  end

  defp confirm_same_time_zone(%{time_zone: zone}, %{time_zone: zone}), do: :ok
  defp confirm_same_time_zone(%{time_zone: _}, %{time_zone: _} = _to), do: :ok
  defp confirm_same_time_zone(_, _), do: :ok

  defp confirm_date_order(from, to) do
    if DateTime.compare(from, to) in [:lt, :eq] do
      :ok
    else
      {:error,
       ArgumentError.exception(
         "`from` must be earlier or equal to `to`. " <>
           "Found #{inspect(from)} and #{inspect(to)}"
       )}
    end
  end

  # ── Private: microsecond handling ───────────────────────────────

  defp extract_microseconds(:microsecond, {microseconds, _precision}), do: microseconds
  defp extract_microseconds(_key, value), do: value

  defp microseconds_from_fraction(number) when is_integer(number), do: {0, 6}

  defp microseconds_from_fraction(number) when is_float(number) do
    fraction = number - trunc(number)

    if fraction == 0.0 do
      {0, 6}
    else
      microseconds = round(fraction * @microseconds_in_second)
      microsecond_precision(microseconds)
    end
  end

  defp microsecond_precision(0), do: {0, 6}
  defp microsecond_precision(us) when us < 10, do: {us, 1}
  defp microsecond_precision(us) when us < 100, do: {us, 2}
  defp microsecond_precision(us) when us < 1_000, do: {us, 3}
  defp microsecond_precision(us) when us < 10_000, do: {us, 4}
  defp microsecond_precision(us) when us < 100_000, do: {us, 5}
  defp microsecond_precision(us), do: {us, 6}

  defp div_mod(a, b), do: {div(a, b), rem(a, b)}
end
