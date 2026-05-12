defmodule Localize.NoPracticalDifferenceError do
  @moduledoc """
  Exception raised when two date or datetime values are considered
  equal at every field used by `Localize.Interval.greatest_difference/2`,
  so no greater-than-zero interval field can be returned.

  """

  defexception [:from, :to]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{from: from, to: to}) do
    Localize.Exception.safe_message(
      "interval",
      "There is no practical difference between {$from} and {$to}",
      from: inspect(from),
      to: inspect(to)
    )
  end
end
