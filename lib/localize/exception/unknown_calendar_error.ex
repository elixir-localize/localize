defmodule Localize.UnknownCalendarError do
  @moduledoc """
  Exception returned when a calendar is not one Localize can use:
  a name that is not a known CLDR calendar type, or a calendar
  module that is neither `Calendar.ISO` nor answers the callbacks
  Localize puts to a calendar, those of the Calendrical behaviour
  and of the `Calendar` behaviour it extends.

  """

  defexception [:calendar]

  @type t :: %__MODULE__{calendar: atom() | String.t() | nil}

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{calendar: calendar}) do
    Localize.Exception.safe_message(
      "locale",
      "The calendar {$calendar} is not known.",
      calendar: inspect(calendar)
    )
  end
end
