defmodule Localize.DateTime.SymbolMatrixTest do
  @moduledoc """
  Every date, time and zone symbol in TR35's Date Field Symbol Table, at
  every width the table defines and at wider widths too, across a spread of
  locales and values.

  Expected values are computed here rather than taken from the formatter:
  numeric fields from `Calendar` arithmetic and TR35's field definitions,
  week fields from the locale's week data by TR35's week rules, the Julian
  day from a fixed epoch, day periods from the locale's day-period rules,
  and names read directly from the locale's calendar data. Each case goes
  through `to_string/2` and `to_parts/2`, whose parts must join to the same
  string.

  TR35 does not define widths past its table. For those, Localize follows
  ICU4J: numeric fields zero-pad to the width and name fields fall back to a
  defined width, per the fallbacks recorded from ICU below. The
  weekday-number, week and Julian-day rules were also cross-checked against
  ICU4J, and the zone cases are ICU4J's output for the same instants.

  """

  use ExUnit.Case, async: true

  @locales [:en, :"en-GB", :de, :fr, :"ar-EG", :fa, :hi, :ja, :ru]

  # A Saturday, a Monday that starts a year, a Sunday that starts a month,
  # both sides of a week-year boundary, a leap day, and a two-digit year for
  # zero padding.
  @dates [
    ~D[2024-07-06],
    ~D[2024-01-01],
    ~D[2024-09-01],
    ~D[2024-12-29],
    ~D[2024-12-30],
    ~D[2021-01-03],
    ~D[2020-02-29],
    ~D[2027-01-01],
    ~D[0099-03-04]
  ]

  # Afternoon, midnight, noon, the last microsecond, morning, and a time with
  # no fractional precision.
  @times [
    ~T[14:30:45.123456],
    ~T[00:00:00.000000],
    ~T[12:00:00.000000],
    ~T[23:59:59.999999],
    ~T[06:05:04.000001],
    ~T[09:07:08]
  ]

  # Each symbol with the widths checked: TR35's own and a few past them.
  # `ddd` is the ordinal day and has its own tests below.
  @date_symbols [
    {"G", [1, 2, 3, 4, 5, 6, 7]},
    {"y", [1, 2, 3, 4, 5, 6, 7]},
    {"Y", [1, 2, 3, 4, 5, 6, 7]},
    {"u", [1, 2, 3, 4, 5, 6]},
    {"U", [1, 2, 3, 4, 5, 6]},
    {"r", [1, 2, 3, 4, 5, 6]},
    {"Q", [1, 2, 3, 4, 5, 6, 7]},
    {"q", [1, 2, 3, 4, 5, 6, 7]},
    {"M", [1, 2, 3, 4, 5, 6, 7]},
    {"L", [1, 2, 3, 4, 5, 6, 7]},
    {"w", [1, 2, 3, 4]},
    {"W", [1, 2, 3]},
    {"d", [1, 2, 4, 5]},
    {"D", [1, 2, 3, 4, 5]},
    {"F", [1, 2, 3]},
    {"g", [1, 7, 10]},
    {"E", [1, 2, 3, 4, 5, 6, 7, 8]},
    {"e", [1, 2, 3, 4, 5, 6, 7, 8]},
    {"c", [1, 2, 3, 4, 5, 6, 7, 8]}
  ]

  @time_symbols [
    {"a", [1, 2, 3, 4, 5, 6, 7]},
    {"b", [1, 2, 3, 4, 5, 6, 7]},
    {"B", [1, 2, 3, 4, 5, 6, 7]},
    {"h", [1, 2, 3, 4]},
    {"H", [1, 2, 3, 4]},
    {"K", [1, 2, 3, 4]},
    {"k", [1, 2, 3, 4]},
    {"m", [1, 2, 3, 4]},
    {"s", [1, 2, 3, 4]},
    {"S", [1, 2, 3, 6, 9]},
    {"A", [1, 8, 9]}
  ]

  for {symbol, widths} <- @date_symbols do
    test "date symbol #{symbol} at widths #{inspect(widths)}" do
      mismatches =
        for locale <- @locales,
            date <- @dates,
            width <- unquote(widths),
            pattern <- [String.duplicate(unquote(symbol), width)],
            expected <- [date_value(unquote(symbol), width, date, locale)],
            mismatch <- [check(Localize.Date, date, pattern, locale, expected)],
            mismatch != nil,
            do: mismatch

      assert mismatches == [], report(mismatches)
    end
  end

  for {symbol, widths} <- @time_symbols do
    test "time symbol #{symbol} at widths #{inspect(widths)}" do
      mismatches =
        for locale <- @locales,
            time <- @times,
            width <- unquote(widths),
            pattern <- [String.duplicate(unquote(symbol), width)],
            expected <- [time_value(unquote(symbol), width, time, locale)],
            mismatch <- [check(Localize.Time, time, pattern, locale, expected)],
            mismatch != nil,
            do: mismatch

      assert mismatches == [], report(mismatches)
    end
  end

  describe "the ordinal day (ddd) from CLDR 49's dayOfMonths data" do
    # en: {0}st one, {0}nd two, {0}rd few, {0}th other. fr: {0}er one, {0}
    # other. uk: {0}-тє few, {0}-е other. The categories are each language's
    # ordinal plural rules; de has no dayOfMonths data, so the day is plain.
    @ordinal_days [
      en: [
        {1, "1st"},
        {2, "2nd"},
        {3, "3rd"},
        {4, "4th"},
        {11, "11th"},
        {12, "12th"},
        {13, "13th"},
        {21, "21st"},
        {22, "22nd"},
        {23, "23rd"},
        {31, "31st"}
      ],
      fr: [{1, "1er"}, {2, "2"}, {21, "21"}, {31, "31"}],
      uk: [{1, "1-е"}, {3, "3-тє"}, {13, "13-е"}, {23, "23-тє"}],
      de: [{1, "1"}, {3, "3"}]
    ]

    test "the day takes the pattern for its ordinal category" do
      mismatches =
        for {locale, days} <- @ordinal_days,
            {day, expected} <- days,
            date <- [Date.new!(2024, 1, day)],
            mismatch <- [check(Localize.Date, date, "ddd", locale, expected)],
            mismatch != nil,
            do: mismatch

      assert mismatches == [], report(mismatches)
    end

    test "beside a numeric month the ordinal day is the plain day" do
      assert Localize.Date.to_string(~D[2024-07-03], format: "M/ddd", locale: :en) == {:ok, "7/3"}

      assert Localize.Date.to_string(~D[2024-07-03], format: "MMM ddd", locale: :en) ==
               {:ok, "Jul 3rd"}
    end

    test "CLDR's ordinal skeletons resolve to the locale's ordinal formats" do
      # en availableFormats: yMMMddd is "MMM ddd, y" and MMMEddd "E, MMM ddd".
      assert Localize.Date.to_string(~D[2024-07-06], format: :yMMMddd, locale: :en) ==
               {:ok, "Jul 6th, 2024"}

      assert Localize.Date.to_string(~D[2024-07-06], format: :MMMEddd, locale: :en) ==
               {:ok, "Sat, Jul 6th"}
    end

    # TR35 §Element dayOfMonth: where a locale has no available format with
    # `ddd`, the best match is the skeleton with `d` and "the width of the `d`
    # field in the pattern is not adjusted in width". de has neither the
    # `dayOfMonths` element nor a `ddd` format, so `yMMMddd` must render
    # exactly as `yMMMd` does — no widening, no ordinal.
    test "a ddd skeleton the locale has no format for matches its d format unwidened" do
      assert Localize.Date.to_string(~D[2024-07-06], format: :yMMMddd, locale: :de) ==
               {:ok, "6. Juli 2024"}

      assert Localize.Date.to_string(~D[2024-07-06], format: :yMMMddd, locale: :de) ==
               Localize.Date.to_string(~D[2024-07-06], format: :yMMMd, locale: :de)

      assert Localize.Date.to_string(~D[2024-07-06], format: :yMMMddd, locale: :ja) ==
               Localize.Date.to_string(~D[2024-07-06], format: :yMMMd, locale: :ja)
    end
  end

  describe "zone symbols" do
    @new_york %DateTime{
      year: 2024,
      month: 7,
      day: 6,
      hour: 14,
      minute: 30,
      second: 45,
      microsecond: {123_000, 3},
      time_zone: "America/New_York",
      zone_abbr: "EDT",
      utc_offset: -18_000,
      std_offset: 3600,
      calendar: Calendar.ISO
    }

    @kolkata %DateTime{
      year: 2024,
      month: 7,
      day: 6,
      hour: 14,
      minute: 30,
      second: 45,
      microsecond: {123_000, 3},
      time_zone: "Asia/Kolkata",
      zone_abbr: "IST",
      utc_offset: 19_800,
      std_offset: 0,
      calendar: Calendar.ISO
    }

    @utc %DateTime{
      year: 2024,
      month: 7,
      day: 6,
      hour: 14,
      minute: 30,
      second: 45,
      microsecond: {123_000, 3},
      time_zone: "Etc/UTC",
      zone_abbr: "UTC",
      utc_offset: 0,
      std_offset: 0,
      calendar: Calendar.ISO
    }

    # ICU4J's output for each instant in en, including past TR35's widths for
    # z and Z.
    @icu_zone_cases [
      {@new_york,
       [
         {"z", "EDT"},
         {"zzz", "EDT"},
         {"zzzz", "Eastern Daylight Time"},
         {"zzzzz", "Eastern Daylight Time"},
         {"Z", "-0400"},
         {"ZZZ", "-0400"},
         {"ZZZZ", "GMT-04:00"},
         {"ZZZZZ", "-04:00"},
         {"ZZZZZZ", "GMT-04:00"},
         {"O", "GMT-4"},
         {"OOOO", "GMT-04:00"},
         {"v", "ET"},
         {"vvvv", "Eastern Time"},
         {"V", "usnyc"},
         {"VV", "America/New_York"},
         {"VVV", "New York"},
         {"VVVV", "New York Time"},
         {"X", "-04"},
         {"XX", "-0400"},
         {"XXX", "-04:00"},
         {"XXXX", "-0400"},
         {"XXXXX", "-04:00"},
         {"x", "-04"},
         {"xx", "-0400"},
         {"xxx", "-04:00"},
         {"xxxx", "-0400"},
         {"xxxxx", "-04:00"}
       ]},
      {@kolkata,
       [
         {"z", "GMT+5:30"},
         {"zzzz", "India Standard Time"},
         {"Z", "+0530"},
         {"ZZZZ", "GMT+05:30"},
         {"ZZZZZ", "+05:30"},
         {"O", "GMT+5:30"},
         {"OOOO", "GMT+05:30"},
         {"v", "India Time"},
         {"vvvv", "India Standard Time"},
         {"V", "inccu"},
         {"VV", "Asia/Kolkata"},
         {"VVV", "Kolkata"},
         {"VVVV", "India Time"},
         {"X", "+0530"},
         {"XXX", "+05:30"},
         {"x", "+0530"},
         {"xxx", "+05:30"}
       ]},
      {@utc,
       [
         {"Z", "+0000"},
         {"ZZZZZ", "Z"},
         {"X", "Z"},
         {"XXX", "Z"},
         {"XXXXX", "Z"},
         {"x", "+00"},
         {"xx", "+0000"},
         {"xxx", "+00:00"},
         {"xxxxx", "+00:00"},
         {"V", "utc"},
         {"VV", "Etc/UTC"}
       ]}
    ]

    # ICU has no output past the widths TR35 defines for O, v, V, X and x;
    # Localize uses the widest defined form of each.
    @widest_zone_cases [
      {@new_york,
       [
         {"OOOOO", "GMT-04:00"},
         {"vvvvv", "Eastern Time"},
         {"VVVVV", "New York Time"},
         {"XXXXXX", "-04:00"},
         {"xxxxxx", "-04:00"}
       ]}
    ]

    test "match ICU4J" do
      assert_zone_cases(@icu_zone_cases)
    end

    test "past ICU's widths use the widest defined form" do
      assert_zone_cases(@widest_zone_cases)
    end
  end

  defp assert_zone_cases(cases) do
    mismatches =
      for {datetime, patterns} <- cases,
          {pattern, expected} <- patterns,
          mismatch <- [check(Localize.DateTime, datetime, pattern, :en, expected)],
          mismatch != nil,
          do: mismatch

    assert mismatches == [], report(mismatches)
  end

  defp check(module, value, pattern, locale, expected) do
    string = module.to_string(value, format: pattern, locale: locale)

    joined =
      case module.to_parts(value, format: pattern, locale: locale) do
        {:ok, parts} -> {:ok, Enum.map_join(parts, & &1.value)}
        other -> other
      end

    if string == {:ok, expected} and joined == {:ok, expected} do
      nil
    else
      {locale, value, pattern, expected, string, joined}
    end
  end

  defp report(mismatches) do
    lines =
      mismatches
      |> Enum.take(30)
      |> Enum.map_join("\n", fn {locale, value, pattern, expected, string, joined} ->
        "  #{locale} #{inspect(value)} #{inspect(pattern)}: expected #{inspect(expected)}, " <>
          "to_string #{inspect(string)}, to_parts joined #{inspect(joined)}"
      end)

    "#{length(mismatches)} mismatches\n#{lines}"
  end

  # ── Date fields ────────────────────────────────────────────

  # Era (G): the name for the current era, AD being era 1.
  defp date_value("G", width, _date, locale), do: era_name(locale, era_width(width), 1)

  # Calendar year (y): minimum digits, except that `yy` is the two low-order
  # digits. Cyclic year (U) has no Gregorian names, so TR35 formats it as `y`.
  defp date_value(symbol, width, date, locale) when symbol in ["y", "U"] do
    date.year |> year_digits(width) |> native_digits(locale)
  end

  # Week-based year (Y): the year the date's week belongs to, sized like `y`.
  defp date_value("Y", width, date, locale) do
    {week_year, _week} = week_of_year(date, locale)
    week_year |> year_digits(width) |> native_digits(locale)
  end

  # Extended year (u): minimum digits, with no special meaning for two
  # letters; for Gregorian it is the year.
  defp date_value("u", width, date, locale), do: date.year |> pad(width) |> native_digits(locale)

  # Related Gregorian year (r): the year itself for Gregorian, minimum digits,
  # and "usually displayed using the latn numbering system" (TR35).
  defp date_value("r", width, date, _locale), do: pad(date.year, width)

  defp date_value(symbol, width, date, locale) when symbol in ["Q", "q"] and width in 1..2 do
    date |> quarter() |> pad(width) |> native_digits(locale)
  end

  defp date_value("Q", width, date, locale),
    do: calendar_name(locale, :quarters, :format, quarter_width(width), quarter(date))

  defp date_value("q", width, date, locale),
    do: calendar_name(locale, :quarters, :stand_alone, quarter_width(width), quarter(date))

  # Month (M, L): numeric at one or two letters, a name at three to five, and
  # numeric again past that (ICU).
  defp date_value(symbol, width, date, locale)
       when symbol in ["M", "L"] and (width in 1..2 or width >= 6) do
    date.month |> pad(width) |> native_digits(locale)
  end

  defp date_value("M", width, date, locale),
    do: calendar_name(locale, :months, :format, name_width(width), date.month)

  defp date_value("L", width, date, locale),
    do: calendar_name(locale, :months, :stand_alone, name_width(width), date.month)

  defp date_value("w", width, date, locale) do
    {_week_year, week} = week_of_year(date, locale)
    week |> pad(width) |> native_digits(locale)
  end

  defp date_value("W", width, date, locale) do
    date |> week_of_month(locale) |> pad(width) |> native_digits(locale)
  end

  defp date_value("d", width, date, locale), do: date.day |> pad(width) |> native_digits(locale)

  defp date_value("D", width, date, locale) do
    date |> Date.day_of_year() |> pad(width) |> native_digits(locale)
  end

  # Day of week in month (F): which occurrence of its weekday the day is.
  defp date_value("F", width, date, locale) do
    (div(date.day - 1, 7) + 1) |> pad(width) |> native_digits(locale)
  end

  # Modified Julian day (g): a continuous day count; TR35's example value is
  # the Julian day number, which is 2,451,545 on 2000-01-01.
  defp date_value("g", width, date, locale) do
    (2_451_545 + Date.diff(date, ~D[2000-01-01])) |> pad(width) |> native_digits(locale)
  end

  defp date_value("E", width, date, locale),
    do: calendar_name(locale, :days, :format, name_width(width), Date.day_of_week(date))

  # Local day of week (e, c): numbered from the locale's first day of the
  # week. `ee` is zero-padded; `c` and `cc` are both one digit.
  defp date_value("e", width, date, locale) when width in 1..2 do
    date |> local_day_of_week(locale) |> pad(width) |> native_digits(locale)
  end

  defp date_value("c", width, date, locale) when width in 1..2 do
    date |> local_day_of_week(locale) |> pad(1) |> native_digits(locale)
  end

  defp date_value("e", width, date, locale),
    do: calendar_name(locale, :days, :format, name_width(width), Date.day_of_week(date))

  defp date_value("c", width, date, locale),
    do: calendar_name(locale, :days, :stand_alone, name_width(width), Date.day_of_week(date))

  # ── Time fields ────────────────────────────────────────────

  defp time_value("a", width, time, locale), do: am_pm(time, locale, am_pm_width(width))

  # b: noon or midnight at exactly those times where the locale names them,
  # otherwise AM or PM.
  defp time_value("b", width, time, locale) do
    names = day_period_names(locale, day_period_width(width))
    period = at_period(locale, minutes_of_day(time))
    name_or_am_pm(names, period, time, locale, width)
  end

  # B: an exact-time period first, then the flexible period whose range
  # holds the time, otherwise AM or PM.
  defp time_value("B", width, time, locale) do
    names = day_period_names(locale, day_period_width(width))
    minutes = minutes_of_day(time)
    period = at_period(locale, minutes) || range_period(locale, minutes)
    name_or_am_pm(names, period, time, locale, width)
  end

  defp time_value("h", width, time, locale) do
    time.hour
    |> rem(12)
    |> then(&if(&1 == 0, do: 12, else: &1))
    |> pad(width)
    |> native_digits(locale)
  end

  defp time_value("H", width, time, locale), do: time.hour |> pad(width) |> native_digits(locale)

  defp time_value("K", width, time, locale),
    do: time.hour |> rem(12) |> pad(width) |> native_digits(locale)

  defp time_value("k", width, time, locale) do
    if(time.hour == 0, do: 24, else: time.hour) |> pad(width) |> native_digits(locale)
  end

  defp time_value("m", width, time, locale),
    do: time.minute |> pad(width) |> native_digits(locale)

  defp time_value("s", width, time, locale),
    do: time.second |> pad(width) |> native_digits(locale)

  # Fractional second (S): truncated to exactly as many digits as the field
  # has letters.
  defp time_value("S", width, time, locale) do
    {microsecond, _precision} = time.microsecond

    microsecond
    |> pad(6)
    |> String.pad_trailing(width, "0")
    |> String.slice(0, width)
    |> native_digits(locale)
  end

  # Milliseconds in day (A): minimum digits, zero-padded.
  defp time_value("A", width, time, locale) do
    {microsecond, _precision} = time.microsecond

    milliseconds =
      (time.hour * 3600 + time.minute * 60 + time.second) * 1000 + div(microsecond, 1000)

    milliseconds |> pad(width) |> native_digits(locale)
  end

  # ── Oracles ────────────────────────────────────────────────

  # TR35's name widths; past them ICU falls back to the abbreviated name for
  # weekdays and eras, the narrow name for quarters and AM/PM, and the wide
  # name for other day periods.
  defp name_width(width) when width in 1..3, do: :abbreviated
  defp name_width(4), do: :wide
  defp name_width(5), do: :narrow
  defp name_width(6), do: :short
  defp name_width(_width), do: :abbreviated

  defp era_width(4), do: :wide
  defp era_width(5), do: :narrow
  defp era_width(_width), do: :abbreviated

  defp quarter_width(3), do: :abbreviated
  defp quarter_width(4), do: :wide
  defp quarter_width(_width), do: :narrow

  defp am_pm_width(width) when width in 1..3, do: :abbreviated
  defp am_pm_width(4), do: :wide
  defp am_pm_width(_width), do: :narrow

  defp day_period_width(width) when width in 1..3, do: :abbreviated
  defp day_period_width(4), do: :wide
  defp day_period_width(5), do: :narrow
  defp day_period_width(_width), do: :wide

  defp pad(number, width), do: number |> Integer.to_string() |> String.pad_leading(width, "0")

  defp year_digits(year, 2), do: year |> rem(100) |> pad(2)
  defp year_digits(year, width), do: pad(year, width)

  defp quarter(date), do: div(date.month - 1, 3) + 1

  defp native_digits(string, locale) do
    {:ok, %{default: system}} = Localize.Number.System.number_systems_for(locale)
    {:ok, digits} = Localize.Number.System.number_system_digits(system)
    native = String.graphemes(digits)

    Regex.replace(~r/[0-9]/, string, fn digit -> Enum.at(native, String.to_integer(digit)) end)
  end

  defp calendar_name(locale, key, context, width, index) do
    {:ok, data} = Localize.Locale.get(locale, [:dates, :calendars, :gregorian, key])
    data |> Map.fetch!(context) |> Map.fetch!(width) |> Map.fetch!(index)
  end

  defp era_name(locale, width, era) do
    {:ok, eras} = Localize.Locale.get(locale, [:dates, :calendars, :gregorian, :eras])
    eras |> Map.fetch!(width) |> Map.fetch!(era)
  end

  # TR35 week rules: a week starts on the locale's first day, and week 1 is
  # the first week holding at least the locale's minimum days of the year.
  defp week_data(locale) do
    {Localize.Calendar.first_day_for_locale(locale),
     Localize.Calendar.min_days_for_locale(locale)}
  end

  defp week_one_start(year, {first_day, min_days}) do
    new_year = Date.new!(year, 1, 1)
    offset = Integer.mod(Date.day_of_week(new_year) - first_day, 7)
    week_start = Date.add(new_year, -offset)

    if 7 - offset >= min_days, do: week_start, else: Date.add(week_start, 7)
  end

  defp week_of_year(date, locale) do
    data = week_data(locale)

    Enum.find_value([date.year + 1, date.year, date.year - 1], fn year ->
      start = week_one_start(year, data)

      if Date.compare(date, start) != :lt do
        {year, div(Date.diff(date, start), 7) + 1}
      end
    end)
  end

  defp week_of_month(date, locale) do
    {first_day, min_days} = week_data(locale)
    offset = Integer.mod(Date.day_of_week(%{date | day: 1}) - first_day, 7)
    week = div(date.day - 1 + offset, 7) + 1

    if 7 - offset >= min_days, do: week, else: week - 1
  end

  defp local_day_of_week(date, locale) do
    {first_day, _min_days} = week_data(locale)
    Integer.mod(Date.day_of_week(date) - first_day, 7) + 1
  end

  defp minutes_of_day(time), do: time.hour * 60 + time.minute

  defp day_period_rules(locale) do
    language = locale |> Atom.to_string() |> String.split("-") |> hd()
    Map.get(Localize.SupplementalData.day_periods().format, language, %{})
  end

  defp at_period(locale, minutes) do
    Enum.find_value(day_period_rules(locale), fn
      {period, %{at: ^minutes}} -> period
      _other -> nil
    end)
  end

  defp range_period(locale, minutes) do
    Enum.find_value(day_period_rules(locale), fn
      {period, %{from: from, before: before}} when from <= before ->
        if minutes >= from and minutes < before, do: period

      {period, %{from: from, before: before}} ->
        if minutes >= from or minutes < before, do: period

      _other ->
        nil
    end)
  end

  defp day_period_names(locale, width) do
    {:ok, periods} = Localize.Locale.get(locale, [:dates, :calendars, :gregorian, :day_periods])
    periods |> Map.fetch!(:format) |> Map.fetch!(width)
  end

  defp am_pm(time, locale, width) do
    key = if time.hour < 12, do: :am, else: :pm
    locale |> day_period_names(width) |> Map.fetch!(key) |> default_form()
  end

  defp name_or_am_pm(names, period, time, locale, width) do
    case period && Map.get(names, period) do
      nil -> am_pm(time, locale, am_pm_width(width))
      name -> default_form(name)
    end
  end

  defp default_form(%{default: name}), do: name
  defp default_form(name) when is_binary(name), do: name
end
