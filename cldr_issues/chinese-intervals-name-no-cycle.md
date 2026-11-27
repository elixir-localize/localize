# Chinese and Dangi interval formats write a year that names no sixty-year cycle

The date formats of the Chinese and Dangi calendars write the related Gregorian year, `r`, alone or beside the cyclic year's name, and their interval formats write the cyclic year's name `U` or the year's place in the cycle `y` and never `r`. So an interval at the skeleton of a date format is written with another kind of year than the date, and with a year that recurs every sixty years.

## Data

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`, `root.xml` and `en.xml`, the Chinese calendar, which the Dangi calendar aliases.

| Format | `root.xml` | `en.xml` |
|---|---|---|
| full date | "r(U) MMMM d, EEEE" (376) | "EEEE, MMMM d, r(U)" (1950) |
| long date | "r(U) MMMM d" (382) | "MMMM d, r(U)" (1956) |
| medium date | "r MMM d" (388) | "MMM d, r" (1962) |
| short date | "r-MM-dd" (394) | "M/d/r" (1968) |
| `y` | "r(U)" (487) | "r(U)" (2055) |
| `yyyyMMMd` | "r MMM d" (493) | "MMM d, r" (2061) |
| `y` interval, `y` | "U–U" (576) | "U – U" (2138) |
| `yMd` interval, `d`, `M`, `y` | "y-MM-dd – y-MM-dd" (583 to 585) | "M/d/y – M/d/y" (2145 to 2147) |
| `yMMM` interval, `y` | "U MMM – U MMM" (594) | "MMM U – MMM U" (2156) |
| `yMMMd` interval, `d` | "U MMM d–d" (597) | "MMM d – d, U" (2159) |
| `yMMMd` interval, `y` | "U MMM d – U MMM d" (599) | "MMM d, U – MMM d, U" (2161) |
| `yMMMEd` interval, `y` | "U MMM d, E – U MMM d, E" (604) | "E, MMM d, U – E, MMM d, U" (2166) |

No interval format of either locale has `r`.

## What goes wrong

The medium date's skeleton is `rMMMd`. TR35's interval algorithm finds the closest interval format as in `availableFormats`, where the year symbols are one field type, so it is `yMMMd`; and an adjustment "should never convert a numeric element in the pattern to an alphabetic element, or the opposite", so its `U` stays a name. 16 June 2026 is the second day of the fifth month of the year that began in 2026:

| | `en` |
|---|---|
| medium date | "Mo5 2, 2026" |
| medium interval, 16 to 20 June 2026 | "Mo5 2 – 6, bing-wu" |
| short date | "5/2/2026" |
| `yMd` interval, 16 to 20 June 2026 | "5/2/43 – 5/6/43" |
| `yMd` interval, 16 June 2026 to 12 June 2086 | "5/2/43 – 5/2/43" |

The interval's year is not the date's, and it is the same for 1966, 2026 and 2086: two dates sixty years apart are written alike, and an interval cannot be read back as the dates it was written from. ICU4C 78.3 does not match `rMMMd` to `yMMMd`, comparing the letters one for one, and writes both dates in full, "Mo5 2, 2026 – Mo5 6, 2026".

## Suggested fix

The interval formats of the Chinese and Dangi calendars with the year their date formats write: `r` where the date format of the same fields has `r` ("MMM d – d, r", "M/d/r – M/d/r") and `r(U)` where it has both. TR35 might also say whether the sixty-year cycle is a calendar field for the interval algorithm's greatest difference: ICU holds it as the era, and TR35 names no field for it.
