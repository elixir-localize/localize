defmodule Localize.UnknownStyleError do
  @moduledoc """
  Exception raised when a display name style is not one of
  the known styles (`:short`, `:standard`, `:variant`).

  """

  defexception [:style, :territory]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{style: style, territory: territory}) do
    base = "The style #{inspect(style)} is unknown"

    if territory do
      base <> " for territory #{inspect(territory)}."
    else
      base <> "."
    end
  end
end
