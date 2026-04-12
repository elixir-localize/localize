defmodule Localize.UnitConversionError do
  @moduledoc """
  Exception raised when a unit conversion cannot be performed.

  This may occur because the units are not convertible, the unit
  has no value, or a special conversion is not supported.

  """

  defexception [:from, :to, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{from: nil, to: nil, reason: reason}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "unit",
      "{$reason}",
      reason: reason
    )
  end

  def message(%__MODULE__{from: from, to: to, reason: reason}) when not is_nil(reason) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "unit",
      "Cannot convert from {$from} to {$to}: {$reason}",
      from: inspect(from),
      to: inspect(to),
      reason: reason
    )
  end

  def message(%__MODULE__{from: from, to: to}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "unit",
      "Units {$from} and {$to} are not convertible",
      from: inspect(from),
      to: inspect(to)
    )
  end
end
