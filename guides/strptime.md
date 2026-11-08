# strptime

`Localize.Date.strptime/3`, `Localize.Time.strptime/3` and `Localize.DateTime.strptime/3` read text written with a `Calendar.strftime/3` format, the `%Y-%m-%d` family of directives that C's `strftime(3)` and `strptime(3)`, Python, Ruby and Elixir share. Each translates the format into the CLDR pattern Localize's parsers read with, through `Localize.DateTime.Strptime.pattern/2`, and reads the text with `parse/2` in the locale given. Nothing is read here that `parse/2` could not read with a pattern; what the functions add is the format you already have, and the round trip with `Calendar.strftime/3`.

This guide lists the directives, then says where the reading matches what `strptime(3)` and `Calendar.strftime/3` lead you to expect, and where it does not. Every result shown was produced by the code.

## Quick start

```elixir
iex> Localize.DateTime.strptime("2026-03-04T07:05:09", "%Y-%m-%dT%H:%M:%S", locale: :en)
{:ok, ~N[2026-03-04 07:05:09]}

iex> Localize.Date.strptime("4 mars 2026", "%e %B %Y", locale: :fr)
{:ok, ~D[2026-03-04]}

iex> Localize.Time.strptime("7:05 PM", "%I:%M %p", locale: :en)
{:ok, ~T[19:05:00]}

iex> Localize.DateTime.strptime("2026-03-04 07:05 +0530", "%Y-%m-%d %H:%M %z", locale: :en)
{:ok, DateTime.new!(~D[2026-03-04], ~T[07:05:00], "+05:30", Localize.TimeZoneDatabase)}
```

The round trip with `Calendar.strftime/3`, whose month, weekday and day-period names `Localize.Calendar.strftime_options!/1` supplies for a locale:

```elixir
iex> strftime_options = Localize.Calendar.strftime_options!(locale: :de)
iex> written = Calendar.strftime(~N[2026-03-04 19:05:09], "%A, %d. %B %Y, %H:%M", strftime_options)
"Mittwoch, 04. März 2026, 19:05"
iex> Localize.DateTime.strptime(written, "%A, %d. %B %Y, %H:%M", locale: :de)
{:ok, ~N[2026-03-04 19:05:00]}
```

The translation alone, for a pattern to use with `parse/2` or `to_string/2`:

```elixir
iex> Localize.DateTime.Strptime.pattern("%d %B %Y at %I:%M %p")
{:ok, "dd MMMM y 'at' hh:mm a"}
```

## Directives

Every directive `Calendar.strftime/3` writes is read, and so are the C directives that read the same text. Padding and width modifiers (`%-d`, `%_m`, `%05Y`) are accepted and ignored, since every field is read at any width.

| Directive | Reads | Pattern | Notes |
|---|---|---|---|
| `%a`, `%A` | A weekday name in the locale | `EEE`, `EEEE` | Either width reads with either directive. |
| `%b`, `%h`, `%B` | A month name in the locale | `MMM`, `MMMM` | Either width reads with either directive. |
| `%c`, `%x`, `%X` | The preferred date and time, date, or time | the `:preferred_*` option | Defaults as `Calendar.strftime/3` has them. |
| `%d`, `%e` | The day of the month | `dd`, `d` | Padded or not. |
| `%f` | A fraction of a second | `SSSSSS` | Any number of digits, kept as precision. |
| `%H`, `%k` | The hour, 0 to 23 | `HH`, `H` | |
| `%I`, `%l` | The hour, 1 to 12, with `%p` | `hh`, `h` | |
| `%j` | The day of the year | `DDD` | |
| `%m` | The month | `MM` | |
| `%M` | The minute | `mm` | |
| `%p`, `%P` | The day period, AM or PM, in the locale | `a` | Either case, and forms such as "p.m.". |
| `%q` | The quarter, 1 to 4 | `Q` | |
| `%S` | The second | `ss` | |
| `%y` | A two-digit year | `yy` | See below. |
| `%Y` | The year, with a sign | `y` | Up to four digits. |
| `%z` | A UTC offset | `xx` | "+0530" and "+05:30" both read. |
| `%Z` | A time zone name | `zzzz` | Needs a time zone database; see below. |
| `%D`, `%F`, `%T`, `%R` | `%m/%d/%y`, `%Y-%m-%d`, `%H:%M:%S`, `%H:%M` | as composed | |
| `%n`, `%t` | Whitespace | a space | |
| `%%` | A percent sign | `%` | |

Any other letter in the format is literal text, quoted in the pattern, so `"%Y-%m-%dT%H:%M"` becomes `y-MM-dd'T'HH:mm`.

## Where the reading is what you expect

* **Unpadded fields and runs of whitespace.** `"2026-3-4   7:05"` reads with `"%Y-%m-%d %H:%M"`, as `strptime(3)` reads it: a numeric directive takes one or two digits, and a space in the format matches any whitespace in the text.

* **Names in either width, in any case.** `%b` reads "March" and `%B` reads "Mar", as `strptime(3)` does; `%p` reads "PM", "pm" and "p.m.".

* **Offsets in either form.** `%z` reads "+0530" and "+05:30", as glibc's `strptime(3)` does, and resolves to a `t:DateTime.t/0` in that fixed offset.

* **`%c`, `%x` and `%X`** stand for the `:preferred_datetime`, `:preferred_date` and `:preferred_time` options, with the same defaults as `Calendar.strftime/3`, `"%Y-%m-%d %H:%M:%S"`, `"%Y-%m-%d"` and `"%H:%M:%S"`, and the same rule that a preferred format may not itself contain them.

* **The round trip with `Calendar.strftime/3`.** Every directive it writes is read, so text it writes with the names `Localize.Calendar.strftime_options!/1` supplies for a locale reads back with the same format in that locale. The suite checks this for English, German, French, Spanish and Japanese.

* **Padding and width modifiers** are accepted and ignored, as `strptime(3)` largely ignores them on input.

* **Partial text** reads with `as: :map`, as `parse/2` reads it, which is the role `strptime(3)`'s partly filled `tm` plays: `Localize.Date.strptime("2026-03", "%Y-%m", locale: :en, as: :map)` is `{:ok, %{calendar: Calendar.ISO, year: 2026, month: 3}}`.

* **Errors are returned, never raised.** An unreadable directive is `{:error, %Localize.DateTimeFormatError{reason: :unsupported_directive}}` naming the directive in `:detail`, before any text is read; text the format does not match is the error `parse/2` returns. `Calendar.strftime/3` raises `ArgumentError` for a directive it does not know.

## Where it is not

* **The whole string must match.** `strptime(3)` stops at the end of the format and hands back the rest of the text; here text after the format is an error. `"2026-03-04 07:05 and more"` does not read with `"%Y-%m-%d %H:%M"`.

* **A two-digit year falls in a window, not at POSIX's pivot.** `%y` resolves into the eighty years before and twenty years after the reference date, today or `:reference_date`, as `parse/2` resolves a two-digit year. POSIX pivots at 69: 69 to 99 are 1969 to 1999 and 00 to 68 are 2000 to 2068. With a reference date in 2026 the two agree from 46 to 99 and differ below: "50" is 1950 here and 2050 for POSIX.

* **The locale is the `:locale` option**, not the process's `LC_TIME`. The names of the C locale are the `:en` locale's; `"4 mars 2026"` reads with `locale: :fr`.

* **`%Z` needs a time zone database.** A zone name, "PST", "Pacific Standard Time" or "Europe/Paris", resolves to a `t:DateTime.t/0` in that zone through the database configured for `Calendar`, with `tz` or `tzdata`, as `parse/2` resolves it. Without one the zone is dropped and the result is a `t:NaiveDateTime.t/0`. `%z` needs no database.

* **`%p` must agree with `%H`.** `strptime(3)` ignores `%p` when `%H` gives the hour; here a day period that contradicts the 24-hour clock is an error: `"19:05 PM"` reads with `"%H:%M %p"` and `"07:05 PM"` does not. Use `%I` with `%p`.

* **A weekday is checked against the date.** glibc ignores `%a` and `%A` on input; here `"Wed 2026-03-05"` does not read with `"%a %Y-%m-%d"`, because 5 March 2026 is a Thursday.

* **A year has at most four digits.** `%Y` reads a sign, so `"-0001-01-01"` is `~D[-0001-01-01]`, but a fifth digit does not read.

* **Each function reads the fields its shape has.** `Localize.DateTime.strptime/3` wants a date and a time in the format, `Localize.Date.strptime/3` a date, `Localize.Time.strptime/3` a time, as the three `parse/2` functions do. A date-only format given to `Localize.DateTime.strptime/3` is a `t:Localize.DateTimeFormatError.t/0`, and a time in a format given to `Localize.Date.strptime/3` is a `t:Localize.DateTimeInvalidInputError.t/0` naming the fields the shape lacks.

* **Directives Localize does not read** are an error naming the directive: `%s`, seconds since the epoch, which no pattern field carries; `%u` and `%w`, the weekday as a number, since CLDR numbers weekdays by the locale's first day of the week where C counts from Monday or Sunday; `%U`, `%W`, `%V`, `%G` and `%g`, the week of the year and the week-based year, for the same reason; `%C`, the century; and the `%E` and `%O` modifiers of POSIX locales.

## Options

* `:preferred_datetime`, `:preferred_date` and `:preferred_time` are the strftime formats `%c`, `%x` and `%X` stand for.

* Every option of `parse/2` but `:format`: `:locale`, `:calendar`, `:reference_date` and `:as`; `Localize.Time.strptime/3` takes no `:reference_date`.

## Errors

* `{:error, %Localize.DateTimeFormatError{reason: :unsupported_directive, detail: directive}}` for a directive Localize does not read, or `%c`, `%x` or `%X` inside a preferred format, with the whole format in `:format`.

* `{:error, %Localize.InvalidValueError{}}` for a format that is not a string, options that are not a keyword list, or a preferred format that is not a string.

* The error `parse/2` returns where the text does not match the format: a `t:Localize.DateParseError.t/0`, `t:Localize.TimeParseError.t/0` or `t:Localize.DateTimeParseError.t/0`.
