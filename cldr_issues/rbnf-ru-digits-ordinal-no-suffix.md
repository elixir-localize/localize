# Russian RBNF digits-ordinal has no suffix

**Status:** draft, not filed, 2026-11-28

**Component:** RBNF (`common/rbnf/ru.xml`).

## Summary

Russian `%digits-ordinal` writes the bare number, so a generic digits ordinal formats 3 as "3" rather than an ordinal.

## Details

In `common/rbnf/ru.xml`, `%digits-ordinal` is:

```
%digits-ordinal:
-x: −>>;
0: =#,##0=;
```

A Russian ordinal's ending depends on gender and case, which the gendered rule sets (`%digits-ordinal-masculine`, `%digits-ordinal-feminine-genitive` and the rest) supply. The ungendered set has no ending at all.

Of the 15 locales with gendered digits ordinals, 12 (uk, es, it, fr, pt, ca, hi and others) define the ungendered set as `=%digits-ordinal-masculine=;`. Swedish points it at the feminine set and Bulgarian adds `.`. Russian alone writes bare digits.

ICU builds from the same data, so it also formats 3 as "3".

## Proposed fix

Change Russian `%digits-ordinal` to `0: =%digits-ordinal-masculine=;`, which formats 3 as "3-й".

## Localize

Reported by a user in localize issue 72. Localize follows the data, and its `:grammatical_gender` and `:grammatical_case` options (1.11.0) choose the gendered rule sets.
