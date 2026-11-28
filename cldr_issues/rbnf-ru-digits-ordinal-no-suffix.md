# Russian RBNF digits-ordinal has no suffix

**Status:** draft, not filed, 2026-11-28

**Component:** RBNF (`common/rbnf/ru.xml`).

## Summary

Russian `%digits-ordinal` writes the bare number, so a generic digits ordinal formats 3 as "3" rather than an ordinal.

## Details

In `common/rbnf/ru.xml` (checked at `main` 951424004b), `%digits-ordinal` is:

```
%digits-ordinal:
-x: −>>;
0: =#,##0=;
```

A Russian ordinal's ending depends on gender and case, which the gendered rule sets (`%digits-ordinal-masculine`, `%digits-ordinal-feminine-genitive` and the rest) supply. The ungendered set has no ending at all.

Of the 15 locales with gendered digits ordinals, 12 define the ungendered set as `=%digits-ordinal-masculine=;`: ca, es, es_419, fr, gu, hi, it, mr, pa, pt, uk and ur. Swedish points it at the feminine set and Bulgarian adds `.`. Russian alone writes bare digits.

ICU builds from the same data (`icu4c/source/data/rbnf/ru.txt` on `main`), so it also formats 3 as "3".

## Proposed fix

Change Russian `%digits-ordinal` to `0: =%digits-ordinal-masculine=;`, which formats 3 as "3-й".

This is the shape CLDR-18690 (v49) gave Italian's `%digits-ordinal` so that digit ordinals parse back to their value. CLDR-19294 (v49) reworked the Russian ordinal rules but concerned the spellout ordinals, and left `%digits-ordinal` as it was.

## Localize

Reported by a user in [elixir-localize/localize#72](https://github.com/elixir-localize/localize/issues/72). Localize follows the data, and its `:grammatical_gender` and `:grammatical_case` options (1.11.0) choose the gendered rule sets.
