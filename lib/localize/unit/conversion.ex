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

  @conversion_factors Localize.Unit.Data.conversion_factors()
  @si_prefix_multipliers Localize.Unit.Data.si_prefix_multipliers()

  # Beaufort scale: minimum m/s threshold for each Beaufort number (0–18).
  # Index 18 is an artificial end value to give a reasonable midpoint for B=17.
  # Source: ICU4C units_converter.cpp minMetersPerSecForBeaufort[].
  @beaufort_thresholds {0.0, 0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7,
                        36.9, 41.4, 46.1, 51.1, 55.8, 61.4}
  @beaufort_max tuple_size(@beaufort_thresholds) - 2

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
  @spec convert(number(), String.t(), String.t()) :: {:ok, float()} | {:error, String.t()}

  def convert(value, from, to) do
    with {:ok, parsed_from} <- Parser.parse(from),
         {:ok, parsed_to} <- Parser.parse(to),
         true <- convertible?(parsed_from, parsed_to) do
      do_convert(to_float(value), parsed_from, parsed_to)
    else
      false ->
        {:error, "Units #{inspect(from)} and #{inspect(to)} are not convertible"}

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
  @spec convert!(number(), String.t(), String.t()) :: float() | no_return()

  def convert!(value, from, to) do
    case convert(value, from, to) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp do_convert(value, from_ast, to_ast) do
    case {special_unit(from_ast), special_unit(to_ast)} do
      {:beaufort, nil} ->
        # Beaufort → base (m/s) → target
        base_value = beaufort_to_mps(value)
        convert_from_base(base_value, to_ast)

      {nil, :beaufort} ->
        # Source → base (m/s) → Beaufort
        with {:ok, from_params} <- conversion_params(from_ast) do
          base_value = value * from_params.factor + from_params.offset
          {:ok, mps_to_beaufort(base_value)}
        end

      {:beaufort, :beaufort} ->
        {:ok, value}

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
    {:error, "Cannot compute conversion factor for mixed units (e.g., foot-and-inch)"}
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
    base = Keyword.fetch!(keyword, :base)
    prefix = Keyword.get(keyword, :prefix)
    power = Keyword.get(keyword, :power)

    case Map.get(@conversion_factors, base) do
      nil ->
        {:error, "Unknown unit for conversion: #{inspect(base)}"}

      %{factor: :special} ->
        {:error, "Special conversion not supported for: #{inspect(base)}"}

      %{factor: base_factor} ->
        prefix_mult =
          if prefix, do: Map.get(@si_prefix_multipliers, Atom.to_string(prefix), 1.0), else: 1.0

        total = base_factor * prefix_mult
        powered = apply_power_to_factor(total, power)
        {:ok, powered}
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

  # Offset only applies when there is exactly one simple unit in the
  # numerator and nothing in the denominator — i.e., a non-compound unit
  # like "fahrenheit" or "celsius".
  defp single_unit_offset([{:single_unit, keyword}], []) do
    base = Keyword.fetch!(keyword, :base)
    prefix = Keyword.get(keyword, :prefix)

    if prefix == nil do
      case Map.get(@conversion_factors, base) do
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

  # ── Beaufort special conversion ───────────────────────────────────

  # Detect if a parsed AST represents the beaufort unit.
  defp special_unit({:unit, keyword}) do
    case Keyword.get(keyword, :numerator, []) do
      [{:single_unit, opts}] ->
        if Keyword.get(opts, :base) == "beaufort" and Keyword.get(opts, :denominator, []) == [],
          do: :beaufort,
          else: nil

      _ ->
        nil
    end
  end

  defp special_unit(_), do: nil

  # Convert a Beaufort scale value to meters per second.
  # Values are clamped to the maximum defined Beaufort number (17).
  # The result is the midpoint between the threshold for floor(B) and ceil(B).
  defp beaufort_to_mps(beaufort) do
    clamped = min(max(beaufort, 0.0), @beaufort_max * 1.0)
    index = trunc(clamped)
    fraction = clamped - index

    low = elem(@beaufort_thresholds, index)
    high = elem(@beaufort_thresholds, index + 1)

    midpoint_low = (low + high) / 2.0

    if fraction == 0.0 do
      midpoint_low
    else
      next_index = min(index + 1, @beaufort_max)
      next_low = elem(@beaufort_thresholds, next_index)
      next_high = elem(@beaufort_thresholds, next_index + 1)
      midpoint_high = (next_low + next_high) / 2.0
      midpoint_low + fraction * (midpoint_high - midpoint_low)
    end
  end

  # Convert meters per second to a Beaufort scale value.
  # Finds the Beaufort band whose midpoint range contains the value.
  defp mps_to_beaufort(mps) do
    cond do
      mps < 0.0 ->
        0.0

      true ->
        find_beaufort_band(mps, 0)
    end
  end

  defp find_beaufort_band(_mps, index) when index >= @beaufort_max do
    @beaufort_max * 1.0
  end

  defp find_beaufort_band(mps, index) do
    low = elem(@beaufort_thresholds, index)
    high = elem(@beaufort_thresholds, index + 1)
    midpoint = (low + high) / 2.0

    next_low = elem(@beaufort_thresholds, index + 1)
    next_high = elem(@beaufort_thresholds, min(index + 2, tuple_size(@beaufort_thresholds) - 1))
    next_midpoint = (next_low + next_high) / 2.0

    if mps < next_midpoint do
      # Interpolate within this band
      if next_midpoint == midpoint do
        index * 1.0
      else
        index + (mps - midpoint) / (next_midpoint - midpoint)
      end
    else
      find_beaufort_band(mps, index + 1)
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(value) when is_float(value), do: value

  defp to_float(value) do
    if Code.ensure_loaded?(Decimal) and is_struct(value, Decimal) do
      Decimal.to_float(value)
    else
      raise ArgumentError, "Expected a number, got: #{inspect(value)}"
    end
  end
end
