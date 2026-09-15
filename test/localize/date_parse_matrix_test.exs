defmodule Localize.DateParseMatrixTest do
  @moduledoc """
  Dates formatted by ICU4C parse back to the date they were formatted from.

  `test/support/data/date_parse_icu_expected.tsv` holds the 21st of every
  month of 2024 in the 42 test locales ICU4C 78.3 carries data for, formatted
  in the Gregorian calendar with the full, long, medium and short date formats
  and with the `yMMMd`, `yMMMMd`, `yMMMEd`, `yMMMMEEEEd`, `yMd`, `yMMM`,
  `yMMMM`, `yM` and `GyMMMd` skeletons. Between them they carry eras, weekdays
  before and after the date, month names of both contexts and every width,
  and native digits. A format with a day parses to that date. A format without
  one has no `t:Date.t/0`, so it parses with `as: :map` to its month and year,
  as the date and time formatting guide documents.

  ICU4C 78.3 carries CLDR 48. The rows whose spelling CLDR 49 changed are left
  out of the sweep, and the CLDR 49 spelling of each is parsed instead.

  """

  use ExUnit.Case, async: true

  @fixture Path.join([__DIR__, "..", "support", "data", "date_parse_icu_expected.tsv"])
  @month_and_year ["yMMM", "yMMMM", "yM"]

  test "each date ICU4C formats parses back to its date" do
    rows =
      @fixture
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))
      |> Enum.map(&row/1)
      |> Enum.reject(&cldr_49_change?/1)

    failures =
      rows
      |> Task.async_stream(&parse_failure/1, timeout: 60_000, ordered: false)
      |> Enum.flat_map(fn {:ok, failure} -> List.wrap(failure) end)

    assert length(rows) == 6_443
    assert failures == [], inspect(Enum.take(failures, 20), pretty: true, limit: 12)
  end

  test "the CLDR 49 spellings of the rows CLDR 49 changed parse" do
    assert Localize.Date.parse("21 sep 2024", locale: "es-AR") == {:ok, ~D[2024-09-21]}

    assert Localize.Date.parse("۲۱ ژانویه ۲۰۲۴",
             locale: :fa
           ) == {:ok, ~D[2024-01-21]}

    assert Localize.Date.parse("2024/1", locale: :ko, as: :map) ==
             {:ok, %{calendar: Calendar.ISO, month: 1, year: 2024}}

    assert Localize.Date.parse("21.01.2024", locale: :ky) == {:ok, ~D[2024-01-21]}

    year = "၂၀၂၄"
    day = "၂၁"
    sunday = "တနင်္ဂနွေ"
    january = "ဇန်နဝါရီ"
    jan = "ဇန်"

    assert Localize.Date.parse("#{year} #{january} #{day}၊ #{sunday}", locale: :my) ==
             {:ok, ~D[2024-01-21]}

    assert Localize.Date.parse("#{year} #{jan} #{day}၊ #{sunday}", locale: :my) ==
             {:ok, ~D[2024-01-21]}

    assert Localize.Date.parse("အေဒီ #{year} #{jan} #{day}", locale: :my) ==
             {:ok, ~D[2024-01-21]}

    assert Localize.Date.parse(
             "২১ জানু, ২০২৪ খ্রি.",
             locale: :bn
           ) == {:ok, ~D[2024-01-21]}
  end

  defp row(line) do
    [_mode, locale, format, year, month, day, formatted | _pattern] = String.split(line, "\t")

    %{
      locale: locale,
      format: format,
      date: Date.new!(String.to_integer(year), String.to_integer(month), String.to_integer(day)),
      string: decode(formatted)
    }
  end

  defp decode(string) do
    Regex.replace(~r/\\u\{([0-9a-f]+)\}/, string, fn _match, hex ->
      <<String.to_integer(hex, 16)::utf8>>
    end)
  end

  defp parse_failure(%{format: format, date: date} = row) when format in @month_and_year do
    expected = {:ok, %{calendar: Calendar.ISO, month: date.month, year: date.year}}
    compare(row, Localize.Date.parse(row.string, locale: row.locale, as: :map), expected)
  end

  defp parse_failure(row) do
    compare(row, Localize.Date.parse(row.string, locale: row.locale), {:ok, row.date})
  end

  defp compare(_row, expected, expected), do: nil
  defp compare(row, result, _expected), do: {row.locale, row.format, row.string, result}

  # The CLDR 48 spellings in ICU4C 78.3 that CLDR 49 changed:
  #
  # * es-AR abbreviates September "sept" in CLDR 48 and "sep" in CLDR 49.
  #
  # * fa's format-context month names that end in "ه" add U+0654 in CLDR 48
  #   and not in CLDR 49.
  #
  # * ko's `yM` is "y. M." in CLDR 48 and "y/M" in CLDR 49.
  #
  # * ky's `yMd` is "y-dd-MM" in CLDR 48 and "dd.MM.y" in CLDR 49.
  #
  # * my's weekday formats are "y MMMM d EEEE" and "y MMM d E" in CLDR 48 and
  #   put "၊" before the weekday in CLDR 49.
  #
  # * my's abbreviated era 1 is U+1021 U+1012 U+1031 U+102E in CLDR 48 and
  #   U+1021 U+1031 U+1012 U+102E in CLDR 49.
  #
  # * bn's abbreviated era 1 is "খৃষ্টাব্দ" in CLDR 48 and "খ্রি." in CLDR 49.
  defp cldr_49_change?(%{locale: "es-AR", date: %{month: 9}, string: string}),
    do: String.contains?(string, "sept ")

  defp cldr_49_change?(%{locale: "fa", string: string}),
    do: String.contains?(string, "هٔ")

  defp cldr_49_change?(%{locale: "ko", format: "yM"}), do: true
  defp cldr_49_change?(%{locale: "ky", format: "yMd"}), do: true

  defp cldr_49_change?(%{locale: "my", format: format}),
    do: format in ["full", "yMMMEd", "yMMMMEEEEd", "GyMMMd"]

  defp cldr_49_change?(%{locale: "bn", format: "GyMMMd"}), do: true
  defp cldr_49_change?(_row), do: false
end
