defmodule Localize.DateTime.SkeletonMatchingTest do
  @moduledoc """
  TR35 §Matching Skeletons and §Missing Skeleton Fields, case by case.

  Each expected value comes from CLDR rather than from this library: a row
  of CLDR's skeleton conformance data (`common/testData/datetime/`), the
  pattern CLDR's reference generator resolves the skeleton to, or the
  locale's own CLDR data where the conformance files have no row. The
  conformance suite in `Localize.DateTime.SkeletonConformanceTest` runs
  every Gregorian row; these pin the individual rules.
  """

  use ExUnit.Case, async: true

  alias Localize.DateTime.Format.AppendItems
  alias Localize.DateTime.Format.Match

  @date ~D[2024-07-06]

  # A Saturday afternoon in a zone observing daylight time.
  @datetime %DateTime{
    year: 2024,
    month: 7,
    day: 6,
    hour: 14,
    minute: 30,
    second: 45,
    microsecond: {0, 0},
    time_zone: "America/New_York",
    zone_abbr: "EDT",
    utc_offset: -18_000,
    std_offset: 3600,
    calendar: Calendar.ISO
  }

  describe "weekday symbols are one field" do
    # CLDR rows `en_US E* → c*`: en answers `E` with "ccc", and a wider
    # request widens that `c`.
    test "a weekday request widens the locale's stand-alone weekday" do
      assert {:ok, "Saturday"} = Localize.Date.to_string(@date, format: :EEEE, locale: :en)
      assert {:ok, "S"} = Localize.Date.to_string(@date, format: :EEEEE, locale: :en)
      assert {:ok, "Sa"} = Localize.Date.to_string(@date, format: :EEEEEE, locale: :en)
    end

    # TR35: E ≅ c, and `e` is the same weekday field.
    test "e and c requests find the E formats" do
      assert {:ok, "Saturday"} = Localize.Date.to_string(@date, format: :eeee, locale: :en)
      assert {:ok, "Saturday"} = Localize.Date.to_string(@date, format: :cccc, locale: :en)
      assert {:ok, "Sat"} = Localize.Date.to_string(@date, format: :eee, locale: :en)
    end

    # TR35 rule 1: a width never crosses between numeric and text, so a
    # numeric `e` matched to en's text "ccc" stays text.
    test "a numeric weekday request does not turn a text weekday numeric" do
      assert {:ok, "Sat"} = Localize.Date.to_string(@date, format: :e, locale: :en)
    end

    # CLDR row `ru yMdEEEE → cccc, dd.MM.y`.
    test "a weekday inside a date widens with it" do
      assert {:ok, "суббота, 06.07.2024"} =
               Localize.Date.to_string(@date, format: :yMdEEEE, locale: :ru)
    end
  end

  describe "year symbols are one field" do
    # CLDR row `ja U → y年`: a Gregorian date has no cyclic year name, so
    # `U` finds the locale's year format and formats its numeric year.
    test "a cyclic year request finds the year format" do
      assert {:ok, "2024年"} = Localize.Date.to_string(@date, format: :U, locale: :ja)
    end

    # `Y` counts the week-based year, so it replaces the matched pattern's
    # `y`. en weeks start on Sunday and need one day in the new year, so
    # Monday 30 December 2024 is in the first week of 2025.
    test "a week-based year request keeps its own symbol" do
      assert {:ok, "12/30/2025"} =
               Localize.Date.to_string(~D[2024-12-30], format: :YMd, locale: :en)

      assert {:ok, "12/30/2024"} =
               Localize.Date.to_string(~D[2024-12-30], format: :yMd, locale: :en)
    end
  end

  describe "text widths" do
    # CLDR row `ja yMdEEEEE → y/M/d(EEEEE)`: narrow sits nearer abbreviated
    # than wide, so the match is `yMEd`'s "y/M/d(E)", not `yMEEEEd`'s.
    test "a narrow request prefers the abbreviated format to the wide one" do
      assert {:ok, "2024/7/6(土)"} =
               Localize.Date.to_string(@date, format: :yMdEEEEE, locale: :ja)
    end

    # CLDR row `eu yMMMMM → y MMMMM`, from `yMMM` rather than `yMMMM`.
    test "a narrow month builds on the abbreviated month" do
      assert {:ok, "2024 U"} = Localize.Date.to_string(@date, format: :yMMMMM, locale: :eu)
    end
  end

  describe "a width the matched format already asks for stands" do
    # CLDR row `fr yyMd → dd/MM/yy`: the `yMd` id asks for `M` and `d`, so
    # its "dd/MM/y" keeps both padded. TR35 rule 2.
    test "on the date path and the date-time path alike" do
      assert {:ok, "06/07/24"} = Localize.Date.to_string(@date, format: :yyMd, locale: :fr)

      assert {:ok, "06/07/24"} =
               Localize.DateTime.to_string(@datetime, format: :yyMd, locale: :fr)
    end
  end

  describe "formats missing a field rank by their fields" do
    # TR35 step 2: en's `MMM` and `E` each lack one field of `EEEEMMMM`;
    # month ranks above weekday, so the month format is the base, widened to
    # "LLLL", and en's Day-Of-Week item, "{1}, {0}", appends the weekday.
    test "the month format is the base, not the weekday format" do
      assert {:ok, :MMM, [{"E", 4}]} = Match.subset_match(:EEEEMMMM, :en)

      assert {:ok, "Saturday, July"} =
               Localize.Date.to_string(@date, format: :EEEEMMMM, locale: :en)
    end
  end

  describe "the day period of an input hour symbol" do
    # CLDR rows `en_US jjjjj → h aaaaa`, `jjjjjm → h:mm aaaaa` and
    # `CCCCC → h aaaaa`: five or six letters ask for the narrow day period.
    test "five letters of j or C ask for the narrow day period" do
      assert {:ok, "2\u202Fp"} =
               Localize.DateTime.to_string(@datetime, format: :jjjjj, locale: :en)

      assert {:ok, "2:30\u202Fp"} =
               Localize.DateTime.to_string(@datetime, format: :jjjjjm, locale: :en)

      assert {:ok, "2\u202Fp"} =
               Localize.DateTime.to_string(@datetime, format: :CCCCC, locale: :en)
    end

    # CLDR row `zh_Hant_TW jjj → BBBBh時`: the width applies to the day
    # period the locale's pattern uses, here `B`.
    test "the width applies to the locale's own day period symbol" do
      assert {:ok, "BBBBh時"} = AppendItems.resolve_pattern(:jjj, :"zh-Hant", :gregorian)
      assert {:ok, "BBBBBh時"} = AppendItems.resolve_pattern(:CCCCC, :"zh-Hant", :gregorian)
    end
  end

  describe "fields no format carries" do
    # CLDR rows `en_US G → G`, `GGGG → GGGG`, `QQQQ → QQQQ`, `m → m`,
    # `ss → ss` and `B → B`: with nothing to build on, the pattern is the
    # field itself.
    test "a lone field is its own pattern" do
      assert {:ok, "AD"} = Localize.Date.to_string(@date, format: :G, locale: :en)
      assert {:ok, "Anno Domini"} = Localize.Date.to_string(@date, format: :GGGG, locale: :en)
      assert {:ok, "3rd quarter"} = Localize.Date.to_string(@date, format: :QQQQ, locale: :en)
      assert {:ok, "30"} = Localize.DateTime.to_string(@datetime, format: :m, locale: :en)
      assert {:ok, "45"} = Localize.DateTime.to_string(@datetime, format: :ss, locale: :en)

      assert {:ok, "in the afternoon"} =
               Localize.DateTime.to_string(@datetime, format: :B, locale: :en)
    end

    # The rest append to the first field in CLDR's canonical order, era
    # before quarter, through en's Quarter item "{0} ({2}: {1})".
    test "further fields append to the first" do
      assert {:ok, "G ('quarter': Q)"} = AppendItems.augment(:QG, :en, :gregorian)
    end
  end

  describe "skeletons match availableFormats, not the standard formats" do
    # CLDR row `ko yMd → y/M/d`. ko's medium date, whose skeleton is also
    # `yMd`, is "y. M. d.", and it is still what `:medium` formats with.
    test "a skeleton request takes the availableFormats entry" do
      assert {:ok, "2024/7/6"} = Localize.Date.to_string(@date, format: :yMd, locale: :ko)
      assert {:ok, "2024. 7. 6."} = Localize.Date.to_string(@date, format: :medium, locale: :ko)
    end

    # eu's medium date "y('e')'ko' MMM d('a')" and its `yMMMd` entry
    # "y MMM d('a')" share a skeleton.
    test "the standard format keeps its own pattern" do
      assert {:ok, "2024 uzt. 6(a)"} = Localize.Date.to_string(@date, format: :yMMMd, locale: :eu)

      assert {:ok, "2024(e)ko uzt. 6(a)"} =
               Localize.Date.to_string(@date, format: :medium, locale: :eu)
    end

    # CLDR row `da yMMMMEEEEd → EEEE d. MMMM y`: da has no `availableFormats`
    # entry for the skeleton, so it widens `yMMMMEd`'s "E d. MMMM y" rather
    # than taking the full date "EEEE 'den' d. MMMM y", whose skeleton it is.
    test "a skeleton only a standard format carries is matched, not looked up" do
      assert {:ok, "lørdag 6. juli 2024"} =
               Localize.Date.to_string(@date, format: :yMMMMEEEEd, locale: :da)

      assert {:ok, "lørdag den 6. juli 2024"} =
               Localize.Date.to_string(@date, format: :full, locale: :da)
    end

    # The parser tries every pattern the locale formats with, the standard
    # formats' included.
    test "both patterns parse" do
      assert {:ok, ~D[2024-07-06]} = Localize.Date.parse("2024. 7. 6.", locale: :ko)
      assert {:ok, ~D[2024-07-06]} = Localize.Date.parse("2024/7/6", locale: :ko)
    end
  end

  describe "glue patterns" do
    # CLDR row `en_US yMMMdv → MMM d, y v`: a time half that is only a zone
    # joins through Date-Timezone, en's "{0} {1}".
    test "a date and a zone join through Date-Timezone" do
      assert {:ok, "Jul 6, 2024 ET"} =
               Localize.DateTime.to_string(@datetime, format: :yMMMdv, locale: :en)

      assert {:ok, "Jul 6, 2024 EDT"} =
               Localize.DateTime.to_string(@datetime, format: :yMMMdz, locale: :en)
    end

    # CLDR rows `en_US Ez → ccc z` and `EEEEv → cccc v` (CLDR-19066): a
    # weekday and a zone are a date half with only a weekday and a time half
    # with only a zone, and Date-Timezone is checked first.
    test "Date-Timezone comes before Time-Day-Of-Week" do
      assert {:ok, "Sat EDT"} = Localize.DateTime.to_string(@datetime, format: :Ez, locale: :en)

      assert {:ok, "Saturday ET"} =
               Localize.DateTime.to_string(@datetime, format: :EEEEv, locale: :en)
    end

    # A date half that is only a weekday joins a time through
    # Time-Day-Of-Week, en's "{1}, {0}", with the weekday as `{1}`.
    test "a weekday and a time join through Time-Day-Of-Week" do
      assert {:ok, "Saturday, 2:30\u202FPM ET"} =
               Localize.DateTime.to_string(@datetime, format: :EEEEhmv, locale: :en)
    end

    # zh-Hant-TW's Date-Timezone is "{1} {0}": CLDR row `zh_Hant_TW Ez →
    # z ccc`.
    test "the locale's template sets the order" do
      assert {:ok, by_pattern} =
               Localize.DateTime.to_string(@datetime, format: "z ccc", locale: :"zh-Hant-TW")

      assert {:ok, ^by_pattern} =
               Localize.DateTime.to_string(@datetime, format: :Ez, locale: :"zh-Hant-TW")
    end
  end
end
