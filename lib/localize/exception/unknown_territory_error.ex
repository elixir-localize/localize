defmodule Localize.UnknownTerritoryError do
  @moduledoc """
  Exception raised when a territory code is not a known
  ISO 3166 territory or CLDR region code.

  """

  defexception [:territory]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{territory: territory}) do
    Localize.Exception.safe_message(
      "locale",
      "The territory {$territory} is not known.",
      territory: inspect(territory)
    )
  end
end
