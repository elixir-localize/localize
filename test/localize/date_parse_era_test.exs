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
