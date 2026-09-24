defmodule Localize.DateTime.SkeletonConformanceTest do
  @moduledoc """
  CLDR 49's skeleton conformance suites, from `common/testData/datetime/`:
  `skeletons.tsv`, `skeletons_all_locales.tsv`, `skeletons_all_skeletons.tsv`
  and `skeletons_random_5percent.tsv`.

  Each row gives a locale, a calendar, a requested skeleton and the pattern
  CLDR's reference pattern generator resolves it to. Rather than compare
  patterns — which would test a pattern-resolution API rather than the
  formatter — each case formats one datetime twice, once by skeleton and
  once by CLDR's expected pattern, and compares the output. Agreement means
  skeleton resolution reaches the same pattern CLDR does.

  Only the Gregorian rows run. The other calendars would need a date
  converted *into* that calendar for the comparison to mean anything, and
  calendar conversion lives in Calendrical. The generator joins a date and a
  time with the standard wrapper, so the cases format with `style: :default`.

  Where this library and the generator part company on purpose, the case is
  recorded in `@deviations` with its reason, and a recorded case that starts
  to agree fails the suite so the record does not go stale.
  """

  use ExUnit.Case, async: true

  @moduletag :conformance

  @data_dir Path.join([__DIR__, "..", "..", "support", "data"])

  @files [
    "skeleton_test_data.tsv",
    "skeleton_all_locales_test_data.tsv",
    "skeleton_all_skeletons_test_data.tsv",
    "skeleton_random_5percent_test_data.tsv"
  ]

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

  # Every skeleton the files use, written here so the atoms come from source
  # code rather than being minted from the files. A skeleton missing from
  # this list fails the suite; add it here.
  @known_skeletons ~w(B BBBB BBBBB BBBBBhm BBBBhm Bh Bhh Bhm C CC CCC CCCC CCCCC CCCCCC
                      CCCCCCm CCCCCm CCCCm CCCm CCm Cm Cms E EEEE EEEEE EEEEEE EEEEv Ez G GG
                      GGG GGGG GGGGG GGGGGyMd GGGGyMd GGGyMd GGyMd GyMd H HH HHm Hm Hms HmsS
                      J JJ JJJ JJJJ JJJJJ JJJJJJ JJJJJJm JJJJJm JJJJm JJJm JJm Jm M MM MMM
                      MMMM MMMMM Q QQ QQQ QQQQ QQQQQ U UUUU d dd h hh hhm hm hmm hms hmss
                      hmsz hmszz hmszzz hmszzzz hmszzzzz j jj jjj jjjj jjjjj jjjjjj jjjjjjm
                      jjjjjm jjjjm jjjm jjm jm m mm s ss v vvvv y yM yMEdz yMM yMMM yMMMM
                      yMMMMEEEEd yMMMMEEEEdvvvv yMMMMM yMMMMd yMMMMdhmsvvvv yMMMMdv yMMMdv
                      yMd yMdE yMdEEEE yMdEEEEE yMdEEEEEE yMdHmsv yMdd yMv yQ yQQQ yQQQQ yy
                      yyMd yyyy yyyyMd z zz zzz zzzz zzzzz)a

  @skeletons_by_name Map.new(@known_skeletons, &{Atom.to_string(&1), &1})

  # Where this library and CLDR's reference generator part company, each for
  # a reason TR35 gives. The lists are skeleton to locales, and every case
  # the files hold for a pair is recorded.

  # TR35 rule 3: "Pattern field lengths for hour, minute, and second should
  # by default not be adjusted to match the requested field length". The
  # generator widens the locale's `h` for `hh`, so its "02" is our "2".
  @hour_width %{
    "hh" => ~w(ar en-US eu fr ja ko kok-Deva nn ru sw vi zh-Hant zh-Hant-TW),
    "hhm" => ~w(ar be cv dsb el en-US eu fr ja ko ml ps ru sr sv vi zh-Hant-TW),
    "Bhh" => ~w(ar as ca en-US eu fr is ja ka ko lv nl ru si tr vi yo zh-Hant-TW)
  }

  # TR35 gives `J` as the hour in "minimum digits" and renders "Jmm" for
  # 18:00 as "6:00". The generator takes the locale's 24-hour `H` format and
  # swaps its hour symbol, so en's "HH" becomes a padded "hh".
  @capital_j %{
    "J" => ~w(ar as en-US),
    "JJ" => ~w(ar en-US kok-Deva),
    "JJJ" => ~w(ar en-US ms),
    "JJJJ" => ~w(ar bn en-US),
    "JJJJJ" => ~w(ar as en-US root),
    "JJJJJJ" => ~w(ar bn en-US sd-Arab),
    "Jm" => ~w(ar en-US ko pa-Guru zh-Hant-TW),
    "JJm" => ~w(ar el en-US ko ml zh-Hant-TW),
    "JJJm" => ~w(ar en-US kn ko zh-Hant-TW),
    "JJJJm" => ~w(ar en-US ko ml or zh-Hant-TW),
    "JJJJJm" => ~w(ar en-US ko zh-Hant-TW),
    "JJJJJJm" => ~w(ar en-US ko ml or zh-Hant-TW)
  }

  # TR35 §Time Data: `regions` may name a locale (`gu_IN`) as well as a
  # region, and its example gives `gu_IN` and `ta_IN` the flexible day
  # period first. The generator looks up the locale identifier and then the
  # region alone, so its `C` finds India's "h H" and a plain `a`.
  @locale_time_data %{
    "C" => ~w(pa ta),
    "CCC" => ~w(ta te),
    "CCCCC" => ~w(mr),
    "Cms" => ~w(gu hi hi-Latn kn ml mr pa pa-Guru ta te)
  }

  # en's `yy` is "’yy", a two-digit year with an elision mark. The generator
  # matches `yyyy` to it as the nearer numeric width and widens it to
  # "’2024"; this library matches `y`.
  @two_digit_year %{"yyyy" => ~w(en-US)}

  @deviations for group <- [@hour_width, @capital_j, @locale_time_data, @two_digit_year],
                  {skeleton, locales} <- group,
                  locale <- locales,
                  into: %{},
                  do: {{locale, skeleton}, true}

  defp cases(file) do
    [_header | rows] =
      [@data_dir, file]
      |> Path.join()
      |> File.stream!()
      |> Stream.map(&String.trim_trailing(&1, "\n"))
      |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.map(&String.split(&1, "\t"))

    for [locale, "gregorian", skeleton, pattern] <- rows do
      {String.replace(locale, "_", "-"), skeleton, pattern}
    end
  end

  defp format_case({locale, skeleton, pattern}) do
    options = [locale: locale, style: :default]

    by_skeleton =
      Localize.DateTime.to_string(@datetime, [format: skeleton_atom(skeleton)] ++ options)

    by_pattern = Localize.DateTime.to_string(@datetime, [format: pattern] ++ options)
    {by_skeleton, by_pattern}
  end

  defp skeleton_atom(skeleton) do
    Map.get(@skeletons_by_name, skeleton) ||
      flunk("CLDR's data uses skeleton #{inspect(skeleton)}, which is not in @known_skeletons")
  end

  defp agrees?({{:ok, same}, {:ok, same}}), do: true
  defp agrees?(_formatted), do: false

  for file <- @files do
    test "#{file}: every Gregorian case agrees with CLDR but the recorded deviations" do
      disagreeing =
        unquote(file)
        |> cases()
        |> Enum.reject(fn {locale, skeleton, _pattern} ->
          Map.has_key?(@deviations, {locale, skeleton})
        end)
        |> Enum.map(&{&1, format_case(&1)})
        |> Enum.reject(fn {_cldr_case, formatted} -> agrees?(formatted) end)

      assert disagreeing == [], describe(disagreeing)
    end

    test "#{file}: every recorded deviation still deviates" do
      agreeing =
        for {locale, skeleton, _pattern} = cldr_case <- cases(unquote(file)),
            Map.has_key?(@deviations, {locale, skeleton}),
            agrees?(format_case(cldr_case)),
            do: {locale, skeleton}

      assert agreeing == [],
             "these now agree with CLDR; remove them from @deviations: #{inspect(agreeing)}"
    end
  end

  test "every Gregorian case resolves to something" do
    unresolved =
      for file <- @files,
          {locale, skeleton, _pattern} <- cases(file),
          match?(
            {:error, _reason},
            Localize.DateTime.to_string(@datetime,
              format: skeleton_atom(skeleton),
              locale: locale
            )
          ),
          uniq: true,
          do: {locale, skeleton}

    assert unresolved == []
  end

  defp describe(disagreeing) do
    shown =
      disagreeing
      |> Enum.take(15)
      |> Enum.map_join("\n", fn {{locale, skeleton, pattern}, {by_skeleton, by_pattern}} ->
        "  #{locale} #{skeleton} (CLDR pattern #{inspect(pattern)})\n" <>
          "    by skeleton: #{inspect(by_skeleton)}\n    by pattern:  #{inspect(by_pattern)}"
      end)

    "#{length(disagreeing)} cases disagree with CLDR:\n#{shown}"
  end
end
