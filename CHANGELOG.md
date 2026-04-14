# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] — April 14th, 2026

### Changed

* `Localize.Unit.Math.mult/2` and `Localize.Unit.Math.div/2` now factor operands that share the same base dimension.

## [0.8.0] — April 14th, 2026

### Added

* `Localize.Message.format_to_safe_list/3` and `format_to_safe_list!/3` — new MF2 formatting entry points that preserve markup structure instead of stripping it.

## [0.7.0] — April 14th, 2026

### Changed

* Territory subdivision functions are now in the Localize.Territory.Subdivision module. Some functions have been renamed, see `Localize.Territory.Subdivision`.  The translate functions have been removed.

## [0.6.0] — April 13th, 2026

### Added

* Public function wrappers in `Localize.Unit.Math` for all dimensionless functions: `sin/1`, `cos/1`, `tan/1`, `asin/1`, `acos/1`, `atan/1`, `sinh/1`, `cosh/1`, `tanh/1`, `asinh/1`, `acosh/1`, `atanh/1`, `exp/1`, `ln/1`, `log/1`, `log2/1`. Previously these were only accessible via `apply_dimensionless/2`.

### Bug Fixes

* `apply_dimensionless/2` now validates that the unit is actually dimensionless before computing. Previously `sin(1 meter)` would silently return a result; it now returns `{:error, "sin requires a dimensionless value, got unit with base: meter"}`. Units must reduce to `revolution` (angles) or `part` (ratios) to be accepted.

## [0.5.0] — April 13th, 2026

### Added

* `:special` conversion support in `CustomRegistry`. Custom units can now be registered with `factor: :special` plus `:forward` and `:inverse` `{module, function}` tuples for nonlinear conversions. This enables logarithmic scales (decibels), temperature functions, density hydrometers, wire gauges, and other conversions that cannot be expressed as `value * factor + offset`. 

* `Conversion.do_convert/3` now uses a generalised `special_unit/1` lookup that checks both `CustomRegistry` and a compiled `@built_in_special` map, replacing the previous hardcoded `:beaufort` pattern match.

## [0.4.0] — April 13th, 2026

### Bug Fixes

* `Localize.all_locale_ids/1` (`:modern`, `:moderate`, `:basic`) now returns the correct expanded list of locales. Thanks to @cw789 for the report.

## [0.3.0] — April 13th, 2026

### Bug Fixes

* Load custom units in a single batch to avoid churning `:persistent_store`

## [0.2.0] — April 13th, 2026

### Bug Fixes

* SI prefix parsing for custom units. Custom units can now be prefixed with SI prefixes and power prefixes.

### Enhancements

* Custom unit category validation relaxed from a fixed allowlist to any non-empty string. The faciliates importing a broader range of unit definitions such as those from Gnu units.

## [0.1.0] — April 13th, 2026

Initial release.

### Highlights

* Full CLDR v48.2 locale data with lazy runtime loading from ETF files cached in `:persistent_term`. No compile-time backend configuration required.

* Number formatting — integers, decimals, percentages, currencies, ranges, and rule-based number formats (RBNF) including Roman numerals and CJK ideographs.

* Date, time, and datetime formatting using CLDR calendar patterns with `:short`, `:medium`, `:long`, and `:full` styles, custom skeleton patterns, and interval formatting.

* Unit formatting with plural-aware patterns, SI/binary prefixes, compound units, measurement system conversion, custom unit registration, and `Localize.Unit.Operators` for natural arithmetic (`km + m`).

* List formatting with locale-appropriate conjunctions, disjunctions, and unit list styles. Per-element formatting via `Localize.Chars`.

* ICU MessageFormat 2 (MF2) parser and interpreter with custom function registry, offset selection, JSON interchange, and bidirectional text support.

* Gettext integration — `Localize.Gettext.Interpolation` provides MF2-based interpolation for Gettext backends.

* `Localize.Chars` protocol — polymorphic locale-aware formatting with built-in implementations for 14 types and `Any` fallback to `Kernel.to_string/1`.

* Currency metadata, ISO 4217 validation, custom currency registration (private-use and extended codes), and territory-to-currency mapping.

* Display names for territories, languages, scripts, calendars, and full locale display names per the CLDR algorithm.

* Unicode Collation Algorithm (UCA) with CLDR locale-specific tailoring for 97 languages, including digraph expansion and script reordering.

* BCP 47 / RFC 5646 language tag parser with full Unicode extension support (`-u-`, `-t-`), locale distance matching, and parent chain resolution.

* On-disk locale cache with HTTPS download provider, version-based staleness detection, and `mix localize.download_locales` for build-time cache population.

* Optional NIF backend for faster Unicode normalisation and collation sort-key generation.

* Calendar data for all CLDR calendar systems including Buddhist, Hebrew, Islamic (5 variants), ROC, Indian, Persian, Coptic, Ethiopic, Chinese, Japanese, and Dangi.

* All public API functions return a standardized `{:error, exception}` (except bang variants). The exception is a standard Elixir exception struct populated with semantic information about the error. The error message can be returned by `Exception.message(exception)`. The exception messages are all Gettext messages using the MF2 format and can be localized.

See the [README](https://hexdocs.pm/localize/readme.html) for full documentation, configuration options, and usage examples.
