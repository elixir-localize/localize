defmodule Localize.Data.UnicodeData do
  @moduledoc false

  # Parses Unicode Character Database text files to generate
  # compact ETF lookup tables for the collation system.

  @unicode_dir "priv/unicode"

  @doc """
  Generates the combining class lookup map from
  `DerivedCombiningClass.txt`.

  Returns a map of `%{codepoint => combining_class}` containing
  only non-zero entries. Codepoint ranges are expanded to
  individual entries for O(1) lookup.

  """
  def generate_combining_classes do
    path = Path.join(File.cwd!(), Path.join(@unicode_dir, "combining_class.txt"))

    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      line = line |> String.split("#") |> hd() |> String.trim()

      case parse_combining_class_line(line) do
        nil -> acc
        {_range, 0} -> acc
        {range, class} -> expand_range(range, class, acc)
      end
    end)
  end

  defp parse_combining_class_line(""), do: nil

  defp parse_combining_class_line(line) do
    case String.split(line, ";") do
      [range_str, class_str] ->
        class = class_str |> String.trim() |> String.to_integer()
        range = parse_codepoint_range(String.trim(range_str))
        {range, class}

      _ ->
        nil
    end
  end

  @doc """
  Generates the decimal digit ranges from
  `DerivedGeneralCategory.txt`.

  Returns a sorted list of `{start, finish}` codepoint range
  tuples where the general category is `Nd` (Decimal Number).

  """
  def generate_decimal_digit_ranges do
    path = Path.join(File.cwd!(), Path.join(@unicode_dir, "general_category.txt"))

    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce([], fn line, acc ->
      line = line |> String.split("#") |> hd() |> String.trim()

      case parse_category_line(line) do
        {:ok, range, "Nd"} -> [range | acc]
        _ -> acc
      end
    end)
    |> Enum.sort()
  end

  defp parse_category_line(""), do: nil

  defp parse_category_line(line) do
    case String.split(line, ";") do
      [range_str, category_str] ->
        {:ok, parse_codepoint_range(String.trim(range_str)), String.trim(category_str)}

      _ ->
        nil
    end
  end

  defp parse_codepoint_range(str) do
    case String.split(str, "..") do
      [single] ->
        cp = String.to_integer(single, 16)
        {cp, cp}

      [from, to] ->
        {String.to_integer(from, 16), String.to_integer(to, 16)}
    end
  end

  defp expand_range({start, finish}, class, acc) do
    Enum.reduce(start..finish, acc, fn cp, map ->
      Map.put(map, cp, class)
    end)
  end
end
