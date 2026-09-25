defmodule Localize.DateTime.HourCycleMatrixTest do
  @moduledoc """
  Times, datetimes, time skeletons and time intervals under each `-u-hc-`
  hour cycle, and under none, in seven locales.

  TR35 part 1 gives each hour cycle its pattern symbol (h11 `K`, h12 `h`, h23
  `H`, h24 `k`) and has it replace the locale's preferred cycle, which the
  standard formats and a skeleton's `j` follow; an explicit `h` or `H` keeps
  the cycle it names. Expected values come from ICU4C 78.3 in UTC on
  2024-07-06: `DateFormat` for standard formats, `DateTimePatternGenerator`
  for skeletons and `DateIntervalFormat` for intervals
  (`test/support/data/hour_cycle_icu_expected.tsv`). Every case goes through
  `to_string` and `to_parts`, whose parts must join to the string.

  """

  use ExUnit.Case, async: true

  @fixture Path.join([__DIR__, "..", "..", "support", "data", "hour_cycle_icu_expected.tsv"])
  @styles %{"short" => :short, "medium" => :medium}

  @skeletons %{
    "hm" => :hm,
    "Hm" => :Hm,
    "hms" => :hms,
    "Hms" => :Hms,
    "jm" => :jm,
    "jms" => :jms,
    "Kms" => :Kms,
    "kms" => :kms,
    "h" => :h,
    "H" => :H,
    "Bhm" => :Bhm
  }

  test "hour cycles match ICU, or TR35 and CLDR 48 where they differ from it" do
    mismatches =
      for line <- File.stream!(@fixture),
          line = String.trim_trailing(line, "\n"),
          line != "" and not String.starts_with?(line, "#"),
          fields = String.split(line, "\t"),
          mismatch <- [check_case(expected_fields(fields))],
          mismatch != nil,
          do: mismatch

    assert mismatches == [], report(mismatches)
  end

  # TR35 part 1: h12 counts hours 1 to 12. ICU's DateIntervalFormat keeps
  # ja's `K` interval patterns under h12 ("午前0時"), where its DateFormat and
  # pattern generator give "午前12時".
  defp expected_fields(["interval", "ja-u-hc-h12", skeleton | _] = fields)
       when skeleton in ["h", "hm", "jm"] do
    List.update_at(fields, 9, fn icu ->
      icu
      |> String.replace("\\u{5348}\\u{524d}0\\u{6642}", "\\u{5348}\\u{524d}12\\u{6642}")
      |> String.replace("\\u{5348}\\u{5f8c}0\\u{6642}", "\\u{5348}\\u{5f8c}12\\u{6642}")
    end)
  end

  # ko's `Hms` is "H시 m분 s초". Under a 24-hour `-u-hc-`, a standard time
  # format resolves through the locale's 24-hour skeleton, here `Hms`; ICU
  # instead rewrites the medium pattern, "a h:mm:ss", as "HH:mm:ss".
  defp expected_fields(["time", "ko-u-hc-" <> cycle = tag, "medium", hour, minute, second, _icu])
       when cycle in ["h23", "h24"] do
    hour_value = String.to_integer(hour)
    hour_value = if cycle == "h24" and hour_value == 0, do: 24, else: hour_value
    expected = "#{hour_value}시 #{String.to_integer(minute)}분 #{String.to_integer(second)}초"

    ["time", tag, "medium", hour, minute, second, expected]
  end

  defp expected_fields(fields), do: fields

  defp check_case(["time", tag, style, hour, minute, second, expected]) do
    time = time(hour, minute, second)
    options = [format: Map.fetch!(@styles, style), locale: tag]

    compare(
      {:time, tag, style, time},
      decode(expected),
      Localize.Time.to_string(time, options),
      Localize.Time.to_parts(time, options)
    )
  end

  defp check_case(["datetime", tag, style, hour, minute, second, expected]) do
    datetime = NaiveDateTime.new!(~D[2024-07-06], time(hour, minute, second))
    options = [format: Map.fetch!(@styles, style), locale: tag]

    compare(
      {:datetime, tag, style, datetime},
      decode(expected),
      Localize.DateTime.to_string(datetime, options),
      Localize.DateTime.to_parts(datetime, options)
    )
  end

  defp check_case(["skeleton", tag, skeleton, hour, minute, second, expected, _pattern]) do
    time = time(hour, minute, second)
    options = [format: Map.fetch!(@skeletons, skeleton), locale: tag]

    compare(
      {:skeleton, tag, skeleton, time},
      decode(expected),
      Localize.Time.to_string(time, options),
      Localize.Time.to_parts(time, options)
    )
  end

  defp check_case([
         "interval",
         tag,
         skeleton,
         hour,
         minute,
         second,
         to_hour,
         to_minute,
         to_second,
         expected
       ]) do
    from = time(hour, minute, second)
    to = time(to_hour, to_minute, to_second)
    options = [format: Map.fetch!(@skeletons, skeleton), locale: tag]

    compare(
      {:interval, tag, skeleton, from, to},
      decode(expected),
      Localize.Interval.to_string(from, to, options),
      Localize.Interval.to_parts(from, to, options)
    )
  end

  defp compare(key, expected, string, parts) do
    cond do
      string != {:ok, expected} ->
        {key, expected, string}

      not match?({:ok, _parts}, parts) ->
        {key, expected, {:parts, parts}}

      Enum.map_join(elem(parts, 1), & &1.value) != expected ->
        {key, expected, {:parts_do_not_join, parts}}

      true ->
        nil
    end
  end

  defp time(hour, minute, second) do
    Time.new!(String.to_integer(hour), String.to_integer(minute), String.to_integer(second))
  end

  defp decode(text) do
    Regex.replace(~r/\\u\{([0-9a-f]+)\}/, text, fn _match, hex ->
      <<String.to_integer(hex, 16)::utf8>>
    end)
  end

  defp report(mismatches) do
    lines =
      mismatches
      |> Enum.take(30)
      |> Enum.map_join("\n", fn {key, expected, actual} ->
        "  #{inspect(key)}: expected #{inspect(expected)}, got #{inspect(actual, limit: 12)}"
      end)

    "#{length(mismatches)} mismatches\n#{lines}"
  end
end
