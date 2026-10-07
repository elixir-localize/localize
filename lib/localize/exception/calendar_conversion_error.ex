defmodule Localize.CalendarConversionError do
  @moduledoc """
  Exception returned when a value cannot be written in the calendar
  asked for, the calendars counting their days differently so that no
  day of the one is a day of the other.

  A locale's `-u-ca-` names the calendar its dates are written in, and
  a value whose own calendar cannot be converted into that one is this
  error.

  """

  defexception [:value, :calendar]

  @type t :: %__MODULE__{value: term(), calendar: module() | nil}

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{value: value, calendar: calendar}) do
    Localize.Exception.safe_message(
      "locale",
      "{$value} cannot be written in the calendar {$calendar}.",
      value: inspect(value),
      calendar: inspect(calendar)
    )
  end
end
