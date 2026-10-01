# TODO

Outstanding work on Localize. The design detail behind these items lives under [plans/](plans/); the shipped history is in [CHANGELOG.md](CHANGELOG.md), and the release standing is in [STATUS.md](STATUS.md).

## Open

* [ ] **A week calendar's date is written as the day it names** — Localize writes a week calendar's date from its own fields, its week-based year, its period's month and its day of the week, so the text names another day and does not read back as the date: ISO 2026-W25-2, Tuesday 16 June 2026, is "Jun 2, 2026" (`D` 170 and `F` 1, where 16 June is 167 and 3), 2026-W27-1, 29 June, is "Jul 1, 2026", and 2026-W01-1, 29 December 2025, is "Jan 1, 2026". Write its era, year, month and day, with `D` and `F`, as the day's own in the calendar it is read in, its `parsing_calendar/0`, converting into it as the parser converts out of it, and keep its weeks and quarters (`w`, `W`, `Y`, `Q`) the calendar's. Planned in [plans/calendar-callbacks.md](plans/calendar-callbacks.md) ("Week-based dates", user, 2026-10-01, reversing "Jun 2, 2026"); Tempo's `to_string/2` of a week date waits on it (found through Tempo, 2026-10-01).

* [ ] **Settle the location format of a non-location zone with CLDR** — TR35 49 says a zone with no region (`PST8PDT`, `Etc/GMT+5`) falls back to the offset format, then gives "PST8PDT, generic → Unknown Location Time" as its worked example. Localize follows the first; the conformance data has no case. Worth a CLDR ticket.

* [ ] Currency parsing - when presented with an ambiguous currency text, resolve it by ordering the locales by the match distance to the current locale (either parameter, or Localize.get_locale/1)

* [ ] **Audit `cldr-49`-only code for map-order dependence** — the 2026-09-26 audit covered `main`. [plans/map-order.md](plans/map-order.md).

* [ ] **Choose a fixed-offset representation that `DateTime` functions honour** — Localize and Calendrical carry an offset such as `-05:00` under `Etc/UTC`, so `DateTime.shift_zone(parsed, "Etc/UTC")` returns it unchanged. The MF2 interpreter converts from the instant instead; `Etc/GMT+5` or an offset string would need both libraries to change together.

* [ ] **Report `pt`'s `GyMMMM` to CLDR** — CLDR gives it as "MMMM 'de' Y G", with the week-based year `Y` where every sibling format has `y`, so 2025-12-29 renders "dezembro de 2026 d.C.".

* [ ] **Report 12-hour patterns without a day period to CLDR** — `fr-CM`'s `h`, `hm` and `hms`, `bal-Latn`'s `hm` and `es-AR`'s `hms` are 12-hour patterns with no day period, which TR35 forbids, so the "12:30" and "1:45" they write each name two times.

* [ ] **Decide whether specific zone names are qualified** — CLDR's own `TimezoneFormatter` qualifies the specific format (`z`, `zzzz`) as it does the generic one, "Central European Summer Time (Germany)" for Berlin in `en`, where ICU4C never does; a specific name already reads back to its instant, and Localize qualifies only the generic format.

* [ ] **The localized GMT format writes Latin digits** — TR35 writes its offset in the locale's default digits, as ICU4C does (`ar-EG` "غرينتش-٤", `ne` "GMT-४"), where Localize writes "غرينتش-4" and "GMT-4"; the parser reads the two forms alike.

* [ ] **The time parser reads only the Gregorian calendar's time formats** — `Localize.DateTime.parse/2` in another calendar reads its time with the Gregorian patterns, so `de`'s Chinese `Bh` "10 vorm." does not parse where its Gregorian "10 Uhr vorm." does; take the calendar's time formats when `:calendar` is given, as the formatter now does.

* [ ] **Date round trips that fail in eight locales** — `haw` writes months in Roman numerals ("31/xii/24"), `nnh`'s long and full dates do not parse, `gd`'s `yMMM` writes the week-based year ("Dùbh 2025" for 2024-12-31, a CLDR report like `pt`'s), `en-ZW` reads "May 2019" as May 20, and numeric `yMd` dates in `mt`, `sbp`, `ug` and `vai-Latn` are read day-first.

* [ ] **Hebrew dates in `he` do not parse** — `he` writes a Hebrew calendar date's day and year in Hebrew numerals ("כ״ב בטבת ה׳תשפ״ד"), the `hebr` numbering, which the parser does not read as it reads `hanidays` and `hanidec`, so none of `he`'s Hebrew dates round-trip.

* [ ] **Decide how a calendar's ISO-shaped numeric date is read** — the parser reads any `y-MM-dd` text as an ISO 8601 date and converts it, so `he`'s Chinese short date "2023-11-22" (related year 2023, month 11, day 22) comes back as Gregorian 22 November 2023; a calendar's own pattern written that way never round-trips.

* [ ] **Numeric era dates read in another pattern's field order** — an era year small enough to be a day or a month fits the locale's other numeric patterns, so the Japanese `my` "Kanpō (1741–1744) 2/6/1" (y/M/d) is read as 1741-06-02 and `fa`'s "6/1/2 Kanpō (1741–1744)" as 1746-01-02, in either digits; `sa` likewise.

* [ ] **Numeric widths in interval patterns** — TR35's `availableFormats` adjustment pads an interval item's `d/M` to a style's `dd/MM` (`vi` short "01/04/2023 – 10/04/2023"); ICU4C and V8 normalise the skeleton's numeric widths away and write "1/4/2023 – 10/4/2023". Decide which to follow; it predates the calendar work and shows in Gregorian `vi`, `id`, `ms`, `te`, `am` and `sw`.

* [ ] **The hour cycle of a short time interval** — `format: :short` takes `hm` or `Hm` from the locale's preferred hour cycle, so in 18 locales, such as `ady-JO`, whose short time format is "HH:mm", a time interval is 12-hour and its single value "10:05 AM" where `Localize.Time.to_string/2` writes "10:05".

* [ ] **`y` in the Chinese and Dangi calendars** — ICU4C writes the year of the sixty-year cycle ("40. 2. 30." in `ko`), Localize the sequential year ("4660. 2. 30."), which CLDR's era data calls the year; TR35's `U` falling back to `y` suggests the cycle year. Decide which to follow and record it.

* [ ] **An ISO 8601 date that is also a locale's pattern** — root's Chinese and Dangi short pattern `r-MM-dd` writes "2020-05-01", which the parser reads as ISO 8601 first, so those dates do not parse back; decide whether a non-Gregorian calendar's own patterns come first.

* [ ] **`Localize.Calendar.localize/3` names the first value of a part the date lacks** — a map without a month is January, the first quarter and a Monday, and one without a year the current era; characterization tests pin this. Decide whether they should be errors.

* [ ] **Settle TR35's `Auto` zone style with CLDR** — TR35 makes it the default but its mapping table gives it no row, so Localize defaults to `:specific`; ICU4X offers no automatic style at all.

* [ ] **Name standard and daylight time by a metazone's `stdOffset` and `dstOffset`** — TR35 lets `usesMetazone` say which offset is standard time and which daylight where the time zone database's flag is unreliable (`Europe/Dublin`, and in CLDR 49 `America/Winnipeg` for Manitoba's DST change); Localize ignores both attributes and decides from the datetime's `std_offset`.

* [ ] **An interval joins its date and time with the "at" pattern** — `format_date_and_time_range/5` defaults `:style` to `:at`, so `en` `yMMMMdHm` on one day is "June 15, 2026 at 10:00 – 14:30" and `de` "15. Juni 2026 um 10:00–14:30 Uhr", where TR35 says an interval takes the standard pattern and ICU4C 78.3 writes "June 15, 2026, 10:00 – 14:30"; `style: :default` matches. Decide the default.

## In progress

* [ ] **Calendar months through callbacks** — Localize takes every answer about a date from callbacks on its calendar, never probing or introspecting it, with `Calendar.ISO` the only calendar it answers for itself; the month's CLDR name is `month_of_year/3` then a new `cardinal_month` callback. Fixes a July-start fiscal year's period 1 written "Jan" and an ISO week date's week written as its month ("25/2/26" for 2026-W25-2); the day a week date names is its own item, under Open. Planned in [plans/calendar-callbacks.md](plans/calendar-callbacks.md); found through Tempo (2026-10-01). Landed: every month field through `month_of_year/3` and `cardinal_month/1`, every other field, the parser and relative time through the calendar's callbacks with no probe left, the refusal of a calendar that cannot answer, a week calendar's dates parsed as Gregorian through its `parsing_calendar/0`, week numbers, weeks of the month and quarters in the calendar's own, and the `:japanese` branch gone; the MF2 `calendar` option is deferred.

* [ ] **CLDR 49 upgrade** — the plan's items are closed bar item 11; the data is built from CLDR `main` pending beta3 (below), then the final release. [plans/cldr-49.md](plans/cldr-49.md).

## Blocked

* [ ] **Move the CLDR pin to beta3** — the data is built from CLDR `main` at `6198cae999`, `release-49-beta2` with the converter fix it lacks (CLDR-19774) and the Manitoba DST metazone change (user, 2026-09-30). Blocked on CLDR 49 beta3, expected 2026-10.

* [ ] **Interval patterns inherited from a different locale level than the single date** — plan item 35: whether to glue or keep the inherited pattern. Blocked on CLDR-14207.

## Deferred

* [ ] **MF2's `calendar` option reaches into Calendrical** — `Localize.Message.Interpreter` resolves `calendar=hebrew` to a module through `Localize.OptionalDependency.call("Calendrical", ...)`, which the rule that Localize never depends on Calendrical forbids; deferred (user, 2026-10-01). A registry Calendrical fills at start-up is one way to a module.

* [ ] **Recheck map-order selections that only today's data keeps deterministic** — seven lookups walk a map and never see two candidates in the current CLDR data; recheck them whenever it is regenerated. [plans/map-order.md](plans/map-order.md).

* [ ] **`localize_emoji` sibling library** — plan item 11, a separate package on its own schedule. A Phoenix LiveView picker (`localize_emoji_live`) is out of scope for its 0.1.0.

## Done

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
