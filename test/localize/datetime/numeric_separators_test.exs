defmodule Localize.DateTime.NumericSeparatorsTest do
  use ExUnit.Case, async: true

  # Separator values are read from the CLDR source, not from library output.
  # cldr-dates-full/main/<locale>/ca-gregorian.json gives, under
  # dateTimeFormats.numericSeparators: en "/" and ":", fi "." and ".",
  # id "/" and ".". TR35 §Elements numericDateSeparator, numericTimeSeparator
  # says the time separator applies to time patterns and the date separator
  # to "date format patterns with numeric months MM and M".

  @date ~D[2024-07-06]
  @time ~T[14:05:09]
  @datetime ~U[2024-07-06 14:05:09Z]

  describe "numeric_separators/2" do
    test "returns the locale's separators" do
      assert Localize.DateTime.numeric_separators(:en) ==
               {:ok, %{numeric_date_separator: "/", numeric_time_separator: ":"}}

      assert Localize.DateTime.numeric_separators(:fi) ==
               {:ok, %{numeric_date_separator: ".", numeric_time_separator: "."}}

      assert Localize.DateTime.numeric_separators(:id) ==
               {:ok, %{numeric_date_separator: "/", numeric_time_separator: "."}}
    end

    test "reads a non-Gregorian calendar" do
      assert {:ok, %{numeric_date_separator: _}} =
               Localize.DateTime.numeric_separators(:en, :islamic)
    end

    test "an unknown locale or calendar returns an error rather than raising" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Localize.DateTime.numeric_separators("nope")

      assert {:error, %Localize.ItemNotFoundError{}} =
               Localize.DateTime.numeric_separators(:en, :nonsense)
    end
  end

  describe "substituting the separators" do
    test "the date separator replaces the locale's in a numeric-month pattern" do
      assert Localize.Date.to_string(@date, format: :yMd, locale: "en") == {:ok, "7/6/2024"}

      assert Localize.Date.to_string(@date,
               format: :yMd,
               locale: "en",
               numeric_date_separator: "-"
             ) == {:ok, "7-6-2024"}
    end

    test "the time separator replaces the locale's in a time pattern" do
      assert Localize.Time.to_string(@time,
               format: "H:mm:ss",
               locale: "en",
               numeric_time_separator: "."
             ) == {:ok, "14.05.09"}
    end

    test "both apply to a combined datetime" do
      assert Localize.DateTime.to_string(@datetime,
               format: :short,
               locale: "en",
               numeric_date_separator: "-",
               numeric_time_separator: "."
             ) == {:ok, "7-6-24, 2.05 PM"}
    end

    test "neither option leaves the pattern untouched" do
      assert Localize.DateTime.to_string(@datetime, format: :short, locale: "en") ==
               {:ok, "7/6/24, 2:05 PM"}
    end
  end

  describe "the two axes stay independent where a locale spells both the same" do
    # fi writes both separators "." — the text alone cannot say which a
    # literal stands for, so each option must change only its own half.
    test "fi renders both as a full stop by default" do
      assert Localize.DateTime.to_string(@datetime, format: :short, locale: "fi") ==
               {:ok, "6.7.2024 klo 14.05"}
    end

    test "changing the date separator leaves the time alone" do
      assert Localize.DateTime.to_string(@datetime,
               format: :short,
               locale: "fi",
               numeric_date_separator: "-"
             ) == {:ok, "6-7-2024 klo 14.05"}
    end

    test "changing the time separator leaves the date alone" do
      assert Localize.DateTime.to_string(@datetime,
               format: :short,
               locale: "fi",
               numeric_time_separator: ":"
             ) == {:ok, "6.7.2024 klo 14:05"}
    end
  end

  describe "intervals" do
    test "both endpoints of an interval are substituted" do
      assert Localize.Interval.to_string(@date, ~D[2024-07-09], format: :short, locale: "en") ==
               {:ok, "7/6/24 – 7/9/24"}

      assert Localize.Interval.to_string(@date, ~D[2024-07-09],
               format: :short,
               locale: "en",
               numeric_date_separator: "-"
             ) == {:ok, "7-6-24 – 7-9-24"}
    end

    # A separator the lexer merges with adjacent literal text is left alone:
    # fi's `yMd` interval pattern for a differing day is "d.–d.M.y", whose
    # first literal tokenizes as ".–" rather than ".". Substitution replaces
    # a literal only when it is exactly the locale's separator, because
    # replacing inside a literal would corrupt patterns that carry the same
    # character as ordinary text.
    test "a separator merged with neighbouring literal text is not substituted" do
      assert Localize.Interval.to_string(@date, ~D[2024-07-09], format: :short, locale: "fi") ==
               {:ok, "6.–9.7.2024"}

      assert Localize.Interval.to_string(@date, ~D[2024-07-09],
               format: :short,
               locale: "fi",
               numeric_date_separator: "-"
             ) == {:ok, "6.–9-7-2024"}
    end
  end

  describe "TR35 limits on where the date separator applies" do
    test "a non-numeric month is left alone" do
      assert Localize.Date.to_string(@date,
               format: :yMMMd,
               locale: "en",
               numeric_date_separator: "-"
             ) == {:ok, "Jul 6, 2024"}
    end

    test "the fractional-second marker is not a time separator" do
      assert Localize.Time.to_string(@time,
               format: "H:mm:ss.SSS",
               locale: "en",
               numeric_time_separator: "-"
             ) == {:ok, "14-05-09.000"}
    end

    test "the substitution follows each locale's own separator" do
      # de writes numeric dates with "." where en writes "/", and both are
      # replaced by the requested string.
      assert Localize.Date.to_string(@date, format: :yMd, locale: "de") == {:ok, "6.7.2024"}

      assert Localize.Date.to_string(@date,
               format: :yMd,
               locale: "de",
               numeric_date_separator: "-"
             ) == {:ok, "6-7-2024"}
    end

    test "the time option does not touch a date separator" do
      assert Localize.Date.to_string(@date,
               format: :yMd,
               locale: "en",
               numeric_time_separator: "-"
             ) == {:ok, "7/6/2024"}
    end
  end
end
