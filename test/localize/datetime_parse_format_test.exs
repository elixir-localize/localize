defmodule Localize.DateTimeParseFormatTest do
  @moduledoc """
  A date and time is read with the format it was written with: each half
  with its part of `:format`, or with `:date_format` and `:time_format`,
  as `Localize.DateTime.to_string/2` writes them (user, 2026-10-04: "Let
  parse/2 take the format the text was written with").

  A standard format is the date's and the time's alike. A skeleton is
  split into its date fields and its time fields. A pattern is split at
  the text between its date fields and its time fields, and so is the
  input. `en` writes its short date "M/d/yy" and time "h:mm a", joined
  "{1}, {0}", and `yMd` "M/d/y" and `Hm` "HH:mm".

  """

  use ExUnit.Case, async: true

  @naive ~N[2024-04-03 22:05:09]

  describe "a pattern of a date and time" do
    test "reads each half with its fields, split where the pattern joins them" do
      for {pattern, text, expected} <- [
            {"d/M/y HH:mm", "3/4/2024 22:05", ~N[2024-04-03 22:05:00]},
            {"MMM d, y, h:mm a", "Apr 3, 2024, 10:05 PM", ~N[2024-04-03 22:05:00]},
            {"EEEE d MMMM y 'at' h:mm a", "Wednesday 3 April 2024 at 10:05 PM",
             ~N[2024-04-03 22:05:00]},
            {"HH:mm 'on' d MMM y", "22:05 on 3 Apr 2024", ~N[2024-04-03 22:05:00]},
            {"y-MM-dd'T'HH:mm:ss", "2024-04-03T22:05:09", @naive},
            {"yyyyMMdd'T'HHmmss", "20240403T220509", @naive},
            {"yyyyMMddHHmmss", "20240403220509", @naive}
          ] do
        assert Localize.DateTime.to_string(expected, locale: :en, format: pattern) ==
                 {:ok, text},
               pattern

        assert Localize.DateTime.parse(text, locale: :en, format: pattern) == {:ok, expected},
               pattern
      end
    end

    # `mt` writes its short date day first and `yMd` month first: the
    # pattern says which the text is.
    test "reads a date its fields order as the pattern does" do
      assert Localize.DateTime.parse("4/3/2024 10:30", locale: :mt) ==
               {:ok, ~N[2024-03-04 10:30:00]}

      assert Localize.DateTime.parse("4/3/2024 10:30", locale: :mt, format: "M/d/y HH:mm") ==
               {:ok, ~N[2024-04-03 10:30:00]}
    end

    test "reads a zone its time fields write, and the fields it holds as a map" do
      assert Localize.DateTime.parse("3/4/2024 22:05 UTC", locale: :en, format: "d/M/y HH:mm z") ==
               {:ok, ~U[2024-04-03 22:05:00Z]}

      assert Localize.DateTime.parse("3/4/2024 22:05",
               locale: :en,
               format: "d/M/y HH:mm",
               as: :map
             ) ==
               {:ok, %{calendar: Calendar.ISO, year: 2024, month: 4, day: 3, hour: 22, minute: 5}}
    end

    # The text is read with the pattern and nothing else: another of the
    # locale's formats and ISO 8601 are not tried.
    test "is the only format the text is read with" do
      for text <- ["4/3/2024, 10:05 PM", "2024-04-03T22:05:09", "3/4/2024, 22:05"] do
        assert {:error, %Localize.DateTimeParseError{}} =
                 Localize.DateTime.parse(text, locale: :en, format: "d/M/y HH:mm"),
               text
      end
    end

    # A pattern of a date and time writes its date fields in one run and its
    # time fields in another. One that mixes them, holds one half alone, or
    # is no pattern is an error whatever the text.
    test "that is not one is an error, and never raises" do
      for pattern <- [
            "d HH:mm MMM y",
            "d/M/y",
            "HH:mm",
            "d/M/y 'at HH:mm",
            "d/M/y nn HH:mm",
            "d/M/y HHHHH:mm",
            "ddddd/M/y HH:mm",
            ""
          ] do
        assert {:error, %Localize.DateTimeFormatError{}} =
                 Localize.DateTime.parse("3/4/2024 22:05", locale: :en, format: pattern),
               inspect(pattern)
      end
    end
  end

  describe "a standard format and a skeleton" do
    test "read the date and the time alike" do
      assert Localize.DateTime.parse("4/3/24, 10:05 PM", locale: :en, format: :short) ==
               {:ok, ~N[2024-04-03 22:05:00]}

      assert Localize.DateTime.parse("Apr 3, 2024, 10:05:09 PM", locale: :en, format: :medium) ==
               {:ok, @naive}

      assert Localize.DateTime.parse("4/3/2024, 22:05", locale: :en, format: :yMdHm) ==
               {:ok, ~N[2024-04-03 22:05:00]}

      # A time written at another length, or in another hour cycle, is not
      # the format's, and ISO 8601 is no standard format's text.
      for {text, format} <- [
            {"4/3/24, 10:05:09 PM", :short},
            {"4/3/2024, 10:05 PM", :yMdHm},
            {"2024-04-03T22:05:09", :medium}
          ] do
        assert {:error, %Localize.DateTimeParseError{}} =
                 Localize.DateTime.parse(text, locale: :en, format: format),
               inspect({text, format})
      end
    end

    test "that is not one is an error" do
      assert {:error, %Localize.DateTimeUnresolvedFormatError{}} =
               Localize.DateTime.parse("4/3/2024, 22:05", locale: :en, format: :nosuchskeleton)

      for format <- [123, 1.5, {:a, :b}, ["yMdHm"], %{}] do
        assert {:error, %Localize.DateTimeFormatError{reason: :invalid_format}} =
                 Localize.DateTime.parse("4/3/2024, 22:05", locale: :en, format: format),
               inspect(format)
      end
    end
  end

  describe "a format for each half" do
    # `:date_format` and `:time_format` take the place of the halves of
    # `:format`, and a half with no format is read in any.
    test "reads the date and the time each with its own" do
      assert Localize.DateTime.parse("4/3/2024, 22:05",
               locale: :en,
               date_format: :yMd,
               time_format: :Hm
             ) == {:ok, ~N[2024-04-03 22:05:00]}

      assert Localize.DateTime.parse("3.4.2024 22h05",
               locale: :en,
               date_format: "d.M.y",
               time_format: "HH'h'mm"
             ) == {:ok, ~N[2024-04-03 22:05:00]}

      assert Localize.DateTime.parse("Apr 3, 2024, 22:05", locale: :en, time_format: :Hm) ==
               {:ok, ~N[2024-04-03 22:05:00]}

      assert {:error, %Localize.DateTimeParseError{}} =
               Localize.DateTime.parse("Apr 3, 2024, 10:05 PM", locale: :en, time_format: :Hm)

      assert Localize.DateTime.parse("4/3/24, 22:05",
               locale: :en,
               format: :short,
               time_format: :Hm
             ) ==
               {:ok, ~N[2024-04-03 22:05:00]}
    end
  end

  describe "a semantic skeleton of a date and time" do
    import Localize.DateTime.SemanticSkeleton, only: [semantic: 2]

    # TR35 resolves a semantic skeleton from the locale's own formats at its
    # length: en.xml's short date is "M/d/yy", its medium "MMM d, y" and its
    # long "MMMM d, y", its time to the minute "h:mm a", and the two are
    # joined "{1}, {0}" or, at the long length, "{1} 'at' {0}".
    test "reads each half with its fields" do
      for {length, text} <- [
            short: "4/3/24, 10:05 PM",
            medium: "Apr 3, 2024, 10:05 PM",
            long: "April 3, 2024 at 10:05 PM"
          ] do
        format = semantic("YMDT", length: length, time_precision: :minute)

        assert Localize.DateTime.to_string(~N[2024-04-03 22:05:00], locale: :en, format: format) ==
                 {:ok, text},
               text

        assert Localize.DateTime.parse(text, locale: :en, format: format) ==
                 {:ok, ~N[2024-04-03 22:05:00]},
               text
      end
    end

    # A time precision of optional minutes leaves the minutes out of a time
    # on the hour, en.xml's `h`, "h a", for its `hm`, "h:mm a".
    test "reads a time on the hour written without its minutes" do
      format = semantic("YMDT", length: :short, time_precision: :minute_optional)

      for {value, text} <- [
            {~N[2024-04-03 22:00:00], "4/3/24, 10 PM"},
            {~N[2024-04-03 22:05:00], "4/3/24, 10:05 PM"}
          ] do
        assert Localize.DateTime.to_string(value, locale: :en, format: format) == {:ok, text},
               text

        assert Localize.DateTime.parse(text, locale: :en, format: format) == {:ok, value}, text
      end
    end

    # As with a pattern, the text is read with the skeleton's formats alone:
    # neither another length's format, nor another hour cycle's, nor ISO
    # 8601 is tried.
    test "is the only format the text is read with" do
      format = semantic("YMDT", length: :short, time_precision: :minute)

      for text <- ["April 3, 2024 at 10:05 PM", "4/3/24, 22:05", "2024-04-03T22:05:00"] do
        assert {:error, %Localize.DateTimeParseError{}} =
                 Localize.DateTime.parse(text, locale: :en, format: format),
               text
      end
    end

    # en.xml's time with a zone is "h:mm a z". A date written without its
    # year is of the reference date's year, as it is read alone.
    test "reads a zone with the time, and a date without its year" do
      zoned = semantic("YMDTZ", length: :medium, time_precision: :minute)

      assert Localize.DateTime.parse("Apr 3, 2024, 10:05 PM UTC", locale: :en, format: zoned) ==
               {:ok, ~U[2024-04-03 22:05:00Z]}

      yearless = semantic("MDT", length: :medium, time_precision: :minute)

      assert Localize.DateTime.parse("Apr 3, 10:05 PM",
               locale: :en,
               format: yearless,
               reference_date: ~D[2024-01-01]
             ) == {:ok, ~N[2024-04-03 22:05:00]}
    end
  end

  describe "what the formatter writes" do
    test "reads back with the format it was written with, in each locale" do
      failures =
        for locale <- [:en, :de, :fr, :ja, :mt, :ug, :ko, :th, :ar, :fa, :he, :"zh-Hant", :vi],
            format <- [
              :short,
              :medium,
              :long,
              :full,
              :yMdHm,
              :yMdhm,
              :yMMMdHms,
              :yMEdjm,
              "d/M/y HH:mm:ss",
              "y-MM-dd'T'HH:mm:ss",
              "HH:mm:ss 'on' d MMMM y"
            ],
            {:ok, text} <- [Localize.DateTime.to_string(@naive, locale: locale, format: format)],
            written =
              if(format in [:short, :yMdHm, :yMdhm, :yMEdjm],
                do: %{@naive | second: 0},
                else: @naive
              ),
            Localize.DateTime.parse(text, locale: locale, format: format) != {:ok, written} do
          {locale, format, text}
        end

      assert failures == []
    end
  end
end
