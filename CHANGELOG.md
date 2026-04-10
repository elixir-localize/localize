# Changelog

All notable changes to this project will be documented in this file.

The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — Unreleased

### Added

* `:list` MF2 function — Localize-specific extension for the MessageFormat 2 interpreter that formats a list operand by delegating to `Localize.List.to_string/2`. Each list element is itself formatted via `Localize.Chars`, so a message like `"{$items :list}"` with `items: [~D[2025-07-10], ~D[2025-08-15]]` produces `"Jul 10, 2025 and Aug 15, 2025"` in `:en`. Accepts a `style` (or `type`) option whose values map to CLDR list styles: `"and"` (default), `"and-short"`, `"and-narrow"`, `"or"`, `"or-short"`, `"or-narrow"`, `"unit"`, `"unit-short"`, `"unit-narrow"`. Documented in `guides/message_formatting.md` and `guides/conformance.md`.

* `Localize.Chars` protocol — single dispatch point for locale-aware string formatting. Mirrors `String.Chars` from Elixir core but is locale-aware and returns the standard `{:ok, string}` / `{:error, exception}` Localize result tuple. Built-in locale-aware implementations cover `Integer`, `Float`, `Decimal`, `Date`, `Time`, `DateTime`, `NaiveDateTime`, `Range`, `BitString`, `List`, `Localize.Unit`, `Localize.Duration`, `Localize.LanguageTag`, and `Localize.Currency`. Any type without a Localize-specific implementation falls through to `Kernel.to_string/1`, so atoms, charlists, booleans, and `nil` produce the same output they would from `Kernel.to_string/1`. Types with no `String.Chars` implementation either (tuples, plain maps, PIDs, references, anonymous functions) raise the same `Protocol.UndefinedError` they would from `Kernel.to_string/1`.

* `Localize.to_string/1`, `Localize.to_string/2`, `Localize.to_string!/1`, `Localize.to_string!/2` — top-level entry points that delegate to `Localize.Chars`. Lets user code format heterogeneous values through a single function regardless of type. The bang variants raise on error; the non-bang variants return the standard result tuple.

* `Localize.List.to_string/2` now formats each list element with `Localize.to_string/2` instead of `Kernel.to_string/1`. The locale (and other forwarded options like `:currency`, `:prefer`, etc.) propagate to every element, so a list of numbers, dates, units, etc. is rendered locale-aware end-to-end. List-specific options (`:format`, `:treat_middle_as_end`) are stripped before being passed to per-element formatters so they don't conflict with per-element formatter options of the same name. Strings still pass through unchanged. Charlists like `~c"hello"` are detected via `List.ascii_printable?/1` and converted via `Kernel.to_string/1` rather than being joined codepoint-by-codepoint, mirroring how `String.Chars`'s `List` impl handles them. `intersperse/2` is unchanged — it still returns the original term shapes for safe HTML and iolist rendering.

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

* Language display names with `:standard`, `:short`, `:long`, `:menu`, and `:variant` styles via `Localize.Language.display_name/2`.

* Script display names with `:standard`, `:short`, `:stand_alone`, and `:variant` styles via `Localize.Script.display_name/2`.

* Locale display names via `Localize.Locale.display_name/2` implementing the CLDR locale display name algorithm.

* Calendar display names via `Localize.Calendar.display_name/3` — a unified API for localized calendar system names, eras, months, days, quarters, day periods, and date-time field labels. Modeled on the JavaScript `Intl.DisplayNames` API.

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

* On-disk locale cache and HTTPS download provider — `Localize.Locale.Provider` exposes `locale_cache_dir/0`, `base_url/0`, `locale_url/1`, and `download_locale/1`, with `Localize.Locale.Provider.Cache` storing downloaded ETF files under the cache directory. The `PersistentTerm` provider falls back to the download path when a locale is not already cached.

* `Localize.version/0` — returns a `%Version{}` assembled from `priv/localize/version` (CLDR release) and `priv/localize/localize_patch_version` (Localize patch counter). Generated locale ETF files embed this value under the `:version` key so the cache can detect stale files. The semver parser tolerates CLDR version strings that omit minor/patch components (e.g. `"48"` from `aliases.json`).

* `mix localize.bump_patch_version` — explicit Mix task that increments the Localize patch counter for the current CLDR release. The patch counter is no longer bumped automatically by `mix localize.generate_locales`, so CI jobs that regenerate locales (for example the Cloudflare upload workflow) do not produce phantom version bumps. Run this task by hand whenever the locale-data generation pipeline (normalizers, transforms, etc.) changes.

* When `Localize.Data.write_version/0` detects a real CLDR major-version change (i.e. the new value from `aliases.json` differs from the major component of the previously recorded version), it now resets the patch counter to `0` automatically. The first `mix localize.bump_patch_version` after a CLDR upgrade therefore takes the patch from `0` to `1`. A more-specific sub-version recorded on disk (e.g. `"48.2"` while `aliases.json` carries `"48"`) is preserved untouched on rerun.

### Changed

* `Localize.LocaleDisplay` moved to `Localize.Locale.LocaleDisplay`.

* `Localize.Language.to_string/2` renamed to `Localize.Language.display_name/2`.

* `Localize.Calendar.localize/3` option `:type` renamed to `:context` for clarity. The `:context` option selects between `:format` and `:stand_alone` forms.

* `Localize.Territory.country_codes/0` renamed to `Localize.Territory.individual_territories/0` for consistency with the rest of the module naming. Returns the same sorted list of leaf territory code atoms, distinct from `Localize.Territory.territory_codes/0` which returns the map of ISO 3166 Alpha-2/Alpha-3/numeric code mappings.

* `Localize.Exception.InvalidLanguageTag` renamed to `Localize.InvalidLanguageTagError` and relocated to `lib/localize/exception/` for consistency with all other exception modules.

* Configuration option `:data_dir` renamed to `:locale_cache_dir`. Defaults to `Path.join(:code.priv_dir(:localize), "localize/locales")`.

* `Localize.List.to_string/2` and `Localize.List.intersperse/2` option `:format` renamed to `:list_style`. The companion helpers `known_list_formats/0` and `list_formats_for/1` were renamed to `known_list_styles/0` and `list_styles_for/1` for consistency. Freeing `:format` from list-specific use means it now passes through to per-element formatters: `Localize.List.to_string([~D[2025-07-10], ~D[2025-08-15]], locale: :en, format: :long)` produces `"July 10, 2025 and August 15, 2025"` because `:format` reaches `Localize.Date.to_string/2` for each element while the list join uses the default `:standard` style. The `list_patterns_for/1` helper is unchanged — it returns the underlying CLDR pattern data, not the style names.

### Added exceptions

* `Localize.LocaleDownloadError`, `Localize.LocaleIsStaleError`, `Localize.LocaleNotFoundInCacheError`, and `Localize.LocaleCacheWriteError` — raised by the new locale download and cache infrastructure.
