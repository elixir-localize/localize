# The Localize ecosystem

Localize is best understood as **an additional set of structured data types** — a currency amount, a unit of measure, a postal address, a phone number, a locale — together with the operations those types need in order to be useful. What makes them a family is not that they are complicated, but that none of them can be rendered, read back, or sorted without knowing *whose* conventions to apply. A price is `$1,234.56` or `1.234,56 €` depending on the reader; a date is `5/16/2026` or `16.05.2026`; a list is "a, b, and c" or "a, b und c". The value is the same. The presentation is not.

Having established those types, the same treatment extends outward to the types Elixir already has. An integer, a `Date`, a `String` and a `Date.Range` are every bit as locale-dependent as a money amount when they meet a human being, so Localize formats, parses and orders them too. The result is a single vocabulary across both sets: whatever the value, you ask the same four questions of it.

## The four operations

* **Formatting** turns a value into text for a particular locale — the operation that has no locale-independent answer.

* **Parsing** reverses it, reading locale-formatted text back into a value. It is the operation most often missing from localization libraries, and the one that matters as soon as a user types something into a form.

* **Ordering** arranges values. For numbers and dates this is arithmetic and needs no locale; for text it is the Unicode Collation Algorithm with CLDR tailoring, where the locale changes the answer (in Swedish `ä` sorts after `z`; in German it sorts with `a`).

* **Serialization** stores a value in a database and reads it back as the same value, rather than as a string someone has to reassemble.

## Elixir's types

| Type | Formatting | Parsing | Ordering | Serialization |
| --- | --- | --- | --- | --- |
| `Integer` | Localize | Localize | `Enum.sort` | Ecto |
| `Float` | Localize | Localize | `Enum.sort` | Ecto |
| `Decimal` | Localize | Localize | `Enum.sort` | Ecto |
| `String` | — | — | **Localize** | Ecto |
| `Date` | Localize | Calendrical | `Enum.sort` | Ecto |
| `Time` | Localize | Calendrical | `Enum.sort` | Ecto |
| `DateTime` | Localize | Calendrical | `Enum.sort` | Ecto |
| `NaiveDateTime` | Localize | Calendrical | `Enum.sort` | Ecto |
| `Duration` | Localize | — | `Enum.sort` | Localize |
| `Date.Range` | Localize | Calendrical | `Enum.sort` | Localize |
| `Range` | Localize | — | `Enum.sort` | Localize |
| `List` | Localize | — | `Enum.sort` | Ecto |

A `String` is the one row with no formatting or parsing: it is already text, so there is nothing to render it into or read it out of. It is also the only row where ordering is a Localize operation rather than a comparison, which is the point — collation is where a locale changes the sort order of values that are otherwise identical.

`Duration`, `Range` and `Date.Range` say Localize under serialization because PostgreSQL has `interval`, `int8range` and `daterange` but Ecto has no types mapping Elixir's values onto them; `localize_sql` supplies those. Everything else in the table is a type Ecto already stores.

## Localize's types

| Type | Formatting | Parsing | Ordering | Serialization |
| --- | --- | --- | --- | --- |
| `Localize.LanguageTag` | Localize | Localize | `Enum.sort` | Localize |
| `Localize.Currency` | Localize | Localize | `Enum.sort` | Localize |
| `Money` | Localize | Localize | `Enum.sort` | Localize |
| `Localize.Unit` | Localize | Localize | `Enum.sort` | Localize |
| `Localize.Duration` | Localize | — | `Enum.sort` | Localize |
| `Localize.Territory` | Localize | Localize | `Enum.sort` | Localize |
| `Localize.Script` | Localize | Localize | `Enum.sort` | Localize |
| `Localize.Address` | Localize | Localize | **Localize** | Localize |
| `Localize.PhoneNumber` | Localize | Localize | `Enum.sort` | Localize |
| `Localize.PersonName` | Localize | — | **Localize** | Localize |
| MF2 message | Localize | — | — | Gettext |

Addresses and person names order through Localize because sorting them means collating their formatted text, which is the `String` case again. Both are stored as `jsonb`, keeping their parts separate — a stored name renders as "Dr. Herbert Fritz von Müller" or "Müller, Herbert" depending on the locale and format asked for at display time, which storing a formatted string would forfeit.

An MF2 message is the one type that is neither parsed from its output nor stored in a database: a formatted message is prose, and the message itself is authored and distributed as a Gettext translation rather than a column value.

## Reading the columns

**`Enum.sort` is not a shortfall.** Elixir's `Enum.sort/2` accepts a module implementing `compare/2`, and the ecosystem's types implement exactly that — so ordering needs no special API:

```elixir
iex> Enum.sort([Money.new(:USD, 30), Money.new(:USD, 10)], Money)
[Money.new(:USD, "10"), Money.new(:USD, "30")]
```

The same call shape sorts units, converting between compatible units before comparing — three feet is shorter than one metre, so it sorts first despite the larger number:

```elixir
iex> {:ok, feet} = Localize.Unit.new(3, "foot")
iex> {:ok, metre} = Localize.Unit.new(1, "meter")
iex> Enum.sort([metre, feet], Localize.Unit) |> Enum.map(& &1.name)
["foot", "meter"]
```

For text, ordering is the locale's collation:

```elixir
iex> Localize.Collation.sort(["ä", "z", "a"], locale: :sv)
["a", "z", "ä"]

iex> Localize.Collation.sort(["ä", "z", "a"], locale: :de)
["a", "ä", "z"]
```

**Parsing is the round trip.** Where a type says Localize or Calendrical under parsing, formatted output can be read back:

```elixir
iex> Localize.Number.to_string(1234.56, locale: :de)
{:ok, "1.234,56"}

iex> Localize.Number.parse("1.234,56", locale: :de)
{:ok, 1234.56}
```

Dates, times and datetimes are parsed by [Calendrical](https://hexdocs.pm/calendrical), which reads locale-formatted input across CLDR's calendars — including relative and partial forms such as `"Q2 2026"` — and is the one sibling that also parses a range:

```elixir
iex> Calendrical.Date.parse("16.05.2026", locale: :de)
{:ok, ~D[2026-05-16]}
```

**Serialization keeps the type.** A column declared with a Localize Ecto type loads as the value, not as text to re-parse. Most map to ordinary `text` or `jsonb` and need no migration beyond the column; money and units map to a PostgreSQL composite type and gain database-side `sum`, `avg`, `min` and `max` aggregates that refuse to add euros to yen. See [localize_sql](https://hexdocs.pm/localize_sql).

## The libraries

Each library adds types, operations, or both. They share the locale resolution, CLDR data and configuration of Localize itself, so a locale set once applies across all of them.

* [localize](https://hexdocs.pm/localize) — the core: number, date, time, unit, list and interval formatting; number and unit parsing; collation; plural rules; RBNF; display names for territories, languages, scripts and currencies; and MessageFormat 2.

* [calendrical](https://hexdocs.pm/calendrical) — CLDR calendars beyond the ISO one, and locale-aware parsing of dates, times, datetimes and date ranges.

* [ex_money](https://hexdocs.pm/ex_money) and [ex_money_sql](https://hexdocs.pm/ex_money_sql) — the `Money` type, its arithmetic and formatting, and its database storage with tag-guarded aggregates.

* [localize_sql](https://hexdocs.pm/localize_sql) — Ecto types for the whole set, the tagged-decimal aggregate machinery that `ex_money_sql` builds on, and locale-aware `COLLATE` for queries on PostgreSQL and SQLite.

* [localize_address](https://hexdocs.pm/localize_address) — postal addresses: parsing unstructured input, and formatting per each territory's conventions.

* [localize_phone_number](https://hexdocs.pm/localize_phone_number) — phone numbers: parsing, validation and formatting via libphonenumber.

* [localize_person_names](https://hexdocs.pm/localize_person_names) — person names formatted to CLDR's per-locale ordering, and its handling of given, surname and honorific order.
