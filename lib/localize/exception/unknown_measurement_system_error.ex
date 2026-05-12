defmodule Localize.UnknownMeasurementSystemError do
  @moduledoc """
  Exception raised when a measurement system type is not a
  known CLDR measurement system.

  """

  defexception [:measurement_system]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{measurement_system: measurement_system}) do
    Localize.Exception.safe_message(
      "unit",
      "The measurement system {$measurement_system} is not known.",
      measurement_system: inspect(measurement_system)
    )
  end
end
