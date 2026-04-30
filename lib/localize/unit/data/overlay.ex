defmodule Localize.Unit.Data.Overlay do
  @moduledoc false

  # Runtime overlay over `Localize.Unit.Data`: checks the custom unit
  # registry first, then falls back to the compile-time CLDR data.
  #
  # Lives in its own module so that `Localize.Unit.Data` can stay a
  # leaf (no runtime back-edges into `Localize.Unit.CustomRegistry`),
  # which keeps the `combinators.ex (compile→) data.ex` edge out of
  # any compile-connected cycle.

  alias Localize.Unit.{CustomRegistry, Data}

  @doc """
  Returns the conversion factor for a unit, checking the custom
  registry first and falling back to the compile-time data.

  """
  @spec conversion_factor(String.t()) :: %{factor: number() | :special, offset: number()} | nil
  def conversion_factor(unit_name) do
    case CustomRegistry.get(unit_name) do
      nil ->
        Data.conversion_factor_raw(unit_name)

      definition ->
        %{factor: definition.factor, offset: Map.get(definition, :offset, 0.0)}
    end
  end

  @doc """
  Returns the base unit for a unit, checking the custom registry
  first and falling back to the compile-time data.

  """
  @spec conversion(String.t()) :: String.t() | nil
  def conversion(unit_name) do
    case CustomRegistry.get(unit_name) do
      nil ->
        Data.conversion_raw(unit_name)

      definition ->
        definition.base_unit
    end
  end
end
