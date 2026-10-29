# Number parser grammar

**Status:** in progress, 2026-10-29

`Localize.Number.Parser.parse_currency_amount/2` and `parse/2` are correct within the rules settled in October 2026 (`plans/tr35-audit.md`), and that correctness is pinned by 6,886 corpus rows, 1,450 lines of tests and ex_money's 35,040-input comparison. The code that gets there is not something to keep: 2,680 lines, 197 private functions and 28 regular expressions, with the rules spread across folds, regexes and string surgery rather than stated once. It is also slow, 145 µs for `Money.parse("USD 100")` against 22 µs in ex_money 6.2.1, 9.6 ms with an `:only` filter, and 82 µs for `Money.new(:USD, "1234.56")` against 6 µs. The profile is a long tail of about sixty `String.replace/3` calls per number, one per lenient fold, plus a dozen regex runs and a currency index rebuilt on every filtered call.

This plan rebuilds the amount and number path as a lexer, a grammar and a per-locale lexicon, with the current parser kept as the reference model until the new one reads everything the same way. Localize 1.5.0 waits for it (user, 2026-10-29), so the new parser ships behind the same API and the reference never reaches hex. `scan/2`, `resolve_currency/2`, `resolve_per/2` and `find_and_replace/3` keep their code in this sprint and move onto the lexer in the next (user: "as much as possible").

## What the current parser does, as rules

Everything below is a rule the new parser must keep. The reference model decides any case this list does not; a difference found by the differential test is a bug in the new parser until the user says otherwise.

### Reading a number (`parse/2`)

* **Digits** are the locale's number system's unless the text is written in Latin digits alone, in which case Latin, with the locale's Latin separators; `:number_system` overrides. Digits are read as ASCII values, whatever script they are written in.

* **Spaces** are the whole `[:Zs:]` category, equivalent to one another. A space at either end of the number, or beside its sign, is ignored. A space inside the number is a group separator where the locale groups with a space, and parts two numbers otherwise (`en` "1 2" is refused).

* **Format characters** (`[:Cf:]`, the bidi controls above all) are dropped anywhere in the number.

* **Lenient folds** come from CLDR's `lenient_parse` data in the `:number` and `:general` scopes: every character in a family reads as its sample, so any dash in the minus family is a minus, any apostrophe is `de-CH`'s group separator, and so on. The fold applies to the separators as well as the text.

* **Signs:** one at most, before or after the digits, or a pair of accounting parentheses, which make the number negative. A sign with parentheses is refused, as is a second sign. A minus before a decimal mark with no digit ahead of it ("-.5") is refused, because Swiss and Dutch write a dash for a zero there.

* **Zero fraction:** one or two dashes after a decimal mark with no digit following ("5.–", "5.--") read as a zero fraction, leniently only.

* **Grouping** is checked one of three ways: `:lenient` (each group no longer than the locale's largest size), `:strict` (`lenient: false`, the sizes exactly), or `:sizes` (each group against the primary and secondary sizes, which differ in the Indian system). A separator in the fraction is refused.

* **Underscores:** the reference drops `_` anywhere, so `parse/2` reads "_5", "5_", "1__000" and "5._5" (2026-10-29 probe); `parse_currency_amount/2` never reads one, since `_` is not part of a digit run. The new parser closes this gap: `_` is Elixir's digit separator and is read only between two digits, as in "1_000_000.34", and anywhere else the text is not a number. `scan/2`'s regex still admits a trailing `_`, so until it moves onto the lexer `scan("5_")` returns the text `"5_"` where it returned `5`. The differential test lists these as expected differences.

* **A foreign decimal point:** a period between digits is refused where no separator set being read makes it a separator and the shape is not a thousands group.

* **Separator sets:** a number is read with the locale's separators; with `:currency`, with the currency's separators and, in `de-AT` and `fr-CH`, the plain ones too; with `root_separators: true`, with the root locale's as well. Every valid reading must give the same value, or the text is refused as ambiguous.

* **Decimal points** may open or close a number (".5", "5."), for every number type alike. A decimal's exponent is bounded.

### Reading a currency amount (`parse_currency_amount/2`)

* **Shape:** the digits from the first to the last are the number, with the signs, parentheses, spaces and marks around them; the currency text stands before the number or after it, inside those decorations. Text with no digits is a currency with a missing amount, unless a sign or parenthesis opens or closes it.

* **Currency text** is matched after NFKC normalization against the locale's strings for the amount reading: codes, names and symbols, with the narrow symbol of another currency only where it is a currency sign naming one currency in the locale and in root, an unclaimed root sign added where the locale names none, letter abbreviations only for the locale's own currency, and historic currencies by code and name only. A string two currencies share, before or after normalization, names neither. A trailing period is tried off as well as on.

* **Bidi marks in currency strings:** two index keys carry an LRM, `he`'s CNY symbol "‎CN¥‎" and `fa-AF`'s CHF narrow symbol "Fr.‎" (2026-10-29 probe, across all 657 locales). The amount splitter strips bidi controls from the text, so neither key can ever match: `he` cannot read "CN¥5", nor its own formatted "‏5.00 ‏‎CN¥‎". The new parser closes this gap by stripping bidi controls from the strings when the lexicon's currency index is built, so the key is "cn¥" as the text is. The `fa-AF` key is a foreign narrow abbreviation and is not read either way. The differential test lists `he` CNY as an expected difference.

* **A mark between the currency and the digits** ("$.50", "kr.5") is the currency's where CLDR writes the currency with it, the number's where it is the currency's decimal mark in the locale, and otherwise refused.

* **Caller currencies** (`:caller_currency`) are asked about any currency text the locale does not name; text naming both a CLDR currency and a different caller currency is refused, except where it names the locale's own currency. A caller word with digits in it is the first word or the last, space-separated, read only where the amount has no other reading.

* **Default currency** (`:default_currency`) takes an amount that names none; without it the amount is a missing-currency error.

* **Filters** `:only` and `:except` narrow the currencies a string may name, and change what counts as a shared string.

* **The number** is read with `grouping: :sizes` and the currency's separators; a caller currency's number with the root locale's separators too. One to three digits, a mark and three more, in a currency of fewer than three places and an amount of one or more, is refused as a possible thousands group.

* **Locale:** a locale whose data is not installed is refused with `Localize.LocaleNotFoundInCacheError`; formatting still falls back.

* **Errors** keep their modules and fields: `UnknownCurrencyError{currency}`, `ParseError{reason: :missing_currency | :unexpected_input | :input_too_large}`, `InvalidAmountError{currency, amount, cause}`, `InvalidValueError`, `LocaleNotFoundInCacheError`. ex_money matches on these; the `detail` text is kept identical where it can be.

## Design

Four modules, each with one job. `Localize.Number.Parser` keeps the public API and its documentation and delegates.

### `Localize.Number.Lexicon`

Everything the lexer and the grammar need to know about a locale, computed once and cached with `Localize.LiteralMemory.cache/2` under a key of locale, number system, currency and `:separators` option:

* **`digits`** — a map from each digit of the number system, and of Latin, to its value.

* **`signs`** — the minus and plus families from the lenient sets, as `MapSet`s of graphemes.

* **`readings`** — a list of one to three separator sets, each with the `MapSet` of graphemes that fold onto its decimal separator, the set for its group separator, whether the group separator is a space, the grouping sizes, and the tag of the locale it belongs to. This is today's `symbol_sets/3` and `lenient_replacements/1` collapsed into lookups.

* **`currencies`** — the amount reading's currency index for the locale: a map from NFKC string to a list of claimants, each a currency code with the kind of string it is (`:code`, `:name`, `:symbol`, `:narrow`, `:sign`, `:unclaimed`, `:historic`). Built unfiltered once per locale; `:only` and `:except` are applied to the claimant list at lookup, which gives the same answer as building a filtered index and costs a list filter instead of 9.6 ms.

The lexicon is where the first-parse cost lives. It is built from the same `Localize.Locale.get/3` calls as today, and the target is under 5 ms per locale after the locale data is loaded.

### `Localize.Number.Lexer`

One pass over the string's graphemes, producing a list of typed tokens. The lexer knows digits, signs and Unicode categories; it does not know which mark is the decimal separator, because that depends on which separator set is being read.

| Token | What it is |
|---|---|
| `{:digits, "1234"}` | A maximal run of digits, as ASCII |
| `{:mark, "."}` | A punctuation character (`Po`, `Pf`, `Pi`) or any other character in a separator family |
| `:space` | A `[:Zs:]` character |
| `:minus`, `:plus` | A character in the minus or plus family |
| `{:dash, "–"}` | A zero-fraction dash that is not a minus |
| `:open`, `:close` | Parentheses |
| `{:text, "USD"}` | A maximal run of anything else: letters, currency signs, symbols |

Format characters are dropped. `_` is dropped, as today. Tokens carry their byte offsets so that `scan/2` can later recover the text between numbers and so that error messages can quote the input.

### `Localize.Number.Grammar`

The number grammar, one function per rule, over the token list. The EBNF goes in the moduledoc:

```ebnf
number    = lead, body, trail ;
lead      = { space }, [ sign ], { space }, [ "(" ], { space }, [ sign ], { space } ;
trail     = { space }, [ sign ], { space }, [ ")" ], { space }, [ sign ], { space } ;
body      = integer, [ decimal, fraction ], [ exponent ] ;
integer   = digits, { group, digits } ;
fraction  = digits | zero-dash ;
exponent  = ( "e" | "E" ), [ sign ], digits ;
```

`decimal` and `group` are whichever marks or spaces the reading's separator set names. Reading the same token list against each set in the lexicon and requiring agreement replaces today's loop of fold, regex and `String.replace`. The refusal rules are named functions, each with a comment naming the TR35 passage or the user decision it comes from: `one_sign`, `balanced_parentheses`, `no_sign_with_parentheses`, `no_minus_before_bare_mark`, `no_grouped_fraction`, `no_interior_space`, `group_sizes`, `no_foreign_decimal_point`, `agreed_readings`, `bounded_exponent`. The output is a number: its sign, integer digits, fraction digits and exponent, which the number type (`:integer`, `:float`, `:decimal`, `nil`) is made from without going back through a string.

### `Localize.Number.Parser.Amount`

The currency amount grammar over the same tokens:

```ebnf
amount    = outer, [ currency ], inner, number, inner, [ currency ], outer ;
currency  = text, [ mark ] ;
outer     = { space | sign | "(" | ")" } ;
inner     = { space | sign | "(" | ")" } ;
```

with at most one `currency`, and the semantic rules as named functions in the order the reference applies them: `currency_of_text` (index lookup, trailing-period variant, filters, single claimant), `mark_between` (currency's, number's or refused), `caller_claim` and `uncontested`, `caller_words` (digits in the text) and `one_reading`, `default_currency`, `number_of_amount` (the grammar with `:sizes` and the currency's readings), `unambiguous_fraction`. The error constructors are shared with the reference so the structs match field for field.

### What stays

`scan/2` keeps its regex scanner this sprint, and `resolve_currency/2`, `resolve_per/2` and `find_and_replace/3` their code, moved to use the lexicon's digit and lenient data where they share it today so no data is computed twice. The next sprint reads `scan/2` as a token-level scan: the maximal runs of tokens the number grammar accepts, with the text between them returned as it is.

## Verification

* **The reference model** is the current module copied to `test/support/reference_parser.ex` as `Localize.Number.ReferenceParser`, `@moduledoc false`, unchanged otherwise. It is deleted before release.

* **A differential test**, `test/localize/number/parser_differential_test.exs`, runs the new and the reference parser on the same inputs in one VM and asserts the same result: the same `{:ok, value}`, or an error of the same module with the same `reason`, `currency` and `amount` fields. Inputs are the corpus, every amount Localize formats for every installed locale, currency and number system in a dozen shapes (the generators of the October hunts, moved in from the scratchpad), the perturbations of those, and the number corpus from `parser_test.exs`. It runs across the 168 installed locales under `ERL_FLAGS="+MIscs 8192"` and is tagged `:differential` so the default suite stays fast.

* **The existing tests and the corpus** run against the new parser unchanged. A test that has to change is a difference to explain first.

* **ex_money's comparison** (`release/step2`, 35,040 inputs) must be all `same` against `new6.etf`, and the seven downstream suites must pass as they do today.

* **Benchmarks** before and after, in the table below, measured with `:timer.tc/1` over 2,000 calls.

| Call | 6.2.1 | Reference | Target |
|---|---|---|---|
| `Money.parse("USD 100")` | 22 µs | 145 µs | 30 µs |
| `Money.parse("1.234,56 €", locale: "de")` | 22 µs | 168 µs | 35 µs |
| `Money.parse("USD 100", only: [:USD, :EUR])` | 79 µs | 9,560 µs | 35 µs |
| `Money.new(:USD, "1234.56")` | 6 µs | 82 µs | 15 µs |
| First parse in a locale | 20 ms | 41 ms | 5 ms after data load |

## Tasks

Each task is one turn: build, run that task's tests, stop for the user to commit.

* [x] **Reference copy and harness** — `test/support/reference_parser.ex`, the generators in `test/support/parser_differential.ex` and `parser_differential_test.exs`, tagged `:differential`. Run against the unchanged parser: 132,215 amount inputs and 99,342 number inputs across 68 locales, 0 differences, 26 s. 2026-10-29.

* [x] **Lexicon** — `Localize.Number.Lexicon.fetch/3` and `number_system/3`, with digits, sign families, zero-fraction dashes, the period family and one to three readings, each a `MapSet` per separator with the lenient family folded in; cached per locale, system, currency and separator options. 19 tests. 2026-10-29.

* [x] **Lexer** — `Localize.Number.Lexer.tokens/2`: one pass, `{kind, value, source}` tokens, nothing dropped (bidi controls, format characters and underscores are tokens the grammars decide on), one regex call only for a non-ASCII character outside every lexicon set. Snapshots for bidi marks, Arabic digits, no-break spaces, "5.–" in `en` and `de-CH`, apostrophes, fullwidth and superscript characters. 2026-10-29.

* [ ] **Number grammar** — `Localize.Number.Grammar` and `parse/2` on it; the differential test on numbers all green; `parser_test.exs` unchanged.

* [ ] **Currency index** — the lexicon's `currencies` map with claimant lists and filters at lookup, equal to today's filtered `amount_strings/3` for every locale and for a sample of filters.

* [ ] **Amount grammar** — `Localize.Number.Parser.Amount` and `parse_currency_amount/2` on it; the differential test on amounts all green; `currency_amount_test.exs` and the corpus unchanged.

* [ ] **Remove the superseded code** — delete the private functions the new path replaces, leaving `scan/2`, `resolve_*` and `find_and_replace/3` working on the lexicon's shared data; credo and dialyzer clean.

* [ ] **Benchmarks and documentation** — fill the table, write the EBNF moduledocs, a CHANGELOG line (internal rewrite, no API change, the speed), delete the reference copy, run the gates, ex_money's comparison and the downstream suites.

* [ ] **Next sprint: `scan/2` on the lexer** — a token-level scan with the same results as the regex scanner, verified the same way.
