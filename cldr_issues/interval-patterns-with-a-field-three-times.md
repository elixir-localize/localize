# Ten interval patterns write a field three times

An interval pattern writes each field of its skeleton once or twice: once where the two dates share it, twice where they differ in it. Ten patterns in eight locales write a field a third time, so one of the two dates is written with a field doubled, or with a field of the other date's. Each looks like a slip of the keyboard.

All references are to CLDR `6198cae999ceb4847b25ddc0815835f07fced411`, `common/main`.

## The patterns

| Locale | Calendar | Item | Difference | Pattern | The field |
|---|---|---|---|---|---|
| `sv` | generic | `GyMMMd` | `y` | "d MMM y G – d MMM d y" | `d`, and no era in the second date |
| `qu` | gregorian | `GyMMMEd` | `M` | "E, d MMM d – E, d MMM y G" | `d`, where the first date's year and era should be |
| `pap` | gregorian | `GyMMMd` | `G` | "d y MMM y G – d MMM y G" | `y` |
| `tr` | generic | `GyMMM` | `G` | "G MMM y G – G MMM y" | `G` |
| `frr` | gregorian | `GyMMMEd` | `G` | "G E, d. MMM y – G E, d. MMM yE" | `E` |
| `yo`, `yo_BJ` | gregorian | `yMEd` | `d` | "E, dd/MM/y – E, dd/MM/y, E" | `E` |
| `en_JP` | generic | `GyMEd` | `d`, `y` | "GGGGG y/MM/dd, E – E, y/MM/dd, E" | `E` |
| `en_JP` | japanese | `yMMMEd` | `d` | "y MMM d, E – E, MMM d, E" | `E` |

## What they write

For 28 December 2026 to 3 January 2027 as Buddhist dates in `sv`, at the medium format (`GyMMMd`):

> 28 dec. 2569 BE – 3 jan. 3 2570

where the item's other patterns write "d MMM y G" for a date. The text cannot be read back as two dates.

## How they were found

Each pattern's fields were counted outside its quoted text, a field being a run of one letter: a letter with three runs or more is in the table. No other pattern of any locale has one.

## Suggested fix

Each pattern as its item's other patterns have a date:

| Locale | Item | Difference | Suggested |
|---|---|---|---|
| `sv` | generic `GyMMMd` | `y` | "d MMM y G – d MMM y G" |
| `qu` | gregorian `GyMMMEd` | `M` | "E, d MMM – E, d MMM y G" |
| `pap` | gregorian `GyMMMd` | `G` | "d MMM y G – d MMM y G" |
| `tr` | generic `GyMMM` | `G` | "G MMM y – G MMM y" |
| `frr` | gregorian `GyMMMEd` | `G` | "G E, d. MMM y – G E, d. MMM y" |
| `yo`, `yo_BJ` | gregorian `yMEd` | `d` | "E, dd/MM/y – E, dd/MM/y" |
| `en_JP` | generic `GyMEd` | `d`, `y` | "GGGGG y/MM/dd, E – y/MM/dd, E" |
| `en_JP` | japanese `yMMMEd` | `d` | "y MMM d, E – MMM d, E" |
