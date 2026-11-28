# CLDR issues

Drafts for the CLDR issue tracker ([unicode-org.atlassian.net, project CLDR](https://unicode-org.atlassian.net/jira/software/c/projects/CLDR/issues)), one issue per file, found in Localize's work on CLDR 49. They are in priority order: wrong output a reader sees, in widely used locales, first; then regressions CLDR 49 made; then clear data fixes; then questions about the specification, which need discussion and are best raised one at a time.

File two or three at a time, and wait for the maintainers to respond before filing more. When one is filed, move it to `## Filed` with its ticket number and the date, and remove the "Blocked on the user filing" line from the `TODO.md` item it unblocks.

## To file

1. **[collation-parents-nb-nn.md](collation-parents-nb-nn.md)** — `nb` and `nn` are missing from the `collations` component of `parentLocales`, so read by TR35 they take the root's collation, not Norwegian. A one-line data fix; Localize carries a marked correction until it lands. Data.

2. **[week-based-year-in-month-year-formats.md](week-based-year-in-month-year-formats.md)** — fifteen date formats in twelve locales write the week-based year `Y` for the calendar year, so `de`'s `GyMMMMEd` writes 29 December 2025 as "29 Dezember 2026". Data.

3. **[en-ca-numeric-intervals-month-first.md](en-ca-numeric-intervals-month-first.md)** — `en_CA`'s numeric intervals are month-first, "6/16/2026–6/20/2026", beside its dates, "2026-06-16". Data.

4. **[interval-patterns-with-the-differing-field-once.md](interval-patterns-with-the-differing-field-once.md)** — twenty-two interval patterns in eighteen locales write the field of their greatest difference once: `sw` writes 16 June to 20 August 2026 as "16 – 20 Ago 2026", `ru` 10:30 to 14:30 as "10:30 — 02:30". Data.

5. **[hy-intervals-day-first-beside-year-first-dates.md](hy-intervals-day-first-beside-year-first-dates.md)** — CLDR 49 made Armenian's dates year-first and left its intervals day-first. A CLDR 49 regression. Data.

6. **[date-skeletons-not-derived-from-their-patterns.md](date-skeletons-not-derived-from-their-patterns.md)** — in 75 locales a standard date format's `datetimeSkeleton` is not its pattern's; `id` and `te` changed their patterns in CLDR 49 and kept the old skeletons. Data.

7. **[twelve-hour-patterns-without-a-day-period.md](twelve-hour-patterns-without-a-day-period.md)** — `fr_CM`, `bal_Latn` and `es_AR` have 12-hour patterns with no day period, which TR35 forbids, so "12:30" names two times. Data.

8. **[rbnf-ru-plural-ordinal-latin-e.md](rbnf-ru-plural-ordinal-latin-e.md)** — two Russian plural ordinals end in a Latin "e" where a Cyrillic "е" belongs. A one-character fix in the same file as CLDR-19933; file it next, or add it to that ticket. Data.

9. **[interval-patterns-with-a-field-three-times.md](interval-patterns-with-a-field-three-times.md)** — ten interval patterns in eight locales write a field a third time, so `sv`'s Buddhist interval across a year is "28 dec. 2569 BE – 3 jan. 3 2570". Data.

10. **[interval-patterns-with-a-date-missing-or-doubling-a-field.md](interval-patterns-with-a-date-missing-or-doubling-a-field.md)** — interval patterns whose date lacks a field the other has (`en_JP`, `hy`, `pcm`); its doubled fields repeat item 9, so file the three that lack one with it. Data.

11. **[interval-patterns-whose-two-dates-order-their-fields-differently.md](interval-patterns-whose-two-dates-order-their-fields-differently.md)** — three interval patterns, in `syr`, `hi_Latn` and `tk`, write their second date's day and month in the other order than their first's. Data.

12. **[interval-items-with-two-field-orders.md](interval-items-with-two-field-orders.md)** — in 57 locales an interval item orders its year, month and day one way for some differences and another for the rest. Data.

13. **[gymd-against-the-numeric-date.md](gymd-against-the-numeric-date.md)** — `af`, `am`, `fa` and `ga`'s generic `GyMd` is month-first beside numeric dates in the locale's own order. Data.

14. **[skeletons-against-the-standard-formats.md](skeletons-against-the-standard-formats.md)** — six locales give a numeric skeleton the opposite field order to their standard date format, and `kk_Arab`'s `yMd` exchanges the day and the month. Data.

15. **[kek-interval-fallback-latest-first.md](kek-interval-fallback-latest-first.md)** — `kek`'s interval fallback pattern is "{1} – {0}", the later date first, the only one in any locale. Data.

16. **[twenty-four-hour-pattern-with-a-day-period.md](twenty-four-hour-pattern-with-a-day-period.md)** — `ksh`'s `Hmsv` is a 24-hour pattern with a day period, the only one in any locale. Data.

17. **[chinese-intervals-name-no-cycle.md](chinese-intervals-name-no-cycle.md)** — the Chinese and Dangi interval formats write a year that names no sixty-year cycle, so two dates sixty years apart are written alike. Data, with a question for the specification.

18. **[generic-formats-and-the-gregorian-calendar.md](generic-formats-and-the-gregorian-calendar.md)** — TR35 says the generic calendar's formats inherit the Gregorian calendar's, and `root.xml` does not make it so. Data or specification.

19. **[compact-number-steps-against-the-test-data.md](compact-number-steps-against-the-test-data.md)** — TR35's compact-number steps give other results than CLDR's test data (generated from ICU): "1000K" where it has "1M". Specification.

20. **[rbnf-optional-text-against-the-test-data.md](rbnf-optional-text-against-the-test-data.md)** — TR35's rule for RBNF's optional text omits it where CLDR's test data writes it: Afrikaans 1100 is "elf honderd nul". Specification.

21. **[location-format-of-a-non-location-zone.md](location-format-of-a-non-location-zone.md)** — TR35 gives two answers for the location format of a zone with no region, such as `PST8PDT`. Specification.

22. **[auto-time-zone-style.md](auto-time-zone-style.md)** — TR35's default zone style, Auto, has no row in its mapping table. Specification.

23. **[rbnf-roll-back-with-one-substitution.md](rbnf-roll-back-with-one-substitution.md)** — TR35 rolls back from an RBNF rule with two substitutions, ICU from one with one; no CLDR 49 data tells them apart. Specification, for the record.

## Filed

* **[CLDR-19933](https://unicode-org.atlassian.net/browse/CLDR-19933)** — [rbnf-ru-digits-ordinal-no-suffix.md](rbnf-ru-digits-ordinal-no-suffix.md): Russian `%digits-ordinal` writes 3 as "3". Filed 2026-11-28.
