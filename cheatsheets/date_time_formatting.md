# Date, Time & DateTime Formatting Cheatsheet

## Date formatting

```elixir
Localize.Date.to_string(~D[2025-07-10])
#=> {:ok, "Jul 10, 2025"}
```

### Standard formats

| Format | `:en` | `:de` | `:ja` |
|---|---|---|---|
| `:short` | `"7/10/25"` | `"10.07.25"` | `"2025/07/10"` |
| `:medium` | `"Jul 10, 2025"` | `"10.07.2025"` | `"2025/07/10"` |
| `:long` | `"July 10, 2025"` | `"10. Juli 2025"` | `"2025年7月10日"` |
| `:full` | `"Wednesday, July 10, 2025"` | `"Donnerstag, 10. Juli 2025"` | `"2025年7月10日木曜日"` |

### Skeleton formats

Skeletons specify which fields to include; CLDR resolves the pattern for the locale.

```elixir
Localize.Date.to_string(~D[2025-07-10], format: :yMMMEd, locale: :en)
#=> {:ok, "Thu, Jul 10, 2025"}

Localize.Date.to_string(~D[2025-07-10], format: :yMd, locale: :en)
#=> {:ok, "7/10/2025"}

Localize.Date.to_string(~D[2025-07-10], format: :yMMMd, locale: :en)
#=> {:ok, "Jul 10, 2025"}
```

Common date skeletons: `:yMd`, `:yMMMd`, `:yMMMEd`, `:yMMM`, `:yMMMM`, `:MMMd`, `:MMMEd`, `:Md`, `:MEd`.

### Custom pattern strings

```elixir
Localize.Date.to_string(~D[2025-07-10], format: "dd/MM/yyyy", locale: :en)
#=> {:ok, "10/07/2025"}

Localize.Date.to_string(~D[2025-07-10], format: "EEEE d MMMM y", locale: :en)
#=> {:ok, "Wednesday 10 July 2025"}
```

### Partial dates (maps)

```elixir
Localize.Date.to_string(%{year: 2025, month: 7}, format: :yMMM, locale: :en)
#=> {:ok, "Jul 2025"}
```

## Time formatting

```elixir
Localize.Time.to_string(~T[14:30:45], prefer: :ascii)
#=> {:ok, "2:30:45 PM"}
```

### Standard formats

| Format | `:en` (`:ascii`) | `:de` | `:ja` |
|---|---|---|---|
| `:short` | `"2:30 PM"` | `"14:30"` | `"14:30"` |
| `:medium` | `"2:30:45 PM"` | `"14:30:45"` | `"14:30:45"` |

The `:prefer` option selects Unicode (default) or ASCII AM/PM markers:

```elixir
Localize.Time.to_string(~T[14:30:00], locale: :en, prefer: :ascii)
#=> {:ok, "2:30:00 PM"}

Localize.Time.to_string(~T[14:30:00], locale: :en, prefer: :unicode)
#=> {:ok, "2:30:00\u202FPM"}  # narrow no-break space before PM
```

## DateTime formatting

```elixir
Localize.DateTime.to_string(~N[2025-07-10 14:30:45], prefer: :ascii)
#=> {:ok, "Jul 10, 2025, 2:30:45 PM"}
```

### Standard formats

| Format | `:en` (`:ascii`) | `:de` (`:ascii`) |
|---|---|---|
| `:short` | `"7/10/25, 2:30 PM"` | `"10.07.25, 14:30"` |
| `:medium` | `"Jul 10, 2025, 2:30:45 PM"` | `"10.07.2025, 14:30:45"` |
| `:long` | `"July 10, 2025, 2:30:45 PM"` | `"10. Juli 2025, 14:30:45"` |

### Separate date and time formats

```elixir
Localize.DateTime.to_string(~N[2025-07-10 14:30:45],
  date_format: :full, time_format: :short, locale: :en, prefer: :ascii)
#=> {:ok, "Wednesday, July 10, 2025, 2:30 PM"}
```

## Relative time formatting

```elixir
Localize.DateTime.Relative.to_string(-60, locale: :en)
#=> {:ok, "1 minute ago"}

Localize.DateTime.Relative.to_string(3600, locale: :en)
#=> {:ok, "in 1 hour"}

Localize.DateTime.Relative.to_string(-86400, locale: :en)
#=> {:ok, "yesterday"}

Localize.DateTime.Relative.to_string(604800, locale: :en)
#=> {:ok, "next week"}
```

## Interval formatting

```elixir
Localize.Interval.to_string(~D[2025-04-22], ~D[2025-04-25], locale: :en)
#=> {:ok, "Apr 22 – 25, 2025"}

Localize.Interval.to_string(~D[2025-01-15], ~D[2025-03-20], locale: :en)
#=> {:ok, "Jan 15 – Mar 20, 2025"}
```

## Date field symbols quick reference

| Symbol | Meaning | 1 char | 2 chars | 3 chars | 4 chars |
|---|---|---|---|---|---|
| `y` | Year | `2025` | `25` | — | — |
| `M` | Month | `7` | `07` | `Jul` | `July` |
| `d` | Day of month | `1` | `01` | — | — |
| `E` | Day name | `Thu` | `Thu` | `Thu` | `Thursday` |
| `G` | Era | `AD` | `AD` | `AD` | `Anno Domini` |
| `Q` | Quarter | `3` | `03` | `Q3` | `3rd quarter` |

## Time field symbols quick reference

| Symbol | Meaning | Example |
|---|---|---|
| `h` | Hour 1–12 | `2` / `02` |
| `H` | Hour 0–23 | `14` |
| `m` | Minute | `5` / `05` |
| `s` | Second | `9` / `09` |
| `a` | AM/PM | `PM` |

## Common options

| Option | Values | Default |
|---|---|---|
| `:locale` | atom, string, `LanguageTag` | `Localize.get_locale()` |
| `:format` | `:short`, `:medium`, `:long`, `:full`, skeleton atom, or pattern string | `:medium` |
| `:prefer` | `:unicode`, `:ascii` | `:unicode` |
