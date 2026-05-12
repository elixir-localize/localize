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
  def message(%__MODULE__{style: style, territory: nil}) do
    Localize.Exception.safe_message(
      "unknown style error",
      "The style {$style} is unknown.",
      style: inspect(style)
    )
  end

  def message(%__MODULE__{style: style, territory: territory}) do
    Localize.Exception.safe_message(
      "unknown style error",
      "The style {$style} is unknown for territory {$territory}.",
      style: inspect(style),
      territory: inspect(territory)
    )
  end
end
