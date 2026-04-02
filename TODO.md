# TODO

## Pre-release

### Hex publishing

* [ ] Add `:description`, `:package`, `:source_url` to `mix.exs` for Hex.

* [ ] Define docs structure in `mix.exs` including topic grouping and user guides.

* [ ] Run `mix docs` and review generated documentation.

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

* [ ] Study the ICU `XLocaleDistance` trie-based implementation.

* [ ] Rewrite `compute_match_distance/2` and `find_match_score/2` to match.

* [ ] Verify whether the ICU test actually passes with 48.2 data, or whether the test data is stale.

* [ ] File a CLDR ticket if confirmed stale.

## Design review

* [x] Revisit `Localize.Locale.to_locale_id/1` — reviewed; internal coercion function, not a public validator. Callers use `validate_locale/1` for validation. No change needed.

* [x] `Localize.Territory.parent/1` returns `NoParentTerritoryError` instead of `UnknownTerritoryError` for valid territories with no parents.

* [x] `Localize.SupplementalData` accessor functions set to `@doc false`.

### Unicode version alignment

Elixir, OTP, and CLDR each ship with their own Unicode version. When these versions differ, string operations (NFC normalization, grapheme breaking, case mapping) may produce subtly different results depending on whether they use the OTP/Elixir Unicode tables or the CLDR Unicode data.

* [ ] Document which Unicode version each component uses.

* [ ] Identify code paths where Unicode version mismatches could produce incorrect results.

* [ ] Evaluate whether the `unicode` library dependency should be version-pinned to match the CLDR Unicode version, or whether we can rely on OTP's built-in Unicode support for OTP 28+.

* [ ] Consider conditional compilation that uses OTP's `:unicode` module directly on OTP 28+.

## Future enhancements

### Digital token (cryptocurrency) support

* [ ] Evaluate whether to integrate `digital_token` as an optional dependency or embed the token data directly.

* [ ] Add currency data for digital tokens (BTC, ETH, etc.) so they can be formatted with `Localize.Number.to_string/2`.

### Custom/additional unit registration

* [ ] A registration API for defining custom units at application start.

* [ ] Integration with the parser, formatter, and conversion system.

## Completed

### Pre-release blockers

* [x] Set version in `mix.exs`.

* [x] Add license file.

* [x] Run `mix dialyzer` and resolve any errors.

* [x] Move the CI workflow (`upload-locales.yml`) to `.github/workflows/`.

* [x] Data loader generates locales on-the-fly in `:dev` and `:test` environments.

* [x] Remove ex_cldr runtime dependency.

* [x] Merge localize_data into localize.

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

* [x] MF2 `u:locale` option — already compliant with removal.

* [x] Data updated to 48.2.

* [x] `tz`, `kr`, `sd`/`rg` key display names implemented.

* [x] Nested bracket replacement data-driven from CLDR locale data.

### Display names

* [x] Language display names support all alt variant styles (`:standard`, `:short`, `:long`, `:menu`, `:variant`).

* [x] `Language.to_string/2` renamed to `Language.display_name/2`.

* [x] T extension data types normalised to atoms consistently.

* [x] Error return consistency — all public functions return `{:error, %Exception{}}`.

### Performance

* [x] NimbleParsec parser compile times optimized: Unit 16.9s→1.0s, Message 23.2s→2.5s.

* [x] Number formatting options validation optimized via `FastOptions`.

* [x] Currency structs pre-built at ETF generation time (301µs→13µs per format).

### Data and tests

* [x] CLDR conformance tests for unit conversions ported.

* [x] Unit preference tests ported.

* [x] Collation fully implemented including tailoring, CJK, search type, reordering.

* [x] Adversarial property tests for all public formatting APIs.

* [x] Compound per-units with currency support (`curr-USD-per-year`).

* [x] Measurement systems data-driven from CLDR (`bcp47/measure.xml` and `measurementData.json`).

* [x] Coverage level data from CLDR (`coverageLevels.json`).

* [x] 24,049 tests passing, 0 failures.
