defmodule Localize.ImpossibleFieldsParseTest do
  use ExUnit.Case, async: true

  # A field value no date or time can have is an error in every parser and
  # in both forms: never a field left out of the map, never one taken from
  # the other endpoint of a range, and never the digits read as another
  # field. The expected values are calendar facts. June has 30 days;
  # February 29 falls only in leap years (2024, not 2025); an ISO year has
  # 12 months and an hour 60 minutes. `Calendar.ISO`'s weeks are the
  # locale's. Under en's week rules (weeks start on Sunday and week 1 holds
  # January 1) 2022 has 53 weeks, its week 53 starting on Sunday, December
  # 25, and 2026 has 52; June 2024 starts on a Saturday, so its week 1 began
  # on Sunday, May 26, and June 30, a Sunday, begins week 1 of July, which
  # leaves June five weeks. Under de's (ISO 8601: Monday, four days) a
  # month's weeks are as many as its Thursdays, four or five, and a week
  # holding fewer than four of its days is the month before's or after's.

  @options [locale: :en, reference_date: ~D[2026-07-05]]
  @map_options Keyword.put(@options, :as, :map)

  describe "Localize.Date.parse/2" do
    test "a month the calendar does not have is an error in both forms" do
      for input <- ["15/06/2026", "0/06/2026", "31/12/2026", "13/06/2026", "15/2026", "13/2026"] do
        assert_error(Localize.Date.parse(input, @options), Localize.DateParseError, input)
        assert_error(Localize.Date.parse(input, @map_options), Localize.DateParseError, input)
      end
    end

    test "a day the month does not have is an error in both forms" do
      for input <- ["06/31/2026", "02/30/2026", "02/29/2025", "06/32/2026", "06/00/2026"] do
        assert_error(Localize.Date.parse(input, @options), Localize.DateParseError, input)
        assert_error(Localize.Date.parse(input, @map_options), Localize.DateParseError, input)
      end
    end

    test "February 29 of a leap year parses in both forms" do
      assert Localize.Date.parse("02/29/2024", @options) == {:ok, ~D[2024-02-29]}

      assert Localize.Date.parse("02/29/2024", @map_options) ==
               {:ok, %{calendar: Calendar.ISO, year: 2024, month: 2, day: 29}}
    end

    test "a day no year gives the month is an error in the map form, not a two-digit year" do
      for input <- ["June 31", "February 30", "May 32", "May 0"] do
        assert_error(Localize.Date.parse(input, @map_options), Localize.DateParseError, input)
      end
    end

    test "a day some year gives the month is a partial date in the map form" do
      assert Localize.Date.parse("February 29", @map_options) ==
               {:ok, %{calendar: Calendar.ISO, month: 2, day: 29}}

      assert Localize.Date.parse("May 2032", @map_options) ==
               {:ok, %{calendar: Calendar.ISO, month: 5, year: 2032}}
    end

    # `Calendar.ISO`'s weeks are the locale's. Under en's (weeks from Sunday,
    # week 1 holding 1 January) 2022 has 53 weeks, its week 53 beginning on
    # Sunday 25 December, and 2026 has 52. Under de's, ISO 8601's, 2026,
    # which begins on a Thursday, has 53, whose Monday is 28 December, and
    # 2025 has 52 (`:calendar.iso_week_number/1`).
    test "a week the year does not have is an error in both forms" do
      for input <- ["week 60 of 2026", "week 0 of 2026", "week 53 of 2026"] do
        assert_error(Localize.Date.parse(input, @options), Localize.DateParseError, input)
        assert_error(Localize.Date.parse(input, @map_options), Localize.DateParseError, input)
      end

      assert Localize.Date.parse("week 53 of 2022", @options) == {:ok, ~D[2022-12-25]}

      assert :calendar.iso_week_number({2025, 12, 28}) == {2025, 52}
      assert :calendar.iso_week_number({2026, 12, 28}) == {2026, 53}

      de_options = Keyword.put(@options, :locale, :de)

      assert_error(
        Localize.Date.parse("Woche 53 des Jahres 2025", de_options),
        Localize.DateParseError,
        "Woche 53 des Jahres 2025"
      )

      assert Localize.Date.parse("Woche 53 des Jahres 2026", de_options) == {:ok, ~D[2026-12-28]}
    end

    # `W` numbers a month's weeks as a year's are numbered, in the month the
    # week belongs to, so no month has a week 0 or a week 6: under en's weeks
    # a week holding the first of a month is that month's week 1, and under
    # de's, ISO 8601's, a month's weeks are as many as its Thursdays. June
    # 2024 has five en weeks, and August 2024 five Thursdays.
    test "a week of the month no month has is an error in the map form" do
      for input <- ["week 7 of June", "week 6 of June", "week 0 of June"] do
        assert_error(Localize.Date.parse(input, @map_options), Localize.DateParseError, input)
      end

      assert Localize.Date.parse("week 5 of June", @map_options) ==
               {:ok, %{calendar: Calendar.ISO, month: 6, week_of_month: 5}}

      de_options = Keyword.put(@map_options, :locale, :de)

      for input <- ["Woche 6 im Februar", "Woche 0 im August"] do
        assert_error(Localize.Date.parse(input, de_options), Localize.DateParseError, input)
      end

      assert Localize.Date.parse("Woche 5 im August", de_options) ==
               {:ok, %{calendar: Calendar.ISO, month: 8, week_of_month: 5}}
    end
  end

  describe "Localize.DateTime.parse/2" do
    test "a date part with a field no date has is an error in both forms" do
      for input <- ["15/06/2026, 10:30 AM", "06/31/2026, 10:30 AM"] do
        assert_error(Localize.DateTime.parse(input, @options), Localize.DateTimeParseError, input)

        assert_error(
          Localize.DateTime.parse(input, @map_options),
          Localize.DateTimeParseError,
          input
        )
      end
    end
  end

  describe "Localize.Time.parse/2" do
    test "a minute or second no time has is an error in both forms" do
      for input <- ["10:61", "10:30:61", "10:30:60"] do
        assert_error(Localize.Time.parse(input, @options), Localize.TimeParseError, input)
        assert_error(Localize.Time.parse(input, @map_options), Localize.TimeParseError, input)
      end
    end
  end

  describe "Localize.Interval.parse/2" do
    test "an endpoint field no date has is an error, not taken from the other endpoint" do
      for input <- ["May 5 – 40, 2026", "5/5/2026 – 15/10/2026", "May 5 – June 31, 2026"] do
        assert_error(
          Localize.Interval.parse(input, @options),
          Localize.DateRangeParseError,
          input
        )

        assert_error(
          Localize.Interval.parse(input, @map_options),
          Localize.DateRangeParseError,
          input
        )
      end
    end
  end

  defp assert_error(result, exception, input) do
    assert match?({:error, %{__struct__: ^exception}}, result),
           "#{inspect(input)} gave #{inspect(result)}"
  end
end
