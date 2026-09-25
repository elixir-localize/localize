# Date and Time Formatting Guide

This guide explains how to use `Localize.Date`, `Localize.Time`, `Localize.DateTime`, and `Localize.DateTime.Relative` for locale-aware date and time formatting. Date/time ranges and elapsed durations have their own guide — see [Interval and Duration Formatting](https://hexdocs.pm/localize/interval_and_duration_formatting.html).

## Overview

Localize formats dates and times using CLDR pattern strings, locale-specific calendar names (months, days, eras, day periods), and Unicode TR35 field symbols. Each module accepts a struct or map and returns a locale-formatted string.

```elixir
iex> Localize.Date.to_string(~D[2024-07-10], locale: :en)
{:ok, "Jul 10, 2024"}

iex> Localize.Time.to_string(~T[14:30:00], locale: :en, prefer: :ascii)
{:ok, "2:30:00 PM"}

iex> Localize.DateTime.to_string(~N[2024-07-10 14:30:00], locale: :en, prefer: :ascii)
{:ok, "Jul 10, 2024, 2:30:00 PM"}
```

## Date formatting

### Standard formats

The `:format` option selects a predefined CLDR format. The default is `:medium`.

```elixir
iex> Localize.Date.to_string(~D[2024-07-10], format: :short, locale: :en)
{:ok, "7/10/24"}

iex> Localize.Date.to_string(~D[2024-07-10], format: :medium, locale: :en)
{:ok, "Jul 10, 2024"}

iex> Localize.Date.to_string(~D[2024-07-10], format: :long, locale: :en)
{:ok, "July 10, 2024"}

iex> Localize.Date.to_string(~D[2024-07-10], format: :full, locale: :en)
{:ok, "Wednesday, July 10, 2024"}
```

### Skeleton formats

Skeleton atoms specify which fields to include without prescribing the exact pattern. CLDR resolves each skeleton to a locale-appropriate pattern.

```elixir
iex> Localize.Date.to_string(~D[2024-07-10], format: :yMMMd, locale: :en)
{:ok, "Jul 10, 2024"}

iex> Localize.Date.to_string(~D[2024-07-10], format: :yMMMEd, locale: :en)
{:ok, "Wed, Jul 10, 2024"}

iex> Localize.Date.to_string(~D[2024-07-10], format: :yMd, locale: :en)
{:ok, "7/10/2024"}
```

Common date skeletons: `:yMd`, `:yMMMd`, `:yMMMEd`, `:yMMM`, `:yMMMM`, `:MMMd`, `:MMMEd`, `:Md`, `:MEd`.

### Semantic skeletons

A classical skeleton names fields. A *semantic* skeleton names what you mean, and lets CLDR choose the fields — TR35 added these so that "a year, a month, a day and a weekday" does not have to be spelled `:yMMMEd` in every locale:

```elixir
iex> skeleton = Localize.DateTime.SemanticSkeleton.semantic("YMDE")
iex> Localize.DateTime.to_string(~U[2024-07-06 14:30:45Z], format: skeleton, locale: :en)
{:ok, "Sat, Jul 6, 2024"}

iex> long = Localize.DateTime.SemanticSkeleton.semantic("YMD", length: :long)
iex> Localize.Date.to_string(~D[2024-07-06], format: long, locale: :en)
{:ok, "July 6, 2024"}
```

The letters name components — `Y` year, `M` month, `D` day, `E` weekday, `T` time, `Z` zone — and `:length`, `:year_style`, `:zone_style`, `:hour_cycle` and `:alignment` adjust the rendering. A semantic skeleton is accepted anywhere a classical one is: `Localize.Date`, `Localize.Time` and `Localize.DateTime` all take it as `:format`.

### Custom pattern strings

Pass a CLDR pattern string directly:

```elixir
iex> Localize.Date.to_string(~D[2024-07-10], format: "dd/MM/yyyy", locale: :en)
{:ok, "10/07/2024"}

iex> Localize.Date.to_string(~D[2024-07-10], format: "EEEE d MMMM y", locale: :en)
{:ok, "Wednesday 10 July 2024"}
```

### Partial dates

Maps with a subset of date fields are supported. A standard format, or no format, derives the skeleton from the fields present, with the month as wide as the format asks:

```elixir
iex> Localize.Date.to_string(%{year: 2024, month: 6}, locale: :en)
{:ok, "Jun 2024"}

iex> Localize.Date.to_string(%{year: 2024, month: 6}, format: :short, locale: :en)
{:ok, "6/2024"}

iex> Localize.Date.to_string(%{year: 2024, month: 6}, format: :yMMM, locale: :fr)
{:ok, "juin 2024"}
```

A skeleton or pattern that asks for a field the map does not have is an error rather than a blank in the output:

```elixir
iex> {:error, error} = Localize.Date.to_string(%{year: 2024, month: 6}, format: :yMMMd, locale: :en)
iex> Exception.message(error)
"The format \"MMM d, y\" cannot be applied to the value: missing :day."
```

### Locale influence on dates

Different locales produce different patterns, field orders, and calendar names:

```elixir
iex> Localize.Date.to_string(~D[2024-07-10], locale: :en)
{:ok, "Jul 10, 2024"}

iex> Localize.Date.to_string(~D[2024-07-10], locale: :de)
{:ok, "10.07.2024"}

iex> Localize.Date.to_string(~D[2024-07-10], locale: :ja)
{:ok, "2024/07/10"}

iex> Localize.Date.to_string(~D[2024-07-10], locale: :fr)
{:ok, "10 juil. 2024"}
```

## Time formatting

### Standard formats

```elixir
iex> Localize.Time.to_string(~T[14:30:00], format: :short, locale: :en, prefer: :ascii)
{:ok, "2:30 PM"}

iex> Localize.Time.to_string(~T[14:30:00], format: :medium, locale: :en, prefer: :ascii)
{:ok, "2:30:00 PM"}
```

### The `:prefer` option

CLDR provides two variants for time patterns in many locales: one using Unicode characters (curly quotes, non-breaking spaces) and one using ASCII equivalents. The `:prefer` option selects which variant to use. The default is `:unicode`.

```elixir
iex> Localize.Time.to_string(~T[14:30:00], locale: :en, prefer: :ascii)
{:ok, "2:30:00 PM"}
```

### 12-hour vs 24-hour clocks

The hour cycle is determined by the locale. English defaults to 12-hour with AM/PM, while German and Japanese default to 24-hour:

```elixir
iex> Localize.Time.to_string(~T[14:30:00], locale: :en, prefer: :ascii)
{:ok, "2:30:00 PM"}

iex> Localize.Time.to_string(~T[14:30:00], locale: :de)
{:ok, "14:30:00"}

iex> Localize.Time.to_string(~T[14:30:00], locale: :ja)
{:ok, "14:30:00"}
```

A `-u-hc-` locale extension replaces the locale's preferred hour cycle, which the standard formats and a skeleton's `j` and `J` follow, and the hour takes that cycle's symbol, so `h11` counts hours from 0 to 11 and `h24` from 1 to 24. An explicit `h` or `H` in a skeleton keeps the cycle it names, and `C`, which asks for the first of the locale's allowed hour formats, is not overridden. `J` asks for the preferred hour without a day period:

```elixir
iex> Localize.Time.to_string(~T[00:30:00], format: :short, locale: "en-u-hc-h11", prefer: :ascii)
{:ok, "0:30 AM"}

iex> Localize.Time.to_string(~T[00:30:00], format: :short, locale: "en-u-hc-h24")
{:ok, "24:30"}

iex> Localize.Time.to_string(~T[21:00:00], format: :Hm, locale: "en-u-hc-h12")
{:ok, "21:00"}

iex> Localize.Time.to_string(~T[18:00:00], format: :Jmm, locale: :en)
{:ok, "6:00"}
```

### Partial times

Maps with a subset of time fields are supported. Without a skeleton the hour follows the locale's hour cycle, or a `-u-hc-` override:

```elixir
iex> Localize.Time.to_string(%{hour: 14, minute: 30}, format: :hm, locale: :en, prefer: :ascii)
{:ok, "2:30 PM"}

iex> Localize.Time.to_string(%{hour: 14, minute: 30}, locale: :de)
{:ok, "14:30"}

iex> Localize.Time.to_string(%{hour: 14, minute: 30}, locale: "en-u-hc-h23")
{:ok, "14:30"}
```

## DateTime formatting

`Localize.DateTime.to_string/2` formats combined date-and-time values. It accepts `DateTime`, `NaiveDateTime`, and maps.

### Standard formats

```elixir
iex> Localize.DateTime.to_string(~N[2024-07-10 14:30:00], format: :short, locale: :en, prefer: :ascii)
{:ok, "7/10/24, 2:30 PM"}

iex> Localize.DateTime.to_string(~N[2024-07-10 14:30:00], format: :medium, locale: :en, prefer: :ascii)
{:ok, "Jul 10, 2024, 2:30:00 PM"}
```

### Separate date and time formats

Combine different format levels for the date and time portions:

```elixir
iex> Localize.DateTime.to_string(~N[2024-07-10 14:30:00], date_format: :full, time_format: :short, locale: :en, prefer: :ascii)
{:ok, "Wednesday, July 10, 2024 at 2:30 PM"}
```

### Partial datetimes

A map holding only some of the date and time fields formats its date half and its time half separately, then joins them with the locale's date-time pattern, so no field is dropped:

```elixir
iex> Localize.DateTime.to_string(%{year: 2026, month: 6, day: 15, hour: 14}, locale: :en, prefer: :ascii)
{:ok, "Jun 15, 2026, 2 PM"}

iex> Localize.DateTime.to_string(%{year: 2026, month: 6, hour: 14}, locale: :en, prefer: :ascii)
{:ok, "Jun 2026, 2 PM"}
```

### Locale influence on datetimes

```elixir
iex> Localize.DateTime.to_string(~N[2024-07-10 14:30:00], locale: :en, prefer: :ascii)
{:ok, "Jul 10, 2024, 2:30:00 PM"}

iex> Localize.DateTime.to_string(~N[2024-07-10 14:30:00], locale: :de, prefer: :ascii)
{:ok, "10.07.2024, 14:30:00"}
```

### Choosing the numeric separators

CLDR 49 records the separator each locale uses between the fields of a numeric date and between the fields of a time, so an application can offer the choice. TR35 designates this section a **technical preview**, so the data and the behaviour may change — dates as "05/06/2006" or "05-06-2006", times as "23:59" or "23.59". Read the locale's own with `Localize.DateTime.numeric_separators/2` and override either axis with `:numeric_date_separator` and `:numeric_time_separator`.

```elixir
iex> Localize.DateTime.numeric_separators(:en)
{:ok, %{numeric_date_separator: "/", numeric_time_separator: ":"}}

iex> Localize.Date.to_string(~D[2024-07-06], format: :yMd, locale: :en, numeric_date_separator: "-")
{:ok, "7-6-2024"}

iex> Localize.DateTime.to_string(~U[2024-07-06 14:05:09Z], format: :short, locale: :en, numeric_time_separator: ".", prefer: :ascii)
{:ok, "7/6/24, 2.05 PM"}
```

The two axes stay independent even where a locale spells both the same — `fi` writes both as a full stop, and each option changes only its own half. Two limits follow TR35: the date separator applies only to patterns whose month is numeric (`M` or `MM`), and a separator the pattern merges with neighbouring literal text is left alone rather than risk rewriting text that merely contains the same character.

### Automatic date-only and time-only fallback

When a map contains only date fields or only time fields, `Localize.DateTime.to_string/2` delegates to `Localize.Date` or `Localize.Time` automatically.

## Interval and Duration formatting

Formatting ranges between two dates ("Apr 22 – 25, 2024"), open intervals ("Jan 1, 2020 –"), and elapsed durations ("11 months, 30 days" or "37:48:12") is covered in a dedicated guide — see [Interval and Duration Formatting](https://hexdocs.pm/localize/interval_and_duration_formatting.html).

## Relative time formatting

`Localize.DateTime.Relative.to_string/2` formats time differences as human-readable phrases like "2 hours ago" or "in 3 days".

### From integer seconds

```elixir
iex> Localize.DateTime.Relative.to_string(-60, locale: :en)
{:ok, "1 minute ago"}

iex> Localize.DateTime.Relative.to_string(3600, locale: :en)
{:ok, "in 1 hour"}
```

### A number of units

With `:unit`, the number is a count of that unit and may be fractional. It is formatted for the locale, and the plural category of the number as displayed selects the pattern:

```elixir
iex> Localize.DateTime.Relative.to_string(1.5, unit: :hour, locale: :en)
{:ok, "in 1.5 hours"}

iex> Localize.DateTime.Relative.to_string(1.5, unit: :day, locale: :fr)
{:ok, "dans 1,5 jour"}

iex> Localize.DateTime.Relative.to_string(-1000, unit: :day, locale: :de)
{:ok, "vor 1.000 Tagen"}
```

### From dates and datetimes

When given a `Date`, `DateTime`, or `Time`, the difference is calculated relative to now (or the `:relative_to` option):

```elixir
Localize.DateTime.Relative.to_string(~D[2024-01-01], relative_to: ~D[2024-01-04], locale: :en)
{:ok, "3 days ago"}
```

### Format styles

```elixir
iex> Localize.DateTime.Relative.to_string(-18000, format: :standard, locale: :en)
{:ok, "5 hours ago"}

iex> Localize.DateTime.Relative.to_string(-18000, format: :short, locale: :en)
{:ok, "5 hr. ago"}

iex> Localize.DateTime.Relative.to_string(-18000, format: :narrow, locale: :en)
{:ok, "5h ago"}
```

### Special ordinal forms

For offsets of -2 to +2 days, many locales provide special names:

* -1 day: "yesterday"
* 0 days: "today"
* +1 day: "tomorrow"

The `:numeric` option controls whether these named forms are used, mirroring ECMA-402's `RelativeTimeFormat` `numeric` option. `:auto` (the default) prefers the named forms; `:always` forces numeric output:

```elixir
iex> Localize.DateTime.Relative.to_string(-1, unit: :day, locale: :en, numeric: :always)
{:ok, "1 day ago"}

iex> Localize.DateTime.Relative.to_string(0, unit: :day, locale: :en, numeric: :always)
{:ok, "in 0 days"}
```

## Parsing

Parsing is the inverse of formatting and reads the same CLDR data, so a locale that formats a date one way accepts that shape back. Each function parses one shape and returns `{:ok, value}` or `{:error, exception}`; none of them raise.

| Function | Returns |
|----------|---------|
| `Localize.Date.parse/2` | `t:Date.t/0` |
| `Localize.Time.parse/2` | `t:Time.t/0` |
| `Localize.DateTime.parse/2` | `t:NaiveDateTime.t/0`, or `t:DateTime.t/0` when the input carries a zone |
| `Localize.Interval.parse/2` | `t:Date.Range.t/0` |
| `Localize.DateTime.Parser.parse/2` | whichever of the four the input turns out to be |

### Dates and times

Input is matched against the locale's own short, medium, long and full patterns, so each locale accepts what it produces:

```elixir
iex> Localize.Date.parse("March 22, 2026", locale: :en)
{:ok, ~D[2026-03-22]}

iex> Localize.Date.parse("22.03.2026", locale: :de)
{:ok, ~D[2026-03-22]}

iex> Localize.Date.parse("22/03/2026", locale: :fr)
{:ok, ~D[2026-03-22]}
```

ISO 8601 is always accepted as well, in every locale, so a wire-format value needs no special handling:

```elixir
iex> Localize.Date.parse("2026-03-22", locale: :de)
{:ok, ~D[2026-03-22]}
```

Parsing is lenient about the decoration a locale allows. A weekday is read wherever the locale's formats place it, and a leading one is stripped from a format that has none. An era is read, stand-alone and format month names are both accepted, and week and quarter forms resolve to the date they begin. Weeks are numbered by the locale's own rules, so an `en` week begins on a Sunday:

```elixir
iex> Localize.Date.parse("Saturday, May 16, 2026", locale: :en)
{:ok, ~D[2026-05-16]}

iex> Localize.Date.parse("Jan 21, 2024 AD", locale: :en)
{:ok, ~D[2024-01-21]}

iex> Localize.Date.parse("week 20 of 2026", locale: :en)
{:ok, ~D[2026-05-10]}

iex> Localize.Date.parse("Q2 2026", locale: :en)
{:ok, ~D[2026-04-01]}
```

Times follow the locale's hour cycle, so a 12-hour locale accepts a day period and a 24-hour locale does not need one:

```elixir
iex> Localize.Time.parse("2:30 PM", locale: :en)
{:ok, ~T[14:30:00]}

iex> Localize.Time.parse("14:30", locale: :de)
{:ok, ~T[14:30:00]}
```

### Partial input

Input that omits the year is completed from a reference date, today by default, with `:reference_date` setting a different one:

```elixir
# The year comes from today, so this result moves with the calendar
iex> Localize.Date.parse("March 22", locale: :en)
{:ok, ~D[2026-03-22]}

# Pin it with :reference_date
iex> Localize.Date.parse("March 22", locale: :en, reference_date: ~D[2020-07-15])
{:ok, ~D[2020-03-22]}
```

Input that omits the *day* is a different matter: there is no `t:Date.t/0` for "March 2026", so it returns a `Localize.DateParseError` rather than inventing the first of the month. Pass `as: :map` to get the fields the input actually carried:

```elixir
iex> Localize.Date.parse("March 2026", locale: :en)
{:error, %Localize.DateParseError{input: "March 2026", locale: :en, calendar: :gregorian}}

iex> Localize.Date.parse("March 2026", locale: :en, as: :map)
{:ok, %{calendar: Calendar.ISO, month: 3, year: 2026}}
```

`as: :map` is the option to reach for when a form field genuinely means "March 2026" and completing it to a day would be a lie. It works the same way on `Localize.Time.parse/2`, `Localize.DateTime.parse/2` and `Localize.Interval.parse/2`.

### Intervals

`Localize.Interval.parse/2` takes either one string, which it splits on the locale's own interval separator, or a `{from, to}` pair for a two-input form that already has the endpoints apart:

```elixir
iex> Localize.Interval.parse("May 5 – May 10, 2026", locale: :en)
{:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}

iex> Localize.Interval.parse("5.–10. Mai 2026", locale: :de)
{:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}

iex> Localize.Interval.parse({"2026-05-05", "2026-05-10"})
{:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}
```

Fields missing from one endpoint are inherited from the other, following the CLDR interval convention, so `"5.–10. Mai 2026"` gives both endpoints a month and a year. An end-before-start interval is rejected unless `allow_inverted: true` is passed.

### When the shape is not known

A single text field that may hold any of these shapes is what `Localize.DateTime.Parser.parse/2` is for. It tries interval, date, time and datetime in that order and returns the first that matches, so the caller pattern-matches on the result to find out what arrived:

```elixir
iex> Localize.DateTime.Parser.parse("March 22, 2026", locale: :en)
{:ok, ~D[2026-03-22]}

iex> Localize.DateTime.Parser.parse("3:45 PM", locale: :en)
{:ok, ~T[15:45:00]}

iex> Localize.DateTime.Parser.parse("May 5, 2026 – May 10, 2026", locale: :en)
{:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}
```

When nothing matches, the returned `Localize.DateTimeParseError` carries an `:attempts` list recording what each sub-parser reported — useful for telling a user *why* their input was rejected rather than just that it was.

### Time zones

A datetime carrying a fixed UTC offset resolves to a `t:DateTime.t/0`. The offset may be written ISO 8601 style or in the locale's GMT format, in that locale's own spelling, and both produce the same struct — the wall time you wrote, with the offset attached rather than normalised away:

```elixir
iex> Localize.DateTime.parse("May 16, 2026 2:30 PM GMT+10:30", locale: :en)
{:ok, #DateTime<2026-05-16 14:30:00+10:30>}

iex> Localize.DateTime.parse("2026-05-16T14:30:00+10:30", locale: :en)
{:ok, #DateTime<2026-05-16 14:30:00+10:30>}
```

Shift to UTC yourself with `DateTime.shift_zone/3` when you want it; the parser does not do it for you, because the original offset cannot be recovered afterwards.

A *named* zone — `"PST"`, `"Asia/Tokyo"` — carries no offset of its own and needs a time-zone database to resolve, which this library does not ship. Without one the zone is dropped and the parse still succeeds, returning a `t:NaiveDateTime.t/0` rather than failing the whole input:

```elixir
iex> Localize.DateTime.parse("May 16, 2026 2:30 PM Asia/Tokyo", locale: :en)
{:ok, ~N[2026-05-16 14:30:00]}
```

Add [calendrical](https://hex.pm/packages/calendrical) to resolve named zones to a `t:DateTime.t/0`.

### Calendars

The `:calendar` option accepts a CLDR calendar name or a calendar module, and parsing needs that calendar's module to be **available at runtime**. `Calendar.ISO` — the Elixir default, and CLDR's `:gregorian` — is always available, so the default case never requires anything extra. Every other calendar is supplied by [calendrical](https://hex.pm/packages/calendrical):

```elixir
# Always available
Localize.Date.parse("22.03.2026", locale: :de, calendar: Calendar.ISO)
#=> {:ok, ~D[2026-03-22]}

# Needs calendrical
Localize.Date.parse("22.03.2026", locale: :de, calendar: :hebrew)
#=> {:error, %Localize.DependencyRequiredError{package: "calendrical"}}

# Not a calendar at all
Localize.Date.parse("22.03.2026", locale: :de, calendar: :bogus)
#=> {:error, %Localize.UnknownCalendarError{calendar: :bogus}}
```

The calendar is resolved before any parsing happens, so the answer does not depend on the shape of the input: ISO 8601 and locale-formatted text both return the same error for the same `:calendar`. A `Localize.DependencyRequiredError` names the package to add; a `Localize.UnknownCalendarError` means the calendar is not a CLDR calendar and not a `Calendar` implementation. Any module implementing the `Calendar` behaviour is accepted directly, so a custom calendar needs no CLDR registration.

`:return_calendar` governs the calendar of the returned date, not the one the input is read in, so it does not waive this — parsing "1 Tishrei 5787" still needs the Hebrew calendar even when you want an ISO date back.

A time carries no date fields, so `Localize.Time.parse/2` resolves no calendar and the option has no effect there.

## Format pattern reference

CLDR format patterns use field symbols to represent date and time components. Each symbol can be repeated to control the output width.

A symbol takes only the widths TR35's Date Field Symbol Table lists for it. At any other width — `dddd`, `MMMMMM`, `HHH` — the field is invalid and formats as U+FFFD (�), as TR35's Handling Invalid Patterns recommends, and a letter the table does not define, such as `n`, makes the pattern an error. A skeleton passes the width it asks for on to the pattern wherever TR35's matching adjusts widths, so `:MMMMMMd` formats its month as U+FFFD too. ICU pads, clamps or drops such fields instead; see [ICU divergences](icu_divergences.md).

### Date field symbols

| Symbol | Meaning | 1 | 2 | 3 | 4 | 5 |
|--------|---------|---|---|---|---|---|
| `G` | Era | AD | AD | AD | Anno Domini | A |
| `y` | Year | 2024 | 24 | 2024 | 2024 | 02024 |
| `M` | Month | 7 | 07 | Jul | July | J |
| `L` | Standalone month | 7 | 07 | Jul | July | J |
| `d` | Day of month | 1 | 01 | 1st | � | � |
| `E` | Day name | Mon | Mon | Mon | Monday | M |
| `e` | Day of week (numeric) | 2 | 02 | Mon | Monday | M |
| `c` | Standalone day | 2 | 2 | Mon | Monday | M |
| `Q` | Quarter | 3 | 03 | Q3 | 3rd quarter | 3 |

`ddd` is CLDR 49's ordinal day of month and is a **technical preview** — TR35 designates the `dayOfMonth` section one, so both the output and the surface may change. It is taken from the locale's `dayOfMonths` data for the ordinal plural category the day selects — `:yMMMddd` renders "Jul 6th, 2024" in `en` and "1er juil. 2024" in `fr`. Only some locales carry that data; the rest format the plain day, as does any pattern whose month is numeric (`M` or `MM`), where TR35 says `ddd` is ignored. A skeleton asking for `ddd` where the locale has no `ddd` format matches its `d` format instead, and the pattern's `d` is left at its own width rather than being widened.

### Time field symbols

| Symbol | Meaning | 1 | 2 |
|--------|---------|---|---|
| `h` | Hour (1-12) | 2 | 02 |
| `H` | Hour (0-23) | 14 | 14 |
| `K` | Hour (0-11) | 2 | 02 |
| `k` | Hour (1-24) | 14 | 14 |
| `m` | Minute | 5 | 05 |
| `s` | Second | 9 | 09 |
| `S` | Fractional second | 1-N digits | |
| `a` | AM/PM | PM | PM |

### Timezone field symbols

| Symbol | Count | Example |
|--------|-------|---------|
| `z` | 1-3 | EST |
| `z` | 4 | Eastern Standard Time |
| `Z` | 1-3 | +0500 |
| `Z` | 4 | GMT+05:00 |
| `Z` | 5 | +05:00 or Z |
| `O` | 1 | GMT+5 |
| `O` | 4 | GMT+05:00 |
| `v` | 1 | ET |
| `v` | 4 | Eastern Time |
| `V` | 1 | usnyc (BCP 47 short zone id) |
| `V` | 2 | America/New_York |
| `V` | 3 | New York (exemplar city) |
| `V` | 4 | New York Time (generic location) |
| `X` | 1-5 | +05, +0500, +05:00 (Z for zero) |
| `x` | 1-5 | +05, +0500, +05:00 (no Z) |

### Hour cycles

The hour symbol determines the cycle:

* `h` — 12-hour (1-12), requires AM/PM (`a`).
* `H` — 24-hour (0-23), no AM/PM.
* `K` — 12-hour (0-11), requires AM/PM.
* `k` — 24-hour (1-24), where 24 means midnight.

Skeleton atoms can use `j` as a meta-symbol that resolves to the locale's preferred hour cycle.

## Options reference

### `Localize.Date.to_string/2`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:locale` | atom, string, or `LanguageTag` | `Localize.get_locale()` | Locale for patterns and calendar names. |
| `:format` | atom, semantic skeleton, or pattern string | `:medium` | Standard name (`:short`, `:medium`, `:long`, `:full`), skeleton atom, `Localize.DateTime.SemanticSkeleton` struct, or custom pattern. |
| `:prefer` | `:unicode` or `:ascii` | `:unicode` | Selects Unicode or ASCII variant of the format pattern. |

### `Localize.Time.to_string/2`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:locale` | atom, string, or `LanguageTag` | `Localize.get_locale()` | Locale for patterns and day period names. |
| `:format` | atom, semantic skeleton, or pattern string | `:medium` | Standard name, skeleton atom, `Localize.DateTime.SemanticSkeleton` struct, or custom pattern. |
| `:prefer` | `:unicode` or `:ascii` | `:unicode` | Selects Unicode or ASCII variant. |

### `Localize.DateTime.to_string/2`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:locale` | atom, string, or `LanguageTag` | `Localize.get_locale()` | Locale for patterns and calendar names. |
| `:format` | atom, semantic skeleton, or pattern string | `:medium` | Standard name, skeleton atom, `Localize.DateTime.SemanticSkeleton` struct, or custom pattern. |
| `:date_format` | atom | (same as `:format`) | Format level for the date portion when using separate levels. |
| `:time_format` | atom | (same as `:format`) | Format level for the time portion when using separate levels. |
| `:style` | atom | `:at` | Wrapper joining date and time. `:at` is TR35's default for an event time ("July 6, 2024 at 2:30 PM"); `:default` is the standard wrapper, for a current time ("July 6, 2024, 2:30 PM"). CLDR defines the "at" wrapper only for `:full` and `:long`. |
| `:prefer` | `:unicode` or `:ascii` | `:unicode` | Selects Unicode or ASCII variant. |

### `Localize.Interval.to_string/3`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:locale` | atom, string, or `LanguageTag` | `Localize.get_locale()` | Locale for patterns and calendar names. |
| `:format` | atom | `:medium` | Detail level: `:short`, `:medium`, or `:long`. |
| `:style` | atom | `:date` | Field scope: `:date`, `:month`, `:month_and_day`, or `:year_and_month`. |

### `Localize.DateTime.Relative.to_string/2`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:locale` | atom, string, or `LanguageTag` | `Localize.get_locale()` | Locale for patterns, pluralization, and the number's digits and grouping. |
| `:format` | atom | `:standard` | Width: `:standard`, `:short`, or `:narrow`. |
| `:unit` | atom | (auto-derived) | Explicit unit: `:second`, `:minute`, `:hour`, `:day`, `:week`, `:month`, `:quarter`, `:year`, or a weekday from `:mon` to `:sun`. |
| `:numeric` | atom | `:auto` | `:auto` uses named forms such as "yesterday" for offsets of -2 to 2; `:always` is always numeric. |
| `:relative_to` | `Date`, `Time`, `NaiveDateTime`, or `DateTime` | `DateTime.utc_now()` | Baseline for calculating the difference. |
