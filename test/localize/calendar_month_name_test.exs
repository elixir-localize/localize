defmodule Localize.CalendarMonthNameTest do
  use ExUnit.Case, async: true

  # A calendar whose month names do not follow a month's position in its
  # year names its months through `month_of_year/3`. Localize does not
  # depend on Calendrical, so these stand-ins answer as Calendrical's Hebrew
  # and Chinese calendars do.
  defmodule Hebrew do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :hebrew
    def cardinal_month(month), do: month
    def year_of_era(year, _month, _day), do: {year, 0}

    def leap_year?(year), do: Integer.mod(7 * year + 1, 19) < 7
    def months_in_year(year), do: if(leap_year?(year), do: 13, else: 12)
    def days_in_month(_year, _month), do: 29
    def valid_date?(year, month, day), do: month in 1..months_in_year(year) and day in 1..29

    # CLDR numbers the months of an ordinary year from Adar on one more than
    # their position, and names month 7 "Adar II" in a leap year.
    def month_of_year(year, month, _day) do
      cond do
        leap_year?(year) and month == 7 -> {7, :leap}
        leap_year?(year) or month < 6 -> month
        true -> month + 1
      end
    end
  end

  defmodule Chinese do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :chinese
    def cardinal_month(month), do: month

    # Year 4660 has a leap second month, at position 3.
    def month_of_year(4660, 3, _day), do: {2, :leap}
    def month_of_year(4660, month, _day) when month > 3, do: month - 1
    def month_of_year(_year, month, _day), do: month

    # Year 4660 began in Gregorian 2023.
    def related_gregorian_year(year, _month, _day), do: year - 2637
  end

  defmodule Unanswering do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def cldr_calendar_type, do: :gregorian
    def cardinal_month(month), do: month
    def month_of_year(_year, _month, _day), do: :not_a_month
  end

  defp month_name(year, month, calendar, options \\ []) do
    date = %{year: year, month: month, day: 1, calendar: calendar}

    case Localize.Calendar.localize(date, :month, Keyword.merge([locale: :en], options)) do
      {:ok, name} -> name
      {:error, _reason} = error -> error
    end
  end

  describe "a Hebrew month" do
    test "an ordinary year's months are named by the calendar, not their position" do
      # 5786 is an ordinary year: Adar is its 6th month and Elul its 12th
      assert Enum.map(1..12, &month_name(5786, &1, Hebrew)) ==
               ~w[Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyar Sivan Tamuz Av Elul]
    end

    test "a leap year's Adar I and Adar II" do
      # 5787 is a leap year: Adar I is its 6th month and Adar II its 7th
      assert Enum.map(1..13, &month_name(5787, &1, Hebrew)) ==
               ["Tishri", "Heshvan", "Kislev", "Tevet", "Shevat", "Adar I", "Adar II"] ++
                 ~w[Nisan Iyar Sivan Tamuz Av Elul]
    end

    test "abbreviated and stand-alone names" do
      assert month_name(5787, 7, Hebrew, style: :abbreviated) == "Adar II"
      assert month_name(5787, 7, Hebrew, context: :stand_alone) == "Adar II"
      assert month_name(5786, 7, Hebrew, style: :abbreviated) == "Nisan"
    end
  end

  describe "a lunisolar leap month" do
    test "takes its month's name in the calendar's leap-month pattern" do
      assert month_name(4660, 3, Chinese) == "Second Monthbis"
      assert month_name(4660, 4, Chinese) == "Third Month"
      assert month_name(4660, 2, Chinese) == "Second Month"
    end
  end

  # ICU4C 78.3 writes a lunisolar month as its number among the traditional
  # months, and a leap month in CLDR's numeric leap pattern: Gregorian
  # 2023-04-01 is day 11 of the leap second month of Chinese year 4660,
  # "2bis/11/2023" in `en` and "2023/闰2/11" in `zh`, and the months after it
  # keep their numbers. It numbers the Hebrew months by their place in the
  # year: Nisan is 8 in the leap year 5784 and 7 in the ordinary year 5785.
  describe "a month written as a number" do
    test "a lunisolar month is its traditional number, a leap month in the leap pattern" do
      assert format(%{year: 4660, month: 2, day: 19}, Chinese, "M/d/r", :en) == "2/19/2023"
      assert format(%{year: 4660, month: 3, day: 11}, Chinese, "M/d/r", :en) == "2bis/11/2023"
      assert format(%{year: 4660, month: 4, day: 12}, Chinese, "M/d/r", :en) == "3/12/2023"
      assert format(%{year: 4660, month: 11, day: 19}, Chinese, "M/d/r", :en) == "10/19/2023"
      assert format(%{year: 4660, month: 3, day: 11}, Chinese, "r/M/d", :zh) == "2023/闰2/11"
      assert format(%{year: 4660, month: 3, day: 11}, Chinese, "MM/dd/r", :en) == "02bis/11/2023"
      assert format(%{year: 4660, month: 3, day: 11}, Chinese, "r/LL/dd", :zh) == "2023/闰02/11"
    end

    test "a partial lunisolar date writes its month and related year" do
      assert format(%{year: 4660, month: 3}, Chinese, "M r", :en) == "2bis 2023"
    end

    # CLDR numbers the Hebrew months alike in every year, Nisan 8, where ICU
    # writes a month's place in the year: Nisan is the seventh month of a
    # common year such as 5785. Both number a leap year's months alike.
    test "a Hebrew month is the CLDR month its name uses, whatever its place in the year" do
      assert format(%{year: 5784, month: 8, day: 12}, Hebrew, "M/d", :en) == "8/12"
      assert format(%{year: 5785, month: 7, day: 12}, Hebrew, "M/d", :en) == "8/12"
    end

    # Read back, the number is the CLDR month too, and so the month of that
    # name in the year: an ordinary year's Adar, its sixth month, is written
    # 7, and a leap year's Adar II, its seventh, is also written 7.
    test "a Hebrew month written as a number reads back to its place in the year" do
      reference = %{year: 5786, month: 1, day: 1, calendar: Hebrew}

      dates =
        for {year, month} <- [
              {5786, 5},
              {5786, 6},
              {5786, 7},
              {5786, 12},
              {5787, 6},
              {5787, 7},
              {5787, 8},
              {5787, 13}
            ],
            do: %Date{year: year, month: month, day: 15, calendar: Hebrew}

      failures =
        for {locale, format} <- [de: :short, fr: :short, ja: :short, zh: :short, en: :medium],
            date <- dates,
            {:ok, text} = Localize.Date.to_string(date, format: format, locale: locale),
            parsed =
              Localize.Date.parse(text,
                locale: locale,
                calendar: Hebrew,
                reference_date: reference
              ),
            parsed != {:ok, date} do
          {locale, date, text, parsed}
        end

      assert failures == []
    end
  end

  defp format(date, calendar, pattern, locale) do
    {:ok, formatted} =
      Localize.Date.to_string(Map.put(date, :calendar, calendar), format: pattern, locale: locale)

    formatted
  end

  describe "a month the calendar does not rename" do
    test "is named by its number" do
      assert Localize.Calendar.localize(~D[2019-06-01], :month, locale: :en) == {:ok, "June"}
    end

    test "a date without a year or calendar is named by its number" do
      assert Localize.Calendar.localize(%{month: 6}, :month, locale: :en) == {:ok, "June"}
    end

    # Localize takes a month from its calendar's answer and never from the
    # date's own field, so an answer that is not a month is an error.
    test "an answer that is not a month is an error" do
      assert {:error, %Localize.InvalidValueError{value: :not_a_month}} =
               month_name(2019, 6, Unanswering)

      assert {:error, %Localize.InvalidValueError{value: :not_a_month}} =
               Localize.Date.to_string(%{year: 2019, month: 6, day: 1, calendar: Unanswering},
                 format: "M/d",
                 locale: :en
               )
    end
  end
end
