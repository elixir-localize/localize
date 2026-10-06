# TR35 audit of what follows ICU

**Status:** in progress, 2026-10-06

Localize follows TR35, and follows ICU only where ICU clearly follows TR35 (user, 2026-10-06: "You must follow TR35 and use ICU ONlY when it's clear it follows TR35"). This document is the check of the code against that rule: every comment and doc in `lib` that names ICU, read against TR35's text at CLDR `6198cae999` (`docs/ldml/tr35-dates.md` in the CLDR repository), and given one of four standings.

* **Contradicted TR35** — fixed, with the commit.

* **TR35 is the rule** — its clause is what the code implements. Where the comment gave only ICU as the reason, it now gives the clause.

* **TR35 is silent, decided** — by the user, with the date, or by me and told to the user at the time.

* **TR35 is silent, decided on recommendation** — fourteen choices that followed ICU, or were mine, and had never been put to the user, who settled them on 2026-10-06.

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
| Noon and midnight are judged at the precision the pattern shows | `Localize.DateTime.Formatter.period_noon_midnight/4` | Parsing Day Periods: "the rounding done by the time format" | Done |
| `b` is nearer `a` than `B` in a skeleton | `Localize.DateTime.Format.Match` | availableFormats: "matches an explicit or implicit 'a'" | Done |
| A wall time the clocks pass twice is read in standard time | `Localize.DateTime.Timezone` | Time zone goals: "favoring standard time" | Done |
| Decimal rounding is half-even | `Localize.Number.Formatter.Decimal` | Rounding | Done |
| A currency's digits override a currency pattern's | `Localize.Number.Format.Options` | Currencies | Done |

The last three rows before the two of numbers were first listed as undecided: I had read the row of the symbol and not the section. TR35's day period rules end "If rounding is done—including the rounding done by the time format—then it needs to be done before the dayperiod is computed, so that the correct format is shown"; its text on day periods in skeletons has `bh` take "h b" where the data has `Bh` too; and its goals for time zones give, for a generic format "when the local time maps to two possible GMT times", the example "favoring standard time". `Localize.DateTime.WallClock`, which takes the first occurrence, is calendar arithmetic as ECMA-262 Temporal has it (user, 2026-10-02), not the reading of a zone's name.

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

**A fixed offset.** TR35's text was not read before this was recommended, and should have been. It says "an implementation will be able to either determine the zone id, or a simple offset from GMT", and that what follows "is only a sample; implementations may use different methods". The sample gives a zone id: `"-08:00" (ISO 8601) => Etc/GMT+8` and `"GMT+3" => Etc/GMT-3`. Localize returns the simple offset, as a `t:DateTime.t/0` whose time zone is `"-08:00"`, which TR35 allows and does not describe, the representation being Elixir's and not TR35's subject. The sample's `Etc/GMT+8` is a zone every IANA database knows, so `DateTime.add/4` would need no `Localize.TimeZoneDatabase` for an offset of whole hours, and it has no id for one of 5 hours and 30 minutes. It stays the simple offset (user, 2026-10-06, on recommendation): one form for every offset, its sign as it is written.

**The order a zone's string is read in.** TR35's sample is "only a sample", and its own measure is that "a correct parse will roundtrip the location format (VVVV) back to the canonical zoneid". Localize departs from the sample's order in three places so that what the formatter writes reads back: the qualifier as a city first, a name the locale has before a region format, and the primary zone of a country with several.

## Departs from TR35 by the user's decision

| Behaviour | TR35 | Decided | Status |
|---|---|---|---|
| A week 53 the year lacks is an error | Week Data, note | User, 2026-10-02 | Done |
| A skeleton is matched against `availableFormats` alone | availableFormats: "the predefined patterns" | User, 2026-10-06 | Done |

**A week 53 the year lacks.** TR35's note on week data has it that such a date "should be treated as in the first week of the following year", and ICU reads it so. Localize returns an error and records the difference (user, 2026-10-02: "keep existing behaviour and note the difference in the ICU Conformance guide").

**`availableFormats` alone.** TR35 names "the predefined patterns" among those a skeleton is matched against, and ICU adds the standard formats' patterns. CLDR's own conformance data is made without them, and adding them fails 43 of its locales, so Localize matches `availableFormats` alone (user, 2026-10-06).

## TR35 is silent, decided on recommendation

These fourteen were found undecided: each had been settled without the user, most as ICU has them. The user settled them on 2026-10-06 ("Follow your recommendations"). Reading TR35's sections whole for the recommendation found its rule for three of them, which are rows of "TR35 is the rule" above; one changed; ten stand, each for the reason given, which is not that ICU does it.

| Behaviour | Where | Decided | Status |
|---|---|---|---|
| A relative offset that is no whole number is the number | `Localize.DateTime.Relative.named_form/3` | Changed | Done |
| A year written without an era is of the reference date's era | `Localize.Date.Parser.implied_era/2` | Kept | Done |
| Of metazones that share a name, the locale's country's is read | `Localize.DateTime.Timezone.preferred_metazone/2` | Kept | Done |
| A wall time the clocks skip is read at the offset before the change | `Localize.DateTime.Timezone.across_gap/4` | Kept | Done |
| A seasonal name CLDR gives no offset takes the zone's own saving | `Localize.DateTime.Timezone.named_offset/4` | Kept | Done |
| An offset's seconds follow its minutes in the GMT format | `Localize.DateTime.Timezone.seconds_pattern/2` | Kept | Done |
| The short GMT pattern is the pattern up to its hour field | `Localize.DateTime.Timezone.hour_field_pattern/1` | Kept | Done |
| Two times across noon at a 24-hour interval take its hour pattern | `Localize.Interval.difference_key/3` | Kept | Done |
| `C` beside a day period of its own writes that day period | `Localize.DateTime.Format.Match.allowed_hour/2` | Kept | Done |
| `:column` alignment pads a month, a day and an hour | `Localize.DateTime.SemanticSkeleton` | Kept | Done |
| Zero takes the future pattern | `Localize.DateTime.Relative` | Kept | Done |

**A relative offset that is no whole number** (`b65c0635`, its fixture test in `5b3e15fc`). With `numeric: :auto`, 0.9999 days was "tomorrow": an offset within half a hundredth of a whole number took the named form, as ICU4C matches it. TR35's `relative` is a name "for the current instance of the field, and one or two past and future instances", "the day with relative value -1" being "Yesterday", so an instance is a whole number of the field away, and ECMA-402, whose option `numeric` is, takes the name for the exact number. Calendar arithmetic gives whole numbers, so there is no error of division to allow for. Only a whole offset is named; 0.9999 days is "in 1 day".

**A year written without an era.** In a calendar that writes its years as years of an era, the Japanese calendars, "5年4月1日" is a year of the reference date's era. TR35's parsing section names no default for a field a text lacks. Kept, because the reference date supplies every other field a text lacks: a date written without its year is of the reference date's year.

**Metazones that share a name.** "Greenwich Mean Time" names the GMT, British and Irish metazones in `en`. TR35's sample takes a name for one metazone and then looks up "the Metazone + Country => TZID mapping"; put to each metazone of the name, that is the first test here, the metazone with a zone in the locale's country (London in `en-GB`, Dublin in `en-IE`). Where none has one, the metazone with zones in the most countries is read, and then the first by name, so that the reading does not turn on the order of a map (Reykjavik, the GMT metazone's golden zone, in `en`). Kept.

**A wall time the clocks skip.** New York's 02:30 on the day it springs forward is read at the offset before the change, 03:30 daylight time. TR35 says of it only that "there can also be a gap". Kept, because it is the one rule the library has: `Localize.DateTime.WallClock` reads a skipped time so for relative time and durations, as RFC 5545 and ECMA-262 Temporal do.

**A seasonal name CLDR gives no offset.** "EST" read in July keeps its own offset, which TR35 allows ("or to just an offset"). Where the zone's metazone period has no `stdOffset` and `dstOffset`, the offset is the zone's standard offset then, with, for a daylight name, the most the zone saves within nine months either side, or an hour where it saves none. Kept: the saving is the zone's own wherever it has one near the date, Lord Howe's half hour among them, and an hour is what daylight time saves everywhere else.

**The GMT format's seconds and its short pattern.** TR35 gives the long format an "optional 2-digit seconds field" and the short one "hour fields without leading zero, with optional 2-digit minutes and seconds fields", and CLDR's `hourFormat` has hours and minutes alone. The seconds follow the minutes behind the text the pattern has between its hours and its minutes ("+HH:mm:ss", `fi`'s "+H.mm.ss"), and the short pattern is the pattern up to its hour field. Kept: both write what TR35 describes with the locale's own separator.

**Two times across noon at a 24-hour interval.** `Hm` from 10:00 to 14:30 takes the item's `H` pattern. TR35 compares "the fields in the pattern", has a 24-hour pattern hold no day period ("should not include fields with day period characters"), and CLDR gives a 24-hour item no `a` entry. Kept: the hour is the greatest difference among the fields such a pattern has, and the other reading would write every such interval around the fallback pattern.

**`C` beside a day period of its own.** `C` takes the first of the locale's allowed hour formats with its day period. TR35 does not speak of a skeleton that names a day period beside `C` (`Ca`). Kept: a skeleton states the fields its caller wants, so its own day period is the one written, and zh-Hant's `Ca` is "ah時", never a pattern of two day periods.

**The fields `:column` alignment pads.** TR35's alignment has "Required Fields: Year, Month, Day, or Hour" and the note that implementations "render a minimum of two digits on impacted fields", "01/01/2000" for "1/1/2000". Kept: a month, a day and an hour are padded, and the year is not, two letters of a year being a pattern's year of two digits.

**Zero takes the future pattern.** "in 0 days". TR35 has a `relativeTime` for "a counted number of units in the past or the future" and does not say which zero is. Kept, as ECMA-402, whose shape this API has, takes the future pattern for a value that is not negative.

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
