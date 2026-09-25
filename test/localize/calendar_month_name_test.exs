defmodule Localize.CalendarMonthNameTest do
  use ExUnit.Case, async: true

  # A calendar whose month names do not follow a month's position in its
  # year names its months through `month_of_year/3`. Localize does not
  # depend on Calendrical, so these stand-ins answer as Calendrical's Hebrew
  # and Chinese calendars do.
  defmodule Hebrew do
    @moduledoc false

    def cldr_calendar_type, do: :hebrew

    def leap_year?(year), do: Integer.mod(7 * year + 1, 19) < 7

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

    def cldr_calendar_type, do: :chinese

    # Year 4660 has a leap second month, at position 3.
    def month_of_year(4660, 3, _day), do: {2, :leap}
    def month_of_year(4660, month, _day) when month > 3, do: month - 1
    def month_of_year(_year, month, _day), do: month
  end

  defmodule Unanswering do
    @moduledoc false

    def cldr_calendar_type, do: :gregorian
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

  describe "a month the calendar does not rename" do
    test "is named by its number" do
      assert Localize.Calendar.localize(~D[2019-06-01], :month, locale: :en) == {:ok, "June"}
    end

    test "a date without a year or calendar is named by its number" do
      assert Localize.Calendar.localize(%{month: 6}, :month, locale: :en) == {:ok, "June"}
    end

    test "an answer that is not a month falls back to the month's number" do
      assert month_name(2019, 6, Unanswering) == "June"
    end
  end
end
