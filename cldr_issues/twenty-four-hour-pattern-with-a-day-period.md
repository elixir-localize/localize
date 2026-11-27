# A 24-hour pattern with a day period in ksh

TR35 (tr35-dates.md, "Elements availableFormats, appendItems"): "Patterns for 24-hour-cycle time formats (using H or k) and skeletons (using H) currently _should not_ include fields with day period characters (a, b, or B)". `ksh`'s `Hmsv` has both, so it writes 16:05:09 in Kolkata as "16:05:09 n.M. Zick vun Indije", an hour of the 24-hour clock followed by "after noon"; ICU4C 78.3 writes the same.

It is the only 24-hour pattern with a day period in the time formats, available formats and interval formats of any locale, in any calendar.

## Data

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`:

* **`common/main/ksh.xml`, line 888 (generic calendar) and line 1198 (Gregorian calendar)** — `<dateFormatItem id="Hmsv" draft="contributed">H:mm:ss a v</dateFormatItem>`, the space before `a` a narrow no-break space (U+202F).

The item beside it is the 12-hour one, `hmsv` "h:mm:ss a v" (lines 887 and 1197), and the locale's other 24-hour items have no day period: `Hms` "H:mm:ss" (lines 886 and 1196), `Hmv` "HH:mm v".

## Why it matters to a parser

TR35's "Parsing Day Periods" has the day period "checked for consistency with the hour". Text that `hmsv` writes for four in the afternoon, "4:00:00 n.M. …", is also in the shape of `Hmsv`, whose 24-hour hour 4 is four in the morning. ICU4C 78.3 reads "4:00 PM" with the pattern `H:mm a` as 12:00, lenient or not, and "16:00 AM" as 00:00.

## Suggested fix

Remove the day period, leaving `Hmsv` "H:mm:ss v" as `Hms` is "H:mm:ss", or remove the item so that it inherits root's "HH:mm:ss v".
