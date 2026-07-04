defmodule Localize.Unit.BaseUnit do
  @moduledoc """
  Converts parsed unit ASTs into their CLDR base unit equivalents.

  Each unit in CLDR maps to a base unit string expressed in terms of
  fundamental units (meter, kilogram, second, ampere, kelvin, candela,
  revolution, item, part, bit, pixel, em, year, night). This module
  decomposes any parsed unit AST into those fundamentals and reconstructs
  the canonical base unit string.

  Powers are fully simplified across the expression. For example,
  `liter-per-kilometer` (volume/length) simplifies to `square-meter`
  and `kilowatt-hour` (power × time) simplifies to
  `kilogram-square-meter-per-square-second` (energy).

  """

  defp simple_base_units do
    cached(:simple_base_units_sorted, fn ->
      Localize.Unit.Data.simple_base_units()
      |> Enum.sort_by(&(-String.length(&1)))
    end)
  end

  defp simple_unit_order do
    cached(:simple_unit_order, fn ->
      Localize.Unit.Data.simple_base_units()
      |> Enum.with_index()
      |> Map.new()
    end)
  end

  @compile {:inline, cached: 2}
  defp cached(key, build_fn) do
    pt_key = {__MODULE__, key}

    case :persistent_term.get(pt_key, :__not_loaded__) do
      :__not_loaded__ ->
        value = build_fn.()
        :persistent_term.put(pt_key, value)
        value

      value ->
        value
    end
  end

  @doc """
  Returns the base unit string for a parsed unit AST or a unit identifier string.

  ### Arguments

  * `input` is either a parsed unit AST tuple or a unit identifier string.

  ### Returns

  * `{:ok, base_unit_string}` where `base_unit_string` is the canonical
    CLDR base unit identifier, or

  * `{:error, reason}` if the unit cannot be resolved.

  ### Examples

      iex> Localize.Unit.BaseUnit.base_unit("foot")
      {:ok, "meter"}

      iex> Localize.Unit.BaseUnit.base_unit("newton")
      {:ok, "kilogram-meter-per-square-second"}

      iex> Localize.Unit.BaseUnit.base_unit("mile-per-hour")
      {:ok, "meter-per-second"}

  """
  @spec base_unit(String.t() | tuple()) ::
          {:ok, String.t()} | {:error, Exception.t() | String.t()}
  @dialyzer {:nowarn_function, base_unit: 1}

  def base_unit(input) when is_binary(input) do
    case Localize.Unit.Parser.parse(input) do
      {:ok, ast} -> base_unit(ast)
      {:error, _} = error -> error
    end
  end

  def base_unit(ast) when is_tuple(ast) do
    case decompose(ast) do
      {:ok, powers} -> {:ok, recompose(powers)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Returns the base unit string for a parsed unit AST or a unit identifier
  string, raising on error.

  Same as `base_unit/1` but returns the string directly or raises
  `ArgumentError`.

  ### Arguments

  * `input` is either a parsed unit AST tuple or a unit identifier string.

  ### Returns

  * A canonical CLDR base unit string.

  ### Examples

      iex> Localize.Unit.BaseUnit.base_unit!("foot")
      "meter"

  """
  @spec base_unit!(String.t() | tuple()) :: String.t() | no_return()
  @dialyzer {:nowarn_function, base_unit!: 1}

  def base_unit!(input) do
    case base_unit(input) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Decomposes a parsed unit AST into a map of fundamental unit powers.

  Positive powers represent numerator units and negative powers represent
  denominator units. Powers are fully simplified across the expression.

  ### Arguments

  * `ast` is a parsed unit AST tuple.

  ### Returns

  * `{:ok, powers}` where `powers` is a map like `%{"meter" => 1, "second" => -2}`, or

  * `{:error, reason}` if the unit cannot be resolved.

  ### Examples

      iex> {:ok, ast} = Localize.Unit.Parser.parse("newton")
      iex> Localize.Unit.BaseUnit.decompose(ast)
      {:ok, %{"kilogram" => 1, "meter" => 1, "second" => -2}}

  """
  @spec decompose(tuple()) :: {:ok, %{String.t() => integer()}} | {:error, String.t()}

  def decompose({:unit, keyword}) do
    numerator = Keyword.get(keyword, :numerator, [])
    denominator = Keyword.get(keyword, :denominator, [])

    with {:ok, num_powers} <- decompose_list(numerator),
         {:ok, den_powers} <- decompose_list(denominator) do
      negated = Map.new(den_powers, fn {unit, power} -> {unit, -power} end)
      {:ok, merge_powers(num_powers, negated)}
    end
  end

  def decompose({:mixed_unit, [first | _rest]}) do
    decompose_single(first)
  end

  def decompose({:single_unit, _} = single) do
    decompose_single(single)
  end

  @doc """
  Reconstructs a canonical base unit string from a powers map.

  ### Arguments

  * `powers` is a map of fundamental unit name to integer power where
    positive values are in the numerator and negative in the denominator.

  ### Returns

  * A canonical CLDR base unit string.

  ### Examples

      iex> Localize.Unit.BaseUnit.recompose(%{"kilogram" => 1, "meter" => 1, "second" => -2})
      "kilogram-meter-per-square-second"

  """
  @spec recompose(%{String.t() => integer()}) :: String.t()

  def recompose(powers) when powers == %{}, do: ""

  def recompose(powers) do
    {numerator, denominator} =
      powers
      |> Enum.reject(fn {_unit, power} -> power == 0 end)
      |> Enum.split_with(fn {_unit, power} -> power > 0 end)

    num_sorted = sort_by_canonical_order(numerator)
    den_sorted = sort_by_canonical_order(denominator)

    num_string = format_product(num_sorted)

    den_string =
      den_sorted
      |> Enum.map(fn {unit, power} -> {unit, abs(power)} end)
      |> format_product()

    case {num_string, den_string} do
      {"", ""} -> ""
      {num, ""} -> num
      {"", den} -> "per-" <> den
      {num, den} -> num <> "-per-" <> den
    end
  end

  # ── Private helpers ─────────────────────────────────────────────────

  defp decompose_list(units) do
    Enum.reduce_while(units, {:ok, %{}}, fn unit, {:ok, acc} ->
      case decompose_single(unit) do
        {:ok, powers} -> {:cont, {:ok, merge_powers(acc, powers)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp decompose_single({:single_unit, keyword}) do
    base = Keyword.fetch!(keyword, :base)
    power = Keyword.get(keyword, :power)

    case resolve_base_unit(base) do
      {:ok, base_powers} ->
        {:ok, apply_power(base_powers, power)}

      {:error, _} = error ->
        error
    end
  end

  defp decompose_single({:constant, _value}) do
    {:ok, %{}}
  end

  defp resolve_base_unit("curr-" <> _code = currency_base) do
    {:ok, %{currency_base => 1}}
  end

  defp resolve_base_unit(name) do
    case Localize.Unit.Data.Overlay.conversion(name) do
      nil ->
        {:error, Localize.UnknownUnitError.exception(unit: name)}

      base_unit_string ->
        {:ok, parse_base_unit_string(base_unit_string)}
    end
  end

  defp parse_base_unit_string("per-" <> den_str) do
    parse_product_string(den_str, -1)
  end

  defp parse_base_unit_string(string) do
    case String.split(string, "-per-", parts: 2) do
      [num_str] ->
        parse_product_string(num_str, 1)

      [num_str, den_str] ->
        num_powers = parse_product_string(num_str, 1)
        den_powers = parse_product_string(den_str, -1)
        merge_powers(num_powers, den_powers)
    end
  end

  defp parse_product_string("", _sign), do: %{}

  defp parse_product_string(string, sign) do
    parse_product_tokens(string, sign, %{})
  end

  defp parse_product_tokens("", _sign, acc), do: acc

  defp parse_product_tokens(string, sign, acc) do
    {power_mult, rest} = consume_power_prefix(string)
    {unit_name, remainder} = consume_simple_unit(rest)

    new_acc = Map.update(acc, unit_name, sign * power_mult, &(&1 + sign * power_mult))

    case remainder do
      "" -> new_acc
      "-" <> tail -> parse_product_tokens(tail, sign, new_acc)
      _ -> new_acc
    end
  end

  defp consume_power_prefix("square-" <> rest), do: {2, rest}
  defp consume_power_prefix("cubic-" <> rest), do: {3, rest}

  defp consume_power_prefix("pow" <> rest) do
    case Integer.parse(rest) do
      {n, "-" <> tail} -> {n, tail}
      _ -> {1, "pow" <> rest}
    end
  end

  defp consume_power_prefix(string), do: {1, string}

  defp consume_simple_unit(string) do
    match =
      simple_base_units()
      |> Enum.find(fn unit -> String.starts_with?(string, unit) end)

    case match do
      nil ->
        case String.split(string, "-", parts: 2) do
          [token, rest] -> {token, "-" <> rest}
          [token] -> {token, ""}
        end

      unit ->
        rest = String.slice(string, String.length(unit)..-1//1)
        {unit, rest}
    end
  end

  defp apply_power(powers, nil), do: powers
  defp apply_power(powers, :square), do: Map.new(powers, fn {u, p} -> {u, p * 2} end)
  defp apply_power(powers, :cubic), do: Map.new(powers, fn {u, p} -> {u, p * 3} end)
  defp apply_power(powers, {:pow, n}), do: Map.new(powers, fn {u, p} -> {u, p * n} end)

  defp merge_powers(map1, map2) do
    Map.merge(map1, map2, fn _key, v1, v2 -> v1 + v2 end)
    |> Enum.reject(fn {_key, value} -> value == 0 end)
    |> Map.new()
  end

  defp sort_by_canonical_order(units) do
    order = simple_unit_order()

    Enum.sort_by(units, fn {unit, _power} ->
      Map.get(order, unit, 999)
    end)
  end

  defp format_product([]), do: ""

  defp format_product(units) do
    units
    |> Enum.map_join("-", fn {unit, power} -> format_powered_unit(unit, power) end)
  end

  defp format_powered_unit(unit, 1), do: unit
  defp format_powered_unit(unit, 2), do: "square-#{unit}"
  defp format_powered_unit(unit, 3), do: "cubic-#{unit}"
  defp format_powered_unit(unit, n), do: "pow#{n}-#{unit}"
end
