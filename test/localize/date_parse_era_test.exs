defmodule Localize.DateParseEraTest do
  @moduledoc """
  A date written with its era parses to the year that era counts to.

  TR35 makes `y` the year of the era `G` names, so "1 BC" is year 0 and
  "44 BC" year -43. ICU4C 78.3 parses "Jun 1, 1 BC" to year 0, as Localize
  does. ICU also pivots a two-digit year it reads beside an era, so "Jun 1,
  44 BC" becomes 2044 BC and ICU cannot read back its own "44 BC"; Localize
  takes a year its era qualifies as written, and keeps the pivot for a year
  written without one.

  A calendar without a before era writes a year below 1 with its sign, as
  Calendrical's Buddhist and Indian calendars do ("Mar 15, -456 BE"), and
  that parses back too.

  The sweep's reference is the formatter: every date it writes with an era,
  in every preloaded locale, parses back to itself.

  """

  use ExUnit.Case, async: true

  # A calendar with no year 0, numbering its years as Calendrical's Julian
  # calendar does: year -1 is 1 BC.
  defmodule NoYearZero do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :gregorian
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month
    def calendar_year(year, _month, _day), do: year
    def year_of_era(year, _month, _day) when year > 0, do: {year, 1}
    def year_of_era(year, _month, _day), do: {-year, 0}

    defdelegate valid_date?(year, month, day), to: Calendar.ISO
    defdelegate days_in_month(year, month), to: Calendar.ISO
    defdelegate months_in_year(year), to: Calendar.ISO
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  # A calendar with no before era, numbering its years as Calendrical's
  # Buddhist calendar does, so a year below 1 is written with its sign.
  defmodule NoBeforeEra do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :buddhist
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month
    def calendar_year(year, _month, _day), do: year
    def year_of_era(year, _month, _day), do: {year, 0}

    defdelegate valid_date?(year, month, day), to: Calendar.ISO
    defdelegate days_in_month(year, month), to: Calendar.ISO
    defdelegate months_in_year(year), to: Calendar.ISO
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  # The Hebrew calendar's months, as Calendrical's Hebrew calendar answers
  # for them: a year has twelve, or thirteen in a leap year, counted by
  # their place, and CLDR numbers them 1 to 13 with Adar I the sixth, so a
  # common year's months from Adar on are one more than their place, and a
  # leap year's seventh is CLDR's leap-year name of month 7, Adar II. Asked
  # about a date it has not, the thirteenth month of a common year, it
  # answers `{:error, :invalid_date}`, as Calendrical's does.
  defmodule Hebrew do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :hebrew
    def cardinal_month(month), do: month

    def leap_year?(year), do: Integer.mod(7 * year + 1, 19) < 7
    def months_in_year(year), do: if(leap_year?(year), do: 13, else: 12)
    def days_in_month(_year, _month), do: 29
    def valid_date?(year, month, day), do: month in 1..months_in_year(year) and day in 1..29

    def calendar_year(year, month, day), do: if_valid(year, month, day, year)
    def year_of_era(year, month, day), do: if_valid(year, month, day, {year, 0})

    def month_of_year(year, month, day) do
      cond do
        not valid_date?(year, month, day) -> {:error, :invalid_date}
        leap_year?(year) and month == 7 -> {7, :leap}
        leap_year?(year) or month < 6 -> month
        true -> month + 1
      end
    end

    defp if_valid(year, month, day, answer),
      do: if(valid_date?(year, month, day), do: answer, else: {:error, :invalid_date})

    defdelegate date_to_string(year, month, day), to: Calendar.ISO

    def naive_datetime_to_iso_days(year, month, day, _hour, _minute, _second, _microsecond) do
      months_before =
        Enum.sum(for y <- 5700..(year - 1)//1, do: months_in_year(y)) + month - 1

      {months_before * 29 + day, {0, 86_400_000_000}}
    end
  end

  # The Japanese calendar's last three eras, Shōwa from 1926-12-25, Heisei
  # from 1989-01-08 and Reiwa from 2019-05-01 (CLDR's `supplementalData.xml`),
  # its dates otherwise ISO's, as Calendrical's Japanese calendar has them.
  defmodule Japanese do
    @moduledoc false
    use Localize.Test.StandInCalendar

    @eras [{~D[2019-05-01], 236}, {~D[1989-01-08], 235}, {~D[1926-12-25], 234}]

    def cldr_calendar_type, do: :japanese
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month

    def year_of_era(_year, month, day) when is_nil(month) or is_nil(day),
      do: {:error, :missing_fields}

    def year_of_era(year, month, day) do
      with {:ok, date} <- Date.new(year, month, day),
           {start, era} <-
             Enum.find(@eras, fn {start, _era} -> Date.compare(date, start) != :lt end) do
        {year - start.year + 1, era}
      else
        _no_era -> {:error, :invalid_date}
      end
    end

    def calendar_year(year, month, day) do
      with {year_of_era, _era} <- year_of_era(year, month, day), do: year_of_era
    end

    defdelegate valid_date?(year, month, day), to: Calendar.ISO
    defdelegate days_in_month(year, month), to: Calendar.ISO
    defdelegate months_in_year(year), to: Calendar.ISO
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  # The Japanese calendar numbering its years as Calendrical's
  # `Reform.Japan` does: from 645 until the reform, its year 1228 being
  # 1872, and as the Gregorian calendar numbers them from 1873, so it has no
  # years 1229 to 1872. Its months and days are ISO's throughout. The eras
  # are CLDR's (`supplementalData.xml`): Meiji from 1868-10-23, Taishō from
  # 1912-07-30, Shōwa from 1926-12-25, Heisei from 1989-01-08 and Reiwa from
  # 2019-05-01.
  defmodule ReformedJapanese do
    @moduledoc false
    use Localize.Test.StandInCalendar

    @reform 1873
    @offset 644

    @eras [
      {{2019, 5, 1}, 236},
      {{1989, 1, 8}, 235},
      {{1926, 12, 25}, 234},
      {{1912, 7, 30}, 233},
      {{1868, 10, 23}, 232}
    ]

    def cldr_calendar_type, do: :japanese
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month

    def year_of_era(_year, month, day) when is_nil(month) or is_nil(day),
      do: {:error, :missing_fields}

    def year_of_era(year, month, day) do
      gregorian = {gregorian_year(year), month, day}

      with true <- valid_date?(year, month, day),
           {{start_year, _month, _day}, era} <-
             Enum.find(@eras, fn {start, _era} -> gregorian >= start end) do
        {gregorian_year(year) - start_year + 1, era}
      else
        _no_such_date_or_before_meiji -> {:error, :invalid_date}
      end
    end

    def calendar_year(year, month, day) do
      with {year_of_era, _era} <- year_of_era(year, month, day), do: year_of_era
    end

    def valid_date?(year, month, day) do
      (year >= @reform or year < @reform - @offset) and
        Calendar.ISO.valid_date?(gregorian_year(year), month, day)
    end

    def days_in_month(year, month), do: Calendar.ISO.days_in_month(gregorian_year(year), month)
    def months_in_year(_year), do: 12

    defdelegate date_to_string(year, month, day), to: Calendar.ISO
    defdelegate day_rollover_relative_to_midnight_utc, to: Calendar.ISO

    def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
      Calendar.ISO.naive_datetime_to_iso_days(
        gregorian_year(year),
        month,
        day,
        hour,
        minute,
        second,
        microsecond
      )
    end

    def naive_datetime_from_iso_days(iso_days) do
      {year, month, day, hour, minute, second, microsecond} =
        Calendar.ISO.naive_datetime_from_iso_days(iso_days)

      own_year = if year >= @reform, do: year, else: year - @offset
      {own_year, month, day, hour, minute, second, microsecond}
    end

    defp gregorian_year(year) when year >= @reform, do: year
    defp gregorian_year(year), do: year + @offset
  end

  @locales ~w(am ar bal be bn cy da de en en-AU es fa fi fr he hi hu it ja ko ky mr my pt ru th uk zh zh-Hant)a

  describe "a year written with its era" do
    test "counts from that era" do
      assert Localize.Date.parse("Jun 1, 1 BC", locale: :en) == {:ok, ~D[0000-06-01]}
      assert Localize.Date.parse("Jun 1, 44 BC", locale: :en) == {:ok, ~D[-0043-06-01]}
      assert Localize.Date.parse("Jun 1, 44 AD", locale: :en) == {:ok, ~D[0044-06-01]}
      assert Localize.Date.parse("Jun 1, 2025 AD", locale: :en) == {:ok, ~D[2025-06-01]}

      assert Localize.Date.parse("1001 BC", locale: :en, as: :map) ==
               {:ok, %{calendar: Calendar.ISO, year: -1000}}
    end

    test "is not pivoted, where a two-digit year without one still is" do
      assert {:ok, %Date{year: year}} = Localize.Date.parse("Jun 1, 44", locale: :en)
      assert year > 1999
    end

    test "counts back from year -1 in a calendar without a year 0" do
      assert Localize.Date.parse("Mar 15, 1 BC", locale: :en, calendar: NoYearZero, as: :map) ==
               {:ok, %{calendar: NoYearZero, year: -1, month: 3, day: 15}}
    end

    test "resolves both ends of an interval" do
      assert Localize.Interval.parse("Mar 15 – 20, 44 BC", locale: :en) ==
               {:ok, Date.range(~D[-0043-03-15], ~D[-0043-03-20])}

      assert Localize.Interval.parse("Mar 15, 44 BC – Mar 20, 44 BC", locale: :en) ==
               {:ok, Date.range(~D[-0043-03-15], ~D[-0043-03-20])}

      assert {:ok, %Date.Range{first: %Date{year: year}}} =
               Localize.Interval.parse("Mar 15 – 20, 44", locale: :en)

      assert year > 1999
    end
  end

  # The calendar says which of its years is written as a year of the era, and
  # is asked about the date the text gives. A month in the text is CLDR's
  # number for it, which is the month's place in the year only in a calendar
  # that numbers its months so: `root.xml` names the Hebrew month 13 "Elul",
  # the twelfth month of a common year, and the era's name is "AM". The
  # calendar was asked about the thirteenth month of a year of twelve, so no
  # Hebrew date in Elul was read beside its era, nor an interval ending in it.
  describe "a year of an era beside a month the calendar counts by its place" do
    @hebrew_reference %{calendar: Hebrew, year: 5786, month: 10, day: 1}

    test "is read in Elul of a common year, CLDR's month 13" do
      elul = Date.new!(5786, 12, 7, Hebrew)

      assert Localize.Date.to_string(elul, format: :medium, locale: :de) ==
               {:ok, "07.13.5786 AM"}

      assert Localize.Date.parse("07.13.5786 AM", locale: :de, calendar: Hebrew) == {:ok, elul}

      assert Localize.Date.parse("7 Elul 5786 AM",
               locale: :en,
               calendar: Hebrew,
               format: "d MMM y G"
             ) == {:ok, elul}
    end

    test "is read in every month of a common year and of a leap year" do
      failures =
        for year <- [5786, 5787],
            month <- 1..Hebrew.months_in_year(year),
            locale <- [:de, :ar, :he, :fr, :en],
            format <- [:short, :medium, :long, :GyMMMd, :GyMd],
            date = Date.new!(year, month, 7, Hebrew),
            {:ok, text} = Localize.Date.to_string(date, format: format, locale: locale),
            parsed =
              Localize.Date.parse(text,
                locale: locale,
                calendar: Hebrew,
                reference_date: @hebrew_reference
              ),
            parsed != {:ok, date} do
          {locale, format, date, text, parsed}
        end

      assert failures == [], inspect(Enum.take(failures, 5), pretty: true)
    end

    test "is read at both ends of an interval that ends in Elul" do
      from = Date.new!(5786, 10, 1, Hebrew)
      to = Date.new!(5786, 12, 7, Hebrew)

      failures =
        for locale <- [:de, :ar, :he, :fr, :en],
            format <- [:medium, :long],
            {:ok, text} = Localize.Interval.to_string(from, to, format: format, locale: locale),
            parsed =
              Localize.Interval.parse(text,
                locale: locale,
                calendar: Hebrew,
                reference_date: @hebrew_reference
              ),
            parsed != {:ok, Date.range(from, to)} do
          {locale, format, text, parsed}
        end

      assert failures == [], inspect(Enum.take(failures, 5), pretty: true)
    end
  end

  # CLDR's interval patterns write an era once where both dates are in it:
  # `en.xml`'s Japanese `GyMd` is "M/d/y – M/d/y G" and `ja.xml`'s
  # "GGGGGy/MM/dd～y/MM/dd". The date without the era is of the era beside
  # the other date. It was read in the era of the reference date, so five
  # days of Heisei 5 (1993) read from 2026 ran on to Reiwa 5 (2023).
  describe "an interval's era, written once" do
    @reiwa_8 Date.new!(2026, 6, 16, Japanese)

    defp japanese_interval(text, locale) do
      Localize.Interval.parse(text, locale: locale, calendar: Japanese, reference_date: @reiwa_8)
    end

    test "is the era of the date written without one" do
      from = Date.new!(1993, 6, 16, Japanese)
      to = Date.new!(1993, 6, 20, Japanese)

      assert Localize.Interval.to_string(from, to, locale: :en, format: :GyMd) ==
               {:ok, "6/16/5 – 6/20/5 Heisei"}

      assert japanese_interval("6/16/5 – 6/20/5 Heisei", :en) ==
               {:ok, Date.range(from, to)}

      assert Localize.Interval.to_string(from, to, locale: :ja, format: :GyMd) ==
               {:ok, "H5/06/16～5/06/20"}

      assert japanese_interval("H5/06/16～5/06/20", :ja) == {:ok, Date.range(from, to)}
    end

    test "is the era of a year written without one" do
      from = Date.new!(1993, 6, 16, Japanese)

      failures =
        for locale <- [:en, :ja, :de, :fr, :ko, :zh],
            format <- [:medium, :long, :GyMd, :GyMMMd],
            to <- [
              Date.new!(1993, 6, 20, Japanese),
              Date.new!(1993, 8, 20, Japanese),
              Date.new!(1994, 8, 20, Japanese)
            ],
            {:ok, text} = Localize.Interval.to_string(from, to, locale: locale, format: format),
            parsed = japanese_interval(text, locale),
            parsed != {:ok, Date.range(from, to)} do
          {locale, format, text, parsed}
        end

      assert failures == [], inspect(Enum.take(failures, 5), pretty: true)
    end

    # Two eras are each written, and each date keeps its own.
    test "leaves a date the era written beside it" do
      from = Date.new!(1988, 6, 16, Japanese)
      to = Date.new!(1990, 8, 20, Japanese)

      for locale <- [:en, :ja, :de], format <- [:medium, :GyMd] do
        {:ok, text} = Localize.Interval.to_string(from, to, locale: locale, format: format)

        assert japanese_interval(text, locale) == {:ok, Date.range(from, to)},
               "#{locale} #{inspect(text)}"
      end
    end

    # `en.xml`'s Gregorian `GyMMMd` for a year's difference is
    # "MMM d, y – MMM d, y G": 45 BC to 44 BC.
    test "is the era before the common era of both years" do
      assert Localize.Interval.to_string(~D[-0044-03-15], ~D[-0043-05-20],
               locale: :en,
               format: :GyMMMd
             ) == {:ok, "Mar 15, 45 – May 20, 44 BC"}

      assert Localize.Interval.parse("Mar 15, 45 – May 20, 44 BC", locale: :en) ==
               {:ok, Date.range(~D[-0044-03-15], ~D[-0043-05-20])}
    end
  end

  # An interval item states its era as `G`, and the formatter writes it at
  # the width the format asks for: most locales' short date formats write
  # the narrow era, `am.xml`'s Japanese short date being "dd/MM/y GGGGG" and
  # its interval "R 8/06/16 – 8/06/20". TR35's parsing takes a field's other
  # forms "if they are unique"; the narrow name was read only where the
  # pattern in hand had five letters.
  describe "a narrow era name" do
    test "is read in an interval whose item states another width" do
      from = Date.new!(2026, 6, 16, Japanese)

      failures =
        for locale <- [:am, :ar, :en, :fr, :de, :ja, :ko],
            format <- [:short, :medium],
            to <- [
              Date.new!(2026, 6, 20, Japanese),
              Date.new!(2026, 8, 20, Japanese),
              Date.new!(2027, 8, 20, Japanese)
            ],
            {:ok, text} = Localize.Interval.to_string(from, to, locale: locale, format: format),
            parsed = japanese_interval(text, locale),
            parsed != {:ok, Date.range(from, to)} do
          {locale, format, text, parsed}
        end

      assert failures == [], inspect(Enum.take(failures, 5), pretty: true)
    end

    test "is read beside a date, where it names one era" do
      assert Localize.Date.parse("6/16/8 R",
               locale: :en,
               calendar: Japanese,
               reference_date: @reiwa_8
             ) == {:ok, Date.new!(2026, 6, 16, Japanese)}

      assert Localize.Date.parse("6/16/5 H",
               locale: :en,
               calendar: Japanese,
               reference_date: @reiwa_8
             ) == {:ok, Date.new!(1993, 6, 16, Japanese)}
    end

    # en.xml's Gregorian formats state the era as `G`, "AD" and "BC", and
    # its narrow names are "A" and "B": no format states them, and the text
    # is read once one that allows them is tried.
    test "is read beside a date where no format states it" do
      assert Localize.Date.parse("6/16/2026 A", locale: :en) == {:ok, ~D[2026-06-16]}
      assert Localize.Date.parse("3/15/44 B", locale: :en) == {:ok, ~D[-0043-03-15]}
      assert Localize.Date.parse("Mar 15, 44 B", locale: :en) == {:ok, ~D[-0043-03-15]}
    end

    # `sv.xml` writes a Japanese date at `GyMd` with "y-MM-dd GGGGG", the
    # narrow era stated, and `sv_AX.xml`'s short date is "d.M.y G". Each
    # reads "8-01-07 R", CLDR's lenient dates taking a hyphen for a full
    # stop: the format that states the narrow name is the one that wrote it,
    # and the other would make it the 8th of January of Reiwa 7.
    test "is read by the format that states it before one that allows it" do
      date = Date.new!(2026, 1, 7, Japanese)

      assert Localize.Date.to_string(date, locale: :"sv-AX", format: :GyMd) ==
               {:ok, "8-01-07 R"}

      assert Localize.Date.parse("8-01-07 R",
               locale: :"sv-AX",
               calendar: Japanese,
               reference_date: @reiwa_8
             ) == {:ok, date}

      # The short date's own text is read in its order, the era's
      # abbreviated name stated.
      assert Localize.Date.to_string(date, locale: :"sv-AX", format: :short) ==
               {:ok, "7.1.8 Reiwa"}

      assert Localize.Date.parse("7.1.8 Reiwa",
               locale: :"sv-AX",
               calendar: Japanese,
               reference_date: @reiwa_8
             ) == {:ok, date}
    end
  end

  # ja.xml's Japanese full, long and medium dates are written with
  # `numbers="y=jpanyear"`, whose rule (`rbnf/ja.xml`,
  # `%spellout-numbering-year-latn`) writes 1 as 元 and every other year in
  # digits, so the first year of an era is "令和元年5月1日", as ICU writes
  # it. A day in `hanidays` and a month in `romanlow` were read as written,
  # and this year was not.
  describe "the first year of an era" do
    defp japanese(text, locale, options \\ []) do
      Localize.Date.parse(
        text,
        [locale: locale, calendar: Japanese, reference_date: @reiwa_8] ++ options
      )
    end

    test "is read as ja writes it" do
      for {date, medium, full} <- [
            {Date.new!(2019, 5, 1, Japanese), "令和元年5月1日", "令和元年5月1日水曜日"},
            {Date.new!(1989, 1, 8, Japanese), "平成元年1月8日", "平成元年1月8日日曜日"},
            {Date.new!(1926, 12, 25, Japanese), "昭和元年12月25日", "昭和元年12月25日土曜日"}
          ] do
        assert Localize.Date.to_string(date, locale: :ja, format: :medium) == {:ok, medium}
        assert Localize.Date.to_string(date, locale: :ja, format: :long) == {:ok, medium}
        assert Localize.Date.to_string(date, locale: :ja, format: :full) == {:ok, full}

        assert japanese(medium, :ja) == {:ok, date}
        assert japanese(full, :ja) == {:ok, date}
        assert japanese(medium, :ja, format: :medium) == {:ok, date}
        assert japanese(full, :ja, format: :full) == {:ok, date}
      end
    end

    test "is read in digits too, and other years as they were" do
      assert japanese("令和1年5月1日", :ja) == {:ok, Date.new!(2019, 5, 1, Japanese)}
      assert japanese("令和8年6月16日", :ja) == {:ok, Date.new!(2026, 6, 16, Japanese)}
      assert japanese("平成31年4月30日", :ja) == {:ok, Date.new!(2019, 4, 30, Japanese)}
    end

    test "reads back in an interval" do
      from = Date.new!(2019, 5, 1, Japanese)

      failures =
        for format <- [:short, :medium, :long, :full],
            to <- [
              Date.new!(2019, 5, 5, Japanese),
              Date.new!(2019, 8, 20, Japanese),
              Date.new!(2020, 8, 20, Japanese)
            ],
            {:ok, text} = Localize.Interval.to_string(from, to, locale: :ja, format: format),
            parsed = japanese_interval(text, :ja),
            parsed != {:ok, Date.range(from, to)} do
          {format, text, parsed}
        end

      assert failures == [], inspect(failures, pretty: true)
    end
  end

  # A calendar may number its years one way when an era begins and another
  # before it ends: Calendrical's Japanese reform calendar counts its
  # lunisolar years from 645 and its years from 1873 as the Gregorian
  # calendar does, so Meiji, which CLDR begins on 1868-10-23, begins in its
  # year 1224, and Meiji 6 is its year 1873. The year was counted on from
  # 1224 alone, to a year 1229 the calendar does not have, so no date from
  # the reform to the end of Meiji in 1912 was read.
  describe "a year of an era that began before the calendar renumbered its years" do
    @reiwa_8_reformed Date.new!(2026, 6, 16, ReformedJapanese)

    defp reformed(text, locale) do
      Localize.Date.parse(text,
        locale: locale,
        calendar: ReformedJapanese,
        reference_date: @reiwa_8_reformed
      )
    end

    # en.xml's Japanese medium date is "MMM d, y G" and ja.xml's "Gy年M月d日".
    test "is read from the year CLDR gives the era's beginning" do
      meiji_6 = Date.new!(1873, 6, 16, ReformedJapanese)

      assert Localize.Date.to_string(meiji_6, locale: :en, format: :medium) ==
               {:ok, "Jun 16, 6 Meiji"}

      assert reformed("Jun 16, 6 Meiji", :en) == {:ok, meiji_6}
      assert reformed("明治6年6月16日", :ja) == {:ok, meiji_6}

      # Meiji's last day was 1912-07-29.
      assert reformed("Jul 29, 45 Meiji", :en) == {:ok, Date.new!(1912, 7, 29, ReformedJapanese)}
    end

    test "is still counted from the era's first year before the calendar renumbers" do
      # Meiji 2 is 1869, the calendar's year 1225.
      meiji_2 = Date.new!(1225, 6, 16, ReformedJapanese)

      assert Localize.Date.to_string(meiji_2, locale: :en, format: :medium) ==
               {:ok, "Jun 16, 2 Meiji"}

      assert reformed("Jun 16, 2 Meiji", :en) == {:ok, meiji_2}
    end

    test "is read as it was for an era that began after it" do
      assert reformed("Jun 16, 2 Taishō", :en) == {:ok, Date.new!(1913, 6, 16, ReformedJapanese)}
      assert reformed("Jun 16, 5 Heisei", :en) == {:ok, Date.new!(1993, 6, 16, ReformedJapanese)}
    end

    # A format that writes no era leaves the year to the era of the
    # reference date, so the formats here are the ones with an era, and
    # each text is read with the format that wrote it: `my`'s `GyMd` is
    # "GGGGG y/M/d" beside a short date of "GGGGG d/M/y".
    test "reads back in each locale's formats with an era" do
      dates = [
        Date.new!(1873, 1, 1, ReformedJapanese),
        Date.new!(1873, 6, 16, ReformedJapanese),
        Date.new!(1900, 2, 28, ReformedJapanese),
        Date.new!(1912, 7, 29, ReformedJapanese)
      ]

      failures =
        for locale <- @locales,
            format <- [:GyMd, :GyMMMd, :GyMMMEd],
            date <- dates,
            {:ok, text} = Localize.Date.to_string(date, locale: locale, format: format),
            parsed =
              Localize.Date.parse(text,
                locale: locale,
                calendar: ReformedJapanese,
                format: format,
                reference_date: @reiwa_8_reformed
              ),
            parsed != {:ok, date} do
          {locale, format, text, parsed}
        end

      assert failures == [], inspect(Enum.take(failures, 5), pretty: true)
    end
  end

  describe "a year written with its sign" do
    test "parses back in a calendar without a before era" do
      assert Localize.Date.parse("Mar 15, -456 BE", locale: :en, calendar: NoBeforeEra, as: :map) ==
               {:ok, %{calendar: NoBeforeEra, year: -456, month: 3, day: 15}}

      for locale <- [:en, :th], year <- [-456, -1, 0, 2568] do
        date = %{year: year, month: 3, day: 15, calendar: NoBeforeEra}
        {:ok, text} = Localize.Date.to_string(date, format: :GyMMMd, locale: locale)

        assert Localize.Date.parse(text, locale: locale, calendar: NoBeforeEra, as: :map) ==
                 {:ok, date},
               "#{locale} #{inspect(text)}"
      end
    end

    test "takes either minus sign and is never pivoted" do
      assert Localize.Date.parse("Jun 1, -4", locale: :en) == {:ok, ~D[-0004-06-01]}
      assert Localize.Date.parse("Jun 1, −4", locale: :en) == {:ok, ~D[-0004-06-01]}
    end
  end

  # Each format with the shape of value it holds: a whole date parses to a
  # `t:Date.t/0`, and a year and month, or a year, parse with `as: :map`.
  @formats [
    {:GyMMMd, :date},
    {:GyMMMEd, :date},
    {:GyMMMMd, :date},
    {:GyMd, :date},
    {:GyMMM, :year_and_month},
    {:Gy, :year}
  ]

  describe "every date the formatter writes with an era" do
    test "parses back to itself in every preloaded locale" do
      failures =
        for locale <- @locales,
            {format, shape} <- @formats,
            year <- [-1000, -43, -1, 0, 1, 44, 999, 2025],
            date = Date.new!(year, 3, 15),
            {:ok, text} = Localize.Date.to_string(date, format: format, locale: locale),
            parsed = parse(text, shape, locale),
            not parsed_to?(parsed, date, shape) do
          {locale, format, date, text, parsed}
        end

      assert failures == [], inspect(Enum.take(failures, 5), pretty: true)
    end
  end

  defp parse(text, :date, locale), do: Localize.Date.parse(text, locale: locale)
  defp parse(text, _shape, locale), do: Localize.Date.parse(text, locale: locale, as: :map)

  defp parsed_to?(parsed, date, :date), do: parsed == {:ok, date}

  defp parsed_to?({:ok, %{year: year, month: month}}, date, :year_and_month),
    do: {year, month} == {date.year, date.month}

  defp parsed_to?({:ok, %{year: year}}, date, :year), do: year == date.year
  defp parsed_to?(_parsed, _date, _shape), do: false
end
