defmodule Localize.UnknownTimezoneError do
  @moduledoc """
  Exception raised when a timezone identifier cannot be resolved
  to a known IANA timezone.

  """

  defexception [:timezone]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{timezone: timezone}) do
    Localize.Exception.safe_message(
      "locale",
      "Unknown timezone: {$timezone}",
      timezone: inspect(timezone)
    )
  end
end
