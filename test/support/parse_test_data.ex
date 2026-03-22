defmodule Localize.DateTime.TestData do
  @moduledoc false

  # Adapted from Cldr.DateTime.TestData. Parses the CLDR
  # date_time_formatting.json test data file into structured
  # test case maps suitable for ExUnit test generation.

  @path "test/support/data/date_time_formatting.json"

  def parse do
    @path
    |> File.read!()
    |> :json.decode()
    |> Enum.with_index(&format_test/2)
  end

  def test(n) do
    parse()
    |> Enum.find(&(&1.index == n))
  end

  @rename_keys %{
    "timeLength" => "time_format",
    "dateLength" => "date_format",
    "semanticSkeleton" => "semantic_skeleton",
    "semanticSkeletonLength" => "semantic_skeleton_length",
    "classicalSkeleton" => "skeleton",
    "yearStyle" => "year_style",
    "zoneStyle" => "zone_style",
    "hourCycle" => "hour_cycle",
    "dateTimeFormatType" => "style"
  }

  @atomize_values [:calendar, :time_format, :date_format, :date_time_format_type, :style]

  def format_test(test, index) do
    test
    |> rename_keys()
    |> atomize_keys()
    |> atomize_values(@atomize_values)
    |> maybe_atomize_skeleton()
    |> Map.put(:index, index + 1)
    |> parse_input()
    |> determine_test_module()
    |> ensure_style_for_date_time()
  end

  defp rename_keys(map) do
    Enum.reduce(@rename_keys, map, fn {old, new}, acc ->
      case Map.pop(acc, old) do
        {nil, acc} -> acc
        {value, acc} -> Map.put(acc, new, value)
      end
    end)
  end

  defp atomize_keys(map) do
    Map.new(map, fn {key, value} ->
      atom_key = if is_binary(key), do: String.to_atom(key), else: key
      {atom_key, value}
    end)
  end

  defp atomize_values(map, only) do
    Enum.reduce(only, map, fn key, acc ->
      case Map.get(acc, key) do
        value when is_binary(value) -> Map.put(acc, key, String.to_atom(value))
        _ -> acc
      end
    end)
  end

  defp maybe_atomize_skeleton(%{skeleton: skeleton} = test) when is_binary(skeleton) do
    if all_one_field?(skeleton) do
      test
    else
      Map.put(test, :skeleton, String.to_atom(skeleton))
    end
  end

  defp maybe_atomize_skeleton(test), do: test

  defp all_one_field?(skeleton) do
    field_list =
      skeleton
      |> String.graphemes()
      |> Enum.chunk_by(& &1)

    length(field_list) == 1
  end

  defp ensure_style_for_date_time(%{test_module: Localize.DateTime} = test) do
    Map.put_new(test, :style, :at)
  end

  defp ensure_style_for_date_time(test), do: test

  defp parse_input(test) do
    case test.input do
      <<datetime::binary-19, "Z[", rest::binary>> ->
        timezone = String.trim_trailing(rest, "]")
        datetime = datetime <> "Z"
        Map.put(test, :input, parse_date(datetime, timezone))

      <<datetime::binary-16, "Z[", rest::binary>> ->
        timezone = String.trim_trailing(rest, "]")
        datetime = datetime <> ":00" <> "Z"
        Map.put(test, :input, parse_date(datetime, timezone))

      <<datetime::binary-16, "+", offset::binary-5, "[", rest::binary>> ->
        timezone = String.trim_trailing(rest, "]")
        datetime = datetime <> ":00" <> "+" <> offset
        Map.put(test, :input, parse_date(datetime, timezone))

      <<datetime::binary-19, "+", offset::binary-5, "[", rest::binary>> ->
        timezone = String.trim_trailing(rest, "]")
        datetime = datetime <> "+" <> offset
        Map.put(test, :input, parse_date(datetime, timezone))
    end
  end

  def parse_date(datetime, timezone) do
    {:ok, datetime, _} = DateTime.from_iso8601(datetime)

    case DateTime.shift_zone(datetime, timezone) do
      {:ok, shifted} -> shifted
      {:error, _} -> datetime
    end
  end

  defp determine_test_module(%{skeleton: _} = test) do
    Map.put(test, :test_module, Localize.DateTime)
  end

  defp determine_test_module(%{time_format: _, date_format: _} = test) do
    Map.put(test, :test_module, Localize.DateTime)
  end

  defp determine_test_module(%{date_format: _} = test) do
    Map.put(test, :test_module, Localize.Date)
  end

  defp determine_test_module(%{time_format: _} = test) do
    Map.put(test, :test_module, Localize.Time)
  end
end
