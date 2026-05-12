defmodule Localize.UnknownCalendarError do
  @moduledoc """
  Exception raised when a calendar name is not a known
  CLDR calendar type.

  """

  defexception [:calendar]

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
