# TODO

Outstanding work on Localize. The design detail behind these items lives under [plans/](plans/); the shipped history is in [CHANGELOG.md](CHANGELOG.md), and the release standing is in [STATUS.md](STATUS.md).

## Open

* [ ] **Loading every locale runs the VM out of literal memory** — a loaded locale stays in `:persistent_term`, about 1.2 MB each, so all 657 take 814 MB of the literal area's default gigabyte, and a VM that also parses in them stops with `literal_alloc: Cannot allocate` (it stopped the test suite). Decide whether to document `+MIscs`, bound what is kept, or keep locales elsewhere.

* [ ] **A datetime interval whose date half is coarser than a day repeats the date** — `format: :yMMMHm` from 10:00 on 15 June to 14:30 on 16 June is "Jun 2026, 10:00 – Jun 2026, 14:30", and `:ywHm` on two days of one week repeats the week, since the datetime path judges the difference by the day field and not by the fields the date half writes, as a date interval now does. ICU4C 78.3 adds the day ("Jun 15, 2026, 10:00 – Jun 16, 2026, 14:30"); the reading that writes `Hm` across days as the times alone gives "Jun 2026, 10:00 – 14:30". Decide which (found 2026-10-04).

* [ ] **A calendar of weeks reads a week date as its own only as it writes it** — for `Calendrical.NRF`, "2026-W25-2" is the calendar's own week 25 (20 July 2026) alone, after a space and before a `T`, but "2026W252" without its hyphens and "2026-W25" without its day are ISO 8601's week (16 and 15 June), since the calendar's notation is what its `parse_date/1` reads and its `date_to_string/3` writes. Decide whether week-date text in any ISO 8601 form is the calendar's own (found 2026-10-04).

* [ ] **Choose a fixed-offset representation that `DateTime` functions honour** — Localize and Calendrical carry an offset such as `-05:00` under `Etc/UTC`, so `DateTime.shift_zone(parsed, "Etc/UTC")` returns it unchanged. The MF2 interpreter converts from the instant instead; `Etc/GMT+5` or an offset string would need both libraries to change together.

* [ ] **`Localize.Calendar.localize/3` names the first value of a part the date lacks** — a map without a month is January, the first quarter and a Monday, and one without a year the current era; characterization tests pin this. Decide whether they should be errors.

* [ ] **An interval item's year is of another kind than the year asked for** — a format that names the year (`de`'s Chinese medium "dd.MM U") takes CLDR's `yMd` item and keeps its number, "43-05-02 – 43-05-06" beside "02.05 bing-wu" (25 locales), and one that writes the related year (`en`'s "MMM d, r") has it put in place of the name in the item "MMM d – d, U", "Mo5 2 – 6, 2026" (488 locales), a change TR35 forbids: "adjustments should never convert a numeric element in the pattern to an alphabetic element, or the opposite". Decide between the item's own year, as TR35's matching leaves it ("Mo5 2 – 6, bing-wu"), both dates in full, as ICU4C writes them ("Mo5 2, 2026 – Mo5 6, 2026" and "02.05 bing-wu – 06.05 bing-wu"), and the year asked for in the item's place.

* [ ] **A calendar of weeks' date written at a skeleton does not read back** — `yMMMd` writes `Calendrical.NRF`'s own year, period and day in CLDR's generic format, "CE 2023 M03 4", and the text is read as a Gregorian date, as text for a calendar of weeks is: none of the 28,908 dates written at eleven skeletons in the two calendars of weeks and 657 locales reads back with its skeleton. Decide what a skeleton writes for a calendar of weeks: its own fields, read back in the calendar, or the Gregorian day.

* [ ] **A composite calendar's dates of its earlier calendar do not read back** — `Calendrical.Reform.Japan` writes a date before 1873 with the Chinese calendar's formats, its `cldr_calendar_type/3` answering for the date, and the reader has only the module's `cldr_calendar_type/0`, the Japanese calendar: "Mo5 11, 1872" and every date of its lunisolar years is an error, where `Calendrical.LunarJapanese` reads the same text. The reader needs every CLDR calendar a module's dates are written in, which no callback answers; decide the callback (an optional `cldr_calendar_types/0` in Calendrical, each reading held to the type the calendar gives the date it makes).

* [ ] **An interval is parsed by compiling its patterns' regexes on every call** — a date's patterns are compiled once for a locale and calendar and kept, an interval's are not, so `Localize.Interval.parse/2` takes about 70 ms where no early pattern reads the text, and `Localize.DateTime.Parser.parse/2` pays it for a single date wherever the locale's fallback separator is in the text (`da`'s hyphen). Keeping them costs literal memory, some megabytes for a locale and calendar; decide between keeping them, a bounded cache, and refusing a pattern by its count of fields before it is compiled.

* [ ] **An interval across sixty-year cycles writes its two dates alike** — two Chinese or Dangi dates sixty years apart take the interval's pattern for a year, "5/2/43 – 5/2/43" for `en`'s `yMd`, where ICU4C holds the cycle as an era and writes both in the skeleton's own format, "5/2/2026 – 5/2/2086". Decide whether a year of another cycle is written in full, as a year of another era is.

* [ ] **`G` for a Chinese or Dangi date is an error** — CLDR gives those calendars one era and no name for it, so a pattern with `G` returns `Localize.ItemNotFoundError`, where ICU4C writes the number of the sixty-year cycle, "78". TR35 is silent; decide what it writes.

* [ ] **A metazone's name is written for dates before 1970** — a `usesMetazone` period with no `from` is taken to reach back without end, so Los Angeles in 1850, at -7:52:58, is "Pacific Standard Time"; TR35 does not say where such a period begins, CLDR's zones are told apart only "back to 1970", and ICU4C begins it at 1970, writing "GMT-07:52:58" and "Los Angeles Time" there and "GMT-05:00" for New York in 1965. Decide where a first period begins.

* [ ] **An interval typed without years across the new year is refused** — "Dec 28 – Jan 3" is two dates of the reference date's year, the later first, and so an inverted range, as it was when each side was read alone. The formatter never writes one, adding the years where they differ, and neither TR35 nor ICU reads an interval. A decision: whether the second date is of the year after.

* [ ] **An interval item is written in digits where the date alone takes its format's numbering** — `he`'s Hebrew medium interval is "1–5 בתמוז 5786" beside the date "א׳ בתמוז ה׳תשפ״ו", and `zh`'s Chinese "2026年五月2至6" beside "2026年五月初二", as ICU4C writes them: CLDR's interval items carry no numbering and TR35 says nothing of one for them. Decide whether an interval at a standard format takes the format's numbering, as it takes its fields.

## In progress

* [ ] **CLDR 49 upgrade** — the plan's items are closed bar item 11; the data is built from CLDR `main` pending beta3 (below), then the final release. [plans/cldr-49.md](plans/cldr-49.md).

## Blocked

* [ ] **Move the CLDR pin to beta3** — the data is built from CLDR `main` at `6198cae999`, `release-49-beta2` with the converter fix it lacks (CLDR-19774) and the Manitoba DST metazone change (user, 2026-09-30). Blocked on CLDR 49 beta3, expected 2026-10.

* [ ] **Interval patterns inherited from a different locale level than the single date** — plan item 35: whether to glue or keep the inherited pattern. Blocked on CLDR-14207.

* [ ] **Report the date formats that write the week-based year to CLDR** — thirteen `availableFormats` entries and two standard date formats, in `de`, `de_CH`, `gd`, `gl`, `kek`, `ki`, `ksh`, `my`, `oc`, `pt`, `sc` and `te`, write `Y` where the skeleton names `y`, so 2025-12-29 is "29 Dezember 2026 n. Chr., Mo." at `de`'s `GyMMMMEd` and "dezembro de 2026 d.C." at `pt`'s `GyMMMM`, and `my` writes the Japanese calendar's 22 November 2023 "R 22/11/2023", which reads back as no date it was written from. Blocked on the user filing `tmp/cldr-reports/01-week-based-year-in-month-year-formats.md`.

* [ ] **Report 12-hour patterns without a day period to CLDR** — `fr-CM`'s `h`, `hm` and `hms`, `bal-Latn`'s `hm` and `es-AR`'s `hms` are 12-hour patterns with no day period, which TR35 forbids, so the "12:30" and "1:45" they write each name two times. Blocked on the user filing `tmp/cldr-reports/02-twelve-hour-patterns-without-a-day-period.md`.

* [ ] **Report `en_CA`'s month-first numeric intervals to CLDR** — its Gregorian `Md`, `MEd`, `yM`, `yMd` and `yMEd` interval items are "M/d/y–M/d/y" where its dates are "y-MM-dd" with a day-first variant, so 16 to 20 June 2026 is "6/16/2026–6/20/2026" beside "2026-06-16". Blocked on the user filing `tmp/cldr-reports/08-en-ca-numeric-intervals-month-first.md`.

* [ ] **Report interval patterns that write their differing field once to CLDR** — twenty-two patterns in eighteen locales: `sw` and `rw` write 16 June to 20 August 2026 as "16 – 20 Ago 2026", which no reader can take for that range, `ru`'s `hm` writes 10:30 to 14:30 as "10:30 — 02:30", and fourteen name one era for two. Blocked on the user filing `tmp/cldr-reports/09-interval-patterns-with-the-differing-field-once.md`.

* [ ] **Report `kek`'s latest-first interval fallback pattern to CLDR** — its Gregorian `intervalFormatFallback` is "{1} – {0}", the only one in any locale, which TR35 makes the order of all its interval patterns, so Localize and ICU write 16 to 20 June 2026 as "20 – 16 Xwaq Po, 2026". Blocked on the user filing `tmp/cldr-reports/10-kek-interval-fallback-latest-first.md`.

* [ ] **Report interval items with two field orders to CLDR** — in 57 locales an item orders its year, month and day one way for some differences and another for the rest, 65 Gregorian items and 45 of the generic calendar: `ha` writes "16/06/26 – 20/06/26" for a day's difference and "26-06-16 – 27-08-20" for a year's. Blocked on the user filing `tmp/cldr-reports/11-interval-items-with-two-field-orders.md`.

* [ ] **Report `GyMd` formats in another order than the numeric date to CLDR** — in `af`, `am`, `fa` and `ga` the generic calendar's `GyMd` is month-first with the year last, as English writes it, beside numeric dates in the locale's own order, so `af` writes 7 January 2569 BE as "1-7-2569 BE" at `GyMd` and "7/1/2569 BE" at `yyyyMd`; `en_AE`, `es_PA`, `es_PR`, `en_SE` and `en_ZA` inherit the same. Blocked on the user filing `tmp/cldr-reports/12-gymd-against-the-numeric-date.md`.

* [ ] **Report `ksh`'s 24-hour pattern with a day period to CLDR** — its `Hmsv` is "H:mm:ss a v", which TR35 says a 24-hour pattern should not be, the only one in any locale; it writes "16:05:09 n.M." and has the shape of the 12-hour text for four in the afternoon. Blocked on the user filing `tmp/cldr-reports/07-twenty-four-hour-pattern-with-a-day-period.md`.

* [ ] **Report standard date and time formats whose `datetimeSkeleton` is not the pattern's to CLDR** — 123 Gregorian date formats in 75 locales, where the pattern changed and the skeleton did not (`id`, `te`), or one of the two is inherited and the other the locale's own (`zu`, `en_NZ`, `vi`, `en_CA`), and 61 time formats in 17 locales, 14 of them with a skeleton of another hour cycle than the pattern (`cop`, `syr`, `bo`). Blocked on the user filing `tmp/cldr-reports/06-date-skeletons-not-derived-from-their-patterns.md`.

* [ ] **Report numeric skeletons that contradict the standard date format to CLDR** — `mt`, `sbp`, `vai_Latn`, `ug`, `my` and `sa` write a skeleton's day and month, or day and year, in the other order than the standard format, and `kk_Arab`'s `yMd` "y-d-M" has ISO 8601's shape, so text the skeleton writes reads as another date unless `parse/2` is given its format. Blocked on the user filing `tmp/cldr-reports/03-skeletons-against-the-standard-formats.md`.

* [ ] **Settle the location format of a non-location zone with CLDR** — TR35 49 says a zone with no region (`PST8PDT`, `Etc/GMT+5`) falls back to the offset format, then gives "PST8PDT, generic → Unknown Location Time" as its worked example. Localize follows the first; the conformance data has no case. Blocked on the user filing `tmp/cldr-reports/04-location-format-of-a-non-location-zone.md`.

* [ ] **Settle TR35's `Auto` zone style with CLDR** — TR35 makes it the default but its mapping table gives it no row, so Localize defaults to `:specific`; ICU4X offers no automatic style at all. Blocked on the user filing `tmp/cldr-reports/05-auto-time-zone-style.md`.

* [ ] **Report `hy`'s day-first intervals beside its year-first dates to CLDR** — CLDR 49's Survey Tool import made Armenian's Gregorian dates year-first, "2026 թ. հնս 16", and left its `yMMMd` and `yMMMEd` interval formats day-first, "16–20 հնս, 2026 թ."; three interval patterns write the year's abbreviation with a one-dot leader after one year and a full stop after the other. Blocked on the user filing `tmp/cldr-reports/13-hy-intervals-day-first-beside-year-first-dates.md`.

## Deferred

* [ ] **An interval pattern's `latestFirst:` and `earliestFirst:` prefixes are not read** — TR35 lets one pattern override the order its locale's fallback pattern states, and ICU4C reads the prefixes. No pattern of CLDR 49 has one, and one would be taken for pattern letters; reading them needs the data build to keep a prefix apart from its pattern.

* [ ] **MF2's `calendar` option reaches into Calendrical** — `Localize.Message.Interpreter` resolves `calendar=hebrew` to a module through `Localize.OptionalDependency.call("Calendrical", ...)`, which the rule that Localize never depends on Calendrical forbids; deferred (user, 2026-10-01). A registry Calendrical fills at start-up is one way to a module.

* [ ] **Recheck map-order selections that only today's data keeps deterministic** — seven lookups walk a map and never see two candidates in the current CLDR data; recheck them whenever it is regenerated. [plans/map-order.md](plans/map-order.md).

* [ ] **`localize_emoji` sibling library** — plan item 11, a separate package on its own schedule. A Phoenix LiveView picker (`localize_emoji_live`) is out of scope for its 0.1.0.

## Done

* [x] **A skeleton is matched against the locale's available formats alone** — decided (user, 2026-10-06): the standard formats' patterns are not added to the patterns a skeleton is matched against, though TR35 names "the predefined patterns" and ICU4C adds them, since CLDR's own conformance data is made without them and 43 of its 279 locales fail with them. Nothing changes in the library; the difference from ICU4C is recorded in `guides/icu_divergences.md` and held by `test/localize/datetime/skeleton_conformance_test.exs`. 2026-10-06, v1.4.0.

* [x] **A year's name beside its number stands when a numbered year is asked for** — a skeleton that asks for the related year (`r`), the extended year or the week's year had its symbol put in the place of every year of the pattern it matched, the name's too, so root's Chinese "r(U)" was "r(r)": the skeleton `r` wrote "2026(2026)" in 543 locales, and `rMMMEd` in `en-CA` "Tue, Mo5 2, 2026(2026)". TR35's adjustments "should never convert a numeric element in the pattern to an alphabetic element, or the opposite", and the name stands, "2026(bing-wu)", as ICU4C writes it; a pattern with the name alone is adjusted as before. Of 15,768 Chinese and Dangi dates at twelve such skeletons in 657 locales 4,708 had a year twice and none has, and 8,597 are ICU4C 78.3's text (5,119 before); 9,152 of 2,645,082 skeleton renderings in 33 calendars change, each a doubled year, and the 256 dates and times of 714,816 that a semantic skeleton wrote so read back. No date, interval or date and time reads otherwise in the other sweeps. 2026-10-06, v1.4.0.

* [x] **A date and time is read with the semantic skeleton it was written with** — `Localize.DateTime.parse/2` ignored a `Localize.DateTime.SemanticSkeleton` given as `:format` and read each half in any of the locale's formats; it reads each half with the skeleton's date fields or its time fields, as it reads with a skeleton or a pattern, so text of another format is refused. A skeleton whose minutes are optional writes a time on the hour without them, "2 PM", which `Localize.Time.parse/2` could not read with it: the reader has no value to choose by as the formatter has, and reads either. Of 714,816 dates and times and times alone written with a semantic skeleton in eleven calendars and 657 locales, 4,812 more read back (714,379) and none fewer; the 437 left are a year's name replaced by the related year, "2026(2026)" (256, a fault of the formatter's own), and CLDR's 12-hour patterns with no day period and `kek`'s week-based year (181). 2026-10-06, v1.4.0.

* [x] **A date and time is written with the numbering its date format states** — CLDR gives a date pattern the numbering of its numeric fields, the `numbers` attribute, which TR35 makes the pattern's, and the date half of a date and time lost it: `he`'s Hebrew date and time was "1 בתמוז 5786, 14:30" beside the date's "א׳ בתמוז ה׳תשפ״ו", `zh`'s Chinese day "2" beside "初二", `ja`'s first year of an era "1" beside "元" and `haw`'s month "6" beside "vi", where ICU4C writes each as the date alone. All 72,270 dates and times at the standard formats in eleven calendars and 657 locales now hold their date as it is written alone (210 did not, in the 17 locales whose formats state a numbering), as the 144,540 date-time intervals do (351 did not), and 142 more read back with the format they were written with; none of 289,080 rows is worse, nor of 714,816 written with a semantic skeleton. 2026-10-06, v1.4.0.

* [x] **An interval whose item names the year is read with the related year written in its place** — the formatter writes the year a format asks for where CLDR's interval item has its year, so `en`'s Chinese medium interval, from the item "MMM d – d, U", is "Mo5 2 – 6, 2026", and the reader offered the related year only for an item's `y`: it reads it for an item's `U` too. 1,979 more of the 195,257 intervals at the standard formats in 35 calendars and 657 locales read back, every lunisolar medium interval among them, and 2,930 more of 183,582 at other dates and formats, 2,073 of which were read as another range; none fewer. The 248 left at the standard formats are written from CLDR patterns that cannot be read back (`sv`'s day written twice, `sw`'s month written once, `om`'s two orders), which the reports to CLDR under Blocked cover. 2026-10-06, v1.4.0.

* [x] **A date two of a locale's formats read is read by the one whose own separators it has** — `af`'s `GyMd` in the generic calendar is "M-d-y G" beside a `yyyyMd` of "d/M/y GGGGG", and its "10-7-2569 BE" was read by the second, a hyphen for its slash, as the tenth of July: a format whose own text is in the input is tried before one that reads it leniently, as an interval's patterns are, and a format's variant is never moved up, the formatter writing it only when asked (`en-CA`'s "5/3" stays the third of May). Of 1,306,116 dates of every month in 657 locales 535 more read back and none fewer, and 16 more of 63,072 read as whichever value the text is; the 1,235 left are in locales whose two formats share their separators (`am`'s "1/7/5785 AM"), which only the data can tell apart. 2026-10-06, v1.4.0.

* [x] **An interval written without a year is of the reference date's year** — two dates an interval format reads with no year, `en`'s "Jun 16 – 20" at `MMMd`, had no year to be dates of and were read only as two partial dates with `as: :map`: each is a date of the reference date's year, as a date alone written without one is. All 57,904 intervals written without a year at eight formats in eleven calendars and 329 locales read back (39,776 before, and 624 of the rest as another range). 2026-10-06, v1.4.0.

* [x] **An interval is read with the spaces beside its dash left out or put in** — an interval's pattern was read only with the spaces it has about its dash, so `en`'s "Jun 16–20, 2026" was an error, as `de`'s "16. – 20.06.2026" was with them: TR35's parsing has spaces "ignored (except to delimit the tokens of the input string)", and a dash delimits without them, so the spaces beside a dash are optional wherever the pattern has it (`fil`'s Hebrew "d – MMM d y" is split at its second day) and the rest of the text between the dates is kept (`hy`'s "dd MMM, y թ․ – dd MMM, y թ."). Of 52,091 intervals with one en or em dash at five formats in eleven calendars and 329 locales, 51,551 read back as written, without the spaces and with them (23,410 before), the other 540 not reading as written either; none of the 195,257 at the standard formats in 35 calendars and 657 locales or the 183,582 with an era reads otherwise, and none of 59,787 single dates is read as a range. 2026-10-06, v1.4.0.

* [x] **An interval in a year two eras share is read** — a date an interval writes without its month asked the calendar which year its year of the era was with no month, and 2019 alone is neither Heisei 31 nor Reiwa 1, so `en`'s "May 1 – 5, 1 Reiwa" and the medium interval of 25 locales in an era's first or last year were errors: each date asks with the month and the day it takes from the other. The 102 such intervals of 105,280 dates and intervals in 329 locales read back, and none of 183,582 intervals with an era or 195,257 at the standard formats reads otherwise. 2026-10-05, v1.4.0.

* [x] **A numbered field takes the abbreviated width of a named format** — TR35 says only that a number and a name are far apart, which left `GyMMMd` and `GyMMMMd` equally near `GyMd` in a calendar with no numbered format beside an era, and the order of the two ids chose the wide month: a name is measured from the abbreviated width and a number by its digits, as CLDR's reference generator and ICU measure them. `GyMd` at every era width in the four lunisolar calendars takes `GyMMMd` (5,096 of 2,645,082 skeleton renderings in 657 locales, and no other changed), and 198 more rows of CLDR's `skeletons.tsv` agree, none fewer; in the 32 locales whose `GyMMMd` names the year by its cyclic name alone, a date more than thirty years from the reference no longer reads back from `GyMd` (744 of 183,582 sample intervals). No row that agreed with ICU4C stopped agreeing. 2026-10-05, v1.4.0.

* [x] **An interval is written and read in the order the locale's fallback pattern states** — TR35 makes the fallback pattern the order of every interval pattern and ICU4C applies it, so `kek`, whose Gregorian pattern is "{1} – {0}", writes its interval formats the later value first, "20/8/2027 – 16/6/2026" and "14:30–10:00", as it joined two dates already, and reads them so; the same dates the other way round are an inverted range there, as the later date first is in `en`. A date written once beside two times stays before them, and an open interval keeps no space where its missing value was. Of `kek`'s 2,970 intervals in 33 calendars the 1,834 that read back still do, 1,120 of them rewritten, and no other locale's fallback pattern is latest first. 2026-10-05, v1.4.0.

* [x] **The first year of a Japanese era is read as `ja` writes it** — its full, long and medium dates take CLDR's `jpanyear` numbering, whose year 1 is 元, and "令和元年5月1日" was an error, where a day in `hanidays` and a month in `romanlow` were read: a year an algorithmic numbering writes otherwise than in digits is read before the digits. The 27 dates of five eras' first years that `ja` writes so, of 105,280 in 329 locales, read back, and none reads otherwise. 2026-10-05, v1.4.0.

* [x] **A year of an era is read where the calendar renumbered its years after the era began** — `Calendrical.Reform.Japan` counts its years from 645 until 1872 and as the Gregorian calendar does from 1873, so Meiji, which begins in its year 1224, was counted on to years it does not have: no date from 1 January 1873 to the end of Meiji in 1912 was read. The year is counted from the year CLDR gives the era's beginning as well, and the calendar is asked whether it writes that year so. Of 105,280 dates and intervals written on each side of the reform and of each era's beginning, in 16 calendars and 329 locales, 11,816 more read back and none fewer; the calendar's lunisolar dates before 1873 are still not read (Open). 2026-10-05, v1.4.0.

* [x] **An interval is read by the pattern whose own separators it has** — `ha`'s `yMd` item writes a year's difference with root's year-first pattern, "26-06-16 – 27-08-20", which its own day-first pattern read through a lenient separator as 26 June 2016 to 27 August 2020: a pattern whose literal text is in the input is tried before one that reads it leniently, and 131 intervals in `ha`, `sah`, `yi`, `kk` and `az-Cyrl` read back as written. With the range fix below, 419 more of the 195,257 intervals at the standard formats in 35 calendars and 657 locales read back and none fewer, and no single date reads otherwise. 2026-10-05, v1.4.0.

* [x] **A range is cut at every place its separator is found** — where a locale's fallback pattern joins two dates with a hyphen, as `da`'s and `el`'s do, a calendar of weeks' "2026-W25-2-2026-W27-1" was cut after "2026" and was no interval: every cut is tried and the first with a date on each side taken, so the 288 intervals of the two calendars of weeks in 16 locales read back, "October 5, 2026 to October 10, 2026" is not cut inside "October", and the text a fallback pattern writes before its first date (`fr-CH`'s "du {0} au {1}") is read. Of 59,787 single dates in 13 calendars and 657 locales none is read as a range, by `Localize.Interval.parse/2` or by `Localize.DateTime.Parser.parse/2`. 2026-10-05, v1.4.0.

* [x] **An interval's date without an era is of the era beside it, and a narrow era is read** — an interval item writes its era once, and the date without it takes the era of the date beside it, where it took the reference date's; a narrow era name is read wherever it names one era, by a format that states it before one that only allows it, as `sv-AX`'s "8-01-07 R" is its `GyMd`'s and not its short date's. Of 183,582 intervals with an era in 31 calendars and 329 locales 23,822 more read back and none fewer, as do 2,077 more of the 195,257 at the standard formats in 657; no single date of 1,306,116 reads otherwise. 2026-10-05, v1.4.0.

* [x] **A Hebrew date in Elul is read beside its era** — the calendar is asked about the month of the year that CLDR's number names, where it was asked about month 13 of a common year of twelve: of 1,306,116 dates of every month in 29 calendars and 657 locales, the 4,726 that were an error or another date, all Hebrew, read back, as do 704 of the 706 intervals ending in Elul; `mn`'s narrow Hebrew "7", Adar's and Adar II's alike, is read too. 2026-10-05, v1.4.0.

* [x] **A narrow month name is read where it names one month** — where a format writes a narrow month and the calendar's narrow names are each one month's, as `mn`'s Roman numerals are and `en`'s "J" is not: `mn` alone writes one, in five formats and 37 interval patterns, so its `yM` "2026 VI" and its numeric intervals read back (52 of its 54 dates that were not, the two left Hebrew), and of 1,486,134 narrow months written in 29 calendars and 657 locales none reads as another month. 2026-10-05, v1.4.0.

* [x] **A format with a variant is read as the formatter writes it** — `en-CA`, the one locale with variants of its date formats, has its standard and default patterns read before their variants: its short date in a calendar it takes from `en` ("5/2/2026", read day first in ten of 173,576 dates) and its numeric intervals, items of two patterns the reader passed over (42 of 195,257 intervals, CLDR's month-first "6/16/2026–6/20/2026" among them, which the formatter writes as ICU4C does). 2026-10-05, v1.4.0.

* [x] **A skeleton's year is a number at every width** — a `y`, `r` or `u` request takes a numbered year's format before the cyclic year's name, `U` being a name at every width, by TR35's larger distance between a numeric and a text field: `en`'s Chinese `yMd` is `yyyyMd`'s "5/2/2026", not `UMd`'s "5/2/bing-wu", and `en-AU`'s Buddhist `yMMMd` "19 Apr 2566 BE", not "19/04/2566"; 21,968 of 1,127,700 dates in 33 calendars and 657 locales changed, none away from ICU4C. 2026-10-05, v1.4.0.

* [x] **A 24-hour hour agrees with a day period beside it** — TR35's parsing checks "the dayperiod … for consistency with the hour", so an `H` or `k` hour its day period does not hold is no reading: `ksh`'s `Hmsv`, "H:mm:ss a v", read "4:00:00 n.M. GMT+5:30", which `hmsz` writes for 16:00, as 04:00. 2026-10-05, v1.4.0.

* [x] **A string with two readings is the zone that writes it at the date** — `resolve/3` takes the first reading whose zone is written as the string then: `it`'s "Ora dell’Europa orientale (Kaliningrad)" is Kaliningrad in 2026 (Minsk before), "Malaysia Time" in 1975 Kuala Lumpur at +07:30 (Kuching in 279 locales), `sv`'s "Kaliningradtid" in a summer Kaliningrad's clock, each the moment ICU4C reads; and a name qualified by a city is that city's zone, "Israel Time (Gaza)" Gaza. 2026-10-05, v1.4.0.

* [x] **A country or city qualifies a zone's name only after a name the locale writes** — TR35's sample parse reads "xxx (Italy)" as Rome whatever xxx is, and with it a 24-hour pattern read a time's day period into its zone, `en-GB`'s "4:00:00 pm (India)" as 04:00 in India, and a time's hour out of its year; "PM (India)" is now no zone. 2026-10-05, v1.4.0.

* [x] **A locale's GMT literal alone is GMT** — the 74 locales with a literal of their own read it with no offset as offset 0, "غرينتش" in `ar` and `ga`'s "MAG", as TR35's parsing has it ("HPG" is `Etc/GMT`) and ICU4C reads it in 647 of 656 locales; only "GMT", "UTC" and "UT" alone were. 2026-10-05, v1.4.0.

* [x] **An offset with no sign is read after the GMT literal** — "GMT 3", "UTC5:30" and "غرينتش ٣" are offsets east to `parse_zone/2`, `parse_offset/2` and `resolve/3`, as TR35's parsing allows "+, -, or nothing"; a zone that is a field of a date or time keeps needing the sign ("12:00:00 UTC 2026" is no offset of 20:26), and so does a number before a literal that follows it ("10:30 GMT"). 2026-10-05, v1.4.0.

* [x] **An offset before standard time is written whole and read back** — the localized GMT format and `Z` write the seconds TR35 gives them an optional field for ("GMT-07:52:58" and "-075258" for Los Angeles' -7:52:58, as ICU4C writes them), and the reader takes seconds after a one-digit hour ("GMT+3:30:45", "33045") and an hour to 23, Juneau's +15:02:19 before 1867. 2026-10-05, v1.4.0.

* [x] **The long localized GMT format has a two-digit hour in every locale** — `cs`, `fi` and `vmw` give their `hourFormat` a one-digit hour, the short format's, and `OOOO` wrote "GMT+5:30" and "UTC+5.30" with it; TR35's long format "always uses 2-digit hours field", so it is "GMT+05:30" and "UTC+05.30", as ICU4C writes them. 2026-10-05, v1.4.0.

* [x] **`Timezone.resolve/3` reads an offset in the digits of any numbering system** — `parse_offset/2`, `parse_zone/2` and `resolve/3` read the localized GMT format with "non-Latin numbers", as TR35's parsing has it: the 154,753 of 3,961,584 zone strings the formatter writes in 67 locales' own digits were an unknown zone, and the digits of all 78 numbering systems are read in any locale. Bytes that are not UTF-8 are an error where they raised. 2026-10-05, v1.4.0.

* [x] **A zone's name is read before a country in its shape, and its qualifier before a country's primary zone** — "Chile Time (Punta Arenas)" is Punta Arenas (Santiago in 289 locales), `ko`'s "사모아 표준시" American Samoa (Apia in nine) and `fo`'s "Vesturevropa tíð (Spania)" the Canary Islands (Madrid), as ICU4C reads each; a country with several zones stands for its primary zone last, after TR35's own steps. 2026-10-05, v1.4.0.

* [x] **A name of standard or daylight time is read with the time its zone keeps at the date** — the reading the formatter names so, by CLDR's `stdOffset` and `dstOffset` where a metazone period gives them, in place of the least and greatest offset within nine months: "Chile Summer Time (Punta Arenas)" in 488 locales, and any name near a change of its zone's offset, 3,366 strings in `en` from 1990 to 2027. 2026-10-05, v1.4.0.

* [x] **The location format writes a country's code where the locale does not name the country** — "CU" for Havana's zone in `su` and "ora de CU" in `oc`, as TR35 composes it and ICU4C writes it, read back only in a locale that writes the country so; a country name in the fallback format's shape, `fr-CA`'s "Saint-Martin (France)", is read whole. 2026-10-05, v1.4.0.

* [x] **An interval's two-digit years beside an era written once read back** — a standard format with `yy` and an era (the short date of `nl`, `de` and `lij` in the era calendars) writes such an interval, and its second year was read as the year itself, "69"; found by running the standard-format intervals through every calendar before and after the change that gave them their pattern's widths. 2026-10-04, v1.4.0.

* [x] **Specific zone names are qualified as CLDR's own formatter qualifies them** — `z` and `zzzz` take TR35's steps for the non-location formats, "Pacific Standard Time (Canada)" for Vancouver in `en`, and read back as their own zone; against `TimezoneFormatter` over 656 locales and 551 zones no name differs but where the tool departs from TR35. 2026-10-04, v1.4.0.

* [x] **Six zones keyed in snake case find their city and names** — Blanc-Sablon, Port-au-Prince, Porto-Novo, Ust-Nera, DumontDUrville and McMurdo were looked up under their lowercase names and never found, so they were written with the city their own name gives and not read from the locale's. 2026-10-04, v1.4.0.

* [x] **`zzzz` keeps the long localized GMT format for a zone with no name** — the user's decision, as ICU4C and ICU4X write it ("GMT+03:00" for Amman), though TR35 49's symbol table says the short one. 2026-10-04, v1.4.0.

* [x] **CI keeps the locales the test helper downloads** — by design (user): a test of every locale walks the locales on the machine, the downloaded ones in CI and all 657 on the maintainer's, where the matrix of the definition of done is run. 2026-10-04.

* [x] **A date-time in another calendar is named with the metazone its zone kept at the instant it names** — its fields are read through its calendar, where they were read as ISO's ("GMT+05:00" for a Persian date in Almaty that is "Kazakhstan Time"); zone names now agree with `Calendar.ISO`'s in 35 of Calendrical's calendars and all 657 locales. 2026-10-04, v1.4.0.

* [x] **`y` in the Chinese and Dangi calendars is the year's place in the sixty-year cycle** — written from the calendar's `cyclic_year/3` where the locale's data names the calendar's years by a cycle, as TR35 has it and ICU4C writes it ("40. 윤2. 29." in `ko`), with `u` for the year's number, and read back as the year of that place nearest the reference date. 2026-10-04, v1.4.0.

* [x] **An interval at a standard format takes the fields of its pattern** — its dates, its times and the times of a date and time are written at the widths, and in the clock, the single value is written with, where CLDR's `datetimeSkeleton` or the region's preferred hour cycle decided (dates in 71 locales, a short time in 5, a date and time's times in 14); a month numbered beside a word stays the named month. 2026-10-04, v1.4.0.

* [x] **A time is read only with an hour its field has** — a 12-hour field took its hour modulo 12 ("45:30 PM" was 21:30 and "13:30 AM" 01:30 in 618 locales, "45:30" 09:30 in `fr-CM` and `bal-Latn`); an hour over 12 there is now no time, as TR35's ranges and ICU's strict parse have it, "13:30 PM" included. 2026-10-04, v1.4.0.

* [x] **`Localize.Time.parse/2` reads ISO 8601's times alone** — after the designator `T` a time without its seconds, minutes or separators ("T10:30", "T10", "T103045"), and a time between colons in every locale ("10:30" in `fi`, whose own format is "H.mm"); digits alone stay unread without the `T`. 2026-10-04, v1.4.0.

* [x] **`Localize.DateTime.parse/2` reads ISO 8601's other dates and times either side of a `T`** — a week date, a day of the year and a date without separators before it, a time without its seconds or minutes or without separators after it ("2026-W25-2T10:30", "20260616T103000Z"), in MessageFormat 2's literals too; a calendar of weeks' own notation before a `T` is its own date. 2026-10-04, v1.4.0.

* [x] **`Localize.DateTime.parse/2` reads a date and time with the format it was written with** — each half is read with its part of `:format` and nothing else: a standard format's and a skeleton's date and time fields, and a pattern split at the text between its date fields and its time fields ("3/4/2024 22:05" with `"d/M/y HH:mm"`, "20240403T220509" with `"yyyyMMdd'T'HHmmss"`), or with `:date_format` and `:time_format`. 2026-10-04, v1.4.0.

* [x] **`Localize.Time.parse/2` takes the format the text was written with** — `:format` is a standard format, a skeleton or a pattern, as `to_string/2` takes it, and the text is read with it alone ("14h30" with `"HH'h'mm"`); a `:long` or a `:full` format reads a time with its zone and one written without it. 2026-10-04, v1.4.0.

* [x] **ISO 8601's remaining date forms are read** — a week without a day ("2026-W25", "2026W25") is the Monday of ISO 8601's week in every locale and calendar, and as a map its week-based year and week, or a calendar of weeks' year and week where it is one of its own; the week date and the day of the year read without separators, and a year and a month or a year as a map in every locale. 2026-10-04, v1.4.0.

* [x] **An interval's skeleton is widened with the month or the year its dates differ in** — `format: :d` is "6/15 – 7/15" across months and "6/15/2026 – 6/15/2027" across years, as ICU4C writes it, where two bare days were written; any skeleton is widened so, with the closest interval item at the widths asked for (`MEd`'s for `Ed`) or with both dates in full (`yQQQ` for `QQQ`). 2026-10-04, v1.4.0.

* [x] **A date and time with no zone reads back at `:long` and `:full`** — its time is the one `Localize.Time.to_string/2` writes for a value with no zone, the format's fields without the zone field, in a `NaiveDateTime` and in a map alike ("2024年4月3日水曜日 10:30:00" in `ja`, no "()" in `fa` or "[]" in `zh-Hant`); every locale reads all four standard formats back, where 24 failed at `:long` and 41 at `:full`. 2026-10-04, v1.4.0.

* [x] **A `Time` at a standard format is written with the locale's standard pattern** — `Localize.Time.to_string/2` resolved CLDR's skeleton for the format in place of its pattern, another pattern in 44 locales at `:short` and 47 at `:medium` ("10:30 ч." in `bg`, a 24-hour clock in `cop`); a format's zone-less fields are now its pattern's own. 2026-10-04, v1.4.0.

* [x] **A week read `as: :map` for a calendar of weeks is its year and week** — `Localize.Date.parse("week 25 of 2026", calendar: Calendrical.ISOWeek, as: :map)` is `%{year: 2026, month: 25}`, the fields the days of the calendar's own week share and the value it was written from, where it carried `day: 1`; each end of an interval and a week beside a time read alike. 2026-10-04, v1.4.0.

* [x] **A date interval compares the fields its format writes** — a week format writes both weeks (`format: :yw` is "week 25 of 2026 – week 30 of 2026", and a pattern of weeks likewise), and a quarter or a calendar of weeks' period is written once for two dates within it, the dates compared in each field written and not in the month and day fields that hold it (TR35's step 4). 2026-10-04, v1.4.0.

* [x] **Numeric widths in interval patterns follow TR35** — an interval item's numeric month and day take the widths of the skeleton requested, as an `availableFormats` pattern does, so `am`'s short interval is "01/04/2023 – 10/04/2023" beside its date "01/04/2023", where ICU4C writes "1/4/2023 – 10/4/2023"; recorded in `guides/icu_divergences.md` (user, 2026-10-04: "Use TR35"). 2026-10-04, v1.4.0.

* [x] **`parse/2` takes the format the text was written with** — `Localize.Date.parse/2` reads text with the `:format` it names and no other, `Localize.DateTime.parse/2` reads its date with `:date_format`, a standard `:format` or a skeleton's date fields, and `Localize.Interval.parse/2` each end, so `mt`'s `:yMd` "4/3/2024", `ug`'s "y-d-M" and `my`'s Japanese `:GyMd` read back (user, 2026-10-04). 2026-10-04, v1.4.0.

* [x] **An ISO 8601 offset written hard against a time is kept** — `Localize.DateTime.parse("11/22/2023 14:30:45+02:00", locale: :en)` is a `DateTime` at +02:00, where `Time.from_iso8601/1` discarded the offset and the value came back naive. 2026-10-04, v1.4.0.

* [x] **An interval of Chinese or Dangi dates reads its related year** — `Localize.Interval.parse/2` takes an interval's year as the related year or the calendar's own, whichever is nearer the reference year, so "11/8/2023 – 11/18/2023" is two days of the Chinese year 4660 and not of the year 2023. 2026-10-04, v1.4.0.

* [x] **A calendar's own formats are read before ISO 8601** — text ISO 8601 reads as a date that any format of the calendar asked for also reads, as leniently as it reads any text (`r-MM-dd`, `y/M/d`), is the calendar's own date, alone or with a time after a space, so the Chinese and Dangi short dates and a Julian date in `sv` read back; `Calendar.ISO`, and text with ISO 8601's `T`, are ISO 8601's (user, 2026-10-04: "Use the broader rule"). 2026-10-04, v1.4.0.

* [x] **`Localize.Nif` loads while Localize is compiled** — its body calls `Code.ensure_compiled!(Localize.Priv)`, so the module its `@on_load` callback calls is compiled and loaded first, and builds on Elixir 1.17 and 1.18 no longer log the callback's `:undef`; a lint test holds every `@on_load` callback to it. 2026-10-04, v1.4.0.

* [x] **An interval of two dates that hold some of their fields** — two months, a month and a day each, or a year and a month take CLDR's interval format for those fields in `Localize.Interval.to_string/3` and `to_parts/3` ("Jun – Aug", "Jun 15 – 20", "Jun – Aug 2026"), open intervals too, and a date and time with no year keeps its date. 2026-10-04, v1.4.0.

* [x] **A year and a week of a calendar of weeks is written as the locale's week of the year** — `Localize.Date.to_string(%{year: 2026, month: 25, calendar: Calendrical.ISOWeek})` is "week 25 of 2026", CLDR's `yw`, the month field read as the week it holds; formatting is Localize's, so the calendar gained no callback (user, 2026-10-04). 2026-10-04, v1.4.0.

* [x] **Standard and daylight time by a metazone's `stdOffset` and `dstOffset`** — the supplemental data keeps TR35's two offsets for each metazone period, and where a period names them the offset picks the specific name: Dublin's summer is "Irish Standard Time" whatever `std_offset` says, Winnipeg's -05:00 "Central Daylight Time". 2026-10-03, v1.4.0.

* [x] **Map-order dependence in the code since the 2026-09-26 audit** — audited; the standard formats come in `standard_formats/0`'s order, and a country or city name of zone parsing that two places share resolves by a fixed rule. [plans/map-order.md](plans/map-order.md). 2026-10-03, v1.4.0.

* [x] **No tag without a CLDR locale id is made by the library** — `Localize.Locale.parent/1` built each parent by clearing the child's subtags and its CLDR locale id, so its nine callers validated every parent again, matching it against all 657 locales (about 20 ms a step); a parent now names its CLDR locale. 2026-10-03, v1.4.0.

* [x] **RBNF formatting takes a fraction of a millisecond** — a rule is looked up along the locale's chain of CLDR locales, found once a locale, where each call revalidated every parent tag: `he`'s Hebrew numerals went from 42 ms a call to 0.4 ms, `en`'s Roman numerals from 54 ms to 0.1 ms. 2026-10-03, v1.4.0.

* [x] **`nnh`'s long and full dates parse** — the date and time parsers read a pattern by code points, so the combining caron after `nnh`'s quoted "lyɛ" no longer swallows the closing quote. 2026-10-03, v1.4.0.

* [x] **`haw`'s Roman-numeral months parse** — a numeric month written in an algorithmic numbering is read as the formatter writes it, as a day already was, so "31/xii/24" is 31 December 2024. 2026-10-03, v1.4.0.

* [x] **`en-ZW` reads "May 2019" as May 2019** — a comma that is a pattern's only separator between two fields stays required, and the comma-stripped month-day swap keeps a space for it, where "dd MMM,y" ran the day and year together. 2026-10-03, v1.4.0.

* [x] **Ambiguous currency text resolves by the nearest locale** — a string several of the locale's currencies share names the currency whose territory's CLDR locale is nearest, within a good fit and untied: "$" is the Canadian dollar in `fr`, and stays unknown in `es`. 2026-10-03, v1.4.0.

* [x] **Hebrew dates in `he` parse** — a year in Hebrew numerals ("ה׳תשפ״ד") is read by its letters' values (`Localize.Number.HebrewNumerals`), and the day was already read as the formatter writes it, so `he`'s Hebrew dates read back. 2026-10-03, v1.4.0.

* [x] **The time parser reads the calendar's time formats** — the `:calendar`'s patterns, then the Gregorian calendar's, so `de`'s Chinese "10 vorm." parses; the compiled patterns are cached per calendar, where the first calendar parsed in a locale kept its patterns for every other. 2026-10-03, v1.4.0.

* [x] **The localized GMT format writes the locale's digits** — "GMT-४" in `ne` and "غرينتش-٤" in `ar-EG`, as TR35 and ICU4C write them, or the digits of `-u-nu-` and `:number_system`, as the date's other fields are. 2026-10-03, v1.4.0.

* [x] **A `-u-rg-` subdivision gives its region as the territory** — `territory_from_locale/1` returns `:GB` for `en-u-rg-gbsct`, where it returned `:gbsct`, so currency, unit preferences and time zone names take the region, as the week data already did. 2026-10-03, v1.4.0.

* [x] **A duration is the span the calendar's own shifting adds** — the years, months and days of `Localize.Duration.new/2` are the most years, then the most months, that the calendar's `shift_date/4` adds without passing the later date, its `diff/3` giving a first count, since a calendar of weeks shifts by its years and then its months: 2026-W53-1 to 2027-W52-1 is a year, where it was a year and 28 days. Found by measuring every calendar's durations against `Date.shift/2`. 2026-10-02, v1.4.0.

* [x] **`Localize.Duration.new/2` measures two date-times in time zones as two moments** — the later is moved to the earlier's time zone, days and longer are counted on that wall clock and the hours, minutes and seconds are the time that passes, as ECMA-262 Temporal and relative time reckon (user, 2026-10-02), so 10:00 UTC to 18:00 in Karachi is 3 hours. A time paired with a naive date-time no longer raises, and no pairing of kinds gives a negative duration. 2026-10-02, v1.4.0.

* [x] **`u` writes the calendar's extended year** — the formatter asks the calendar's `extended_year/3`, so 15 June 1 BC in `Calendrical.Julian`, whose year is -1, is "0". The Buddhist, ROC, Chinese and Dangi calendars keep their own year, where ICU4C writes a Gregorian one (user, 2026-10-02), recorded in the ICU divergences guide. 2026-10-02, v1.4.0.

* [x] **A year or a week alone in a calendar of weeks formats** — a partial date's year and era are asked of its calendar with the fields it has, and a span of days it could be ends on a day the calendar has (`year/1`, `valid_date?/3`), never one composed from `months_in_year/1` and `days_in_month/2`, so a year alone in `Calendrical.ISOWeek` writes "2026 AD", as its whole date does, where it was a `Localize.InvalidValueError`. Found through Tempo. 2026-10-02, v1.4.0.

* [x] **`Localize.Calendar.ISO` answers the whole Calendrical behaviour** — all 27 callbacks in the one module, as `Calendrical.ISO` answers them, held to the behaviour by a Calendrical test, and the calculations Localize made itself come from the calendar: a `W` week's days, a year's days, the years, quarters and months of a relative time and the years, months and days of `Localize.Duration.new/2` (`week/2`, `year/1`, `diff/3`, `plus/6`), with two dates ordered by their days and not by `Date.compare/2` (user, 2026-10-02, point 5). [plans/calendar-callbacks.md](plans/calendar-callbacks.md). 2026-10-02, v1.4.0.

* [x] **A week's month and a week 53 the year lacks stay as they are** — `W` keeps a week in the month that holds the locale's minimum days of it, and a week 53 the year does not have stays an error, where ICU4C keeps a week in its date's month and reads the week 53 as week 1 of the next year (user, 2026-10-02: "keep existing behaviour"); both recorded in the ICU divergences guide. 2026-10-02, v1.4.0.

* [x] **`Calendar.ISO`'s weeks are the locale's** — `w`, `Y` and `W` follow the locale's week data by TR35's rule, in this one case only (user, 2026-10-02), with TR35's first day algorithm in full (`-u-fw-`, `-u-rg-`, `-u-sd-`, `-u-ca-iso8601`) and `e` and `c` honouring it; `Y`, `w` and `e` agree with ICU4C 78.3 on 74,511 locale-days, and `W` gives a week to the month holding the minimum days of it. [plans/calendar-callbacks.md](plans/calendar-callbacks.md). 2026-10-02, v1.4.0.

* [x] **A week calendar's date is written in its own notation** — "2026-W25-2" from the calendar's `date_to_string/3` at every standard format, in a date and time and in an interval, read back through its `parse_date/1`, with a pattern's months named by CLDR's generic calendar ("M06"), replacing `281b9990`'s Gregorian day (user, 2026-10-02). 2026-10-02, v1.4.0.

* [x] **Calendar months through callbacks** — every answer about a date comes from its calendar's callbacks, `Calendar.ISO` answered by Localize, with no probe or identity branch left; the MF2 `calendar` option is deferred. [plans/calendar-callbacks.md](plans/calendar-callbacks.md). 2026-10-02, v1.4.0.

* [x] **An interval joins its date and time with the standard pattern** — as TR35 says, on one day and for whole datetimes across days (user, 2026-10-02), where it took the "at" pattern; ICU4C 78.3 takes "at" for the whole datetimes. `style: :at` keeps it. 2026-10-02, v1.4.0.

* [x] **`Localize.Interval.to_string/3` selects an interval format by its skeleton** — a date interval takes a skeleton or a pattern by `:format` or `:date_format`, and a datetime interval splits a skeleton into its date and time fields (TR35 step 3.2); a time skeleton across days keeps TR35's reading, not ICU's added `yMd` (user). Found through Tempo. 2026-10-01, v1.4.0.

* [x] **An impossible date or time is an error** — every value Localize formats is checked with its calendar's `valid_date?/3` and `valid_time?/4` where it enters (`Localize.Calendar.validate_value/1`), where `E`, `e`, `c`, `D`, `g` and `Q` raised and other fields wrote "Feb 30, 2019". 2026-10-01, v1.4.0.

* [x] **Publish the CLDR 49 locale data** — v49.0.0 published to R2 from this machine with `mix localize.publish_locales`; manifest, all 657 files and a CDN sample verified. 2026-10-01.

* [x] **Menu names for key types** — `type_name/3` with `prefer: :menu` returns CLDR's `scope="core"` names now that the converter keeps them per value (CLDR-19774); all 11,195 in 160 locales reach the data. 2026-09-30, v1.4.0.

* [x] **The CLDR JSON is built by Localize** — `mix localize.build_cldr_json` runs CLDR's converter from the pinned CLDR ref with `fullnumbers`, replacing cldr-json's release, so locales carry every numbering system's data CLDR gives them; nothing is vendored. 2026-09-30, v1.4.0.

* [x] **Locale data is published from the maintainer's machine** — `mix localize.publish_locales` uploads the generated set, purges the Cloudflare cache and records the manifest, refusing a released data version; CI only checks R2 holds the committed data, since the converter needs more memory than a runner has. 2026-09-30.

* [x] **Root's `arab` and `arabext` data reaches every locale** — first read from `root.xml` into `und`, then the same day carried by each locale's own JSON, as ICU gives it (168 ICU4C cases added); the long currency format no longer raises in `sd` and `ckb`. 2026-09-30, v1.4.0.

* [x] **Relative time counts calendar periods** — every unit is counted with the value's calendar arithmetic, never seconds over a mean month or year (user, 2026-09-30), so `:quarter` and the weekday units no longer format seconds; months and years match ICU4C's `fieldDifference` in eight calendars. 2026-09-30, v1.4.0.

* [x] **The generic zone format writes ambiguous names** — `v` and `vvvv` follow TR35's steps as CLDR's own formatter implements them, qualifying a metazone name by country or city ("Mountain Time (Phoenix)") and taking a standard name only for a zone that keeps one offset; every zoned date-time formatted in every locale now reads back but `nnh`'s. 2026-09-30, v1.4.0.

* [x] **Zone names and localized GMT formats parse** — `Localize.DateTime.Timezone.parse_zone/2` reads every form TR35's time zone parsing does and `resolve/3` resolves it through the configured time zone database, no longer through Calendrical; of 52,560 zoned date-times formatted in every locale 14,099 round-tripped and 51,903 now do, the rest `nnh` and the generic format item. 2026-09-30, v1.4.0.

* [x] **Native digits in the time parser** — times, and with them date-times, are read in the digits of the locale's number system, and month, quarter, weekday and era names written in those digits (`dz`, `bn`, `ckb`, `ff-Adlm`) are read too; of 59,787 times and 3,942 short and medium date-times formatted in every locale none in native digits fails to parse, and a zoned one fails only where its Latin-digit form does. 2026-09-30, v1.4.0.

* [x] **The time parser's pattern order** — standard formats first and patterns with a zone or a flexible day period last, and a flexible day period read against every period of its name; of 59,787 times formatted in every locale, every one in Latin digits parses back but 15 from the patterns CLDR gives no day period. 2026-09-30, v1.4.0.

* [x] **Interval formats of non-Gregorian calendars** — intervals, date-times and times take their calendar's formats and date-time pattern, an era change shows both eras, equal endpoints take the standard format, and date-times parse back in every calendar; checked against ICU4C 78.3 and V8 in 17 calendars and 36 locales. 2026-09-29, v1.4.0.

* [x] **Lunisolar dates parse back** — the parsers read `r`, `U`, leap months, traditional month numbers and `hanidays`/`hanidec` numerals, checked against ICU4C 78.3; of 29,640 lunisolar round trips the 701 left are ISO 8601 look-alikes, two-digit years outside the window and era years written without their era. 2026-09-29, v1.4.0.

* [x] **Calendrical's era and year answers reach Localize whole** — Calendrical no longer raises before a first era, and Localize names eras from `era_calendar_type/0`, completes a year-less date in the calendar's own year and reads Amete Alem years. 2026-09-29, v1.4.0.

* [x] **Lunisolar numeric months match ICU4C** — a numeric month is its traditional number, a leap month in CLDR's numeric leap pattern, and a partial date writes its related and cyclic year; every fifth day of 2020–2026 in the Chinese and Dangi calendars formats as ICU4C does (477 differed). 2026-09-29, v1.4.0.

* [x] **The date parser reads a signed year** — the `y` field takes a leading minus, so a calendar without a before era reads back the year below 1 it writes ("Mar 15, -456 BE"); Calendrical's Buddhist and Indian round trips now pass. 2026-09-29, v1.4.0.

* [x] **The date parser reads the era** — a year written with its era is found among the candidates its era could count to, checked through the formatter's own functions, so every date the formatter writes with an era parses back (1,392 across 29 locales); a year its era qualifies is not pivoted. 2026-09-29, v1.4.0.

* [x] **A year before a Calendrical calendar's first era counts back from it** — a year below 1 from `calendar_year/3` is shown as its year of era, so `Calendrical.Gregorian` year 0 is "1 BC"; across Calendrical's 32 calendars only years below 1 change. 2026-09-29, v1.4.0.

* [x] **An era for a partial date** — its era and year of era are those its days agree on, so a year and month take `:Gy`, `year_style: :with_era` and `th`'s long `YM`; a Japanese date spanning two eras names the fields that settle it. 2026-09-29, v1.4.0.

* [x] **`SemanticSkeleton` rejects the field sets and options TR35 does not allow** — `new/2` takes TR35's 34 field sets in any order and refuses an option given without the fields it applies to; the formatters check a struct built by hand rather than raising on it. 2026-09-29, v1.4.0.

* [x] **`SemanticSkeleton` applies `:column` alignment** — a one-letter month, day or hour in the resolved pattern is widened to two, as ICU4X does, on every path through `Localize.Date`, `Localize.Time` and `Localize.DateTime`; the default takes TR35's name, `:inline`. 2026-09-29, v1.4.0.

* [x] **`he`'s short GMT format of a whole hour carries one left-to-right mark** — the short form keeps the offset pattern up to its hour field, as ICU's `truncateOffsetPattern` does, so "GMT-5" no longer repeats the mark its negative pattern ends with. The long form and the short form with minutes keep both marks, as ICU's do. 2026-09-29, v1.4.0.

* [x] **Invalid UTF-8 is an error, not a raise** — number and unit parsing, number, date/time and interval patterns, semantic skeleton codes, territory names, collation and inflection return their errors for a binary that is not UTF-8. A sweep of every documented function, with the text in each argument and in options and MF2 bindings, finds no other raise. 2026-09-29, v1.4.0.

* [x] **MF2 `:date`, `:time` and `:datetime` take TR35's options** — `fields`, `length`, `precision`, `timeZoneStyle`, `dateFields`, `dateLength` and `timePrecision` choose a semantic skeleton, and `timeZone`, `hour12` and `calendar` act on the operand. `en-AU` `fields=month-day` is "14 Jun" at TR35's default medium length; "14 June" is `length=long`. 2026-09-29, v1.4.0.

* [x] **The inflection engine keeps a locale's extensions** — `Localize.Inflection.Locale.normalize/1` drops `-u-`, `-t-` and `-x-` extensions, so quantities, lists and units in `ar-u-nu-arab`, `es-u-co-trad` or `tr-u-ca-gregory` keep their language's rules. 2026-09-29, v1.4.0.

* [x] **`Localize.Locale.parent/1` keeps the child's `cldr_locale_id`** — a parent found by dropping a subtag resolves its own CLDR locale, so regional locales spell numbers out with their language's RBNF rules as ICU does; a validated `und` walks to root, not English. 2026-09-29, v1.4.0.

* [x] **Print and speak output for the `i:` functions** — `output: :ssml` writes a message as SSML with upstream's `<sub alias>` spoken forms, and `:i:quantify` speaks its number in agreement with the noun, as upstream's factories do. 2026-09-29, v1.4.0.

* [x] **Semantic concepts as `i:` operands** — `Localize.Inflection.Concept` takes `:display_data`, forms of its own for sets of constraints as upstream's semantic concepts have, so all 49 upstream MF2 fixtures pass on their print lines. 2026-09-29, v1.4.0.

* [x] **`to=` on `:i:inflect` and `:i:pronoun`** — gives the operand's value for a feature (`to=number` gives `plural`), printing the operand for an unknown feature, as upstream does. 2026-09-29, v1.4.0.

* [x] **`:i:inflect` and `:i:pronoun` as selectors** — `.match` keys match what the function formats, and an unknown `to` feature matches only the catch-all; `:i:quantify`, `:i:list` and `:i:numeral` are not selectors. 2026-09-29, v1.4.0.

* [x] **`withReferent` on `:i:pronoun`** — chooses the pronoun that agrees with a referent string or concept ("mío" with "casas" gives "mías"). 2026-09-29, v1.4.0.

* [x] **Concept and pronoun-concept operands for the `i:` functions** — `:i:inflect` and `:i:quantify` take a `Localize.Inflection.Concept`, `:i:pronoun` a `PronounConcept` with its own pronouns, and either agrees as an option value. 2026-09-29, v1.4.0.

* [x] **Upstream option names, `:i:list` and `:i:numeral`** — the `i:` functions take the Unicode inflection project's option names (`case=`, `withValue=`), reject unknown features, and gain `:i:list` and `:i:numeral`. 2026-09-29, v1.4.0.

* [x] **Move the MF2 inflection functions to the `i` namespace** — `:i:inflect`, `:i:pronoun` and `:i:quantify` replace the `l:` names, and `i` is reserved in place of `l`. 2026-09-29, v1.4.0.

* [x] **Reject an impossible month in the datetime parser's map form** — the map forms of the date, datetime, time and interval parsers reject any field no date or time has, as the struct forms do, instead of dropping or keeping it. 2026-09-29, v1.4.0.

* [x] **Selections that followed map order** — a territory's primary currency, shared narrow currency symbols, the parser's longest and fuzzy matches, territory-name lookup and a locale's number-system order no longer depend on map order. [plans/map-order.md](plans/map-order.md). 2026-09-26, v1.4.0.

* [x] **The pipeline reads the CLDR sources in place** — nothing is copied into `priv/cldr` any more, the cldr-json release and CLDR ref are recorded in `priv/localize`, and `mix localize.fetch_sources` fetches them, so checking out `main` needs no ceremony. Details in [plans/cldr-source-payload.md](plans/cldr-source-payload.md). 2026-09-25.

* [x] **Pattern fields at a width TR35 does not list format as U+FFFD** — `dddd`, `MMMMMM`, `HHH` and the rest follow TR35's Handling Invalid Patterns instead of ICU's padding and clamping; an undefined letter stays an error. 2026-09-25, v1.4.0.

* [x] **Locale downloads retry transient CDN failures** — server errors, timeouts and dropped connections are retried with backoff and jitter, a 404 fails at once, and the address family is configurable. Details in [plans/locale-downloader-resilience.md](plans/locale-downloader-resilience.md). 2026-09-24, v1.4.0.

* [x] **Atom creation audited across the library and tests** — no test mints an atom from a fixture file; `Localize.Utils.Json` lost its atom-key option; `Localize.Inflection` rejects a path-shaped locale. The remaining runtime conversions in `lib/` are bounded and say why. 2026-09-24.

* [x] **CLDR's spec changes since beta1 reviewed** — hour cycle variations, the Date-Timezone and Time-Day-Of-Week glue, `placeholderBoundarySpacing`, plural rules in semantic order and `ha` ≡ `h` implemented; range separator patterns confirmed example-only; pattern-only skeleton symbols are only deprecated for CLDR 50. 2026-09-24.

* [x] **CLDR's full skeleton conformance data** — three further CLDR files wired in, and the matching defects they exposed fixed: weekday and year symbols, text widths, `j`/`C` day periods, lone fields, quoted literals, and skeletons matching `availableFormats` alone. 2026-09-24.

* [x] **Supplemental data regenerated from the beta1 sources** — the committed ETFs predated them: the US POSIX zones, the Eurozone, Breton collation and `u` validity changed. 2026-09-24.

* [x] **Refresh to CLDR 49 beta1** — sources from the cldr-json release zip, a guard against mixing pre-releases in `copy_sources`, and a recorded baseline for curated fixtures. 2026-09-24.

* [x] **Report the cldr-json `scope="core"` defect** — fixed upstream as CLDR-19774, which missed beta1; it arrives with beta2. 2026-09-24.

* [x] **Numeric date and time separators** — `Localize.DateTime.numeric_separators/2`, plus `:numeric_date_separator` and `:numeric_time_separator` on `Localize.Date`, `Localize.Time`, `Localize.DateTime` and `Localize.Interval`. 2026-09-20.

* [x] **Ordinal days (`ddd`) reviewed against the committed CLDR spec** — conforms on every normative point, and ships as a technical preview while CLDR's spec is pre-beta. 2026-09-20.

* [x] **Variant currency symbols** — `Localize.Currency.variant_symbol` and `currency_symbol: :variant`, which pick up the new Unicode 18 currency signs at the next data refresh. 2026-09-20.

* [x] **Public functions return errors instead of raising on wrong-type input** — plan item 41, swept across the public API. 2026-09-20.
