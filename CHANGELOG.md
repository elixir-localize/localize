# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Bug Fixes

* `Localize.supported_locales/0` now lazily resolves `config :localize, supported_locales: [...]` from the application environment when the `:persistent_term` cache has not yet been populated, instead of falling back to the full CLDR locale list. The cache is populated on application startup, but callers that run before the application has started — notably compile-time macro expansion in dependent applications like `localize_web`'s `~q` sigil — previously saw the full CLDR list during partial recompiles. This caused `Localize.validate_locale/1` to best-match against all CLDR locales rather than the configured subset, producing incorrect `cldr_locale_id` resolutions (e.g. `Localize.validate_locale("de")` resolving to `:de` instead of the configured `:"de-CH"`) and `CaseClauseError` at runtime when the resolved locale did not match any sigil-generated case clause.

## [0.22.0] — April 22nd, 2026

### Bug Fixes

* Fix `Cldr.Number.to_string/2` for `Decimal` numbers to produce the correct decimal digits. 

## [0.21.0] — April 22nd, 2026

### Bug Fixes

* Fix normalizing CLDR locale names to our standard atom format in `Localize.validate_calendar/1`.

* `Localize.Calendar.iso_day_of_week/1` no longer crashes with `MatchError` on non-ISO calendars. The generic branch destructured `calendar.day_of_week/4` as a 2-tuple but the `Calendar` behaviour returns `{day, first, last}`.

* `Localize.Time.to_string/2` with a partial time and a standard format atom (`:short`/`:medium`/`:long`/`:full`) now derives a CLDR skeleton from the fields actually present (`:h`, `:hm`, `:ms`) instead of returning `DateTimeUnresolvedFormatError`.

* `Localize.DateTime.to_string/2` no longer silently drops the hour when given a partial datetime such as `%{year: _, month: _, day: _, hour: _}` without `:minute`. Partial datetimes render via a split date + time path composed with the locale's datetime wrapper.

* `Localize.DateTime.to_string/2` with hour + minute (no second) under `:medium` no longer emits a stray trailing `:` before the AM/PM marker — the partial path derives the `:hm` skeleton instead of using the full `h:mm:ss a` pattern with an empty seconds slot.

* The datetime formatter's AM/PM handler now accepts any map with `:hour`, not just maps that also have `:minute`.

* `Localize.Number.to_string/2` now produces identical output for equivalent `Decimal` and float values. Previously `Decimal.new("1234.56")` rendered as `"1,234.560"` under the standard pattern because `Decimal.round/3` returns a result padded to the requested scale; the formatter now normalizes after rounding so only the digits actually needed are emitted. Currency and other formats with a mandatory minimum scale still pad correctly via `adjust_trailing_zeros/2`.

## [0.20.0] — April 22nd, 2026

### Bug Fixes

* Fixes mapping CLDR calendar types to the implementation module name.

## [0.19.0] — April 19th, 2026

### Bug Fixes

* Restored the support of RBNF locales in `Localize.Number.to_string/2`. They are implemented in `Localize.Number.Rbnf.to_string/1` but the delegation was lost on the `ex_cldr` transition. Thanks to @tangulip for the report. Closes #11.

## [0.18.0] — April 18th, 2026

### Breaking Change

* MF2 highlighter token class atoms renamed to match the tree-sitter capture taxonomy used by [`mf2_wasm_editor`](https://hex.pm/packages/mf2_wasm_editor), so one stylesheet now styles both server-rendered HTML and the browser editor. 

* `Localize.Message.to_html/2` now emits the new canonical class names with `_` converted to `-` on output (`.mf2-variable`, `.mf2-punctuation-bracket`, `.mf2-string-escape`, `.mf2-constant-builtin`, etc.). 

* `Localize.Message.to_ansi/2` default palette keys renamed to the new atoms.

### Removed

* The `mf2_theme_css/` directory and `scripts/generate_mf2_themes.exs` generator. Themes now live canonically in [`mf2_wasm_editor`](https://hex.pm/packages/mf2_wasm_editor).

### Bug Fixes

* `Localize.Gettext.Interpolation.runtime_interpolate/2` no longer raises `Localize.ParseError` when a translated string is not valid MF2. It now returns the message unchanged and logs a warning, matching gettext's own "fall back to the msgid" behaviour for missing translations. Dev-facing UI copy that happens to contain MF2-like syntax (e.g. `{{…}}` or `.match`) no longer crashes callers.

## [0.17.0] — April 17th, 2026

### Added

* `mix format` plugin `Localize.Message.Formatter.Plugin`. Canonicalises MF2 messages in `~M` sigils and standalone `.mf2` files. Enable by adding the plugin to `.formatter.exs`. See the "`mix format` plugin" section in the [MessageFormat 2 guide](https://hexdocs.pm/localize/message_formatting.html).

## [0.16.0] — April 17th, 2026

### Bug Fixes

* Fix locale download infinite recursion loop. Thanks to @woylie for the report. Closes #10.

## [0.15.0] — April 17th, 2026

### Added

* MF2 syntax highlighter. See `Localize.Message.to_tokens/2`, `Localize.Message.to_html/2` and `Localize.Message.to_ansi/2`. 

### Bug Fixes

* Fix the exception and message when formatting a number and specifying a number system that is not valid for the given locale.

## [0.14.0] — April 16th, 2026

### Breaking Change

* Remove `@derive` for `Jason` since `Jason` is no longer configured or used anywhere in the application.

### Bug Fixes

* Fix locale downloader to ensure it only uses the `:cldr_locale_id` field to construct the download URL.

## [0.13.0] — April 15th, 2026

### Bug Fixes

* `Localize.Interval.to_string/3` now correctly formats datetime intervals — matching `ex_cldr_dates_times` behaviour. Previously any interval between two datetime values was rendered as a date-only range, discarding the time portion. Now same-day intervals render as `"Apr 8, 2026, 12:00 PM – 2:00 PM"` (date once, time range) and different-day intervals render as `"Apr 15, 2026, 12:49 AM – Apr 16, 2026, 1:49 AM"` (full datetime on both sides). Time-only intervals (`Time` values on both sides) use the locale's time-interval patterns.

## [0.12.0] — April 15th, 2026

### Bug Fixes

* Chinese collation tailorings (`zh-u-co-pinyin`, `zh-u-co-stroke`, `zh-u-co-zhuyin`) now produce correct locale-specific ordering for Han characters. .

* Han radical-stroke ordering (UAX #38) under `-u-co-unihan` now applies correctly. The `Localize.Collation.Han` module was previously orphaned — its data was never loaded in consumer apps and the sort path never consulted it. Radical data is now pre-generated in the build pipeline and shipped in `priv/localize/collation_table.etf`; the sort path invokes `Han.collation_elements/1` for CJK codepoints when the `:han_ordering` option is `:radical_stroke` (set automatically for the `-u-co-unihan` collation type).

### Added

* `Localize.Collation.Options.han_ordering` option — `:implicit` (default, UCA codepoint-based) or `:radical_stroke` (UAX #38). Automatically set to `:radical_stroke` for `-u-co-unihan` locales.

* Persistent-term cache for parsed tailorings. First call to `Tailoring.get_tailoring/2` parses the rule string (~70 ms for zh-pinyin); subsequent calls read from persistent_term in microseconds.

* Differential tests for `zh-u-co-pinyin`, `zh-u-co-stroke`, `zh-u-co-zhuyin`, and `ja-u-co-unihan` that assert output differs from root codepoint order for specific character pairs — guards against silent regressions.

### Changed

* `Localize.Collation.Han` is no longer a GenServer. Radical data is loaded alongside the main collation table by `Localize.Collation.Table` (one ETF, one load step).

## [0.11.0] — April 14th, 2026

### Added

* `Localize.Interval.to_string/3` now accepts `nil` for either the `from` or `to` endpoint to format an open interval (e.g. `"Jan 1, 2020 –"` or `"– Jan 1, 2020"`). 

* New guide: [Interval and Duration Formatting](https://hexdocs.pm/localize/interval_and_duration_formatting.html) — covers `Localize.Interval` (including open intervals) and `Localize.Duration` (calendar-unit strings and numeric time strings) in one place.

## [0.10.0] — April 14th, 2026

### Changed

* Mix tasks now only do `Mix.Task.run("app.config")` followed by `Application.ensure_all_started(:localize)`, avoiding starting any consumer application. Thanks to @lostkobrakai for the report. Closes #7,

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
