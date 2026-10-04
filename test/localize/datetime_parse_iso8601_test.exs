defmodule Localize.DateTimeParseIso8601Test do
  @moduledoc """
  ISO 8601's dates and times either side of a `T`, as
  `Localize.DateTime.parse/2` reads them.

  ISO 8601 writes a date as a calendar date, a day of the year or a week
  date, and a time with its seconds, or its minutes and seconds, left out,
  each with its separators (the extended format) or without them (the basic
  format). The expected values are ISO 8601's own arithmetic, checked here
  against Erlang's `:calendar`, which Localize does not use for them: 16 June
  2026 is the 167th day of its year and the Tuesday of week 25.

  Which forms of a calendar date and a time are read together follows
  ECMA-262's Temporal, whose answers (`Temporal.PlainDateTime.from` and
  `Temporal.Instant.from` in Node 24.9) are the cases marked so. Temporal
  reads no day of the year and no week date.

  """

  use ExUnit.Case, async: true

  @day ~D[2026-06-16]
  @dates ["2026-06-16", "20260616", "2026-167", "2026167", "2026-W25-2", "2026W252"]

  # A time, the `Time` it is and the fields it does not write.
  @times [
    {"10:30:45", ~T[10:30:45], []},
    {"103045", ~T[10:30:45], []},
    {"10:30:45.5", ~T[10:30:45.5], []},
    {"103045,25", ~T[10:30:45.25], []},
    {"10:30", ~T[10:30:00], [:second]},
    {"1030", ~T[10:30:00], [:second]},
    {"10", ~T[10:00:00], [:minute, :second]}
  ]

  # An offset and its seconds east of UTC. `z` is RFC 3339's, and U+2212 the
  # minus sign ISO 8601 writes.
  @offsets [
    {"Z", 0},
    {"z", 0},
    {"+02:00", 7200},
    {"+0200", 7200},
    {"+02", 7200},
    {"-05:30", -19_800},
    {"−05:30", -19_800}
  ]

  defp fraction(%Time{microsecond: {_microseconds, 0}}), do: %{}
  defp fraction(%Time{microsecond: microsecond}), do: %{microsecond: microsecond}

  describe "the day this file's dates name" do
    test "is 16 June 2026 by Erlang's calendar" do
      assert :calendar.iso_week_number({2026, 6, 16}) == {2026, 25}
      assert :calendar.day_of_the_week({2026, 6, 16}) == 2

      assert :calendar.date_to_gregorian_days({2026, 6, 16}) -
               :calendar.date_to_gregorian_days({2026, 1, 1}) + 1 == 167
    end
  end

  describe "a date and a time joined by a T" do
    test "are read in every form of the date and every form of the time" do
      for date <- @dates, {time_text, time, _unwritten} <- @times do
        text = date <> "T" <> time_text

        assert Localize.DateTime.parse(text, locale: :en) ==
                 {:ok, NaiveDateTime.new!(@day, time)},
               text
      end
    end

    # The wall time is the one written, with the offset beside it.
    test "keep the offset the time was written with" do
      for date <- @dates,
          {time_text, time, _unwritten} <- @times,
          {offset_text, offset} <- @offsets do
        text = date <> "T" <> time_text <> offset_text

        assert {:ok, %DateTime{} = datetime} = Localize.DateTime.parse(text, locale: :en), text

        assert {DateTime.to_naive(datetime), datetime.utc_offset, datetime.std_offset} ==
                 {NaiveDateTime.new!(@day, time), offset, 0},
               text
      end
    end

    # RFC 3339 allows `t` for `T`, and Temporal reads it.
    test "or by a t" do
      assert Localize.DateTime.parse("2026-06-16t10:30:45", locale: :en) ==
               {:ok, ~N[2026-06-16 10:30:45]}

      assert Localize.DateTime.parse("2026-W25-2t1030", locale: :en) ==
               {:ok, ~N[2026-06-16 10:30:00]}
    end

    # Temporal's readings: a time's seconds and minutes may be left out, and
    # a date and a time need not both have their separators, though ISO 8601
    # says they must.
    test "are read as Temporal reads a calendar date and a time" do
      for {text, expected} <- [
            {"2026-06-16T10:30", ~N[2026-06-16 10:30:00]},
            {"2026-06-16T10", ~N[2026-06-16 10:00:00]},
            {"20260616T103045", ~N[2026-06-16 10:30:45]},
            {"20260616T1030", ~N[2026-06-16 10:30:00]},
            {"20260616T10", ~N[2026-06-16 10:00:00]},
            {"20260616T10:30:45", ~N[2026-06-16 10:30:45]},
            {"2026-06-16T103045", ~N[2026-06-16 10:30:45]},
            {"2026-06-16T1030", ~N[2026-06-16 10:30:00]},
            {"20260616T103045.123", ~N[2026-06-16 10:30:45.123]},
            {"20260616T103045,123", ~N[2026-06-16 10:30:45.123]}
          ] do
        assert Localize.DateTime.parse(text, locale: :en) == {:ok, expected}, text
      end
    end

    # ISO 8601's weeks and days of the year at a year's ends, by Erlang's
    # calendar: 29 December 2025 is the Monday of week 1 of 2026, 3 January
    # 2021 the Sunday of week 53 of 2020, and 31 December 2024, in a leap
    # year, its 366th day.
    test "name the day ISO 8601's weeks and days of the year do" do
      assert :calendar.iso_week_number({2025, 12, 29}) == {2026, 1}
      assert :calendar.day_of_the_week({2025, 12, 29}) == 1
      assert :calendar.iso_week_number({2021, 1, 3}) == {2020, 53}
      assert :calendar.day_of_the_week({2021, 1, 3}) == 7
      assert :calendar.is_leap_year(2024)

      for {text, expected} <- [
            {"2026-W01-1T00:00", ~N[2025-12-29 00:00:00]},
            {"2020-W53-7T23:59", ~N[2021-01-03 23:59:00]},
            {"2020W537T2359", ~N[2021-01-03 23:59:00]},
            {"2024-366T12:00", ~N[2024-12-31 12:00:00]},
            {"2024366T1200", ~N[2024-12-31 12:00:00]},
            {"2026-001T00", ~N[2026-01-01 00:00:00]}
          ] do
        assert Localize.DateTime.parse(text, locale: :en) == {:ok, expected}, text
      end
    end

    # ISO 8601 is no locale's format, so every locale reads it alike.
    test "are read alike in every locale" do
      for locale <- [:de, :ja, :ar, :th, :fa],
          {text, expected} <- [
            {"2026-W25-2T10:30", ~N[2026-06-16 10:30:00]},
            {"20260616T103045", ~N[2026-06-16 10:30:45]},
            {"2026-167T10:30:45", ~N[2026-06-16 10:30:45]}
          ] do
        assert Localize.DateTime.parse(text, locale: locale) == {:ok, expected},
               "#{text} in #{locale}"
      end
    end

    # The date before the `T` is the date the same text is alone.
    test "have the date the text before the T is alone" do
      for date <- @dates do
        assert {:ok, alone} = Localize.Date.parse(date, locale: :en)
        assert {:ok, datetime} = Localize.DateTime.parse(date <> "T10:30", locale: :en)
        assert NaiveDateTime.to_date(datetime) == alone, date
      end
    end

    # A format names how the text was written, and ISO 8601 is then not
    # tried, in these forms as in the one Elixir reads.
    test "are not read where a format is given" do
      for text <- ["2026-W25-2T10:30", "20260616T103045", "2026-06-16T10:30"] do
        assert {:error, %Localize.DateTimeParseError{}} =
                 Localize.DateTime.parse(text, locale: :en, format: :medium),
               text
      end
    end
  end

  describe "a date and a time joined by a T, as a map" do
    # A map holds the fields the text gave: a time without its seconds has
    # none, as the same time after a space has none.
    test "leave out the seconds and the minutes the time does not write" do
      for date <- @dates, {time_text, time, unwritten} <- @times do
        text = date <> "T" <> time_text

        expected =
          %{calendar: Calendar.ISO, year: 2026, month: 6, day: 16}
          |> Map.merge(Map.take(time, [:hour, :minute, :second]))
          |> Map.merge(fraction(time))
          |> Map.drop(unwritten)

        assert Localize.DateTime.parse(text, locale: :en, as: :map) == {:ok, expected}, text
      end

      assert Localize.DateTime.parse("2026-06-16T10:30", locale: :en, as: :map) ==
               Localize.DateTime.parse("2026-06-16 10:30", locale: :en, as: :map)
    end

    # A fixed offset is carried under `Etc/UTC`, as a `DateTime` carries it.
    test "carry the offset's zone fields" do
      assert Localize.DateTime.parse("20260616T1030+0200", locale: :en, as: :map) ==
               {:ok,
                %{
                  calendar: Calendar.ISO,
                  year: 2026,
                  month: 6,
                  day: 16,
                  hour: 10,
                  minute: 30,
                  time_zone: "Etc/UTC",
                  zone_abbr: "+02:00",
                  utc_offset: 7200,
                  std_offset: 0
                }}
    end
  end

  describe "text that is no ISO 8601 date and time" do
    # Temporal refuses each of the calendar-date cases but an offset of
    # "-00:00", which ISO 8601 forbids and Elixir does not read, and a
    # second of 60, which Temporal reads as 59.
    test "is an error" do
      # 2025 has no week 53: 28 December is always in a year's last week.
      assert :calendar.iso_week_number({2025, 12, 28}) == {2025, 52}

      for text <- [
            # Separators in part of a time.
            "2026-06-16T10:3045",
            "2026-06-16T1030:45",
            # A fraction of a minute or of an hour, which ISO 8601 writes
            # and neither Elixir nor Temporal reads.
            "2026-06-16T10:30,5",
            "2026-06-16T10,5",
            # A digit missing.
            "2026-06-16T",
            "2026-06-16T1",
            "2026-06-16T103",
            "2026-06-16T10:3",
            "2026-06-16T10:30:4",
            "2026-06-16T10:30:45.",
            # No time of day.
            "2026-06-16T24:00:00",
            "2026-06-16T25:00",
            "2026-06-16T10:60",
            "2026-06-16T1060",
            "2026-06-16T23:59:60",
            # No offset.
            "2026-06-16T10:30:45+2",
            "2026-06-16T10:30:45+02:0",
            "2026-06-16T10:30+24:00",
            "2026-06-16T10:30+02:60",
            "2026-06-16T10:30-00:00",
            "2026-06-16T10:30:45 +02:00",
            # A date without its day, which ISO 8601 joins to no time.
            "2026-W25T10:30:45",
            "2026-06T10:30:45",
            "2026T10:30",
            # No date.
            "2026-13-01T10:30:45",
            "2026-02-30T10:30",
            "20260230T1030",
            "2026-366T10:30:45",
            "2026-000T10:30",
            "2026-W54-1T10:30:45",
            "2025-W53-1T10:30",
            "2026-W25-8T10:30:45",
            "2026-W25-0T10:30",
            # Two of them.
            "2026-06-16TT10:30"
          ] do
        assert {:error, %Localize.DateTimeParseError{}} =
                 Localize.DateTime.parse(text, locale: :en),
               text
      end
    end
  end

  describe "text that is no text" do
    # Whatever is given is an error and never a raise: bytes that are not
    # UTF-8, nothing at all, a `T` with nothing either side and a string far
    # longer than any date and time.
    test "is an error, and never raises" do
      for input <- [
            <<50, 48, 255, ?T, ?1, ?0>>,
            "",
            "T",
            "TT",
            "T10:30",
            String.duplicate("9", 5000) <> "T10",
            "2026-06-16T" <> String.duplicate("1", 5000),
            String.duplicate("2026-06-16T10:30", 2000)
          ] do
        assert {:error, %_exception{}} = Localize.DateTime.parse(input, locale: :en)
        assert {:error, %_exception{}} = Localize.DateTime.parse(input, locale: :en, as: :map)
        assert Localize.DateTime.Parser.from_iso8601(input) == :error
        assert Localize.Date.Parser.from_iso8601(input) == :error
      end
    end
  end

  describe "Localize.DateTime.Parser.parse/2" do
    test "reads them as a date and time" do
      assert Localize.DateTime.Parser.parse("2026-W25-2T10:30:45", locale: :en) ==
               {:ok, ~N[2026-06-16 10:30:45]}

      assert Localize.DateTime.Parser.parse("20260616T1030Z", locale: :en) ==
               {:ok, ~U[2026-06-16 10:30:00Z]}
    end
  end
end
