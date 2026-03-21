defmodule Localize.DateTimeOrderError do
  @moduledoc """
  Exception raised when dates in an interval are not in
  chronological order.

  """

  defexception [:from, :to]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{from: from, to: to}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "datetime",
      "The start %{from} must be before the end %{to}.",
      from: inspect(from),
      to: inspect(to)
    )
  end
end
