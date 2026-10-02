defmodule Localize.Test.StandInCalendar do
  @moduledoc false

  # Every question Localize puts to a calendar other than `Calendar.ISO`
  # (the callbacks `Localize.Calendar.validate_calendar/1` checks), answered
  # as the Gregorian calendar answers it: the Calendrical behaviour's that
  # Localize asks, and every `Calendar` callback, passed to `Calendar.ISO`.
  # Localize does not depend on Calendrical, so a test calendar stands in
  # for one of Calendrical's: it uses this module and overrides the answers
  # it is about. `without: [parsing_calendar: 0]` leaves answers out, for a
  # calendar that cannot give them.
  #
  # A year's days (`year/1`) and the arithmetic of months and years (`plus/6`
  # and `diff/3`) are answered from the calendar's own `Calendar` callbacks,
  # its `months_in_year/1`, `days_in_month/2` and `shift_date/4`, as
  # Calendrical derives a calendar's from them, so a stand-in that overrides
  # those answers the rest to match.

  @localize_answers [
    cldr_calendar_type: 0,
    era_calendar_type: 0,
    parsing_calendar: 0,
    month_of_year: 3,
    cardinal_month: 1,
    calendar_year: 3,
    extended_year: 3,
    related_gregorian_year: 3,
    cyclic_year: 3,
    week_of_year: 3,
    week_of_month: 3,
    week: 2,
    quarter: 2,
    year: 1,
    plus: 6,
    diff: 3
  ]

  @calendar_callbacks Calendar.behaviour_info(:callbacks) --
                        Calendar.behaviour_info(:optional_callbacks)

  defmacro __using__(options) do
    without = Keyword.get(options, :without, [])
    answers = Enum.reject(@localize_answers ++ @calendar_callbacks, &(&1 in without))
    definitions = Enum.map(answers, &definition/1)

    quote do
      unquote_splicing(definitions)
      defoverridable unquote(answers)
    end
  end

  defp definition({:cldr_calendar_type, 0}),
    do: quote(do: def(cldr_calendar_type, do: :gregorian))

  defp definition({:era_calendar_type, 0}),
    do: quote(do: def(era_calendar_type, do: cldr_calendar_type()))

  defp definition({:parsing_calendar, 0}), do: quote(do: def(parsing_calendar, do: __MODULE__))

  defp definition({:month_of_year, 3}),
    do: quote(do: def(month_of_year(_year, month, _day), do: month))

  defp definition({:cardinal_month, 1}), do: quote(do: def(cardinal_month(month), do: month))

  defp definition({:calendar_year, 3}),
    do: quote(do: def(calendar_year(year, _month, _day), do: year))

  defp definition({:extended_year, 3}),
    do: quote(do: def(extended_year(year, _month, _day), do: year))

  defp definition({:related_gregorian_year, 3}),
    do: quote(do: def(related_gregorian_year(year, _month, _day), do: year))

  defp definition({:cyclic_year, 3}),
    do: quote(do: def(cyclic_year(year, _month, _day), do: year))

  defp definition({:week_of_year, 3}) do
    quote do
      def week_of_year(year, month, day), do: :calendar.iso_week_number({year, month, day})
    end
  end

  defp definition({:week_of_month, 3}) do
    quote do
      def week_of_month(year, month, day),
        do: Localize.Calendar.ISO.week_of_month(year, month, day)
    end
  end

  # ISO 8601's week `week` of `year`, in the calendar using this module.
  defp definition({:week, 2}) do
    quote do
      def week(year, week) do
        case Localize.Calendar.ISO.week(year, week) do
          %Date.Range{first: first, last: last} ->
            Date.range(Date.convert!(first, __MODULE__), Date.convert!(last, __MODULE__))

          error ->
            error
        end
      end
    end
  end

  # The Gregorian quarter `quarter` of `year`, in the calendar using this
  # module.
  defp definition({:quarter, 2}) do
    quote do
      def quarter(year, quarter) do
        case Localize.Calendar.ISO.quarter(year, quarter) do
          %Date.Range{first: first, last: last} ->
            Date.range(Date.convert!(first, __MODULE__), Date.convert!(last, __MODULE__))

          error ->
            error
        end
      end
    end
  end

  # The days of a year, from the first day of its first month to the last
  # day of its last, as the calendar using this module counts them.
  defp definition({:year, 1}) do
    quote do
      def year(year) do
        last_month = months_in_year(year)
        last_day = days_in_month(year, last_month)

        Date.range(
          %Date{year: year, month: 1, day: 1, calendar: __MODULE__},
          %Date{year: year, month: last_month, day: last_day, calendar: __MODULE__}
        )
      end
    end
  end

  # The date a number of years, quarters, months, weeks or days on, as the
  # calendar using this module shifts a date (its `shift_date/4`), which
  # brings the day into a shorter month.
  defp definition({:plus, 6}) do
    quote do
      def plus(year, month, day, date_part, increment, _options) do
        duration =
          case date_part do
            :years -> Duration.new!(year: increment)
            :quarters -> Duration.new!(month: increment * 3)
            :months -> Duration.new!(month: increment)
            :weeks -> Duration.new!(week: increment)
            :days -> Duration.new!(day: increment)
          end

        shift_date(year, month, day, duration)
      end
    end
  end

  defp definition({:diff, 3}) do
    quote do
      def diff(from, to, date_part),
        do: Localize.Test.StandInCalendar.diff(__MODULE__, from, to, date_part)
    end
  end

  defp definition({name, arity}) do
    arguments = Macro.generate_arguments(arity, __MODULE__)

    quote do
      def unquote(name)(unquote_splicing(arguments)),
        do: Calendar.ISO.unquote(name)(unquote_splicing(arguments))
    end
  end

  # The whole years, quarters, months, weeks or days from one date of a
  # calendar to another, the inverse of its `plus/6`: the most that adds to
  # the earlier date without passing the later, and negative when `to` is the
  # earlier.
  def diff(calendar, from, to, date_part) do
    if days(calendar, to) < days(calendar, from),
      do: -count(calendar, to, from, date_part),
      else: count(calendar, from, to, date_part)
  end

  defp count(calendar, from, to, :days), do: days(calendar, to) - days(calendar, from)
  defp count(calendar, from, to, :weeks), do: div(count(calendar, from, to, :days), 7)
  defp count(calendar, from, to, :quarters), do: div(count(calendar, from, to, :months), 3)

  defp count(calendar, {year, month, day}, to, date_part) do
    limit = days(calendar, to)

    past =
      Enum.find(Stream.iterate(1, &(&1 + 1)), fn count ->
        days(calendar, calendar.plus(year, month, day, date_part, count, coerce: true)) > limit
      end)

    past - 1
  end

  defp days(calendar, {year, month, day}) do
    {days, _fraction} = calendar.naive_datetime_to_iso_days(year, month, day, 0, 0, 0, {0, 0})
    days
  end
end
