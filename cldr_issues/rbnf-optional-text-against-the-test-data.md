# TR35's rule for RBNF's optional text gives other results than CLDR's test data

TR35's rule for the optional text between square brackets in an RBNF rule, read as it is written, gives results that CLDR's test data does not have. CLDR's own test data under `common/testData` is generated from ICU, so this is a place where the specification and ICU differ, and an implementation cannot follow both.

All references are to CLDR `6198cae999ceb4847b25ddc0815835f07fced411`.

## The specification

TR35 Numbers, Rule Sets (`docs/ldml/tr35-numbers.md`, the table of substitution tokens):

> `[]` in normal rule: When the number is not an even multiple of the rule's divisor, use the text and rules between the beginning square bracket, and the end square bracket or the | symbol. When the number is an even multiple of the rule's divisor, and no | symbol is used, omit the text.

## The data and the test data

`common/rbnf/af.xml`:

```
%%2d-year:
0: honderd[ >%spellout-numbering>];
1: nul =%spellout-numbering=;
10: =%spellout-numbering=;
%spellout-numbering-year:
1100/100: << >%%2d-year>;
```

`common/testData/rbnf/af.ssv`:

| Rule set | Number | Test data | By the sentence as written |
|---|---|---|---|
| `%spellout-numbering-year` | 1100 | "elf honderd nul" | "elf honderd" |
| `%spellout-numbering-year` | 2000 | "twintig honderd nul" | "twintig honderd" |

## What differs

The rule `0: honderd[ >%spellout-numbering>]` is given 0, an even multiple of any divisor, so by the sentence its optional text is omitted and the year is "elf honderd". ICU implements the brackets by making two rules of a rule, one without the text and one with it, and does so only for a rule whose base value is positive and an even multiple of its divisor (`NFRule.makeRules`); any other rule keeps its text always, and writes "nul" here. The rule's author seems to have meant the specification's reading.

## Suggested fix

Either the test data and ICU are corrected to omit the text, or the table says that the brackets of a rule whose base value is zero, or no even multiple of its divisor, are always written, and `af.xml`'s rule is rewritten without them.
