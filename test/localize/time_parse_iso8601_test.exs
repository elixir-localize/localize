defmodule Localize.TimeParseIso8601Test do
  @moduledoc """
  ISO 8601's times, as `Localize.Time.parse/2` reads them alone.

  ISO 8601 writes a time after its time designator, `T`, with its seconds,
  or its minutes and seconds, left out, and with its separators (the
  extended format) or without them (the basic format); the designator may
  be left off a time written between colons. The expected values are the
  hours, minutes and seconds each text spells out. Which texts are times
  follows ISO 8601 and, where a test says so, `Temporal.PlainTime.from` in
  Node 24.9.

  """

  use ExUnit.Case, async: true

  # A time after the designator, the `Time` it is and the fields it does
  # not write. Temporal reads each as the same time.
  @designated [
    {"T10:30:45", ~T[10:30:45], []},
    {"T103045", ~T[10:30:45], []},
    {"T10:30:45.25", ~T[10:30:45.25], []},
    {"T103045,5", ~T[10:30:45.5], []},
    {"T10:30", ~T[10:30:00], [:second]},
    {"T1030", ~T[10:30:00], [:second]},
    {"T10", ~T[10:00:00], [:minute, :second]},
    {"t10:30", ~T[10:30:00], [:second]}
  ]

  # An offset and the zone fields a map carries for it. `z` is RFC 3339's,
  # and U+2212 the minus sign ISO 8601 writes.
  @offsets [
    {"Z", 0, "UTC"},
    {"z", 0, "UTC"},
    {"+02:00", 7200, "+02:00"},
    {"+0200", 7200, "+02:00"},
    {"+02", 7200, "+02:00"},
    {"-05:30", -19_800, "-05:30"},
    {"−05:30", -19_800, "-05:30"}
  ]

  defp fields(%Time{} = time, unwritten) do
    time
    |> Map.take([:hour, :minute, :second])
    |> Map.merge(fraction(time))
    |> Map.drop(unwritten)
  end

  defp fraction(%Time{microsecond: {_microseconds, 0}}), do: %{}
  defp fraction(%Time{microsecond: microsecond}), do: %{microsecond: microsecond}

  describe "a time after the designator T" do
    test "is read in every form ISO 8601 writes one" do
      for {text, time, _unwritten} <- @designated do
        assert Localize.Time.parse(text, locale: :en) == {:ok, time}, text
      end
    end

    # A map holds the fields the text gave: a time without its seconds has
    # none, as the locale's "10:30" has none.
    test "as a map leaves out the seconds and the minutes it does not write" do
      for {text, time, unwritten} <- @designated do
        assert Localize.Time.parse(text, locale: :en, as: :map) == {:ok, fields(time, unwritten)},
               text
      end

      assert Localize.Time.parse("T10:30", locale: :en, as: :map) ==
               Localize.Time.parse("10:30", locale: :en, as: :map)
    end

    # A `Time` has no zone, so the struct is the time as written; the map
    # carries the offset as a `DateTime` would, a fixed offset under
    # `Etc/UTC`.
    test "keeps the offset written after it" do
      for {text, time, unwritten} <- @designated,
          {offset_text, offset, abbreviation} <- @offsets do
        input = text <> offset_text
        assert Localize.Time.parse(input, locale: :en) == {:ok, time}, input

        zone = %{
          time_zone: "Etc/UTC",
          utc_offset: offset,
          std_offset: 0,
          zone_abbr: abbreviation
        }

        assert Localize.Time.parse(input, locale: :en, as: :map) ==
                 {:ok, Map.merge(fields(time, unwritten), zone)},
               input
      end
    end

    # ISO 8601 is no locale's format, so every locale reads it alike.
    test "is read alike in every locale" do
      for locale <- [:de, :fi, :ja, :ar, :th, :"fr-CA"],
          {text, time, _unwritten} <- @designated do
        assert Localize.Time.parse(text, locale: locale) == {:ok, time}, "#{text} in #{locale}"
      end
    end

    # A format names how the text was written, and ISO 8601 is then not
    # tried.
    test "is not read where a format is given" do
      for text <- ["T10:30", "T1030", "T10:30:45"] do
        assert {:error, %Localize.TimeParseError{}} =
                 Localize.Time.parse(text, locale: :en, format: :short),
               text
      end
    end
  end

  describe "a time between colons without the designator" do
    # ISO 8601 lets the designator be left off a time between colons, so
    # "10:30" is its hour and minute in every locale. CLDR's `Hm` is "H.mm"
    # in `fi`, "HH.mm" in `da`, "HH 'h' mm" in `fr-CA` and "HH:mm 'ч'." in
    # `bg`, so none of their formats reads it.
    test "is read in a locale whose formats write a time another way" do
      for locale <- [:fi, :da, :"fr-CA", :bg, :"en-DK", :hsb] do
        assert Localize.Time.parse("10:30", locale: locale) == {:ok, ~T[10:30:00]}, "#{locale}"

        assert Localize.Time.parse("10:30", locale: locale, as: :map) ==
                 {:ok, %{hour: 10, minute: 30}},
               "#{locale}"

        assert Localize.Time.parse("10:30+02:00", locale: locale, as: :map) ==
                 {:ok,
                  %{
                    hour: 10,
                    minute: 30,
                    time_zone: "Etc/UTC",
                    utc_offset: 7200,
                    std_offset: 0,
                    zone_abbr: "+02:00"
                  }},
               "#{locale}"
      end
    end

    # `fi` writes a date "d.M.y" (CLDR's short and medium date), and the
    # time beside it may be ISO 8601's.
    test "is the time of a date and time there too" do
      assert Localize.DateTime.parse("16.6.2026 10:30", locale: :fi) ==
               {:ok, ~N[2026-06-16 10:30:00]}
    end

    # RFC 3339's `z` and ISO 8601's own minus sign after a whole time.
    test "takes z for Z and U+2212 for a hyphen" do
      assert Localize.Time.parse("10:30:45z", locale: :en, as: :map) ==
               Localize.Time.parse("10:30:45Z", locale: :en, as: :map)

      assert Localize.Time.parse("10:30:45−05:30", locale: :en, as: :map) ==
               Localize.Time.parse("10:30:45-05:30", locale: :en, as: :map)
    end
  end

  describe "digits alone" do
    # Without the designator, digits are no time: the time parser also
    # reads the time of a date and time split at a space, where "2026" after
    # "June 16" would be 20:26. Temporal reads "103045" and refuses "1030",
    # which is as much a month and a day.
    test "are no time without the designator" do
      for text <- ["103045", "1030", "103045Z", "1030+0200"] do
        assert {:error, %Localize.TimeParseError{}} = Localize.Time.parse(text, locale: :en), text
      end

      assert {:error, %Localize.DateTimeParseError{}} =
               Localize.DateTime.parse("June 16 2026", locale: :en)
    end

    # An hour alone is the locale's to read: `en` has a format that does
    # (CLDR's `H`, "HH"), and `de`'s is "HH 'Uhr'".
    test "of an hour are the locale's" do
      assert Localize.Time.parse("10", locale: :en) == {:ok, ~T[10:00:00]}
      assert {:error, %Localize.TimeParseError{}} = Localize.Time.parse("10", locale: :de)
      assert Localize.Time.parse("T10", locale: :de) == {:ok, ~T[10:00:00]}
    end
  end

  describe "text that is no ISO 8601 time" do
    # Temporal refuses each but an offset of "-00:00", which ISO 8601
    # forbids and Elixir does not read, and a second of 60, which Temporal
    # reads as 59.
    test "is an error" do
      for text <- [
            # Nothing after the designator, or two of them.
            "T",
            "TT10:30",
            "T 10:30",
            # A digit missing.
            "T1",
            "T103",
            "T10:3",
            "T10:30:4",
            "T10:30:45.",
            # Separators in part of a time.
            "T10:3045",
            "T1030:45",
            # No time of day.
            "T24:00",
            "T25",
            "T10:60",
            "T1060",
            "T23:59:60",
            # A fraction of a minute or of an hour, which ISO 8601 writes
            # and neither Elixir nor Temporal reads.
            "T10:30,5",
            "T10,5",
            # No offset.
            "T10:30+2",
            "T10:30+24:00",
            "T10:30+02:60",
            "T10:30-00:00"
          ] do
        assert {:error, %Localize.TimeParseError{}} = Localize.Time.parse(text, locale: :en), text
      end
    end

    # Whatever is given is an error and never a raise.
    test "is an error for bytes that are no text and for a string of any length" do
      for input <- [
            <<?T, 49, 255>>,
            "",
            "T" <> String.duplicate("1", 5000),
            String.duplicate("T10:30", 2000)
          ] do
        assert {:error, %_exception{}} = Localize.Time.parse(input, locale: :en)
        assert {:error, %_exception{}} = Localize.Time.parse(input, locale: :en, as: :map)
        assert Localize.Time.Parser.extended_iso8601(String.replace_invalid(input)) == :error
      end
    end
  end

  describe "Localize.DateTime.Parser.parse/2" do
    test "reads a time after the designator as a time" do
      assert Localize.DateTime.Parser.parse("T10:30", locale: :en) == {:ok, ~T[10:30:00]}
      assert Localize.DateTime.Parser.parse("T103045", locale: :en) == {:ok, ~T[10:30:45]}
      assert Localize.DateTime.Parser.parse("10:30", locale: :fi) == {:ok, ~T[10:30:00]}
    end
  end
end
