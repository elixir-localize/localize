defmodule Localize.IntervalSkeletonTest do
  @moduledoc """
  `Localize.Interval.to_string/3` selects an interval format by its skeleton,
  as CLDR keys interval formats: a date interval takes a skeleton or a
  pattern, and a datetime interval splits a skeleton into its date and time
  fields, as TR35's interval algorithm does (step 3.2).

  The expected values are ICU4C 78.3's `DateIntervalFormat` for the same
  skeletons, except where a test says otherwise.

  """

  use ExUnit.Case, async: true

  @thin " "
  @narrow " "

  defp interval(from, to, options), do: Localize.Interval.to_string(from, to, options)

  describe "a date interval" do
    test "takes a skeleton" do
      for {skeleton, {from, to}, expected} <- [
            {:yMMMd, {~D[2026-06-15], ~D[2026-06-18]}, "Jun 15#{@thin}–#{@thin}18, 2026"},
            {:yMMMEd, {~D[2026-06-15], ~D[2026-06-18]},
             "Mon, Jun 15#{@thin}–#{@thin}Thu, Jun 18, 2026"},
            {:yMMMd, {~D[2026-06-15], ~D[2026-06-15]}, "Jun 15, 2026"},
            {:MMMd, {~D[2026-06-15], ~D[2026-08-18]}, "Jun 15#{@thin}–#{@thin}Aug 18"},
            {:yMd, {~D[2026-06-15], ~D[2026-08-18]}, "6/15/2026#{@thin}–#{@thin}8/18/2026"},
            {:MMMd, {~D[2026-12-30], ~D[2027-01-02]}, "Dec 30, 2026#{@thin}–#{@thin}Jan 2, 2027"}
          ] do
        assert interval(from, to, format: skeleton, locale: :en) == {:ok, expected}
        assert interval(from, to, date_format: skeleton, locale: :en) == {:ok, expected}
      end
    end

    test "takes a skeleton in other locales" do
      assert interval(~D[2026-06-15], ~D[2026-06-18], format: :yMMMEd, locale: :ja) ==
               {:ok, "2026年6月15日(月)～18日(木)"}

      assert interval(~D[2026-06-15], ~D[2026-06-18], format: :yMMMEd, locale: :fr) ==
               {:ok, "lun. 15#{@thin}–#{@thin}jeu. 18 juin 2026"}

      assert interval(~D[2026-06-15], ~D[2026-06-18], format: :yMd, locale: :de) ==
               {:ok, "15.–18.06.2026"}
    end

    # ICU takes no pattern, so these follow TR35's last step: both dates in
    # the pattern around `en`'s fallback "{0} – {1}", or one date when they
    # differ in no field the pattern shows.
    test "takes a pattern" do
      assert interval(~D[2026-06-15], ~D[2026-06-18], format: "d MMM y", locale: :en) ==
               {:ok, "15 Jun 2026#{@thin}–#{@thin}18 Jun 2026"}

      assert interval(~D[2026-06-15], ~D[2026-06-18], date_format: "d MMM y", locale: :en) ==
               {:ok, "15 Jun 2026#{@thin}–#{@thin}18 Jun 2026"}

      assert interval(~D[2026-06-15], ~D[2026-06-18], format: "MMM y", locale: :en) ==
               {:ok, "Jun 2026"}

      assert interval(~D[2026-06-15], ~D[2026-06-15], format: "d MMM y", locale: :en) ==
               {:ok, "15 Jun 2026"}
    end

    test "with a skeleton no format resolves is an error" do
      assert {:error, %Localize.DateTimeUnresolvedFormatError{}} =
               interval(~D[2026-06-15], ~D[2026-06-18], format: :bogus, locale: :en)
    end

    # TR35's step 4 writes one date where "there is no difference among any
    # of the fields in the pattern", so the fields a format writes decide, a
    # week among them, and not the month and the day that hold it. `en`
    # writes `yw` "'week' w 'of' Y" and `MMMMW` "'week' W 'of' MMMM", and
    # numbers its weeks from Sunday with a minimum of one day: 15 June 2026,
    # a Monday, is in week 25 of the year and week 3 of June, 22 June in
    # weeks 26 and 4, 20 July in week 30 and 21 June 2027 in week 26. ICU4C
    # 78.3 makes no pattern for either skeleton.
    test "of weeks writes both weeks, and one where the days are in the same week" do
      for {format, {from, to}, expected} <- [
            {:yw, {~D[2026-06-15], ~D[2026-07-20]},
             "week 25 of 2026#{@thin}–#{@thin}week 30 of 2026"},
            {:yw, {~D[2026-06-15], ~D[2026-06-22]},
             "week 25 of 2026#{@thin}–#{@thin}week 26 of 2026"},
            {:yw, {~D[2026-06-15], ~D[2026-06-17]}, "week 25 of 2026"},
            {:yw, {~D[2026-06-15], ~D[2027-06-21]},
             "week 25 of 2026#{@thin}–#{@thin}week 26 of 2027"},
            {"Y-'W'ww", {~D[2026-06-15], ~D[2026-07-20]}, "2026-W25#{@thin}–#{@thin}2026-W30"},
            {"Y-'W'ww", {~D[2026-06-15], ~D[2026-06-17]}, "2026-W25"},
            {:MMMMW, {~D[2026-06-15], ~D[2026-06-22]},
             "week 3 of June#{@thin}–#{@thin}week 4 of June"},
            {:MMMMW, {~D[2026-06-15], ~D[2026-06-17]}, "week 3 of June"}
          ] do
        assert interval(from, to, format: format, locale: :en) == {:ok, expected},
               inspect({format, from, to})
      end

      assert {:ok, parts} =
               Localize.Interval.to_parts(~D[2026-06-15], ~D[2026-07-20],
                 format: :yw,
                 locale: :en
               )

      assert Enum.map_join(parts, & &1.value) ==
               "week 25 of 2026#{@thin}–#{@thin}week 30 of 2026"
    end

    # A quarter is compared as a quarter: April and May are both in the
    # second, though the months differ. `en` writes `yQQQ` "QQQ y" and has
    # no interval of quarters, so two are written around its fallback
    # pattern. ICU4C 78.3 writes both dates of the one quarter, "Q2 2026 –
    # Q2 2026", which `guides/icu_divergences.md` records.
    test "of quarters writes one quarter where the months are in the same one" do
      assert interval(~D[2026-04-15], ~D[2026-05-20], format: :yQQQ, locale: :en) ==
               {:ok, "Q2 2026"}

      assert interval(~D[2026-04-15], ~D[2026-05-20], format: :yQQQQ, locale: :en) ==
               {:ok, "2nd quarter 2026"}

      assert interval(~D[2026-04-15], ~D[2026-07-20], format: :yQQQ, locale: :en) ==
               {:ok, "Q2 2026#{@thin}–#{@thin}Q3 2026"}
    end

    # Two Mondays are one weekday, and January and June are two months
    # though each is written "J": a field's value is compared, not its text.
    # A month and a day a year apart are alike in every field written and
    # differ in a larger one, which the pattern is widened with. ICU4C 78.3
    # writes the two Mondays "Mon – Mon", and the others as here.
    test "compares the value of each field written" do
      assert interval(~D[2026-06-15], ~D[2026-06-22], format: :E, locale: :en) == {:ok, "Mon"}

      assert interval(~D[2026-01-15], ~D[2026-06-15], format: "MMMMM", locale: :en) ==
               {:ok, "J#{@thin}–#{@thin}J"}

      assert interval(~D[2026-01-05], ~D[2027-01-05], format: :MMMd, locale: :en) ==
               {:ok, "Jan 5, 2026#{@thin}–#{@thin}Jan 5, 2027"}
    end

    # Two dates that differ in a month or a year the skeleton does not write
    # take the interval of the skeleton widened with it: a day alone takes
    # `Md`'s across months, where "15 – 20" would read as days of one month,
    # and `yMd`'s across years, and the widened pattern keeps the widths
    # asked for.
    test "widens a skeleton with the month or the year its dates differ in" do
      for {locale, format, {from, to}, expected} <- [
            {:en, :d, {~D[2026-06-15], ~D[2026-06-20]}, "15#{@thin}–#{@thin}20"},
            {:en, :d, {~D[2026-06-15], ~D[2026-07-15]}, "6/15#{@thin}–#{@thin}7/15"},
            {:en, :d, {~D[2026-06-15], ~D[2026-07-20]}, "6/15#{@thin}–#{@thin}7/20"},
            {:en, :d, {~D[2026-06-15], ~D[2027-06-15]}, "6/15/2026#{@thin}–#{@thin}6/15/2027"},
            {:en, :d, {~D[2026-12-30], ~D[2027-01-02]}, "12/30/2026#{@thin}–#{@thin}1/2/2027"},
            {:en, :d, {~D[2026-06-15], ~D[2027-07-20]}, "6/15/2026#{@thin}–#{@thin}7/20/2027"},
            {:en, :MMMMd, {~D[2026-06-15], ~D[2027-06-15]},
             "June 15, 2026#{@thin}–#{@thin}June 15, 2027"},
            {:en, :MEd, {~D[2026-06-15], ~D[2027-06-15]},
             "Mon, 6/15/2026#{@thin}–#{@thin}Tue, 6/15/2027"},
            {:en, :MMMM, {~D[2026-06-15], ~D[2027-06-15]}, "June 2026#{@thin}–#{@thin}June 2027"},
            {:de, :d, {~D[2026-06-15], ~D[2026-07-15]}, "15.06.#{@thin}–#{@thin}15.07."},
            {:de, :d, {~D[2026-06-15], ~D[2027-06-15]}, "15.06.2026#{@thin}–#{@thin}15.06.2027"},
            {:fr, :d, {~D[2026-06-15], ~D[2026-07-15]}, "15/06#{@thin}–#{@thin}15/07"},
            {:fr, :d, {~D[2026-06-15], ~D[2027-06-15]}, "15/06/2026#{@thin}–#{@thin}15/06/2027"},
            {:ja, :d, {~D[2026-06-15], ~D[2026-07-15]}, "06/15～07/15"},
            {:ja, :d, {~D[2026-06-15], ~D[2027-06-15]}, "2026/06/15～2027/06/15"}
          ] do
        assert interval(from, to, format: format, locale: locale) == {:ok, expected},
               inspect({locale, format, from, to})
      end
    end

    # A skeleton CLDR has no interval for is widened the same way, where
    # ICU4C 78.3 writes both dates with it as it stands: "15 Mon – 15 Wed",
    # "Q2 – Q2" and "25 – 25". A weekday and a day take `MEd`'s interval, "E,
    # M/d – E, M/d" in `en`; a quarter and a week take their year, written
    # in full as `yQQQ` and `yw`. Two days of one week either side of the
    # new year are one week, whose year is the week's.
    test "widens a skeleton that has no interval of its own" do
      assert interval(~D[2026-06-15], ~D[2026-07-15], format: :Ed, locale: :en) ==
               {:ok, "Mon, 6/15#{@thin}–#{@thin}Wed, 7/15"}

      assert interval(~D[2026-06-15], ~D[2027-06-15], format: :QQQ, locale: :en) ==
               {:ok, "Q2 2026#{@thin}–#{@thin}Q2 2027"}

      assert interval(~D[2026-06-15], ~D[2027-06-15], format: :w, locale: :en) ==
               {:ok, "week 25 of 2026#{@thin}–#{@thin}week 25 of 2027"}

      assert interval(~D[2026-12-30], ~D[2027-01-02], format: :w, locale: :en) == {:ok, "1"}

      assert interval(~D[2026-06-15], ~D[2026-07-15], format: :E, locale: :en) ==
               {:ok, "Mon#{@thin}–#{@thin}Wed"}
    end
  end

  describe "a datetime interval" do
    test "splits a skeleton into its date and time fields" do
      from = ~N[2026-06-15 10:00:00]
      same_day = ~N[2026-06-15 14:30:00]

      for {skeleton, expected} <- [
            {:yMMMdHm, "Jun 15, 2026, 10:00#{@thin}–#{@thin}14:30"},
            {:yMMMdHms, "Jun 15, 2026, 10:00:00#{@thin}–#{@thin}14:30:00"},
            {:yMMMEdhm, "Mon, Jun 15, 2026, 10:00#{@narrow}AM#{@thin}–#{@thin}2:30#{@narrow}PM"},
            {:yMMMdjm, "Jun 15, 2026, 10:00#{@narrow}AM#{@thin}–#{@thin}2:30#{@narrow}PM"}
          ] do
        assert interval(from, same_day, format: skeleton, locale: :en) == {:ok, expected}
      end

      assert interval(from, same_day, format: :yMMMdjm, locale: "en-u-hc-h23") ==
               {:ok, "Jun 15, 2026, 10:00#{@thin}–#{@thin}14:30"}

      assert interval(from, ~N[2026-06-16 14:30:00], format: :yMMMdHm, locale: :en) ==
               {:ok, "Jun 15, 2026, 10:00#{@thin}–#{@thin}Jun 16, 2026, 14:30"}
    end

    test "with a skeleton of time fields writes the times alone" do
      assert interval(~N[2026-06-15 10:00:00], ~N[2026-06-15 14:30:00], format: :Hm, locale: :en) ==
               {:ok, "10:00#{@thin}–#{@thin}14:30"}

      assert {:ok, parts} =
               Localize.Interval.to_parts(~N[2026-06-15 10:00:00], ~N[2026-06-15 14:30:00],
                 format: :Hm,
                 locale: :en
               )

      assert Enum.map_join(parts, & &1.value) == "10:00#{@thin}–#{@thin}14:30"
    end

    # TR35's algorithm read as it is written, as the user chose (2026-10-01):
    # no `Hm` item has a day difference, so both values are formatted with
    # the skeleton around the fallback pattern. ICU4C 78.3 adds the locale's
    # `yMd` date, "6/15/2026, 10:00 – 6/16/2026, 14:30".
    test "with a skeleton of time fields across days writes the times alone" do
      assert interval(~N[2026-06-15 10:00:00], ~N[2026-06-16 14:30:00], format: :Hm, locale: :en) ==
               {:ok, "10:00#{@thin}–#{@thin}14:30"}
    end

    test "with a skeleton of date fields is a date interval" do
      assert interval(~N[2026-06-15 10:00:00], ~N[2026-06-16 14:30:00],
               format: :yMMMd,
               locale: :en
             ) == {:ok, "Jun 15#{@thin}–#{@thin}16, 2026"}

      assert interval(~N[2026-06-15 10:00:00], ~N[2026-06-15 14:30:00],
               format: :yMMMd,
               locale: :en
             ) == {:ok, "Jun 15, 2026"}
    end

    # TR35: "If an interval is being formatted, use the standard combining
    # pattern", for a date joined to a time range ("March 15, 3:00 – 5:00
    # PM") and for whole datetimes ("March 15, 9:00 AM – March 16, 5:00
    # PM"). ICU4C 78.3 writes the first as these do and joins the second's
    # whole datetimes with the "at" pattern ("June 15, 2026 at 10:00 – June
    # 16, 2026 at 14:30").
    test "joins a date and a time with the standard pattern" do
      from = ~N[2026-06-15 10:00:00]

      for {locale, same_day, two_days} <- [
            {:en, "June 15, 2026, 10:00#{@thin}–#{@thin}14:30",
             "June 15, 2026, 10:00#{@thin}–#{@thin}June 16, 2026, 14:30"},
            {:de, "15. Juni 2026, 10:00–14:30 Uhr",
             "15. Juni 2026, 10:00#{@thin}–#{@thin}16. Juni 2026, 14:30"},
            {:fr, "15 juin 2026, 10:00#{@thin}–#{@thin}14:30",
             "15 juin 2026, 10:00#{@thin}–#{@thin}16 juin 2026, 14:30"}
          ] do
        assert interval(from, ~N[2026-06-15 14:30:00], format: :yMMMMdHm, locale: locale) ==
                 {:ok, same_day}

        assert interval(from, ~N[2026-06-16 14:30:00], format: :yMMMMdHm, locale: locale) ==
                 {:ok, two_days}
      end

      assert interval(from, nil, format: :yMMMMdHm, locale: :en) ==
               {:ok, "June 15, 2026, 10:00#{@thin}–"}

      assert interval(from, from, format: :yMMMMdHm, locale: :en) ==
               {:ok, "June 15, 2026, 10:00"}

      assert interval(from, ~N[2026-06-15 14:30:00], format: :yMMMMdHm, locale: :en, style: :at) ==
               {:ok, "June 15, 2026 at 10:00#{@thin}–#{@thin}14:30"}
    end

    test "joins its parts to the same text" do
      for format <- [:yMMMdHm, :yMMMEdhm, :Hm, :yMMMd] do
        from = ~N[2026-06-15 10:00:00]
        to = ~N[2026-06-15 14:30:00]
        assert {:ok, text} = interval(from, to, format: format, locale: :en)
        assert {:ok, parts} = Localize.Interval.to_parts(from, to, format: format, locale: :en)
        assert Enum.map_join(parts, & &1.value) == text
      end
    end
  end
end
