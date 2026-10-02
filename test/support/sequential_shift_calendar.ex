defmodule Localize.Test.SequentialShiftCalendar do
  @moduledoc false

  # `Calendar.ISO` shifting a date by its years and then, from the date
  # reached, by its months, each bringing the day into a shorter month, where
  # `Calendar.ISO` counts the two together as months and brings the day in
  # once. A year and a month on from 29 February 2020 is 28 March 2021 here,
  # by way of 28 February, and 29 March in `Calendar.ISO`. Calendrical's
  # calendars of weeks shift this way, keeping the week in the year reached
  # before counting months on, and Localize cannot load them.
  use Localize.Test.StandInCalendar

  def shift_date(year, month, day, %Duration{} = duration) do
    %Duration{year: years, month: months, week: weeks, day: days} = duration

    {year, month, day} = Calendar.ISO.shift_date(year, month, day, Duration.new!(year: years))
    {year, month, day} = Calendar.ISO.shift_date(year, month, day, Duration.new!(month: months))

    Calendar.ISO.shift_date(year, month, day, Duration.new!(week: weeks, day: days))
  end
end
