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
