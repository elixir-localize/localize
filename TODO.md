# TODO

## Pre-release

* [ ] Add `:description`, `:package`, `:source_url` to `mix.exs` for Hex.

* [ ] Define docs structure in `mix.exs` including topic grouping and user guides.

* [ ] Run `mix docs` and review generated documentation.

## Open

* [x] File a CLDR ticket for stale `localeDistanceTest.txt` test data (confirmed our 48.2 rule-aligned results are correct; CLDR test expectations are outdated).

### Unicode version alignment

Removed the `unicode` hex dependency. Collation now uses `Localize.Collation.Unicode` backed by UCD data (combining classes, decimal digits) downloaded from `unicode.org` and stored as ETF files. NFC/NFD normalization uses OTP's built-in `:unicode` module.

* [x] Removed `unicode` hex dependency — replaced with `Localize.Collation.Unicode` using UCD ETF data.

* [x] `mix localize.download_unicode_data` fetches UCD files from `unicode.org/Public/17.0.0/ucd/`.

* [x] Only OTP's `:unicode` module (NFC/NFD) and our own UCD ETF data are used — no external Unicode library.

## Future enhancements

### Digital token (cryptocurrency) support

* [ ] Evaluate whether to integrate `digital_token` as an optional dependency or embed the token data directly.

* [ ] Add currency data for digital tokens (BTC, ETH, etc.) so they can be formatted with `Localize.Number.to_string/2`.

### Custom/additional unit registration

* [ ] A registration API for defining custom units at application start.

* [ ] Integration with the parser, formatter, and conversion system.

### Person name formatting

* [ ] Create a separate `localize_person_names` package using `unicode_string` for Unicode word segmentation.

* [ ] Implement TR35 person name formatting spec (`tr35-personNames.md`).

* [ ] Person name data is already normalized and stored in locale ETFs (`:person_names` key).

## Completed

### Pre-release blockers

* [x] Set version, license, dialyzer, CI workflow, data loader, ex_cldr removal, localize_data merge, CLDR_DATA.md, minimum versions, zero warnings.

### Library merges

* [x] All ex_cldr_* libraries merged: Collation, Currency, Message, Number, Date/Time/DateTime/Interval, Unit, List, Territory, Language, LocaleDisplay.

### CLDR 48.2 migration

* [x] Locale display name ordering, T extension flattening, key fallbacks, MF2 stable features, data updated to 48.2, nested bracket replacement data-driven.

### Display names

* [x] Language display names with all alt variant styles. Renamed to `Language.display_name/2`. T extension types normalised. Error returns standardised. `SupplementalData` set to `@doc false`. `Territory.parent/1` returns `NoParentTerritoryError`. `Locale.to_locale_id/1` reviewed (no change needed).

### Locale distance

* [x] Trie-based locale distance algorithm (`Localize.Locale.DistanceTrie`) — 242x faster than flat scan. CLDR test data discrepancies confirmed as stale.

### Performance

* [x] NimbleParsec parser compile times (16.9s→1.0s, 23.2s→2.5s). Number formatting via `FastOptions`. Currency structs pre-built (301µs→13µs).

### Data and tests

* [x] CLDR conformance tests, unit preferences, collation, adversarial property tests. Compound per-units with currency (`curr-USD-per-year`). Measurement systems from CLDR. Coverage levels. 24,049 tests passing, 0 failures.
