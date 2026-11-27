# kek's interval fallback pattern puts the later date first

`kek`, new in CLDR 49, has `{1} – {0}` for its Gregorian `intervalFormatFallback`, where every other locale and every other calendar of `kek` has `{0}` before `{1}`. TR35 makes that the order of every interval pattern of the locale: "{1} - {0}" means "the first part of the interval patterns in current locale are formatted with the end datetime".

## Data

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`:

* **`common/main/kek.xml`, line 830** — `<intervalFormatFallback>{1} – {0}</intervalFormatFallback>`, in the Gregorian calendar.

`kek`'s generic calendar inherits root's `{0} – {1}`. No locale's interval pattern has an `earliestFirst:` or `latestFirst:` prefix, so the fallback is the only statement of order in the data.

## What goes wrong

16 June 2026 to 20 August 2027, written with a pattern the locale has no interval item for, is "20/8/2027 – 16/6/2026", and a range of quarters "R3 2027 – R2 2026". By TR35's rule the locale's interval items are latest first as well: `yMd`'s "d/M/y – d/M/y" writes the same dates "20/8/2027 – 16/6/2026", `yMMMd`'s "d – d MMM, y" writes 16 to 20 June 2026 as "20 – 16 Xwaq Po, 2026", and `Hm` writes 10:00 to 14:30 as "14:30–10:00". ICU4C's `DateIntervalFormat` does the same when its `DateIntervalInfo` is given this fallback pattern ("Jun 20 – 16, 2026" for `en`), so ICU will write `kek`'s intervals this way once it takes CLDR 49's data.

## Suggested fix

`{0} – {1}`, as in `kek`'s generic calendar.
