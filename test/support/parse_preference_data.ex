defmodule Localize.Test.PreferenceData do
  @moduledoc false

  @preference_test_data "test/support/data/preference_test_data.txt"
  @external_resource @preference_test_data

  def preferences do
    @preference_test_data
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.with_index(1)
    |> Enum.map(&parse_test/1)
    |> Enum.reject(&is_nil/1)
  end

  @fields [:quantity, :usage, :region, :input_rational, :input_double, :input_unit, :output]

  defp parse_test({"", _}), do: nil
  defp parse_test({<<"#", _rest::binary>>, _}), do: nil

  defp parse_test({test, index}) do
    parts =
      test
      |> String.split(";")
      |> Enum.map(&String.trim/1)

    {input, output} = :lists.split(6, parts)

    fields =
      @fields
      |> Enum.zip(input ++ [output])
      |> Enum.map(&transform/1)

    output_units = extract_output_units(Keyword.get(fields, :output))

    fields
    |> Keyword.put(:output_units, output_units)
    |> Keyword.put(:line, index)
    |> Map.new()
  end

  defp extract_output_units(output) do
    Enum.map(output, fn {unit_name, _values} ->
      unit_name
      |> String.replace("-", "_")
      |> String.to_atom()
    end)
  end

  defp transform({:output, parts}) do
    # Output parts come in groups of 3 (rational, double, unit) for single units
    # or 5 (int, unit, rational, double, unit) for mixed units like foot-and-inch
    parsed = parse_output_parts(parts)
    {:output, parsed}
  end

  defp transform({:input_double, string}), do: {:input_double, parse_number(string)}
  defp transform({:input_rational, string}), do: {:input_rational, parse_rational(string)}
  defp transform({:region, string}), do: {:region, String.to_atom(string)}

  defp transform({:usage, string}) do
    {:usage, string |> String.replace("-", "_") |> String.to_atom()}
  end

  defp transform({:input_unit, string}), do: {:input_unit, string}
  defp transform(other), do: other

  defp parse_output_parts(parts) do
    case parts do
      [rational, double, unit] ->
        [{unit, [rational, double]}]

      [first_int, first_unit, rational, double, unit] ->
        [{first_unit, [first_int, nil]}, {unit, [rational, double]}]

      _ ->
        # Handle other mixed unit patterns
        parse_mixed_output(parts, [])
    end
  end

  defp parse_mixed_output([], acc), do: Enum.reverse(acc)
  defp parse_mixed_output([int, unit, rational, double, last_unit], acc) do
    Enum.reverse([{last_unit, [rational, double]}, {unit, [int, nil]} | acc])
  end
  defp parse_mixed_output([int, unit | rest], acc) do
    parse_mixed_output(rest, [{unit, [int, nil]} | acc])
  end

  defp parse_number(string) do
    case Float.parse(string) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_rational(string) do
    case String.split(string, "/") do
      [num, den] ->
        Decimal.div(String.to_integer(String.trim(num)), String.to_integer(String.trim(den)))

      [int] ->
        String.to_integer(String.trim(int))
    end
  end
end
