# Numeric skeletons whose field order contradicts the locale's standard date format

In six locales an `availableFormats` item and the standard date format for the same fields put the day and the month, or the day and the year, in opposite orders. Text one writes reads as the other, and since both readings are valid dates a parser cannot tell which was meant: "3/4/2024" is 4 March or 3 April. In a seventh the skeleton writes a year, a day and a month between hyphens, which is ISO 8601's shape with the day and the month exchanged.

## Data

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`:

* **`common/main/mt.xml`** — Gregorian short date "dd/MM/y" (line 1348), `yMd` "M/d/y" (line 1447).

* **`common/main/sbp.xml`** — Gregorian short date "dd/MM/y" (line 480), `yMd` "M/d/y" (line 528).

* **`common/main/vai_Latn.xml`** — Gregorian short date "dd/MM/y" (line 389), `yMd` "M/d/y" (line 437).

* **`common/main/ug.xml`** — Gregorian short date "y-MM-dd", inherited from root (line 1660), `yMd` "y-d-M" (line 1746) and `yMEd` "y-d-M، E" (line 1747). "2024-10-11" is 11 October by the first and 10 November by the second.

* **`common/main/kk_Arab.xml`** — Gregorian `yMd` "y-d-M" (line 2413) and `yMEd` "y-d-M، E" (line 2414), beside a short date of "dd-MM-y" (line 2288). The day precedes the month in both, but the skeleton's text has ISO 8601's shape, so "2024-10-11", written for 10 November, reads as 11 October wherever ISO 8601 is read.

* **`common/main/my.xml`** — generic short date "GGGGG d/M/y" (line 1240), `GyMd` "GGGGG y/M/d" (line 1311). In the Japanese calendar 1 June of Reiwa 5 (2023), written year first by `GyMd`, reads as the short date's 5 June of Reiwa 1 (2019).

* **`common/main/sa.xml`** — generic medium date "G d MMM y" (line 175), and `GyMMMd` "G y MMM d" inherited from root, which `sa` does not localize.

## Suggested fix

Give each locale's skeleton the field order of its standard format (`mt`, `sbp` and `vai_Latn`: `yMd` "d/M/y"; `ug`: `yMd` "y-M-d" and `yMEd` to match; `my`: `GyMd` "GGGGG d/M/y"; `sa`: a `GyMMMd` of "G d MMM y"), or the standard format the skeleton's order, whichever the locale uses. For `kk_Arab`, a `yMd` in the order of its short date, "d-M-y", or the year-month-day order its shape suggests.
