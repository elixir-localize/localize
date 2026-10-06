# TR35 audit of what follows ICU

**Status:** in progress, 2026-10-06

Localize follows TR35, and follows ICU only where ICU clearly follows TR35 (user, 2026-10-06: "You must follow TR35 and use ICU ONlY when it's clear it follows TR35"). This document is the check of the code against that rule: every comment and doc in `lib` that names ICU, read against TR35's text at CLDR `6198cae999` (`docs/ldml/tr35-dates.md` in the CLDR repository), and given one of four standings.

* **Contradicted TR35** — fixed, with the commit.

* **TR35 is the rule** — its clause is what the code implements. Where the comment gave only ICU as the reason, it now gives the clause.

* **TR35 is silent, decided** — by the user, with the date, or by me and told to the user at the time.

* **TR35 is silent, undecided** — the choice followed ICU, or was mine, and was never put to the user. These are `Open`, and are the user's to decide.

* **Departs from TR35 by the user's decision** — two behaviours the user decided with TR35's text in the question. They are listed so that every place Localize does not do as TR35 says is in one document.

The date, time, time zone, interval and calendar modules are checked in full: the 64 mentions of ICU their 11 files held before the audit, each behaviour in a table below. The number, unit, RBNF, plural-rule, locale-matching and message modules name ICU in 44 more places in 15 files that justify a behaviour, and **none of those has been read against TR35 yet**; they are the last table.

## Contradicted TR35, fixed

| Behaviour | TR35 | Status |
|---|---|---|
| A field the skeleton lacks was added to an interval | Interval algorithm, steps 4 and 8 | Done |
| Two times of a day with no interval format wrote the date once | Interval algorithm, step 8 | Done |
| `h` read an hour of 0 and `K` an hour of 12 | Date Field Symbol Table | Done |

**A field the skeleton lacks** (`d17b4a6e`). `MMMd` from 28 December to 3 January was "Dec 28, 2026 – Jan 3, 2027", the year added as ICU adds it. TR35: "If there is no difference among any of the fields in the pattern, format as a single date", and where the item has no pattern for the greatest difference, "format the start and end datetime using the fallback pattern". It is "Dec 28 – Jan 3". This reverses the user's decision of 2026-09-14 ([plans/cldr-49.md](cldr-49.md) item 36, "Widen, as ICU does").

**Two times of a day with no interval format** (`70ce58f1`). The default format, whose time has seconds, wrote "Apr 8, 2026, 12:00:00 PM – 2:00:00 PM", the date once, as ICU's `fallbackFormat` writes two values of one day. TR35's step 3.2 writes the date once only where "the time fields part" finds an `intervalFormatItem`, and no item of CLDR's has seconds; then step 8 applies, and of the fallback pattern TR35 says "{0} is replaced by the start datetime, and {1} is replaced by the end datetime". It is "Apr 8, 2026, 12:00:00 PM – Apr 8, 2026, 2:00:00 PM". `time_format: :short`, or a skeleton without seconds, still writes the date once beside CLDR's `hm` or `Hm` item. This reverses the user's decision of 2026-09-14 ("keep showing the date once where it does not"), and is one commit to revert.

**An hour outside its field** (`d097a8c1`). TR35 gives `h` "Hour [1-12]" and `K` "Hour [0-11]", and its parsing notes have "a number larger than the largest month cannot be a month". "0:30 AM" at `h:mm a` and "12:30 AM" at `K:mm a` were read, as ICU's lenient parser reads them, and are errors.

## TR35 is the rule

| Behaviour | Where | TR35 | Status |
|---|---|---|---|
| `y` is the year's place in the sixty-year cycle | `Localize.DateTime.Formatter`, `Localize.Calendar.cycle_place/2`, `Localize.Date.Parser` | `U` and `y` in the symbol table | Done |
| A numeric year is nearer `y` than a cyclic name | `Localize.DateTime.Format.Match` | Matching Skeletons, 2.3 | Done |
| A 24-hour skeleton drops a day period | `Localize.DateTime.Format.Match` | availableFormats: "should be ignored if they appear in skeletons" | Done |
| A name is measured from the abbreviated width against a number | `Localize.DateTime.Format.Match` | Matching Skeletons, 2.3, with CLDR's conformance data | Done |
| `-u-hc-` gives the matched pattern its hour symbol | `Localize.Time.apply_hour_cycle/3` | Hour cycle identifier | Done |
| `C` takes the first allowed hour format, whatever `-u-hc-` | `Localize.Time` | Time Data: "traversed from first to last" | Done |
| An hour is read in one or two digits whatever the pattern's count | `Localize.Time.Parser` | Parsing Dates and Times: "accept 9, 09" | Done |
| `g` is a Julian day number | `Localize.DateTime.Formatter` | `g` in the symbol table | Done |
| A numeric month is CLDR's number for it | `Localize.DateTime.Formatter` | Month names keyed by number | Done |
| An interval's numbers take the format's `numbers` | `Localize.Interval` | dateFormats: "all of the numeric fields in the date format" | Done |
| An interval is written in the fallback pattern's order | `Localize.Interval` | intervalFormats: "determines the default order" | Done |
| An interval item is matched as `availableFormats` are | `Localize.Interval`, `Localize.DateTime.Format.Match` | Interval algorithm, step 2 | Done |
| The era is the greatest difference | `Localize.Interval` | CLDR's `G` entries of its `Gy` items | Done |
| A calendar's formats inherit the Gregorian calendar's | `Localize.DateTime.Format.AppendItems` | Calendar data inheritance | Done |
| The localized GMT format's digits are the locale's | `Localize.DateTime.Timezone` | Localized GMT format | Done |
| The GMT format is read leniently, in any digits | `Localize.DateTime.Timezone` | Time Zone Parsing, step 3 | Done |
| A string that is a name is read before it is split | `Localize.DateTime.Timezone` | Time Zone Parsing: "the longest match" | Done |
| A metazone's name with a country is that country's zone | `Localize.DateTime.Timezone` | Time Zone Parsing, step 8 | Done |
| A standard name with no daylight name stands for every type | `Localize.DateTime.Timezone` | Type fallback | Done |
| A name of another season reads back as its own offset | `Localize.DateTime.Timezone` | Time Zone Parsing: "or to just an offset" | Done |
| A metazone's name is qualified in both non-location formats | `Localize.DateTime.Timezone` | Non-location formats, step 4.3 | Done |
| Decimal rounding is half-even | `Localize.Number.Formatter.Decimal` | Rounding | Done |
| A currency's digits override a currency pattern's | `Localize.Number.Format.Options` | Currencies | Done |

In these the comment that named only ICU now names the clause, or names ICU after it as agreeing or as differing. A sentence that records what ICU writes beside a rule of TR35's is kept: the difference is a fact the divergence guide needs.

## TR35 is silent, decided

| Behaviour | Decided | Status |
|---|---|---|
| `G` in a calendar of cyclic years is the cycle's number | User, 2026-10-06 | Done |
| Two dates of different cycles are written in full | User, 2026-10-06 | Done |
| A zone keeps its metazone from 1970 | User, 2026-10-06 | Done |
| `zzzz` for a zone with no name is the long GMT format | User, 2026-10-04 | Done |
| A fixed offset is a `DateTime` whose zone is the offset | User, 2026-10-06 | Done |
| A date and time interval takes the standard date-time pattern | User, 2026-10-02 | Done |
| A metazone's name read with a date before 1970 | Mine, told 2026-10-06 | Done |
| An ISO 8601 offset is read in any numbering system's digits | Mine, told 2026-10-05 | Done |
| The order a zone's string is read in, where it leaves TR35's sample | Mine, told 2026-10-05 | Done |
| A numbered month beside a word stays a name in an interval's skeleton | Mine, told 2026-10-04 | Done |

**A fixed offset.** TR35's text was not read before this was recommended, and should have been. It says "an implementation will be able to either determine the zone id, or a simple offset from GMT", and that what follows "is only a sample; implementations may use different methods". The sample gives a zone id: `"-08:00" (ISO 8601) => Etc/GMT+8` and `"GMT+3" => Etc/GMT-3`. Localize returns the simple offset, as a `t:DateTime.t/0` whose time zone is `"-08:00"`, which TR35 allows and does not describe, the representation being Elixir's and not TR35's subject. The sample's `Etc/GMT+8` is a zone every IANA database knows, so `DateTime.add/4` would need no `Localize.TimeZoneDatabase` for an offset of whole hours, and it has no id for one of 5 hours and 30 minutes.

**The order a zone's string is read in.** TR35's sample is "only a sample", and its own measure is that "a correct parse will roundtrip the location format (VVVV) back to the canonical zoneid". Localize departs from the sample's order in three places so that what the formatter writes reads back: the qualifier as a city first, a name the locale has before a region format, and the primary zone of a country with several.

## Departs from TR35 by the user's decision

| Behaviour | TR35 | Decided | Status |
|---|---|---|---|
| A week 53 the year lacks is an error | Week Data, note | User, 2026-10-02 | Done |
| A skeleton is matched against `availableFormats` alone | availableFormats: "the predefined patterns" | User, 2026-10-06 | Done |

**A week 53 the year lacks.** TR35's note on week data has it that such a date "should be treated as in the first week of the following year", and ICU reads it so. Localize returns an error and records the difference (user, 2026-10-02: "keep existing behaviour and note the difference in the ICU Conformance guide").

**`availableFormats` alone.** TR35 names "the predefined patterns" among those a skeleton is matched against, and ICU adds the standard formats' patterns. CLDR's own conformance data is made without them, and adding them fails 43 of its locales, so Localize matches `availableFormats` alone (user, 2026-10-06).

## TR35 is silent, undecided

Each of these was decided without the user. Most follow ICU; none contradicts a clause of TR35's.

| Behaviour | Where | Status |
|---|---|---|
| A year written without an era | `Localize.Date.Parser.implied_era/2` | Open |
| Metazones that share a name | `Localize.DateTime.Timezone.preferred_metazone/2` | Open |
| A wall time the clocks pass twice | `Localize.DateTime.Timezone`, `Localize.DateTime.WallClock` | Open |
| A wall time the clocks skip | `Localize.DateTime.Timezone.across_gap/4` | Open |
| The offset of a seasonal name CLDR gives no offset | `Localize.DateTime.Timezone.named_offset/4` | Open |
| Where an offset's seconds go in the GMT format | `Localize.DateTime.Timezone.seconds_pattern/2` | Open |
| How the short GMT pattern is cut | `Localize.DateTime.Timezone.hour_field_pattern/1` | Open |
| Two times across noon at a 24-hour interval | `Localize.Interval.difference_key/3` | Open |
| Noon and midnight where the pattern shows no minutes | `Localize.DateTime.Formatter.period_noon_midnight/4` | Open |
| The distances between `a`, `b` and `B` | `Localize.DateTime.Format.Match` | Open |
| `C` beside a day period of its own | `Localize.DateTime.Format.Match.allowed_hour/2` | Open |
| The fields `:column` alignment pads | `Localize.DateTime.SemanticSkeleton` | Open |
| A relative offset a hundredth from a whole number | `Localize.DateTime.Relative.named_form/3` | Open |
| Zero takes the future pattern | `Localize.DateTime.Relative` | Open |

**A year written without an era.** In a calendar that writes its years as years of an era, the Japanese calendars, "5年4月1日" is read as a year of the reference date's era, as ICU takes the current era. TR35's parsing section names no default for a field the text lacks. The alternative is an error.

**Metazones that share a name.** "Greenwich Mean Time" names the GMT, British and Irish metazones in `en`. The one with a zone in the locale's territory is read, else the one with zones in the most territories, else the first by name: Reykjavik in `en`, London in `en-GB`, Dublin in `en-IE`. TR35's sample takes a name for one metazone; the order was made to give ICU's results.

**A wall time the clocks pass twice.** Read with a zone's name, "1:30 AM Eastern Time" on the day the clocks go back is standard time, the later moment, as ICU reads it. `Localize.DateTime.WallClock.offset_at/3`, which relative time and durations use, takes the first occurrence, as RFC 5545 and ECMA-262 Temporal do. TR35 says nothing of either, and the library has both rules.

**A wall time the clocks skip.** It is read at the offset before the change in both places: New York's 02:30 on the day it springs forward is 03:30 daylight time.

**The offset of a seasonal name CLDR gives no offset.** "EST" read in July keeps its own offset, which TR35 allows ("or to just an offset"). Where the zone's metazone period has no `stdOffset` and `dstOffset`, the offset is the zone's standard offset then, with, for a daylight name, the most the zone saves within nine months either side, or an hour where it saves none. The nine months and the hour are ICU's.

**The GMT format's seconds and its short pattern.** TR35 gives the long format an "optional 2-digit seconds field" and the short one "hour fields without leading zero, with optional 2-digit minutes and seconds fields", and CLDR's `hourFormat` has hours and minutes alone. The seconds follow the minutes behind the text between the hours and the minutes ("+HH:mm:ss", `fi`'s "+H.mm.ss"), and the short pattern is the pattern up to its hour field, as ICU's `expandOffsetPattern` and `truncateOffsetPattern` have them.

**Two times across noon at a 24-hour interval.** `Hm` from 10:00 to 14:30 takes the item's `H` pattern. TR35 has "the calendar field with the greatest difference" choose the pattern and does not say whether the day period is a field of a pattern that does not write one; CLDR gives a 24-hour item no `a` entry, so the other reading would write every such interval around the fallback pattern.

**Noon and midnight where the pattern shows no minutes.** "h b" writes 12:05 as "12 noon" and "h:mm b" as "12:05 PM": the time is judged at the precision its pattern shows, as ICU judges it. TR35 has noon "= 12:00" and does not speak of a pattern without minutes. The other reading writes "12 PM".

**The distances between `a`, `b` and `B`.** TR35 has the three "a small distance from each other" and gives no numbers. `b` is nearer `a` than `B` (10, 15 and 20), as ICU's pattern generator has them, so `hb` takes the `h` format over `Bh`.

**`C` beside a day period of its own.** `C` takes the first of the locale's allowed hour formats with its day period. Where the skeleton names a day period too (`Ca`), the allowed format's is dropped, as ICU's generator does for zh-Hant's "ah時". TR35 does not speak of `Ca`.

**The fields `:column` alignment pads.** TR35's note is that "the most common behavior ... is for implementations to render a minimum of two digits on impacted fields", and it does not name them. A month, a day and an hour are padded and a year is not, as ICU4X does.

**A relative offset a hundredth from a whole number.** With `numeric: :auto`, 0.9999 days is "tomorrow": an offset within one percent of -2 to 2 takes the named form, as ICU matches it. ECMA-402 takes the named form for the exact number alone, and TR35 does not speak of an offset that is no whole number.

**Zero takes the future pattern.** "in 0 days", as ECMA-402 has it. TR35 does not say which pattern zero takes.

## Not yet checked

| Module | Places | Status |
|---|---|---|
| `Localize.Number`, its formatters, parser and options | 25 | Open |
| `Localize.Number.Rbnf` and its processor | 8 | Open |
| `Localize.Message.Interpreter` | 4 | Open |
| `Localize.Unit` formatting and the Beaufort scale | 3 | Open |
| `Localize.Locale.DistanceTrie` | 2 | Open |
| `Localize.Inflection` | 2 | Open |

These name ICU as the reason for a behaviour: the lenient grouping a number is read with, the sign of a negative zero, compact notation's rounding, grouping and default precision, the plural operands of a currency, RBNF's rollback rule and its bracketed rules, the numbering system of rule-based output, the Beaufort scale's boundaries, and the walk of the locale-distance trie. Each is to be read against TR35's Part 3 (`tr35-numbers.md`), Part 1 (`tr35.md`) and Part 6 (`tr35-info.md`), and given a standing as above. Mentions that only name a thing, ICU MessageFormat 2 or the NIF that binds ICU4C, are not counted.
