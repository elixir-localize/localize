defmodule Localize.Unit.Data.Expression do
  @moduledoc false

  # Compile-time helpers for evaluating CLDR unit constant expressions.
  # This module is compiled before Localize.Unit.Data so its functions
  # are available during Data's module body evaluation.

  @doc false
  def parse_number(string) do
    cleaned = String.replace(string, " ", "")

    cond do
      String.contains?(cleaned, "/") ->
        [num, den] = String.split(cleaned, "/", parts: 2)
        parse_number(num) / parse_number(den)

      String.contains?(cleaned, ".") or String.contains?(String.upcase(cleaned), "E") ->
        {value, ""} = Float.parse(cleaned)
        value

      true ->
        String.to_integer(cleaned) * 1.0
    end
  end

  @doc false
  def evaluate_expression(expression, constants) do
    # CLDR expressions use the form: A*B*C/D*E*F
    # where "/" splits numerator from denominator.
    # Everything before the first "/" is the numerator product,
    # everything after is the denominator product.
    cleaned = String.replace(expression, " ", "")

    {numerator_str, denominator_str} =
      case String.split(cleaned, "/", parts: 2) do
        [num] -> {num, nil}
        [num, den] -> {num, den}
      end

    numerator = evaluate_product(numerator_str, constants)

    if denominator_str do
      denominator = evaluate_product(denominator_str, constants)
      numerator / denominator
    else
      numerator
    end
  end

  defp evaluate_product(string, constants) do
    string
    |> String.split("*")
    |> Enum.map(&resolve_token(&1, constants))
    |> Enum.reduce(&(&2 * &1))
  end

  defp resolve_token(token, constants) do
    case Map.get(constants, token) do
      nil -> parse_number(token)
      value -> value
    end
  end

  @doc false
  def resolve_all(all_raw, resolved) when map_size(all_raw) == map_size(resolved), do: resolved

  def resolve_all(all_raw, resolved) do
    newly_resolved =
      all_raw
      |> Enum.reject(fn {c, _} -> Map.has_key?(resolved, c) end)
      |> Enum.filter(fn {_c, expr} ->
        refs =
          Regex.scan(~r/[a-zA-Z_][a-zA-Z_0-9]*/, expr)
          |> List.flatten()
          |> Enum.reject(fn token -> String.match?(token, ~r/^\d/) end)

        Enum.all?(refs, &Map.has_key?(resolved, &1))
      end)
      |> Map.new(fn {c, expr} -> {c, evaluate_expression(expr, resolved)} end)

    if map_size(newly_resolved) == 0 do
      resolved
    else
      resolve_all(all_raw, Map.merge(resolved, newly_resolved))
    end
  end
end
