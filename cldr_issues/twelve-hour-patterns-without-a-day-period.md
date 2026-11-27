# Twelve-hour patterns without a day period in fr_CM, bal_Latn and es_AR

TR35 (tr35-dates.md, "Time Data"): "Formats with 'h' or 'K' must also include a field with one of the day period pattern characters: 'a', 'b', or 'B'." Five Gregorian `availableFormats` have an `h` and no day period, so the times they write name two times each: "12:30" is half past midnight or half past noon, "1:45" a quarter to two in the morning or the afternoon.

## Data

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`, all in the Gregorian calendar:

* **`common/main/fr_CM.xml`, lines 51 to 53** — `h` "h", `hm` "h:mm", `hms` "h:mm:ss" (all `draft="contributed"`).

* **`common/main/bal_Latn.xml`, line 2490** — `hm` "h:mm"; its `hms` on line 2492, "h:mm:ss a", has the day period.

* **`common/main/es_AR.xml`, line 234** — `hms` "hh:mm:ss" (`draft="contributed"`).

## Suggested fix

Add the day period the locale's other twelve-hour formats use (`fr_CM`'s "h a", "h:mm a" and "h:mm:ss a"; `bal_Latn`'s "h:mm a"; `es_AR`'s "hh:mm:ss a"), or remove the items so they inherit.
