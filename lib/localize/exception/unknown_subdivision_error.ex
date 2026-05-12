defmodule Localize.UnknownSubdivisionError do
  @moduledoc """
  Exception raised when a territory subdivision code is
  not a known ISO 3166-2 subdivision.

  """

  defexception [:subdivision]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{subdivision: subdivision}) do
    Localize.Exception.safe_message(
      "locale",
      "The subdivision {$subdivision} is not known.",
      subdivision: inspect(subdivision)
    )
  end
end
