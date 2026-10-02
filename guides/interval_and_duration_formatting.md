# Interval and Duration Formatting

This guide covers two related but distinct concepts in Localize:

* **Intervals** (`Localize.Interval`) — format a pair of dates, times, or datetimes as a range like "Apr 22 – 25, 2024" or "Jan 15 – Mar 20, 2024". The inputs are the endpoints; the output is a localised range string.

* **Durations** (`Localize.Duration`) — format an *amount of elapsed time* like "11 months, 30 days" or "37:48:12". The input is a duration struct (calculated from two points in time, or from a number of seconds); the output is a localised length-of-time string.

## Interval formatting

`Localize.Interval.to_string/3` takes two date/time values (or one value and a `nil` for open intervals) and produces a single localised range string. It identifies the greatest calendar field that differs between the two endpoints and selects a CLDR interval pattern that elides the shared fields.

### Closed intervals

```elixir
iex> {:ok, result} = Localize.Interval.to_string(~D[2024-04-22], ~D[2024-04-25], locale: :en)
iex> String.contains?(result, "22") and String.contains?(result, "25")
true

iex> {:ok, result} = Localize.Interval.to_string(~D[2024-01-15], ~D[2024-03-20], locale: :en)
iex> String.contains?(result, "Jan") and String.contains?(result, "Mar")
true
```

Because the two April dates share month and year, the result is "Apr 22 – 25, 2024" (not "Apr 22, 2024 – Apr 25, 2024"). When the months differ, both appear.

### Open intervals

Pass `nil` as either endpoint to produce an open interval with the locale's appropriate separator and placement:

```elixir
iex> Localize.Interval.to_string(~D[2020-01-01], nil, locale: :en)
{:ok, "Jan 1, 2020\u2009–"}

iex> Localize.Interval.to_string(nil, ~D[2020-01-01], locale: :en)
{:ok, "–\u2009Jan 1, 2020"}

iex> Localize.Interval.to_string(~D[2020-01-01], nil, locale: :ja)
{:ok, "2020/01/01～"}

iex> Localize.Interval.to_string(nil, ~D[2020-01-01], locale: :ja)
{:ok, "～2020/01/01"}
```

For an open interval the separator comes from CLDR's `intervalFormatFallback` pattern — most Western locales use an en-dash (`–`), Japanese a fullwidth tilde (`～`). A closed interval usually takes its separator from the matched interval pattern instead, which is why the two can differ within one locale. Passing `nil` for both endpoints returns an error.

### Fields and formats

Two independent options shape the output. `:fields` selects *which* date fields appear:

| Fields | Description |
|---|---|
| `:date` | The whole date (the default) |
| `:month` | Month only |
| `:month_and_day` | Month and day |
| `:year_and_month` | Year and month |

`:format` selects *how wide* those fields render: `:short`, `:medium` (the default), `:long`, or `:full`.

```elixir
iex> {:ok, result} =
...>   Localize.Interval.to_string(~D[2022-04-22], ~D[2022-04-25],
...>     locale: :en,
...>     fields: :month_and_day,
...>     format: :long
...>   )
iex> String.contains?(result, "Fri") and String.contains?(result, "Mon")
true
```

The pair selects a CLDR skeleton. `Localize.Interval.known_fields/0` returns the mapping for the non-default selections; `:date` is resolved per-locale from the same table `Localize.Date.to_string/2` uses, so it has no fixed entry here:

```elixir
iex> Localize.Interval.known_fields()
%{
  month: %{short: :M, full: :MMM, long: :MMM, medium: :MMM},
  month_and_day: %{short: :Md, full: :MMMEd, long: :MMMEd, medium: :MMMd},
  year_and_month: %{short: :yM, full: :yMMMM, long: :yMMMM, medium: :yMMM}
}
```

### Skeletons and patterns

`:format` also takes a skeleton, which selects CLDR's interval format for its fields as CLDR keys them, so it can name a format no standard format reaches, or a pattern, with which both endpoints are formatted around the locale's interval fallback pattern. `:date_format` takes either too. `:fields` applies with a standard format only, since a skeleton names its fields itself.

```elixir
iex> Localize.Interval.to_string(~D[2026-06-15], ~D[2026-06-18], format: :yMMMEd, locale: :en)
{:ok, "Mon, Jun 15 – Thu, Jun 18, 2026"}

iex> Localize.Interval.to_string(~D[2026-06-15], ~D[2026-06-18], format: "d MMM y", locale: :en)
{:ok, "15 Jun 2026 – 18 Jun 2026"}
```

### Intervals for times and datetimes

`Localize.Interval.to_string/3` accepts `Date`, `Time`, `NaiveDateTime`, and `DateTime` values, as well as any map with the appropriate fields. The formatting strategy depends on what fields differ:

* **Same-day datetime intervals** — format the date once with the start time and end time as a time range (`"Apr 8, 2026, 12:00 PM – 2:00 PM"`). The `:time_format` option (`:short`, `:medium`, `:long`) controls the time portion independently.

* **Different-day datetime intervals** — format both endpoints as full datetimes separated by the locale's interval fallback separator (`"Apr 15, 2026, 12:49 AM – Apr 16, 2026, 1:49 AM"`).

* **Time-only intervals** — use the locale's time-interval pattern (`"10:00 – 12:30 PM"`).

A date and a time in an interval are joined with the locale's standard date-time pattern, as TR35 says an interval takes, where a single date and time takes the "at" pattern by default: "June 15, 2026, 10:00 – 14:30", not "June 15, 2026 at 10:00 – 14:30". `style: :at` asks for the "at" pattern.

```elixir
iex> {:ok, result} =
...>   Localize.Interval.to_string(
...>     ~N[2026-04-08 12:00:00],
...>     ~N[2026-04-08 14:00:00],
...>     locale: :en, format: :medium, time_format: :short
...>   )
iex> String.contains?(result, "Apr 8, 2026") and String.contains?(result, "2:00")
true

iex> {:ok, result} =
...>   Localize.Interval.to_string(
...>     ~N[2026-04-15 00:49:00],
...>     ~N[2026-04-16 01:49:00],
...>     locale: :en, format: :medium, time_format: :short
...>   )
iex> String.contains?(result, "Apr 15") and String.contains?(result, "Apr 16")
true

iex> {:ok, result} = Localize.Interval.to_string(~T[10:00:00], ~T[12:30:00], locale: :en)
iex> String.contains?(result, "10:00") and String.contains?(result, "12:30")
true
```

Open intervals work the same way:

```elixir
iex> {:ok, result} = Localize.Interval.to_string(~T[10:30:00], nil, locale: :en)
iex> String.contains?(result, "10:30")
true
```

A skeleton for a datetime interval is split into its date and time fields, as TR35's interval algorithm separates them. On one day the date is written once and the times as a range. A skeleton of time fields alone writes only the times, across days too, as TR35's algorithm reads; ICU adds the locale's numeric date there. A skeleton of date fields alone formats the dates as a date interval does.

```elixir
iex> Localize.Interval.to_string(~N[2026-06-15 10:00:00], ~N[2026-06-15 14:30:00], format: :yMMMdHm, locale: :en)
{:ok, "Jun 15, 2026, 10:00 – 14:30"}

iex> Localize.Interval.to_string(~N[2026-06-15 10:00:00], ~N[2026-06-16 14:30:00], format: :Hm, locale: :en)
{:ok, "10:00 – 14:30"}

iex> Localize.Interval.to_string(~N[2026-06-15 10:00:00], ~N[2026-06-16 14:30:00], format: :yMMMd, locale: :en)
{:ok, "Jun 15 – 16, 2026"}
```

### Calendars and eras

An interval is formatted with the formats of its endpoints' calendar: its interval patterns, its date and time formats, and the date-time pattern that joins a date to a time range. Two dates in Calendrical's Hebrew calendar take the Hebrew calendar's CLDR formats, as a single Hebrew date does in `Localize.Date.to_string/2`. Endpoints in two different calendars are an error, because there is no one calendar to take the formats from.

When the endpoints are in different eras, the era is the greatest difference, and each endpoint shows its era wherever the locale has an era pattern for the interval's fields, as ICU does:

```elixir
iex> Localize.Interval.to_string(~D[0000-12-31], ~D[0001-01-01], locale: :en)
{:ok, "Dec 31, 1 BC\u2009–\u2009Jan 1, 1 AD"}
```

The Japanese calendar changes era within a year, so its interval from 30 April to 1 May 2019 reads "Apr 30, 31 Heisei – May 1, 1 Reiwa" although both dates fall in the same Gregorian year.

### How interval formatting works

1. The greatest difference between the two endpoints is identified (era, year, month, day, hour, or minute). Endpoints that differ in no field the format shows are formatted once; whole dates then take the requested standard format, exactly as `Localize.Date.to_string/2` renders it.

2. A skeleton given as `:format` is the skeleton; `:fields` and a standard `:format` resolve to one, from the endpoints' calendar. A datetime interval's skeleton is split into its date and time fields, the time fields taking the interval entry. A pattern names no entry, so both endpoints are formatted with it, as in step 5.

3. That skeleton is looked up in the interval table of the locale and calendar. If CLDR ships no entry under it, the closest entry carrying the same fields is taken and its pattern adjusted to the requested widths — TR35 matches on fields, not widths, so a `yMMMd` pattern answering a requested `yMMMMd` still has to spell "June" rather than "Jun". A candidate with different fields can never win.

4. The matched pattern splits at the field that differs, which is why two dates in the same month produce "Apr 22 – 25, 2024" rather than repeating the month and year. German at `:medium` gives "03.–05.05.2026" for the same reason, even though its style skeleton is not itself a key in the table.

5. Only when no entry carries the same fields are both endpoints formatted in full and joined with the locale's `intervalFormatFallback` pattern.

6. For open intervals (one endpoint is `nil`), the known endpoint is formatted using the appropriate single-value formatter (`Localize.Date`, `Localize.Time`, or `Localize.DateTime`), then substituted into the locale's `intervalFormatFallback` pattern with the appropriate trimming so only the separator on the "open" side remains.

## Duration formatting

`Localize.Duration` represents an amount of elapsed time in calendar units (years, months, days, hours, minutes, seconds, microseconds). Unlike intervals, a duration is not tied to two specific points — it is a scalar quantity of time.

### Creating durations

From two dates, times, or datetimes:

```elixir
iex> {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2019-12-31])
iex> d.month
11

iex> {:ok, d} = Localize.Duration.new(~T[10:00:00], ~T[12:30:45])
iex> {d.hour, d.minute, d.second}
{2, 30, 45}
```

The years, months and days between two dates are the span the dates' own calendar adds to the earlier to reach the later, as `Date.shift/2` adds it: the most years that do not pass the later date, then the most months after them, then the days left. A day of the month is brought into a shorter month, so 31 January to 29 February is one month:

```elixir
iex> {:ok, d} = Localize.Duration.new(~D[2023-01-14], ~D[2023-07-13])
iex> {d.month, d.day}
{5, 29}

iex> {:ok, d} = Localize.Duration.new(~D[2024-01-31], ~D[2024-02-29])
iex> {d.month, d.day}
{1, 0}
```

Two date-times in time zones are two moments, measured where the earlier is, as ECMA-262 Temporal measures two zoned date-times. The later is moved to the earlier's time zone, the years, months and days are counted on that wall clock, and the hours, minutes and seconds are the time that passes after them. So 10:00 UTC to 18:00 in Karachi is three hours, noon to noon across a change of clocks is one day though 23 hours pass, and 23:00 to 04:00 across the hour the clocks skip is four hours:

```elixir
iex> karachi = DateTime.new!(~D[2026-06-15], ~T[18:00:00], "Asia/Karachi")
iex> {:ok, d} = Localize.Duration.new(~U[2026-06-15 10:00:00Z], karachi)
iex> {d.day, d.hour}
{0, 3}

iex> noon = DateTime.new!(~D[2024-03-09], ~T[12:00:00], "America/New_York")
iex> next_noon = DateTime.new!(~D[2024-03-10], ~T[12:00:00], "America/New_York")
iex> {:ok, d} = Localize.Duration.new(noon, next_noon)
iex> {d.day, d.hour}
{1, 0}

iex> late = DateTime.new!(~D[2024-03-09], ~T[23:00:00], "America/New_York")
iex> early = DateTime.new!(~D[2024-03-10], ~T[04:00:00], "America/New_York")
iex> {:ok, d} = Localize.Duration.new(late, early)
iex> {d.day, d.hour}
{0, 4}
```

A time zone is known through the time zone database the application configures, such as [tz](https://hex.pm/packages/tz). Without one that knows the earlier value's zone, the later is taken to the UTC offset the earlier carries. Where the clocks repeat an hour, the hours that pass can be 24 or more.

Any other two values are measured on the wall clocks they are written in: a date paired with a date-time is taken at midnight, and a time paired with a date-time is measured against its time of day.

From a number of seconds:

```elixir
iex> d = Localize.Duration.new_from_seconds(136_092)
iex> {d.hour, d.minute, d.second}
{37, 48, 12}

iex> d = Localize.Duration.new_from_seconds(90.5)
iex> {d.minute, d.second}
{1, 30}
```

### Formatting durations as text

`Localize.Duration.to_string/2` produces human-readable strings using locale-aware unit names joined with the locale's list conjunction:

```elixir
iex> {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2019-12-31])
iex> Localize.Duration.to_string(d, locale: :en)
{:ok, "11 months, 30 days"}
```

The `:format` option switches between `:long` (default), `:short`, and `:narrow` unit forms:

```elixir
iex> {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2019-12-31])
iex> Localize.Duration.to_string(d, locale: :en, format: :short)
{:ok, "11 mths, 30 days"}
```

The `:except` option drops specific units from the output. By default, `:microsecond` is excluded:

```elixir
iex> d = Localize.Duration.new_from_seconds(3665)
iex> Localize.Duration.to_string(d, locale: :en, except: [:microsecond, :second])
{:ok, "1 hour, 1 minute"}
```

Other locales format durations using their native unit names and list separator:

```elixir
iex> {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2019-12-31])
iex> Localize.Duration.to_string(d, locale: :fr)
{:ok, "11\u00A0mois et 30\u00A0jours"}
```

### Formatting durations as numeric time

`Localize.Duration.to_time_string/2` formats the time portion using a numeric pattern like `"hh:mm:ss"`. Hours are unbounded — a duration of 37 hours formats as `"37:48:12"`, not a clock time:

```elixir
iex> d = Localize.Duration.new_from_seconds(136_092)
iex> Localize.Duration.to_time_string(d)
{:ok, "37:48:12"}

iex> d = Localize.Duration.new_from_seconds(65)
iex> Localize.Duration.to_time_string(d, format: "m:ss")
{:ok, "1:05"}
```

The `:format` option accepts any pattern made from `h`, `hh`, `m`, `mm`, `s`, `ss` field symbols plus literal characters:

| Pattern | 37 hours 48 min 12 sec |
|---|---|
| `"hh:mm:ss"` (default) | `"37:48:12"` |
| `"h:mm:ss"` | `"37:48:12"` |
| `"mm:ss"` | `"48:12"` |
| `"h'h' m'm'"` | `"37h 48m"` |

## When to use which

| If you want | Use |
|---|---|
| "From Jan 10 to Jan 12" or "Apr 22 – 25, 2024" | `Localize.Interval.to_string/3` |
| "Open ended date" like "Jan 1, 2020 –" | `Localize.Interval.to_string/3` with a `nil` endpoint |
| "2 years and 3 months" or "37 hours" | `Localize.Duration.to_string/2` |
| "37:48:12" (stopwatch-style) | `Localize.Duration.to_time_string/2` |
| Relative phrases like "2 hours ago" | `Localize.DateTime.Relative.to_string/2` (see the Date and Time guide) |
