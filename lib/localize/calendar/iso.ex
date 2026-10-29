defmodule Localize.Calendar.ISO do
  @moduledoc false

  # The ISO 8601 calendar as a full calendar module: the proleptic Gregorian
  # calendar of Elixir's `Calendar.ISO`, with ISO 8601's weeks.
  #
  # `Calendar.ISO` keeps Elixir's `Calendar` behaviour alone. A calendar
  # answers what a format needs to know about its dates through the
  # callbacks of the Calendrical behaviour too, which `Calendar.ISO` has
  # none of, and Calendrical may not be present. This module is the one
  # calendar that keeps both:
  #
  # * Every callback of the `Calendar` behaviour is passed to `Calendar.ISO`.
  #
  # * Every callback of the Calendrical behaviour is implemented here, as
  #   Calendrical's own `Calendrical.ISO` answers it, which a Calendrical
  #   test holds this module to. Localize does not depend on Calendrical, so
  #   that behaviour is kept and not declared.
  #
  # It is a calendar in its own right: a date it answers with is a date of
  # this module, as every calendar's answers are dates of itself, and a
  # date written for it is read as a date of it (`parsing_calendar/0`). A
  # value may name it as its calendar, and it is then the `Calendar.ISO`
  # value of the same fields under another module's name: `Date.convert/2`
  # takes one to the other, and Localize reads, writes and numbers the
  # weeks of both alike.
  #
  # Localize puts every question about a `Calendar.ISO` date to this module
  # and to no other (`Localize.Calendar.answering/1`; user, 2026-10-02: "All
  # Calendrical behaviour callbacks must be implemented for Calendar.ISO and
  # done so in a specific, isolated, callback module").
  #
  # Every error this module returns is an atom because the Calendrical
  # behaviour returns one: `Calendrical.Base.Month.month/3` and its
  # neighbours answer `{:error, :invalid_date}`, and a value of this
  # module is read beside a value of one of Calendrical's own calendars.
  # An exception struct here would answer a question Calendrical asks in
  # a shape it does not take, so the whole file is exempt from the house
  # rule rather than each of its three dozen returns saying so.
  #
  # credo:disable-for-this-file Localize.Credo.ErrorTuple

  @behaviour Calendar

  # ISO 8601's weeks begin on Monday, and its week 1 holds four days of the
  # year: the weeks this module answers where a question carries no locale.
  @iso_8601_weeks {1, 4}

  # The static facts about this calendar, with the fields of Calendrical's
  # `Calendrical.Info` struct, which Localize does not depend on: a plain
  # map with the same keys, which every reader of the facts takes.
  @info %{
    calendar: __MODULE__,
    cldr_calendar_type: :gregorian,
    era_calendar_type: :gregorian,
    epoch: Calendar.ISO.date_to_iso_days(1, 1, 1),
    year_zero?: true,
    structure: :months,
    months_in_year: {12, 12},
    weeks: %{first_day: 1, min_days_in_first_week: 4},
    years_in_cycle: 400,
    year_cycle: nil,
    location: nil,
    month_lengths: %{
      1 => 31,
      2 => 28..29//1,
      3 => 31,
      4 => 30,
      5 => 31,
      6 => 30,
      7 => 31,
      8 => 31,
      9 => 30,
      10 => 31,
      11 => 30,
      12 => 31
    },
    parsing_calendar: __MODULE__,
    family: __MODULE__,
    members: nil
  }

  for {name, arity} <- Calendar.behaviour_info(:callbacks) do
    arguments = Macro.generate_arguments(arity, __MODULE__)

    @doc false
    @impl Calendar
    def unquote(name)(unquote_splicing(arguments)),
      do: Calendar.ISO.unquote(name)(unquote_splicing(arguments))
  end

  @typedoc false
  @type info :: %{
          calendar: __MODULE__,
          cldr_calendar_type: :gregorian,
          era_calendar_type: :gregorian,
          epoch: 366,
          year_zero?: true,
          structure: :months,
          months_in_year: {12, 12},
          weeks: %{first_day: 1, min_days_in_first_week: 4},
          years_in_cycle: 400,
          year_cycle: nil,
          location: nil,
          month_lengths: %{
            1 => 31,
            2 => %Range{first: 28, last: 29, step: 1},
            3 => 31,
            4 => 30,
            5 => 31,
            6 => 30,
            7 => 31,
            8 => 31,
            9 => 30,
            10 => 31,
            11 => 30,
            12 => 31
          },
          parsing_calendar: __MODULE__,
          family: __MODULE__,
          members: nil
        }

  @doc false
  # The static facts about the ISO calendar: the Gregorian calendar's names
  # and eras, a year 0, twelve months of the Gregorian lengths, ISO 8601's
  # weeks, a 400-year cycle, and itself for parsing.
  @spec info() :: info()
  def info, do: @info

  @doc false
  # The CLDR month of a month of a year: the month itself, in the one
  # calendar whose months are their own numbering.
  @spec cldr_month(Calendar.year(), Calendar.month()) :: Calendar.month()
  def cldr_month(_year, month), do: month

  @doc false
  # The month a CLDR month is written with: the month itself.
  @spec written_month_from_cldr_month(Calendar.year(), Calendar.month()) :: Calendar.month()
  def written_month_from_cldr_month(_year, cldr_month), do: cldr_month

  @doc false
  # A date is written as its own fields.
  @spec written_date(Calendar.year(), Calendar.month(), Calendar.day()) ::
          {Calendar.year(), Calendar.month(), Calendar.day()}
  def written_date(year, month, day), do: {year, month, day}

  @doc false
  # The date written figures name: the fields themselves, where they are a
  # date.
  @spec date_from_written_date(Calendar.year(), Calendar.month(), Calendar.day()) ::
          {:ok, {Calendar.year(), Calendar.month(), Calendar.day()}} | {:error, :invalid_date}
  def date_from_written_date(year, month, day) do
    if Calendar.ISO.valid_date?(year, month, day),
      do: {:ok, {year, month, day}},
      else: {:error, :invalid_date}
  end

  @doc false
  @spec cldr_calendar_type() :: :gregorian
  def cldr_calendar_type, do: :gregorian

  @doc false
  @spec cldr_calendar_type(Calendar.year(), Calendar.month(), Calendar.day()) :: :gregorian
  def cldr_calendar_type(_year, _month, _day), do: :gregorian

  @doc false
  @spec era_calendar_type() :: :gregorian
  def era_calendar_type, do: :gregorian

  # A date written for this calendar is read as a date of it.
  @doc false
  @spec parsing_calendar() :: __MODULE__
  def parsing_calendar, do: __MODULE__

  # The calendars a date of `Calendar.ISO` may be written in: that
  # calendar alone, which `Localize.Calendar.parsing_calendars/1` already
  # names first.
  @doc false
  @spec parsing_calendars() :: [Calendar.ISO, ...]
  def parsing_calendars, do: [Calendar.ISO]

  # Localize resolves no CLDR calendar type to a module itself: that is
  # the calendar provider's to answer, which is asked when this is not.
  @doc false
  @spec calendar_from_cldr_calendar_type(atom() | String.t()) ::
          {:error, Localize.UnknownCalendarError.t()}
  def calendar_from_cldr_calendar_type(calendar_type),
    do: {:error, Localize.UnknownCalendarError.exception(calendar: calendar_type)}

  @doc false
  @spec month_of_year(Calendar.year(), Calendar.month(), Calendar.day()) :: Calendar.month()
  def month_of_year(_year, month, _day), do: month

  @doc false
  @spec cardinal_month(Calendar.month()) :: Calendar.month()
  def cardinal_month(month), do: month

  # The day that names a date and the number its month is written with in
  # figures are its own day and month.
  @doc false
  @spec cardinal_day(Calendar.year(), Calendar.month(), Calendar.day()) :: Calendar.day()
  def cardinal_day(_year, _month, day), do: day

  @doc false
  @spec numeric_month(Calendar.year(), Calendar.month(), Calendar.day()) :: Calendar.month()
  def numeric_month(_year, month, _day), do: month

  # The twelve months are their own numbering, and no year has a leap month.
  @doc false
  @spec lunar_month_of_year(Calendar.year(), Calendar.month()) ::
          Calendar.month() | {:error, :invalid_month}
  def lunar_month_of_year(year, month) when is_integer(year) and month in 1..12, do: month
  def lunar_month_of_year(_year, _month), do: {:error, :invalid_month}

  @doc false
  @spec ordinal_month_from_traditional(Calendar.year(), term()) ::
          {:ok, Calendar.month()} | {:error, :invalid_month | :invalid_leap_month}
  def ordinal_month_from_traditional(year, month) when is_integer(year) and month in 1..12,
    do: {:ok, month}

  def ordinal_month_from_traditional(year, {_month, :leap}) when is_integer(year),
    do: {:error, :invalid_leap_month}

  def ordinal_month_from_traditional(_year, _month), do: {:error, :invalid_month}

  # The Gregorian calendar names its months as it numbers them, so a month
  # is its own traditional month and has no leap month.
  @doc false
  @spec traditional_month(Calendar.year(), Calendar.month()) ::
          Calendar.month() | {:error, Localize.InvalidValueError.t()}
  def traditional_month(year, month) when is_integer(year) and month in 1..12, do: month
  def traditional_month(year, month), do: {:error, invalid_month(year, month)}

  @doc false
  @spec month_from_traditional(Calendar.year(), Calendar.month() | {Calendar.month(), :leap}) ::
          Calendar.month() | {:error, Localize.InvalidValueError.t()}
  def month_from_traditional(year, month) when is_integer(year) and month in 1..12, do: month
  def month_from_traditional(year, month), do: {:error, invalid_month(year, month)}

  @doc false
  @spec leap_month(Calendar.year()) :: nil
  def leap_month(_year), do: nil

  @doc false
  @spec traditional_leap_month(Calendar.year()) :: nil
  def traditional_leap_month(_year), do: nil

  @doc false
  @spec traditional_months(Calendar.year()) :: [Calendar.month()]
  def traditional_months(year) when is_integer(year), do: Enum.to_list(1..12)
  def traditional_months(_year), do: []

  # The Gregorian calendar's years repeat, their days and their weekdays
  # alike, after 400: 146,097 days, which are 20,871 weeks.
  @doc false
  @spec years_in_cycle() :: 400
  def years_in_cycle, do: 400

  # A solar term is the sun's place in the sky on a day, which is astronomy:
  # Localize has none, and no question it puts to a calendar asks for one.
  @doc false
  @spec solar_term(term(), term()) :: {:error, :undefined}
  def solar_term(_index, _gregorian_year), do: {:error, :undefined}

  # Every year has the months 1 to 12, and every month its days from 1.
  @doc false
  @spec month_numbers(Calendar.year()) :: [Range.t()]
  def month_numbers(year) when is_integer(year), do: [1..12//1]
  def month_numbers(_year), do: []

  @doc false
  @spec day_numbers(Calendar.year(), Calendar.month()) :: [Range.t()]
  def day_numbers(year, month) when is_integer(year) and month in 1..12,
    do: [1..Calendar.ISO.days_in_month(year, month)//1]

  def day_numbers(_year, _month), do: []

  # A month is named by its own number, so the days of a named month are
  # the month's.
  @doc false
  @spec named_month(Calendar.year(), Calendar.month()) :: [Date.Range.t()]
  def named_month(year, named_month) do
    case month(year, named_month) do
      %Date.Range{} = days -> [days]
      {:error, _no_such_month} -> []
    end
  end

  # The days of a year are counted from 1 January.
  @doc false
  @spec date_from_day_of_year(Calendar.year(), pos_integer()) ::
          Date.t() | {:error, :invalid_date}
  def date_from_day_of_year(year, day_of_year)
      when is_integer(year) and is_integer(day_of_year) and day_of_year >= 1 do
    if day_of_year <= days_in_year(year) do
      with {:ok, first} <- Date.new(year, 1, 1, __MODULE__) do
        Date.add(first, day_of_year - 1)
      end
    else
      {:error, :invalid_date}
    end
  end

  def date_from_day_of_year(_year, _day_of_year), do: {:error, :invalid_date}

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

  # The year a date is written with: its own year, since a Gregorian
  # date is written as itself.
  @doc false
  @spec cardinal_year(Calendar.year(), Calendar.month(), Calendar.day()) :: Calendar.year()
  def cardinal_year(year, _month, _day), do: year

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

  # Every Gregorian year has twelve months.
  @doc false
  @spec months_in_year_bounds() :: {12, 12}
  def months_in_year_bounds, do: {12, 12}

  # A leap year has the twelve months every year has.
  @doc false
  @spec months_in_leap_year() :: 12
  def months_in_leap_year, do: 12

  # A Gregorian date is written as its own fields, so a written date is
  # the date itself, where it is one.
  @doc false
  @spec date_from_cardinal_date(Calendar.year(), Calendar.month(), Calendar.day()) ::
          {Calendar.year(), Calendar.month(), Calendar.day()} | {:error, :invalid_date}
  def date_from_cardinal_date(year, month, day)
      when is_integer(year) and is_integer(month) and is_integer(day) do
    if Calendar.ISO.valid_date?(year, month, day),
      do: {year, month, day},
      else: {:error, :invalid_date}
  end

  def date_from_cardinal_date(_year, _month, _day), do: {:error, :invalid_date}

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

  # The fewest and the most days a month has in any year: February's two.
  @doc false
  @spec days_in_month_bounds(Calendar.month()) ::
          {Calendar.day(), Calendar.day()} | {:error, Localize.InvalidValueError.t()}
  def days_in_month_bounds(2), do: {28, 29}
  def days_in_month_bounds(month) when month in [4, 6, 9, 11], do: {30, 30}
  def days_in_month_bounds(month) when month in 1..12, do: {31, 31}
  def days_in_month_bounds(month), do: {:error, invalid_month(nil, month)}

  # ISO 8601's weeks of a year: 52, or 53 in a year that begins on a
  # Thursday, or on a Wednesday in a leap year.
  @doc false
  @spec weeks_in_year(Calendar.year()) :: 52 | 53 | {:error, :invalid_date}
  def weeks_in_year(year) when is_integer(year) do
    case Date.new(year, 1, 1) do
      {:ok, january_1} ->
        january_1 = Date.to_gregorian_days(january_1)
        next_year = week_one(january_1 + days_in_year(year), @iso_8601_weeks)
        div(next_year - week_one(january_1, @iso_8601_weeks), 7)

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
    case Date.new(year, month, day, __MODULE__) do
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
  @spec shift(
          Calendar.year(),
          Calendar.month(),
          Calendar.day(),
          :years | :quarters | :months | :weeks | :days,
          integer(),
          Keyword.t()
        ) :: {Calendar.year(), Calendar.month(), Calendar.day()} | {:error, :invalid_date}
  def shift(year, month, day, date_part, increment, options \\ [])

  def shift(year, month, day, date_part, increment, options)
      when is_integer(year) and month in 1..12 and is_integer(day) and is_integer(increment) do
    part_on(date_part, {year, month, day}, increment, options)
  end

  def shift(_year, _month, _day, _date_part, _increment, _options), do: {:error, :invalid_date}

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
    if Keyword.get(options, :clamp, true),
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

  # The weeks of a month are those `week_of_month/3` names for it, with ISO
  # 8601's weeks: from the first week holding four days of the month to the
  # week before the next month's first.
  @doc false
  @spec weeks_in_month(Calendar.year(), Calendar.month()) ::
          pos_integer() | {:error, :invalid_date}
  def weeks_in_month(year, month) do
    with {:ok, first_week, next_first_week} <- month_week_bounds(year, month),
         do: div(next_first_week - first_week, 7)
  end

  # The weeks of a month in order, each the seven days of a week that begins
  # on Monday: the first may begin in the month before and the last run into
  # the month after, as TR35 numbers a month's weeks.
  @doc false
  @spec weeks_of_month(Calendar.year(), Calendar.month()) ::
          [Date.Range.t()] | {:error, Localize.InvalidValueError.t()}
  def weeks_of_month(year, month) do
    case month_week_bounds(year, month) do
      {:ok, first_week, next_first_week} ->
        first_week
        |> Stream.iterate(&(&1 + 7))
        |> Enum.take_while(&(&1 < next_first_week))
        |> Enum.map(&week_from_day/1)

      {:error, :invalid_date} ->
        {:error, invalid_month(year, month)}
    end
  end

  @doc false
  @spec month_week(Calendar.year(), Calendar.month(), pos_integer()) ::
          Date.Range.t() | {:error, :invalid_date}
  def month_week(year, month, week) when is_integer(week) and week >= 1 do
    with {:ok, first_week, next_first_week} <- month_week_bounds(year, month) do
      week_of_month(first_week + (week - 1) * 7, next_first_week)
    end
  end

  def month_week(_year, _month, _week), do: {:error, :invalid_date}

  # A week belongs to the period when it starts before the next period does.
  defp week_of_month(first, next_first) when first < next_first, do: week_from_day(first)

  defp week_of_month(_first, _next_first), do: {:error, :invalid_date}

  # The first day of a month's week 1 and of the next month's.
  defp month_week_bounds(year, month) when is_integer(year) and is_integer(month) do
    case Date.new(year, month, 1) do
      {:ok, date} ->
        first = Date.to_gregorian_days(date)
        next_first = first + Calendar.ISO.days_in_month(year, month)
        {:ok, week_one(first, @iso_8601_weeks), week_one(next_first, @iso_8601_weeks)}

      {:error, _reason} ->
        {:error, :invalid_date}
    end
  end

  defp month_week_bounds(_year, _month), do: {:error, :invalid_date}

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
    with {:ok, january_1} <- Date.new(year, 1, 1) do
      january_1 = Date.to_gregorian_days(january_1)
      next_year = week_one(january_1 + days_in_year(year), week_data)

      week_of_month(week_one(january_1, week_data) + (week - 1) * 7, next_year)
    end
  end

  def week(_year, _week, _week_data), do: {:error, :invalid_date}

  # ISO 8601's week dates: a year, a week of it and a day of the week counted
  # from Monday. Every calendar answers a week date by ISO 8601's rule over
  # its own year (the Calendrical behaviour's `date_from_week_date/3`,
  # `week_date_from_date/3` and `weeks_in_week_year/1`), and this calendar's
  # are ISO 8601's own: "2026-W25-2" is 16 June 2026.
  @doc false
  @spec date_from_week_date(Calendar.year(), pos_integer(), 1..7) ::
          Date.t() | {:error, :invalid_date}
  def date_from_week_date(week_year, week, day) when is_integer(day) and day in 1..7 do
    case week(week_year, week) do
      %Date.Range{first: first} -> Date.add(first, day - 1)
      {:error, _reason} -> {:error, :invalid_date}
    end
  end

  def date_from_week_date(_week_year, _week, _day) do
    {:error, :invalid_date}
  end

  @doc false
  @spec week_date_from_date(Calendar.year(), Calendar.month(), Calendar.day()) ::
          {Calendar.year(), pos_integer(), 1..7} | {:error, :invalid_date}
  def week_date_from_date(year, month, day) do
    case week_of_year(year, month, day) do
      {week_year, week} when is_integer(week_year) and is_integer(week) ->
        {day_of_week, _first, _last} = Calendar.ISO.day_of_week(year, month, day, :monday)
        {week_year, week, day_of_week}

      {:error, _reason} ->
        {:error, :invalid_date}
    end
  end

  @doc false
  @spec weeks_in_week_year(Calendar.year()) :: 52 | 53 | {:error, :invalid_date}
  def weeks_in_week_year(week_year) do
    case weeks_in_year(week_year) do
      weeks when is_integer(weeks) -> weeks
      {:error, _reason} -> {:error, :invalid_date}
    end
  end

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

  # A month no year of this calendar has, as the exception the Calendrical
  # behaviour's callbacks answer with.
  defp invalid_month(year, month) do
    Localize.InvalidValueError.exception(
      value: month,
      expected: :month,
      allowed_values: Enum.to_list(1..12),
      context: year
    )
  end

  # The seven days of the week that begins on day `first`, as dates of this
  # calendar: each the `Calendar.ISO` date of that day under this module's
  # name.
  defp week_from_day(first) do
    Date.range(
      %{Date.from_gregorian_days(first) | calendar: __MODULE__},
      %{Date.from_gregorian_days(first + 6) | calendar: __MODULE__}
    )
  end

  defp weekday(days), do: Integer.mod(days + 5, 7) + 1

  # The days from the first of one month of a year to the last of another,
  # as dates of this calendar.
  defp months(year, first_month, last_month) when is_integer(year) do
    with {:ok, first} <- Date.new(year, first_month, 1, __MODULE__),
         {:ok, last} <- Date.new(year, last_month, 1, __MODULE__) do
      Date.range(first, Date.end_of_month(last))
    end
  end

  defp months(_year, _first_month, _last_month), do: {:error, :invalid_date}
end
