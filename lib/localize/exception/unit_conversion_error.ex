defmodule Localize.UnitConversionError do
  @moduledoc """
  Exception raised when a unit conversion cannot be performed.

  This may occur because the units are not convertible, the unit
  requires a special conversion that is not supported, or the
  conversion involves mixed units.

  """

  defexception [:from, :to, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{from: from, to: to, reason: :not_convertible}) do
    Localize.Exception.safe_message(
      "unit",
      "Units {$from} and {$to} are not convertible.",
      from: inspect(from),
      to: inspect(to)
    )
  end

  def message(%__MODULE__{from: from, reason: :special_conversion}) do
    Localize.Exception.safe_message(
      "unit",
      "Special conversion is not supported for {$from}.",
      from: inspect(from)
    )
  end

  def message(%__MODULE__{reason: :mixed_units}) do
    Localize.Exception.safe_message(
      "unit",
      "Cannot compute conversion factor for mixed units."
    )
  end

  def message(%__MODULE__{from: from, to: to}) do
    Localize.Exception.safe_message(
      "unit",
      "Cannot convert from {$from} to {$to}.",
      from: inspect(from),
      to: inspect(to)
    )
  end
end
