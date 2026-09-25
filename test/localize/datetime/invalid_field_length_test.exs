defmodule Localize.DateTime.InvalidFieldLengthTest do
  use ExUnit.Case, async: true

  # TR35's Date Field Symbol Table (tr35-dates.md) lists the lengths each
  # pattern character takes, and its notes make any other length invalid.
  # TR35's Handling Invalid Patterns (tr35.md) formats an invalid field as
  # U+FFFD and rejects a pattern holding a character it does not define. The
  # lengths here are transcribed from the CLDR 49 table, not from Localize.
  @listed_lengths %{
    "G" => 1..5,
    "U" => 1..5,
    "Q" => 1..5,
    "q" => 1..5,
    "M" => 1..5,
    "L" => 1..5,
    "l" => [1],
    "w" => 1..2,
    "W" => [1],
    "d" => 1..3,
    "D" => 1..3,
    "F" => [1],
    "E" => 1..6,
    "e" => 1..6,
    "c" => 1..6,
    "a" => 1..5,
    "b" => 1..5,
    "B" => 1..5,
    "h" => 1..2,
    "H" => 1..2,
    "K" => 1..2,
    "k" => 1..2,
    "m" => 1..2,
    "s" => 1..2,
    "z" => 1..4,
    "Z" => 1..5,
    "O" => [1, 4],
    "v" => [1, 4],
    "V" => 1..4,
    "X" => 1..5,
    "x" => 1..5
  }

  # The characters the table lists at any length.
  @any_length ~w(y Y u r g S A)

  # The letters the table does not define, and the skeleton symbols `j`, `J`
  # and `C`, which TR35 says must not occur in patterns.
  @not_in_patterns ~w(f i n o p t I N P R T j J C)

  @longest_checked 8

  setup_all do
    {:ok, datetime: DateTime.new!(~D[2026-09-06], ~T[07:05:03.123], "America/New_York")}
  end

  test "the lists account for every ASCII letter" do
    letters = Map.keys(@listed_lengths) ++ @any_length ++ @not_in_patterns
    ascii_letters = Enum.map(Enum.concat(?A..?Z, ?a..?z), &<<&1>>)

    assert Enum.sort(letters) == Enum.sort(ascii_letters)
  end

  describe "a pattern field" do
    test "formats at every length the table lists", %{datetime: datetime} do
      failures =
        for {letter, lengths} <- @listed_lengths,
            length <- lengths,
            pattern = String.duplicate(letter, length),
            result = format(datetime, pattern),
            not formatted?(result),
            do: {pattern, result}

      assert failures == []
    end

    test "formats as U+FFFD at every other length", %{datetime: datetime} do
      failures =
        for {letter, lengths} <- @listed_lengths,
            length <- 1..@longest_checked,
            length not in lengths,
            pattern = String.duplicate(letter, length),
            result = format(datetime, pattern),
            result != {:ok, "�"},
            do: {pattern, result}

      assert failures == []
    end

    test "formats at any length where the table sets no limit", %{datetime: datetime} do
      failures =
        for letter <- @any_length,
            length <- 1..@longest_checked,
            pattern = String.duplicate(letter, length),
            result = format(datetime, pattern),
            not formatted?(result),
            do: {pattern, result}

      assert failures == []
    end

    test "is an error when the letter has no meaning in a pattern", %{datetime: datetime} do
      for letter <- @not_in_patterns do
        assert {:error, %Localize.DateTimeFormatError{reason: :tokenize_error}} =
                 format(datetime, letter)
      end
    end
  end

  describe "an invalid field" do
    test "leaves the rest of the pattern formatted", %{datetime: datetime} do
      assert format(datetime, "EEEE, MMMM dddd, y") == {:ok, "Sunday, September �, 2026"}
    end

    test "needs nothing from the value" do
      # A date has no hour, yet `HHH` is invalid before it is unformattable,
      # while a valid `HH` still asks for the hour.
      assert Localize.Date.to_string(~D[2026-09-06], format: "d HHH", locale: :en) ==
               {:ok, "6 �"}

      assert {:error, %Localize.DateTimeInvalidInputError{missing: [:hour]}} =
               Localize.Date.to_string(~D[2026-09-06], format: "d HH", locale: :en)
    end

    test "keeps its field's part type" do
      assert Localize.Date.to_parts(~D[2026-09-06], format: "dddd MMM", locale: :en) ==
               {:ok,
                [
                  %{type: :day, value: "�"},
                  %{type: :literal, value: " "},
                  %{type: :month, value: "Sep"}
                ]}
    end

    test "formats in each endpoint of a time interval's pattern" do
      assert Localize.Interval.to_string(~T[07:00:00], ~T[09:30:00],
               format: "HHH:mm",
               locale: :en
             ) ==
               {:ok, "�:00 – �:30"}
    end
  end

  describe "a skeleton" do
    # CLDR's skeleton test data maps `hmszzzzz` to "h:mm:ss a zzzzz" in `en`:
    # matching carries the requested width over, so the pattern it produces
    # holds an invalid field.
    test "carries an invalid width into its pattern", %{datetime: datetime} do
      assert Localize.DateTime.to_string(datetime, format: :hmszzzzz, locale: :en) ==
               {:ok, "7:05:03 AM �"}
    end

    # TR35's matching never adjusts hour, minute and second widths, so a
    # skeleton cannot pass an invalid one on.
    test "keeps the matched pattern's hour, minute and second widths" do
      assert Localize.Time.to_string(~T[07:05:03], format: :HHHmmmsss, locale: :en) ==
               {:ok, "07:05:03"}
    end
  end

  defp format(datetime, pattern) do
    Localize.DateTime.to_string(datetime, format: pattern, locale: :en)
  end

  defp formatted?({:ok, string}), do: not String.contains?(string, "�")
  defp formatted?(_error), do: false
end
