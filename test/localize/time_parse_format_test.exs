defmodule Localize.TimeParseFormatTest do
  @moduledoc """
  A time is read with the format it was written with when `:format` names
  it, as `Localize.Time.to_string/2` takes it: a standard format, a
  skeleton or a pattern, as `Localize.Date.parse/2` reads a date (user,
  2026-10-04: "Let parse/2 take the format the text was written with").

  The patterns are CLDR's, from `common/main` at the pinned revision: `en`
  writes its short time "h:mm a", medium "h:mm:ss a", long "h:mm:ss a z"
  and full "h:mm:ss a zzzz", `Hm` "HH:mm" and `hm` "h:mm a"; `ja`'s full
  time is "H時mm分ss秒 zzzz" and its `Hms` "H:mm:ss".

  """

  use ExUnit.Case, async: true

  describe "the format the text was written with" do
    test "is a standard format, a skeleton or a pattern" do
      for {format, text, time} <- [
            {:short, "10:30 PM", ~T[22:30:00]},
            {:medium, "10:30:45 PM", ~T[22:30:45]},
            {:Hm, "22:30", ~T[22:30:00]},
            {:hm, "10:30 PM", ~T[22:30:00]},
            {:Hms, "22:30:45", ~T[22:30:45]},
            {"HH'h'mm", "22h30", ~T[22:30:00]},
            {"HH.mm.ss", "22.30.45", ~T[22:30:45]},
            {"HH:mm:ss.SSS", "22:30:45.250", ~T[22:30:45.250]}
          ] do
        assert Localize.Time.to_string(time, locale: :en, format: format, prefer: :ascii) ==
                 {:ok, text},
               inspect(format)

        assert Localize.Time.parse(text, locale: :en, format: format) == {:ok, time},
               inspect(format)
      end
    end

    # The text is read with that format and no other: ISO 8601 and the
    # locale's other formats are not tried.
    test "is the only format the text is read with" do
      for text <- ["10:30:45 PM", "22:30", "22:30:45"] do
        assert {:error, %Localize.TimeParseError{format: :short} = error} =
                 Localize.Time.parse(text, locale: :en, format: :short)

        assert Exception.message(error) =~ "written with the format :short"
      end

      assert Localize.Time.parse("22:30", locale: :en) == {:ok, ~T[22:30:00]}
      assert Localize.Time.parse("22:30", locale: :en, format: nil) == {:ok, ~T[22:30:00]}
    end

    test "gives the fields the text holds as a map" do
      assert Localize.Time.parse("22h30", locale: :en, format: "HH'h'mm", as: :map) ==
               {:ok, %{hour: 22, minute: 30}}
    end

    test "reads back what the formatter writes with it, in each locale and format" do
      failures =
        for locale <- [:en, :de, :fr, :ja, :ko, :th, :ar, :bn, :fa, :"zh-Hant", :bg, :am],
            format <- [:short, :medium, :long, :full, :Hm, :hm, :Hms, :hms],
            time <- [~T[22:05:09], ~T[00:30:00]],
            {:ok, text} <- [Localize.Time.to_string(time, locale: locale, format: format)],
            written = if(format in [:short, :Hm, :hm], do: %{time | second: 0}, else: time),
            Localize.Time.parse(text, locale: locale, format: format) != {:ok, written} do
          {locale, format, time, text}
        end

      assert failures == []
    end
  end

  # TR35's time precision of optional minutes leaves the minutes out of a
  # time on the hour: en.xml's `h` is "h a" and its `hm` "h:mm a", so 14:00
  # is "2 PM" and 14:30 "2:30 PM". The formatter chooses between them by the
  # time it writes, which the reader does not have, so it reads either.
  describe "a semantic skeleton of optional minutes" do
    import Localize.DateTime.SemanticSkeleton, only: [semantic: 2]

    test "reads a time on the hour and a time with its minutes" do
      format = semantic("T", time_precision: :minute_optional)

      for {time, text} <- [{~T[14:00:00], "2 PM"}, {~T[14:30:00], "2:30 PM"}] do
        assert Localize.Time.to_string(time, locale: :en, format: format) == {:ok, text}, text
        assert Localize.Time.parse(text, locale: :en, format: format) == {:ok, time}, text
      end
    end

    test "is still the only format the text is read with" do
      format = semantic("T", time_precision: :minute_optional)

      for text <- ["2:30:45 PM", "14:30", "14"] do
        assert {:error, %Localize.TimeParseError{}} =
                 Localize.Time.parse(text, locale: :en, format: format),
               text
      end
    end
  end

  describe "a long or a full format" do
    # Both formats end in a zone. A time with no zone is written with the
    # format's other fields, as the locale writes them alone, and a time in
    # a zone with the whole pattern; the format reads either.
    test "reads a time with its zone and a time with none" do
      assert Localize.Time.parse("10:30:45 PM", locale: :en, format: :long) ==
               {:ok, ~T[22:30:45]}

      assert Localize.Time.parse("10:30:45 PM UTC", locale: :en, format: :long) ==
               {:ok, ~T[22:30:45]}

      assert Localize.Time.parse("10:30:00", locale: :ja, format: :full) == {:ok, ~T[10:30:00]}

      assert Localize.Time.parse("10時30分00秒 日本標準時", locale: :ja, format: :full) ==
               {:ok, ~T[10:30:00]}

      assert {:ok, %{hour: 22, minute: 30, second: 45, time_zone: "Etc/UTC", utc_offset: 0}} =
               Localize.Time.parse("10:30:45 PM UTC", locale: :en, format: :long, as: :map)
    end
  end

  describe "a format that is not one" do
    # A format is one the formatter writes a time with. A quote left open
    # and a letter that is no pattern field fail to tokenize, a field longer
    # than any format writes is written as U+FFFD, and a date's field needs
    # a date.
    test "is an error that says so, and never raises" do
      for format <- ["'open", "HH:mm j", "HHHHH", "mmm", "ssss"] do
        assert {:error, %Localize.DateTimeFormatError{}} =
                 Localize.Time.parse("22:30", locale: :en, format: format),
               inspect(format)
      end

      for format <- ["d/M/y", :yMd] do
        assert {:error, %Localize.DateTimeInvalidInputError{}} =
                 Localize.Time.parse("22:30", locale: :en, format: format),
               inspect(format)
      end

      assert {:error, %Localize.DateTimeUnresolvedFormatError{}} =
               Localize.Time.parse("22:30", locale: :en, format: :nosuchskeleton)

      for format <- [123, 1.5, {:a, :b}, ["Hm"], %{}] do
        assert {:error, %Localize.DateTimeFormatError{reason: :invalid_format}} =
                 Localize.Time.parse("22:30", locale: :en, format: format),
               inspect(format)
      end

      for format <- ["", String.duplicate("'x'", 2000)] do
        assert {:error, %Localize.TimeParseError{}} =
                 Localize.Time.parse("22:30", locale: :en, format: format)
      end
    end
  end
end
