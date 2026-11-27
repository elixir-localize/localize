# Three interval patterns write their second date's fields in another order than their first's

Three interval patterns, in three locales, write the day and the month of their second date in the other order than their first's. Each looks like a slip of the keyboard.

All references are to CLDR `6198cae999ceb4847b25ddc0815835f07fced411`, `common/main`.

## The patterns

| Locale | Calendar | Item | Difference | Pattern |
|---|---|---|---|---|
| `syr` | generic | `MEd` | `d`, `M` | "E، d/M – E، M/d" |
| `hi_Latn` | gregorian | `GyMMMd` | `y` | "G y MMM d – y d MMM" |
| `tk` | generic | `GyMMMEd` | `d` | "G d MMM, E – MMM d, E y" |

`syr`'s `MEd` for a date alone is "EEEE، dd/MM", day first. So two Islamic dates of two years written at `MEd`, each whole about the fallback pattern as TR35's interval algorithm has them where the item has no pattern for a difference of the year, are "… 30/12 - … 04/01", and a reader that tries the item's pattern takes the second for the first day of the fourth month.

They were found by comparing, in each pattern, the order of the day and the month, the month and the year, and the day and the year in the first date with their order in the second.

Suggested: "E، d/M – E، d/M" for `syr`; "G y MMM d – y MMM d" for `hi_Latn`; "G d MMM, E – d MMM, E y" for `tk`.
