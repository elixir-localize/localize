# TODO

## Pre-release

### Hex publishing

* [ ] Set version in `mix.exs`.

* [ ] Add `:description`, `:package`, `:source_url` to `mix.exs` for Hex.

* [ ] Add license file.

* [ ] Define docs structure in `mix.exs` including topic grouping and user guides.

* [ ] Run `mix docs` and review generated documentation.

* [ ] Run `mix dialyzer` and resolve any errors.

### CI

* [ ] Move the CI workflow (`upload-locales.yml`) to `.github/workflows/`.

## Open work

### Rewrite locale distance algorithm

The locale distance computation (`Localize.LanguageTag.match_distance/2` and `compute_match_distance/2`) uses a flat rule scan that does not match the ICU reference implementation. The ICU builds a trie-based distance table from `languageInfo.xml` where each level (language → script → region) returns a subtable for the next level. Our flat scan produces correct results for simple cases but diverges on edge cases.

The CLDR 48.2 test file (`localeDistanceTest.txt`) appears stale — expected values don't match the current `languageInfo.xml` rules. Our computed values align with the 48.2 rule data. See the discrepancy table below.

| Case | CLDR test | Our result | Notes |
|------|-----------|------------|-------|
| `nn → no` | 10 | 20 | XML rule says `distance="20"` |
| `to → en` | 14 | 34 | Rule `distance="30"` + region 4 |
| `zh-Hant → zh-Hans` | 23 | 54 | Script wildcard 50 + region 4 |
| `en-AU → en-CA` | 4 | 5 | CA in `$enUS` cluster → cross-cluster |
| `hr → sr-Latn` | 8 | 84 | `sr → hr` rule commented out in XML |

* [ ] Study the ICU `XLocaleDistance` trie-based implementation (`$CLDR_REPO/tools/cldr-code/src/main/java/org/unicode/cldr/draft/XLocaleDistance.java`).

* [ ] Rewrite `compute_match_distance/2` and `find_match_score/2` to match.

* [ ] Verify whether the ICU test actually passes with 48.2 data, or whether the test data is stale.

* [ ] File a CLDR ticket if confirmed stale.

### Nested bracket replacement (CLDR 48.2)

CLDR 48.2 formalizes nested bracket replacement as structured data. Our current implementation uses hardcoded `String.replace` calls which produce correct output for all known locales but don't use the CLDR data.

* [ ] Load `nestedBracketReplacement` data from CLDR locale data.

* [ ] Replace hardcoded `replace_parens_with_brackets/1` with a data-driven implementation.

* [ ] Apply bracket replacement only when nesting is detected (inner brackets within outer brackets).

## Design review

* [ ] Revisit `Localize.Locale.to_locale_id/1` — the nil-cldr_locale_id fallback path may produce atoms that don't correspond to known CLDR locales. Consider validation.

* [ ] Review error return consistency — most functions return `{:error, %Exception{}}` but some return bare `:error`. Standardise.

* [ ] Review whether `Localize.Territory.parent/1` should return a more specific error for territories with no parents.

* [ ] Consider whether `Localize.SupplementalData` accessor functions should be `@doc false`.

* [ ] MF2 JSON interchange format (`Localize.Message.JSON`) — requires `:json` module (OTP 27+). Decide fallback strategy for OTP 26.

## Future enhancements

### Custom/additional unit registration

ex_cldr_units supports runtime registration of custom units. Implementing this in Localize would require:

* [ ] A registration API for defining custom units at application start.

* [ ] Integration with the parser, formatter, and conversion system.

## Completed

### Pre-release blockers

* [x] Remove ex_cldr runtime dependency — ETF loader replaces `Cldr.Locale.Loader.get_locale/2`.

* [x] Merge localize_data into localize — all modules, data, Mix tasks, and scripts moved.

* [x] Write `CLDR_DATA.md` documenting the data update process.

* [x] Determine minimum Elixir/OTP versions — Elixir 1.17+, OTP 26+.

* [x] Zero compiler warnings on `mix compile --force`.

### Library merges

* [x] All ex_cldr_* libraries merged: Collation, Currency, Message, Number, Date/Time/DateTime/Interval, Unit, List, Territory, Language, LocaleDisplay.

### CLDR 48.2 migration

* [x] Reorder -u- before -t- in locale display names.

* [x] Flatten -t- language names to avoid nested parentheses.

* [x] Missing key translations fall back to key identifier.

* [x] MF2 `:currency` and `:percent` documented as Stable.

* [x] MF2 `u:locale` option — never implemented, already compliant with removal.

* [x] Data updated to 48.2.

* [x] `tz`, `kr`, `sd`/`rg` key display names implemented.

### Performance

* [x] NimbleParsec parser compile times optimized: Unit 16.9s→1.0s, Message 23.2s→2.5s.

* [x] Number formatting options validation optimized via `FastOptions`.

* [x] Currency structs pre-built at ETF generation time (301µs→13µs per format).

### Data and tests

* [x] CLDR conformance tests for unit conversions ported.

* [x] Unit preference tests ported.

* [x] Collation fully implemented including tailoring, CJK, search type, reordering.

* [x] Adversarial property tests for all public formatting APIs.

* [x] 23,960 tests passing, 0 failures.
