defmodule Localize.Duration do
  @moduledoc """
  Functions to create and format durations — the difference
  between two dates, times, or datetimes expressed in calendar
  units.

  A duration is represented as years, months, days, hours,
  minutes, seconds, and microseconds. This is useful for
  producing human-readable strings like "11 months, 30 days"
  or numeric patterns like "37:48:12".

  ## Creating durations

  * `new/2` — calculates the duration between two dates, times,
    or datetimes.

  * `new_from_seconds/1` — creates a duration from a number of
    seconds.

  ## Formatting durations

  * `to_string/2` — formats a duration as a localized string
    using unit names (e.g., "11 months, 30 days") via
    `Localize.Unit` and `Localize.List`.

  * `to_time_string/2` — formats the time portion of a duration
    using a pattern like `"hh:mm:ss"`. Hours are unbounded
    (e.g., "37:48:12" for 37 hours).

  """

  import Kernel, except: [to_string: 1]
  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  @struct_list [year: 0, month: 0, day: 0, hour: 0, minute: 0, second: 0, microsecond: {0, 6}]
  @keys Keyword.keys(@struct_list)
  defstruct @struct_list

  @display_values [:auto, :always]
  @format_values [:long, :short, :narrow]

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
  Calculates the calendar duration between two dates, times, or datetimes.

  The years, months and days are counted by the values' own calendar, never from their fields: the whole months from `from` to `to`, then the days left after them, with the whole years taken out of the months. A day of the month is brought into a shorter month, so 31 January to 29 February is one month. The duration is the span that `Date.shift/2` adds to `from` to reach `to`. Between two datetimes the time between their times of day is added, and where `to`'s time of day is the earlier of the two, the dates are counted to the day before `to`.

  ### Arguments

  * `from` is a date, time, or datetime representing the start.

  * `to` is a date, time, or datetime representing the end. It is in the same calendar as `from` and is not earlier.

  ### Returns

  * `{:ok, duration}` where `duration` is a `t:t/0` struct.

  * `{:error, exception}` if the arguments are incompatible, `to` is earlier than `from`, or a value is not one its calendar has. A calendar that cannot be asked for its arithmetic is a `t:Localize.UnknownCalendarError.t/0`.

  ### Examples

      iex> {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2019-12-31])
      iex> d.month
      11

      iex> {:ok, d} = Localize.Duration.new(~D[2023-01-14], ~D[2023-07-13])
      iex> {d.month, d.day}
      {5, 29}

      iex> {:ok, d} = Localize.Duration.new(~T[10:00:00], ~T[12:30:45])
      iex> {d.hour, d.minute, d.second}
      {2, 30, 45}

  """
  @spec new(from :: date_or_time_or_datetime(), to :: date_or_time_or_datetime()) ::
          {:ok, t()} | {:error, Exception.t() | atom()}
  @dialyzer {:nowarn_function, new: 2}

  def new(
        %{year: _, month: _, day: _, hour: _, minute: _, second: _} = from,
        %{year: _, month: _, day: _, hour: _, minute: _, second: _} = to
      ) do
    with :ok <- confirm_fields(from),
         :ok <- confirm_fields(to),
         :ok <- confirm_same_calendar(from, to),
         :ok <- Localize.Calendar.validate_value(from),
         :ok <- Localize.Calendar.validate_value(to),
         :ok <- confirm_same_time_zone(from, to),
         :ok <- confirm_date_order(from, to) do
      datetime_duration(from, to, time_duration(from, to))
    end
  end

  def new(
        %{year: _, month: _, day: _} = from,
        %{year: _, month: _, day: _} = to
      ) do
    with {:ok, from_dt} <- cast_to_datetime(from),
         {:ok, to_dt} <- cast_to_datetime(to) do
      new(from_dt, to_dt)
    end
  end

  def new(
        %{hour: _, minute: _, second: _} = from,
        %{hour: _, minute: _, second: _} = to
      ) do
    with {:ok, from_dt} <- cast_to_datetime(from),
         {:ok, to_dt} <- cast_to_datetime(to),
         :ok <- confirm_order(DateTime.compare(from_dt, to_dt), from, to) do
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

  def new(from, to) do
    {:error,
     Localize.InvalidValueError.exception(
       value: {from, to},
       expected: "two dates, two times or two datetimes"
     )}
  end

  @doc """
  Calculates the calendar duration of a `t:Date.Range.t/0`.

  Equivalent to `new(range.first, range.last)`.

  ### Arguments

  * `range` is a `t:Date.Range.t/0` (e.g., `Date.range/2`).

  ### Returns

  * `{:ok, duration}` where `duration` is a `t:t/0` struct.

  * `{:error, exception}` if the range endpoints are incompatible.

  ### Examples

      iex> {:ok, d} = Localize.Duration.new(Date.range(~D[2019-01-01], ~D[2019-12-31]))
      iex> d.month
      11

  """
  @spec new(Date.Range.t()) :: {:ok, t()} | {:error, Exception.t() | atom()}
  def new(%Date.Range{first: first, last: last}) do
    new(first, last)
  end

  def new(range), do: {:error, Localize.Utils.Helpers.invalid_value(range, "a Date.Range")}

  @doc """
  Same as `new/2` but raises on error.

  ### Arguments

  * `from` is a date, time, or datetime representing the start.

  * `to` is a date, time, or datetime representing the end.

  ### Returns

  * A `t:t/0` duration struct.

  * Raises an exception if the arguments are incompatible.

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

  * `{:error, exception}` if `seconds` is not a number.

  ### Examples

      iex> d = Localize.Duration.new_from_seconds(136_092)
      iex> {d.hour, d.minute, d.second}
      {37, 48, 12}

      iex> d = Localize.Duration.new_from_seconds(90.5)
      iex> {d.minute, d.second}
      {1, 30}

  """
  @spec new_from_seconds(seconds :: number()) :: t() | {:error, Exception.t()}
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

  def new_from_seconds(seconds),
    do: {:error, Localize.Utils.Helpers.invalid_value(seconds, "a number of seconds")}

  # ── Formatting ──────────────────────────────────────────────────

  @doc """
  Formats a duration as a localized string using unit names.

  Non-zero duration parts are formatted as units and joined
  with the locale's unit list pattern for the requested width,
  per ECMA-402 `Intl.DurationFormat` (e.g., "11 months,
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

  * `:format` is the display width applied to every unit: one of
    `:long` ("11 months, 30 days"), `:short` ("11 mths, 30 days"),
    or `:narrow` ("11m 30d"). The default is `:long`. It also
    selects the CLDR unit list pattern that joins the parts.

  * `:display` is a keyword list of per-unit display control,
    mirroring ECMA-402's per-unit `*Display` options. Each key is
    a unit atom (`:year`, `:month`, `:day`, `:hour`, `:minute`,
    `:second`, `:microsecond`) and each value is `:auto` (omit
    the unit when zero, the default) or `:always` (render the
    unit even when zero).

  * `:formats` is a keyword list of per-unit width overrides,
    mirroring ECMA-402's per-unit width options. Each key is a
    unit atom (the same set as `:display`) and each value is
    `:long`, `:short`, or `:narrow`, overriding `:format` for
    that unit alone; units not named keep `:format`. Note the
    plural: `:format` sets the width for the whole duration,
    `:formats` overrides individual units within it.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if formatting fails.

  ### Examples

      iex> {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2019-12-31])
      iex> Localize.Duration.to_string(d, locale: :en)
      {:ok, "11 months, 30 days"}

      iex> {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2019-12-31])
      iex> Localize.Duration.to_string(d, locale: :en, format: :narrow)
      {:ok, "11m 30d"}

      iex> duration = %Localize.Duration{hour: 2}
      iex> Localize.Duration.to_string(duration, locale: :en, display: [minute: :always])
      {:ok, "2 hours, 0 minutes"}

      iex> duration = %Localize.Duration{hour: 2, minute: 30}
      iex> Localize.Duration.to_string(duration, locale: :en, formats: [hour: :narrow])
      {:ok, "2h, 30 minutes"}

  """
  @spec to_string(t(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(duration, options \\ [])

  def to_string(%__MODULE__{} = duration, options) when is_keyword_list(options) do
    except = Keyword.get(options, :except, [:microsecond])
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, :long)
    display = Keyword.get(options, :display, [])
    formats = Keyword.get(options, :formats, [])

    with :ok <- validate_per_unit(display, :display, @display_values),
         :ok <- validate_per_unit(formats, :formats, @format_values),
         :ok <- validate_except(except) do
      duration
      |> duration_units(display, except)
      |> format_units(locale, format, formats)
    end
  end

  def to_string(duration, options), do: invalid_arguments(duration, options)

  # A value that is not a duration, or options that are not a keyword list.
  defp invalid_arguments(_duration, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  defp invalid_arguments(duration, _options),
    do: {:error, Localize.Utils.Helpers.invalid_value(duration, "a Localize.Duration")}

  defp validate_except(except) when is_list(except), do: :ok

  defp validate_except(except) do
    {:error,
     Localize.InvalidValueError.exception(
       value: except,
       expected: "a list of time unit atoms",
       context: "the :except option"
     )}
  end

  defp duration_units(duration, display, except) do
    for key <- @keys,
        value = extract_microseconds(key, Map.get(duration, key)),
        include_unit?(key, value, display, except) do
      {key, Localize.Unit.new!(value, Atom.to_string(key))}
    end
  end

  # All parts are zero — format as "0 seconds"
  defp format_units([], locale, format, formats) do
    unit = Localize.Unit.new!(0, "second")
    Localize.Unit.to_string(unit, locale: locale, format: unit_format(:second, formats, format))
  end

  defp format_units(units, locale, format, formats) do
    with {:ok, formatted_parts} <- format_each(units, locale, format, formats) do
      Localize.List.to_string(formatted_parts, locale: locale, list_style: list_style(format))
    end
  end

  @doc """
  Formats a duration into typed parts, mirroring ECMA-402's `formatToParts` for `Intl.DurationFormat`.

  The parts concatenate to exactly the string `to_string/2` produces with the same options. Each duration field contributes its unit parts (from `Localize.Unit.to_parts/2`) with the numeric segments carrying a `:unit` key naming the field; the list separators between fields are `:literal` parts.

  ### Arguments

  * `duration` is a `t:t/0` struct.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * `{:ok, parts}` where `parts` is a list of `%{type: atom(), value: String.t()}` maps; numeric parts also carry a `:unit` key.

  * `{:error, exception}` if formatting fails.

  ### Examples

      iex> duration = %Localize.Duration{hour: 2, minute: 30}
      iex> Localize.Duration.to_parts(duration, locale: :en)
      {:ok,
       [
         %{type: :integer, value: "2", unit: :hour},
         %{type: :literal, value: " "},
         %{type: :unit, value: "hours"},
         %{type: :literal, value: ", "},
         %{type: :integer, value: "30", unit: :minute},
         %{type: :literal, value: " "},
         %{type: :unit, value: "minutes"}
       ]}

  """
  @spec to_parts(t(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(duration, options \\ [])

  def to_parts(%__MODULE__{} = duration, options) when is_keyword_list(options) do
    except = Keyword.get(options, :except, [:microsecond])
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, :long)
    display = Keyword.get(options, :display, [])
    formats = Keyword.get(options, :formats, [])

    with :ok <- validate_per_unit(display, :display, @display_values),
         :ok <- validate_per_unit(formats, :formats, @format_values),
         :ok <- validate_except(except) do
      duration
      |> duration_units(display, except)
      |> units_to_parts(locale, format, formats)
    end
  end

  def to_parts(duration, options), do: invalid_arguments(duration, options)

  @doc """
  Same as `to_parts/2` but raises on error.

  ### Arguments

  * `duration` is a `t:t/0` struct.

  * `options` is a keyword list of options. See `to_parts/2`.

  ### Returns

  * A list of `%{type: atom(), value: String.t()}` maps.

  ### Raises

  * Raises an exception if formatting fails.

  ### Examples

      iex> Localize.Duration.to_parts!(%Localize.Duration{hour: 2}, locale: :en) |> length()
      3

  """
  @spec to_parts!(t(), Keyword.t()) :: [%{type: atom(), value: String.t()}]
  def to_parts!(duration, options \\ []) do
    case to_parts(duration, options) do
      {:ok, parts} -> parts
      {:error, exception} -> raise exception
    end
  end

  # All parts are zero — the "0 seconds" fallback, as parts.
  defp units_to_parts([], locale, format, formats) do
    unit = Localize.Unit.new!(0, "second")

    with {:ok, parts} <-
           Localize.Unit.to_parts(unit,
             locale: locale,
             format: unit_format(:second, formats, format)
           ) do
      {:ok, tag_numeric_parts(parts, :second)}
    end
  end

  # `intersperse/2` flattens, interleaving the field part maps with
  # separator strings — each separator becomes a `:literal` part.
  defp units_to_parts(units, locale, format, formats) do
    with {:ok, parts_lists} <- parts_each(units, locale, format, formats),
         {:ok, interspersed} <-
           Localize.List.intersperse(parts_lists, locale: locale, list_style: list_style(format)) do
      parts =
        Enum.map(interspersed, fn
          separator when is_binary(separator) -> %{type: :literal, value: separator}
          part when is_map(part) -> part
        end)

      {:ok, parts}
    end
  end

  defp parts_each(units, locale, format, formats) do
    Enum.reduce_while(units, {:ok, []}, fn {key, unit}, {:ok, acc} ->
      case Localize.Unit.to_parts(unit, locale: locale, format: unit_format(key, formats, format)) do
        {:ok, parts} -> {:cont, {:ok, [tag_numeric_parts(parts, key) | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parts_lists} -> {:ok, Enum.reverse(parts_lists)}
      {:error, _} = error -> error
    end
  end

  # Numeric segments carry the duration field they belong to,
  # matching the JS `DurationFormat` part shape.
  defp tag_numeric_parts(parts, key) do
    Enum.map(parts, fn
      %{type: type} = part when type in [:literal, :unit] -> part
      part -> Map.put(part, :unit, key)
    end)
  end

  # A unit renders when its per-unit display is :always, and is
  # otherwise omitted when zero or excluded.
  defp include_unit?(key, value, display, except) do
    cond do
      Keyword.get(display, key) == :always -> true
      key in except -> false
      true -> value != 0
    end
  end

  defp unit_format(key, formats, format) do
    Keyword.get(formats, key, format)
  end

  # CLDR defines dedicated *unit* list patterns for joining measures,
  # and ECMA-402's `Intl.DurationFormat` joins duration parts with the
  # unit list style matched to the width: "3 days, 2 hr" rather than the
  # `:standard` prose conjunction "3 days and 2 hr". The width follows
  # the overall `:format` option, so a per-unit `:formats` override
  # changes only that field's unit width, not the join (as in ECMA-402).
  defp list_style(:short), do: :unit_short
  defp list_style(:narrow), do: :unit_narrow
  defp list_style(_long), do: :unit

  defp validate_per_unit(per_unit, option_name, allowed) when is_list(per_unit) do
    Enum.find_value(per_unit, :ok, fn
      {key, value} when key in @keys and value in [:auto, :always, :long, :short, :narrow] ->
        if value in allowed, do: nil, else: per_unit_error(option_name, {key, value}, allowed)

      entry ->
        per_unit_error(option_name, entry, allowed)
    end)
  end

  defp validate_per_unit(other, option_name, allowed) do
    per_unit_error(option_name, other, allowed)
  end

  defp per_unit_error(option_name, entry, allowed) do
    {:error,
     Localize.InvalidValueError.exception(
       value: entry,
       expected: option_name,
       allowed_values: allowed,
       context: "Localize.Duration.to_string/2"
     )}
  end

  # Format each unit, short-circuiting on the first error so a single
  # bad locale or unit cannot crash duration formatting with a
  # `MatchError`. Returns `{:ok, list}` only when every part formats.
  defp format_each(units, locale, format, formats) do
    Enum.reduce_while(units, {:ok, []}, fn {key, unit}, {:ok, acc} ->
      case Localize.Unit.to_string(unit,
             locale: locale,
             format: unit_format(key, formats, format)
           ) do
        {:ok, formatted} -> {:cont, {:ok, [formatted | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, Enum.reverse(parts)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Same as `to_string/2` but raises on error.

  ### Arguments

  * `duration` is a `t:t/0` struct.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * The formatted duration as a string.

  * Raises an exception if formatting fails.

  ### Examples

      iex> {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2019-12-31])
      iex> Localize.Duration.to_string!(d, locale: :en)
      "11 months, 30 days"

  """
  @spec to_string!(t(), Keyword.t()) :: String.t() | no_return()
  def to_string!(duration, options \\ []) do
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
    hours, or `"mm:ss"` for minutes and seconds only. Each of
    `h`, `m` and `s` takes one or two letters; a longer field
    formats as U+FFFD, as TR35 recommends for an invalid field.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if `duration` is not a `t:t/0` struct,
    `options` is not a keyword list or `:format` is not a string.

  ### Examples

      iex> d = Localize.Duration.new_from_seconds(136_092)
      iex> Localize.Duration.to_time_string(d)
      {:ok, "37:48:12"}

      iex> d = Localize.Duration.new_from_seconds(65)
      iex> Localize.Duration.to_time_string(d, format: "m:ss")
      {:ok, "1:05"}

  """
  @spec to_time_string(t(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_time_string(duration, options \\ [])

  def to_time_string(%__MODULE__{} = duration, options) when is_keyword_list(options) do
    options
    |> Keyword.get(:format, "hh:mm:ss")
    |> time_string(duration)
  end

  def to_time_string(duration, options), do: invalid_arguments(duration, options)

  @doc """
  Same as `to_time_string/2` but raises on error.

  ### Arguments

  * `duration` is a `t:t/0` struct.

  * `options` is a keyword list of options.

  ### Options

  See `to_time_string/2` for the supported options.

  ### Returns

  * The formatted time portion of the duration as a string.

  * Raises an exception if formatting fails.

  ### Examples

      iex> d = Localize.Duration.new_from_seconds(136_092)
      iex> Localize.Duration.to_time_string!(d)
      "37:48:12"

      iex> d = Localize.Duration.new_from_seconds(65)
      iex> Localize.Duration.to_time_string!(d, format: "m:ss")
      "1:05"

  """
  @spec to_time_string!(t(), Keyword.t()) :: String.t()
  def to_time_string!(duration, options \\ []) do
    case to_time_string(duration, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  # ── Time pattern formatting ─────────────────────────────────────

  defp time_string(format, duration) when is_binary(format),
    do: {:ok, format_time_pattern(duration, format)}

  defp time_string(format, _duration),
    do: {:error, Localize.Utils.Helpers.invalid_value(format, "a format pattern string")}

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
      # TR35's duration patterns use the date symbols `h`, `m` and `s`, which
      # take one or two letters. A longer field is invalid and formats as
      # U+FFFD, as it does in a date pattern.
      {:field, _invalid} -> "�"
      {:literal, text} -> text
    end)
    |> IO.iodata_to_binary()
  end

  # TR35 pattern quoting: text between single quotes is literal, and
  # a doubled quote is a literal quote character, so "h'h' m'm'"
  # renders as "37h 48m".
  defp chunk_pattern(graphemes), do: chunk_pattern(graphemes, [])

  defp chunk_pattern([], acc), do: Enum.reverse(acc)

  defp chunk_pattern(["'", "'" | rest], acc) do
    chunk_pattern(rest, [{:literal, "'"} | acc])
  end

  defp chunk_pattern(["'" | rest], acc) do
    {literal, rest} = quoted_span(rest, [])
    chunk_pattern(rest, [{:literal, literal} | acc])
  end

  defp chunk_pattern([c | _] = graphemes, acc) when c in ~w(h m s) do
    {field, rest} = Enum.split_while(graphemes, &(&1 == c))
    chunk_pattern(rest, [{:field, Enum.join(field)} | acc])
  end

  defp chunk_pattern(graphemes, acc) do
    {literal, rest} = Enum.split_while(graphemes, fn g -> g not in ~w(h m s ') end)
    chunk_pattern(rest, [{:literal, Enum.join(literal)} | acc])
  end

  # Consume up to the closing quote; a doubled quote inside the span
  # is a literal quote. An unterminated quote takes the rest of the
  # pattern as literal text.
  defp quoted_span(["'", "'" | rest], acc), do: quoted_span(rest, ["'" | acc])
  defp quoted_span(["'" | rest], acc), do: {acc |> Enum.reverse() |> Enum.join(), rest}
  defp quoted_span([g | rest], acc), do: quoted_span(rest, [g | acc])
  defp quoted_span([], acc), do: {acc |> Enum.reverse() |> Enum.join(), []}

  defp pad(number, width) do
    number
    |> Integer.to_string()
    |> String.pad_leading(width, "0")
  end

  # ── Private: duration calculation ───────────────────────────────

  # The duration between two date-times: the years, months and days between
  # their dates and the time between their times of day. Where the later
  # value's time of day is the earlier of the two, the dates are counted to
  # the day before it, as its calendar reaches that day, and the time runs on
  # through midnight.
  defp datetime_duration(%{calendar: calendar} = from, to, time_diff) when time_diff < 0 do
    with {:ok, day_before} <- Localize.Calendar.plus(calendar, date_fields(to), :days, -1),
         {:ok, duration} <- date_duration(calendar, date_fields(from), day_before) do
      {:ok, merge(duration, @microseconds_in_day + time_diff)}
    end
  end

  defp datetime_duration(%{calendar: calendar} = from, to, time_diff) do
    with {:ok, duration} <- date_duration(calendar, date_fields(from), date_fields(to)) do
      {:ok, merge(duration, time_diff)}
    end
  end

  defp date_fields(%{year: year, month: month, day: day}), do: {year, month, day}

  defp time_duration(from, to) do
    Time.diff(to, from, :microsecond)
  end

  # The years, months and days from one date to a later one, counted by their
  # calendar and never from the dates' fields: its `diff/3` counts whole
  # periods and its `plus/6` reaches the date a number of them on. The months
  # are the whole months between the two and the days are those left after
  # them, so the duration added to the earlier date, months and then days, is
  # the later date, as `Date.shift/2` adds it. The years are the whole years
  # between the two, and take their months out of the count: twelve a year,
  # or thirteen where a Hebrew year has them.
  defp date_duration(calendar, from, to) do
    with {:ok, months} <- Localize.Calendar.diff(calendar, from, to, :months),
         {:ok, reached} <- Localize.Calendar.plus(calendar, from, :months, months),
         {:ok, days} <- Localize.Calendar.diff(calendar, reached, to, :days),
         {:ok, years} <- Localize.Calendar.diff(calendar, from, to, :years),
         {:ok, years_on} <- Localize.Calendar.plus(calendar, from, :years, years),
         {:ok, months_of_years} <- Localize.Calendar.diff(calendar, from, years_on, :months) do
      {:ok, %__MODULE__{year: years, month: months - months_of_years, day: days}}
    end
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

  # ── Private: type casting ───────────────────────────────────────

  # A date is taken at midnight and a time on a day of its own, each at UTC,
  # so that two of a kind are measured as date-times are. A value its
  # calendar does not have is an error.
  defp cast_to_datetime(%{__struct__: _, year: _, month: _, day: _, hour: _} = dt) do
    {:ok, dt}
  end

  defp cast_to_datetime(%{__struct__: _, year: y, month: m, day: d} = date)
       when is_integer(y) and is_integer(m) and is_integer(d) do
    calendar = Map.get(date, :calendar, Calendar.ISO)

    with :ok <- Localize.Calendar.validate_value(date) do
      at_utc(NaiveDateTime.new(y, m, d, 0, 0, 0, {0, 6}, calendar), date)
    end
  end

  defp cast_to_datetime(%{__struct__: _, hour: h, minute: m, second: s} = time)
       when is_integer(h) and is_integer(m) and is_integer(s) do
    case Map.get(time, :microsecond, {0, 6}) do
      {microsecond, precision} = fraction when is_integer(microsecond) and precision in 0..6 ->
        at_utc(NaiveDateTime.new(1, 1, 1, h, m, s, fraction), time)

      _not_a_fraction ->
        at_utc({:error, :invalid_time}, time)
    end
  end

  defp cast_to_datetime(value) do
    {:error,
     Localize.InvalidValueError.exception(
       value: value,
       expected: "a date, a time or a datetime"
     )}
  end

  defp at_utc({:ok, naive}, _value), do: DateTime.from_naive(naive, "Etc/UTC")

  defp at_utc({:error, _reason}, value) do
    {:error,
     Localize.InvalidValueError.exception(
       value: value,
       expected: "a date or a time its calendar has"
     )}
  end

  # ── Private: validation ─────────────────────────────────────────

  # The fields counted are integers in a date or a time Elixir builds, which
  # a struct built by hand need not hold.
  defp confirm_fields(value) do
    whole? =
      Enum.all?([:year, :month, :day, :hour, :minute, :second], &is_integer(Map.get(value, &1)))

    fraction? =
      match?(
        {microsecond, precision} when is_integer(microsecond) and precision in 0..6,
        Map.get(value, :microsecond)
      )

    if whole? and fraction? do
      :ok
    else
      {:error,
       Localize.InvalidValueError.exception(
         value: value,
         expected: "a date and a time whose fields are integers"
       )}
    end
  end

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

  defp confirm_date_order(%{utc_offset: _} = from, %{utc_offset: _} = to) do
    confirm_order(DateTime.compare(from, to), from, to)
  end

  defp confirm_date_order(from, to) do
    confirm_order(NaiveDateTime.compare(from, to), from, to)
  end

  defp confirm_order(comparison, from, to) do
    if comparison in [:lt, :eq] do
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
