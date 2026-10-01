defmodule Localize.Calendar.ISO do
  @moduledoc false

  # A calendar answers what a format needs to know about its dates through
  # callbacks on its own module. `Calendar.ISO` has none of those callbacks
  # and Calendrical may not be present, so Localize answers for it here, as
  # the Gregorian calendar: `Localize.Calendar.answering/1` names this module
  # for `Calendar.ISO` and every other calendar answers for itself.

  @doc false
  @spec month_of_year(Calendar.year(), Calendar.month(), Calendar.day()) :: Calendar.month()
  def month_of_year(_year, month, _day), do: month

  @doc false
  @spec cardinal_month(Calendar.month()) :: Calendar.month()
  def cardinal_month(month), do: month
end
