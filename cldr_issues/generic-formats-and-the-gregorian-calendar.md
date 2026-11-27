# The generic calendar's date formats do not inherit from the Gregorian calendar's, as TR35 says they do

TR35 says the generic calendar's date format data inherits from the Gregorian calendar's. `root.xml` has no alias that makes it so, and the two readings give different answers for a skeleton the generic calendar has no format for.

## The specification

TR35 Dates, Calendar Elements (`docs/ldml/tr35-dates.md`, line 159 at CLDR `6198cae999ceb4847b25ddc0815835f07fced411`):

> Non-Gregorian calendars inherit standard time formats (in the `<timeFormats>` element) from the Gregorian calendar in the same locale. Most non-Gregorian calendars (other than Chinese and Dangi) inherit general date format data (in the `<dateFormats>` and `<dateTimeFormats>` elements) from the "generic" calendar format data in the same locale, which in turn inherits from Gregorian.

## The data

`common/main/root.xml` at the same commit:

| Calendar | Element | What `root.xml` has |
|---|---|---|
| Hebrew (and Buddhist, Coptic, Ethiopic, Indian, Islamic, Japanese, Persian, ROC) | `dateFormats` | an alias to the generic calendar's (1721) |
| Hebrew (and the rest) | `dateTimeFormats` | an alias to the generic calendar's (1727) |
| generic | `timeFormats` | an alias to the Gregorian calendar's (908) |
| generic | `dateFormats` | its own formats (881), and no alias |
| generic | `dateTimeFormats` | its own formats (910), with an alias for `numericSeparators` alone (912) |

So the first hop of the sentence is in the data and the second is not: an `availableFormats` item the Gregorian calendar has and the generic calendar lacks is not inherited.

## What differs

The Gregorian calendar has `yw` ("'week' w 'of' Y" in `en`) and `MMMMW`, and the generic calendar has neither. For 16 June 2026 as a Hebrew date, 1 Tamuz 5786, in `en`:

| Skeleton | With the inheritance TR35 states | With the data as it is (ICU4C 78.3) |
|---|---|---|
| `yw` | "week 39 of 5786" | "5786 (week: 39)" |
| `Yw` | "week 39 of 5786" | "39 5786 AM" |
| `MMMMW` | "week 1 of Tamuz" | "1 (month: Tamuz)" |
| `yMMMdw` | "1 Tamuz 5786 (week: 39)" | "1 Tamuz 5786 (week: 39)" |

The same sentence sits oddly beside TR35's rule for calendars whose year needs an era ("If a client requests a format string containing a year, and all the availableFormats patterns with a year also contain an era, then include the era as part of the result"): were the Gregorian calendar's formats inherited item by item, a Japanese date would have formats with a year and no era among its own.

## Suggested fix

One of two, as CLDR means it:

* **The data** — aliases in `root.xml` from the generic calendar's week formats to the Gregorian calendar's, or `yw` and `MMMMW` items of the generic calendar's own, with its era where the year needs one.

* **The specification** — the sentence without "which in turn inherits from Gregorian" for `dateFormats` and `dateTimeFormats`, saying instead which elements of the generic calendar the Gregorian calendar supplies (`timeFormats`, `days`, `quarters`, `dayPeriods`, `dayOfMonths`, `numericSeparators`).
