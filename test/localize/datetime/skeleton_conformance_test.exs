defmodule Localize.DateTime.SkeletonConformanceTest do
  @moduledoc """
  CLDR 49's skeleton conformance suite (`common/testData/datetime/skeletons.tsv`).

  Each row gives a locale, a calendar, a requested skeleton and the pattern
  CLDR resolves it to. Rather than compare patterns — which would test a
  pattern-resolution API rather than the formatter — each case formats one
  datetime twice, once by skeleton and once by CLDR's expected pattern, and
  compares the output. Agreement means our skeleton resolution reaches the
  same pattern CLDR does.

  Only the Gregorian rows run. The other calendars would need a date
  converted *into* that calendar for the comparison to mean anything, and
  calendar conversion lives in Calendrical.
  """

  use ExUnit.Case, async: true

  @moduletag :conformance

  @data_file Path.join([__DIR__, "..", "..", "support", "data", "skeleton_test_data.tsv"])

  # A datetime that distinguishes as many fields as possible: a Saturday, a
  # two-digit day and month, a PM hour, and a zone observing daylight time.
  @datetime %DateTime{
    year: 2024,
    month: 7,
    day: 6,
    hour: 14,
    minute: 30,
    second: 45,
    microsecond: {123_000, 3},
    time_zone: "America/New_York",
    zone_abbr: "EDT",
    utc_offset: -18_000,
    std_offset: 3600,
    calendar: Calendar.ISO
  }

  # 84 of the 90 Gregorian cases agree. Every difference is in a separator
  # or a wrapper, never in which fields are chosen or how wide they are, and
  # they fall into two groups.
  #
  # The date-time glue — `zh-Hant-TW`, `ko` and `fr` at `yMdHmsv`, and the
  # comma before the year in `vi` `yMMMMd` / `yMMMMEEEEd`. We join with the
  # locale's `dateTimeFormat`; CLDR's generator uses a plain space. Both
  # glue styles are ingested and `atTime` is now the default, per TR35, but
  # CLDR defines it only for `:full` and `:long` — these cases combine at
  # `:medium`, where `atTime` and `standard` are the same pattern, so the
  # difference is the generator's, not a missing style.
  #
  # The locale's own format — `ko` `yMd` renders "2024. 7. 6." from `ko`'s
  # `availableFormats` where the fixture expects a generated `y/M/d`, and
  # `ja` `yMMMMEEEEd` keeps the parentheses `ja` puts round its weekday.
  # Reading the locale's shipped format is what TR35 asks for, so these are
  # the fixture generator's synthesis differing from the data, not defects.
  #
  # See item 12 in plans/cldr-49.md.
  @expected_matches 84

  defp cases do
    [_header | rows] =
      @data_file
      |> File.stream!()
      |> Stream.map(&String.trim_trailing(&1, "\n"))
      |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.map(&String.split(&1, "\t"))

    Enum.filter(rows, &match?([_locale, "gregorian", _skeleton, _pattern], &1))
  end

  test "skeletons resolve to the same pattern CLDR resolves them to" do
    {matched, mismatched} =
      Enum.reduce(cases(), {0, []}, fn [locale, _calendar, skeleton, pattern],
                                       {matched, misses} ->
        locale = String.replace(locale, "_", "-")

        by_skeleton =
          Localize.DateTime.to_string(@datetime, format: String.to_atom(skeleton), locale: locale)

        by_pattern = Localize.DateTime.to_string(@datetime, format: pattern, locale: locale)

        case {by_skeleton, by_pattern} do
          {{:ok, same}, {:ok, same}} ->
            {matched + 1, misses}

          _differ ->
            {matched, [{locale, skeleton, pattern, by_skeleton, by_pattern} | misses]}
        end
      end)

    total = length(cases())

    assert matched == @expected_matches,
           """
           #{matched}/#{total} Gregorian skeleton cases match, expected #{@expected_matches}.

           #{mismatched |> Enum.reverse() |> Enum.take(10) |> Enum.map_join("\n", fn {l, s, p, bs, bp} -> "  #{l} #{s} (CLDR pattern #{inspect(p)})\n    by skeleton: #{inspect(bs)}\n    by pattern:  #{inspect(bp)}" end)}
           """
  end

  test "every Gregorian case resolves to something" do
    unresolved =
      Enum.filter(cases(), fn [locale, _calendar, skeleton, _pattern] ->
        locale = String.replace(locale, "_", "-")

        match?(
          {:error, _reason},
          Localize.DateTime.to_string(@datetime, format: String.to_atom(skeleton), locale: locale)
        )
      end)

    assert unresolved == []
  end
end
