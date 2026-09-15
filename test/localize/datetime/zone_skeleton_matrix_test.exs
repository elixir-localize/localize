defmodule Localize.DateTime.ZoneSkeletonMatrixTest do
  @moduledoc """
  Time skeletons with a time zone field of every width, at 13:05:09 in
  Etc/UTC on 2024-07-06.

  Expected values come from ICU4C 78.3's `DateTimePatternGenerator`
  (`test/support/data/zone_skeleton_icu_expected.tsv`), for `jm`, `Hm` and
  `hm` with each of `z`, `zzzz`, `v`, `vvvv`, `O`, `OOOO`, `X` to `XXXXX`,
  `x` to `xxxxx`, `V` to `VVVV`, `Z`, `ZZZZ` and `ZZZZZ`. A zone field that
  differs from the matched format's stands in for it, so `jmX` renders
  `h:mm a X`.

  Two differences from ICU follow CLDR data and TR35 instead. For `v` and
  `vvvv`, TR35's type fallback (§Using Time Zone Names) takes a zone's
  standard name when it has no generic one and its offset never changes,
  and CLDR gives Etc/UTC standard names ("UTC", "Coordinated Universal
  Time"), where ICU renders the localized GMT format. And CLDR's `fr` names
  Etc/UTC "TU" in the short specific form, where ICU renders "UTC".

  """

  use ExUnit.Case, async: true

  @fixture Path.join([__DIR__, "..", "..", "support", "data", "zone_skeleton_icu_expected.tsv"])
  @datetime ~U[2024-07-06 13:05:09Z]

  @skeletons Map.new(
               ~w(jmz jmzzzz jmv jmvvvv jmO jmOOOO jmX jmXX jmXXX jmXXXX jmXXXXX jmx jmxx
                  jmxxx jmxxxx jmxxxxx jmV jmVV jmVVV jmVVVV jmZ jmZZZZ jmZZZZZ
                  Hmz Hmzzzz Hmv Hmvvvv HmO HmOOOO HmX HmXX HmXXX HmXXXX HmXXXXX Hmx Hmxx
                  Hmxxx Hmxxxx Hmxxxxx HmV HmVV HmVVV HmVVVV HmZ HmZZZZ HmZZZZZ
                  hmz hmzzzz hmv hmvvvv hmO hmOOOO hmX hmXX hmXXX hmXXXX hmXXXXX hmx hmxx
                  hmxxx hmxxxx hmxxxxx hmV hmVV hmVVV hmVVVV hmZ hmZZZZ hmZZZZZ)a,
               &{Atom.to_string(&1), &1}
             )

  test "zone fields match ICU, or CLDR 49 and TR35 where they differ from it" do
    rows =
      for line <- File.stream!(@fixture),
          line = String.trim_trailing(line, "\n"),
          line != "" and not String.starts_with?(line, "#"),
          [_mode, locale, skeleton, _hour, _minute, _second, formatted, _pattern] =
            String.split(line, "\t"),
          not follows_cldr_instead?(locale, skeleton),
          do: {locale, skeleton, decode(formatted)}

    failures =
      for {locale, skeleton, expected} <- rows,
          result = format(skeleton, locale),
          result != {:ok, expected},
          do: {locale, skeleton, expected, result}

    assert length(rows) == 438
    assert failures == [], inspect(failures, pretty: true, limit: :infinity)
  end

  test "v and vvvv take Etc/UTC's standard names" do
    for {locale, short, long} <- [
          {"en", "UTC", "Coordinated Universal Time"},
          {"de", "UTC", "Koordinierte Weltzeit"},
          {"ja", "UTC", "協定世界時"},
          {"ko", "UTC", "협정 세계시"},
          {"fr", "TU", "temps universel coordonné"}
        ] do
      assert {:ok, short_result} = format("Hmv", locale)
      assert String.ends_with?(short_result, " " <> short), inspect({locale, short_result})

      assert {:ok, long_result} = format("Hmvvvv", locale)
      assert String.ends_with?(long_result, " " <> long), inspect({locale, long_result})
    end
  end

  test "fr names Etc/UTC TU in the short specific form" do
    assert format("Hmz", "fr") == {:ok, "13:05 TU"}
  end

  defp follows_cldr_instead?(_locale, skeleton) when skeleton in ["jmv", "Hmv", "hmv"], do: true

  defp follows_cldr_instead?(_locale, skeleton) when skeleton in ["jmvvvv", "Hmvvvv", "hmvvvv"],
    do: true

  defp follows_cldr_instead?("fr", skeleton) when skeleton in ["jmz", "Hmz", "hmz"], do: true
  defp follows_cldr_instead?(_locale, _skeleton), do: false

  defp format(skeleton, locale) do
    Localize.DateTime.to_string(@datetime,
      format: Map.fetch!(@skeletons, skeleton),
      locale: locale
    )
  end

  defp decode(string) do
    Regex.replace(~r/\\u\{([0-9a-f]+)\}/, string, fn _match, hex ->
      <<String.to_integer(hex, 16)::utf8>>
    end)
  end
end
