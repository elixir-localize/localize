defmodule Localize.DateTime.ExtendedYearSymbolTest do
  @moduledoc """
  The extended year, TR35's `u`, is the calendar's answer.

  TR35's Date Field Symbol Table: "Extended year (numeric). This is a single
  number designating the year of this calendar system, encompassing all
  supra-year fields. For example, for the Julian calendar system, year
  numbers are positive, with an era of BCE or CE. An extended year value for
  the Julian calendar system assigns positive values to CE years and
  negative values to BCE years, with 1 BCE being year 0. For 'u', all field
  lengths specify a minimum number of digits; there is no special
  interpretation for 'uu'."

  So the year a date carries is not always its extended year: a Julian date
  in 1 BC carries year -1, since that calendar has no year 0, and its
  extended year is 0. The calendar says which, through its `extended_year/3`.

  Localize cannot load Calendrical, so stand-ins answer as its calendars do,
  and Calendrical's own are held to ICU4C in its
  `test/localize_extended_year_test.exs`. The digits of a year of 0 and
  below are ICU4C 78.3's for the same widths: "0" and "0000", "-1" and
  "-0001".

  """

  use ExUnit.Case, async: true

  alias Localize.Test.NoYearZeroCalendar

  # A calendar whose year field is the year of a reign that began in 2019,
  # so its year 8 is the 2026th of its count: the extended year is not the
  # field at all.
  defmodule Regnal do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def extended_year(year, _month, _day), do: year + 2018
  end

  # A calendar that answers for a whole date only, as Calendrical's calendars
  # built on its behaviour do: a date missing its month or day is not its to
  # answer.
  defmodule WholeDates do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def extended_year(_year, month, day) when is_nil(month) or is_nil(day),
      do: {:error, :missing_fields}

    def extended_year(year, _month, _day), do: year + 2018
  end

  # A calendar whose count turns on 1 July, within the year its dates carry:
  # the days of a year disagree, and the days of any one month agree.
  defmodule MidYear do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def extended_year(_year, month, day) when is_nil(month) or is_nil(day),
      do: {:error, :missing_fields}

    def extended_year(year, month, _day) when month >= 7, do: year + 1
    def extended_year(year, _month, _day), do: year
  end

  # A calendar whose count turns on the 16th of July, within a month.
  defmodule MidMonth do
    @moduledoc false
    use Localize.Test.StandInCalendar

    def extended_year(_year, month, day) when is_nil(month) or is_nil(day),
      do: {:error, :missing_fields}

    def extended_year(year, month, day) when {month, day} >= {7, 16}, do: year + 1
    def extended_year(year, _month, _day), do: year
  end

  defp date(year, month, day, calendar),
    do: %Date{year: year, month: month, day: day, calendar: calendar}

  defp format(value, pattern, locale \\ :en),
    do: Localize.Date.to_string(value, format: pattern, locale: locale)

  describe "in Calendar.ISO" do
    # ISO 8601 numbers 1 BC as year 0, as TR35's extended year does.
    test "is the year itself, 1 BC being year 0" do
      assert format(~D[2026-06-15], "u") == {:ok, "2026"}
      assert format(~D[0001-06-15], "u") == {:ok, "1"}

      assert format(~D[0000-06-15], "u") == {:ok, "0"}
      assert format(~D[0000-06-15], "y G") == {:ok, "1 BC"}

      assert format(~D[-0001-06-15], "u") == {:ok, "-1"}
      assert format(~D[-0001-06-15], "y G") == {:ok, "2 BC"}
    end

    test "every length is a minimum number of digits" do
      assert format(~D[2026-06-15], "uu") == {:ok, "2026"}
      assert format(~D[2026-06-15], "uuuuuu") == {:ok, "002026"}
      assert format(~D[0005-06-15], "uu") == {:ok, "05"}
      assert format(~D[0000-06-15], "uuuu") == {:ok, "0000"}
      assert format(~D[-0001-06-15], "uuuu") == {:ok, "-0001"}
    end
  end

  describe "in a calendar with no year 0" do
    # Year -1 is 1 BC, which is extended year 0, and year -2 is -1.
    test "counts 1 BC as 0 where the date's year is -1" do
      assert format(date(2026, 6, 15, NoYearZeroCalendar), "u") == {:ok, "2026"}
      assert format(date(1, 6, 15, NoYearZeroCalendar), "u") == {:ok, "1"}

      assert format(date(-1, 6, 15, NoYearZeroCalendar), "u") == {:ok, "0"}
      assert format(date(-1, 6, 15, NoYearZeroCalendar), "uuuu") == {:ok, "0000"}
      assert format(date(-1, 6, 15, NoYearZeroCalendar), "y G") == {:ok, "1 BC"}

      assert format(date(-2, 6, 15, NoYearZeroCalendar), "u") == {:ok, "-1"}
      assert format(date(-2, 6, 15, NoYearZeroCalendar), "uuuu") == {:ok, "-0001"}
      assert format(date(-45, 3, 15, NoYearZeroCalendar), "u") == {:ok, "-44"}
    end

    # The same day in `Calendar.ISO` has the same extended year.
    test "agrees with Calendar.ISO on the same day" do
      for iso <- [~D[0000-06-15], ~D[-0001-06-15], ~D[-0044-03-15], ~D[0001-01-01]] do
        converted = Date.convert!(iso, NoYearZeroCalendar)

        assert format(converted, "u") == format(iso, "u"), inspect(iso)
      end
    end
  end

  describe "in a calendar whose years are not its count" do
    test "is the calendar's count, where `y` is the date's year" do
      value = date(8, 6, 15, Regnal)

      assert format(value, "u") == {:ok, "2026"}
      assert format(value, "y") == {:ok, "8"}
      assert format(value, "uuuuu") == {:ok, "02026"}
    end

    test "is a year part" do
      assert Localize.Date.to_parts(date(8, 6, 15, Regnal), format: "u", locale: :en) ==
               {:ok, [%{type: :year, value: "2026"}]}
    end

    test "is written in the locale's digits" do
      assert format(date(8, 6, 15, Regnal), "u", :"ar-EG") == {:ok, "٢٠٢٦"}
    end

    test "is the week's month's year in a pattern with W" do
      # 30 December 2019 is in the first week of January 2020 in `en-GB`,
      # whose weeks are ISO 8601's: the week holding Thursday 2 January.
      assert format(~D[2019-12-30], "'week' W 'of' MMMM u", :"en-GB") ==
               {:ok, "week 1 of January 2020"}
    end
  end

  describe "a partial date" do
    test "shows the extended year of its year" do
      assert format(%{year: 2026}, "u") == {:ok, "2026"}
      assert format(%{year: 0, month: 6}, "u") == {:ok, "0"}
      assert format(%{year: -1, calendar: NoYearZeroCalendar}, "u") == {:ok, "0"}
      assert format(%{year: 8, month: 6, calendar: Regnal}, "u") == {:ok, "2026"}
    end

    # A calendar that answers for a whole date only is asked about the first
    # and the last day the date could be, which agree.
    test "is asked of the days it could be where the calendar needs a whole date" do
      assert format(%{year: 8, calendar: WholeDates}, "u") == {:ok, "2026"}
      assert format(%{year: 8, month: 6, calendar: WholeDates}, "u") == {:ok, "2026"}
      assert Localize.Calendar.extended_year(%{year: 8, calendar: WholeDates}) == {:ok, 2026}
    end

    test "needs the fields that settle it where its days disagree" do
      assert format(%{year: 2026, month: 3, calendar: MidYear}, "u") == {:ok, "2026"}
      assert format(%{year: 2026, month: 7, calendar: MidYear}, "u") == {:ok, "2027"}

      assert {:error, %Localize.DateTimeInvalidInputError{missing: [:month, :day]}} =
               format(%{year: 2026, calendar: MidYear}, "u")

      assert {:error, %Localize.DateTimeInvalidInputError{missing: [:day]}} =
               format(%{year: 2026, month: 7, calendar: MidMonth}, "u")

      assert format(%{year: 2026, month: 7, day: 15, calendar: MidMonth}, "u") == {:ok, "2026"}
      assert format(%{year: 2026, month: 7, day: 16, calendar: MidMonth}, "u") == {:ok, "2027"}
    end

    test "without a year is an error naming it" do
      assert {:error, %Localize.DateTimeInvalidInputError{missing: [:year]}} =
               format(%{month: 6, day: 15}, "u")
    end
  end
end
