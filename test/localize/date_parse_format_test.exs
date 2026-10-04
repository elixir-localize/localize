defmodule Localize.DateParseFormatTest do
  @moduledoc """
  A date is read with the format it was written with when `:format` names
  it, as `Localize.Date.to_string/2` takes it: a standard format, a
  skeleton or a pattern (user, 2026-10-04: "Let parse/2 take the format the
  text was written with").

  Without it the parser tries the locale's formats in turn and the first to
  read the text wins, so a date written by a skeleton whose fields stand in
  another order than the standard format's reads as another date. The
  patterns are CLDR's, from `common/main` at the pinned revision:

      mt  gregorian  short  "dd/MM/y"           yMd     "M/d/y"
      ug  gregorian  short  "y-MM-dd" (root's)  yMd     "y-d-M"
      my  generic    short  "GGGGG d/M/y"       GyMd    "GGGGG y/M/d"
      sa  generic    medium "G d MMM y"         GyMMMd  "G y MMM d" (root's)

  """

  use ExUnit.Case, async: true

  # Localize cannot load Calendrical's calendars, which depend on it. This
  # stand-in names the Japanese calendar and answers `year_of_era/3` for
  # Kanpō, from 1741-04-12, and Enkyō, from 1744-04-03, taking the rest of
  # its arithmetic from `Calendar.ISO`. Localize defines every Japanese era,
  # the eras before Meiji included, where CLDR 49 ships only Meiji onwards:
  # their start dates are `priv/localize/curated/japanese_eras.json`'s and
  # their names, "Kanpō (1741–1744)" among them, CLDR 48.2's, kept in
  # `priv/localize/curated/japanese_era_names.json`.
  defmodule Japanese do
    @moduledoc false
    use Localize.Test.StandInCalendar

    @eras [{~D[1744-04-03], 214}, {~D[1741-04-12], 213}]

    def cldr_calendar_type, do: :japanese
    def cardinal_month(month), do: month
    def month_of_year(_year, month, _day), do: month

    def year_of_era(_year, month, day) when is_nil(month) or is_nil(day),
      do: {:error, :missing_fields}

    def year_of_era(year, month, day) do
      date = Date.new!(year, month, day)

      {start, era} =
        Enum.find(@eras, List.last(@eras), fn {start, _era} ->
          Date.compare(date, start) != :lt
        end)

      {year - start.year + 1, era}
    end

    def calendar_year(year, month, day) do
      with {year_of_era, _era} <- year_of_era(year, month, day), do: year_of_era
    end

    defdelegate valid_date?(year, month, day), to: Calendar.ISO
    defdelegate days_in_month(year, month), to: Calendar.ISO
    defdelegate months_in_year(year), to: Calendar.ISO
    defdelegate date_to_string(year, month, day), to: Calendar.ISO
  end

  # The second day of the sixth month of Kanpō 1.
  @kanpo Date.new!(1741, 6, 2, Japanese)
  @reference Date.new!(1742, 1, 1, Japanese)

  defp japanese(options),
    do: Keyword.merge([calendar: Japanese, reference_date: @reference], options)

  describe "a skeleton whose fields stand in another order than the standard format's" do
    # `mt` writes 3 April 2024 "4/3/2024" with `yMd`, month first, and its
    # short date day first, so the same text is 4 March without the format.
    test "reads back with it in the Gregorian calendar" do
      assert Localize.Date.to_string(~D[2024-04-03], locale: :mt, format: :yMd) ==
               {:ok, "4/3/2024"}

      assert Localize.Date.parse("4/3/2024", locale: :mt) == {:ok, ~D[2024-03-04]}
      assert Localize.Date.parse("4/3/2024", locale: :mt, format: :yMd) == {:ok, ~D[2024-04-03]}

      # `ug`'s `yMd` writes the day before the month, in the shape ISO 8601
      # writes a date in, which is read first without the format.
      assert Localize.Date.to_string(~D[2024-11-10], locale: :ug, format: :yMd) ==
               {:ok, "2024-10-11"}

      assert Localize.Date.parse("2024-10-11", locale: :ug) == {:ok, ~D[2024-10-11]}
      assert Localize.Date.parse("2024-10-11", locale: :ug, format: :yMd) == {:ok, ~D[2024-11-10]}
    end

    # `my` writes its digits ၀ to ၉. `GyMd` writes Kanpō 1, month 6, day 2
    # year first, and the short date writes a day first, so the text is the
    # first of the sixth month of Kanpō 2 without the format.
    test "reads back with it beside an era" do
      assert Localize.Date.to_string(@kanpo, locale: :my, format: :GyMd) ==
               {:ok, "Kanpō (1741–1744) ၁/၆/၂"}

      assert Localize.Date.parse("Kanpō (1741–1744) ၁/၆/၂", japanese(locale: :my)) ==
               {:ok, Date.new!(1742, 6, 1, Japanese)}

      assert Localize.Date.parse("Kanpō (1741–1744) ၁/၆/၂", japanese(locale: :my, format: :GyMd)) ==
               {:ok, @kanpo}

      # `sa` writes its digits ० to ९ and June "जून:". Root's `GyMMMd` puts
      # the year before the month and `sa`'s medium date the day.
      assert Localize.Date.to_string(@kanpo, locale: :sa, format: :GyMMMd) ==
               {:ok, "Kanpō (1741–1744) १ जून: २"}

      assert Localize.Date.parse("Kanpō (1741–1744) १ जून: २", japanese(locale: :sa)) ==
               {:ok, Date.new!(1742, 6, 1, Japanese)}

      assert Localize.Date.parse(
               "Kanpō (1741–1744) १ जून: २",
               japanese(locale: :sa, format: :GyMMMd)
             ) == {:ok, @kanpo}
    end
  end

  describe "the format the text was written with" do
    test "is a standard format, a skeleton or a pattern" do
      for {format, text} <- [
            {:short, "3/4/24"},
            {:medium, "Mar 4, 2024"},
            {:long, "March 4, 2024"},
            {:full, "Monday, March 4, 2024"},
            {:yMd, "3/4/2024"},
            {:yMMMEd, "Mon, Mar 4, 2024"},
            {"yyyy.MM.dd", "2024.03.04"},
            {"d 'of' MMMM, y", "4 of March, 2024"}
          ] do
        assert Localize.Date.to_string(~D[2024-03-04], locale: :en, format: format) == {:ok, text}

        assert Localize.Date.parse(text, locale: :en, format: format) == {:ok, ~D[2024-03-04]},
               inspect(format)
      end
    end

    test "reads back what the formatter writes with it, in each locale and format" do
      failures =
        for locale <- [:en, :de, :fr, :ja, :mt, :ug, :"kk-Arab", :my, :sa, :fa, :he, :ar, :th],
            format <- [:short, :medium, :long, :full, :yMd, :yMMMd, :yMMMEd, :GyMd, :GyMMMd],
            date <- [~D[2024-03-04], ~D[2024-11-10]],
            {:ok, text} <- [Localize.Date.to_string(date, locale: locale, format: format)],
            Localize.Date.parse(text, locale: locale, format: format) != {:ok, date} do
          {locale, format, date, text}
        end

      assert failures == []
    end

    # A format with fewer fields than a date reads the fields it has.
    test "of some of a date's fields gives those fields as a map" do
      assert Localize.Date.parse("Mar 2024", locale: :en, format: :yMMM, as: :map) ==
               {:ok, %{calendar: Calendar.ISO, year: 2024, month: 3}}

      assert Localize.Date.parse("3/4/2024", locale: :en, format: :yMd, as: :map) ==
               {:ok, %{calendar: Calendar.ISO, year: 2024, month: 3, day: 4}}

      assert {:error, %Localize.DateParseError{format: :yMMM}} =
               Localize.Date.parse("Mar 2024", locale: :en, format: :yMMM)
    end

    # The text is read with that format and no other: ISO 8601 and the
    # locale's other formats are not tried.
    test "is the only format the text is read with" do
      for text <- ["2024-03-04", "March 4, 2024", "Mar 4, 2024"] do
        assert {:error, %Localize.DateParseError{format: :short} = error} =
                 Localize.Date.parse(text, locale: :en, format: :short)

        assert Exception.message(error) =~ "written with the format :short"
      end

      assert Localize.Date.parse("2024-03-04", locale: :en) == {:ok, ~D[2024-03-04]}
    end
  end

  describe "a format that is not one" do
    # A pattern is one the formatter writes a date with. A quote left open
    # and a letter that is no pattern field fail to tokenize, a field longer
    # than any format writes is written as U+FFFD, and a time's field needs
    # a time.
    test "is an error that says so, and never raises" do
      for format <- ["'open", "y'", "j", "QQQQQQQQQ", "MMMMMM", "EEEEEEE", "dddddd"] do
        assert {:error, %Localize.DateTimeFormatError{}} =
                 Localize.Date.parse("3/4/2024", locale: :en, format: format),
               inspect(format)
      end

      assert {:error, %Localize.DateTimeInvalidInputError{missing: [:hour, :minute]}} =
               Localize.Date.parse("3/4/2024", locale: :en, format: "d/M/y HH:mm")

      for format <- [:nosuchskeleton, :""] do
        assert {:error, %Localize.DateTimeUnresolvedFormatError{}} =
                 Localize.Date.parse("3/4/2024", locale: :en, format: format),
               inspect(format)
      end

      for format <- [123, 1.5, {:a, :b}, ["yMd"], %{}] do
        assert {:error, %Localize.DateTimeFormatError{reason: :invalid_format}} =
                 Localize.Date.parse("3/4/2024", locale: :en, format: format),
               inspect(format)
      end

      for format <- ["", "ggg", String.duplicate("y", 5000)] do
        assert {:error, %Localize.DateParseError{}} =
                 Localize.Date.parse("3/4/2024", locale: :en, format: format)
      end
    end

    test "that is nil is no format" do
      assert Localize.Date.parse("2024-03-04", locale: :en, format: nil) == {:ok, ~D[2024-03-04]}
    end
  end

  describe "a date and time" do
    # `mt` joins a date and a time with a space, root's "{1} {0}", and a
    # skeleton of both is written as its date fields' format and its time
    # fields', so the date is read with the date fields.
    test "reads its date with the date fields of a skeleton" do
      assert Localize.DateTime.to_string(~N[2024-04-03 10:30:00], locale: :mt, format: :yMdHm) ==
               {:ok, "4/3/2024 10:30"}

      assert Localize.DateTime.parse("4/3/2024 10:30", locale: :mt) ==
               {:ok, ~N[2024-03-04 10:30:00]}

      assert Localize.DateTime.parse("4/3/2024 10:30", locale: :mt, format: :yMdHm) ==
               {:ok, ~N[2024-04-03 10:30:00]}

      assert Localize.DateTime.parse("4/3/2024 10:30", locale: :mt, date_format: :yMd) ==
               {:ok, ~N[2024-04-03 10:30:00]}

      assert Localize.DateTime.parse("4/3/2024 10:30", locale: :mt, format: :yMdHm, as: :map) ==
               {:ok,
                %{calendar: Calendar.ISO, year: 2024, month: 4, day: 3, hour: 10, minute: 30}}
    end

    test "reads back what the formatter writes with a skeleton, in each locale" do
      naive = ~N[2024-04-03 10:30:00]

      failures =
        for locale <- [:en, :de, :fr, :ja, :mt, :ug, :"kk-Arab", :my, :sa, :fa, :he, :ar, :th],
            format <- [:yMdhm, :yMdHm, :yMMMdhm, :yMEdjm, :GyMdHms],
            {:ok, text} <- [Localize.DateTime.to_string(naive, locale: locale, format: format)],
            Localize.DateTime.parse(text, locale: locale, format: format) != {:ok, naive} do
          {locale, format, text}
        end

      assert failures == []
    end

    # A pattern of a date and time is split at the text between its date
    # fields and its time fields, and each half is read with its part
    # (`test/localize/datetime_parse_format_test.exs`). The date's own format
    # is `:date_format`.
    test "reads its date with the date fields of a pattern of both" do
      assert Localize.DateTime.parse("4/3/2024 10:30", locale: :mt, format: "M/d/y HH:mm") ==
               {:ok, ~N[2024-04-03 10:30:00]}

      assert Localize.DateTime.parse("4/3/2024 10:30", locale: :mt, date_format: "M/d/y") ==
               {:ok, ~N[2024-04-03 10:30:00]}
    end

    # The text is a date, a time, a date and time or an interval, and the
    # format goes to whichever reads it.
    test "of unknown shape is read with the format" do
      assert Localize.DateTime.Parser.parse("4/3/2024", locale: :mt, format: :yMd) ==
               {:ok, ~D[2024-04-03]}

      assert Localize.DateTime.Parser.parse("4/3/2024 10:30", locale: :mt, format: :yMdHm) ==
               {:ok, ~N[2024-04-03 10:30:00]}
    end

    # `Localize.DateTime.to_string/2` writes the date with `:date_format`,
    # and the date is read with it. A standard `:format` is the date's and
    # the time's alike.
    test "reads its date with the format it was written with" do
      naive = %NaiveDateTime{
        calendar: Japanese,
        year: 1741,
        month: 6,
        day: 2,
        hour: 10,
        minute: 30,
        second: 0
      }

      {:ok, text} =
        Localize.DateTime.to_string(naive, locale: :my, date_format: :GyMd, time_format: :short)

      assert {:ok, %NaiveDateTime{year: 1742, month: 6, day: 1, hour: 10, minute: 30}} =
               Localize.DateTime.parse(text, japanese(locale: :my))

      assert {:ok, %NaiveDateTime{year: 1741, month: 6, day: 2, hour: 10, minute: 30}} =
               Localize.DateTime.parse(text, japanese(locale: :my, date_format: :GyMd))

      assert Localize.DateTime.parse("3/4/24, 10:30 AM", locale: :en, format: :short) ==
               {:ok, ~N[2024-03-04 10:30:00]}

      # A date written at another length is not the short date.
      assert {:error, %Localize.DateTimeParseError{}} =
               Localize.DateTime.parse("Mar 4, 2024, 10:30 AM", locale: :en, format: :short)
    end
  end

  describe "an interval" do
    # The format is the one each end was written with, so each is read with
    # it about the separator, as `Localize.Interval.to_string/3` writes both
    # ends with a pattern. The locale's interval patterns, which `en` writes
    # month first, are not tried.
    test "reads each end with the format" do
      assert Localize.Interval.to_string(~D[2024-03-04], ~D[2024-03-10],
               locale: :en,
               format: "d/M/y"
             ) == {:ok, "4/3/2024 – 10/3/2024"}

      assert Localize.Interval.parse("4/3/2024 – 10/3/2024", locale: :en, format: "d/M/y") ==
               {:ok, Date.range(~D[2024-03-04], ~D[2024-03-10])}

      assert Localize.Interval.parse("4/3/2024 – 10/3/2024", locale: :en) ==
               {:ok, Date.range(~D[2024-04-03], ~D[2024-10-03])}

      assert Localize.Interval.parse("4/3/2024 – 10/3/2024",
               locale: :en,
               format: "d/M/y",
               as: :map
             ) ==
               {:ok,
                {%{calendar: Calendar.ISO, year: 2024, month: 3, day: 4},
                 %{calendar: Calendar.ISO, year: 2024, month: 3, day: 10}}}
    end
  end
end
