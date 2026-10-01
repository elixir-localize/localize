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

  @localize_answers [
    cldr_calendar_type: 0,
    era_calendar_type: 0,
    parsing_calendar: 0,
    month_of_year: 3,
    cardinal_month: 1,
    calendar_year: 3,
    related_gregorian_year: 3,
    cyclic_year: 3,
    week_of_year: 3,
    week: 2
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

  defp definition({:related_gregorian_year, 3}),
    do: quote(do: def(related_gregorian_year(year, _month, _day), do: year))

  defp definition({:cyclic_year, 3}),
    do: quote(do: def(cyclic_year(year, _month, _day), do: year))

  defp definition({:week_of_year, 3}) do
    quote do
      def week_of_year(year, month, day), do: :calendar.iso_week_number({year, month, day})
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

  defp definition({name, arity}) do
    arguments = Macro.generate_arguments(arity, __MODULE__)

    quote do
      def unquote(name)(unquote_splicing(arguments)),
        do: Calendar.ISO.unquote(name)(unquote_splicing(arguments))
    end
  end
end
