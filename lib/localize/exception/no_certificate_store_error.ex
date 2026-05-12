defmodule Localize.NoCertificateStoreError do
  @moduledoc """
  Exception raised when no certificate trust store can be located.

  Carries the list of paths that were searched in the `:searched`
  field so callers and operators can see exactly which locations
  were considered.

  """

  defexception [:searched]

  @type t :: %__MODULE__{
          searched: [String.t()]
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{searched: searched}) do
    Localize.Exception.safe_message(
      "locale",
      "No certificate trust store was found. Tried looking for: {$searched}. " <>
        "Install the `castore` or `certifi` hex package, or configure " <>
        "`config :localize, cacertfile: \"/path/to/cacertfile\"`.",
      searched: inspect(searched)
    )
  end
end
