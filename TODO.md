# TODO

## Pre-release

* [ ] Add `:description`, `:package`, `:source_url` to `mix.exs` for Hex.

* [ ] Define docs structure in `mix.exs` including topic grouping and user guides.

* [ ] Run `mix docs` and review generated documentation.

## Open

* [ ] File a CLDR ticket for stale `localeDistanceTest.txt` test data (confirmed our 48.2 rule-aligned results are correct; CLDR test expectations are outdated).

### Unicode version alignment

Elixir, OTP, and CLDR each ship with their own Unicode version. When these versions differ, string operations may produce subtly different results.

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
