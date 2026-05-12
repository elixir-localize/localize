defmodule Localize.UnknownUnitError do
  @moduledoc """
  Exception raised when a unit identifier cannot be resolved
  to a known CLDR unit.

  """

  defexception [:unit]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{unit: unit}) do
    Localize.Exception.safe_message(
      "unit",
      "Unknown unit: {$unit}",
      unit: inspect(unit)
    )
  end
end
