# Russian RBNF plural digits ordinals use a Latin e

**Status:** draft, not filed, 2026-11-28

**Component:** RBNF (`common/rbnf/ru.xml`).

## Summary

Two Russian plural digits-ordinal rule sets end in LATIN SMALL LETTER E (U+0065) where CYRILLIC SMALL LETTER IE (U+0435) belongs.

## Details

In `common/rbnf/ru.xml`, `%digits-ordinal-plural` and `%digits-ordinal-plural-accusative` both read:

```
0: =#,##0=-e;
```

The `e` is U+0065. Every other Russian rule set uses Cyrillic letters (`-й`, `-х`, `-м`), so 3 formats as "3-e" with a Latin letter that looks right and is not.

## Proposed fix

Replace U+0065 with U+0435 in both rule sets: `0: =#,##0=-е;`.

## Localize

Found while triaging localize issue 72. Localize returns the data as CLDR gives it.
