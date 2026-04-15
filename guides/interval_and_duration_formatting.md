# Interval and Duration Formatting

This guide covers two related but distinct concepts in Localize:

* **Intervals** (`Localize.Interval`) — format a pair of dates, times, or datetimes as a range like "Apr 22 – 25, 2024" or "Jan 15 – Mar 20, 2024". The inputs are the endpoints; the output is a localised range string.

* **Durations** (`Localize.Duration`) — format an *amount of elapsed time* like "11 months and 30 days" or "37:48:12". The input is a duration struct (calculated from two points in time, or from a number of seconds); the output is a localised length-of-time string.

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
{:ok, "Jan 1, 2020\u2009\u2013"}

iex> Localize.Interval.to_string(nil, ~D[2020-01-01], locale: :en)
{:ok, "\u2013\u2009Jan 1, 2020"}

iex> Localize.Interval.to_string(~D[2020-01-01], nil, locale: :ja)
{:ok, "2020/01/01\uFF5E"}

iex> Localize.Interval.to_string(nil, ~D[2020-01-01], locale: :ja)
{:ok, "\uFF5E2020/01/01"}
```

The separator comes from CLDR's `intervalFormatFallback` pattern for the locale — most Western locales use an en-dash (`–`), Japanese uses a fullwidth tilde (`～`), and so on. Passing `nil` for both endpoints returns an error.

### Styles and formats

The `:style` option controls which fields appear in the output:

| Style | Description | Example skeleton |
|---|---|---|
| `:date` | Full date (default) | `:yMMMd` |
| `:month` | Month only | `:MMM` |
| `:month_and_day` | Month and day | `:MMMd` |
| `:year_and_month` | Year and month | `:yMMM` |

The `:format` option selects the detail level: `:short`, `:medium` (default), or `:long`.

```elixir
iex> {:ok, result} =
...>   Localize.Interval.to_string(~D[2022-04-22], ~D[2022-04-25],
...>     locale: :en,
...>     style: :month_and_day,
...>     format: :long
...>   )
iex> String.contains?(result, "Fri") and String.contains?(result, "Mon")
true
```

### Intervals for times and datetimes

`Localize.Interval.to_string/3` accepts `Date`, `Time`, `NaiveDateTime`, and `DateTime` values, as well as any map with the appropriate fields. The formatting strategy depends on what fields differ:

* **Same-day datetime intervals** — format the date once with the start time and end time as a time range (`"Apr 8, 2026, 12:00 PM – 2:00 PM"`). The `:time_format` option (`:short`, `:medium`, `:long`) controls the time portion independently.

* **Different-day datetime intervals** — format both endpoints as full datetimes separated by the locale's interval fallback separator (`"Apr 15, 2026, 12:49 AM – Apr 16, 2026, 1:49 AM"`).

* **Time-only intervals** — use the locale's time-interval pattern (`"10:00 – 12:30 PM"`).

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

### How interval formatting works

1. The greatest difference between the two endpoints is identified (year, month, day, hour, or minute).

2. The `:style` and `:format` options resolve to a CLDR skeleton atom.

3. CLDR provides interval patterns that split the skeleton at the field that differs. This is why two dates in the same month produce "Apr 22 – 25, 2024" rather than repeating the month and year.

4. For open intervals (one endpoint is `nil`), the known endpoint is formatted using the appropriate single-value formatter (`Localize.Date`, `Localize.Time`, or `Localize.DateTime`), then substituted into the locale's `intervalFormatFallback` pattern with the appropriate trimming so only the separator on the "open" side remains.

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
{:ok, "11 months and 30 days"}
```

The `:style` option switches between `:long` (default), `:short`, and `:narrow` unit forms:

```elixir
iex> {:ok, d} = Localize.Duration.new(~D[2019-01-01], ~D[2019-12-31])
iex> Localize.Duration.to_string(d, locale: :en, style: :short)
{:ok, "11 mths and 30 days"}
```

The `:except` option drops specific units from the output. By default, `:microsecond` is excluded:

```elixir
iex> d = Localize.Duration.new_from_seconds(3665)
iex> Localize.Duration.to_string(d, locale: :en, except: [:microsecond, :second])
{:ok, "1 hour and 1 minute"}
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
