# Dates, times, intervals, durations, relative time

Most common calls:

| Task | Call |
|------|------|
| Format a date | `Localize.Date.to_string(~D[2026-07-06])` → `{:ok, "Jul 6, 2026"}` |
| Format a time | `Localize.Time.to_string(~T[14:30:00], prefer: :ascii)` → `{:ok, "2:30:00 PM"}` |
| Format a datetime | `Localize.DateTime.to_string(dt, format: :yMMMdHm)` |
| Date range | `Localize.Interval.to_string(from, to)` → `{:ok, "Jul 6 – 9, 2026"}` |
| "2 hours ago" | `Localize.DateTime.Relative.to_string(-7200)` |
| Elapsed time | `Localize.Duration.new!(d1, d2) \|> Localize.Duration.to_string()` |

All three formatters accept the corresponding struct (`Date`, `Time`, `DateTime`, `NaiveDateTime`) or a plain map with a subset of fields (partial dates like `%{year: 2026, month: 7}` work). Options common to all: `:locale`, `:format`, `:prefer`.

## Style and skeleton formats

`:format` accepts a standard style (`:short`, `:medium` — the default, `:long`, `:full`), a skeleton atom, or a literal pattern string. Prefer styles and skeletons: a skeleton names the fields you want and each locale arranges them its own way (order, separators, standalone vs formatted month names). Literal patterns freeze one locale's convention.

```elixir
Localize.Date.to_string(~D[2026-07-06], format: :short)
#=> {:ok, "7/6/26"}
Localize.Date.to_string(~D[2026-07-06], format: :full)
#=> {:ok, "Monday, July 6, 2026"}
Localize.Date.to_string(~D[2026-07-06], locale: :de)                          # same :medium, different locale
#=> {:ok, "06.07.2026"}
Localize.Date.to_string(~D[2026-07-06], locale: :ja)
#=> {:ok, "2026/07/06"}
```

Skeletons are matched against the locale's `availableFormats`; the closest pattern wins and field widths adapt. Common ones — dates: `:yMd`, `:yMMMd`, `:yMMMEd`, `:yMMM`, `:MMMd`, `:MMMEd`, `:Md`; times: `:Hm`, `:Hms`, `:hm`, `:hms`, `:EHm`; combined: `:yMMMdHm`.

```elixir
Localize.Date.to_string(~D[2026-07-06], format: :yMd)
#=> {:ok, "7/6/2026"}
Localize.Date.to_string(~D[2026-07-06], format: :yMMMEd)
#=> {:ok, "Mon, Jul 6, 2026"}
Localize.Date.to_string(~D[2026-07-06], format: :yMMMEd, locale: :de)         # same skeleton, German layout
#=> {:ok, "Mo., 6. Juli 2026"}
Localize.Time.to_string(~T[14:30:00], format: :Hm)                            # H forces 24-hour
#=> {:ok, "14:30"}
Localize.Time.to_string(~T[14:30:45], format: :hms, prefer: :ascii)
#=> {:ok, "2:30:45 PM"}
Localize.DateTime.to_string(~N[2026-07-06 14:30:00], format: :yMMMdHm)
#=> {:ok, "Jul 6, 2026, 14:30"}
Localize.DateTime.to_string(~N[2026-07-06 14:30:00], format: :EHm)
#=> {:ok, "Mon 14:30"}
Localize.Date.to_string(%{year: 2026, month: 7}, format: :yMMM)                # partial dates take skeletons
#=> {:ok, "Jul 2026"}
```

`Localize.DateTime.to_string/2` also takes `:date_format` and `:time_format` to mix style levels:

```elixir
Localize.DateTime.to_string(~N[2026-07-06 14:30:00], date_format: :full, time_format: :short, prefer: :ascii)
#=> {:ok, "Monday, July 6, 2026, 2:30 PM"}
```

## The :prefer option

Many locales publish `alt` pattern variants. `prefer: :ascii` replaces the Unicode narrow no-break space (U+202F) before AM/PM (and curly quotes) with plain ASCII — use it when output goes to systems that choke on invisible characters. `prefer: :variant` selects locale-variant patterns (en-CA's `:short` is ISO `"y-MM-dd"` by default; the variant is `d/M/yy`). Default is `[:standard, :unicode]`.

```elixir
Localize.Time.to_string(~T[14:30:00])                                          # real U+202F before PM
#=> {:ok, "2:30:00 PM"}
Localize.Time.to_string(~T[14:30:00], prefer: :ascii)
#=> {:ok, "2:30:00 PM"}
Localize.Date.to_string(~D[2026-07-06], format: :short, locale: "en-CA")
#=> {:ok, "2026-07-06"}
Localize.Date.to_string(~D[2026-07-06], format: :short, locale: "en-CA", prefer: :variant)
#=> {:ok, "6/7/26"}
```

## Pattern symbols (literal format strings)

| Symbol | Field | Notes (repeat count widens: 1 numeric, 2 zero-padded, 3 abbreviated, 4 wide, 5 narrow) |
|--------|-------|------|
| `G` | Era | `G`→AD, `GGGG`→Anno Domini |
| `y` | Year | `yy` → 2-digit |
| `Q` | Quarter | `QQQQ` → "3rd quarter" |
| `M` / `L` | Month / standalone month | `MMM`→Jul, `MMMM`→July |
| `w` | Week of year | numeric |
| `d` | Day of month | |
| `E` | Weekday name | `E`→Mon, `EEEE`→Monday |
| `a` / `B` | AM/PM / flexible day period | `B` → "in the afternoon" |
| `h` / `H` / `K` / `k` | Hour 1-12 / 0-23 / 0-11 / 1-24 | `h` needs `a` |
| `m` / `s` / `S` | Minute / second / fractional second | |
| `z` / `zzzz` | Zone abbreviation / full name | EDT / Eastern Daylight Time |
| `v` / `vvvv` | Generic zone short / long | ET / Eastern Time |
| `V`(`VV`) | Zone ID | America/New_York |
| `Z` / `ZZZZ` | Offset | -0400 / GMT-04:00 |
| `x` / `X` | ISO offset (X uses Z for zero) | -04:00 |

```elixir
Localize.Date.to_string(~D[2026-07-06], format: "EEEE d MMMM y")
#=> {:ok, "Monday 6 July 2026"}
Localize.Date.to_string(~D[2026-07-06], format: "G y")
#=> {:ok, "AD 2026"}
Localize.Date.to_string(~D[2026-07-06], format: "QQQQ")
#=> {:ok, "3rd quarter"}
Localize.Date.to_string(~D[2026-07-06], format: "w")                           # week of year
#=> {:ok, "28"}
Localize.DateTime.to_string(~N[2026-07-06 14:30:00], format: "B")
#=> {:ok, "in the afternoon"}
```

## Time zones

Zone symbols read the `DateTime`'s own zone fields plus CLDR zone-name data — the value must already be in the target zone (shift with `DateTime.shift_zone!/2` and a tz database first; Localize does not shift). A UTC `DateTime` formats with GMT names. `NaiveDateTime` has no zone, so zone symbols render empty.

```elixir
nyc = %DateTime{year: 2026, month: 7, day: 6, hour: 10, minute: 30, second: 0, microsecond: {0, 0},
                time_zone: "America/New_York", zone_abbr: "EDT", utc_offset: -18000, std_offset: 3600,
                calendar: Calendar.ISO}
Localize.DateTime.to_string(nyc, format: "HH:mm z")
#=> {:ok, "10:30 EDT"}
Localize.DateTime.to_string(nyc, format: "HH:mm zzzz")
#=> {:ok, "10:30 Eastern Daylight Time"}
Localize.DateTime.to_string(nyc, format: "HH:mm vvvv")                          # generic (no DST distinction)
#=> {:ok, "10:30 Eastern Time"}
Localize.DateTime.to_string(nyc, format: "ZZZZ")
#=> {:ok, "GMT-04:00"}
Localize.DateTime.to_string(~U[2026-07-06 14:30:00Z], format: :full, prefer: :ascii)
#=> {:ok, "Monday, July 6, 2026, 2:30:00 PM Greenwich Mean Time"}
```

## Hour cycle, calendars, digits

The locale's `-u-hc-` extension overrides the hour cycle for styles and `j`-based skeletons (`h12`, `h23`):

```elixir
Localize.Time.to_string(~T[14:30:00], locale: :de)                              # German defaults to 24-hour
#=> {:ok, "14:30:00"}
Localize.Time.to_string(~T[14:30:00], locale: "en-u-hc-h23")
#=> {:ok, "14:30:00"}
```

Non-Gregorian calendars: the formatter derives the CLDR calendar from the date's own `:calendar` module (any module exporting `cldr_calendar_type/0`, e.g. the ex_cldr_calendars packages). A `-u-ca-buddhist` locale extension does NOT convert an ISO date — `~D[2026-07-06]` still formats as "Jul 6, 2026". To render Buddhist/Japanese/etc. dates, convert the date to that calendar module first. Similarly, date digits come from the locale's own date formatting data — Thai locale renders Thai month names but keeps Latin digits, matching CLDR.

## Intervals

`Localize.Interval.to_string/3` formats two endpoints as one range, eliding shared fields (same month → "Jul 6 – 9, 2026", not two full dates). The separator and its spacing are locale data — English wraps the en dash in thin spaces (U+2009, shown by inspect as ` `); Japanese uses a fullwidth tilde. Accepts `Date`, `Time`, `NaiveDateTime`, `DateTime`, or maps; `nil` for one endpoint makes an open interval.

```elixir
Localize.Interval.to_string(~D[2026-07-06], ~D[2026-07-09])
#=> {:ok, "Jul 6\u2009–\u20099, 2026"}
Localize.Interval.to_string(~D[2026-01-15], ~D[2026-03-20])                      # month differs, both shown
#=> {:ok, "Jan 15\u2009–\u2009Mar 20, 2026"}
Localize.Interval.to_string(~D[2026-07-06], ~D[2026-07-09], style: :month_and_day, format: :long)
#=> {:ok, "Mon, Jul 6\u2009–\u2009Thu, Jul 9"}
Localize.Interval.to_string(~D[2026-01-15], ~D[2026-03-20], style: :year_and_month)
#=> {:ok, "Jan\u2009–\u2009Mar 2026"}
Localize.Interval.to_string(~D[2026-07-06], nil)                                 # open-ended
#=> {:ok, "Jul 6, 2026\u2009–"}
Localize.Interval.to_string(~D[2026-07-06], nil, locale: :ja)
#=> {:ok, "2026/07/06～"}
Localize.Interval.to_string(~T[10:00:00], ~T[12:30:00], prefer: :ascii)
#=> {:ok, "10:00:00 AM\u2009–\u200912:30:00 PM"}
Localize.Interval.to_string(~N[2026-07-06 12:00:00], ~N[2026-07-06 14:00:00], time_format: :short, prefer: :ascii)
#=> {:ok, "Jul 6, 2026, 12:00 PM\u2009–\u20092:00 PM"}
Localize.Interval.to_string(nil, nil)
#=> {:error, %Localize.DateTimeInvalidInputError{type: :datetime}}
```

Options: `:style` (`:date` default, `:month`, `:month_and_day`, `:year_and_month`), `:format` (`:short`/`:medium`/`:long`), `:time_format` for the time part of datetime intervals.

## Durations

A `Localize.Duration` is an amount of elapsed time (not two endpoints). Build with `new/2` / `new!/2` from two dates/times/datetimes or a `Date.Range`, or `new_from_seconds/1`.

```elixir
Localize.Duration.new(~D[2026-01-01], ~D[2026-12-31])
#=> {:ok, %Localize.Duration{year: 0, month: 11, day: 30, hour: 0, minute: 0, second: 0, microsecond: {0, 6}}}
Localize.Duration.new!(~D[2026-01-01], ~D[2026-12-31]) |> Localize.Duration.to_string()
#=> {:ok, "11 months and 30 days"}
Localize.Duration.new!(~D[2026-01-01], ~D[2026-12-31]) |> Localize.Duration.to_string(style: :narrow)
#=> {:ok, "11m and 30d"}
Localize.Duration.new_from_seconds(3665) |> Localize.Duration.to_string()
#=> {:ok, "1 hour, 1 minute, and 5 seconds"}
Localize.Duration.new_from_seconds(3665) |> Localize.Duration.to_string(except: [:second])
#=> {:ok, "1 hour and 1 minute"}
Localize.Duration.new!(~D[2026-01-01], ~D[2026-12-31]) |> Localize.Duration.to_string(locale: :fr)
#=> {:ok, "11\u00A0mois et 30\u00A0jours"}
```

Styles: `:long` (default), `:short`, `:narrow`. `:except` drops units (`:microsecond` is excluded by default). Unit names and the list conjunction are both locale data. `to_time_string/2` renders stopwatch style with unbounded hours; `:format` takes `h`/`hh`/`m`/`mm`/`s`/`ss` plus literals:

```elixir
Localize.Duration.new_from_seconds(136_092) |> Localize.Duration.to_time_string()
#=> {:ok, "37:48:12"}
Localize.Duration.new_from_seconds(65) |> Localize.Duration.to_time_string(format: "m:ss")
#=> {:ok, "1:05"}
```

## Relative time

`Localize.DateTime.Relative.to_string/2` renders "N units ago" / "in N units". A bare integer is seconds and the unit is auto-selected by magnitude. With an explicit `:unit`, the integer is a count of that unit (not seconds). `Date`/`DateTime` input is diffed against `:relative_to` (default: now). Offsets of -2..2 days use special forms ("yesterday", "tomorrow"); weekday units give "last/next Sunday".

```elixir
Localize.DateTime.Relative.to_string(-3600)
#=> {:ok, "1 hour ago"}
Localize.DateTime.Relative.to_string(30)
#=> {:ok, "in 30 seconds"}
Localize.DateTime.Relative.to_string(~D[2026-07-01], relative_to: ~D[2026-07-06])
#=> {:ok, "5 days ago"}
Localize.DateTime.Relative.to_string(1, unit: :day)
#=> {:ok, "tomorrow"}
Localize.DateTime.Relative.to_string(2, unit: :quarter)                          # integer is 2 quarters, not seconds
#=> {:ok, "in 2 quarters"}
Localize.DateTime.Relative.to_string(1, unit: :sun)
#=> {:ok, "next Sunday"}
Localize.DateTime.Relative.to_string(-18000, format: :short)
#=> {:ok, "5 hr. ago"}
Localize.DateTime.Relative.to_string(-18000, format: :narrow)
#=> {:ok, "5h ago"}
Localize.DateTime.Relative.to_string(-3600, locale: :de)
#=> {:ok, "vor 1 Stunde"}
Localize.DateTime.Relative.to_string(-3600, unit: :bogus)
#=> {:error, %Localize.InvalidValueError{value: :bogus, expected: :time_unit, allowed_values: [:day, :fri, :hour, :minute, :mon, :month, :quarter, :sat, :second, :sun, :thu, :tue, :wed, :week, :year], context: "Localize.DateTime.Relative"}}
```

## Standalone month/day/era names

`Localize.Calendar.localize/3` returns one localized name from a date — parts `:era`, `:quarter`, `:month`, `:day_of_week`, `:days_of_week` (list of tuples), `:am_pm`. Options: `format: :wide | :abbreviated | :narrow`, `era: :variant` ("CE" vs "AD"), `am_pm: :variant`, `context: :stand_alone`. Returns a bare string (not a tuple).

```elixir
Localize.Calendar.localize(~D[2026-07-06], :month)
#=> "Jul"
Localize.Calendar.localize(~D[2026-07-06], :month, format: :wide, locale: :fr)
#=> "juillet"
Localize.Calendar.localize(~D[2026-07-06], :day_of_week)
#=> "Mon"
Localize.Calendar.localize(~D[2026-07-06], :era, era: :variant)
#=> "CE"
Localize.Calendar.localize(~D[2026-07-06], :days_of_week, locale: :de)
#=> [{1, "Mo."}, {2, "Di."}, {3, "Mi."}, {4, "Do."}, {5, "Fr."}, {6, "Sa."}, {7, "So."}]
```

## Errors

```elixir
Localize.Date.to_string(~D[2026-07-06], format: :bogus)
#=> {:error, %Localize.DateTimeUnresolvedFormatError{format: :bogus, locale: :en}}
Localize.Date.to_string("2026-07-06")                                            # strings are not parsed
#=> {:error, %Localize.DateTimeInvalidInputError{type: :date}}
```

A time formatted with a date-only pattern does not error — date fields render as empty, leaving separator junk (`"//"`). Match the pattern to the value's fields.
