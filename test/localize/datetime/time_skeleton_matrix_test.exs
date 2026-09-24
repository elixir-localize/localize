defmodule Localize.DateTime.TimeSkeletonMatrixTest do
  @moduledoc """
  Time skeletons for every hour symbol and day period, in fourteen locales
  and hour cycles, at the times where day periods and hour cycles turn.

  Expected values come from ICU4C 78.3's `DateTimePatternGenerator` in
  Etc/UTC on 2024-07-06 (`test/support/data/time_skeleton_icu_expected.tsv`):
  the hour symbols `j`, `J`, `C`, `h`, `H`, `K` and `k`, with and without
  minutes and seconds, with no day period or `a`, `b` or `B`, at 00:00:00,
  00:05:09, 12:00:00, 12:00:30, 12:05:09 and 18:30:00. Every case goes
  through `Localize.DateTime.to_string/2`, `Localize.DateTime.to_parts/2`
  (whose parts must join to the string) and `Localize.Time.to_string/2`.

  Four kinds of row follow TR35 or CLDR 49 where ICU does not, and are
  checked by the tests after the sweep instead:

  * A time that shows as midnight renders `b` and `B` as the locale's
    midnight period, as TR35's day period rules select it; ICU never renders
    midnight. As for noon, a pattern without minutes shows 00:05 as midnight.

  * `J` renders the hour with the digits the locale's pattern shows once its
    day period is dropped: TR35's example has "Jmm" render 18:00 as "6:00",
    where ICU pads the hour from a 24-hour pattern ("06:00").

  * `fr`'s `H` format is "HH 'h'" and `ko`'s `Hms` "H시 m분 s초" in CLDR 48,
    and "HH" and "HH:mm:ss" in CLDR 49.

  * `zh-Hant`'s 12-hour formats name the flexible day period ("Bh:mm"); ICU
    derives each format's skeleton from its pattern, so a skeleton without
    a day period finds "ah:mm" there instead. TR35 treats an `a` beside an
    hour as no day period at all ("`ha` is treated as equivalent to `h`"),
    so `ha` renders "Bh:mm" too where ICU renders "ah:mm".

  """

  use ExUnit.Case, async: true

  @fixture Path.join([__DIR__, "..", "..", "support", "data", "time_skeleton_icu_expected.tsv"])

  @skeletons Map.new(
               ~w(j ja jb jB jm jma jmb jmB jms jmsa jmsb jmsB
                  J Ja Jb JB Jm Jma Jmb JmB Jms Jmsa Jmsb JmsB
                  C Ca Cb CB Cm Cma Cmb CmB Cms Cmsa Cmsb CmsB
                  h ha hb hB hm hma hmb hmB hms hmsa hmsb hmsB
                  H Ha Hb HB Hm Hma Hmb HmB Hms Hmsa Hmsb HmsB
                  K Ka Kb KB Km Kma Kmb KmB Kms Kmsa Kmsb KmsB
                  k ka kb kB km kma kmb kmB kms kmsa kmsb kmsB)a,
               &{Atom.to_string(&1), &1}
             )

  # The fixture locales CLDR 49 gives a midnight day period.
  @midnight_locales ~w(en en-GB fr de ja ko zh-Hant hi en-u-hc-h11 en-u-hc-h24
                       ja-u-hc-h11 ja-u-hc-h24)

  test "time skeletons match ICU, or TR35 and CLDR 49 where they differ from it" do
    rows =
      for line <- File.stream!(@fixture),
          line = String.trim_trailing(line, "\n"),
          line != "" and not String.starts_with?(line, "#"),
          row = row(String.split(line, "\t")),
          not follows_tr35_or_cldr_instead?(row),
          do: row

    failures =
      rows
      |> Task.async_stream(&failure/1, timeout: 60_000, ordered: false)
      |> Enum.flat_map(fn {:ok, failure} -> List.wrap(failure) end)

    assert failures == [],
           "#{length(failures)} rows differ: " <>
             inspect(Enum.take(failures, 30), pretty: true, limit: :infinity)

    assert length(rows) == 5_746
  end

  test "b and B render midnight at a time that shows as midnight" do
    for {locale, skeleton, time, expected} <- [
          {"en", "hb", ~T[00:00:00], "12 midnight"},
          {"en", "hB", ~T[00:00:00], "12 midnight"},
          {"en", "hB", ~T[00:05:09], "12 midnight"},
          {"en", "hmb", ~T[00:00:00], "12:00 midnight"},
          {"en", "hmB", ~T[00:00:00], "12:00 midnight"},
          {"en-u-hc-h11", "hb", ~T[00:00:00], "0 midnight"},
          {"de", "hb", ~T[00:00:00], "12 Mitternacht"},
          {"de", "hB", ~T[00:00:00], "12 Uhr Mitternacht"},
          {"ja", "hb", ~T[00:00:00], "真夜中0時"},
          {"ja", "hB", ~T[00:00:00], "真夜中0時"},
          {"hi", "hB", ~T[00:00:00], "मध्यरात्रि 12"},
          {"hi", "C", ~T[00:00:00], "मध्यरात्रि 12"},
          {"zh-Hant", "hB", ~T[00:00:00], "午夜12時"},
          {"ko", "hB", ~T[00:00:00], "자정 12시"}
        ] do
      assert {locale, skeleton, time, format(skeleton, time, locale)} ==
               {locale, skeleton, time, {:ok, expected}}
    end
  end

  test "J shows the hour without padding it" do
    assert format("Jm", ~T[18:30:00], "en") == {:ok, "6:30"}
    assert format("Jm", ~T[18:30:00], "ar") == {:ok, "6:30"}
    assert format("J", ~T[18:30:00], "es-MX") == {:ok, "6"}
    assert format("J", ~T[00:00:00], "en-u-hc-h11") == {:ok, "0"}
  end

  test "fr's H and ko's Hms follow CLDR 49" do
    assert format("H", ~T[00:05:09], "fr") == {:ok, "00"}
    assert format("Hms", ~T[00:05:09], "ko") == {:ok, "00:05:09"}
  end

  # ICU renders zh-Hant's `hmB` and `hmsB` with the patterns CLDR gives `hm`
  # and `hms`.
  test "zh-Hant's 12-hour formats name the flexible day period" do
    assert format("hm", ~T[00:05:09], "zh-Hant") == {:ok, "凌晨12:05"}
    assert format("hms", ~T[00:05:09], "zh-Hant") == {:ok, "凌晨12:05:09"}
    assert format("hma", ~T[00:05:09], "zh-Hant") == {:ok, "凌晨12:05"}
    assert format("ha", ~T[18:30:00], "zh-Hant") == format("h", ~T[18:30:00], "zh-Hant")
  end

  defp row([_mode, locale, skeleton, hour, minute, second, formatted, pattern]) do
    %{
      locale: locale,
      skeleton: skeleton,
      time:
        Time.new!(String.to_integer(hour), String.to_integer(minute), String.to_integer(second)),
      expected: decode(formatted),
      pattern: pattern |> decode() |> unquoted()
    }
  end

  defp follows_tr35_or_cldr_instead?(row) do
    shows_midnight_day_period?(row) or padded_capital_j?(row) or cldr_48_hour_format?(row) or
      pattern_derived_day_period?(row)
  end

  # Midnight at the precision the pattern shows: a minute or second the
  # pattern does not show is taken as zero.
  defp shows_midnight_day_period?(%{locale: locale, time: time, pattern: pattern}) do
    locale in @midnight_locales and String.contains?(pattern, ["b", "B"]) and time.hour == 0 and
      (time.minute == 0 or not String.contains?(pattern, "m")) and
      (time.second == 0 or not String.contains?(pattern, "s"))
  end

  defp padded_capital_j?(%{skeleton: skeleton, pattern: pattern}) do
    String.starts_with?(skeleton, "J") and String.contains?(pattern, ["hh", "HH", "KK", "kk"])
  end

  defp cldr_48_hour_format?(%{locale: "fr", pattern: pattern}), do: pattern == "HH "
  # ICU writes the CLDR 48 pattern with the hour symbol it resolves, so a
  # `J` or `h` request shows "h시 m분 s초".
  defp cldr_48_hour_format?(%{locale: "ko", pattern: pattern}),
    do: String.ends_with?(pattern, "시 m분 s초")

  defp cldr_48_hour_format?(_row), do: false

  defp pattern_derived_day_period?(%{locale: "zh-Hant", skeleton: skeleton, pattern: pattern}) do
    not String.contains?(skeleton, ["b", "B", "J"]) and String.contains?(pattern, "a")
  end

  defp pattern_derived_day_period?(_row), do: false

  defp failure(row) do
    datetime = DateTime.from_naive!(NaiveDateTime.new!(~D[2024-07-06], row.time), "Etc/UTC")
    skeleton = Map.fetch!(@skeletons, row.skeleton)
    expected = {:ok, row.expected}

    string = Localize.DateTime.to_string(datetime, format: skeleton, locale: row.locale)
    parts = joined(Localize.DateTime.to_parts(datetime, format: skeleton, locale: row.locale))
    time = Localize.Time.to_string(row.time, format: skeleton, locale: row.locale)

    if {string, parts, time} == {expected, expected, expected},
      do: nil,
      else: {row.locale, row.skeleton, row.time, row.expected, string, parts, time}
  end

  defp format(skeleton, time, locale) do
    datetime = DateTime.from_naive!(NaiveDateTime.new!(~D[2024-07-06], time), "Etc/UTC")

    Localize.DateTime.to_string(datetime,
      format: Map.fetch!(@skeletons, skeleton),
      locale: locale
    )
  end

  defp joined({:ok, parts}), do: {:ok, Enum.map_join(parts, & &1.value)}
  defp joined(other), do: other

  # A pattern's quoted text is literal, not fields, so the rules above look
  # only at what lies outside the quotes.
  defp unquoted(pattern) do
    pattern
    |> String.split("'")
    |> Enum.take_every(2)
    |> Enum.join()
  end

  defp decode(string) do
    Regex.replace(~r/\\u\{([0-9a-f]+)\}/, string, fn _match, hex ->
      <<String.to_integer(hex, 16)::utf8>>
    end)
  end
end
