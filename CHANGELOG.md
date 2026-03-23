# Changelog

All notable changes to this project will be documented in this file.

The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — Unreleased

### Added

* Number formatting — integers, decimals, percentages, currencies, and rule-based number formats (RBNF) for algorithmic systems such as Roman numerals and CJK ideographs.

* Number formatting of ranges

* Number formatting options :min_fractional_digits / :max_fractional_digits options

* MF2 offset, json interchange and bidi

* Date, time, and datetime formatting using CLDR calendar patterns with predefined `:short`, `:medium`, `:long`, and `:full` styles and support for custom format patterns.

* Interval formatting for date, time, and datetime ranges.

* Unit formatting with plural-aware patterns, SI/binary prefix support, compound units (e.g., "meter-per-second"), and territory-based usage preferences.

* List formatting with locale-appropriate conjunctions, disjunctions, and unit list styles.

* Currency metadata, ISO 4217 validation, territory-to-currency mapping, current/historic currency queries, and custom currency registration.

* Territory display names, containment hierarchies, subdivision names, and emoji flag generation.

* Language display names with `:standard` and `:menu` styles.

* Locale display names implementing the CLDR locale display name algorithm.

* Calendar data access — era names, month names, day names, and day period names for all CLDR-supported calendars.

* Unicode Collation Algorithm (UCA) implementation with CLDR locale-specific tailoring for 97 languages, including digraph expansion (Hungarian), script reordering, and the `[suppressContractions]` directive.

* Number range formatting — `to_range_string/3` formats numeric ranges using locale-specific patterns (e.g., "3–5"). Also `to_approximately_string/2`, `to_at_least_string/2`, and `to_at_most_string/2`. Accepts Elixir `Range` values (e.g., `3..5`).

* Number formatting options `:min_fractional_digits` and `:max_fractional_digits` for independent control of minimum and maximum fractional digits in `to_string/2`.

* ICU MessageFormat 2 (MF2) parser and interpreter with pre-compiled NimbleParsec grammar and integration with all formatting modules.

* MF2 `:offset` function for plural selection with numeric offsets (e.g., "you and N other people").

* MF2 JSON interchange format — `Localize.Message.JSON.to_json/2` and `from_json/1` for round-trip serialization to the TR35 §8 data model.

* MF2 bidirectional text handling — `:bidi` option (`:none`, `:isolate`, `:auto`) on `format_list/3` wraps placeholder output in Unicode isolate characters. Supports `u:dir` attribute for per-expression directional overrides.

* BCP 47 / RFC 5646 language tag parser with full support for Unicode extensions (`-u-` and `-t-`), private use subtags, and grandfathered tags.

* Locale management — per-process locale via `get_locale/0` and `put_locale/1`, application-wide default resolved from environment variables and application config. Locale loading serialized through `Localize.Locale.Loader` GenServer to prevent race conditions.

* Runtime data loading from ETF and JSON files with `:persistent_term` caching. No compile-time backend configuration required.

* Calendar data for all CLDR calendar systems including Buddhist, Hebrew, Islamic (5 variants), ROC (Minguo), Indian, Persian, Coptic, Ethiopic, Chinese, Japanese, and Dangi.

* Optional NIF (via `elixir_make`) for faster Unicode normalisation and collation sort-key generation. Enabled with `LOCALIZE_NIF=true`.

* Gettext integration — `Localize.Gettext.Interpolation` provides an MF2-based interpolation module for Gettext backends.
