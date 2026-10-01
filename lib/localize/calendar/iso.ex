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

  # `Calendar.ISO` numbers ISO 8601's weeks: they begin on Monday, and week
  # 1 is the one holding 4 January, so 1 January 2027 is in week 53 of 2026.
  @doc false
  @spec week_of_year(Calendar.year(), Calendar.month(), Calendar.day()) ::
          {Calendar.year(), pos_integer()} | {:error, :invalid_date}
  def week_of_year(year, month, day) do
    if Calendar.ISO.valid_date?(year, month, day),
      do: :calendar.iso_week_number({year, month, day}),
      else: {:error, :invalid_date}
  end

  # The days of ISO 8601 week `week` of week-based year `year`, Monday to
  # Sunday. A year has 52 weeks, or 53 when it begins on a Thursday, or on a
  # Wednesday in a leap year.
  @doc false
  @spec week(Calendar.year(), pos_integer()) :: Date.Range.t() | {:error, :invalid_date}
  def week(year, week) when is_integer(year) and is_integer(week) do
    with {:ok, january_4} <- Date.new(year, 1, 4),
         true <- week in 1..weeks_in_year(year) do
      monday = Date.add(january_4, (week - 1) * 7 + 1 - Date.day_of_week(january_4))
      Date.range(monday, Date.add(monday, 6))
    else
      _not_a_week -> {:error, :invalid_date}
    end
  end

  def week(_year, _week), do: {:error, :invalid_date}

  defp weeks_in_year(year) do
    {_year, weeks} = :calendar.iso_week_number({year, 12, 28})
    weeks
  end
end
