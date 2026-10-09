defmodule Localize.Calendar.ISO do
  @moduledoc false

  # A calendar answers what a format needs to know about its dates through
  # callbacks on its own module. `Calendar.ISO` has none of the Calendrical
  # behaviour's callbacks and Calendrical may not be present, so Localize
  # answers them for it here and nowhere else, as the proleptic Gregorian
  # calendar: `Localize.Calendar.answering/1` names this module for
  # `Calendar.ISO`, and every other calendar answers for itself (user,
  # 2026-10-02: "All Calendrical behaviour callbacks must be implemented for
  # Calendar.ISO and done so in a specific, isolated, callback module"). Every
  # callback of the Calendrical behaviour is answered, as Calendrical's own
  # `Calendrical.ISO` answers it, which a Calendrical test holds this module
  # to. Every callback of the `Calendar` behaviour is passed to `Calendar.ISO`,
  # so every question Localize puts to a calendar goes to the one module.

  for {name, arity} <- Calendar.behaviour_info(:callbacks) do
    arguments = Macro.generate_arguments(arity, __MODULE__)

    @doc false
    def unquote(name)(unquote_splicing(arguments)),
      do: Calendar.ISO.unquote(name)(unquote_splicing(arguments))
  end

  # ISO 8601's weeks begin on Monday, and its week 1 holds four days of the
  # year: the weeks this module answers where a question carries no locale.
  @iso_8601_weeks {1, 4}

  @doc false
  @spec cldr_calendar_type() :: :gregorian
  def cldr_calendar_type, do: :gregorian

  @doc false
  @spec cldr_calendar_type(Calendar.year(), Calendar.month(), Calendar.day()) :: :gregorian
  def cldr_calendar_type(_year, _month, _day), do: :gregorian

  @doc false
  @spec era_calendar_type() :: :gregorian
  def era_calendar_type, do: :gregorian

  @doc false
  @spec parsing_calendar() :: Calendar.ISO
  def parsing_calendar, do: Calendar.ISO

  @doc false
  @spec month_of_year(Calendar.year(), Calendar.month(), Calendar.day()) :: Calendar.month()
  def month_of_year(_year, month, _day), do: month

  @doc false
  @spec cardinal_month(Calendar.month()) :: Calendar.month()
  def cardinal_month(month), do: month

  @doc false
  @spec days_in_week() :: 7
  def days_in_week, do: 7

  @doc false
  @spec date_to_iso_days(Calendar.year(), Calendar.month(), Calendar.day()) :: integer()
  def date_to_iso_days(year, month, day) do
    {iso_days, _day_fraction} =
      Calendar.ISO.naive_datetime_to_iso_days(year, month, day, 0, 0, 0, {0, 0})

    iso_days
  end

  @doc false
  @spec date_from_iso_days(integer()) :: {Calendar.year(), Calendar.month(), Calendar.day()}
  def date_from_iso_days(iso_days) when is_integer(iso_days) do
    {year, month, day, _hour, _minute, _second, _microsecond} =
      Calendar.ISO.naive_datetime_from_iso_days({iso_days, {0, 86_400_000_000}})

    {year, month, day}
  end

  # The year as the calendar shows it: the proleptic year, which
  # `Localize.Calendar.displayed_year/1` counts back from the era below 1.
  @doc false
  @spec calendar_year(Calendar.year(), Calendar.month(), Calendar.day()) :: Calendar.year()
  def calendar_year(year, _month, _day), do: year

  @doc false
  @spec related_gregorian_year(Calendar.year(), Calendar.month(), Calendar.day()) ::
          Calendar.year()
  def related_gregorian_year(year, _month, _day), do: year

  # The Gregorian calendar has no cycle of years, so the year is its own
  # count of years, which CLDR names no cycle for.
  @doc false
  @spec cyclic_year(Calendar.year(), Calendar.month(), Calendar.day()) :: Calendar.year()
  def cyclic_year(year, _month, _day), do: year

  @doc false
  @spec extended_year(Calendar.year(), Calendar.month(), Calendar.day()) :: Calendar.year()
  def extended_year(year, _month, _day), do: year

  # A calendar of months, its dates a year, a month and a day of the month.
  @doc false
  @spec calendar_base() :: :month
  def calendar_base, do: :month

  # ── The year's parts ───────────────────────────────────────

  # A year's periods are its months, twelve in every year.
  @doc false
  @spec periods_in_year(Calendar.year()) :: 12 | {:error, :invalid_date}
  def periods_in_year(year) when is_integer(year), do: 12
  def periods_in_year(_year), do: {:error, :invalid_date}

  # The months of a year, with no year to count them in.
  @doc false
  @spec months_in_year() :: 12
  def months_in_year, do: 12

  @doc false
  @spec days_in_year(Calendar.year()) :: 365 | 366 | {:error, :invalid_date}
  def days_in_year(year) when is_integer(year),
    do: if(Calendar.ISO.leap_year?(year), do: 366, else: 365)

  def days_in_year(_year), do: {:error, :invalid_date}

  # A month's days with no year to count them in: February's depend on it.
  @doc false
  @spec days_in_month(Calendar.month()) ::
          Calendar.day() | {:ambiguous, Range.t()} | {:error, :undefined}
  def days_in_month(2), do: {:ambiguous, 28..29}
  def days_in_month(month) when month in [4, 6, 9, 11], do: 30
  def days_in_month(month) when month in 1..12, do: 31
  def days_in_month(_month), do: {:error, :undefined}

  # ISO 8601's weeks of a year and the days of the last, always seven: 52
  # weeks, or 53 in a year that begins on a Thursday, or on a Wednesday in a
  # leap year.
  @doc false
  @spec weeks_in_year(Calendar.year()) :: {52 | 53, 7} | {:error, :invalid_date}
  def weeks_in_year(year) when is_integer(year) do
    case Date.new(year, 1, 1) do
      {:ok, january_1} ->
        january_1 = Date.to_gregorian_days(january_1)
        next_year = week_one(january_1 + days_in_year(year), @iso_8601_weeks)
        {div(next_year - week_one(january_1, @iso_8601_weeks), 7), 7}

      {:error, _reason} ->
        {:error, :invalid_date}
    end
  end

  def weeks_in_year(_year), do: {:error, :invalid_date}

  # The dates of a month and day that fall in a Gregorian year: the one day,
  # where the year has it.
  @doc false
  @spec dates_in_gregorian_year(Calendar.year(), Calendar.month(), Calendar.day()) :: [Date.t()]
  def dates_in_gregorian_year(year, month, day)
      when is_integer(year) and is_integer(month) and is_integer(day) do
    case Date.new(year, month, day) do
      {:ok, date} -> [date]
      {:error, _reason} -> []
    end
  end

  def dates_in_gregorian_year(_year, _month, _day), do: []

  # ── Periods of a year ──────────────────────────────────────

  # The days of a year, and of its halves, thirds, quarters and months: a
  # semester is six months, a quadrimester four and a quarter three, each
  # from January.
  @doc false
  @spec year(Calendar.year()) :: Date.Range.t() | {:error, :invalid_date}
  def year(year), do: months(year, 1, 12)

  @doc false
  @spec semester(Calendar.year(), pos_integer()) :: Date.Range.t() | {:error, :invalid_date}
  def semester(year, semester) when semester in 1..2,
    do: months(year, semester * 6 - 5, semester * 6)

  def semester(_year, _semester), do: {:error, :invalid_date}

  @doc false
  @spec quadrimester(Calendar.year(), pos_integer()) ::
          Date.Range.t() | {:error, :invalid_date}
  def quadrimester(year, quadrimester) when quadrimester in 1..3,
    do: months(year, quadrimester * 4 - 3, quadrimester * 4)

  def quadrimester(_year, _quadrimester), do: {:error, :invalid_date}

  @doc false
  @spec quarter(Calendar.year(), pos_integer()) :: Date.Range.t() | {:error, :invalid_date}
  def quarter(year, quarter) when quarter in 1..4,
    do: months(year, quarter * 3 - 2, quarter * 3)

  def quarter(_year, _quarter), do: {:error, :invalid_date}

  @doc false
  @spec month(Calendar.year(), Calendar.month()) :: Date.Range.t() | {:error, :invalid_date}
  def month(year, month) when month in 1..12, do: months(year, month, month)
  def month(_year, _month), do: {:error, :invalid_date}

  # ── Arithmetic ─────────────────────────────────────────────

  # The date a number of years, quarters, months, weeks or days on. A year,
  # a quarter or a month on keeps the day, brought into a shorter month
  # unless `coerce: false` asks for it as it stands: 31 January and a month
  # is 29 February 2024, and 29 February and a year 28 February 2025.
  @doc false
  @spec plus(
          Calendar.year(),
          Calendar.month(),
          Calendar.day(),
          :years | :quarters | :months | :weeks | :days,
          integer(),
          Keyword.t()
        ) :: {Calendar.year(), Calendar.month(), Calendar.day()} | {:error, :invalid_date}
  def plus(year, month, day, date_part, increment, options \\ [])

  def plus(year, month, day, date_part, increment, options)
      when is_integer(year) and month in 1..12 and is_integer(day) and is_integer(increment) do
    part_on(date_part, {year, month, day}, increment, options)
  end

  def plus(_year, _month, _day, _date_part, _increment, _options), do: {:error, :invalid_date}

  defp part_on(:years, {year, month, day}, years, options),
    do: in_month(year + years, month, day, options)

  defp part_on(:quarters, date, quarters, options), do: months_on(date, quarters * 3, options)
  defp part_on(:months, date, months, options), do: months_on(date, months, options)
  defp part_on(:weeks, date, weeks, _options), do: days_on(date, weeks * 7)
  defp part_on(:days, date, days, _options), do: days_on(date, days)
  defp part_on(_date_part, _date, _increment, _options), do: {:error, :invalid_date}

  defp months_on({year, month, day}, months, options) do
    months_from_year_0 = year * 12 + month - 1 + months

    in_month(
      Integer.floor_div(months_from_year_0, 12),
      Integer.mod(months_from_year_0, 12) + 1,
      day,
      options
    )
  end

  defp in_month(year, month, day, options) do
    if Keyword.get(options, :coerce, true),
      do: {year, month, min(day, Calendar.ISO.days_in_month(year, month))},
      else: {year, month, day}
  end

  defp days_on({year, month, day}, days) do
    case Date.new(year, month, day) do
      {:ok, date} -> date |> Date.add(days) |> Date.to_erl()
      {:error, _reason} -> {:error, :invalid_date}
    end
  end

  # The whole years, quarters, months, weeks or days from one date to
  # another: the most that `plus/6`, bringing the day into a shorter month,
  # adds to the earlier without passing the later, and negative when `to` is
  # the earlier. From 31 January 2024 it is a month to 29 February and none
  # to 28 February.
  @doc false
  @spec diff(
          {Calendar.year(), Calendar.month(), Calendar.day()},
          {Calendar.year(), Calendar.month(), Calendar.day()},
          :years | :quarters | :months | :weeks | :days
        ) :: integer() | {:error, :invalid_date}
  def diff({from_year, from_month, from_day} = from, {to_year, to_month, to_day} = to, date_part)
      when is_integer(from_year) and is_integer(from_month) and is_integer(from_day) and
             is_integer(to_year) and is_integer(to_month) and is_integer(to_day) and
             date_part in [:years, :quarters, :months, :weeks, :days] do
    with {:ok, from_date} <- Date.new(from_year, from_month, from_day),
         {:ok, to_date} <- Date.new(to_year, to_month, to_day) do
      days = Date.diff(to_date, from_date)

      if days < 0,
        do: -count(to, from, -days, date_part),
        else: count(from, to, days, date_part)
    else
      {:error, _reason} -> {:error, :invalid_date}
    end
  end

  def diff(_from, _to, _date_part), do: {:error, :invalid_date}

  # The count from an earlier date to a later one, `days` apart. The months
  # and years the fields count are one too many where the day they reach,
  # brought into the later month, is past the later date. The fields are the
  # integers `diff/3` has checked.
  defp count(_earlier, _later, days, :days) when is_integer(days), do: days
  defp count(_earlier, _later, days, :weeks), do: div(days, 7)
  defp count(earlier, later, days, :quarters), do: div(count(earlier, later, days, :months), 3)

  defp count({year, month, day}, {later_year, later_month, later_day}, _days, :months)
       when is_integer(year) and is_integer(month) and is_integer(later_year) and
              is_integer(later_month) do
    reached = min(day, Calendar.ISO.days_in_month(later_year, later_month))
    (later_year - year) * 12 + later_month - month - if(reached > later_day, do: 1, else: 0)
  end

  defp count({year, month, day}, {later_year, later_month, later_day}, _days, :years)
       when is_integer(year) and is_integer(later_year) do
    reached = {month, min(day, Calendar.ISO.days_in_month(later_year, month))}
    later_year - year - if(reached > {later_month, later_day}, do: 1, else: 0)
  end

  # ── Weeks ──────────────────────────────────────────────────

  # `Calendar.ISO` has no weeks of its own: Elixir numbers none for it. Its
  # weeks are therefore the locale's, as TR35 numbers them from the locale's
  # week data, a first day of the week (1 Monday to 7 Sunday) and the fewest
  # days of a year or a month that its week 1 holds. Localize passes that
  # data with the questions it puts for a `Calendar.ISO` date
  # (`Localize.Calendar.week_of_year/2` and its kin). The callbacks of the
  # Calendrical behaviour's shape, which carry no locale, answer ISO 8601's
  # weeks, which begin on Monday and whose week 1 holds four days: they are
  # the weeks of a week date such as "2026-W25-2".
  @typedoc false
  @type week_data :: {1..7, 1..7}

  @doc false
  @spec week_of_year(Calendar.year(), Calendar.month(), Calendar.day()) ::
          {Calendar.year(), pos_integer()} | {:error, :invalid_date}
  def week_of_year(year, month, day), do: week_of_year(year, month, day, @iso_8601_weeks)

  # The week-based year a date's week belongs to and its week of that year.
  # Week 1 of a year is its first week holding at least the fewest days of
  # it, so a week across a year's end is the last of the old year or the
  # first of the new one: with weeks from Sunday holding one day, 1 January
  # 2027, a Friday, is in week 1 of 2027, and with ISO 8601's in week 53 of
  # 2026.
  @doc false
  @spec week_of_year(Calendar.year(), Calendar.month(), Calendar.day(), week_data()) ::
          {integer(), pos_integer()} | {:error, :invalid_date}
  def week_of_year(year, month, day, week_data)
      when is_integer(year) and is_integer(month) and is_integer(day) do
    case Date.new(year, month, day) do
      {:ok, date} ->
        days = Date.to_gregorian_days(date)
        january_1 = days - Date.day_of_year(date) + 1
        this_year = week_one(january_1, week_data)
        next_year = week_one(january_1 + days_in_year(year), week_data)

        cond do
          days >= next_year ->
            {year + 1, 1}

          days >= this_year ->
            {year, week_from(this_year, days)}

          true ->
            {year - 1, week_from(week_one(january_1 - days_in_year(year - 1), week_data), days)}
        end

      {:error, _reason} ->
        {:error, :invalid_date}
    end
  end

  def week_of_year(_year, _month, _day, _week_data), do: {:error, :invalid_date}

  @doc false
  @spec week_of_month(Calendar.year(), Calendar.month(), Calendar.day()) ::
          {Calendar.month(), pos_integer()} | {:error, :invalid_date}
  def week_of_month(year, month, day), do: week_of_month(year, month, day, @iso_8601_weeks)

  # The month a date's week belongs to and its week of that month, numbered
  # as a year's weeks are, as TR35 says they are: week 1 of a month is its
  # first week holding at least the fewest days of it, so a week across a
  # month's end is the last of the old month or the first of the new one.
  # With ISO 8601's weeks, 1 October 2021, a Friday, is in week 5 of
  # September; with weeks from Sunday holding one day, 30 September 2021 is
  # in week 1 of October.
  @doc false
  @spec week_of_month(Calendar.year(), Calendar.month(), Calendar.day(), week_data()) ::
          {Calendar.month(), pos_integer()} | {:error, :invalid_date}
  def week_of_month(year, month, day, week_data)
      when is_integer(year) and is_integer(month) and is_integer(day) do
    case Date.new(year, month, day) do
      {:ok, date} ->
        days = Date.to_gregorian_days(date)
        first = days - day + 1
        this_month = week_one(first, week_data)
        next_month = week_one(first + Calendar.ISO.days_in_month(year, month), week_data)

        cond do
          days >= next_month -> {Integer.mod(month, 12) + 1, 1}
          days >= this_month -> {month, week_from(this_month, days)}
          true -> week_of_month_before(first, year, month, days, week_data)
        end

      {:error, _reason} ->
        {:error, :invalid_date}
    end
  end

  def week_of_month(_year, _month, _day, _week_data), do: {:error, :invalid_date}

  defp week_of_month_before(first, year, month, days, week_data) do
    {year_before, month_before} = if month == 1, do: {year - 1, 12}, else: {year, month - 1}
    first_before = first - Calendar.ISO.days_in_month(year_before, month_before)
    {month_before, week_from(week_one(first_before, week_data), days)}
  end

  @doc false
  @spec week(Calendar.year(), pos_integer()) :: Date.Range.t() | {:error, :invalid_date}
  def week(year, week), do: week(year, week, @iso_8601_weeks)

  # The days of week `week` of week-based year `year`, from the first day of
  # the week: a year's weeks end where the next year's week 1 begins, so it
  # has 52 or 53 of them.
  @doc false
  @spec week(Calendar.year(), pos_integer(), week_data()) ::
          Date.Range.t() | {:error, :invalid_date}
  def week(year, week, week_data) when is_integer(year) and is_integer(week) and week >= 1 do
    with {:ok, january_1} <- Date.new(year, 1, 1),
         january_1 = Date.to_gregorian_days(january_1),
         first = week_one(january_1, week_data) + (week - 1) * 7,
         true <- first < week_one(january_1 + days_in_year(year), week_data) do
      Date.range(Date.from_gregorian_days(first), Date.from_gregorian_days(first + 6))
    else
      _not_a_week -> {:error, :invalid_date}
    end
  end

  def week(_year, _week, _week_data), do: {:error, :invalid_date}

  # The ISO 8601 week of a date, which is this calendar's own week of the
  # year without a locale.
  @doc false
  @spec iso_week_of_year(Calendar.year(), Calendar.month(), Calendar.day()) ::
          {Calendar.year(), pos_integer()} | {:error, :invalid_date}
  def iso_week_of_year(year, month, day), do: week_of_year(year, month, day, @iso_8601_weeks)

  # The day week 1 of a period (a year or a month) begins on, the period
  # beginning on day `first`: the week holding `first` when at least the
  # fewest days of the period are in it, else the week after. Days are
  # counted from 0000-01-01, a Saturday.
  defp week_one(first, {first_day, min_days}) do
    before = Integer.mod(weekday(first) - first_day, 7)
    if 7 - before >= min_days, do: first - before, else: first - before + 7
  end

  defp week_from(week_one, days), do: div(days - week_one, 7) + 1

  defp weekday(days), do: Integer.mod(days + 5, 7) + 1

  # The days from the first of one month of a year to the last of another.
  defp months(year, first_month, last_month) when is_integer(year) do
    with {:ok, first} <- Date.new(year, first_month, 1),
         {:ok, last} <- Date.new(year, last_month, 1) do
      Date.range(first, Date.end_of_month(last))
    else
      {:error, _reason} -> {:error, :invalid_date}
    end
  end

  defp months(_year, _first_month, _last_month), do: {:error, :invalid_date}
end
