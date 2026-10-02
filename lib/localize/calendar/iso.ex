defmodule Localize.Calendar.ISO do
  @moduledoc false

  # A calendar answers what a format needs to know about its dates through
  # callbacks on its own module. `Calendar.ISO` has none of the Calendrical
  # behaviour's callbacks and Calendrical may not be present, so Localize
  # answers them for it here, as the Gregorian calendar:
  # `Localize.Calendar.answering/1` names this module for `Calendar.ISO`, and
  # every other calendar answers for itself. Every callback of the `Calendar`
  # behaviour is passed to `Calendar.ISO`, so every question Localize puts to
  # a calendar goes to the one module.

  for {name, arity} <- Calendar.behaviour_info(:callbacks) do
    arguments = Macro.generate_arguments(arity, __MODULE__)

    @doc false
    def unquote(name)(unquote_splicing(arguments)),
      do: Calendar.ISO.unquote(name)(unquote_splicing(arguments))
  end

  @doc false
  @spec cldr_calendar_type() :: :gregorian
  def cldr_calendar_type, do: :gregorian

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

  @iso_8601_weeks {1, 4}

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

  # The days of quarter `quarter` of `year`: three months each, the first
  # from January.
  @doc false
  @spec quarter(Calendar.year(), pos_integer()) :: Date.Range.t() | {:error, :invalid_date}
  def quarter(year, quarter) when is_integer(year) and quarter in 1..4 do
    with {:ok, first} <- Date.new(year, quarter * 3 - 2, 1),
         {:ok, last_month} <- Date.new(year, quarter * 3, 1) do
      Date.range(first, Date.end_of_month(last_month))
    else
      _not_a_quarter -> {:error, :invalid_date}
    end
  end

  def quarter(_year, _quarter), do: {:error, :invalid_date}

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

  defp days_in_year(year), do: if(Calendar.ISO.leap_year?(year), do: 366, else: 365)
end
