defmodule Localize.DateTime.Relative do
  @moduledoc """
  Formats relative times such as "3 days ago", "tomorrow" or "in 1.5 hours".

  A relative time is a number of units, or the difference between a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0` and a baseline. The number is formatted with the locale's digits and grouping, and the plural category of the number as displayed selects the unit's pattern. `to_string/2` returns the string and `to_parts/2` the same result as typed parts.

  A difference is counted with the arithmetic of the value's own calendar, in the calendar periods between the two: the years, quarters, months, weeks and days between their dates on the value's wall clock, and the hours, minutes and seconds between them on the value's clock at its UTC offset, so an hour that a change of offset skips or repeats is counted as the time that passes. It is never a number of seconds divided by a mean length, so a month is a month of the value's calendar whatever its length, and a Hebrew leap year has thirteen of them.

  """

  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  # A number of seconds has no calendar, so it is counted only in units of a
  # fixed length, largest first. A difference between two dates or times is
  # always counted with the calendar's own arithmetic, never through these.
  @fixed_units [week: 604_800, day: 86_400, hour: 3600, minute: 60, second: 1]

  @weekday_units [:mon, :tue, :wed, :thu, :fri, :sat, :sun]
  @date_units [:year, :quarter, :month, :week, :day] ++ @weekday_units
  @unit_keys Enum.sort(
               [:second, :minute, :hour, :day, :week, :month, :quarter, :year] ++ @weekday_units
             )
  @known_formats [:standard, :narrow, :short]

  @doc """
  Returns a string representing a relative time for a given
  number, date, time, or datetime.

  ### Arguments

  * `relative` is a number of `:unit`s, which may be fractional, or a number of seconds when there is no `:unit`. It may instead be a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0`, whose difference from `:relative_to` is formatted.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The number is formatted with the locale's digits and grouping, in the number system a `-u-nu-` extension names if it has one. The default is `Localize.get_locale/0`.

  * `:format` is `:standard`, `:narrow`, or `:short`. The default is `:standard`.

  * `:unit` is the time unit for formatting. One of `:second`, `:minute`, `:hour`, `:day`, `:week`, `:month`, `:quarter`, `:year`, `:mon`, `:tue`, `:wed`, `:thu`, `:fri`, `:sat` or `:sun`. A difference is the number of the unit's calendar periods from the baseline to the value: 1 February is "next month" from 31 January, and 00:01 is "in 1 hour" from 23:59 the day before. A week and a weekday unit count calendar weeks, each starting on the locale's first day of the week, so "next Monday" is the Monday of the week after the baseline's. Two times have no date, so no days or longer periods lie between them. If omitted, the unit is the largest of which a whole one lies between the two, from a year down to a day for dates and to a second for times. A whole day, week, month or year is reckoned as ECMA-262 Temporal reckons it: across a change of UTC offset, a day is whole once the wall clock is at or past its time on the next day and that time has passed, a skipped time being taken at the offset before the gap, and in a lunisolar calendar a year is whole on the month of the same name, a leap month's year on the ordinary month it doubles. A number with no unit is a number of seconds, which has no calendar: it is counted, to the nearest, in the largest of weeks, days, hours, minutes and seconds it reaches, and never in months, quarters or years.

  * `:numeric` is `:auto` or `:always`, mirroring ECMA-402's `numeric` option. With `:auto` (the default), an offset of -2 to 2 takes the unit's named form, such as "yesterday" or "tomorrow", where the locale has one. With `:always`, output is always numeric: "1 day ago" instead of "yesterday".

  * `:relative_to` is the baseline from which the difference is calculated. A `t:Date.t/0` or `t:Time.t/0` is measured against a value of its own type, a `t:NaiveDateTime.t/0` or a `t:DateTime.t/0`, a `t:NaiveDateTime.t/0` against a `t:NaiveDateTime.t/0` or a `t:DateTime.t/0`, and a `t:DateTime.t/0` against a `t:DateTime.t/0`. The baseline is converted into the value's calendar, and a `t:DateTime.t/0` baseline of a `t:DateTime.t/0` is moved into the value's time zone, so the two are compared on the value's wall clock. Any other pairing, or a baseline that cannot be converted, returns an error. The default is `DateTime.utc_now/0`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` on failure.

  ### Examples

      iex> Localize.DateTime.Relative.to_string(-1, unit: :day, locale: :en)
      {:ok, "yesterday"}

      iex> Localize.DateTime.Relative.to_string(-3, unit: :day, locale: :en)
      {:ok, "3 days ago"}

      iex> Localize.DateTime.Relative.to_string(1.5, unit: :hour, locale: :en)
      {:ok, "in 1.5 hours"}

      iex> Localize.DateTime.Relative.to_string(-1000, unit: :day, locale: :de)
      {:ok, "vor 1.000 Tagen"}

      iex> Localize.DateTime.Relative.to_string(-1, unit: :day, locale: :en, numeric: :always)
      {:ok, "1 day ago"}

      iex> Localize.DateTime.Relative.to_string(~D[2024-02-01], relative_to: ~D[2024-01-31], unit: :month, locale: :en)
      {:ok, "next month"}

  """
  @spec to_string(number() | Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_string(relative, options \\ [])

  def to_string(relative, options) when is_keyword_list(options) do
    with {:ok, parts} <- to_parts(relative, options) do
      {:ok, Enum.map_join(parts, & &1.value)}
    end
  end

  def to_string(_relative, options), do: {:error, invalid_options(options)}

  @doc """
  Same as `to_string/2` but raises on error.

  ### Arguments

  * `relative` is a number, or a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0`. See `to_string/2`.

  * `options` is a keyword list of options.

  ### Options

  * See `to_string/2` for the supported options.

  ### Returns

  * The localized relative time as a string.

  ### Raises

  * Raises an exception if the relative time cannot be formatted.

  ### Examples

      iex> Localize.DateTime.Relative.to_string!(-3, unit: :day, locale: :en)
      "3 days ago"

      iex> Localize.DateTime.Relative.to_string!(~D[2024-06-14], relative_to: ~D[2024-06-15], locale: :en)
      "yesterday"

  """
  @spec to_string!(number() | Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t(), Keyword.t()) ::
          String.t()
  def to_string!(relative, options \\ []) do
    case to_string(relative, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats a relative time into typed parts, mirroring ECMA-402's `formatToParts` for `Intl.RelativeTimeFormat`.

  The parts concatenate to exactly the string `to_string/2` produces with the same options. A named form ("yesterday") is a single `:literal` part. A pattern form places the number's parts from `Localize.Number.to_parts/2` (`:integer`, `:group`, `:decimal`, `:fraction`), each carrying a `:unit` key, between `:literal` parts, as ECMA-402 does: "in 1,000 days" is `:literal` "in ", `:integer` "1", `:group` ",", `:integer` "000" and `:literal` " days".

  ### Arguments

  * `relative` is a number, or a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0`.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * `{:ok, parts}` where `parts` is a list of `%{type: atom(), value: String.t()}` maps; the number's parts also carry a `:unit` key.

  * `{:error, exception}` if `relative` or the options are invalid.

  ### Examples

      iex> Localize.DateTime.Relative.to_parts(-1, unit: :day, locale: :en)
      {:ok, [%{type: :literal, value: "yesterday"}]}

      iex> Localize.DateTime.Relative.to_parts(1000, unit: :day, locale: :en)
      {:ok,
       [
         %{type: :literal, value: "in "},
         %{type: :integer, value: "1", unit: :day},
         %{type: :group, value: ",", unit: :day},
         %{type: :integer, value: "000", unit: :day},
         %{type: :literal, value: " days"}
       ]}

  """
  @spec to_parts(number() | Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(relative, options \\ [])

  def to_parts(relative, options) when is_keyword_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, :standard)
    unit = Keyword.get(options, :unit)
    numeric = Keyword.get(options, :numeric, :auto)
    relative_to = Keyword.get_lazy(options, :relative_to, &DateTime.utc_now/0)

    with {:ok, locale_id} <- resolve_locale_id(locale),
         {:ok, unit} <- validate_unit(unit),
         {:ok, format} <- validate_format(format),
         {:ok, numeric} <- validate_numeric(numeric),
         {:ok, {count, resolved_unit}} <- relative_count(relative, relative_to, unit, locale) do
      {:ok, relative_parts(count, resolved_unit, format, locale, locale_id, numeric)}
    end
  end

  def to_parts(_relative, options), do: {:error, invalid_options(options)}

  @doc """
  Same as `to_parts/2` but raises on error.

  ### Arguments

  * `relative` is a number, or a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0`. See `to_string/2`.

  * `options` is a keyword list of options. See `to_parts/2`.

  ### Returns

  * A list of `%{type: atom(), value: String.t()}` maps.

  ### Raises

  * Raises an exception if `relative` or the options are invalid.

  ### Examples

      iex> Localize.DateTime.Relative.to_parts!(-1, unit: :day, locale: :en)
      [%{type: :literal, value: "yesterday"}]

  """
  @spec to_parts!(number() | Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t(), Keyword.t()) ::
          [%{type: atom(), value: String.t()}]
  def to_parts!(relative, options \\ []) do
    case to_parts(relative, options) do
      {:ok, parts} -> parts
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the list of known time units.

  ### Examples

      iex> Localize.DateTime.Relative.known_units()
      [:day, :fri, :hour, :minute, :mon, :month, :quarter, :sat, :second, :sun, :thu, :tue, :wed, :week, :year]

  """
  @spec known_units() :: [atom(), ...]
  def known_units, do: @unit_keys

  # ── Formatting ────────────────────────────────────────────

  # `to_string/2` joins these parts, so the two always agree. A unit the
  # locale has no data for formats as the number alone.
  defp relative_parts(relative, unit, format, locale, locale_id, numeric) do
    with {:ok, date_fields} <- Localize.Locale.get(locale_id, [:date_fields]),
         %{} = unit_data <- get_in(date_fields, [unit, format]) do
      case named_form(relative, unit_data, numeric) do
        nil -> pattern_parts(relative, unit, unit_data, locale, locale_id)
        name -> [%{type: :literal, value: name}]
      end
    else
      _no_data -> number_parts(relative, unit, locale)
    end
  end

  # With `numeric: :auto` an offset of -2 to 2 takes the unit's named form
  # ("yesterday", "this hour") where the locale has one. ICU matches an
  # offset within one percent of those, so 0.9999 days is still "tomorrow".
  defp named_form(relative, %{relative_ordinal: %{} = names}, :auto)
       when relative > -2.1 and relative < 2.1 do
    hundredths = round(relative * 100)

    if rem(hundredths, 100) == 0 do
      Map.get(names, div(hundredths, 100))
    end
  end

  defp named_form(_relative, _unit_data, _numeric), do: nil

  # The number is formatted for the locale, and the pattern is chosen by the
  # plural category of the number as displayed: "in 1.5 days" is `:other` in
  # English and "dans 1,5 jour" `:one` in French. Zero takes the future
  # pattern ("in 0 days"), as in ECMA-402 and ICU.
  defp pattern_parts(relative, unit, unit_data, locale, locale_id) do
    direction = if relative < 0, do: :relative_past, else: :relative_future
    magnitude = abs(relative)

    with %{} = patterns <- unit_data[direction],
         {:ok, number} <- Localize.Number.to_parts(magnitude, locale: locale) do
      category =
        magnitude
        |> Localize.Number.source_number(locale: locale)
        |> Localize.Number.PluralRule.Cardinal.plural_rule(locale_id)

      case Map.get(patterns, category) || Map.get(patterns, :other) do
        nil -> number_parts(relative, unit, locale)
        pattern -> Localize.Substitution.substitute_parts([with_unit(number, unit)], pattern)
      end
    else
      _no_pattern -> number_parts(relative, unit, locale)
    end
  end

  defp number_parts(relative, unit, locale) do
    case Localize.Number.to_parts(relative, locale: locale) do
      {:ok, parts} -> with_unit(parts, unit)
      {:error, _exception} -> [%{type: :integer, value: Kernel.to_string(relative), unit: unit}]
    end
  end

  # As in ECMA-402's `formatToParts`, every part of the number carries the
  # unit.
  defp with_unit(parts, unit), do: Enum.map(parts, &Map.put(&1, :unit, unit))

  # ── Counting ───────────────────────────────────────────────

  # A number with a unit is a count of that unit, whole or fractional.
  defp relative_count(relative, _relative_to, unit, _locale)
       when is_number(relative) and not is_nil(unit) do
    {:ok, {relative, unit}}
  end

  # A number with no unit is a number of seconds. Seconds have no calendar,
  # so they are counted, to the nearest, in the largest unit of a fixed
  # length they reach: 5,000,000 seconds is "in 8 weeks". The count is
  # rounded half away from zero in integers, as a number of seconds can be
  # beyond the range of a float.
  defp relative_count(relative, _relative_to, nil, _locale) when is_number(relative) do
    seconds = trunc(relative)

    {unit, length} =
      Enum.find(@fixed_units, List.last(@fixed_units), fn {_unit, length} ->
        abs(seconds) >= length
      end)

    count = div(2 * abs(seconds) + length, 2 * length)
    {:ok, {if(seconds < 0, do: -count, else: count), unit}}
  end

  # A difference between two dates or times is counted with the calendar's
  # own arithmetic from their fields, never through a number of seconds.
  # Both calendars must answer Localize, as `Localize.Calendar` checks.
  defp relative_count(relative, relative_to, unit, locale) do
    with :ok <- Localize.Calendar.validate_value(relative),
         :ok <- Localize.Calendar.validate_value(relative_to),
         {:ok, moment, baseline} <- moments(relative, relative_to) do
      unit = unit || whole_unit(moment, baseline)
      {:ok, {periods(moment, baseline, unit, locale), unit}}
    end
  end

  # ── The two values measured ───────────────────────────────

  # The value and its baseline as the fields they are counted from: a date, a
  # time, or both. A date is measured against a date, a time against a time
  # and a date-time against a date-time, a date-time baseline giving a date or
  # a time its date or time, and a naive date-time its wall clock. The
  # baseline is taken into the value's calendar before counting. Any other
  # pairing is an error.
  #
  # `:date` and `:time` are on the value's wall clock, and the days and longer
  # periods between the two are counted from them. `:clock` holds the same
  # instant at the value's UTC offset, and the hours, minutes and seconds are
  # counted from it: where the offset changes between the two, the wall clock
  # skips or repeats an hour that no time passes through. The two differ only
  # for a date-time baseline of a date-time. `:zone` is the value's time zone,
  # in which a wall-clock time between them is resolved, for a date-time in a
  # zone whose offset can change.
  defp moments(%DateTime{} = relative, %DateTime{} = relative_to) do
    naive = DateTime.to_naive(relative)
    zone = zone(relative)

    with {:ok, moment, baseline} <- moments(naive, wall_clock(relative_to, relative)),
         {:ok, _moment, elapsed} <- moments(naive, at_offset(relative_to, offset(relative))) do
      {:ok, %{moment | zone: zone}, %{baseline | clock: elapsed.clock, zone: zone}}
    end
  end

  defp moments(%NaiveDateTime{} = relative, %NaiveDateTime{} = relative_to) do
    relative_to
    |> NaiveDateTime.convert(relative.calendar)
    |> both(relative, relative_to, &date_and_time/1)
  end

  defp moments(%NaiveDateTime{} = relative, %DateTime{} = relative_to),
    do: moments(relative, DateTime.to_naive(relative_to))

  defp moments(%Date{} = relative, %Date{} = relative_to) do
    relative_to
    |> Date.convert(relative.calendar)
    |> both(relative, relative_to, &date_only/1)
  end

  defp moments(%Date{} = relative, %NaiveDateTime{} = relative_to),
    do: moments(relative, NaiveDateTime.to_date(relative_to))

  defp moments(%Date{} = relative, %DateTime{} = relative_to),
    do: moments(relative, DateTime.to_date(relative_to))

  defp moments(%Time{} = relative, %Time{} = relative_to) do
    relative_to
    |> Time.convert(relative.calendar)
    |> both(relative, relative_to, &time_only/1)
  end

  defp moments(%Time{} = relative, %NaiveDateTime{} = relative_to),
    do: moments(relative, NaiveDateTime.to_time(relative_to))

  defp moments(%Time{} = relative, %DateTime{} = relative_to),
    do: moments(relative, DateTime.to_time(relative_to))

  defp moments(%DateTime{}, relative_to) do
    {:error, invalid_baseline(relative_to, "a DateTime")}
  end

  defp moments(%NaiveDateTime{}, relative_to) do
    {:error, invalid_baseline(relative_to, "a NaiveDateTime or DateTime")}
  end

  defp moments(%Date{}, relative_to) do
    {:error, invalid_baseline(relative_to, "a Date, NaiveDateTime or DateTime")}
  end

  defp moments(%Time{}, relative_to) do
    {:error, invalid_baseline(relative_to, "a Time, NaiveDateTime or DateTime")}
  end

  defp moments(relative, _relative_to) do
    {:error,
     Localize.InvalidValueError.exception(
       value: relative,
       expected: "an integer, float, Date, Time, NaiveDateTime or DateTime"
     )}
  end

  defp both({:ok, baseline}, relative, _relative_to, fields),
    do: {:ok, fields.(relative), fields.(baseline)}

  defp both({:error, _reason}, relative, relative_to, _fields) do
    {:error,
     invalid_baseline(relative_to, "a value convertible to #{inspect(relative.calendar)}")}
  end

  # The baseline's wall clock at the value's place: shifted into the value's
  # time zone by the time zone database, or, for a fixed offset or where no
  # database can, taken to the value's offset.
  defp wall_clock(%DateTime{} = relative_to, %DateTime{} = relative) do
    shifted =
      if fixed_offset?(relative),
        do: :fixed_offset,
        else:
          DateTime.shift_zone(relative_to, relative.time_zone, Calendar.get_time_zone_database())

    case shifted do
      {:ok, baseline} -> DateTime.to_naive(baseline)
      _no_shift -> at_offset(relative_to, offset(relative))
    end
  end

  # The baseline's clock at a UTC offset.
  defp at_offset(%DateTime{} = relative_to, offset) do
    NaiveDateTime.add(DateTime.to_naive(relative_to), offset - offset(relative_to))
  end

  # A fixed offset is carried under `Etc/UTC`, as parsing a localized GMT
  # format gives it.
  defp fixed_offset?(%DateTime{time_zone: "Etc/UTC"} = datetime), do: offset(datetime) != 0
  defp fixed_offset?(_datetime), do: false

  defp offset(%DateTime{utc_offset: utc_offset, std_offset: std_offset}),
    do: utc_offset + std_offset

  defp date_and_time(%NaiveDateTime{} = datetime),
    do: fields(NaiveDateTime.to_date(datetime), NaiveDateTime.to_time(datetime))

  defp date_only(%Date{} = date), do: fields(date, nil)
  defp time_only(%Time{} = time), do: fields(nil, time)

  defp fields(date, time),
    do: %{date: date, time: time, clock: %{date: date, time: time}, zone: nil}

  defp zone(%DateTime{} = datetime) do
    if fixed_offset?(datetime),
      do: nil,
      else: {datetime.time_zone, offset(datetime), Calendar.get_time_zone_database()}
  end

  # ── Calendar arithmetic ───────────────────────────────────

  # The number of the unit's periods from the baseline to the value, counted
  # from their fields: years, quarters and months of the value's calendar,
  # weeks from the locale's first day and days, on the wall clock, and then
  # the hours, minutes and seconds on top of the days, on the clock at the
  # value's offset. Two times have no date, and so no days or longer periods
  # between them.
  defp periods(%{date: nil}, _baseline, unit, _locale) when unit in @date_units, do: 0

  defp periods(moment, baseline, :year, _locale), do: moment.date.year - baseline.date.year

  defp periods(moment, baseline, :quarter, _locale) do
    (moment.date.year - baseline.date.year) * 4 + Date.quarter_of_year(moment.date) -
      Date.quarter_of_year(baseline.date)
  end

  defp periods(moment, baseline, :month, _locale), do: months_between(baseline.date, moment.date)
  defp periods(moment, baseline, :day, _locale), do: days(moment, baseline)
  defp periods(moment, baseline, :hour, _locale), do: hours(moment.clock, baseline.clock)
  defp periods(moment, baseline, :minute, _locale), do: minutes(moment.clock, baseline.clock)
  defp periods(moment, baseline, :second, _locale), do: seconds(moment.clock, baseline.clock)

  # A week and a weekday count calendar weeks, each starting on the locale's
  # first day of the week: "next Monday" is the Monday of the week after the
  # baseline's, so a Monday is "next Monday" from the Sunday before it in
  # `en-GB`, whose weeks start on Monday, and "this Monday" in `en-US`, whose
  # weeks start on Sunday.
  defp periods(moment, baseline, _week, locale) do
    {first_day, _min_days} = Localize.DateTime.Week.config(locale)
    div(Date.diff(week_start(moment.date, first_day), week_start(baseline.date, first_day)), 7)
  end

  defp days(%{date: nil}, _baseline), do: 0
  defp days(moment, baseline), do: Date.diff(moment.date, baseline.date)

  defp hours(clock, baseline), do: days(clock, baseline) * 24 + hour(clock) - hour(baseline)

  defp minutes(clock, baseline),
    do: hours(clock, baseline) * 60 + minute(clock) - minute(baseline)

  defp seconds(clock, baseline),
    do: minutes(clock, baseline) * 60 + second(clock) - second(baseline)

  # Months from one date to another in their calendar: how many months on
  # from `from`, as the calendar shifts a date by months (its
  # `shift_date/4`, through `Date.shift/2`), the month `to` is in, a month
  # being known by its year and its `month_of_year/3`. So a Hebrew leap year
  # has thirteen, and a week calendar's months are its periods of weeks,
  # which its week field does not count. The months the dates' month fields
  # count, which are the answer wherever the field is the month, are where
  # the search starts.
  defp months_between(from, to) do
    month = month_key(to)

    position = fn months ->
      shifted = Date.shift(from, month: months)

      cond do
        month_key(shifted) == month -> :eq
        Date.compare(shifted, to) == :lt -> :lt
        true -> :gt
      end
    end

    estimate = months_counted(from, to)

    case position.(estimate) do
      :eq -> estimate
      :lt -> bisect(position, months_above(position, estimate, 1))
      :gt -> bisect(position, months_below(position, estimate, 1))
    end
  end

  defp month_key(%{calendar: calendar, year: year, month: month, day: day}),
    do: {year, Localize.Calendar.answering(calendar).month_of_year(year, month, day)}

  # From a number of months short of the month sought, doubles the step
  # until it is reached or passed; from one past it, the same backwards.
  defp months_above(position, low, step) do
    case position.(low + step) do
      :lt -> months_above(position, low + step, step * 2)
      :eq -> {:found, low + step}
      :gt -> {low, low + step}
    end
  end

  defp months_below(position, high, step) do
    case position.(high - step) do
      :gt -> months_below(position, high - step, step * 2)
      :eq -> {:found, high - step}
      :lt -> {high - step, high}
    end
  end

  # The month sought lies between `low` months on, short of it, and `high`,
  # past it. Each month on from a date is the month after the last, so it
  # is always found before the two meet; a calendar that skips one ends
  # the search at `high`.
  defp bisect(_position, {:found, months}), do: months
  defp bisect(_position, {low, high}) when high - low <= 1, do: high

  defp bisect(position, {low, high}) do
    middle = low + div(high - low, 2)

    case position.(middle) do
      :eq -> middle
      :lt -> bisect(position, {middle, high})
      :gt -> bisect(position, {low, middle})
    end
  end

  # The months the month fields count from one date to another, the years
  # between counted by the calendar's `months_in_year/1`.
  defp months_counted(%{year: year} = from, %{year: year} = to), do: to.month - from.month

  defp months_counted(from, to) do
    if to.year > from.year,
      do: months_forward(from, to),
      else: -months_forward(to, from)
  end

  defp months_forward(from, to) do
    calendar = to.calendar

    between =
      Enum.reduce((from.year + 1)..(to.year - 1)//1, 0, fn year, months ->
        months + calendar.months_in_year(year)
      end)

    calendar.months_in_year(from.year) - from.month + between + to.month
  end

  # The first day of the week a date is in, `first_day` being 1 for Monday
  # through 7 for Sunday.
  defp week_start(date, first_day) do
    Date.add(date, -Integer.mod(Date.day_of_week(date, :monday) - first_day, 7))
  end

  defp hour(%{time: nil}), do: 0
  defp hour(%{time: time}), do: time.hour

  defp minute(%{time: nil}), do: 0
  defp minute(%{time: time}), do: time.minute

  defp second(%{time: nil}), do: 0
  defp second(%{time: time}), do: time.second

  # ── The unit chosen ────────────────────────────────────────

  # With no unit, the largest of which a whole one lies between the two, by
  # the calendar's arithmetic, counted in its periods: a date is counted in
  # days at the finest, and a time in seconds. Which of the two is the later
  # is read from the clock, as the wall clock can repeat an hour.
  defp whole_unit(moment, baseline) do
    {earlier, later} =
      if later?(moment.clock, baseline.clock), do: {baseline, moment}, else: {moment, baseline}

    finest = if is_nil(moment.time), do: :day, else: :second
    Enum.find([:year, :month, :week, :day, :hour, :minute], finest, &whole?(earlier, later, &1))
  end

  defp later?(clock, baseline) do
    case compare_dates(clock, baseline) do
      :eq -> time_of_day(clock) > time_of_day(baseline)
      order -> order == :gt
    end
  end

  defp compare_dates(%{date: nil}, _baseline), do: :eq
  defp compare_dates(moment, baseline), do: Date.compare(moment.date, baseline.date)

  # Whether a whole unit lies between two moments. Hours and minutes are read
  # from the clock. A day, week, month or year is whole as ECMA-262 Temporal's
  # `DifferenceZonedDateTime` reckons it: the later moment is at or past the
  # earlier's wall-clock time on the anniversary, the date one unit on, and,
  # in a zone whose offset can change, at or past that wall-clock time's
  # instant. So a day is not yet whole where its time recurs in a skipped
  # hour, nor where the later moment falls back to before it in a repeated
  # hour.
  defp whole?(%{date: nil}, _later, unit) when unit in [:year, :month, :week, :day], do: false

  defp whole?(earlier, later, :hour) do
    one_or_more?(hours(later.clock, earlier.clock), fn ->
      Tuple.delete_at(time_of_day(later.clock), 0) >=
        Tuple.delete_at(time_of_day(earlier.clock), 0)
    end)
  end

  defp whole?(earlier, later, :minute) do
    one_or_more?(minutes(later.clock, earlier.clock), fn ->
      {_hour, _minute, second, microsecond} = time_of_day(later.clock)
      {_hour, _minute, earlier_second, earlier_microsecond} = time_of_day(earlier.clock)
      {second, microsecond} >= {earlier_second, earlier_microsecond}
    end)
  end

  # Still in the earlier's year, or month, the later is short of the next.
  defp whole?(%{date: %{year: year}}, %{date: %{year: year}}, :year), do: false

  defp whole?(%{date: %{year: year, month: month}}, %{date: %{year: year, month: month}}, :month),
    do: false

  defp whole?(earlier, later, unit) do
    anniversary = anniversary(earlier.date, unit)
    on_or_after?(later, anniversary, earlier) and reached?(later, anniversary, earlier)
  end

  # The date one unit after `date` in its calendar: the next day, the same
  # day a week on, or the date a month or a year on as the calendar shifts
  # it (its `shift_date/4`, through `Date.shift/2`): the same day of the next
  # month, clamped to that month's days as ICU clamps it, or of the month of
  # the same name next year, as a lunisolar calendar keeps it, Nisan being
  # the eighth month of a Hebrew leap year and the seventh of an ordinary one.
  defp anniversary(date, :day), do: Date.add(date, 1)
  defp anniversary(date, :week), do: Date.add(date, 7)
  defp anniversary(date, :month), do: Date.shift(date, month: 1)
  defp anniversary(date, :year), do: Date.shift(date, year: 1)

  defp on_or_after?(later, date, earlier) do
    case Date.compare(later.date, date) do
      :gt -> true
      :eq -> time_of_day(later) >= time_of_day(earlier)
      :lt -> false
    end
  end

  # Whether the later moment is at or past the instant of the earlier's
  # wall-clock time on `date` in the value's time zone, resolved as RFC 5545
  # and Temporal resolve a local time: a repeated time at its first
  # occurrence, and a skipped time at the offset before the gap. Without a
  # zone, or where the database cannot resolve the time, the wall clock
  # alone decides.
  defp reached?(%{zone: nil}, _date, _earlier), do: true

  defp reached?(%{zone: {time_zone, offset, database}} = later, date, earlier) do
    with {:ok, wall} <- NaiveDateTime.new(date, earlier.time),
         {:ok, resolved} <- offset_at(wall, time_zone, database),
         {:ok, later_clock} <- NaiveDateTime.new(later.clock.date, later.clock.time) do
      NaiveDateTime.compare(NaiveDateTime.add(wall, offset - resolved), later_clock) != :gt
    else
      _unresolved -> true
    end
  end

  defp offset_at(wall, time_zone, database) do
    case DateTime.from_naive(wall, time_zone, database) do
      {:ok, datetime} -> {:ok, offset(datetime)}
      {:ambiguous, first, _second} -> {:ok, offset(first)}
      {:gap, before, _after} -> {:ok, offset(before)}
      {:error, _reason} = error -> error
    end
  end

  defp one_or_more?(count, _at_place?) when count > 1, do: true
  defp one_or_more?(1, at_place?), do: at_place?.()
  defp one_or_more?(_count, _at_place?), do: false

  defp time_of_day(%{time: nil}), do: {0, 0, 0, 0}

  defp time_of_day(%{time: time}) do
    {microsecond, _precision} = time.microsecond
    {time.hour, time.minute, time.second, microsecond}
  end

  defp invalid_options(options) do
    Localize.InvalidValueError.exception(value: options, expected: "a keyword list of options")
  end

  defp invalid_baseline(relative_to, expected) do
    Localize.InvalidValueError.exception(
      value: relative_to,
      expected: expected,
      context: ":relative_to"
    )
  end

  # ── Validation ─────────────────────────────────────────────

  defp validate_unit(nil), do: {:ok, nil}
  defp validate_unit(unit) when unit in @unit_keys, do: {:ok, unit}

  defp validate_unit(unit) do
    {:error,
     Localize.InvalidValueError.exception(
       value: unit,
       expected: :time_unit,
       allowed_values: @unit_keys,
       context: "Localize.DateTime.Relative"
     )}
  end

  defp validate_format(format) when format in @known_formats, do: {:ok, format}

  defp validate_format(format) do
    {:error,
     Localize.InvalidValueError.exception(
       value: format,
       expected: :format,
       allowed_values: @known_formats,
       context: "Localize.DateTime.Relative"
     )}
  end

  defp validate_numeric(numeric) when numeric in [:auto, :always], do: {:ok, numeric}

  defp validate_numeric(numeric) do
    {:error,
     Localize.InvalidValueError.exception(
       value: numeric,
       expected: :numeric,
       allowed_values: [:auto, :always],
       context: "Localize.DateTime.Relative"
     )}
  end

  defp resolve_locale_id(locale), do: Localize.Locale.cldr_locale_id_from(locale)
end
