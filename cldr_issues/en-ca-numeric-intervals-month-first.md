# en_CA's numeric interval formats are month-first

`en_CA`'s Gregorian numeric dates are year-month-day, with a day-month-year variant, but its numeric interval formats write the month before the day, an order neither its default nor its variant has. A date range is then written in another order than either of its dates is written alone.

## Data

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`, `common/main/en_CA.xml`, Gregorian calendar.

The date formats:

| Line | Item | Default | `alt="variant"` |
|---|---|---|---|
| 2182 | short `dateFormat` | `y-MM-dd` | `d/M/yy` |
| 2300 | `Md` | `MM-dd` | `d/M` |
| 2302 | `MEd` | `E, MM-dd` | `E, d/M` |
| 2319 | `yM` | `y-MM` | none |
| 2320 | `yMd` | `y-MM-dd` | `d/M/y` |
| 2322 | `yMEd` | `E, y-MM-dd` | `E, d/M/y` |

The interval formats:

| Lines | Item | Default | `alt="variant"` |
|---|---|---|---|
| 2441 to 2446 | `Md` | `M/d–M/d` | `d/M – d/M` |
| 2447 to 2452 | `MEd` | `E, M/d–E, M/d` | `E, d/M – E, d/M` |
| 2471 to 2474 | `yM` | `M/y–M/y` | none |
| 2475 to 2482 | `yMd` | `M/d/y–M/d/y` | `d/M/y – d/M/y` |
| 2483 to 2490 | `yMEd` | `E, M/d/y–E, M/d/y` | `E, d/M/y – E, d/M/y` |

The variants agree, day first in both. The defaults do not: a date is `y-MM-dd` and an interval `M/d/y–M/d/y`. The same items in `en_CA`'s Chinese calendar are consistent, `MM-dd – MM-dd` and `y-MM-dd – y-MM-dd`. The data is the same in CLDR 48.

## What goes wrong

16 to 20 June 2026 at the skeleton `yMd`:

* **The date alone** — "2026-06-16".

* **The interval** — "6/16/2026–6/20/2026", in ICU4C 78.3 as well.

6 May to 8 July 2026 is "5/6/2026–7/8/2026", which read day first, as the variant writes a date, is 5 June to 7 August. The default interval also has no space beside its dash where the variant and `en`'s have a thin space.

## Suggested fix

The interval defaults in the order of the dates:

* **`Md`** — `MM-dd – MM-dd`.

* **`MEd`** — `E, MM-dd – E, MM-dd`.

* **`yM`** — `y-MM – y-MM`.

* **`yMd`** — `y-MM-dd – y-MM-dd`.

* **`yMEd`** — `E, y-MM-dd – E, y-MM-dd`.
