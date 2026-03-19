defmodule Localize.LocaleDistanceTest do
  use ExUnit.Case, async: true

  @moduledoc false

  alias Localize.LanguageTag

  @data_file Path.join([__DIR__, "..", "support", "data", "locale_distance_test_data.txt"])

  @test_cases @data_file
              |> File.read!()
              |> String.split("\n")
              |> Enum.reject(fn line ->
                trimmed = String.trim(line)

                trimmed == "" or
                  String.starts_with?(trimmed, "#") or
                  String.starts_with?(trimmed, "@")
              end)
              |> Enum.map(fn line ->
                # Strip inline comments
                line = line |> String.split("#") |> hd() |> String.trim()

                parts =
                  line
                  |> String.split(";")
                  |> Enum.map(&String.trim/1)

                case parts do
                  [supported, desired, dist_sd] ->
                    {supported, desired, String.to_integer(dist_sd), nil}

                  [supported, desired, dist_sd, dist_dx] ->
                    {supported, desired, String.to_integer(dist_sd), String.to_integer(dist_dx)}
                end
              end)

  describe "locale distance against CLDR test data" do
    for {{supported, desired, expected_distance, _reverse_distance}, index} <-
          Enum.with_index(@test_cases) do
      @tag_supported supported
      @tag_desired desired
      @tag_expected_distance expected_distance

      test "#{index}: distance(#{supported}, #{desired}) == #{expected_distance}" do
        result = LanguageTag.match_distance(@tag_supported, @tag_desired)

        if @tag_expected_distance == 100 do
          # 100 means "fail" — distance should be > 50 (the default threshold)
          assert is_integer(result) and result > 50,
                 "Expected high distance (>50) for #{inspect(@tag_supported)} vs #{inspect(@tag_desired)}, got #{inspect(result)}"
        else
          assert result == @tag_expected_distance,
                 "Expected distance #{@tag_expected_distance} for #{inspect(@tag_supported)} vs #{inspect(@tag_desired)}, got #{inspect(result)}"
        end
      end
    end
  end
end
