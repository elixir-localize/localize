defmodule Localize.Test.StandInCalendar do
  @moduledoc false

  # Every question Localize puts to a calendar other than `Calendar.ISO`
  # (the callbacks `Localize.Calendar.validate_calendar/1` checks), answered
  # as the Gregorian calendar answers it: the Calendrical behaviour's that
  # Localize asks, and every `Calendar` callback, passed to `Calendar.ISO`.
  # Localize does not depend on Calendrical, so a test calendar stands in
  # for one of Calendrical's: it uses this module and overrides the answers
  # it is about.

  @calendar_callbacks Calendar.behaviour_info(:callbacks) --
                        Calendar.behaviour_info(:optional_callbacks)

  defmacro __using__(_options) do
    passed_to_iso =
      for {name, arity} <- @calendar_callbacks do
        arguments = Macro.generate_arguments(arity, __MODULE__)

        quote do
          def unquote(name)(unquote_splicing(arguments)),
            do: Calendar.ISO.unquote(name)(unquote_splicing(arguments))
        end
      end

    quote do
      def cldr_calendar_type, do: :gregorian
      def era_calendar_type, do: cldr_calendar_type()
      def month_of_year(_year, month, _day), do: month
      def cardinal_month(month), do: month
      def calendar_year(year, _month, _day), do: year
      def related_gregorian_year(year, _month, _day), do: year
      def cyclic_year(year, _month, _day), do: year
      def iso_week_of_year(year, month, day), do: :calendar.iso_week_number({year, month, day})

      unquote_splicing(passed_to_iso)

      defoverridable [
                       cldr_calendar_type: 0,
                       era_calendar_type: 0,
                       month_of_year: 3,
                       cardinal_month: 1,
                       calendar_year: 3,
                       related_gregorian_year: 3,
                       cyclic_year: 3,
                       iso_week_of_year: 3
                     ] ++ unquote(@calendar_callbacks)
    end
  end
end
