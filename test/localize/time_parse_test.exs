defmodule Localize.TimeParseTest do
  @moduledoc """
  A time parses back as the formatter writes it, whatever order the
  locale's patterns arrive in.

  The expected times are ICU4C 78.3's readings of the same text with the
  pattern the locale writes it in, except where a test says otherwise.

  """

  use ExUnit.Case, async: true

  describe "a day period" do
    # `ms` writes its short time "h:mm a" and names its day periods "PG" and
    # "PTG", which a pattern with a zone would read as a zone.
    test "is read as a day period, not a zone" do
      assert Localize.Time.parse("11:59 PTG", locale: :ms) == {:ok, ~T[23:59:00]}
      assert Localize.Time.parse("12:30 PG", locale: :ms) == {:ok, ~T[00:30:00]}

      assert Localize.Time.parse("11:59 PTG", locale: :ms, as: :map) ==
               {:ok, %{hour: 23, minute: 59}}

      assert Localize.Time.parse("12:30:00 BN", locale: :ku) == {:ok, ~T[00:30:00]}
      assert Localize.Time.parse("11:59:59 UT", locale: :ebu) == {:ok, ~T[23:59:59]}
    end

    # `sd-Deva` names no flexible day periods, and its "h:mm:ss a" is read
    # before a pattern with one.
    test "is read by the pattern that writes it" do
      assert Localize.Time.parse("11:59:59 PM", locale: :"sd-Deva") == {:ok, ~T[23:59:59]}
    end
  end

  describe "a flexible day period" do
    # `fr` calls morning1 (04:00–12:00) and night1 (00:00–04:00) "matin"
    # alike, so the name is the period the hour falls in.
    test "is the period of that name its hour falls in" do
      assert Localize.Time.parse("9:05:00 matin", locale: :fr) == {:ok, ~T[09:05:00]}
      assert Localize.Time.parse("11:59:00 matin", locale: :fr) == {:ok, ~T[11:59:00]}
      assert Localize.Time.parse("2:00:00 du matin", locale: :fr) == {:ok, ~T[02:00:00]}
      assert Localize.Time.parse("1:45 mchana", locale: :sw) == {:ok, ~T[13:45:00]}
    end

    # `gl` calls midnight and night1 (21:00–24:00) "da noite".
    test "is midnight or noon at its hour" do
      assert Localize.Time.parse("12 da noite", locale: :gl) == {:ok, ~T[00:00:00]}
    end

    # TR35: where a locale gives a flexible day period no name, formatting
    # falls back to its AM and PM names. `oc` has no day-period rules, and
    # ICU4C writes 23:59 in its `Bhm` pattern "h:mm B" as "11:59 PM" but does
    # not read that back.
    test "is read as AM or PM where the locale names none" do
      assert Localize.Time.to_string(~T[23:59:00], locale: :oc, format: :Bhm) ==
               {:ok, "11:59 PM"}

      assert Localize.Time.parse("11:59 PM", locale: :oc) == {:ok, ~T[23:59:00]}
    end
  end

  # TR35 gives each hour field its hours: `h` "Hour [1-12]", `H` "[0-23]",
  # `K` "[0-11]" and `k` "[1-24]", and its parsing notes take a number
  # beyond a field's range for no value of it ("a number larger than the
  # largest month cannot be a month"). An hour is read where its field has
  # it, and nowhere else.
  defp read(text, pattern), do: Localize.Time.parse(text, locale: :en, format: pattern)

  describe "an hour" do
    test "of a 12-hour field with a day period is one that field has" do
      for {text, expected} <- [
            {"1:30 AM", ~T[01:30:00]},
            {"12:30 AM", ~T[00:30:00]},
            {"12:30 PM", ~T[12:30:00]},
            {"11:30 PM", ~T[23:30:00]}
          ] do
        assert read(text, "h:mm a") == {:ok, expected}, text
      end

      # `h`'s hours begin at 1: its 0 was read as its 12, ICU's reading when
      # it is lenient.
      for text <- [
            "0:30 AM",
            "0:30 PM",
            "13:30 AM",
            "13:30 PM",
            "23:30 PM",
            "24:00 PM",
            "45:30 PM",
            "99:59 AM"
          ] do
        assert {:error, %Localize.TimeParseError{}} = read(text, "h:mm a"), text
      end
    end

    # A pattern of a 12-hour time with no day period, as `fr-CM`'s and
    # `bal-Latn`'s `hm` is ("h:mm" in CLDR's `fr_CM.xml`), reads an hour
    # before noon.
    test "of a 12-hour field with no day period is one that field has" do
      assert read("1:30", "h:mm") == {:ok, ~T[01:30:00]}
      assert read("12:30", "h:mm") == {:ok, ~T[00:30:00]}

      for text <- ["0:30", "13:30", "24:00", "45:30", "99:59"] do
        assert {:error, %Localize.TimeParseError{}} = read(text, "h:mm"), text
      end
    end

    # `K` counts its hours from 0 to 11, so its 12 is no hour of it before
    # noon or after. Before noon it was read as twelve hours on from that
    # 0, ICU's reading when it is lenient.
    test "of a field counted from 0 is one that field has" do
      for {text, expected} <- [
            {"0:30 AM", ~T[00:30:00]},
            {"0:30 PM", ~T[12:30:00]},
            {"11:30 AM", ~T[11:30:00]},
            {"11:30 PM", ~T[23:30:00]}
          ] do
        assert read(text, "K:mm a") == {:ok, expected}, text
      end

      for text <- ["12:30 AM", "12:30 PM", "13:30 AM", "13:30 PM", "45:30 AM"] do
        assert {:error, %Localize.TimeParseError{}} = read(text, "K:mm a"), text
      end
    end

    # TR35's range for `k` starts at 1, and its 24 is midnight. ICU reads
    # its 0 as midnight, lenient or not.
    test "of a 24-hour field is one that field has" do
      assert read("0:30", "H:mm") == {:ok, ~T[00:30:00]}
      assert read("23:30", "H:mm") == {:ok, ~T[23:30:00]}
      assert read("1:30", "k:mm") == {:ok, ~T[01:30:00]}
      assert read("24:30", "k:mm") == {:ok, ~T[00:30:00]}

      for {text, pattern} <- [
            {"24:00", "H:mm"},
            {"24:30", "H:mm"},
            {"45:30", "H:mm"},
            {"0:30", "k:mm"},
            {"25:30", "k:mm"},
            {"45:30", "k:mm"}
          ] do
        assert {:error, %Localize.TimeParseError{}} = read(text, pattern), "#{text} #{pattern}"
      end
    end

    # TR35: a 24-hour pattern "should not include fields with day period
    # characters", and in parsing "the dayperiod is checked for consistency
    # with the hour". CLDR 49's `Hmsv` for `ksh` is "H:mm:ss a v" all the
    # same, and read four in the afternoon, "4:00:00 n.M.", as 04:00. A
    # 24-hour hour its day period does not hold is no time. ICU4C 78.3 is no
    # guide here: lenient or not, it reads "4:00 PM" and "16:00 PM" alike as
    # noon, and "16:00 AM" as midnight.
    test "of a 24-hour field agrees with a day period beside it" do
      for {text, pattern, expected} <- [
            {"16:00 PM", "H:mm a", ~T[16:00:00]},
            {"12:30 PM", "H:mm a", ~T[12:30:00]},
            {"4:00 AM", "H:mm a", ~T[04:00:00]},
            {"0:30 AM", "H:mm a", ~T[00:30:00]},
            {"13:00 PM", "k:mm a", ~T[13:00:00]},
            {"24:30 AM", "k:mm a", ~T[00:30:00]},
            {"4:00", "H:mm", ~T[04:00:00]}
          ] do
        assert read(text, pattern) == {:ok, expected}, "#{text} #{pattern}"
      end

      for {text, pattern} <- [
            {"4:00 PM", "H:mm a"},
            {"16:00 AM", "H:mm a"},
            {"12:30 AM", "H:mm a"},
            {"1:00 PM", "k:mm a"},
            {"13:00 AM", "k:mm a"}
          ] do
        assert {:error, %Localize.TimeParseError{}} = read(text, pattern), "#{text} #{pattern}"
      end
    end

    # Read in any of a locale's formats, an hour beyond a field's range is
    # no time either: "45:30 PM" was 21:30 and "13:30 AM" 01:30 wherever a
    # locale has a 12-hour pattern, and "45:30" was 09:30 in `fr-CM`.
    test "beyond every field's range is no time in any of a locale's formats" do
      for text <- [
            "13:30 AM",
            "13:30 PM",
            "13 PM",
            "45:30 PM",
            "24:00 PM",
            "13 in the morning",
            "13 in the afternoon"
          ] do
        assert {:error, %Localize.TimeParseError{}} = Localize.Time.parse(text, locale: :en), text

        assert {:error, %Localize.TimeParseError{}} =
                 Localize.Time.parse(text, locale: :en, as: :map),
               text
      end

      for locale <- [:"fr-CM", :"bal-Latn"], text <- ["45:30", "99:59", "24:00", "25", "45"] do
        assert {:error, %Localize.TimeParseError{}} = Localize.Time.parse(text, locale: locale),
               "#{text} in #{locale}"
      end

      assert Localize.Time.parse("13:30", locale: :"fr-CM") == {:ok, ~T[13:30:00]}
      assert Localize.Time.parse("12:30", locale: :"fr-CM") == {:ok, ~T[12:30:00]}

      assert {:error, %Localize.DateTimeParseError{}} =
               Localize.DateTime.parse("Jun 16, 2026, 13:30 PM", locale: :en)
    end

    # `ja` writes a 12-hour time from 0, "aK:mm" (CLDR's `hm`), and `zh` a
    # day period before the hour.
    test "beyond its range is no time beside a day period of another script" do
      assert Localize.Time.parse("午前0:30", locale: :ja) == {:ok, ~T[00:30:00]}
      assert Localize.Time.parse("午後0:30", locale: :ja) == {:ok, ~T[12:30:00]}
      assert Localize.Time.parse("午後11:30", locale: :ja) == {:ok, ~T[23:30:00]}

      for text <- ["午前12:30", "午前13:30", "午後13:30", "午後12:30", "午後45:30"] do
        assert {:error, %Localize.TimeParseError{}} = Localize.Time.parse(text, locale: :ja), text
      end

      assert Localize.Time.parse("下午1:30", locale: :zh) == {:ok, ~T[13:30:00]}

      for text <- ["下午13:30", "上午13:30"] do
        assert {:error, %Localize.TimeParseError{}} = Localize.Time.parse(text, locale: :zh), text
      end
    end
  end
end
