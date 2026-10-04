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
  # "y. M. d." "40. 윤2. 29."). The calendar answers its displayed year, and
  # a calendar that answers the place in the cycle is written and read so.
  describe "a calendar that displays a year as its place in the cycle" do
    defp cyclic(year, month, day), do: Date.new!(year, month, day, CyclicLunisolar)

    defp parse_cyclic(text, locale, options \\ []) do
      reference = %{calendar: CyclicLunisolar, year: 4662, month: 6, day: 1}

      [locale: locale, calendar: CyclicLunisolar, reference_date: reference]
      |> Keyword.merge(options)
      |> then(&Localize.Date.parse(text, &1))
    end

    test "writes y as that place, and u as the year's number" do
      date = cyclic(4660, 2, 29)

      for {pattern, expected} <- [
            {"y", "40"},
            {"yy", "40"},
            {"yyyy", "0040"},
            {"u", "4660"},
            {"r", "2023"},
            {"U", "gui-mao"}
          ] do
        assert Localize.Date.to_string(date, format: pattern, locale: :en) == {:ok, expected},
               pattern
      end

      assert Localize.Date.to_string(cyclic(4663, 5, 2), format: "y", locale: :en) == {:ok, "43"}
      assert Localize.Date.to_string(cyclic(4625, 1, 1), format: "yy", locale: :en) == {:ok, "05"}
    end

    # `ko.xml`: the Chinese calendar's short date is "y/M/d" and the Dangi
    # calendar's "y. M. d.".
    test "writes a locale's formats with it" do
      assert Localize.Date.to_string(cyclic(4660, 2, 29), format: :short, locale: :ko) ==
               {:ok, "40/2/29"}

      assert Localize.Date.to_string(cyclic(4660, 2, 29), format: "y. M. d.", locale: :ko) ==
               {:ok, "40. 2. 29."}
    end

    # The place recurs every sixty years, so it is the year of that place
    # nearest the reference year, as a cyclic name is.
    test "reads y as the year of that place nearest the reference year" do
      assert parse_cyclic("40. 2. 29.", :ko) == {:ok, cyclic(4660, 2, 29)}
      assert parse_cyclic("43. 5. 2.", :ko) == {:ok, cyclic(4663, 5, 2)}
      assert parse_cyclic("40/2/29", :ko) == {:ok, cyclic(4660, 2, 29)}

      later = %{calendar: CyclicLunisolar, year: 4700, month: 1, day: 1}
      assert parse_cyclic("40. 2. 29.", :ko, reference_date: later) == {:ok, cyclic(4720, 2, 29)}

      assert parse_cyclic("40. 2. 29.", :ko, as: :map) ==
               {:ok, %{calendar: CyclicLunisolar, year: 4660, month: 2, day: 29}}
    end

    # A number beyond the cycle is the year as the calendar numbers it, and
    # a related year is read as it is in any lunisolar calendar.
    test "reads a number beyond the cycle as the year's number" do
      assert parse_cyclic("4660. 2. 29.", :ko) == {:ok, cyclic(4660, 2, 29)}
      assert parse_cyclic("2023. 2. 29.", :ko) == {:ok, cyclic(4660, 2, 29)}
    end

    test "reads back every date it writes in a locale's standard formats" do
      dates = [cyclic(4660, 2, 30), cyclic(4660, 3, 1), cyclic(4660, 4, 1), cyclic(4661, 12, 30)]

      failures =
        for locale <- [:en, :zh, :ja, :ko, :vi, :de, :fr],
            format <- [:short, :medium, :long],
            date <- dates,
            {:ok, text} = Localize.Date.to_string(date, format: format, locale: locale),
            parse_cyclic(text, locale) != {:ok, date} do
          {locale, format, date, text}
        end

      assert failures == []
    end

    # A calendar that displays a year as its number is read as it was.
    test "leaves a calendar that displays its year's number as it was" do
      assert parse("4660. 2. 30.", :ko) == {:ok, date(4660, 2, 30)}
      assert parse("40. 2. 30.", :ko) != {:ok, date(4660, 2, 30)}
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
  describe "a date ISO 8601 also reads" do
    test "is the calendar's own date where a format of the calendar writes it so" do
      eleventh = date(4660, 12, 22)

      assert Localize.Date.to_string(eleventh, format: :short, locale: :he) ==
               {:ok, "2023-11-22"}

      assert parse("2023-11-22", :he) == {:ok, eleventh}
      assert parse("2023-11-22", :sw) == {:ok, eleventh}

      assert Localize.Date.to_string(eleventh, format: :short, locale: :lt) ==
               {:ok, "4660-11-22"}

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
