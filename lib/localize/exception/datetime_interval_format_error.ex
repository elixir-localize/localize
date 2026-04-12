defmodule Localize.DateTimeIntervalFormatError do
  @moduledoc """
  Exception raised when an interval format cannot be resolved.

  """

  defexception [:reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: reason}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "datetime",
      "Interval format error: {$reason}.",
      reason: reason
    )
  end
end
