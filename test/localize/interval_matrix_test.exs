defmodule Localize.IntervalMatrixTest do
  @moduledoc """
  Date, time and datetime intervals across `:fields`, `:format`, locales and
  the shapes of difference TR35 §Interval Formats distinguishes: none, a
  day, a month, a year boundary, a year, an hour on one side of noon, across
  noon, and a minute.

  Expected values come from ICU4J 73's `DateIntervalFormat` for Gregorian
  dates in UTC (`test/support/data/interval_icu_expected.tsv`), except where
  CLDR 49 has changed the locale data since ICU 73's CLDR 43; those cases
  are checked here against the CLDR 49 patterns themselves. Every case goes
  through `to_string/3` and `to_parts/3`, whose parts must join to the same
  string and carry a valid `:source`.

  """

  use ExUnit.Case, async: true

  @fixture Path.join([__DIR__, "..", "support", "data", "interval_icu_expected.tsv"])
  @sources [:start_range, :end_range, :shared]

  test "date and time intervals match ICU wherever CLDR 49 agrees with its data" do
    mismatches =
      for line <- File.stream!(@fixture),
          line = String.trim_trailing(line, "\n"),
          line != "" and not String.starts_with?(line, "#"),
          [locale, kind, format, from, to, expected] <- [String.split(line, "\t")],
          mismatch <- [check_case(locale, kind, format, from, to, expected)],
          mismatch != nil,
          do: mismatch

    assert mismatches == [], report(mismatches)
  end

  describe "data CLDR 49 changed since ICU 73" do
    # de.xml: the `yM` interval item is "M/y – M/y" for both a month and a
    # year difference, where CLDR 43 had "MM/y".
    test "de numeric year and month" do
      assert Localize.Interval.to_string(~D[2024-07-06], ~D[2024-08-09],
               fields: :year_and_month,
               format: :short,
               locale: :de
             ) == {:ok, "7/2024 – 8/2024"}

      assert Localize.Interval.to_string(~D[2025-12-30], ~D[2026-01-02],
               fields: :month,
               format: :short,
               locale: :de
             ) == {:ok, "12/2025 – 1/2026"}
    end

    # de.xml: `h` and its interval item's `a` entry inherit root's "h a" and
    # "h a – h a"; CLDR 43 had "h 'Uhr' a".
    test "de 12-hour hours across noon" do
      assert Localize.Interval.to_string(~T[10:00:00], ~T[14:00:00], format: :h, locale: :de) ==
               {:ok, "10 AM – 2 PM"}
    end

    # fr.xml: `H` inherits root's "HH"; CLDR 43 had "HH 'h'". Two times in
    # the same hour differ in no field `H` displays, so they format as one.
    test "fr 24-hour hour within one hour" do
      assert Localize.Interval.to_string(~T[10:00:00], ~T[10:30:00], format: :H, locale: :fr) ==
               {:ok, "10"}
    end
  end

  describe "the rules TR35 and ICU apply" do
    # ICU widens a skeleton without a year by one when the endpoints are in
    # different years, taking `yMMMd`'s pattern for `MMMd`.
    test "an interval across a year boundary keeps both years" do
      assert Localize.Interval.to_string(~D[2025-12-30], ~D[2026-01-02],
               fields: :month_and_day,
               locale: :en
             ) == {:ok, "Dec 30, 2025 – Jan 2, 2026"}
    end

    # TR35 step 4: no difference in any field the pattern displays formats
    # a single value, with the requested fields.
    test "a difference the fields do not display formats a single value" do
      assert Localize.Interval.to_string(~D[2024-07-06], ~D[2024-07-09],
               fields: :year_and_month,
               locale: :en
             ) == {:ok, "Jul 2024"}

      assert Localize.Interval.to_string(~D[2024-07-06], ~D[2024-07-06],
               fields: :month_and_day,
               locale: :en
             ) == {:ok, "Jul 6"}
    end

    # CLDR's `hm` item has an `a` entry for a difference in the day period.
    test "times across noon take the day-period pattern" do
      assert Localize.Interval.to_string(~T[10:00:00], ~T[14:00:00], format: :hm, locale: :en) ==
               {:ok, "10:00 AM – 2:00 PM"}
    end

    # TR35 step 3.2: a same-day difference in the time fields shows the date
    # once, joined to the time interval by the date-time pattern of the
    # length TR35 picks from the date fields; fr's short pattern is "{1} {0}".
    test "a same-day datetime interval shows the date once" do
      assert Localize.Interval.to_string(~N[2024-07-06 10:00:00], ~N[2024-07-06 10:30:00],
               format: :short,
               locale: :en
             ) == {:ok, "7/6/24, 10:00 – 10:30 AM"}

      assert Localize.Interval.to_string(~N[2024-07-06 10:00:00], ~N[2024-07-06 10:30:00],
               format: :short,
               locale: :fr
             ) == {:ok, "06/07/2024 10:00 – 10:30"}
    end

    # CLDR ships no time interval pattern with seconds. The date is still
    # shown once, with both times joined by the fallback pattern.
    test "with seconds the date is shown once and both times in full" do
      assert Localize.Interval.to_string(~N[2024-07-06 10:00:00], ~N[2024-07-06 14:00:00],
               format: :medium,
               locale: :en
             ) == {:ok, "Jul 6, 2024, 10:00:00 AM – 2:00:00 PM"}
    end

    test "a difference only in seconds is an interval only where seconds show" do
      from = ~N[2024-07-06 10:00:00]
      to = ~N[2024-07-06 10:00:30]

      assert Localize.Interval.to_string(from, to, format: :medium, locale: :en) ==
               {:ok, "Jul 6, 2024, 10:00:00 AM – 10:00:30 AM"}

      assert Localize.Interval.to_string(from, to, format: :short, locale: :en) ==
               {:ok, "7/6/24, 10:00 AM"}
    end
  end

  describe "every pairing of endpoint shapes" do
    @endpoints [
      {:date, ~D[2024-07-06]},
      {:time, ~T[14:30:00]},
      {:naive_datetime, ~N[2024-07-06 14:30:00]},
      {:date_map, %{year: 2024, month: 7, day: 6}},
      {:time_map, %{hour: 14, minute: 30}},
      {:datetime_map, %{year: 2024, month: 7, day: 6, hour: 14, minute: 30, second: 0}},
      {:year_month_map, %{year: 2024, month: 7}},
      {nil, nil}
    ]

    test "never raise, and parts join to the string" do
      failures =
        for {from_kind, from} <- @endpoints,
            {to_kind, to} <- @endpoints,
            locale <- [:en, :ja],
            format <- [:short, :medium, :long, :full],
            failure <- [pairing_failure(from, to, locale, format)],
            failure != nil,
            do: {from_kind, to_kind, locale, format, failure}

      assert failures == [], inspect(Enum.take(failures, 20), pretty: true, limit: 12)
    end
  end

  defp check_case(locale, kind, format, from, to, expected) do
    locale = String.to_existing_atom(locale)
    format = String.to_existing_atom(format)

    {from, to, options} =
      case kind do
        "time" ->
          {Time.from_iso8601!(from), Time.from_iso8601!(to), [format: format, locale: locale]}

        "datetime" ->
          {NaiveDateTime.from_iso8601!(from), NaiveDateTime.from_iso8601!(to),
           [format: format, locale: locale]}

        fields ->
          {Date.from_iso8601!(from), Date.from_iso8601!(to),
           [fields: String.to_existing_atom(fields), format: format, locale: locale]}
      end

    string = Localize.Interval.to_string(from, to, options)
    parts = Localize.Interval.to_parts(from, to, options)

    cond do
      string != {:ok, expected} ->
        {locale, kind, format, from, to, expected, string}

      not match?({:ok, _parts}, parts) ->
        {locale, kind, format, from, to, expected, {:parts, parts}}

      Enum.map_join(elem(parts, 1), & &1.value) != expected ->
        {locale, kind, format, from, to, expected, {:parts_do_not_join, parts}}

      Enum.any?(elem(parts, 1), &(&1.source not in @sources)) ->
        {locale, kind, format, from, to, expected, {:bad_source, parts}}

      true ->
        nil
    end
  end

  defp pairing_failure(from, to, locale, format) do
    options = [format: format, locale: locale]

    string = Localize.Interval.to_string(from, to, options)
    parts = Localize.Interval.to_parts(from, to, options)

    case {string, parts} do
      {{:ok, value}, {:ok, parts}} ->
        if Enum.map_join(parts, & &1.value) == value, do: nil, else: {:parts_do_not_join, value}

      {{:ok, _value}, {:error, _exception}} when is_nil(from) or is_nil(to) ->
        nil

      {{:error, %{__exception__: true} = error}, {:error, %{__exception__: true}}} ->
        # An error without a message raises here and fails the test.
        _message = Exception.message(error)
        nil

      other ->
        {:unexpected, other}
    end
  end

  defp report(mismatches) do
    lines =
      mismatches
      |> Enum.take(25)
      |> Enum.map_join("\n", fn {locale, kind, format, from, to, expected, actual} ->
        "  #{locale} #{kind} #{format} #{from}..#{to}: expected #{inspect(expected)}, " <>
          "got #{inspect(actual, printable_limit: 200, limit: 10)}"
      end)

    "#{length(mismatches)} mismatches\n#{lines}"
  end
end
