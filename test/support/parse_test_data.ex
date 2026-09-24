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

  # Every key the fixture uses, after renaming, written here so the atoms
  # exist whichever test module compiles first. A key missing from this list
  # makes the parser raise; add it here.
  @known_keys ~w(locale input expected calendar semantic_skeleton skeleton
                 semantic_skeleton_length zone_style time_format date_format hour_cycle
                 year_style style)a

  @keys_by_name Map.new(@known_keys, &{Atom.to_string(&1), &1})

  # The values the atomised keys take that tests compare against atoms. Any
  # other value (`islamic-civil`) stays a string and simply matches nothing.
  @known_values ~w(gregorian buddhist japanese short medium long full standard)a

  @values_by_name Map.new(@known_values, &{Atom.to_string(&1), &1})

  # Every multi-field classical skeleton the fixture uses, written here so the
  # atoms come from source code rather than being minted from the file. The
  # parser runs at compile time of the conformance module, before any locale
  # data is loaded, so none of these exist otherwise — and several (the
  # semantic-derived `yMMMdEEE`) are resolved by best-match and never appear
  # as an `availableFormats` key at all. A skeleton missing from this list
  # makes the parser raise rather than create an atom; add it here.
  @known_skeletons ~w(GGGGGyMdEEE GyMMMMdEEEE GyMMMdEEE GyMMMdEEEE GyMdEEE Hms
                      MMMMdjmsO MMMMdjmsVVVV MMMMdjmsv MMMMdjmsz MMMdjmsO MMMdjmsVVVV
                      MMMdjmsv MMMdjmsz MdjmsO MdjmsVVVV Mdjmsv Mdjmsz hms jms
                      yMMMMdEEEE yMMMdEEE yyMdEEE)a

  @skeletons_by_name Map.new(@known_skeletons, &{Atom.to_string(&1), &1})

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

  # The fixture is a file, and atoms are never minted from file input — not
  # even in a test helper. Keys, values and skeletons come from the lists
  # above, so an unknown key or skeleton is a fixture change worth failing
  # on, and an unknown value (`islamic-civil`) stays a string and simply
  # matches nothing.
  defp atomize_keys(map) do
    Map.new(map, fn {key, value} ->
      atom_key = if is_binary(key), do: known_atom!(key), else: key
      {atom_key, value}
    end)
  end

  defp atomize_values(map, only) do
    Enum.reduce(only, map, fn key, acc ->
      case Map.get(acc, key) do
        value when is_binary(value) ->
          Map.put(acc, key, Map.get(@values_by_name, value, value))

        _ ->
          acc
      end
    end)
  end

  defp maybe_atomize_skeleton(%{skeleton: skeleton} = test) when is_binary(skeleton) do
    cond do
      all_one_field?(skeleton) ->
        test

      Map.has_key?(@skeletons_by_name, skeleton) ->
        Map.put(test, :skeleton, Map.fetch!(@skeletons_by_name, skeleton))

      true ->
        raise ArgumentError,
              "date_time_formatting.json uses skeleton #{inspect(skeleton)}, which is " <>
                "not in @known_skeletons in #{__ENV__.file}"
    end
  end

  defp maybe_atomize_skeleton(test), do: test

  defp known_atom!(string) do
    Map.get(@keys_by_name, string) ||
      raise ArgumentError,
            "date_time_formatting.json uses key #{inspect(string)}, which is not in " <>
              "@known_keys in #{__ENV__.file}"
  end

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
      {:ok, shifted} ->
        shifted

      {:error, _} when timezone == "Etc/GMT" ->
        %{datetime | time_zone: "Etc/GMT", zone_abbr: "GMT"}

      {:error, _} ->
        datetime
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
