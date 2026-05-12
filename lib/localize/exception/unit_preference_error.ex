defmodule Localize.UnitPreferenceError do
  @moduledoc """
  Exception raised when a unit preference cannot be determined
  for a given unit, region, or usage combination.

  """

  defexception [:unit, :region, :usage, :category, :quantity, :reason]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: :unknown_quantity, unit: unit}) do
    Localize.Exception.safe_message(
      "unit",
      "No quantity found for base unit {$unit}.",
      unit: inspect(unit)
    )
  end

  def message(%__MODULE__{reason: :unknown_category, quantity: quantity}) do
    Localize.Exception.safe_message(
      "unit",
      "No unit preferences found for quantity {$quantity}.",
      quantity: inspect(quantity)
    )
  end

  def message(%__MODULE__{reason: :no_preference_for_usage, category: category, usage: usage}) do
    Localize.Exception.safe_message(
      "unit",
      "No unit preferences for category {$category} and usage {$usage}.",
      category: inspect(category),
      usage: inspect(usage)
    )
  end

  def message(%__MODULE__{reason: :no_preference_for_region, category: category, region: region}) do
    Localize.Exception.safe_message(
      "unit",
      "No unit preference for region {$region} in category {$category}.",
      region: inspect(region),
      category: inspect(category)
    )
  end
end
