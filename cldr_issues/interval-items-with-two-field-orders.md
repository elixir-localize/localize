# Interval items whose patterns order the year, month and day differently

In 57 locales an `intervalFormatItem` writes its fields in one order for some `greatestDifference` values and in another for the rest: 65 items of the Gregorian calendar in 38 locales and 45 of the generic calendar in 31. Some are items where a locale gives some of the differences and leaves the others as `↑↑↑`, so root's year-first pattern stands beside the locale's own (`zu`, `ha`); others are a locale's own patterns disagreeing (`sv`).

## Data

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`, as resolved:

| Locale | Calendar | Item | One difference | Another |
|---|---|---|---|---|
| `zu` | gregorian | `yMMMd` | `d`: "y MMM d–d" | `y`: "MMM d, y – MMM d, y" |
| `zu` | gregorian | `yMEd` | `d`: "y-MM-dd, E – y-MM-dd, E" | `y`: "E, M/d/y – E, M/d/y" |
| `ha` | gregorian | `yMd` | `y`: "y-MM-dd – y-MM-dd" | `d`: "dd/MM/y – dd/MM/y" |
| `am` | gregorian | `GyMd` | `M`: "G y-MM-dd – y-MM-dd" | `y`: "GGGGG d/M/y – d/M/y" |
| `sv` | generic | `GyMd` | `y`: "y-MM-dd – y-MM-dd GGGGG" | `d`: "d/M/y–d/M/y GGGGG" |
| `sv` | generic | `GyMEd` | `d`: "E y-MM-dd – E y-MM-dd GGGGG" | `y`: "E d/M y – E d/M y GGGGG" |
| `he` | generic | `GyMd` | `d`: "G y-MM-dd – y-MM-dd" | `y`: "d.M.y – d.M.y GGGGG" |
| `cy` | generic | `GyMMMd` | `d`: "MMM d – d, y G" | `y`: "d MMM y – d MMM y G" |
| `de_CH` | gregorian | `MMMMd` | `d`: "MMMM d.–d." | `M`: "d. MMMM – d. MMMM" |
| `lv` | gregorian | `MMMMd` | `d`: "MMMM d–d" | `M`: "d. MMMM – d. MMMM" |

* **`common/main/zu.xml`, lines 1996 to 2000** — the Gregorian `yMMMd` item, its `d` left as `↑↑↑` beside "MMM d – MMM d, y" and "MMM d, y – MMM d, y".

* **`common/main/ha.xml`, lines 1955 to 1959** — the Gregorian `yMd` item, "dd/MM/y – dd/MM/y" for `d` and `M` and `↑↑↑` for `y`.

* **`common/main/sv.xml`, lines 2586 to 2591** — the generic `GyMd` item, all four of its patterns the locale's own.

The locales, with the number of items in each: Gregorian — `am` 2, `as` 1, `az_Cyrl` 1, `ba` 1, `brx` 3, `bs` 1, `bua` 1, `de_CH` 1, `en_CA` 4, `gu` 1, `ha` 4, `ig` 1, `kn` 5, `kok` 1, `ky` 2, `lv` 1, `mr` 1, `mt` 1, `om` 1, `ps` 2, `sah` 1, `so` 1, `te` 1, `tg` 1, `wae` 1, `yi` 1, `yo` 3, `zu` 2, and the locales that inherit from them; generic — `be` 1, `brx` 2, `bs` 1, `ckb` 2, `cy` 2, `en_CA` 4, `gu` 1, `he` 1, `hy` 1, `kn` 1, `kok` 1, `lld` 1, `lo` 2, `si` 1, `sv` 2, `sw` 1, `te` 1, `tg` 1, `wae` 1, `yo` 1, `zu` 4, and theirs. `en_CA`'s four are the subject of the report on its month-first numeric intervals.

## What goes wrong

A range reads one way until its dates are a month or a year apart and then turns round. `ha`'s short interval writes 16 to 20 June 2026 as "16/06/26 – 20/06/26" and 16 June 2026 to 20 August 2027 as "26-06-16 – 27-08-20", which is as easily 26 June 2016 to 27 August 2020. `zu` writes "2026 Jun 16–20" beside "Jun 16 – Aga 20, 2026", `de_CH` "Juni 16.–20." beside "16. Juni – 20. August", and `am` "16/6/2026 – 20/6/2026" beside "2026-06-16 – 2026-08-20".

## Suggested fix

Where a locale gives any `greatestDifference` of an item, give them all, in the order its dates are written. A Survey Tool check that the patterns of one item order their fields alike would find these.
