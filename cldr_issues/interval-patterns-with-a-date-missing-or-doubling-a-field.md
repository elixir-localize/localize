# Interval patterns whose dates lack a field the other has, or hold one twice

In an interval pattern each date writes the fields of the skeleton, the shared ones once and the differing ones in both. Ten patterns in seven locales have a date that lacks a field the other date has, or holds one twice. The list is every such pattern in `common/main`: each locale's interval patterns in every calendar were searched for a date that holds a field twice or lacks one the other date has.

All references are to CLDR `6198cae999ceb4847b25ddc0815835f07fced411`, `common/main`.

The patterns here that hold a field twice, in `en_JP`, `qu`, `sv`, `tr` and `yo`, are also in `interval-patterns-with-a-field-three-times.md`, so file them in one ticket or the other; the three that lack a field, in `en_JP`, `hy` and `pcm`, are in this report alone.

## Data

| File and line | Calendar | Item | Pattern | Fault |
|---|---|---|---|---|
| `en_JP.xml` 123 and 126 | generic | `GyMEd` for `d` and `y` | `GGGGG y/MM/dd, E – E, y/MM/dd, E` | The second date has its weekday twice. |
| `en_JP.xml` 610 | japanese | `GyMMMd` for `y` | `G y MMM d – y MMM` | The second date has no day. |
| `en_JP.xml` 699 | japanese | `yMMMEd` for `d` | `y MMM d, E – E, MMM d, E` | The second date has its weekday twice. |
| `hy.xml` 2028 | gregorian | `GyMMMEd` for `G` | `G y թ. MMM d E – G MMM d E` | The second date has no year. |
| `pcm.xml` 1866 | gregorian | `GyMMMEd` for `G` | `G y MMM d, E – G y MMM` | The second date has no day. |
| `qu.xml` 1878 | gregorian | `GyMMMEd` for `M` | `E, d MMM d – E, d MMM y G` | The first date has its day twice. |
| `sv.xml` 2607 | generic | `GyMMMd` for `y` | `d MMM y G – d MMM d y` | The second date has its day twice and no era. |
| `tr.xml` 1948 | generic | `GyMMM` for `G` | `G MMM y G – G MMM y` | The first date has its era twice. |
| `yo.xml` 1992 | gregorian | `yMEd` for `d` | `E, dd/MM/y – E, dd/MM/y, E` | The second date has its weekday twice. |

`sv`'s writes 16 June 2026 to 20 August 2027 in the Islamic calendar, at its medium format, as "30 Dhuʻl-H. 1447 AH – 17 Rab. I 17 1449", and `en_JP`'s writes the same days in the Japanese calendar as "Reiwa 8 Jun 16 – 9 Aug".
