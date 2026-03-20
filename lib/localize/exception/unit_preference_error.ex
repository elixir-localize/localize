defmodule Localize.UnitPreferenceError do
  @moduledoc """
  Exception raised when a unit preference cannot be determined
  for a given unit, region, or usage combination.

  """

  defexception [:unit, :region, :usage, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: reason}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "unit",
      "No unit preference found: %{reason}",
      reason: reason
    )
  end
end
