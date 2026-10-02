defmodule Localize.DurationZonedMatrixTest do
  @moduledoc """
  `Localize.Duration.new/2` between two date-times in time zones, about 36
  changes of clocks in twelve time zones: hours the clocks skip and repeat,
  by an hour and by half of one, at midnight, and the day Samoa left out.

  Expected values are those of the ECMA-262 Temporal specification's
  `DifferenceZonedDateTime`, taken step by step
  (`test/support/data/zoned_duration_temporal_expected.tsv`): the later
  moment is moved to the earlier's time zone, whole days are counted on that
  wall clock, and the seconds are the time that passes after them. A
  duration's years, months and days are compared as the days they span from
  the earlier's date, which `Date.shift/2` counts.

  In one case the expected seconds are the time that passes and not the
  specification's, which the rows concerned carry too: where the earlier
  moment is the second occurrence of a time the clocks repeat and no whole
  day is counted, the specification's steps resolve the earlier's wall-clock
  time again, at its first occurrence, and count the repeated time twice.

  """

  use ExUnit.Case, async: true

  @fixture Path.join([__DIR__, "..", "support", "data", "zoned_duration_temporal_expected.tsv"])

  test "is the specification's duration about every change of clocks" do
    rows = rows()

    mismatches =
      for {from, to, days, seconds, _specification} <- rows,
          measured = measure(from, to),
          measured != {days, seconds},
          do: {from, to, {days, seconds}, measured}

    assert mismatches == [], report(mismatches)
    assert length(rows) == 3025
  end

  # The one case kept apart from the specification: no whole day is counted,
  # the seconds are the time that passes (`DateTime.diff/3`), and the
  # specification's are more, by the time the clocks repeat.
  test "is the time that passes from the second occurrence of a repeated time" do
    apart =
      for {_from, _to, _days, _seconds, specification} = row <- rows(), specification, do: row

    assert length(apart) == 301

    for {from, to, days, seconds, specification} <- apart do
      assert {:ambiguous, _first, ^from} =
               DateTime.new(DateTime.to_date(from), DateTime.to_time(from), from.time_zone),
             inspect(from)

      assert days == 0
      assert seconds == DateTime.diff(to, from)
      assert specification > seconds
    end
  end

  defp rows do
    for line <- File.stream!(@fixture),
        line = String.trim_trailing(line, "\n"),
        line != "" and not String.starts_with?(line, "#") do
      [from_zone, from_unix, to_zone, to_unix, days, seconds | specification] =
        String.split(line, "\t")

      {moment(from_unix, from_zone), moment(to_unix, to_zone), String.to_integer(days),
       String.to_integer(seconds), specification |> List.first() |> integer_or_nil()}
    end
  end

  defp moment(unix, time_zone) do
    unix |> String.to_integer() |> DateTime.from_unix!() |> DateTime.shift_zone!(time_zone)
  end

  defp integer_or_nil(nil), do: nil
  defp integer_or_nil(text), do: String.to_integer(text)

  # A duration as the days its years, months and days span from the
  # earlier's date, and the seconds of its hours, minutes and seconds.
  defp measure(from, to) do
    case Localize.Duration.new(from, to) do
      {:ok, duration} ->
        date = DateTime.to_date(from)
        reached = Date.shift(date, year: duration.year, month: duration.month, day: duration.day)

        {Date.diff(reached, date), duration.hour * 3600 + duration.minute * 60 + duration.second}

      error ->
        error
    end
  end

  defp report(mismatches) do
    mismatches
    |> Enum.take(10)
    |> Enum.map_join("\n", fn {from, to, expected, measured} ->
      "#{DateTime.to_iso8601(from)} [#{from.time_zone}] to #{DateTime.to_iso8601(to)} " <>
        "[#{to.time_zone}]: expected #{inspect(expected)}, got #{inspect(measured)}"
    end)
  end
end
