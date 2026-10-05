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

The letters name components — `Y` year, `M` month, `D` day, `E` weekday, `T` time, `Z` zone — and `:length`, `:year_style`, `:zone_style`, `:zone_length`, `:hour_cycle`, `:time_precision` and `:alignment` adjust the rendering. The letters form a set, in any order, and only the sets TR35 defines are accepted: `YD`, a year and a day without a month, is an error, as is an option for fields the set lacks, such as `:year_style` without `Y`. A semantic skeleton is accepted anywhere a classical one is: `Localize.Date`, `Localize.Time` and `Localize.DateTime` all take it as `:format`.

The year, month and day take their widths from the locale's own date format at the requested length, as TR35 specifies, so a year, month and day is the standard date format of that length: numeric in German at medium length, where English abbreviates the month. A time shows its seconds unless `:time_precision` asks for `:hour` or `:minute`:

```elixir
iex> Localize.Date.to_string(~D[2024-07-06], format: Localize.DateTime.SemanticSkeleton.semantic("YMD"), locale: :de)
{:ok, "06.07.2024"}

iex> skeleton = Localize.DateTime.SemanticSkeleton.semantic("T", time_precision: :minute)
iex> Localize.Time.to_string(~T[14:30:45], format: skeleton, locale: :en, prefer: :ascii)
{:ok, "2:30 PM"}
```

Dates and times set in a column line up when their numbers are the same width, which `alignment: :column` arranges: a numeric month, day and hour are padded to two digits, in the locale's own digits, while a spelled-out month stays as it is:

```elixir
iex> column = Localize.DateTime.SemanticSkeleton.semantic("YMD", length: :short, alignment: :column)
iex> Localize.Date.to_string(~D[2025-01-05], format: column, locale: :en)
{:ok, "01/05/25"}
```

MessageFormat 2's `:date`, `:time` and `:datetime` functions are built on semantic skeletons; see the [message formatting guide](message_formatting.md).

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

A value is checked against its calendar wherever it enters: a date or a time the calendar does not have is an error rather than a string written from impossible fields. A partial date is checked by the fields it holds, a year and a month as the month's first day, so a month and day without a year may be any year's:

```elixir
iex> {:error, error} = Localize.Date.to_string(%{year: 2023, month: 2, day: 29}, locale: :en)
iex> error.expected
"a date its calendar has"

iex> Localize.Date.to_string(%{month: 2, day: 29}, format: "MMM d", locale: :en)
{:ok, "Feb 29"}
```

An era needs only the year wherever a calendar's eras begin with its years. In the Japanese calendar, whose eras begin mid-year, a partial date in the year or month an era began is an error naming the fields that would settle it:

```elixir
iex> Localize.Date.to_string(%{year: 2024, month: 6}, format: :GyMMM, locale: :en)
{:ok, "Jun 2024 AD"}
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

The `:long` and `:full` patterns end in a time zone. A value with no zone, a `Time`, a `NaiveDateTime` or a map without one, has nothing to write that field with, so those formats write their other fields as the locale writes them alone, and a date and time joins its date to the same time:

```elixir
iex> Localize.Time.to_string(~T[10:30:00], format: :full, locale: :ja)
{:ok, "10:30:00"}

iex> Localize.DateTime.to_string(~N[2024-04-03 10:30:00], format: :full, locale: :ja)
{:ok, "2024年4月3日水曜日 10:30:00"}
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

### From a number of seconds

Without `:unit`, a number is a number of seconds. Seconds have no calendar, so they are counted, to the nearest, in the largest of weeks, days, hours, minutes and seconds they reach, and never in months, quarters or years:

```elixir
iex> Localize.DateTime.Relative.to_string(-60, locale: :en)
{:ok, "1 minute ago"}

iex> Localize.DateTime.Relative.to_string(3600, locale: :en)
{:ok, "in 1 hour"}

iex> Localize.DateTime.Relative.to_string(31_556_926, locale: :en)
{:ok, "in 52 weeks"}
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

Given a `Date`, `Time`, `NaiveDateTime` or `DateTime`, the difference from now, or from the `:relative_to` option, is formatted. It is counted with the arithmetic of the value's calendar, in the calendar periods between the two: the years, quarters, months, weeks and days between their dates, and the hours, minutes and seconds between their clocks. A month is a month of the value's calendar whatever its length, so 31 January is "last month" from 1 February:

```elixir
iex> Localize.DateTime.Relative.to_string(~D[2024-01-01], relative_to: ~D[2024-01-04], locale: :en)
{:ok, "3 days ago"}

iex> Localize.DateTime.Relative.to_string(~D[2024-01-31], relative_to: ~D[2024-02-01], unit: :month, locale: :en)
{:ok, "last month"}
```

Without `:unit`, the unit is the largest of which a whole one lies between the two, from a year down to a day for dates and to a second for times:

```elixir
iex> Localize.DateTime.Relative.to_string(~D[2024-03-15], relative_to: ~D[2024-01-01], locale: :en)
{:ok, "in 2 months"}
```

A week, and a weekday unit such as `:mon`, count calendar weeks, each starting on the locale's first day of the week. So "next Monday" is the Monday of the week after the baseline's, and a Monday is "next Monday" from the Sunday before it where weeks start on Monday, and "this Monday" where they start on Sunday:

```elixir
iex> Localize.DateTime.Relative.to_string(~D[2024-06-17], relative_to: ~D[2024-06-16], unit: :mon, locale: :"en-GB")
{:ok, "next Monday"}

iex> Localize.DateTime.Relative.to_string(~D[2024-06-17], relative_to: ~D[2024-06-16], unit: :mon, locale: :"en-US")
{:ok, "this Monday"}
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

Input is matched against the locale's own short, medium, long and full patterns, and then its other available formats, so each locale accepts what it produces and an ambiguous numeric date is read the way the locale writes it:

```elixir
iex> Localize.Date.parse("March 22, 2026", locale: :en)
{:ok, ~D[2026-03-22]}

iex> Localize.Date.parse("22.03.2026", locale: :de)
{:ok, ~D[2026-03-22]}

iex> Localize.Date.parse("22/03/2026", locale: :fr)
{:ok, ~D[2026-03-22]}
```

ISO 8601 is always accepted as well, in every locale, so a wire-format value needs no special handling (for a `:calendar` other than `Calendar.ISO`, see [Calendars](#calendars)):

```elixir
iex> Localize.Date.parse("2026-03-22", locale: :de)
{:ok, ~D[2026-03-22]}
```

Its other date forms are read too: without separators ("20260322"), by the day of the year ("2026-081", "2026081") and by the week, with its day ("2026-W12-7", "2026W127") or without one. A week without a day is the week's first day, and its weeks are ISO 8601's, from Monday, whatever the locale's are. A year and a month, or a year alone, is no date and is read `as: :map`:

```elixir
iex> Localize.Date.parse("2026-W25", locale: :en)
{:ok, ~D[2026-06-15]}

iex> Localize.Date.parse("2026-W25", locale: :en, as: :map)
{:ok, %{calendar: Calendar.ISO, year: 2026, week_based_year: 2026, week_of_year: 25}}

iex> Localize.Date.parse("2026-03", locale: :en, as: :map)
{:ok, %{calendar: Calendar.ISO, year: 2026, month: 3}}
```

A date and time takes any of those dates that names a day before ISO 8601's `T`, and after it a time with its seconds, or its minutes and seconds, left out, as an HTML `datetime-local` field writes one. Either half may be written without its separators, and an offset or `Z` after the time is kept. Read `as: :map`, the time holds the fields it wrote. A fraction is the second's alone: a fraction of a minute or of an hour ("10:30,5") is not read, and neither is a time of 24:00.

```elixir
iex> Localize.DateTime.parse("2026-03-22T14:30", locale: :de)
{:ok, ~N[2026-03-22 14:30:00]}

iex> Localize.DateTime.parse("2026-W12-7T14:30:00", locale: :de)
{:ok, ~N[2026-03-22 14:30:00]}

iex> Localize.DateTime.parse("20260322T143000Z", locale: :de)
{:ok, ~U[2026-03-22 14:30:00Z]}

iex> Localize.DateTime.parse("2026-081T14:30", locale: :de, as: :map)
{:ok, %{calendar: Calendar.ISO, year: 2026, month: 3, day: 22, hour: 14, minute: 30}}
```

Parsing is lenient about the decoration a locale allows. A weekday is read wherever the locale's formats place it, and a leading one is stripped from a format that has none. An era is read and its year counts from it, so 1 BC is year 0 and a two-digit year a format writes in full beside an era is taken as written, where ICU would move it into this century (see [ICU divergences](icu_divergences.md#date-parsing)). A format that writes the year as `yy`, its two low-order digits, is read in the century around the reference year even beside an era, as ICU reads it: `de`'s Buddhist "01.04.66 BE" is 2566 BE, and in a calendar that shows years of an era the digits are the year of that era, so `de`'s Japanese "01.04.05 R" is Reiwa 5. Stand-alone and format month names are both accepted, and week and quarter forms resolve to the date they begin. Dates, times and date-times written in the digits of the locale's number system are read as their Latin-digit forms are — `bn`'s "১০:০৫ AM" is 10:05, and names written in those digits, such as `dz`'s months, which are Tibetan numbers, are read too — and Latin digits are always accepted. A field a format writes in an algorithmic numbering is read as it is written: `haw`'s months in Roman numerals ("16/vi/26") and the 元 `ja` writes for the first year of a Japanese era ("令和元年5月1日"). Week text is read in the weeks it is written in: a calendar's own, and for `Calendar.ISO`, which has none of its own, the locale's, so week 20 of 2026 begins on Sunday 10 May in `en` and on Monday 11 May in `en-GB`:

```elixir
iex> Localize.Date.parse("Saturday, May 16, 2026", locale: :en)
{:ok, ~D[2026-05-16]}

iex> Localize.Date.parse("Jan 21, 2024 AD", locale: :en)
{:ok, ~D[2024-01-21]}

iex> Localize.Date.parse("Mar 15, 44 BC", locale: :en)
{:ok, ~D[-0043-03-15]}

iex> Localize.Date.parse("week 20 of 2026", locale: :en)
{:ok, ~D[2026-05-10]}

iex> Localize.Date.parse("week 20 of 2026", locale: :"en-GB")
{:ok, ~D[2026-05-11]}

iex> Localize.Date.parse("Q2 2026", locale: :en)
{:ok, ~D[2026-04-01]}
```

A lunisolar date parses as it is written, in the calendar the `:calendar` option names: its related Gregorian year (`r`), its cyclic year name (`U`, read as the year of that name nearest the reference date), a leap month in the locale's pattern ("Mo2bis", "闰二月", "2bis") and `zh`'s day numerals ("初一", "廿一"). Where a locale writes the year both as the calendar's own and as the related Gregorian year, the reading nearer the reference date is taken, in an interval as in a single date: CLDR keys the calendar's interval formats by `y`, and the formatter writes them with the year the standard format writes, so "11/8/2023 – 11/18/2023" is two days of the Chinese year that began in 2023. A string that is also an ISO 8601 date is the calendar's own date where one of its formats reads it, as CLDR's root short date `r-MM-dd` does, and an ISO 8601 date otherwise (see [Calendars](#calendars)). In a calendar that writes its years as years of an era, as the Japanese calendars do, a year written without its era is a year of the reference date's era, as ICU reads one.

In a calendar of cyclic years, the Chinese and Dangi calendars, `y` is the year's place in the sixty-year cycle, the number `U` names, as TR35 has it: 43 for the year that began in 2026, as ICU writes it, with `u` for the year's number, 4663. The calendar answers the place, its `cyclic_year/3`. The place recurs every sixty years, so it is read as the year of that place nearest the reference date, as a cyclic name is. A lunisolar calendar that displays its years as years of an era keeps the year of the era for `y`.

A date-time is read with the date-time patterns of the calendar it is read in, in the order the locale writes the two halves: `vi` puts the time first, as in "10:05 1/4/23".

Times follow the locale's hour cycle, so a 12-hour locale accepts a day period and a 24-hour locale does not need one:

```elixir
iex> Localize.Time.parse("2:30 PM", locale: :en)
{:ok, ~T[14:30:00]}

iex> Localize.Time.parse("14:30", locale: :de)
{:ok, ~T[14:30:00]}
```

An hour is read only where its field has it. Beside a day period it is an hour of the 12-hour clock, so "13:30 PM" and "13:30 AM" are no times, where "13:30" is one, and no hour is carried into the next day, as ICU carries one when it is lenient (see [ICU divergences](icu_divergences.md#time-parsing)).

A day period is read by the locale's own names, before any pattern with a zone could take it for one, and a flexible day period is the period of that name the hour falls in, where a locale gives two periods one name:

```elixir
iex> Localize.Time.parse("11:59 PTG", locale: :ms)
{:ok, ~T[23:59:00]}

iex> Localize.Time.parse("9:05 matin", locale: :fr)
{:ok, ~T[09:05:00]}
```

An ISO 8601 time is read in every locale, whatever the locale's own separator: a time between colons, with its seconds or without them, and after ISO 8601's time designator `T` a time without its minutes or without its separators. Without the `T`, digits alone are not ISO 8601's: an hour by itself is the locale's to read, and "1430" is no time, since it is as much a year.

```elixir
iex> Localize.Time.parse("14:30", locale: :fi)
{:ok, ~T[14:30:00]}

iex> Localize.Time.parse("T1430", locale: :fi)
{:ok, ~T[14:30:00]}

iex> Localize.Time.parse("T14", locale: :fi, as: :map)
{:ok, %{hour: 14}}
```

### Partial input

Input that omits the year is completed from a reference date, today by default, with `:reference_date` setting a different one. The reference date is taken in the calendar the input is read in, so a Hebrew date without a year is in the current Hebrew year, and a two-digit year is read in the century around the reference year in every calendar:

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
{:error, %Localize.DateParseError{input: "March 2026", locale: :en, calendar: Calendar.ISO}}

iex> Localize.Date.parse("March 2026", locale: :en, as: :map)
{:ok, %{calendar: Calendar.ISO, month: 3, year: 2026}}
```

`as: :map` is the option to reach for when a form field genuinely means "March 2026" and completing it to a day would be a lie. It works the same way on `Localize.Time.parse/2`, `Localize.DateTime.parse/2` and `Localize.Interval.parse/2`.

### Text written with a known format

Without a format, a date is read in whichever of the locale's formats reads it first, the standard formats before the skeletons. A skeleton whose fields stand in another order than the standard formats' therefore reads as another date: Maltese writes its short date day first and `:yMd` month first. `:format` names the format the text was written with, as `Localize.Date.to_string/2` takes it — a standard format, a skeleton, a semantic skeleton or a pattern — and the text is read with that format and no other:

```elixir
iex> Localize.Date.to_string(~D[2024-04-03], locale: :mt, format: :yMd)
{:ok, "4/3/2024"}

iex> Localize.Date.parse("4/3/2024", locale: :mt)
{:ok, ~D[2024-03-04]}

iex> Localize.Date.parse("4/3/2024", locale: :mt, format: :yMd)
{:ok, ~D[2024-04-03]}

iex> Localize.Date.parse("4/3/2024", locale: :en, format: "d/M/y")
{:ok, ~D[2024-03-04]}
```

`Localize.Time.parse/2` takes `:format` the same way, and reads a `:long` or a `:full` time with its zone or, as it is written for a time that has none, without it. `Localize.DateTime.parse/2` reads each half with its part of `:format`: a standard format is the date's and the time's alike, a skeleton or a semantic skeleton is split into its date fields and its time fields, and a pattern is split at the text between its date fields and its time fields, where the input is split too. `:date_format` and `:time_format` name a half's format on its own. `Localize.Interval.parse/2` reads each end with `:format`:

```elixir
iex> Localize.Time.parse("14h30", locale: :en, format: "HH'h'mm")
{:ok, ~T[14:30:00]}

iex> Localize.DateTime.parse("4/3/2024 10:30", locale: :mt, format: :yMdHm)
{:ok, ~N[2024-04-03 10:30:00]}

iex> Localize.DateTime.parse("3/4/2024 22:05", locale: :en, format: "d/M/y HH:mm")
{:ok, ~N[2024-04-03 22:05:00]}

iex> Localize.DateTime.parse("20240403T220509", locale: :en, format: "yyyyMMdd'T'HHmmss")
{:ok, ~N[2024-04-03 22:05:09]}

iex> Localize.Interval.parse("4/3/2024 – 10/3/2024", locale: :en, format: "d/M/y")
{:ok, Date.range(~D[2024-03-04], ~D[2024-03-10])}
```

### Intervals

`Localize.Interval.parse/2` takes either one string or a `{from, to}` pair for a two-input form that already has the endpoints apart. One string is read with the locale's interval formats, and otherwise cut where the locale's fallback pattern or a separator people write, a dash or "to", has a date on each side:

```elixir
iex> Localize.Interval.parse("May 5 – May 10, 2026", locale: :en)
{:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}

iex> Localize.Interval.parse("5.–10. Mai 2026", locale: :de)
{:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}

iex> Localize.Interval.parse("October 5, 2026 to October 10, 2026", locale: :en)
{:ok, Date.range(~D[2026-10-05], ~D[2026-10-10])}

iex> Localize.Interval.parse({"2026-05-05", "2026-05-10"})
{:ok, Date.range(~D[2026-05-05], ~D[2026-05-10])}
```

Fields missing from one endpoint are inherited from the other, following the CLDR interval convention, so `"5.–10. Mai 2026"` gives both endpoints a month and a year. Two dates written without a year are of the reference date's year, as a date alone is, and the spaces about an interval format's dash may be left out or put in, so "May 5–10, 2026" reads as "May 5 – 10, 2026" does. An end-before-start interval is rejected unless `allow_inverted: true` is passed.

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

A datetime carrying a fixed UTC offset resolves to a `t:DateTime.t/0`. The offset may be written ISO 8601 style or in the locale's GMT format, in that locale's own spelling and in the digits of any numbering system ("غرينتش+٥:٣٠" in `ar-EG`), and both produce the same struct — the wall time you wrote, with the offset attached rather than normalised away:

```elixir
iex> Localize.DateTime.parse("May 16, 2026 2:30 PM GMT+10:30", locale: :en)
{:ok, #DateTime<2026-05-16 14:30:00+10:30>}

iex> Localize.DateTime.parse("2026-05-16T14:30:00+10:30", locale: :en)
{:ok, #DateTime<2026-05-16 14:30:00+10:30>}
```

Shift to UTC yourself with `DateTime.shift_zone/3` when you want it; the parser does not do it for you, because the original offset cannot be recovered afterwards.

A *named* zone resolves too, in any form the locale writes one, as TR35's time zone parsing reads them: a zone or metazone name, long or short (`"EDT"`, `"Eastern Daylight Time"`, `"heure d’été de l’Est nord-américain"`), a location (`"New York Time"`, `"heure : New York"`), a city or a zone ID (`"Asia/Tokyo"`). Its offset depends on the date, so it needs the time zone database the application configures, such as [tz](https://hex.pm/packages/tz):

```elixir
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
```

```elixir
iex> Localize.DateTime.parse("July 1, 2023 at 10:05:00 AM Eastern Daylight Time", locale: :en)
{:ok, #DateTime<2023-07-01 10:05:00-04:00 EDT America/New_York>}

iex> Localize.DateTime.parse("samedi 1 juillet 2023 à 10:05:00 heure d’été de l’Est nord-américain", locale: :fr)
{:ok, #DateTime<2023-07-01 10:05:00-04:00 EDT America/New_York>}
```

A name of standard or daylight time keeps its own offset, as ICU reads it, so `"July 1, 2023 at 10:05:00 AM EST"` is 10:05 at -05:00 although New York keeps daylight time in July. On a date the zone keeps that time the name is the zone's own time, by the offsets CLDR names standard and daylight for the zone's metazone where it gives them: Punta Arenas keeps -03:00 all year, which CLDR names Chile's summer time, so "Chile Summer Time (Punta Arenas)" is that zone's time in every month. `Localize.DateTime.Timezone.parse_zone/2` reads a zone on its own. Without a time zone database a named zone is dropped and the parse still succeeds, returning a `t:NaiveDateTime.t/0` rather than failing the whole input:

```elixir
iex> Localize.DateTime.parse("May 16, 2026 2:30 PM Asia/Tokyo", locale: :en)
{:ok, ~N[2026-05-16 14:30:00]}
```

### Calendars

The `:calendar` option is a calendar module: `Calendar.ISO`, the default, or a calendar implementing the Calendrical behaviour, such as `Calendrical.Hebrew` from [calendrical](https://hex.pm/packages/calendrical). The input is read with the locale's patterns for that calendar, and the date is built and returned in the module you name. A CLDR calendar name such as `:hebrew` is not a calendar, and neither is a module that is not installed:

```elixir
Localize.Date.parse("22.03.2026", locale: :de, calendar: Calendar.ISO)
#=> {:ok, ~D[2026-03-22]}

# With calendrical installed
Localize.Date.parse("22.03.2026", locale: :de, calendar: Calendrical.Gregorian)
#=> {:ok, ~D[2026-03-22 Calendrical.Gregorian]}

# A CLDR calendar name is not a calendar
Localize.Date.parse("22.03.2026", locale: :de, calendar: :hebrew)
#=> {:error, %Localize.UnknownCalendarError{calendar: :hebrew}}
```

The calendar is checked before any parsing happens, so the answer does not depend on the shape of the input: ISO 8601 and locale-formatted text both return the same error for the same `:calendar`. A calendar names its own CLDR calendar type and months through the Calendrical behaviour's callbacks, so a custom calendar needs no registration with Localize; a module implementing only the `Calendar` behaviour cannot say how its dates are written, and is refused with `Localize.UnknownCalendarError`, as it is when formatting.

The date comes back in the `:calendar` module. When a consumer needs it in another calendar, such as `Calendar.ISO` for an Ecto `:date` field, convert it with `Date.convert/2`.

ISO 8601 text is a Gregorian date, read in every locale and converted into the calendar asked for. A calendar's own formats come first, though. When the text is a year, a month and a day between hyphens and any of the calendar's formats in the locale reads it, as leniently as it reads any text, it is the calendar's own date, so what the formatter writes reads back as the date it was written from. CLDR's root short date of the Chinese calendar is `r-MM-dd`, which `he` takes. `fa` writes a Persian short date "y/M/d", and a hyphen is read for a slash. `en` has no Hebrew format that reads such text:

```elixir
# With calendrical installed
Localize.Date.parse("2023-11-22", locale: :he, calendar: Calendrical.Chinese)
#=> {:ok, ~D[4660-12-22 Calendrical.Chinese]}

Localize.Date.parse("1402-09-01", locale: :fa, calendar: Calendrical.Persian)
#=> {:ok, ~D[1402-09-01 Calendrical.Persian]}

Localize.Date.parse("2023-11-22", locale: :en, calendar: Calendrical.Hebrew)
#=> {:ok, ~D[5784-03-09 Calendrical.Hebrew]}
```

The first is the twenty-second day of the eleventh month of the Chinese year that began in 2023, its twelfth month after a leap month, the second is the Persian date as it is written, and the third is 22 November 2023 converted. A format reads the text in the order it writes its fields, so `kk-Arab`'s "y-d-M" reads "2023-10-11" as 10 November. A date of that shape with a time after a space is read the same way, an offset after the time with it. Text with ISO 8601's `T` is none of a calendar's formats, so it is ISO 8601's, as are its forms without separators, by the day of the year and by the week, and every ISO 8601 date in `Calendar.ISO`, whose own notation ISO 8601 is. Only a calendar of weeks' own notation is read before it (below).

A calendar of weeks, such as `Calendrical.ISOWeek`, has no month or day of the month of its own, so a written month and day name no single one of its weeks. Its `parsing_calendar/0` callback answers `Calendar.ISO`, so input other than its own notation (below) is read as a Gregorian date and converted into it:

```elixir
# With calendrical installed
Localize.Date.parse("Feb 1, 2024", locale: :en, calendar: Calendrical.ISOWeek)
#=> {:ok, ~D[2024-W05-4 Calendrical.ISOWeek]}
```

The formatter writes a week date in the calendar's own notation, as the calendar writes it with `date_to_string/3`, at every standard format and in every locale, and the parser reads that notation back as itself, through the calendar's `parse_date/1`:

```elixir
# With calendrical installed
Localize.Date.to_string(~D[2026-W25-2 Calendrical.ISOWeek], format: :long, locale: :en)
#=> {:ok, "2026-W25-2"}

Localize.Date.parse("2026-W25-2", locale: :en, calendar: Calendrical.ISOWeek)
#=> {:ok, ~D[2026-W25-2 Calendrical.ISOWeek]}
```

A date and time joins the notation to the locale's time, "2026-W25-2, 10:30:00 AM", and an interval writes both dates around the locale's fallback pattern, "2026-W25-2 – 2026-W27-1". The notation is the calendar's own date before a time however the two are joined, by the locale's separator, a space or ISO 8601's `T`: "2026-W25-2T10:30:00" is day 2 of the calendar's own week 25, which is ISO 8601's only where the calendar's weeks are. A pattern takes the calendar's own answers: its weeks, quarters and days of the week, and its months, the ordinal periods of its pattern of weeks, named by CLDR's generic calendar, "M06"; see the [format pattern reference](#format-pattern-reference).

A date of such a calendar without its day is a week, since the month field of its dates holds a week. It is written as the locale writes a week of the year, CLDR's `yw` format, at every standard format:

```elixir
# With calendrical installed
Localize.Date.to_string(%{year: 2026, month: 25, calendar: Calendrical.ISOWeek}, locale: :en)
#=> {:ok, "week 25 of 2026"}

Localize.Date.to_string(%{year: 2026, month: 25, calendar: Calendrical.ISOWeek}, locale: :de)
#=> {:ok, "Woche 25 des Jahres 2026"}
```

The text names no day, so read `as: :map` it is the year and the week it was written from, the fields the days of that week share, where the struct form gives the week's first day:

```elixir
# With calendrical installed
Localize.Date.parse("week 25 of 2026", locale: :en, calendar: Calendrical.ISOWeek, as: :map)
#=> {:ok, %{calendar: Calendrical.ISOWeek, year: 2026, month: 25}}

Localize.Date.parse("week 25 of 2026", locale: :en, calendar: Calendrical.ISOWeek)
#=> {:ok, ~D[2026-W25-1 Calendrical.ISOWeek]}
```

`Localize.Time.parse/2` takes the option too: a time is read in the time formats of the calendar given, and then in the Gregorian calendar's.

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
| `Y` | Week-based year | 2024 | 24 | 2024 | 2024 | 02024 |
| `w` | Week of year | 27 | 27 | � | � | � |
| `W` | Week of month | 1 | � | � | � | � |
| `Q` | Quarter | 3 | 03 | Q3 | 3rd quarter | 3 |

`Y`, `w` and `W` count weeks. A calendar that numbers its weeks gives its own, whatever the locale: `Y` and `w` are its week-based year and week of the year, its `week_of_year/3`, and `W` its week of the month, its `week_of_month/3`, so a calendar of weeks, or Calendrical's Gregorian calendar, whose week 1 holds 1 January, writes the weeks it defines. `Calendar.ISO`, the default calendar, has no weeks of its own, so its weeks are the locale's, numbered as TR35 numbers them from the locale's week data: a week begins on the locale's first day, and week 1 of a year is the first week holding at least the locale's minimum days of it. So 1 January 2027, a Friday, is in week 1 of 2027 in `en`, whose weeks begin on Sunday and need one day, and in week 53 of 2026 in `de` and `en-GB`, whose weeks are ISO 8601's, Monday and four days. The week data is found as TR35's first day algorithm finds it, from a `-u-fw-` first day, a `-u-rg-` region, the `-u-ca-iso8601` calendar and the locale's region, so `en-u-ca-iso8601` numbers ISO 8601's weeks in English. An ISO 8601 week date such as "2026-W25-2" is ISO 8601's week in every locale.

`W` numbers a month's weeks as a year's are numbered, so a week belongs to the month that holds at least the minimum days of it, which can be the month before or after its date's. A pattern with `W` therefore writes its month, and the year and era that month is in, as the week's month, as `Y` writes the year `w` belongs to: `MMMMW` writes 1 October 2021 as "week 5 of September" in `en-GB` and 30 September 2021 as "week 1 of October" in `en`. The day stays the date's.

`Q` and `q` are the calendar's quarter, its `quarter_of_year/3`: a thirteenth month, as the Coptic and Ethiopic calendars and a Hebrew leap year have, is in the fourth quarter, and a calendar of weeks' quarters are thirteen of its weeks, so a quarter needs the year as well as the month. The numeric day of the week, `e` and `c`, counts from the locale's first day, as TR35 defines it. ICU numbers every calendar's weeks by the locale's week data and keeps a week in its date's month; see [ICU divergences](icu_divergences.md#date-and-time-patterns).

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

An offset with seconds, as zones kept before standard time, is written whole by the fields TR35 gives an optional seconds field: the localized GMT format (`O`, `OOOO`, `ZZZZ`) and the longer ISO 8601 fields (`Z` to `ZZZ`, `ZZZZZ`, `XXXX`, `XXXXX`, `xxxx`, `xxxxx`). Los Angeles in 1850 is "GMT-7:52:58", "GMT-07:52:58", "-075258" and "-07:52:58". The shorter `X` and `x` fields have hours and minutes alone, so they write "-0752" and "-07:52", and text written with them reads back up to 59 seconds out.

A zone's name in the non-location formats, generic (`v`, `vvvv`) and specific (`z`, `zzzz`), is the zone's own name where the locale has one, and else its metazone's, qualified with the zone's country or city unless the zone is the metazone's preferred zone for the locale's country, so that it reads back as that zone. In `en`, New York is "Eastern Time" and "Eastern Standard Time", Berlin "Central European Time (Germany)" and "Central European Summer Time (Germany)", and Phoenix "Mountain Time (Phoenix)" and "Mountain Standard Time (Phoenix)". A zone the locale has no name for is written in the localized GMT format, the short one for `z` and the long one for `zzzz`.

A zone keeps a metazone from 1970 on. CLDR tells zones apart back to 1970, and a zone's first metazone period that it gives no beginning begins at 00:00 on 1 January 1970 in UTC, as ICU begins it. Before that a zone is written by its own names, its offset and its location: New York in 1965 is "GMT-5" and "GMT-05:00" at `z` and `zzzz`, and "New York Time" at `v` and `vvvv`. A metazone's name is still read with an earlier date, and means what it means later: "10:00 EST" in July 1965 is 10:00 at -05:00.

The location format (`VVVV`) names the zone's country where the zone is the only one in its country or CLDR's primary zone for it, and the zone's city otherwise: "Italy Time" and "China Time", "Buenos Aires Time". The country is written by its short name where the locale has one ("UK Time"), and by its code where the locale has no name for it, as TR35 composes it: Havana's zone is "CU" in `su` and "ora de CU" in `oc`. A code is read back as a country only in a locale that writes that country so, and a time a day period can follow keeps that reading: in `nnh`, where Saint Pierre and Miquelon's zone is "PM", "10:05 PM" is 22:05.

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
| `:format` | atom or string | `:medium` | A standard format (`:short`, `:medium`, `:long`, `:full`), a skeleton such as `:yMMMEd`, or a pattern. |
| `:date_format` | atom or string | `:format` | The date half of a datetime interval, or a date interval's format. |
| `:time_format` | atom or string | `:format` | The time half of a datetime interval, or a time interval's format. |
| `:fields` | atom | `:date` | Fields a date interval shows with a standard format: `:date`, `:month`, `:month_and_day`, or `:year_and_month`. |
| `:style` | atom | `:default` | Wrapper joining a datetime interval's date and time: `:default`, the standard one TR35 says an interval takes, or `:at`. |

### `Localize.DateTime.Relative.to_string/2`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:locale` | atom, string, or `LanguageTag` | `Localize.get_locale()` | Locale for patterns, pluralization, and the number's digits and grouping. |
| `:format` | atom | `:standard` | Width: `:standard`, `:short`, or `:narrow`. |
| `:unit` | atom | (the largest whole unit) | Explicit unit: `:second`, `:minute`, `:hour`, `:day`, `:week`, `:month`, `:quarter`, `:year`, or a weekday from `:mon` to `:sun`. |
| `:numeric` | atom | `:auto` | `:auto` uses named forms such as "yesterday" for offsets of -2 to 2; `:always` is always numeric. |
| `:relative_to` | `Date`, `Time`, `NaiveDateTime`, or `DateTime` | `DateTime.utc_now()` | Baseline, converted into the value's calendar. |
