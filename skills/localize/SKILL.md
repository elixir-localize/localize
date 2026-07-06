---
name: localize
description: Write localized Elixir applications with the Localize library (hex package "localize") — formatting numbers, currencies, dates, times, durations, units of measure, lists, collation/sorting, and MessageFormat 2 messages. Use this skill whenever an Elixir app renders numbers, money, dates, times, quantities, or sorted text for people to read — even if the app targets a single locale — and for any task mentioning localize, ex_cldr migration, CLDR, locale validation, language tags, plural rules, or translatable message strings. Also use it when reviewing Elixir code that formats values by hand (interpolation, Calendar.strftime, :io_lib.format, Enum.sort on user-visible strings) since Localize is usually the better replacement.
license: Apache-2.0
---

# Writing localized Elixir applications with Localize

Localize (hex: `localize`) formats numbers, currencies, dates/times, units, lists and messages using Unicode CLDR data, and sorts text with the Unicode Collation Algorithm. It is the successor to the `ex_cldr` family: one package, no compile-time backend modules, data loaded at runtime.

## Why use it even for a single-locale app

Hand-formatting is where localization bugs are born, and most of them bite in English too:

* `"#{count} files"` is wrong for `count == 1`. `Localize.Message.format/3` or a cardinal plural rule gets "1 file / 2 files" right for free.
* `"$#{amount}"` breaks on 1000000 (no grouping), negative amounts, and non-USD currencies. `Localize.Number.to_string(amount, format: :currency)` renders "$1,234.56" correctly today and "1.234,56 €" the day the app grows a second locale.
* `Calendar.strftime/3` hardcodes one ordering and one language of month names. `Localize.Date.to_string/2` gives the locale's convention.
* `Enum.sort/1` on user-visible strings puts "Zebra" before "apple" and mishandles accents. `Localize.Collation.sort/2` sorts the way people expect.

So when writing or reviewing Elixir that renders values for humans, reach for the Localize call rather than string interpolation, `strftime`, or raw `Enum.sort` — the single-locale output is equally correct and the app is localization-ready without a rewrite.

## Core conventions (apply everywhere)

* **Results are tagged tuples**: `{:ok, formatted}` or `{:error, %SomeError{}}` where the error is an exception struct with a readable `Exception.message/1`. Every formatter has a `!` variant that returns the bare value or raises.
* **Every formatting function takes a `:locale` option** defaulting to the process locale `Localize.get_locale()` (itself defaulting to the app config, then `:en`). Set it per-process with `Localize.put_locale/1`, per-call with `locale: "fr"`, or per-block with `Localize.with_locale/2`.
* **Validate untrusted locale input** with `Localize.validate_locale/1` — it parses, canonicalizes (aliases like `iw` → `he`), resolves likely subtags, applies `-u-` extensions, and caches. Pass the resulting `LanguageTag` around rather than re-validating strings.
* **Zero config is valid config.** With no configuration, `:en` works out of the box; other locales download on first use (integrity-verified). Configure `supported_locales` and `default_locale` when the app knows its audience.

```elixir
# config/config.exs — typical production setup
config :localize,
  default_locale: :en,
  supported_locales: [:en, :de, :fr, :ja],
  otp_app: :my_app
```

## Quick reference by subsystem

Each row shows the everyday call; the reference file has the full option set, more examples, and the edge cases. Read the reference file when the task goes beyond the row.

### Numbers, currencies, plurals — [references/numbers.md](references/numbers.md)

```elixir
Localize.Number.to_string(1234.5)                              # {:ok, "1,234.5"}
Localize.Number.to_string(1234.5, format: :currency)           # {:ok, "$1,234.50"} (currency from locale)
Localize.Number.to_string(1234.5, format: :currency, currency: :EUR, locale: :de)
                                                               # {:ok, "1.234,50 €"} (no-break space before €)
Localize.Number.to_string(0.456, format: :percent)             # {:ok, "46%"}
Localize.Number.to_string(1_234_000, format: :decimal_short)   # {:ok, "1.2M"}
Localize.Number.to_string(42, format: :ordinal)                # {:ok, "42nd"}
Localize.Number.PluralRule.plural_type(1, locale: :en)         # :one  (drive "file" vs "files")
Localize.Number.parse("1,234.56")                              # parse localized input back
```

Read the reference for: rounding and digit options, significant digits via patterns, spellout/RBNF, ranges ("3–5"), scanning numbers out of text, `Decimal` inputs, custom format patterns.

### Dates, times, intervals, durations — [references/dates-times.md](references/dates-times.md)

```elixir
Localize.Date.to_string(~D[2026-07-06])                        # {:ok, "Jul 6, 2026"}
Localize.Date.to_string(~D[2026-07-06], format: :full)         # {:ok, "Monday, July 6, 2026"}
Localize.DateTime.to_string(dt, format: :yMMMdHm)              # skeleton — locale picks the layout
Localize.Interval.to_string(~D[2026-07-06], ~D[2026-07-09])    # {:ok, "Jul 6 – 9, 2026"} (thin spaces around the dash)
Localize.DateTime.Relative.to_string(-3600)                    # {:ok, "1 hour ago"}
Localize.Duration.to_string(duration)                          # {:ok, "11 months and 30 days"}
```

Prefer style atoms (`:short`/`:medium`/`:long`/`:full`) or skeletons (`:yMd`, `:yMMMEd`, `:Hm`) over literal pattern strings — skeletons let each locale arrange fields its own way. Read the reference for: pattern symbols, time zones, week/quarter fields, non-Gregorian calendars, `to_time_string` clock-style durations.

### Units of measure — [references/units.md](references/units.md)

```elixir
unit = Localize.Unit.new!(3.5, "kilometer")
Localize.Unit.to_string(unit)                                  # {:ok, "3.5 kilometers"}
Localize.Unit.to_string(unit, format: :short)                  # {:ok, "3.5 km"}
Localize.Unit.convert(unit, "mile")                            # {:ok, mile-unit}
Localize.Unit.to_string(Localize.Unit.new!(5, "curr-usd-per-100-kilometer"))
                                                               # {:ok, "$5.00 per 100 kilometers"}
```

Compound identifiers compose (`kilowatt-hour`, `meter-per-second`, `foot-and-inch`); usage-based preferences (`usage: "person-height"`) pick regional units automatically. Read the reference for: conversion, mixed units, arithmetic, custom units, grammatical case/gender in inflected languages.

### Lists — inline, no reference needed

```elixir
Localize.List.to_string(["a", "b", "c"])                       # {:ok, "a, b, and c"}
Localize.List.to_string(["a", "b"], list_style: :or)           # {:ok, "a or b"}
```

Never `Enum.join(items, ", ")` user-facing lists — conjunction rules differ by locale and by list length.

### Collation (sorting and comparing text) — [references/collation.md](references/collation.md)

```elixir
Localize.Collation.sort(["banana", "Apple", "cherry"])          # ["Apple", "banana", "cherry"]
Localize.Collation.compare("résumé", "resume", strength: :primary)  # :eq — accent-insensitive
Localize.Collation.sort(["file10", "file2"], numeric: true)     # ["file2", "file10"]
Localize.Collation.sort_key("text")                             # store for DB-side ordering
```

Read the reference for: strength levels (accent/case-insensitive matching), `ignore_punctuation`, script reordering, locale collation types (`zh-u-co-pinyin`), search-style matching.

### MessageFormat 2 (translatable message strings) — [references/message-format.md](references/message-format.md)

```elixir
Localize.Message.format("{{Hello {$name}!}}", %{"name" => "World"})
# {:ok, "Hello World!"}

Localize.Message.format(
  ".input {$count :number}\n.match $count\n1 {{You have one file}}\n* {{You have {$count} files}}",
  %{"count" => 3}
)
# {:ok, "You have 3 files"}
```

MF2 is the right shape for any user-visible sentence containing a value: the plural/gender/select logic lives in the (translatable) message, not in Elixir `if`s. Read the reference for: built-in functions (`:number`, `:datetime`, `:currency`, `:unit`), markup, custom functions, Gettext integration, and when plain Gettext is the better fit.

### Locale validation, language tags, configuration — [references/locales-and-config.md](references/locales-and-config.md)

```elixir
{:ok, locale} = Localize.validate_locale("pt-br")     # canonical "pt-BR", ready to pass around
Localize.put_locale(locale)                           # set for this process
Localize.Territory.display_name(:NZ, locale: :fr)     # {:ok, "Nouvelle-Zélande"}
Localize.Currency.currency_from_locale(locale)        # territory-appropriate default currency
```

`-u-` extension keys on a locale (e.g. `"en-u-ca-buddhist-nu-thai-hc-h23"`) automatically drive calendar, digits, hour cycle, collation and more through every formatter. Read the reference for: the `LanguageTag` struct, supported/known vocabularies, display names, runtime data download and supervision, per-locale defaults derived from territory data.

## Patterns for application code

**Set the locale once per request, then format without ceremony.** In Phoenix, a plug resolves the user's locale (session, `Accept-Language`, URL) through `validate_locale/1` and calls `Localize.put_locale/1`; every downstream `to_string` call then does the right thing with no `:locale` plumbing.

**Prefer the non-bang variants at boundaries, bang variants internally.** User-supplied locales, currencies, or units can be invalid — handle `{:error, e}` (its `Exception.message/1` is presentable). For app-internal constants (`Localize.Unit.new!(1, "meter")`), the bang variant is cleaner and a raise means a programming error.

**Keep values as values until the last moment.** Store money as `Decimal` + currency code, dates as `Date`/`DateTime`, quantities as `Localize.Unit` — format at the presentation edge. Never parse formatted output back except with `Localize.Number.parse/2`.

**Plural-sensitive text belongs in messages, not conditionals.** Replace `if count == 1, do: "file", else: "files"` with an MF2 message or `PluralRule.pluralize/3` — English has 2 plural categories but Arabic has 6, and the conditional version silently caps the app at English.

## Common mistakes to catch in review

* String interpolation of numbers, money, dates, or lists into user-visible text.
* `Calendar.strftime/3` or `Timex.format` for user-facing dates (fine for logs and machine formats).
* `Enum.sort/1` / `Enum.sort_by(&String.downcase/1)` on human-visible lists.
* Hardcoded `"$"`, `"%"`, thousands separators, or month/day names.
* `String.to_atom(user_locale)` — use `validate_locale/1`, which is safe on untrusted input.
* Concatenating sentence fragments around a value ("You have " <> n <> " new") — word order varies; use MF2.
* Treating `validate_locale` output as a string — it returns a `%Localize.LanguageTag{}`; pass the struct.
