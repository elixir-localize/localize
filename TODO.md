# TODO

Outstanding work on Localize. The design detail behind these items lives under [plans/](plans/); the shipped history is in [CHANGELOG.md](CHANGELOG.md), and the release standing is in [STATUS.md](STATUS.md).

## Open

* [ ] **Decide whether root's `arab` and `arabext` blocks become a pipeline source** — plan item 38: CLDR JSON does not carry them, so `en-u-nu-arab` formats with the locale's `latn` symbols until `common/main/root.xml` is read directly.

* [ ] **Settle the location format of a non-location zone with CLDR** — TR35 49 says a zone with no region (`PST8PDT`, `Etc/GMT+5`) falls back to the offset format, then gives "PST8PDT, generic → Unknown Location Time" as its worked example. Localize follows the first; the conformance data has no case. Worth a CLDR ticket.

* [ ] Currency parsing - when presented with an ambiguous currency text, resolve it by ordering the locales by the match distance to the current locale (either parameter, or Localize.get_locale/1)

* [ ] **Audit `cldr-49`-only code for map-order dependence** — the 2026-09-26 audit covered `main`. [plans/map-order.md](plans/map-order.md).

* [ ] **Choose a fixed-offset representation that `DateTime` functions honour** — Localize and Calendrical carry an offset such as `-05:00` under `Etc/UTC`, so `DateTime.shift_zone(parsed, "Etc/UTC")` returns it unchanged. The MF2 interpreter converts from the instant instead; `Etc/GMT+5` or an offset string would need both libraries to change together.

* [ ] **Report `pt`'s `GyMMMM` to CLDR** — CLDR gives it as "MMMM 'de' Y G", with the week-based year `Y` where every sibling format has `y`, so 2025-12-29 renders "dezembro de 2026 d.C.".

* [ ] **Report 12-hour patterns without a day period to CLDR** — `fr-CM`'s `h`, `hm` and `hms`, `bal-Latn`'s `hm` and `es-AR`'s `hms` are 12-hour patterns with no day period, which TR35 forbids, so the "12:30" and "1:45" they write each name two times.

* [ ] **Zone names and localized GMT formats do not parse** — the zone field reads only English-shaped text, so of 7,884 zoned long and full date-times formatted in every locale 2,951 fail on their zone (`fr` "UTC−4", `de` "Nordamerikanische Ostküsten-Sommerzeit", `ar` "غرينتش-4"), and the names it does read ("EDT", "Eastern Daylight Time") are not resolved, so 1,075 come back without their zone.

* [ ] **The localized GMT format writes Latin digits** — TR35 writes its offset in the locale's default digits, as ICU4C does (`ar-EG` "غرينتش-٤", `ne` "GMT-४"), where Localize writes "غرينتش-4" and "GMT-4"; the parser reads the two forms alike.

* [ ] **The time parser reads only the Gregorian calendar's time formats** — `Localize.DateTime.parse/2` in another calendar reads its time with the Gregorian patterns, so `de`'s Chinese `Bh` "10 vorm." does not parse where its Gregorian "10 Uhr vorm." does; take the calendar's time formats when `:calendar` is given, as the formatter now does.

* [ ] **Date round trips that fail in eight locales** — `haw` writes months in Roman numerals ("31/xii/24"), `nnh`'s long and full dates do not parse, `gd`'s `yMMM` writes the week-based year ("Dùbh 2025" for 2024-12-31, a CLDR report like `pt`'s), `en-ZW` reads "May 2019" as May 20, and numeric `yMd` dates in `mt`, `sbp`, `ug` and `vai-Latn` are read day-first.

* [ ] **Numeric era dates read in another pattern's field order** — an era year small enough to be a day or a month fits the locale's other numeric patterns, so the Japanese `my` "Kanpō (1741–1744) 2/6/1" (y/M/d) is read as 1741-06-02 and `fa`'s "6/1/2 Kanpō (1741–1744)" as 1746-01-02, in either digits; `sa` likewise.

* [ ] **Numeric widths in interval patterns** — TR35's `availableFormats` adjustment pads an interval item's `d/M` to a style's `dd/MM` (`vi` short "01/04/2023 – 10/04/2023"); ICU4C and V8 normalise the skeleton's numeric widths away and write "1/4/2023 – 10/4/2023". Decide which to follow; it predates the calendar work and shows in Gregorian `vi`, `id`, `ms`, `te`, `am` and `sw`.

* [ ] **The hour cycle of a short time interval** — `format: :short` takes `hm` or `Hm` from the locale's preferred hour cycle, so in 18 locales, such as `ady-JO`, whose short time format is "HH:mm", a time interval is 12-hour and its single value "10:05 AM" where `Localize.Time.to_string/2` writes "10:05".

* [ ] **`y` in the Chinese and Dangi calendars** — ICU4C writes the year of the sixty-year cycle ("40. 2. 30." in `ko`), Localize the sequential year ("4660. 2. 30."), which CLDR's era data calls the year; TR35's `U` falling back to `y` suggests the cycle year. Decide which to follow and record it.

* [ ] **An ISO 8601 date that is also a locale's pattern** — root's Chinese and Dangi short pattern `r-MM-dd` writes "2020-05-01", which the parser reads as ISO 8601 first, so those dates do not parse back; decide whether a non-Gregorian calendar's own patterns come first.

* [ ] **`Localize.Calendar.localize/3` names the first value of a part the date lacks** — a map without a month is January, the first quarter and a Monday, and one without a year the current era; characterization tests pin this. Decide whether they should be errors.

* [ ] **Settle TR35's `Auto` zone style with CLDR** — TR35 makes it the default but its mapping table gives it no row, so Localize defaults to `:specific`; ICU4X offers no automatic style at all.

## In progress

* [ ] **CLDR 49 upgrade** — the plan's items are closed bar those listed here; what remains is the beta2 refresh below. Work lives on the `cldr-49` branch, which does not merge to `main` until the final beta. [plans/cldr-49.md](plans/cldr-49.md).

## Blocked

* [ ] **Refresh to CLDR 49 beta2 and re-run the conformance suites** — blocked on the CLDR 49 beta2 release, expected 2026-10. It brings the `scope="core"` display-name fix (CLDR-19774, which missed beta1), `datetime.json` in the Clock12/Clock24 labels, and CLDR-19066's skeleton test data, vendored from CLDR `main` ahead of it.

* [ ] **Interval patterns inherited from a different locale level than the single date** — plan item 35: whether to glue or keep the inherited pattern. Blocked on CLDR-14207.

## Deferred

* [ ] **Recheck map-order selections that only today's data keeps deterministic** — seven lookups walk a map and never see two candidates in the current CLDR data; recheck them whenever it is regenerated. [plans/map-order.md](plans/map-order.md).

* [ ] **`localize_emoji` sibling library** — plan item 11, a separate package on its own schedule. A Phoenix LiveView picker (`localize_emoji_live`) is out of scope for its 0.1.0.

## Done

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
