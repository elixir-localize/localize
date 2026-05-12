defmodule Localize.UnitNoValueError do
  @moduledoc """
  Exception raised when a unit operation requires a numeric value
  but the unit struct has `nil` as its value.

  """

  defexception [:operation]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{operation: operation}) do
    Localize.Exception.safe_message(
      "unit",
      "Cannot apply {$operation} to a unit without a value.",
      operation: to_string(operation)
    )
  end
end
