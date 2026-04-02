defmodule Localize.Unit.Parser.Combinator do
  @moduledoc false

  import NimbleParsec

  # ── Compile-time data ───────────────────────────────────────────────

  @si_prefix_names Localize.Unit.Data.si_prefix_names()
  @base_units Localize.Unit.Data.base_units()
  @categories Localize.Unit.Data.categories()

  # ── Leaf combinators ────────────────────────────────────────────────

  @doc false
  def si_prefix do
    @si_prefix_names
    |> Enum.sort_by(&(-String.length(&1)))
    |> Enum.map(&string/1)
    |> choice()
    |> unwrap_and_tag(:si_prefix)
  end

  @doc false
  def power_prefix do
    choice([
      string("square-") |> replace({:power, :square}),
      string("cubic-") |> replace({:power, :cubic}),
      string("pow")
      |> ascii_string([?0..?9], min: 1, max: 2)
      |> ignore(string("-"))
      |> reduce(:wrap_pow)
    ])
  end

  @doc false
  def wrap_pow([_pow_string, digits]) do
    {:power, {:pow, String.to_integer(digits)}}
  end

  @doc false
  def base_unit do
    @base_units
    |> Enum.sort_by(&(-String.length(&1)))
    |> Enum.map(&string/1)
    |> choice()
    |> unwrap_and_tag(:base)
  end

  @doc false
  def unit_constant do
    choice([
      # Scientific notation: 1e6, 1e9, etc.
      string("1e")
      |> ascii_string([?0..?9], min: 1)
      |> reduce(:wrap_constant),
      # Plain integer > 1
      ascii_string([?1..?9], 1)
      |> ascii_string([?0..?9], min: 1)
      |> reduce(:wrap_constant)
    ])
  end

  @doc false
  def wrap_constant(parts) do
    {:constant, Enum.join(parts)}
  end

  # ── Currency unit ───────────────────────────────────────────────────

  @doc false
  def currency_unit do
    ignore(string("curr-"))
    |> ascii_string([?a..?z, ?A..?Z], 3)
    |> reduce(:wrap_currency_unit)
  end

  # ── Single unit ─────────────────────────────────────────────────────

  @doc false
  def single_unit do
    choice([
      # Currency unit (curr-USD, curr-EUR, etc.)
      currency_unit(),
      # Unit with optional power prefix, optional SI prefix, and base unit
      optional(power_prefix())
      |> choice([
        base_unit(),
        si_prefix() |> concat(base_unit())
      ])
      |> reduce(:wrap_single_unit),
      # Numeric constant (e.g., 100, 1e6)
      unit_constant()
    ])
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
        {:si_prefix, value} -> String.to_atom(value)
        nil -> nil
      end

    base =
      case Enum.find(parts, &match?({:base, _}, &1)) do
        {:base, value} -> value
        nil -> nil
      end

    {:single_unit, prefix: si_prefix, power: power, base: base}
  end

  # ── Product unit ────────────────────────────────────────────────────

  @doc false
  def product_unit do
    single_unit()
    |> repeat(
      lookahead_not(string("-per-"))
      |> lookahead_not(string("-and-"))
      |> ignore(string("-"))
      |> concat(single_unit())
    )
    |> tag(:product)
  end

  # ── Core unit identifier ────────────────────────────────────────────

  @doc false
  def core_unit_identifier do
    choice([
      # Leading "per-" (empty numerator)
      ignore(string("per-"))
      |> concat(product_unit())
      |> repeat(ignore(string("-per-")) |> concat(product_unit()))
      |> reduce(:wrap_per_leading),
      # Normal: numerator with optional -per- denominator(s)
      product_unit()
      |> repeat(ignore(string("-per-")) |> concat(product_unit()))
      |> reduce(:wrap_core_unit)
    ])
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

  # ── Category ────────────────────────────────────────────────────────

  @doc false
  def category do
    @categories
    |> Enum.sort_by(&(-String.length(&1)))
    |> Enum.map(&string/1)
    |> choice()
  end

  # ── Long unit identifier (with category prefix) ─────────────────────

  @doc false
  def long_unit_identifier do
    category()
    |> ignore(string("-"))
    |> concat(core_unit_identifier())
    |> reduce(:wrap_long_unit)
  end

  @doc false
  def wrap_long_unit([category_name, {:unit, keyword}]) do
    {:unit, Keyword.put(keyword, :type, category_name)}
  end

  # ── Mixed unit identifier ───────────────────────────────────────────

  @doc false
  def mixed_unit_identifier do
    single_unit()
    |> times(ignore(string("-and-")) |> concat(single_unit()), min: 1)
    |> reduce(:wrap_mixed_unit)
  end

  @doc false
  def wrap_mixed_unit(units) do
    {:mixed_unit, units}
  end

  # ── Top-level ───────────────────────────────────────────────────────

  @doc false
  def unit_identifier do
    choice([
      mixed_unit_identifier(),
      core_unit_identifier(),
      long_unit_identifier()
    ])
    |> eos()
  end
end
