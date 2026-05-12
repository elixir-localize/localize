defmodule Localize.DateTimeInvalidInputError do
  @moduledoc """
  Exception raised when a date, time, or datetime value does not
  have the required keys for formatting.

  """

  defexception [:type]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{type: :time}) do
    Localize.Exception.safe_message(
      "datetime",
      "Time must have at least one of :hour, :minute, or :second keys."
    )
  end

  def message(%__MODULE__{type: :date}) do
    Localize.Exception.safe_message(
      "datetime",
      "Date must have at least one of :year, :month, or :day keys."
    )
  end

  def message(%__MODULE__{type: :datetime}) do
    Localize.Exception.safe_message(
      "datetime",
      "Datetime must have date and/or time keys."
    )
  end
end
