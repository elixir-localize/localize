defmodule Localize.Unit.Parser.Helpers do
  @moduledoc false

  # Runtime helper functions called by the pre-compiled parser.
  # These are extracted from the combinator module so the
  # NimbleParsec dependency is not needed at runtime.

  @doc false
  def wrap_pow([_pow_string, digits]) do
    {:power, {:pow, String.to_integer(digits)}}
  end

  @doc false
  def wrap_constant(parts) do
    {:constant, Enum.join(parts)}
  end

  @doc false
  def wrap_currency_unit([code]) do
    {:single_unit, prefix: nil, power: nil, base: "curr-" <> String.upcase(code)}
  end

  @doc false
  def wrap_single_unit(parts) do
    power =
      case Enum.find(parts, fn
             {:power, _} -> true
             _ -> false
           end) do
        {:power, value} -> value
        nil -> nil
      end

    si_prefix =
      case Enum.find(parts, &match?({:si_prefix, _}, &1)) do
        {:si_prefix, value} -> Localize.Unit.Data.si_prefix_atom(value)
        nil -> nil
      end

    base =
      case Enum.find(parts, &match?({:base, _}, &1)) do
        {:base, value} -> value
        nil -> nil
      end

    {:single_unit, prefix: si_prefix, power: power, base: base}
  end

  @doc false
  def wrap_per_leading(products) do
    denominator = Enum.flat_map(products, fn {:product, units} -> units end)
    {:unit, type: nil, numerator: [], denominator: denominator}
  end

  @doc false
  def wrap_core_unit([{:product, numerator}]) do
    {:unit, type: nil, numerator: numerator, denominator: []}
  end

  def wrap_core_unit([{:product, numerator} | denominator_products]) do
    denominator = Enum.flat_map(denominator_products, fn {:product, units} -> units end)
    {:unit, type: nil, numerator: numerator, denominator: denominator}
  end

  @doc false
  def wrap_long_unit([category_name, {:unit, keyword}]) do
    {:unit, Keyword.put(keyword, :type, category_name)}
  end

  @doc false
  def wrap_mixed_unit(units) do
    {:mixed_unit, units}
  end
end
