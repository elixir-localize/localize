defmodule Localize.Unit.Conversion do
  @moduledoc """
  Converts numeric values between CLDR units of measure.

  Two units are convertible if they reduce to the same base unit.
  The conversion goes through the base unit:
  `source_value → base_value → target_value`.

  For simple units: `base_value = source_value * factor + offset`.
  For compound units (products and per-expressions), the total factor
  is the product of all component factors raised to their respective
  powers.

  """

  alias Localize.Unit.{BaseUnit, Parser}

  @doc """
  Checks whether two units are convertible (same dimensional base unit).

  ### Arguments

  * `unit_1` is a unit identifier string or parsed AST.

  * `unit_2` is a unit identifier string or parsed AST.

  ### Returns

  * `true` if the units are convertible, `false` otherwise.

  ### Examples

      iex> Localize.Unit.Conversion.convertible?("foot", "meter")
      true

      iex> Localize.Unit.Conversion.convertible?("foot", "kilogram")
      false

  """
  @spec convertible?(String.t() | tuple(), String.t() | tuple()) :: boolean()

  def convertible?(unit_1, unit_2) do
    with {:ok, base_1} <- BaseUnit.base_unit(unit_1),
         {:ok, base_2} <- BaseUnit.base_unit(unit_2) do
      base_1 == base_2
    else
      _ -> false
    end
  end

  @doc """
  Converts a numeric value from one unit to another.

  Both units must be of the same category (convertible). Accepts
  integers, floats, and Decimal values.

  ### Arguments

  * `value` is the numeric value to convert (integer, float, or Decimal).

  * `from` is the source unit identifier string.

  * `to` is the target unit identifier string.

  ### Returns

  * `{:ok, converted_value}` where the result is a float, or

  * `{:error, reason}` if the units cannot be parsed or are not convertible.

  ### Examples

      iex> Localize.Unit.Conversion.convert(1, "kilometer", "meter")
      {:ok, 1000.0}

      iex> Localize.Unit.Conversion.convert(32, "fahrenheit", "celsius")
      {:ok, 0.0}

  """
  @spec convert(number() | Decimal.t(), String.t(), String.t()) ::
          {:ok, float() | Decimal.t()} | {:error, Exception.t() | String.t()}
  @dialyzer {:nowarn_function, convert: 3}

  def convert(value, from, to) do
    with {:ok, parsed_from} <- Parser.parse(from),
         {:ok, parsed_to} <- Parser.parse(to),
         true <- convertible?(parsed_from, parsed_to) do
      case value do
        %Decimal{} -> do_convert_decimal(value, parsed_from, parsed_to)
        _ -> do_convert(to_float(value), parsed_from, parsed_to)
      end
    else
      false ->
        {:error,
         Localize.UnitConversionError.exception(from: from, to: to, reason: :not_convertible)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Converts a numeric value from one unit to another, raising on error.

  Same as `convert/3` but returns the value directly or raises
  `ArgumentError`.

  ### Arguments

  * `value` is the numeric value to convert.

  * `from` is the source unit identifier string.

  * `to` is the target unit identifier string.

  ### Returns

  * The converted value as a float.

  ### Examples

      iex> Localize.Unit.Conversion.convert!(1000, "meter", "kilometer")
      1.0

  """
  @spec convert!(number() | Decimal.t(), String.t(), String.t()) ::
          float() | Decimal.t() | no_return()

  def convert!(value, from, to) do
    case convert(value, from, to) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  # Decimal-typed conversion path. Conversion factors and offsets are
  # stored as floats (CLDR ships them as exact rationals but our pipeline
  # collapses them to floats during ingestion); we coerce them to Decimal
  # at the boundary via `Decimal.from_float/1`. Intermediate arithmetic
  # then runs in Decimal so we don't accumulate float-rounding error
  # across the multiply/divide chain. Special (nonlinear) conversions
  # like Beaufort fall back to the float path because their forward/
  # inverse functions aren't Decimal-aware.
  defp do_convert_decimal(value, from_ast, to_ast) do
    case {special_unit(from_ast), special_unit(to_ast)} do
      {nil, nil} ->
        with {:ok, from_params} <- conversion_params(from_ast),
             {:ok, to_params} <- conversion_params(to_ast) do
          base_value =
            value
            |> Decimal.mult(Decimal.from_float(from_params.factor))
            |> add_offset(from_params.offset)

          result =
            base_value
            |> sub_offset(to_params.offset)
            |> Decimal.div(Decimal.from_float(to_params.factor))

          {:ok, result}
        end

      _special ->
        do_convert(Decimal.to_float(value), from_ast, to_ast)
    end
  end

  defp add_offset(value, +0.0), do: value
  defp add_offset(value, offset), do: Decimal.add(value, Decimal.from_float(offset))

  defp sub_offset(value, +0.0), do: value
  defp sub_offset(value, offset), do: Decimal.sub(value, Decimal.from_float(offset))

  defp do_convert(value, from_ast, to_ast) do
    case {special_unit(from_ast), special_unit(to_ast)} do
      {{:special, fwd, _inv}, nil} ->
        base_value = apply(elem(fwd, 0), elem(fwd, 1), [value])
        convert_from_base(base_value, to_ast)

      {nil, {:special, _fwd, inv}} ->
        with {:ok, from_params} <- conversion_params(from_ast) do
          base_value = value * from_params.factor + from_params.offset
          {:ok, apply(elem(inv, 0), elem(inv, 1), [base_value])}
        end

      {{:special, fwd, _}, {:special, _, inv}} ->
        base_value = apply(elem(fwd, 0), elem(fwd, 1), [value])
        {:ok, apply(elem(inv, 0), elem(inv, 1), [base_value])}

      {nil, nil} ->
        with {:ok, from_params} <- conversion_params(from_ast),
             {:ok, to_params} <- conversion_params(to_ast) do
          base_value = value * from_params.factor + from_params.offset
          result = (base_value - to_params.offset) / to_params.factor
          {:ok, result}
        end
    end
  end

  defp convert_from_base(base_value, to_ast) do
    with {:ok, to_params} <- conversion_params(to_ast) do
      result = (base_value - to_params.offset) / to_params.factor
      {:ok, result}
    end
  end

  # Compute the total factor and offset for a parsed unit AST.
  # For compound units, offset is always 0 (offsets only apply to
  # simple temperature-like units).
  defp conversion_params({:unit, keyword}) do
    numerator = Keyword.get(keyword, :numerator, [])
    denominator = Keyword.get(keyword, :denominator, [])

    with {:ok, num_factor} <- product_factor(numerator),
         {:ok, den_factor} <- product_factor(denominator) do
      total_factor = num_factor / den_factor

      # Offset only applies to single simple units (temperature conversions)
      offset = single_unit_offset(numerator, denominator)

      {:ok, %{factor: total_factor, offset: offset}}
    end
  end

  defp conversion_params({:mixed_unit, _units}) do
    {:error, Localize.UnitConversionError.exception(reason: :mixed_units)}
  end

  defp product_factor([]), do: {:ok, 1.0}

  defp product_factor(units) do
    Enum.reduce_while(units, {:ok, 1.0}, fn unit, {:ok, acc} ->
      case single_factor(unit) do
        {:ok, factor} -> {:cont, {:ok, acc * factor}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp single_factor({:single_unit, keyword}) do
    case Keyword.fetch!(keyword, :base) do
      "curr-" <> _code ->
        {:ok, 1.0}

      base ->
        prefix = Keyword.get(keyword, :prefix)
        power = Keyword.get(keyword, :power)
        factor_for_base(base, Localize.Unit.Data.Overlay.conversion_factor(base), prefix, power)
    end
  end

  defp single_factor({:constant, value_string}) do
    value =
      if String.contains?(value_string, "e") do
        {v, ""} = Float.parse("1" <> String.replace(value_string, "1e", "e"))
        v
      else
        {v, ""} = Float.parse(value_string)
        v
      end

    {:ok, value}
  end

  defp factor_for_base(base, nil, _prefix, _power) do
    {:error, Localize.UnknownUnitError.exception(unit: base)}
  end

  defp factor_for_base(base, %{factor: :special}, _prefix, _power) do
    {:error,
     Localize.UnitConversionError.exception(
       from: base,
       reason: :special_conversion
     )}
  end

  defp factor_for_base(_base, %{factor: base_factor}, prefix, power) do
    total = base_factor * prefix_multiplier(prefix)
    {:ok, apply_power_to_factor(total, power)}
  end

  defp prefix_multiplier(nil), do: 1.0

  defp prefix_multiplier(prefix) do
    Map.get(Localize.Unit.Data.si_prefix_multipliers(), Atom.to_string(prefix), 1.0)
  end

  # Offset only applies when there is exactly one simple unit in the
  # numerator and nothing in the denominator — i.e., a non-compound unit
  # like "fahrenheit" or "celsius".
  defp single_unit_offset([{:single_unit, keyword}], []) do
    base = Keyword.fetch!(keyword, :base)
    prefix = Keyword.get(keyword, :prefix)

    if prefix == nil do
      case Localize.Unit.Data.Overlay.conversion_factor(base) do
        %{offset: offset} when offset != 0.0 -> offset
        _ -> 0.0
      end
    else
      0.0
    end
  end

  defp single_unit_offset(_numerator, _denominator), do: 0.0

  defp apply_power_to_factor(factor, nil), do: factor
  defp apply_power_to_factor(factor, :square), do: factor * factor
  defp apply_power_to_factor(factor, :cubic), do: factor * factor * factor
  defp apply_power_to_factor(factor, {:pow, n}), do: :math.pow(factor, n)

  # ── Special (nonlinear) conversion detection ─────────────────────

  # Built-in special conversions compiled from CLDR data. These are
  # always available without requiring CustomRegistry registration.
  @built_in_special %{
    "beaufort" => {
      {Localize.Unit.Conversion.Beaufort, :forward},
      {Localize.Unit.Conversion.Beaufort, :inverse}
    }
  }

  # Detect if a parsed AST represents a unit with a registered special
  # conversion (forward/inverse functions). Only simple units without
  # SI prefixes or power prefixes qualify — compound units cannot be special.
  defp special_unit({:unit, keyword}) do
    with [{:single_unit, opts}] <- Keyword.get(keyword, :numerator, []),
         [] <- Keyword.get(keyword, :denominator, []),
         nil <- Keyword.get(opts, :prefix),
         nil <- Keyword.get(opts, :power),
         base when is_binary(base) <- Keyword.get(opts, :base),
         %{factor: :special} <- Localize.Unit.Data.Overlay.conversion_factor(base) do
      lookup_special(base)
    else
      _ -> nil
    end
  end

  defp special_unit({:mixed_unit, _}), do: nil

  defp lookup_special(name) do
    case Localize.Unit.CustomRegistry.get(name) do
      %{forward: fwd, inverse: inv} ->
        {:special, fwd, inv}

      _ ->
        case Map.get(@built_in_special, name) do
          {fwd, inv} -> {:special, fwd, inv}
          nil -> nil
        end
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(value) when is_float(value), do: value
end
