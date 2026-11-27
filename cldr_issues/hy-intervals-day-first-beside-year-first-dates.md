# `hy` date intervals are day-first beside the year-first dates CLDR 49 gave it

CLDR 49's Survey Tool import (CLDR-19616) changed Armenian's Gregorian dates from day-first to year-first, and its `yMMMd` and `yMMMEd` interval formats were left day-first. Three of its interval patterns also write the year's abbreviation with two different marks in the one pattern.

## Data

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`, `hy.xml`, the Gregorian calendar. Commit `03725842ae` changed the long date from "dd MMMM, y թ." to "y թ. MMMM d", the medium from "dd MMM, y թ." to "y թ. MMM d", and `yMMMd` from "d MMM, y թ." to "y թ. MMM d".

| Format | Pattern | Order |
|---|---|---|
| medium date (line 1819) | "y թ. MMM d" | year first |
| `yMMMd` (1958) | "y թ. MMM d" | year first |
| `yMMMEd` (1959) | "y թ. MMM d, E" | year first |
| `GyMMMd` interval, `d` (2021) | "G y թ. MMM dd–dd" | year first |
| `yMMM` interval, `M` (2108) | "y թ. MMM – MMM" | year first |
| `yMMMd` interval, `d` (2112) | "dd–dd MMM, y թ." | day first |
| `yMMMd` interval, `M` (2113) | "dd MMM – dd MMM, y թ." | day first |
| `yMMMd` interval, `y` (2114) | "dd MMM, y թ․ – dd MMM, y թ." | day first |
| `yMMMEd` interval, `d` and `M` (2117, 2118) | "E, d MMM – E, d MMM, y թ." | day first |
| `yMMMEd` interval, `y` (2119) | "E, d MMM, y – E, d MMM, y թ." | day first |

The year's abbreviation is "թ." with a full stop in 27 of the Gregorian calendar's patterns, the standard formats among them, and "թ․" with U+2024 ONE DOT LEADER in 17 (`y`, `yMMMM`, `yMMMMd`, `GyMMMd` and others). Three patterns have one of each: lines 2022 and 2024, "G y թ․ MMM dd – G y թ. MMM dd", and line 2114 above.

## What goes wrong

16 June 2026 is "2026 թ. հնս 16", and 16 to 20 June 2026 at the same format is "16–20 հնս, 2026 թ.". 16 June 2026 to 20 August 2027 is "16 հնս, 2026 թ․ – 20 օգս, 2027 թ.", the first year followed by a one-dot leader and the second by a full stop. The wide month's date, "2026 թ․ հունիսի 16", has the leader where the long date, "2026 թ. հունիսի 16", has the full stop.

## Suggested fix

The `yMMMd` and `yMMMEd` interval formats in the order of the dates: "y թ. MMM d–d", "y թ. MMM d – MMM d" and "y թ. MMM d – y թ. MMM d", and the same with the weekday. One mark after "թ" throughout, whichever the Armenian vetters prefer.
