defmodule Localize.DateTimeFormatError do
  @moduledoc """
  Exception raised when a date, time, or datetime format
  pattern cannot be processed.

  """

  defexception [:format, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{format: format, reason: reason}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "datetime",
      "The format {$format} is invalid: {$reason}.",
      format: inspect(format),
      reason: reason
    )
  end
end
