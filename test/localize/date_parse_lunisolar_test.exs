defmodule Localize.DateParseLunisolarTest do
  @moduledoc """
  Lunisolar dates, and the years of other calendars, parse back as the
  formatter writes them.

  The expected strings are ICU4C 78.3's, for the Chinese year 4660 (2023),
  whose leap second month follows its second month: Gregorian 2023-04-01
  is day 11 of the leap second month, and ICU writes it "2bis/11/2023" and
  "Mo2bis 11, 2023" in `en`, "2023/闰2/11", "2023年闰二月十一" and
  "2023癸卯年闰二月十一" in `zh`, "癸卯年閏二月一一日" in `ja` and
  "11-02 Nhuận Quý Mão" in `vi`. Localize does not depend on Calendrical,
  so the calendars here are stand-ins that answer as Calendrical's do.

  """

  use ExUnit.Case, async: true

  # Chinese years, numbered as Calendrical numbers them, of twelve months
  # but for 4660, whose leap second month is its third of thirteen.
  defmodule Lunisolar do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :chinese
    def cardinal_month(month), do: month

    def months_in_year(4660), do: 13
    def months_in_year(_year), do: 12

    def days_in_month(4660, 3), do: 29
    def days_in_month(_year, _month), do: 30

    def valid_date?(year, month, day),
      do: month in 1..months_in_year(year) and day in 1..days_in_month(year, month)

    def month_of_year(4660, 3, _day), do: {2, :leap}
    def month_of_year(4660, month, _day) when month > 3, do: month - 1
    def month_of_year(_year, month, _day), do: month

    def calendar_year(year, _month, _day), do: year
    def year_of_era(year, _month, _day), do: {year, 0}
    def related_gregorian_year(year, _month, _day), do: year - 2637
    def cyclic_year(year, _month, _day), do: Localize.Utils.Math.amod(year, 60)

    defdelegate date_to_string(year, month, day), to: Calendar.ISO

    # A day count from the first day of 4600, for `Date.range/2`.
    def naive_datetime_to_iso_days(year, month, day, _hour, _minute, _second, _microsecond) do
      days_before =
        for y <- 4600..year//1, m <- 1..months_in_year(y), {y, m} < {year, month}, reduce: 0 do
          days -> days + days_in_month(y, m)
        end

      {days_before + day, {0, 86_400_000_000}}
    end
  end

  # The same years, displayed as TR35 has a calendar of cyclic years display
  # one: its `calendar_year/3`, which `y` writes, is the year's place in the
  # sixty-year cycle, and its `extended_year/3`, which `u` writes, the year's
  # number.
  defmodule CyclicLunisolar do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :chinese
    def cardinal_month(month), do: month

    defdelegate months_in_year(year), to: Lunisolar
    defdelegate days_in_month(year, month), to: Lunisolar
    defdelegate valid_date?(year, month, day), to: Lunisolar
    defdelegate month_of_year(year, month, day), to: Lunisolar
    defdelegate year_of_era(year, month, day), to: Lunisolar
    defdelegate related_gregorian_year(year, month, day), to: Lunisolar
    defdelegate cyclic_year(year, month, day), to: Lunisolar
    defdelegate date_to_string(year, month, day), to: Calendar.ISO

    defdelegate naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond),
      to: Lunisolar

    def calendar_year(year, month, day), do: cyclic_year(year, month, day)
    def extended_year(year, _month, _day), do: year
  end

  # The same years, displayed as years of an imperial era, as Calendrical's
  # lunisolar Japanese calendar displays its own: the Chinese calendar's
  # months and cycle, the Japanese calendar's eras, 4656 being Reiwa 1.
  defmodule LunisolarEras do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :chinese
    def era_calendar_type, do: :japanese
    def cardinal_month(month), do: month

    defdelegate months_in_year(year), to: Lunisolar
    defdelegate days_in_month(year, month), to: Lunisolar
    defdelegate valid_date?(year, month, day), to: Lunisolar
    defdelegate month_of_year(year, month, day), to: Lunisolar
    defdelegate related_gregorian_year(year, month, day), to: Lunisolar
    defdelegate cyclic_year(year, month, day), to: Lunisolar
    defdelegate date_to_string(year, month, day), to: Calendar.ISO

    defdelegate naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond),
      to: Lunisolar

    def year_of_era(year, _month, _day), do: {year - 4655, 236}
    def calendar_year(year, _month, _day), do: year - 4655
  end

  # The Chinese calendar's years and cycle under three of the Japanese
  # calendar's eras, as Calendrical's lunisolar Japanese calendar has them:
  # Shōwa (era 234) from the year that began in 1926, Heisei (235) from 1989
  # and Reiwa (236) from 2019, each of whole years here. A year is its
  # Gregorian year and 2637, so 2026 is 4663, the forty-third of its cycle,
  # and its months and days are the Gregorian calendar's.
  defmodule ImperialLunisolar do
    @moduledoc false
    use Localize.Test.StandInCalendar

    @offset 2637
    @eras [{4656, 236}, {4626, 235}, {4563, 234}]

    def cldr_calendar_type, do: :chinese
    def era_calendar_type, do: :japanese
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month
    def related_gregorian_year(year, _month, _day), do: year - @offset
    def cyclic_year(year, _month, _day), do: Localize.Utils.Math.amod(year, 60)

    def year_of_era(year, _month, _day) do
      {first, era} = Enum.find(@eras, List.last(@eras), fn {first, _era} -> year >= first end)
      {year - first + 1, era}
    end

    def calendar_year(year, month, day), do: elem(year_of_era(year, month, day), 0)

    def valid_date?(year, month, day),
      do: year >= 4563 and Calendar.ISO.valid_date?(year - @offset, month, day)

    def days_in_month(year, month), do: Calendar.ISO.days_in_month(year - @offset, month)
    def months_in_year(year), do: Calendar.ISO.months_in_year(year - @offset)

    defdelegate date_to_string(year, month, day), to: Calendar.ISO
    defdelegate day_rollover_relative_to_midnight_utc, to: Calendar.ISO

    def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
      Calendar.ISO.naive_datetime_to_iso_days(
        year - @offset,
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

      {year + @offset, month, day, hour, minute, second, microsecond}
    end
  end

  # The tabular Islamic civil calendar (Reingold and Dershowitz,
  # "Calendrical Calculations", the arithmetic Islamic calendar): years of
  # 354 days, 355 in eleven of every thirty, months of 30 and 29 days in
  # turn, and a first day of Friday 16 July 622 in the Julian calendar. Its
  # year is eleven days shorter than the Gregorian calendar's, so its years
  # and their related Gregorian years drift apart, about three in a century.
  defmodule TabularIslamic do
    @moduledoc false
    use Localize.Test.StandInCalendar

    # The ISO day of 1 Muharram of year 1, Gregorian 0622-07-19.
    @epoch 227_380

    def cldr_calendar_type, do: :islamic_civil
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month
    def calendar_year(year, _month, _day), do: year
    def year_of_era(year, _month, _day), do: {year, 0}
    def months_in_year(_year), do: 12

    def days_in_month(year, 12), do: if(Integer.mod(14 + 11 * year, 30) < 11, do: 30, else: 29)
    def days_in_month(_year, month), do: if(rem(month, 2) == 1, do: 30, else: 29)

    def valid_date?(year, month, day),
      do: month in 1..12 and day in 1..days_in_month(year, month)

    def related_gregorian_year(year, _month, _day) do
      {gregorian_year, _month, _day} = Calendar.ISO.date_from_iso_days(first_day(year))
      gregorian_year
    end

    defdelegate date_to_string(year, month, day), to: Calendar.ISO
    defdelegate day_rollover_relative_to_midnight_utc, to: Calendar.ISO

    def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
      days = first_day(year) + 29 * (month - 1) + div(month, 2) + day - 1
      {days, Calendar.ISO.time_to_day_fraction(hour, minute, second, microsecond)}
    end

    def naive_datetime_from_iso_days({days, fraction}) do
      year = Integer.floor_div(30 * (days - @epoch) + 10_646, 10_631)
      {month, day} = month_and_day(year, days - first_day(year) + 1, 1)
      {hour, minute, second, microsecond} = Calendar.ISO.time_from_day_fraction(fraction)
      {year, month, day, hour, minute, second, microsecond}
    end

    defp first_day(year), do: @epoch + (year - 1) * 354 + Integer.floor_div(3 + 11 * year, 30)

    defp month_and_day(year, day, month) do
      days = days_in_month(year, month)
      if day <= days, do: {month, day}, else: month_and_day(year, day - days, month + 1)
    end
  end

  # A calendar numbering its years 543 ahead of the Gregorian, as the
  # Buddhist calendar does, with no era before its first.
  defmodule Offset do
    @moduledoc false
    use Localize.Test.StandInCalendar
    @offset 543

    def cldr_calendar_type, do: :buddhist
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month
    def calendar_year(year, _month, _day), do: year
    def year_of_era(year, _month, _day), do: {year, 0}

    def valid_date?(year, month, day), do: Calendar.ISO.valid_date?(year - @offset, month, day)
    def days_in_month(year, month), do: Calendar.ISO.days_in_month(year - @offset, month)
    def months_in_year(year), do: Calendar.ISO.months_in_year(year - @offset)

    defdelegate date_to_string(year, month, day), to: Calendar.ISO
    defdelegate day_rollover_relative_to_midnight_utc, to: Calendar.ISO

    def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
      Calendar.ISO.naive_datetime_to_iso_days(
        year - @offset,
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

      {year + @offset, month, day, hour, minute, second, microsecond}
    end
  end

  # The Ethiopic calendar's arithmetic, with the years before 1 in Amete
  # Alem, 5500 years earlier, as CLDR and ICU number them.
  defmodule Ethiopic do
    @moduledoc false
    use Localize.Test.StandInCalendar

    # The ISO day of 1 Meskerem of year 1, Gregorian 0008-08-27.
    @epoch 3161

    def cldr_calendar_type, do: :ethiopic
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month
    def calendar_year(year, _month, _day), do: year
    def year_of_era(year, _month, _day) when year >= 1, do: {year, 1}
    def year_of_era(year, _month, _day), do: {year + 5500, 0}

    def months_in_year(_year), do: 13
    def days_in_month(year, 13), do: if(Integer.mod(year, 4) == 3, do: 6, else: 5)
    def days_in_month(_year, _month), do: 30

    def valid_date?(year, month, day),
      do: month in 1..13 and day in 1..days_in_month(year, month)

    defdelegate date_to_string(year, month, day), to: Calendar.ISO
    defdelegate day_rollover_relative_to_midnight_utc, to: Calendar.ISO

    def naive_datetime_to_iso_days(year, month, day, _hour, _minute, _second, _microsecond),
      do: {iso_days(year, month, day), {0, 86_400_000_000}}

    def naive_datetime_from_iso_days({days, _fraction}) do
      year = Integer.floor_div(4 * (days - @epoch) + 1463, 1461)
      month = Integer.floor_div(days - iso_days(year, 1, 1), 30) + 1
      {year, month, days + 1 - iso_days(year, month, 1), 0, 0, 0, {0, 0}}
    end

    defp iso_days(year, month, day) do
      @epoch - 1 + 365 * (year - 1) + Integer.floor_div(year, 4) + 30 * (month - 1) + day
    end
  end

  # A calendar that writes its years as Japanese era years, as
  # Calendrical's lunisolar Japanese calendar does, and names its months
  # from the Chinese calendar and its eras from the Japanese one. Its
  # arithmetic is the Gregorian calendar's, its years counted from 645.
  defmodule EraYears do
    @moduledoc false
    use Localize.Test.StandInCalendar
    @offset -644

    def cldr_calendar_type, do: :chinese
    def cardinal_month(month), do: month
    def era_calendar_type, do: :japanese
    def month_of_year(_year, month, _day), do: month
    def related_gregorian_year(year, _month, _day), do: year - @offset

    # The era depends on the day, so a date without its month or day is not
    # this calendar's to answer, as Calendrical's Japanese calendar says of one.
    def year_of_era(_year, month, day) when is_nil(month) or is_nil(day),
      do: {:error, :missing_fields}

    # Reiwa began on 2019-05-01 and Heisei on 1989-01-08.
    def year_of_era(year, month, day) do
      gregorian = {year - @offset, month, day}

      if gregorian >= {2019, 5, 1},
        do: {year - @offset - 2018, 236},
        else: {year - @offset - 1988, 235}
    end

    def calendar_year(year, month, day) do
      with {year_of_era, _era} <- year_of_era(year, month, day), do: year_of_era
    end

    def valid_date?(year, month, day), do: Calendar.ISO.valid_date?(year - @offset, month, day)
    def days_in_month(year, month), do: Calendar.ISO.days_in_month(year - @offset, month)
    def months_in_year(year), do: Calendar.ISO.months_in_year(year - @offset)

    defdelegate date_to_string(year, month, day), to: Calendar.ISO
    defdelegate day_rollover_relative_to_midnight_utc, to: Calendar.ISO

    def naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond) do
      Calendar.ISO.naive_datetime_to_iso_days(
        year - @offset,
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

      {year + @offset, month, day, hour, minute, second, microsecond}
    end
  end

  # The Gregorian calendar with Japanese eras, as Calendrical's
  # `Reform.Japan` is from 1873: CLDR's Gregorian patterns and the
  # Japanese calendar's era names.
  defmodule JapaneseEras do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :gregorian
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month
    def era_calendar_type, do: :japanese

    # The era depends on the day, so a date without its month or day is not
    # this calendar's to answer, as Calendrical's Japanese calendar says of one.
    def year_of_era(_year, month, day) when is_nil(month) or is_nil(day),
      do: {:error, :missing_fields}

    # Reiwa began on 2019-05-01 and Heisei on 1989-01-08.
    def year_of_era(year, month, day) do
      if {year, month, day} >= {2019, 5, 1},
        do: {year - 2018, 236},
        else: {year - 1988, 235}
    end

    def calendar_year(year, month, day) do
      with {year_of_era, _era} <- year_of_era(year, month, day), do: year_of_era
    end

    defdelegate valid_date?(year, month, day), to: Calendar.ISO
    defdelegate days_in_month(year, month), to: Calendar.ISO
    defdelegate months_in_year(year), to: Calendar.ISO
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
    defdelegate day_rollover_relative_to_midnight_utc, to: Calendar.ISO

    defdelegate naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond),
      to: Calendar.ISO

    defdelegate naive_datetime_from_iso_days(iso_days), to: Calendar.ISO
  end

  # A calendar that computes only a range of years, as Calendrical's
  # Persian calendar does, and raises for a year outside it.
  defmodule Bounded do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :persian
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month

    def valid_date?(year, month, day),
      do: year >= 1000 and month in 1..12 and day in 1..days_in_month(year, month)

    def calendar_year(year, _month, _day) when year >= 1000, do: year
    def year_of_era(year, _month, _day) when year >= 1000, do: {year, 0}
    def months_in_year(year) when year >= 1000, do: 12
    def days_in_month(year, month) when year >= 1000 and month <= 6, do: 31
    def days_in_month(year, _month) when year >= 1000, do: 30

    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  # Chinese 4662, in which Gregorian 2025 began.
  @reference %{calendar: Lunisolar, year: 4662, month: 6, day: 1}

  defp parse(text, locale, options \\ []) do
    options =
      Keyword.merge([locale: locale, calendar: Lunisolar, reference_date: @reference], options)

    Localize.Date.parse(text, options)
  end

  defp date(year, month, day), do: Date.new!(year, month, day, Lunisolar)

  describe "ICU4C's lunisolar dates" do
    test "a leap month in its numeric and named forms" do
      leap_11 = date(4660, 3, 11)

      assert parse("2bis/11/2023", :en) == {:ok, leap_11}
      assert parse("Mo2bis 11, 2023", :en) == {:ok, leap_11}
      assert parse("Second Monthbis 11, 2023(gui-mao)", :en) == {:ok, leap_11}
      assert parse("2023/闰2/11", :zh) == {:ok, leap_11}
      assert parse("2023/閏2/11", :"zh-Hant") == {:ok, leap_11}
      assert parse("11-02 Nhuận Quý Mão", :vi) == {:ok, leap_11}
      assert parse("계묘년 윤2월 11일", :ko) == {:ok, leap_11}
    end

    test "a month after the leap month keeps its traditional number" do
      assert parse("3/1/2023", :en) == {:ok, date(4660, 4, 1)}
      assert parse("Mo3 1, 2023", :en) == {:ok, date(4660, 4, 1)}
      assert parse("2/30/2023", :en) == {:ok, date(4660, 2, 30)}
    end

    test "zh writes its days in hanidays" do
      assert parse("2023年闰二月初一", :zh) == {:ok, date(4660, 3, 1)}
      assert parse("2023年闰二月十一", :zh) == {:ok, date(4660, 3, 11)}
      assert parse("2023年闰二月二十", :zh) == {:ok, date(4660, 3, 20)}
      assert parse("2023年闰二月廿一", :zh) == {:ok, date(4660, 3, 21)}
      assert parse("2023年二月三十", :zh) == {:ok, date(4660, 2, 30)}
      assert parse("2023癸卯年闰二月十一", :zh) == {:ok, date(4660, 3, 11)}
    end

    test "ja writes its numbers in hanidec" do
      assert parse("癸卯年閏二月一一日", :ja) == {:ok, date(4660, 3, 11)}
      assert parse("癸卯年閏二月二〇日", :ja) == {:ok, date(4660, 3, 20)}
      assert parse("癸卯-閏2-11", :ja) == {:ok, date(4660, 3, 11)}
    end

    test "a leap month the year does not have is an error" do
      assert {:error, _} = parse("Mo3bis 1, 2023", :en)
      assert {:error, _} = parse("2bis/11/2024", :en)
    end
  end

  describe "the year" do
    test "a related year and a cyclic name written together must agree" do
      assert {:error, _} = parse("Second Monthbis 11, 2023(jia-zi)", :en)
    end

    # A cyclic name recurs every sixty years.
    test "a cyclic name alone is the year of that name nearest the reference year" do
      assert parse("Mo2 11, gui-mao", :en) == {:ok, date(4660, 2, 11)}

      assert parse("Mo2 11, gui-mao", :en, reference_date: %{@reference | year: 4700}) ==
               {:ok, date(4720, 2, 11)}
    end

    # ICU4C 78.3 reads `pl`'s medium "d MMM U" "1 12 jia-chen" as the
    # first day of the twelfth month; an available format reads the same
    # text month first.
    test "a date the standard format writes is read as it writes it" do
      assert parse("1 12 jia-chen", :pl) == {:ok, date(4661, 12, 1)}
    end

    # ICU4C 78.3 reads `de`'s Persian short "dd.MM.yy GGGGG" "01.04.02 AP"
    # as 1402. A year the calendar does not hold is an error, however its
    # calendar answers for it.
    test "a year beside its era is one the calendar holds" do
      reference = %{calendar: Bounded, year: 1405, month: 3, day: 1}
      options = [locale: :de, calendar: Bounded, reference_date: reference]

      assert Localize.Date.parse("01.04.02 AP", options) == {:ok, Date.new!(1402, 4, 1, Bounded)}
      assert {:error, _} = Localize.Date.parse("1.4.2 AP", options)
    end

    # `ko` writes the year as the calendar's year in "y. M. d." and as the
    # related year in "r. M. d.", so the same digits read as years 2637
    # apart.
    test "digits that read as the calendar's year or the related year take the nearer" do
      assert parse("4660. 2. 30.", :ko) == {:ok, date(4660, 2, 30)}
      assert parse("2023. 2. 30.", :ko) == {:ok, date(4660, 2, 30)}
    end
  end

  # TR35's `U` names "the year value" and, where it has no name for it, is
  # written as `y` writes it, so `y` and `U` write one number: the year's
  # place in the sixty-year cycle. ICU4C 78.3 writes the Chinese and Dangi
  # year that began in 2023 as 40 and the one that began in 2026 as 43
  # (`y` "40", `yy` "40", `yyyy` "0040", `ko`'s Dangi short date
  # "y. M. d." "40. 윤2. 29."), and their number with `u`. The calendar
  # answers the place, its `cyclic_year/3`, as it does for `U`.
  describe "the year of a calendar of cyclic years" do
    defp cyclic(year, month, day), do: Date.new!(year, month, day, CyclicLunisolar)

    defp parse_cyclic(text, locale, options \\ []) do
      reference = %{calendar: CyclicLunisolar, year: 4662, month: 6, day: 1}

      [locale: locale, calendar: CyclicLunisolar, reference_date: reference]
      |> Keyword.merge(options)
      |> then(&Localize.Date.parse(text, &1))
    end

    test "is written by y as its place in the cycle, and by u as its number" do
      for {pattern, expected} <- [
            {"y", "40"},
            {"yy", "40"},
            {"yyyy", "0040"},
            {"u", "4660"},
            {"r", "2023"},
            {"U", "gui-mao"}
          ] do
        assert Localize.Date.to_string(date(4660, 2, 29), format: pattern, locale: :en) ==
                 {:ok, expected},
               pattern
      end

      assert Localize.Date.to_string(date(4663, 5, 2), format: "y", locale: :en) == {:ok, "43"}
      assert Localize.Date.to_string(date(4625, 1, 1), format: "yy", locale: :en) == {:ok, "05"}

      assert Localize.Date.to_string(%{calendar: Lunisolar, year: 4660}, format: "y") ==
               {:ok, "40"}
    end

    # `ko.xml`: the Chinese calendar's short date is "y/M/d" and the Dangi
    # calendar's "y. M. d.".
    test "is written so in a locale's formats" do
      assert Localize.Date.to_string(date(4660, 2, 29), format: :short, locale: :ko) ==
               {:ok, "40/2/29"}

      assert Localize.Date.to_string(date(4660, 2, 29), format: "y. M. d.", locale: :ko) ==
               {:ok, "40. 2. 29."}
    end

    # The place recurs every sixty years, so it is the year of that place
    # nearest the reference year, as a cyclic name is.
    test "is read from its place as the year nearest the reference year" do
      assert parse("40. 2. 29.", :ko) == {:ok, date(4660, 2, 29)}
      assert parse("43. 5. 2.", :ko) == {:ok, date(4663, 5, 2)}
      assert parse("40/2/29", :ko) == {:ok, date(4660, 2, 29)}

      assert parse("40. 2. 29.", :ko, reference_date: %{@reference | year: 4700}) ==
               {:ok, date(4720, 2, 29)}

      assert parse("40. 2. 29.", :ko, as: :map) ==
               {:ok, %{calendar: Lunisolar, year: 4660, month: 2, day: 29}}
    end

    # A number beyond the cycle is the year as the calendar numbers it, and
    # a related year is read as it was.
    test "is read from a number beyond the cycle as that number" do
      assert parse("4660. 2. 29.", :ko) == {:ok, date(4660, 2, 29)}
      assert parse("2023. 2. 29.", :ko) == {:ok, date(4660, 2, 29)}
    end

    # A related year beside the place names the year, far from the reference
    # date as near it, and the place must be that year's: 4601 began in
    # 1964 (4601 less 2637) and is the 41st of its cycle (4601 less 76
    # cycles of 60).
    test "is the year a related year beside its place names" do
      assert Localize.Date.to_string(date(4601, 2, 29), format: "r y. M. d.", locale: :en) ==
               {:ok, "1964 41. 2. 29."}

      assert parse("1964 41. 2. 29.", :en, format: "r y. M. d.") == {:ok, date(4601, 2, 29)}
      assert {:error, _reason} = parse("1964 40. 2. 29.", :en, format: "r y. M. d.")
    end

    # Years of different cycles share their places and their names, and an
    # interval item writes a year as its place or its name: `en.xml` writes
    # the Chinese calendar's `yMd` across years as "M/d/y – M/d/y", so 16
    # June 2026 to 12 June 2086 was "5/2/43 – 5/2/43". The two are written in
    # full, each as the format writes a date alone (user, 2026-10-06), as
    # ICU4C 78.3, which holds the cycle as an era, writes them. `de`'s formats
    # name the year by its place or its name alone, and its dates are alike
    # there too.
    test "is written in full for both dates of an interval across cycles" do
      from = date(4663, 5, 2)
      to = date(4723, 5, 2)

      for {locale, format, expected} <- [
            {:en, :yMd, "5/2/2026 – 5/2/2086"},
            {:en, :yM, "5/2026 – 5/2086"},
            {:en, :yMMMd, "Mo5 2, 2026 – Mo5 2, 2086"},
            {:en, :yMMM, "Mo5 2026 – Mo5 2086"},
            {:en, :y, "2026(bing-wu) – 2086(bing-wu)"},
            {:en, :UMd, "5/2/bing-wu – 5/2/bing-wu"},
            {:en, :short, "5/2/2026 – 5/2/2086"},
            {:en, :medium, "Mo5 2, 2026 – Mo5 2, 2086"},
            {:de, :yMd, "2.5.43 – 2.5.43"},
            {:de, :yMMMd, "2. M05 bing-wu – 2. M05 bing-wu"},
            {:de, :medium, "02.05 bing-wu – 02.05 bing-wu"}
          ] do
        assert Localize.Interval.to_string(from, to, format: format, locale: locale) ==
                 {:ok, expected},
               "#{locale} #{format}"
      end

      # 2087 is another place of the next cycle: ICU4C writes
      # "5/2/2026 – 6/2/2086" for a month on in 2086.
      assert Localize.Interval.to_string(from, date(4723, 6, 2), format: :yMd, locale: :en) ==
               {:ok, "5/2/2026 – 6/2/2086"}
    end

    # Within one cycle a year's difference takes the item's pattern, as it
    # did, and as ICU4C writes it: "5/2/43 – 7/19/44" for 16 June 2026 to 20
    # August 2027.
    test "is written by the interval's pattern for two years of one cycle" do
      assert Localize.Interval.to_string(date(4663, 5, 2), date(4664, 7, 19),
               format: :yMd,
               locale: :en
             ) == {:ok, "5/2/43 – 7/19/44"}

      # One date is written with the skeleton's own format, which for
      # `yMMMd` is `yyyyMMMd`'s "MMM d, r" and not `UMMMd`'s "MMM d, U": TR35
      # puts a numeric and a text field further apart than two widths of a
      # number, and ICU4C 78.3 writes it so.
      assert Localize.Interval.to_string(date(4663, 5, 2), date(4663, 5, 2),
               format: :yMMMd,
               locale: :en
             ) == {:ok, "Mo5 2, 2026"}
    end

    # A format that writes no year writes none (user, 2026-10-06). Two dates
    # sixty years apart are alike in every field of such a pattern, and are
    # one date, TR35's step 4; two that differ in a month or a day are both
    # written with it around the fallback pattern. `en`'s Chinese `Md` is
    # "M/d" and its `MMMd` "MMM d". ICU4C 78.3, which holds the cycle as an
    # era, writes "5/2 – 5/2". A year was added and both written in full:
    # "5/2/2026 – 5/2/2086".
    test "is written without a year across cycles where the format has none" do
      from = date(4663, 5, 2)
      to = date(4723, 5, 2)

      written =
        for format <- [:Md, :MMMd, :d, :MMM] do
          {format, Localize.Interval.to_string(from, to, format: format, locale: :en)}
        end

      assert written == [
               Md: {:ok, "5/2"},
               MMMd: {:ok, "Mo5 2"},
               d: {:ok, "2"},
               MMM: {:ok, "Mo5"}
             ]

      assert Localize.Interval.to_string(from, date(4723, 6, 3), format: :Md, locale: :en) ==
               {:ok, "5/2 – 6/3"}
    end

    test "an interval written in full across cycles reads back" do
      from = date(4663, 5, 2)
      to = date(4723, 5, 2)

      for locale <- [:en, :zh, :ko, :he], format <- [:yMd, :yMMMd, :short, :medium] do
        {:ok, text} = Localize.Interval.to_string(from, to, format: format, locale: locale)

        if text =~ "2086" do
          assert Localize.Interval.parse(text,
                   locale: locale,
                   calendar: Lunisolar,
                   reference_date: @reference
                 ) == {:ok, Date.range(from, to)},
                 "#{locale} #{format} #{text}"
        end
      end
    end

    # A calendar may answer the place itself, from its `calendar_year/3`: it
    # is written and read the same.
    test "is the same where the calendar displays the place itself" do
      assert Localize.Date.to_string(cyclic(4660, 2, 29), format: "y", locale: :en) ==
               {:ok, "40"}

      assert Localize.Date.to_string(cyclic(4660, 2, 29), format: "u", locale: :en) ==
               {:ok, "4660"}

      assert parse_cyclic("40. 2. 29.", :ko) == {:ok, cyclic(4660, 2, 29)}
      assert parse_cyclic("4660. 2. 29.", :ko) == {:ok, cyclic(4660, 2, 29)}

      failures =
        for locale <- [:en, :zh, :ja, :ko, :vi, :de, :fr],
            format <- [:short, :medium, :long],
            date <- [cyclic(4660, 2, 30), cyclic(4660, 3, 1), cyclic(4661, 12, 30)],
            {:ok, text} = Localize.Date.to_string(date, format: format, locale: locale),
            parse_cyclic(text, locale) != {:ok, date} do
          {locale, format, date, text}
        end

      assert failures == []
    end

    # A lunisolar calendar that displays its years as years of an era, as
    # Calendrical's lunisolar Japanese calendar does, has the cycle's names
    # for `U` and the year of its era for `y`.
    test "is its year of era where the calendar displays one" do
      date = Date.new!(4662, 6, 1, LunisolarEras)

      assert Localize.Date.to_string(date, format: "y", locale: :en) == {:ok, "7"}
      assert Localize.Date.to_string(date, format: "U", locale: :en) == {:ok, "yi-si"}
    end

    # A calendar with no cycle of years is as it was.
    test "is no part of a calendar with no cycle" do
      assert Localize.Date.to_string(~D[2026-06-16], format: "y", locale: :en) == {:ok, "2026"}
      assert Localize.Date.to_string(~D[0040-06-16], format: "y", locale: :en) == {:ok, "40"}

      assert Localize.Date.to_string(Date.new!(2569, 6, 16, Offset), format: "y", locale: :en) ==
               {:ok, "2569"}
    end
  end

  # CLDR gives the Chinese and Dangi calendars one era and no name for it,
  # and TR35 does not say what `G` writes there. ICU holds the sixty-year
  # cycle as their era and writes its number, counted alike in both from the
  # cycle that began in 2637 BC, and Localize follows it (user, 2026-10-06).
  # ICU4C 78.3 writes "78" for `G`, `GGGG` and `GGGGG` on 16 June 2026 in
  # both calendars, "78 43" for "G y", "78 bing-wu" for "G U" and "78 2026"
  # for "G r"; "77 60" on 1 February 1984 and "78 1" the day after, the new
  # year; "78 60" and "79 1" either side of the new year of 2044; and
  # "٧٨ ٤٣" in `ar-EG`. The year that began in 1983 is 4620 as Calendrical
  # numbers it, and 2026's is 4663.
  describe "the era of a calendar of cyclic years" do
    test "is written as the number of the year's cycle, at every width" do
      for pattern <- ["G", "GG", "GGG", "GGGG", "GGGGG"] do
        assert Localize.Date.to_string(date(4663, 5, 2), format: pattern, locale: :en) ==
                 {:ok, "78"},
               pattern
      end

      for {year, expected} <- [
            {4663, "78 43"},
            {4620, "77 60"},
            {4621, "78 1"},
            {4680, "78 60"},
            {4681, "79 1"}
          ] do
        assert Localize.Date.to_string(date(year, 5, 2), format: "G y", locale: :en) ==
                 {:ok, expected},
               "#{year}"
      end

      assert Localize.Date.to_string(date(4663, 5, 2), format: "G U", locale: :en) ==
               {:ok, "78 bing-wu"}

      assert Localize.Date.to_string(date(4663, 5, 2), format: "G r", locale: :en) ==
               {:ok, "78 2026"}

      assert Localize.Date.to_string(%{calendar: Lunisolar, year: 4663}, format: "G y") ==
               {:ok, "78 43"}
    end

    test "is written in the numbering of the date's numbers" do
      assert Localize.Date.to_string(date(4663, 5, 2), format: "G y", locale: :"ar-EG") ==
               {:ok, "٧٨ ٤٣"}

      assert Localize.Date.to_string(date(4663, 5, 2), format: "G y", locale: "zh-u-nu-hanidec") ==
               {:ok, "七八 四三"}
    end

    # A place in the cycle alone is the year of that place nearest the
    # reference date, 4680 for the 60th from 4662. With its cycle it is one
    # year, however far from the reference date.
    test "is read with the year's place as the one year the two name" do
      assert parse("60-5-2", :en, format: "y-M-d") == {:ok, date(4680, 5, 2)}
      assert parse("77 60-5-2", :en, format: "G y-M-d") == {:ok, date(4620, 5, 2)}
      assert parse("79 1-5-2", :en, format: "G y-M-d") == {:ok, date(4681, 5, 2)}
      assert parse("70 43-5-2", :en, format: "G y-M-d") == {:ok, date(4183, 5, 2)}

      assert parse("78 bing-wu 5 2", :en, format: "G U M d") == {:ok, date(4663, 5, 2)}
      assert parse("77 bing-wu 5 2", :en, format: "G U M d") == {:ok, date(4603, 5, 2)}

      assert parse("٧٧ ٦٠-٥-٢", :"ar-EG", format: "G y-M-d") == {:ok, date(4620, 5, 2)}

      assert parse("七八 四三", "zh-u-nu-hanidec", format: "G y", as: :map) ==
               {:ok, %{calendar: Lunisolar, year: 4663}}

      assert parse("77 60", :en, format: "G y", as: :map) ==
               {:ok, %{calendar: Lunisolar, year: 4620}}
    end

    test "is read back as it is written, far from the reference date" do
      failures =
        for locale <- [:en, :zh, :ja, :ko, :vi, :de, :"ar-EG", :fa],
            pattern <- ["G y-M-d", "y G M d", "G U M d", "d M G y", "G r-M-d"],
            year <- [4183, 4601, 4620, 4621, 4660, 4663, 4680, 4681, 4723],
            written = date(year, 5, 2),
            {:ok, text} = Localize.Date.to_string(written, format: pattern, locale: locale),
            parse(text, locale, format: pattern) != {:ok, written} do
          {locale, pattern, year, text}
        end

      assert failures == []
    end

    # 2026 is of the 78th cycle.
    test "is refused beside a year of another cycle" do
      assert parse("78 2026-5-2", :en, format: "G r-M-d") == {:ok, date(4663, 5, 2)}
      assert {:error, %Localize.DateParseError{}} = parse("77 2026-5-2", :en, format: "G r-M-d")
    end

    # Calendrical's lunisolar Japanese calendar has the Chinese calendar's
    # months and cycle and the Japanese calendar's eras, which CLDR names.
    test "is its name where the calendar's eras have names" do
      date = Date.new!(4662, 6, 1, LunisolarEras)

      assert Localize.Date.to_string(date, format: "G y", locale: :en) == {:ok, "Reiwa 7"}
      assert Localize.Date.to_string(~D[2026-06-16], format: "G", locale: :en) == {:ok, "AD"}
    end
  end

  # TR35's Matching Skeletons gives a numeric and a text field "a larger
  # distance from each other" than two widths of one kind, and a year is a
  # number at every width of `y` where `U` is the year's name at every width
  # of its own. So a skeleton's `y` is nearer `yyyyMd`, the year in four
  # digits, than `UMd`, the cyclic year's name. The texts are ICU4C 78.3's
  # for the second day of the fifth month of the Chinese year that began in
  # 2026: a locale's `yyyy` format writes the related year (`en`'s "M/d/r"),
  # the year's place in its cycle (`de`'s "d.M.y") or its name (`ja`).
  describe "a skeleton with a year" do
    @skeleton_texts [
      {:en, :yM, "5/2026"},
      {:en, :yMd, "5/2/2026"},
      {:en, :yMMM, "Mo5 2026"},
      {:en, :yMMMd, "Mo5 2, 2026"},
      {:de, :yM, "5.43"},
      {:de, :yMd, "2.5.43"},
      {:de, :yMMM, "M05 bing-wu"},
      {:de, :yMMMd, "2. M05 bing-wu"},
      {:fr, :yM, "5/43"},
      {:fr, :yMd, "2/5/43"},
      {:fr, :yMMM, "5yuè bing-wu"},
      {:fr, :yMMMd, "2 5yuè bing-wu"},
      {:ko, :yM, "2026. 5."},
      {:ko, :yMd, "2026. 5. 2."},
      {:ko, :yMMM, "2026년(병오년) 5월"},
      {:ko, :yMMMd, "2026년 5월 2일"},
      {:vi, :yM, "5/2026"},
      {:vi, :yMd, "02-05-2026"},
      {:vi, :yMMM, "tháng 5 năm 2026"},
      {:vi, :yMMMd, "ngày 2 tháng 5 năm 2026"},
      {:zh, :yM, "2026丙午年五月"},
      {:zh, :yMd, "2026年五月2"},
      {:zh, :yMMM, "2026丙午年五月"},
      {:zh, :yMMMd, "2026年五月2"},
      {:ja, :yM, "丙午年5月"},
      {:ja, :yMd, "丙午-5-2"},
      {:ja, :yMMM, "丙午年五月"},
      {:ja, :yMMMd, "丙午年五月2日"}
    ]

    test "takes the format of a numbered year before the format of the year's name" do
      for {locale, skeleton, expected} <- @skeleton_texts do
        assert Localize.Date.to_string(date(4663, 5, 2), format: skeleton, locale: locale) ==
                 {:ok, expected},
               "#{locale} #{skeleton}"
      end
    end

    # The year's name is still what `U` asks for: `en.xml`'s `UMd` is
    # "M/d/U", root's "U MM-d" and `ko.xml`'s "U년 M. d.".
    test "takes the format of the year's name where the name is asked for" do
      for {locale, expected} <- [
            en: "5/2/bing-wu",
            de: "bing-wu 05-2",
            ko: "병오년 5. 2.",
            vi: "2/5 năm Bính Ngọ"
          ] do
        assert Localize.Date.to_string(date(4663, 5, 2), format: :UMd, locale: locale) ==
                 {:ok, expected},
               "#{locale}"
      end
    end

    # The calendar's formats with an era name their month: `en.xml`'s
    # `GyMMMd` is "MMM d, r" and its `GyMMMMd` "MMMM d, r(U)". A numbered
    # month beside an era takes the abbreviated month's, as CLDR's
    # conformance data resolves `GyMd` ("MMM d, r" in `en`, "r년 MMM d일" in
    # `ko`, "r年MMMd" in `zh`, "d. MMM U" in `de`) and ICU4C writes it; it
    # took the wide month's, "Fifth Month 2, 2026(bing-wu)". `ja.xml` has a
    # `GyMd` of its own, "U-M-d".
    test "with an era and a numbered month takes the abbreviated month's format" do
      for {locale, expected} <- [
            en: "Mo5 2, 2026",
            ko: "2026년 5월 2일",
            zh: "2026年五月2",
            de: "2. M05 bing-wu",
            fr: "2 5yuè bing-wu",
            ja: "丙午-5-2"
          ] do
        assert Localize.Date.to_string(date(4663, 5, 2), format: :GyMd, locale: locale) ==
                 {:ok, expected},
               "#{locale}"
      end

      assert Localize.Date.to_string(date(4663, 5, 2), format: :GyM, locale: :en) ==
               {:ok, "Mo5 2026"}

      assert Localize.Date.to_string(date(4663, 5, 2), format: :GyMMMMd, locale: :en) ==
               {:ok, "Fifth Month 2, 2026(bing-wu)"}
    end

    test "is read back with that skeleton" do
      for {locale, skeleton, text} <- @skeleton_texts do
        if skeleton in [:yMd, :yMMMd] do
          assert parse(text, locale, format: skeleton) == {:ok, date(4663, 5, 2)},
                 "#{locale} #{skeleton} #{text}"
        else
          assert parse(text, locale, format: skeleton, as: :map) ==
                   {:ok, %{calendar: Lunisolar, year: 4663, month: 5}},
                 "#{locale} #{skeleton} #{text}"
        end
      end
    end

    # A calendar whose years have no names has no format of a year's name
    # to take, and `yyyy` is a number of four digits beside `y`'s: `en.xml`'s
    # Gregorian `yMd` is "M/d/y".
    test "is as it was in a calendar with no cycle of years" do
      assert Localize.Date.to_string(~D[2026-06-16], format: :yMd, locale: :en) ==
               {:ok, "6/16/2026"}

      assert Localize.Date.to_string(~D[0926-06-16], format: :yyyyMd, locale: :en) ==
               {:ok, "6/16/0926"}
    end
  end

  describe "every date the formatter writes" do
    test "parses back in each locale's standard formats" do
      locales = [:en, :zh, :"zh-Hant", :ja, :ko, :vi, :de, :fr]

      dates =
        for {year, month, day} <- [
              {4660, 2, 30},
              {4660, 3, 1},
              {4660, 3, 21},
              {4660, 4, 1},
              {4661, 12, 30}
            ],
            do: date(year, month, day)

      failures =
        for locale <- locales,
            format <- [:short, :medium, :long],
            date <- dates,
            {:ok, text} = Localize.Date.to_string(date, format: format, locale: locale),
            parse(text, locale) != {:ok, date} do
          {locale, format, date, text}
        end

      assert failures == []
    end
  end

  # A calendar's own formats come before ISO 8601 (user, 2026-10-04), any of
  # them, read as leniently as they are read anywhere. CLDR's root short
  # date of the Chinese calendar is `r-MM-dd`, which `he` and `sw` take, and
  # `lt`'s is `y-MM-dd` (`common/main/root.xml`, `lt.xml`): each writes a
  # date as ISO 8601 writes one, and ISO 8601 read its text as a Gregorian
  # date. The Chinese year 4660 began in 2023, its related year, and its
  # eleventh month is its twelfth, after the leap second month.
  # af.xml's generic calendar writes `GyMd` as "M-d-y G" and `yyyyMd` as
  # "d/M/y GGGGG". Each reads "10-7-2569 BE", the second taking a hyphen
  # for its slash, and TR35's parsing matches "fields and literals against
  # those in the format string": the format whose own separators the text
  # has is the one that wrote it. It was the tenth of July, read by the
  # first of the two to be tried.
  describe "a date two of a locale's formats read" do
    test "is read by the format whose own separators it has" do
      date = Date.new!(2569, 10, 7, Offset)

      assert Localize.Date.to_string(date, locale: :af, format: :GyMd) == {:ok, "10-7-2569 BE"}
      assert Localize.Date.to_string(date, locale: :af, format: :yyyyMd) == {:ok, "7/10/2569 BE"}

      for text <- ["10-7-2569 BE", "7/10/2569 BE"] do
        assert Localize.Date.parse(text, locale: :af, calendar: Offset, reference_date: date) ==
                 {:ok, date},
               text
      end
    end

    # `en_CA.xml`'s `Md` is "MM-dd" with the variant "d/M". The formatter
    # writes a variant only when it is asked to, so one is never moved
    # ahead of the default that reads the text.
    test "is still the default's where the other is its variant" do
      assert Localize.Date.parse("5/3", locale: :"en-CA", as: :map) ==
               {:ok, %{calendar: Calendar.ISO, month: 5, day: 3}}

      assert Localize.Date.parse("05-03", locale: :"en-CA", as: :map) ==
               {:ok, %{calendar: Calendar.ISO, month: 5, day: 3}}
    end
  end

  describe "a date ISO 8601 also reads" do
    test "is the calendar's own date where a format of the calendar writes it so" do
      eleventh = date(4660, 12, 22)

      assert Localize.Date.to_string(eleventh, format: :short, locale: :he) ==
               {:ok, "2023-11-22"}

      assert parse("2023-11-22", :he) == {:ok, eleventh}
      assert parse("2023-11-22", :sw) == {:ok, eleventh}

      # `lt`'s `y` is the year's place in the cycle, 40, as ICU4C writes it; a
      # year written by its number is still the calendar's own, not ISO
      # 8601's Gregorian year 4660.
      assert Localize.Date.to_string(eleventh, format: :short, locale: :lt) ==
               {:ok, "40-11-22"}

      assert parse("40-11-22", :lt) == {:ok, eleventh}
      assert parse("4660-11-22", :lt) == {:ok, eleventh}

      assert parse("2023-11-22", :he, as: :map) ==
               {:ok, %{calendar: Lunisolar, year: 4660, month: 12, day: 22}}
    end

    test "parses back in every standard format of the locales that write it so" do
      dates =
        for {year, month, day} <- [{4660, 2, 30}, {4660, 3, 11}, {4660, 12, 22}, {4661, 1, 1}],
            do: date(year, month, day)

      failures =
        for locale <- [:he, :sw, :lt, :id, :af],
            format <- [:short, :medium, :long],
            date <- dates,
            {:ok, text} = Localize.Date.to_string(date, format: format, locale: locale),
            parse(text, locale) != {:ok, date} do
          {locale, format, date, text}
        end

      assert failures == []
    end

    # Any of the calendar's formats reads the text, as leniently as the
    # parser reads it anywhere (user, 2026-10-04: "Use the broader rule").
    # CLDR's lenient date scope takes a hyphen, a period and a slash for one
    # another (`root.xml`, `parseLenients`), so `ko`'s short date of the
    # Chinese calendar, "y/M/d" (`ko.xml`), reads a year, a month and a day
    # between hyphens as the calendar's own year, and `fa`'s of the Persian
    # calendar, "y/M/d" (`fa.xml`), the Persian year 1402.
    test "is the calendar's own date where a format of the calendar reads it leniently" do
      assert parse("4660-11-22", :ko) == {:ok, date(4660, 12, 22)}

      persian = [locale: :fa, calendar: Bounded, reference_date: Date.new!(1405, 3, 1, Bounded)]

      assert Localize.Date.parse("1402-09-01", persian) == {:ok, Date.new!(1402, 9, 1, Bounded)}
    end

    # A date and a time joined by a space is ISO 8601's too, and the
    # calendar's own for the same reason, an offset or a `Z` after the time
    # with it. ISO 8601's `T` is in no locale's pattern, so text with one is
    # not the calendar's.
    test "with a time is the calendar's own date and time" do
      options = [locale: :he, calendar: Lunisolar, reference_date: @reference]

      assert {:ok,
              %NaiveDateTime{
                calendar: Lunisolar,
                year: 4660,
                month: 12,
                day: 22,
                hour: 14,
                minute: 30,
                second: 45
              }} = Localize.DateTime.parse("2023-11-22 14:30:45", options)
    end

    # `en` writes no Buddhist date that reads a year, a month and a day
    # between hyphens, so the text there is ISO 8601's: a Gregorian date,
    # taken into the calendar, 543 years on. `ksh`'s `yMd` is "y-MM-dd"
    # (`common/main/ksh.xml`), so the same shape there is the calendar's own
    # year, with its offset where it has one.
    test "is ISO 8601's where no format of the calendar reads it" do
      assert Localize.Date.parse("2023-11-22", locale: :en, calendar: Offset) ==
               {:ok, Date.new!(2566, 11, 22, Offset)}

      assert Localize.Date.parse("2566-11-22", locale: :ksh, calendar: Offset) ==
               {:ok, Date.new!(2566, 11, 22, Offset)}

      assert {:ok, %NaiveDateTime{calendar: Offset, year: 2566, month: 11, day: 22, hour: 14}} =
               Localize.DateTime.parse("2566-11-22 14:30:45", locale: :ksh, calendar: Offset)

      assert {:ok, %DateTime{calendar: Offset, year: 2566, month: 11, day: 22, utc_offset: 7200}} =
               Localize.DateTime.parse("2566-11-22 14:30:45+02:00",
                 locale: :ksh,
                 calendar: Offset
               )

      assert {:ok, %NaiveDateTime{calendar: Offset, year: 3109, month: 11, day: 22, hour: 14}} =
               Localize.DateTime.parse("2566-11-22T14:30:45", locale: :ksh, calendar: Offset)
    end

    # ISO 8601 is `Calendar.ISO`'s own notation, so it comes first there, in
    # every locale. `ug`'s and `kk-Arab`'s `yMd` is "y-d-M"
    # (`common/main/ug.xml`, `kk_Arab.xml`), which would read the same text
    # as 10 November.
    test "is ISO 8601's in Calendar.ISO, in every locale" do
      for locale <- [:sv, :ug, :"kk-Arab", :ko] do
        assert Localize.Date.parse("2024-10-11", locale: locale) == {:ok, ~D[2024-10-11]},
               inspect(locale)
      end
    end

    # ISO 8601's other forms are in no calendar's formats: a date without
    # separators, a day of the year and a week date stay ISO 8601's.
    test "is ISO 8601's in its basic, ordinal and week forms" do
      november_22 = Date.new!(2566, 11, 22, Offset)

      for text <- ["20231122", "2023-326", "2023-W47-3"] do
        assert Localize.Date.parse(text, locale: :ksh, calendar: Offset) == {:ok, november_22},
               text
      end
    end
  end

  # ICU4C 78.3's `yMMMd` and `yMd` intervals from Gregorian 2023-04-01.
  describe "ICU4C's lunisolar intervals" do
    test "parse with the calendar's interval patterns" do
      within_month = Date.range(date(4660, 3, 11), date(4660, 3, 20))
      across_months = Date.range(date(4660, 3, 11), date(4660, 4, 1))

      for {text, locale, range} <- [
            {"Mo2bis 11 – 20, gui-mao", :en, within_month},
            {"Mo2bis 11 – Mo3 1, gui-mao", :en, across_months},
            {"2023年闰二月11至20", :zh, within_month},
            {"2023年闰二月11至三月1", :zh, across_months},
            {"2023-闰2-11至2023-闰2-20", :zh, within_month}
          ] do
        assert Localize.Interval.parse(text,
                 locale: locale,
                 calendar: Lunisolar,
                 reference_date: @reference
               ) == {:ok, range},
               "#{locale} #{inspect(text)}"
      end
    end

    # CLDR keys the Chinese calendar's `yMd` interval by `y`, "M/d/y – M/d/y"
    # in `en` and "y-MM-dd – y-MM-dd" in root (`common/main/en.xml`,
    # `root.xml`), and the formatter writes it with the year the standard
    # short date writes, the related year (`M/d/r`, `r-MM-dd`): 2023 for two
    # days of 4660. So an interval's year is read as the related year or as
    # the calendar's own, whichever is nearer the reference year, as a single
    # date's is; it was read as the Chinese year 2023.
    test "read a year as the related year or the calendar's own, whichever is nearer" do
      range = Date.range(date(4660, 12, 8), date(4660, 12, 18))
      options = [calendar: Lunisolar, reference_date: @reference]

      for {text, locale} <- [
            {"11/8/2023 – 11/18/2023", :en},
            {"11/8/4660 – 11/18/4660", :en},
            {"2023-11-08 – 2023-11-18", :he},
            {"4660-11-08 – 4660-11-18", :he}
          ] do
        assert Localize.Interval.parse(text, [locale: locale] ++ options) == {:ok, range},
               "#{locale} #{inspect(text)}"
      end

      assert Localize.Interval.parse("11/8/2023 – 11/18/2023", [locale: :en, as: :map] ++ options) ==
               {:ok,
                {%{calendar: Lunisolar, year: 4660, month: 12, day: 8},
                 %{calendar: Lunisolar, year: 4660, month: 12, day: 18}}}
    end

    test "parse back as the formatter writes them at the short format and with a skeleton" do
      range = Date.range(date(4660, 12, 8), date(4660, 12, 18))

      failures =
        for locale <- [:en, :he, :sw, :lt, :zh, :ko],
            format <- [:short, :yMd],
            {:ok, text} =
              Localize.Interval.to_string(range.first, range.last, locale: locale, format: format),
            Localize.Interval.parse(text,
              locale: locale,
              calendar: Lunisolar,
              reference_date: @reference
            ) != {:ok, range} do
          {locale, format, text}
        end

      assert failures == []
    end

    # A calendar whose formats write no related year reads an interval's
    # year as its own: 2566 of a calendar 543 years on is not the related
    # year of 3109.
    test "read a year as the calendar's own where its formats write no related year" do
      assert Localize.Interval.parse("1/4/2566 – 10/4/2566 BE", locale: :en, calendar: Offset) ==
               {:ok, Date.range(Date.new!(2566, 1, 4, Offset), Date.new!(2566, 10, 4, Offset))}
    end
  end

  # `en_CA.xml` gives the Chinese calendar a variant of its short date,
  # "d/M/r", beside the "M/d/r" it keeps from `en.xml`, and its `yMd`
  # interval item a variant, "d/M/y – d/M/y", beside "y-MM-dd – y-MM-dd".
  # The formatter writes the standard and the default form unless
  # `prefer: :variant` asks for the other, so those are read first. The
  # variant was read first and took the day for the month, and an item that
  # is two patterns was not read at all.
  describe "a format with a variant" do
    test "is read as the standard pattern writes it" do
      assert Localize.Date.to_string(date(4663, 5, 2), format: :short, locale: :"en-CA") ==
               {:ok, "5/2/2026"}

      assert parse("5/2/2026", :"en-CA") == {:ok, date(4663, 5, 2)}
      assert parse("5/2/2026", :"en-CA", format: :short) == {:ok, date(4663, 5, 2)}
    end

    test "is read as the variant writes it where the standard pattern reads no date" do
      assert Localize.Date.to_string(date(4663, 5, 30),
               format: :short,
               locale: :"en-CA",
               prefer: :variant
             ) == {:ok, "30/5/2026"}

      assert parse("30/5/2026", :"en-CA") == {:ok, date(4663, 5, 30)}
    end

    test "is read as the variant writes it where the variant is asked for" do
      assert parse("2/5/2026", :"en-CA", format: :short, prefer: :variant) ==
               {:ok, date(4663, 5, 2)}
    end

    # ICU4C 78.3 writes the `yMd` interval of the second to the sixth day of
    # the fifth month as "43-05-02 – 43-05-06", the year its place in the
    # cycle. It was read as two dates, each by its related year.
    test "is read as an interval's default pattern writes it" do
      range = Date.range(date(4663, 5, 2), date(4663, 5, 6))

      assert Localize.Interval.to_string(range.first, range.last, locale: :"en-CA", format: :yMd) ==
               {:ok, "43-05-02 – 43-05-06"}

      for format <- [:yMd, :short] do
        {:ok, text} =
          Localize.Interval.to_string(range.first, range.last, locale: :"en-CA", format: format)

        assert Localize.Interval.parse(text,
                 locale: :"en-CA",
                 calendar: Lunisolar,
                 reference_date: @reference
               ) == {:ok, range},
               "#{format} #{inspect(text)}"
      end
    end
  end

  describe "the reference year is the reference date's year in the calendar" do
    test "a date without a year is in the calendar's year" do
      assert Localize.Date.parse("Mar 15",
               locale: :en,
               calendar: Offset,
               reference_date: ~D[2026-06-01]
             ) == {:ok, Date.new!(2569, 3, 15, Offset)}
    end

    test "a two-digit year is read in the century around it" do
      assert Localize.Date.parse("15/3/69",
               locale: :th,
               calendar: Offset,
               reference_date: ~D[2026-06-01]
             ) == {:ok, Date.new!(2569, 3, 15, Offset)}
    end

    # `de` writes a Buddhist short date "dd.MM.yy G". ICU4C 78.3 reads
    # "01.04.66 BE" as 2566 BE: `yy` is the year's two low-order digits,
    # read in the window whatever era is written beside it.
    test "a two-digit year is read in the century around it beside its era" do
      assert Localize.Date.parse("01.04.66 BE",
               locale: :de,
               calendar: Offset,
               reference_date: ~D[2026-06-01]
             ) == {:ok, Date.new!(2566, 4, 1, Offset)}

      assert Localize.DateTime.parse("01.04.66 BE, 10:05",
               locale: :de,
               calendar: Offset,
               reference_date: ~D[2026-06-01]
             ) ==
               {:ok,
                %NaiveDateTime{
                  calendar: Offset,
                  year: 2566,
                  month: 4,
                  day: 1,
                  hour: 10,
                  minute: 5,
                  second: 0,
                  microsecond: {0, 0}
                }}
    end
  end

  # ICU4C 78.3 writes Ethiopic year -5 as "Hedar 15, 5495 AA".
  describe "an era that begins before the calendar's first year" do
    test "counts its years from the calendar year it began in" do
      date = Date.new!(-5, 3, 15, Ethiopic)

      assert Localize.Date.to_string(date, format: "MMM d, y G", locale: :en) ==
               {:ok, "Hedar 15, 5495 AA"}

      assert Localize.Date.parse("Hedar 15, 5495 AA", locale: :en, calendar: Ethiopic) ==
               {:ok, date}
    end
  end

  # A year named by its place in the sixty-year cycle beside an era is the
  # year of that place in the era. 2000 and 1940 are both geng-chen years
  # (庚辰, the seventeenth of the cycle), the first in Heisei and the second in
  # Shōwa; Shōwa ran for 63 years, so it has two bing-yin years (丙寅, the
  # third), 1926 and 1986, and Heisei, 1989 to 2018, has no bing-wu year (丙午,
  # the forty-third: 1966 and 2026). en.xml names the eras "Shōwa", "Heisei"
  # and "Reiwa" and the years "geng-chen", "bing-yin" and "bing-wu". The era
  # was not asked: the year was the one of its name nearest the reference
  # date, 2000 for every geng-chen read in 2026.
  describe "a cyclic year's name beside an era" do
    defp imperial(text, reference_year, options \\ []) do
      defaults = [
        locale: :en,
        calendar: ImperialLunisolar,
        format: "G U M d",
        reference_date: Date.new!(reference_year + 2637, 5, 2, ImperialLunisolar)
      ]

      Localize.Date.parse(text, Keyword.merge(defaults, options))
    end

    test "is the year of that name in the era" do
      for {gregorian, text} <- [
            {2000, "Heisei geng-chen 4 29"},
            {1940, "Shōwa geng-chen 4 29"},
            {2060, "Reiwa geng-chen 4 29"}
          ] do
        date = Date.new!(gregorian + 2637, 4, 29, ImperialLunisolar)

        assert Localize.Date.to_string(date, locale: :en, format: "G U M d") == {:ok, text}

        for reference <- [2026, 1950, 2090] do
          assert imperial(text, reference) == {:ok, date}, "#{text} read in #{reference}"
        end
      end
    end

    test "is the nearer of an era's two years of the name" do
      assert imperial("Shōwa bing-yin 4 29", 2026) ==
               {:ok, Date.new!(1986 + 2637, 4, 29, ImperialLunisolar)}

      assert imperial("Shōwa bing-yin 4 29", 1930) ==
               {:ok, Date.new!(1926 + 2637, 4, 29, ImperialLunisolar)}
    end

    test "is no year where the era has none of the name" do
      assert {:error, %Localize.DateParseError{}} = imperial("Heisei bing-wu 4 29", 2026)
    end

    test "without an era is the year of the name nearest the reference date" do
      options = [format: "U M d"]

      assert imperial("geng-chen 4 29", 2026, options) ==
               {:ok, Date.new!(2000 + 2637, 4, 29, ImperialLunisolar)}

      assert imperial("geng-chen 4 29", 1950, options) ==
               {:ok, Date.new!(1940 + 2637, 4, 29, ImperialLunisolar)}
    end

    test "agrees with a year of the era written beside it" do
      assert imperial("Heisei 12 geng-chen 4 29", 2026, format: "G y U M d") ==
               {:ok, Date.new!(2000 + 2637, 4, 29, ImperialLunisolar)}

      assert {:error, %Localize.DateParseError{}} =
               imperial("Heisei 13 geng-chen 4 29", 2026, format: "G y U M d")
    end
  end

  # `r` is the Gregorian year a calendar's year begins in (TR35), and a
  # calendar whose year is not the solar year's length does not keep its
  # year a fixed number from it. Calendrical's `Islamic.Civil` has 16 June
  # 1700 as 28 Dhuʻl-Hijjah 1111, a year that began in 1699, 16 June 1900 as
  # 17 Safar 1318, which began in 1900, and 16 June 2026 as 30 Dhuʻl-Hijjah
  # 1447, which began in 2025: 336 Islamic years in 326. The year was taken
  # as far from the reference date's as its related year is from the
  # reference date's, which is the year 1121 for 1699 read in 2026, a year
  # that began in 1709, and no date.
  describe "a related year in a calendar out of step with the Gregorian" do
    defp islamic(year, month, day), do: Date.new!(year, month, day, TabularIslamic)

    test "the stand-in is the tabular Islamic calendar" do
      assert Date.convert(~D[1700-06-16], TabularIslamic) == {:ok, islamic(1111, 12, 28)}
      assert Date.convert(~D[1900-06-16], TabularIslamic) == {:ok, islamic(1318, 2, 17)}
      assert Date.convert(~D[2026-06-16], TabularIslamic) == {:ok, islamic(1447, 12, 30)}
      assert Date.convert(islamic(1448, 1, 1), Calendar.ISO) == {:ok, ~D[2026-06-17]}
    end

    test "is read as the year that begins in it, however far from the reference date" do
      for {date, text} <- [
            {islamic(1111, 12, 28), "AH 1699-12-28"},
            {islamic(1318, 2, 17), "AH 1900-2-17"},
            {islamic(1447, 12, 30), "AH 2025-12-30"}
          ] do
        assert Localize.Date.to_string(date, locale: :en, format: "G r-M-d") == {:ok, text}

        for reference <- [islamic(1448, 1, 1), islamic(1111, 1, 1), islamic(700, 1, 1)],
            format <- ["G r-M-d", "r-M-d"] do
          text = if format == "r-M-d", do: String.replace_prefix(text, "AH ", ""), else: text

          assert Localize.Date.parse(text,
                   locale: :en,
                   calendar: TabularIslamic,
                   format: format,
                   reference_date: reference
                 ) == {:ok, date},
                 "#{text} read on #{inspect(reference)}"
        end
      end
    end

    # The Islamic years 1429 and 1430 both began in 2008, on 10 January and
    # on 29 December, so "2008" is either, and the nearer the reference
    # date is meant.
    test "is the nearer of two years that begin in one Gregorian year" do
      assert TabularIslamic.related_gregorian_year(1429, 1, 1) == 2008
      assert TabularIslamic.related_gregorian_year(1430, 1, 1) == 2008

      options = [locale: :en, calendar: TabularIslamic, format: "G r-M-d"]

      assert Localize.Date.parse("AH 2008-6-15", [reference_date: islamic(1448, 1, 1)] ++ options) ==
               {:ok, islamic(1430, 6, 15)}

      assert Localize.Date.parse("AH 2008-6-15", [reference_date: islamic(1400, 1, 1)] ++ options) ==
               {:ok, islamic(1429, 6, 15)}
    end

    test "must agree with a year written beside it" do
      options = [
        locale: :en,
        calendar: TabularIslamic,
        format: "G y (r) M d",
        reference_date: islamic(1448, 1, 1)
      ]

      assert Localize.Date.parse("AH 1111 (1699) 12 28", options) == {:ok, islamic(1111, 12, 28)}

      assert {:error, %Localize.DateParseError{}} =
               Localize.Date.parse("AH 1111 (1700) 12 28", options)
    end
  end

  describe "a calendar that writes its years as years of an era" do
    test "names its eras from its era calendar" do
      date = Date.new!(1381, 2, 16, EraYears)

      assert Localize.Calendar.localize(date, :era, locale: :ja) == {:ok, "令和"}
      assert Localize.Date.to_string(date, format: "y G", locale: :en) == {:ok, "7 Reiwa"}
    end

    test "reads the era names of its era calendar" do
      for date <- [Date.new!(2025, 3, 15, JapaneseEras), Date.new!(1989, 1, 9, JapaneseEras)] do
        {:ok, text} = Localize.Date.to_string(date, format: :GyMMMd, locale: :en)

        assert Localize.Date.parse(text, locale: :en, calendar: JapaneseEras) == {:ok, date},
               inspect(text)
      end
    end

    # ICU reads a Japanese year written without its era as a year of the
    # current era.
    test "reads a year written without its era as a year of the reference date's era" do
      date = Date.new!(1381, 2, 16, EraYears)
      {:ok, text} = Localize.Date.to_string(date, format: :short, locale: :de)

      assert text == "16.02.07"

      assert Localize.Date.parse(text,
               locale: :de,
               calendar: EraYears,
               reference_date: ~D[2026-06-01]
             ) == {:ok, date}
    end
  end
end
