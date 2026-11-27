# Malformed interval patterns

An `intervalFormatItem`'s `greatestDifference` pattern is used when the two dates differ in that field, so it has to write the field twice. Twenty-two patterns in eighteen locales write it once: a range across two months names one month, a range across noon has one day period or none, and a range across two eras names one era.

The list is every such pattern in `common/main`: each locale's interval patterns in every calendar were searched for a `greatestDifference` whose own field (the month for `M`, the day period for `a`, the era for `G`) appears fewer than twice.

## Data

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`.

A month difference with one month:

| File and line | Calendar | Item | Pattern for `M` |
|---|---|---|---|
| `sw.xml` 2292 | gregorian | `yMMMd` | `d – d MMM y` |
| `rw.xml` 691 | gregorian | `yMMMd` | `d – d MMM y` |
| `wae.xml` 768 | generic | `MMMd` | `d. – d. MMM` |
| `wae.xml` 1149 | gregorian | `MMMd` | `d. – d. MMM` |
| `th.xml` 1716 | buddhist | `MEd` | `E d – E d/M` |
| `rm.xml` 1522 | generic | `GyMd` | `dd – dd-MM-y G` |

A day-period difference with one day period, or none:

| File and line | Calendar | Item | Pattern for `a` |
|---|---|---|---|
| `ru.xml` 2699 | gregorian | `hm` | `hh:mm — hh:mm` |
| `ta.xml` 1888 | generic | `hmv` | `h:mm – h:mm a v` |

An era difference with one era:

| File and line | Calendar | Item | Pattern for `G` |
|---|---|---|---|
| `az.xml` 2150 | gregorian | `GyMMMEd` | `G E, d MMM y – E, d MMM y` |
| `ca.xml` 2085 | generic | `GyMMMd` | `d MMM, y – d MMM, y G` |
| `fi.xml` 2223 | generic | `GyMMMEd` | `E d.M.y – E d.M.y G` |
| `fi.xml` 2872 | gregorian | `GyMMMEd` | `E d.M.y – E d.M.y G` |
| `hr.xml` 1808 | generic | `GyMd` | `d. M. y. – d. M. y. GGGGG` |
| `it.xml` 1783 | generic | `GyMEd` | `E, d/M/y – E, d/M/y GGGGG` |
| `ko.xml` 2700 | generic | `GyMMMd` | `G y년 M월 d일~y년 M월 d일` |
| `lij.xml` 1844 | gregorian | `GyMEd` | `E d/M/y – E d/M/y G` |
| `lld.xml` 885 | generic | `GyMEd` | `E, d.M.y – E, d.M.y G` |
| `lld.xml` 1424 | gregorian | `GyMEd` | `E, d.M.y – E, d.M.y GGGGG` |
| `pcm.xml` 1849 | gregorian | `GyMEd` | `GGGGG y-MM-dd, E – y-MM-dd, E` |
| `scn.xml` 1450 | gregorian | `GyMMM` | `MMM y – MMM y G` |
| `yue.xml` 3228 | gregorian | `GyM` | `GGGGGy年M月至y年M月` |
| `yue.xml` 3234 | gregorian | `GyMd` | `GGGGGy年M月dd日y年M月dd日` |

`sw`'s pattern is inherited by `sw_CD`, `sw_KE` and `sw_UG`, `ru`'s by its regional locales, `ta`'s by `ta_LK`, `ta_MY` and `ta_SG` and by its Gregorian calendar, and the generic calendar's by every calendar without patterns of its own. `fr_CM`'s `h`, `hm`, `hmv` and `hv` have no day period either; they are in the report of 12-hour patterns without a day period. `yue`'s `GyMd` also has no separator between its two dates.

## What goes wrong

16 June to 20 August 2026:

| Locale | Skeleton | Written | In ICU4C 78.3 |
|---|---|---|---|
| `sw` | `yMMMd` | "16 – 20 Ago 2026" | "16 – 20 Ago 2026" |
| `rw` | `yMMMd` | "16 – 20 Kan. 2026" | "16 Kam. – 20 Kan. 2026" (CLDR 48) |
| `wae` | `MMMd` | "16. – 20. Öig" | |

Each reads as five days of August. 10:30 to 14:30 at `ru`'s `hm` is "10:30 — 02:30", which reads as a range ending in the night.

## Suggested fix

The differing field in both halves, as each locale's pattern for the next greater difference already has it:

* **`sw`, `rw`** — `yMMMd` for `M`: `d MMM – d MMM y`.

* **`wae`** — `MMMd` for `M`: `d. MMM – d. MMM`.

* **`th`** — Buddhist `MEd` for `M`: `E d/M – E d/M`.

* **`rm`** — generic `GyMd` for `M`: `dd-MM – dd-MM-y G`.

* **`ru`** — `hm` for `a`: `hh:mm a — hh:mm a`.

* **`ta`** — generic `hmv` for `a`: `h:mm a – h:mm a v`.

* **The era patterns** — the era beside each year, in the order the locale writes a date with its era.
