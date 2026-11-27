# `GyMd` formats in another order than the locale's numeric dates

In `af`, `am`, `fa` and `ga` the generic calendar's `GyMd` writes the month before the day and the year last, as English does, beside numeric dates of the same calendar in the locale's own order. The same contradiction reaches other locales by inheritance.

## Data

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`, all in the generic calendar:

| Locale | `GyMd` | `yyyyMd` | Short date |
|---|---|---|---|
| `af` (`af.xml`, line 1315) | "M-d-y G" | "d/M/y GGGGG" | "y-MM-dd G" |
| `am` (`am.xml`, line 1945) | "M/d/y GGGGG" | "G y/MM/dd" | "dd/MM/y GGGGG" |
| `fa` (`fa.xml`, line 1756) | "M/d/y GGGGG" | "y/M/d GGGGG" | "y/M/d GGGGG" |
| `ga` (`ga.xml`, line 1716) | "M/d/y G" | "dd/MM/y GGGGG" | "dd/MM/y GGGGG" |

Each locale's Gregorian `GyMd` is in its own order: `af`'s "y-MM-dd G", `am`'s "d/M/y GGGGG", `fa`'s "y/M/d GGGGG" and `ga`'s "dd/MM/y GGGGG".

By inheritance: `en_AE` has "M/d/y G" beside its own "dd/MM/y"; `es_PA` and `es_PR` have "d/M/y GGGGG" beside their own "MM/dd/y"; `en_SE` and `en_ZA` have "dd/MM/y G" beside their own "y-MM-dd" and "y/MM/dd".

## What goes wrong

7 January of the Buddhist year 2569 is "1-7-2569 BE" at `GyMd` in `af` and "7/1/2569 BE" at `yyyyMd`; in `ga` "1/7/2569 RB" beside "07/01/2569 RB"; in `am` "1/7/2569 BE" beside its short date "07/01/2569 BE". A reader of the locale takes the `GyMd` text for 1 July. In `fa` the same date is "۱/۷/۲۵۶۹" at `GyMd` and "۲۵۶۹/۱/۷" in every other numeric format.

## Suggested fix

`GyMd` in the order of each locale's numeric date: "d-M-y G" or "y-MM-dd G" for `af`, "d/M/y GGGGG" for `am`, "y/M/d GGGGG" for `fa` and "dd/MM/y GGGGG" for `ga`, and a `GyMd` of their own for `en_AE`, `es_PA`, `es_PR`, `en_SE` and `en_ZA`.
