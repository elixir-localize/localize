# Date formats that write the week-based year

Thirteen `dateFormatItem`s and two standard date formats, in twelve locales, write the week-based year `Y` where the skeleton names the calendar year `y` and every sibling format writes it. The last days of December then carry the next year's number, and a calendar that counts its years from an era writes a year that is not the era's.

The list is every such format in `common/main`: each locale's `availableFormats` and standard date formats in every calendar were searched for a `Y` in a pattern whose skeleton has no week field.

## Data

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`.

In `availableFormats`:

| File and line | Calendar | Skeleton | Pattern |
|---|---|---|---|
| `de.xml` 3134 | gregorian | `GyMMMMEd` | `d MMMM Y G, E` |
| `de_CH.xml` 2025 | gregorian | `GyMEd` | `E, MM.dd.Y G` |
| `gd.xml` 3338 | gregorian | `yMMM` | `LLL Y` |
| `ki.xml` 661 | gregorian | `yMMMd` | `dd-MM-YYYY` |
| `ki.xml` 664 | gregorian | `yMMMMd` | `dd-MM-YYYY` |
| `ki.xml` 665 | gregorian | `yMMMMEd` | `dd-MM-YYYY E` |
| `ksh.xml` 897 | generic | `yM` | `Y-MM` |
| `ksh.xml` 1207 | gregorian | `yM` | `Y-MM` |
| `my.xml` 1336 | generic | `yyyyMd` | `GGGGG dd/MM/Y` |
| `oc.xml` 1230 | gregorian | `GyMd` | `dd/MM/Y G` |
| `pt.xml` 2564 | gregorian | `GyMMMM` | `MMMM 'de' Y G` |
| `sc.xml` 5185 | gregorian | `yM` | `MM/Y` |
| `te.xml` 1812 | generic | `yyyyMMMM` | `MMMM YYYY` |

In the standard date formats, both in the generic calendar:

| File and line | Length | Pattern | `datetimeSkeleton` |
|---|---|---|---|
| `gl.xml` 1207 | full | `EEEE, d 'de' MMMM 'de' Y G` | `GYMMMMEEEEd` |
| `kek.xml` 187 | short | `dd/MM/Y G` | none |

`de`'s format is inherited by `de_AT`, `de_BE`, `de_CH`, `de_IT`, `de_LI` and `de_LU`. `oc`'s is `draft="unconfirmed"`. `de_CH`'s `GyMEd` also writes the month before the day, "MM.dd", where `de`'s is "E, dd.MM.y G".

## What goes wrong

29 December 2025 is a Monday in the first week of the week-based year 2026, and 31 December 2024 is in the first week of 2025:

| Locale | Skeleton | Date | Written |
|---|---|---|---|
| `de` | `GyMMMMEd` | 29 December 2025 | "29 Dezember 2026 n. Chr., Mo." |
| `de_CH` | `GyMEd` | 29 December 2025 | "Mo., 12.29.2026 n. Chr." |
| `gd` | `yMMM` | 31 December 2024 | "Dùbh 2025" |
| `ki` | `yMMMd` | 29 December 2025 | "29-12-2026" |
| `ksh` | `yM` | 29 December 2025 | "2026-12" |
| `pt` | `GyMMMM` | 29 December 2025 | "dezembro de 2026 d.C." |
| `sc` | `yM` | 29 December 2025 | "12/2026" |

The generic calendar's formats are every other calendar's, so `my`, `te`, `ksh`, `gl` and `kek` write a week-based year beside an era in the Japanese, Buddhist and Islamic calendars. In the Japanese calendar 22 November 2023, which is Reiwa 5, is written by `my`'s `yyyyMd` (and by `yMd`, which matches it) as the era, the day, the month and the week-based year 2023, "R 22/11/2023" in Latin digits, where `GyMd` writes the year of the era, "R 5/11/22". Text written so does not read back as the date it was written from.

A month and year is a calendar month of a calendar year, and a year, month and day a calendar day; the skeletons name `y`, and the patterns should too.

## Suggested fix

Each pattern with `y` for its `Y` (and `YYYY`), and `gl`'s `datetimeSkeleton` `GyMMMMEEEEd`:

* **`de`** — `GyMMMMEd` "d MMMM y G, E".

* **`de_CH`** — `GyMEd` "E, dd.MM.y G".

* **`gd`** — `yMMM` "LLL y", as `yMMMM` already is.

* **`ki`** — "dd-MM-y" and "dd-MM-y E"; a format with a named month for `yMMMd`, `yMMMMd` and `yMMMMEd` is the locale's to choose.

* **`ksh`** — `yM` "y-MM" in both calendars.

* **`my`** — generic `yyyyMd` "GGGGG dd/MM/y".

* **`oc`** — `GyMd` "dd/MM/y G".

* **`pt`** — `GyMMMM` "MMMM 'de' y G".

* **`sc`** — `yM` "MM/y".

* **`te`** — generic `yyyyMMMM` "MMMM y".

* **`gl`** — generic full "EEEE, d 'de' MMMM 'de' y G".

* **`kek`** — generic short "dd/MM/y G".
