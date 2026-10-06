defmodule Localize.DateTime.Relative do
  @moduledoc """
  Formats relative times such as "3 days ago", "tomorrow" or "in 1.5 hours".

  A relative time is a number of units, or the difference between a `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0` and a baseline. The number is formatted with the locale's digits and grouping, and the plural category of the number as displayed selects the unit's pattern. `to_string/2` returns the string and `to_parts/2` the same result as typed parts.

  A difference is counted with the arithmetic of the value's own calendar, in the calendar periods between the two: the years, quarters, months, weeks and days between their dates on the value's wall clock, and the hours, minutes and seconds between them on the value's clock at its UTC offset, so an hour that a change of offset skips or repeats is counted as the time that passes. It is never a number of seconds divided by a mean length, so a month is a month of the value's calendar whatever its length, and a Hebrew leap year has thirteen of them.

  """

  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  alias Localize.DateTime.WallClock

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
  # ("yesterday", "this hour") where the locale has one. An offset within
  # one percent of those is taken for it, so 0.9999 days is still
  # "tomorrow": TR35 does not speak of an offset that is no whole number,
  # and ICU matches it so (`plans/tr35-audit.md`).
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
  # pattern ("in 0 days"), as ECMA-402 has it; TR35 does not say which
  # pattern zero takes (`plans/tr35-audit.md`).
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

      with {:ok, count} <- period_count(moment, baseline, unit, locale) do
        {:ok, {count, unit}}
      end
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
    with :ok <- WallClock.validate(relative),
         :ok <- WallClock.validate(relative_to) do
      naive = DateTime.to_naive(relative)
      zone = WallClock.zone(relative)
      at_value_offset = WallClock.at_offset(relative_to, WallClock.offset(relative))
      at_value_place = WallClock.at_place_of(relative_to, relative)

      with {:ok, moment, baseline} <- moments(naive, at_value_place),
           {:ok, _moment, elapsed} <- moments(naive, at_value_offset) do
        {:ok, %{moment | zone: zone}, %{baseline | clock: elapsed.clock, zone: zone}}
      end
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

  defp date_and_time(%NaiveDateTime{} = datetime),
    do: fields(NaiveDateTime.to_date(datetime), NaiveDateTime.to_time(datetime))

  defp date_only(%Date{} = date), do: fields(date, nil)
  defp time_only(%Time{} = time), do: fields(nil, time)

  defp fields(date, time),
    do: %{date: date, time: time, clock: %{date: date, time: time}, zone: nil}

  # ── Calendar arithmetic ───────────────────────────────────

  # The unit's periods from the baseline to the value. Years, quarters and
  # months are the calendar's own count, which an answer that is no count
  # makes an error; every other unit is counted in days and on the clock.
  defp period_count(%{date: %Date{} = to}, %{date: %Date{} = from}, :year, _locale),
    do: years_between(from, to)

  defp period_count(%{date: %Date{} = to}, %{date: %Date{} = from}, :quarter, _locale),
    do: quarters_between(from, to)

  defp period_count(%{date: %Date{} = to}, %{date: %Date{} = from}, :month, _locale),
    do: months_between(from, to)

  defp period_count(moment, baseline, unit, locale),
    do: {:ok, periods(moment, baseline, unit, locale)}

  # The number of the unit's periods from the baseline to the value: weeks
  # from the locale's first day and days, in the calendar's count of days on
  # the wall clock, and then the hours, minutes and seconds on top of the
  # days, on the clock at the value's offset. Two times have no date, and so
  # no days or longer periods between them.
  defp periods(%{date: nil}, _baseline, unit, _locale) when unit in @date_units, do: 0

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

  # Years from one date to another in their calendar: how many years on from
  # `from`'s the year `to` is in lies. A year is known by its number, and the
  # calendar says which year follows which: the Julian calendar has no year
  # 0, so AD 1 is the year after 1 BC.
  defp years_between(from, to) do
    periods_between(from, to, :years, fn _calendar, {year, _month, _day} -> {:ok, year} end)
  end

  # Quarters from one date to another in their calendar: four to each year
  # between them, and the quarters of the year between the two as the
  # calendar numbers them (its `quarter_of_year/3`).
  defp quarters_between(from, to) do
    with {:ok, years} <- years_between(from, to),
         {:ok, quarter} <- Localize.Calendar.quarter_of_year(to),
         {:ok, from_quarter} <- Localize.Calendar.quarter_of_year(from) do
      {:ok, years * 4 + quarter - from_quarter}
    end
  end

  # Months from one date to another in their calendar: how many months on
  # from `from`'s the month `to` is in lies, so a Hebrew leap year has
  # thirteen and a week calendar's months are its periods of weeks, which its
  # week field does not count. A month is known by its `month_of_year/3`
  # alone, as a year can turn within one: a Julian year reckoned from 25
  # March begins part-way through March.
  defp months_between(from, to), do: periods_between(from, to, :months, &month_of_year/2)

  defp month_of_year(calendar, {year, month, day}) do
    Localize.Calendar.ask(calendar, :month_of_year, [year, month, day], "a month of the year", fn
      {month, :leap} -> is_integer(month)
      month -> is_integer(month)
    end)
  end

  # The periods from one date to another as their calendar counts them. Its
  # `diff/3` gives the whole periods between the two dates and its `plus/6`
  # the date that many on from `from`, which is less than one period short of
  # `to`. The two are in one period when `period` names it the same for both,
  # and `to` is otherwise in the next, as from 31 January to 1 February,
  # which no whole month separates.
  defp periods_between(from, to, part, period) do
    calendar = from.calendar
    start = {from.year, from.month, from.day}
    finish = {to.year, to.month, to.day}

    with {:ok, whole} <- Localize.Calendar.diff(calendar, start, finish, part),
         {:ok, reached} <- Localize.Calendar.plus(calendar, start, part, whole),
         {:ok, reached_period} <- period.(calendar, reached),
         {:ok, finish_period} <- period.(calendar, finish) do
      cond do
        reached_period == finish_period -> {:ok, whole}
        Localize.Calendar.compare_days(to, from) == :lt -> {:ok, whole - 1}
        true -> {:ok, whole + 1}
      end
    end
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

  defp compare_dates(moment, baseline),
    do: Localize.Calendar.compare_days(moment.date, baseline.date)

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

  # Still in the earlier's year, the later is short of the next. A month is
  # not known by its year and number alone: where a calendar's year turns
  # within a month, as a Julian year reckoned from 25 March does, the month's
  # first days and its last are a year's length apart.
  defp whole?(%{date: %{year: year}}, %{date: %{year: year}}, :year), do: false

  defp whole?(earlier, later, unit) do
    anniversary = anniversary(earlier.date, unit)
    on_or_after?(later, anniversary, earlier) and reached?(later, anniversary, earlier)
  end

  # The date one unit after `date` in its calendar: the next day, the same
  # day a week on, or the date a month or a year on as the calendar shifts
  # it (its `shift_date/4`, through `Date.shift/2`): the same day of the next
  # month, clamped to that month's days as the calendar clamps it, or of the
  # month of
  # the same name next year, as a lunisolar calendar keeps it, Nisan being
  # the eighth month of a Hebrew leap year and the seventh of an ordinary one.
  defp anniversary(date, :day), do: Date.add(date, 1)
  defp anniversary(date, :week), do: Date.add(date, 7)
  defp anniversary(date, :month), do: Date.shift(date, month: 1)
  defp anniversary(date, :year), do: Date.shift(date, year: 1)

  defp on_or_after?(later, date, earlier) do
    case Localize.Calendar.compare_days(later.date, date) do
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
         {:ok, resolved} <- WallClock.offset_at(wall, time_zone, database),
         {:ok, later_clock} <- NaiveDateTime.new(later.clock.date, later.clock.time) do
      NaiveDateTime.compare(NaiveDateTime.add(wall, offset - resolved), later_clock) != :gt
    else
      _unresolved -> true
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
