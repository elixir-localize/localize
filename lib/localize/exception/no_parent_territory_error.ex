defmodule Localize.NoParentTerritoryError do
  @moduledoc """
  Exception raised when a territory has no parent container
  in the CLDR territory containment data.

  """

  defexception [:territory]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{territory: territory}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "locale",
      "No parent territory found for %{territory}.",
      territory: inspect(territory)
    )
  end
end
