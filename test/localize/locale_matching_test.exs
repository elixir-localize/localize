defmodule Localize.LocaleMatchingTest do
  use ExUnit.Case, async: true

  @moduledoc false

  alias Localize.LanguageTag

  @data_file Path.join([__DIR__, "..", "support", "data", "locale_matching_test_data.txt"])

  # The default threshold for the CLDR XLocaleMatcher. In the CLDR distance
  # system, 100 means "no match" (failure). The ICU default script threshold
  # is approximately 80, allowing cross-script matches (like zh-Hant/zh-Hans
  # at distance 54) while rejecting cross-language matches (like de/fr at 84).
  @default_threshold 80

  # Parse the test data file into structured test cases.
  # Format: supported ; desired ; expected [; combined]
  # The supported field may start with a threshold distance number.
  # Lines starting with @debug, @Threshold, @DistanceOption are directives.
  # A "null" expected result means no match is expected.

  @test_cases (fn ->
                 lines =
                   @data_file
                   |> File.read!()
                   |> String.split("\n")

                 {cases, _threshold} =
                   Enum.reduce(lines, {[], @default_threshold}, fn line, {acc, threshold} ->
                     trimmed = String.trim(line)

                     cond do
                       trimmed == "" or String.starts_with?(trimmed, "#") or
                           String.starts_with?(trimmed, "@debug") ->
                         {acc, threshold}

                       String.starts_with?(trimmed, "@Threshold=") ->
                         value =
                           trimmed
                           |> String.replace("@Threshold=", "")
                           |> String.split("#")
                           |> hd()
                           |> String.trim()

                         new_threshold =
                           if value == "-1",
                             do: @default_threshold,
                             else: String.to_integer(value)

                         {acc, new_threshold}

                       String.starts_with?(trimmed, "@DistanceOption=") ->
                         # We don't support SCRIPT_FIRST option yet, skip remaining
                         {acc, threshold}

                       true ->
                         # Strip inline comments
                         data_line = line |> String.split("#") |> hd() |> String.trim()

                         if data_line == "" do
                           {acc, threshold}
                         else
                           parts =
                             data_line
                             |> String.split(";")
                             |> Enum.map(&String.trim/1)

                           case parts do
                             [supported_str, desired_str, expected | _rest] ->
                               # Parse the supported list (may start with a threshold number)
                               supported_parts =
                                 supported_str
                                 |> String.split(",")
                                 |> Enum.map(&String.trim/1)

                               {case_threshold, supported_list} =
                                 case Integer.parse(hd(supported_parts)) do
                                   {num, ""} -> {num, tl(supported_parts)}
                                   _ -> {threshold, supported_parts}
                                 end

                               # Parse desired (may be comma-separated for multiple preferences)
                               desired_list =
                                 desired_str
                                 |> String.split(",")
                                 |> Enum.map(&String.trim/1)

                               case_data = %{
                                 supported: supported_list,
                                 desired: desired_list,
                                 expected: String.trim(expected),
                                 threshold: case_threshold,
                                 line: data_line
                               }

                               {[case_data | acc], threshold}

                             _ ->
                               {acc, threshold}
                           end
                         end
                     end
                   end)

                 Enum.reverse(cases)
               end).()

  # Filter out SCRIPT_FIRST cases (last 4 lines after @DistanceOption=SCRIPT_FIRST)
  # and tests requiring unimplemented features (mul handling, grandfathered tags).
  @filtered_cases Enum.reject(@test_cases, fn test_case ->
                    cond do
                      # Skip SCRIPT_FIRST tests
                      test_case.line =~ ~r/^(ru|hr|da), / -> true
                      # Skip "mul" tests — requires special multilingual matching rules
                      "mul" in test_case.supported -> true
                      # Skip grandfathered tag tests (i-klingon)
                      "i-klingon" in test_case.supported -> true
                      true -> false
                    end
                  end)

  describe "locale matching against CLDR test data" do
    for {test_case, index} <- Enum.with_index(@filtered_cases) do
      @test_case test_case

      @tag_supported_display if(length(test_case.supported) > 5,
                               do: Enum.join(Enum.take(test_case.supported, 5), ", ") <> "...",
                               else: Enum.join(test_case.supported, ", ")
                             )

      test "#{index}: best_match(#{Enum.join(test_case.desired, ", ")} in [#{@tag_supported_display}]) == #{test_case.expected}" do
        supported = @test_case.supported
        desired = @test_case.desired
        expected = @test_case.expected
        threshold = @test_case.threshold

        if expected == "null" do
          # "null" means no match expected — empty supported list
          if supported == [""] do
            assert {:error, _} = LanguageTag.best_match(hd(desired), [], threshold)
          else
            result = LanguageTag.best_match(hd(desired), supported, threshold)

            assert match?({:error, _}, result),
                   "Expected no match for desired=#{inspect(desired)} in supported=#{inspect(supported)}, got #{inspect(result)}"
          end
        else
          # Try each desired locale in order, pick the best overall match.
          # Earlier desired locales are preferred (lower demotion).
          result = find_best_from_desired_list(desired, supported, threshold)

          case result do
            {:ok, matched, _score} ->
              assert matched == expected,
                     "Expected #{inspect(expected)} for desired=#{inspect(desired)} in supported=#{inspect(supported)}, got #{inspect(matched)}"

            {:error, reason} ->
              flunk(
                "best_match failed for desired=#{inspect(desired)} in supported=#{inspect(supported)}: #{inspect(reason)}"
              )
          end
        end
      end
    end
  end

  # Try each desired locale in order. Return the match with the lowest
  # effective distance (actual distance + per-position demotion).
  # This implements the CLDR "getBestMatchForList" behavior.
  # The demotion per desired locale position follows the ICU default
  # which uses approximately the default region distance.
  @demotion_per_locale 6

  defp find_best_from_desired_list(desired_list, supported, threshold) do
    desired_list
    |> Enum.with_index()
    |> Enum.reduce(nil, fn {desired, position}, best ->
      case LanguageTag.best_match(desired, supported, threshold) do
        {:ok, matched, score} ->
          effective = score + position * @demotion_per_locale

          if best == nil or effective < elem(best, 2) do
            {:ok, matched, effective}
          else
            best
          end

        {:error, _} ->
          best
      end
    end)
    |> case do
      nil -> {:error, "No match for any desired locale"}
      result -> result
    end
  end
end
