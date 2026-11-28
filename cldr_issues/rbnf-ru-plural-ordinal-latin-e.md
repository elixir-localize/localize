# Latin letters in Russian and Belarusian RBNF rules

**Status:** filed as [CLDR-19934](https://unicode-org.atlassian.net/browse/CLDR-19934), 2026-11-28

**Component:** RBNF (`common/rbnf/ru.xml`, `common/rbnf/be.xml`).

## Summary

Three Cyrillic RBNF rules contain a Latin letter that looks like the Cyrillic one it replaces: two Russian plural digits ordinals end in LATIN SMALL LETTER E (U+0065) where CYRILLIC SMALL LETTER IE (U+0435) belongs, and Belarusian 1 is spelt with LATIN SMALL LETTER I (U+0069) where CYRILLIC SMALL LETTER BYELORUSSIAN-UKRAINIAN I (U+0456) belongs.

## Details

Checked at `main` 951424004b.

In `common/rbnf/ru.xml`, `%digits-ordinal-plural` and `%digits-ordinal-plural-accusative` both read:

```
0: =#,##0=-e;
```

The `e` is U+0065, so 3 formats as "3-e", which looks right and is not Russian text. Every other Russian rule set uses Cyrillic letters (`-й`, `-х`, `-м`), and the neuter sets' `-е` is U+0435.

In `common/rbnf/be.xml`, `%spellout-cardinal-masculine` has:

```
1: адзiн;
```

The `i` is U+0069. The same word everywhere else in the file uses U+0456: `адзінаццаць`, `адзінаццаты`, `адзінаццатая`, `адзінаццатае`.

These are the only Latin letters in the rule text of the eleven RBNF files written in Cyrillic (ba, be, bg, cv, kk, ky, mk, ru, sr, uk, and root's Cyrillic numerals; root's Roman numeral rule sets are Latin by design). ICU builds from the same data, and `icu4c/source/data/rbnf/ru.txt` and `be.txt` on `main` carry the same letters.

## Proposed fix

Replace U+0065 with U+0435 in both Russian rule sets, `0: =#,##0=-е;`, and U+0069 with U+0456 in Belarusian, `1: адзін;`.

## Localize

Found while triaging localize issue 72, a companion to CLDR-19933. Localize returns the data as CLDR gives it.
