# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.40.0] — June 1st, 2026

### Breaking Changes

* A *bare* relative `:locale_cache_dir` (no `:otp_app` set) is now refused at app start with `Localize.LocaleCacheDirError` — it resolved against the BEAM's CWD, which differs between mix tasks, `mix test`, and a release. Fix: add `:otp_app` to anchor the relative path, or use an absolute path.

### Bug Fixes

* `Localize.Locale.Provider.locale_cache_dir/0` validates its configuration at app start (via `Localize.Supervisor`) and raises `Localize.LocaleCacheDirError` instead of silently reading from the wrong directory at runtime.

* `Localize.Locale.LocaleDisplay.display_name/2` no longer raises `FunctionClauseError` on a BCP 47 generic extension carrying an odd number of subtags (e.g. `cr-s-7b`); the trailing singleton chunk now renders as a bare subtag.

### Enhancements

* New `:otp_app` config key. Three supported forms for the locale cache directory: (1) `:otp_app` only → `Application.app_dir(<otp_app>, "priv/localize/locales")`; (2) `:otp_app` + relative `:locale_cache_dir` → `Application.app_dir(<otp_app>, <relative>)`; (3) absolute `:locale_cache_dir` → used verbatim, `:otp_app` ignored.

## [0.39.0] — May 31st, 2026

### Bug Fixes

* Scope download_locales skip check to the configured cache dir, not the bundled fallback. Thanks to @allenwyma for the issue. Closes #35.

## [0.38.0] — May 23rd, 2026

### Enhancements

* `Localize.Locale.expand_locale_list/2` (and therefore the `:supported_locales` configuration) now accepts a Gettext backend module like `MyApp.Gettext` as an entry; it expands to `Gettext.known_locales/1` with each returned string re-resolved through the existing POSIX-normalisation and likely-subtag canonicalisation path. The check uses `Code.ensure_compiled/1` so the entry is safe to place in either `config.exs` or `runtime.exs`.

## [0.37.0] — May 17th, 2026

### Bug Fixes

* `Localize.DateTime.Formatter` audit: removed remaining `:gregorian` / `Calendar.ISO` hardcoding. The `{0}` / `{1}` date-time placeholders now derive the CLDR calendar from the date instead of always asking for the gregorian pattern, ISO week-of-year (`w` / `Y`) prefers the date's own `iso_week_of_year/3` callback before falling back to converting to `Calendar.ISO`, and `iso_day/1`'s dead silent-fallback clause for unknown calendars was removed.

* `Localize.Date.to_string/2` now honours CLDR `number_system` overrides carried alongside date patterns — Hebrew dates render in Hebrew numerals (`י״ב באייר ה׳תשפ״ד`), Japanese imperial year-1 renders as `元年`, and numeric overrides like `:arab` transliterate per-field via the system's digit set. Algorithmic systems resolve through CLDR's `numberingSystems.json` to the right RBNF rule (`:hebr` → `:hebrew`, `:jpanyear` → `:spellout-numbering-year-latn` under `:ja`).

* `Localize.Date.to_string/2` with a skeleton format (e.g. `:yMMMM`) against a non-Gregorian calendar no longer infinite-loops. `Match.best_match/3` now receives the calendar explicitly and `resolve_skeleton` carries a `seen` set, terminating any residual match cycle.

* `Localize.Date.to_string/2` now honours non-Gregorian calendars carried in the date's `:calendar` field — previously every call hard-coded `:gregorian`. A `Date` built with `Calendrical.Japanese` now formats as `平成12年1月1日` under `:"ja-JP"` instead of `2000/01/01`.

* `Localize.Calendar.localize/3` for `:era` now derives the correct era by delegating to the date's `year_of_era/3` callback. Previously it always returned era 1, producing `白雉` (Hakuchi, AD 650) for every `Calendrical.Japanese` date.

* `Localize.DateTime.Formatter` `y` token now uses the calendar's `calendar_year/3` (or `year_of_era/3` as fallback) for non-`Calendar.ISO` dates, so era-relative year numbering — Heisei 12, Reiwa 6, AH 1420, BE 2543 — renders correctly.

* `Localize.DateTime.Format.resolve_variant/2` now handles the CLDR `%{format: pattern, number_system: ns}` variant shape. Without this, locales whose date patterns carry a `number_system` override (Japanese `jpanyear`, Hebrew `hebr`) silently fell back to Gregorian.

## [0.36.0] — May 15th, 2026

### Bug Fixes

* Fix `currency_symbol: :none` when processing options for `Localize.Number.to_string/2`.

## [0.35.0] — May 14th, 2026

### Bug Fixes

* `Localize.Unit.localize/2` and a list-of-units overload of `Localize.Unit.to_string/2` close the parity gap with `Cldr.Unit.localize/3`: passing `:usage` to `to_string/2` now resolves the locale-preferred unit set (territory derived from `:locale` via `Localize.Territory.territory_from_locale/1`), decomposes the value across it, and joins the parts with the locale's standard list pattern in a single call (e.g. `Localize.Unit.to_string(Localize.Unit.new!(1.83, "meter"), usage: :person_height, locale: "en-US")` returns `{:ok, "6 feet and 0.047 inches"}`).

* `Localize.Unit.Conversion.convert/3` and `Localize.Unit.decompose/2` now preserve `Decimal` precision end-to-end: `Decimal` inputs flow through Decimal arithmetic instead of round-tripping through float.

* `Localize.Unit` gains a `:format_options` struct field that `localize/2` populates from the `skeleton` attribute on CLDR's `unitPreferenceData` (e.g. `[round_nearest: 50]` for `usage: :road` distances of 300 m+ in region 001). `to_string/2` merges these per-unit options with caller-supplied options and forwards them to the number formatter, so a 311 m road distance now renders as `"300 meters"` rather than `"311 meters"`. Caller-supplied options win on conflict; usages whose CLDR preferences carry no skeleton (e.g. `person-height`) are unchanged.

* `Localize.Unit.Math.round/3` now accepts a rounding mode (`:half_up` default, plus `:half_even`, `:half_down`, `:up`, `:down`, `:ceiling`, `:floor`); float values are routed through `Decimal` so every mode produces consistent results. New `Localize.Unit.Math.trunc/1` truncates toward zero with the same Decimal/float/integer dispatch as `floor/1` and `ceil/1`.

* `Localize.Unit.measurement_system_for_territory/2` accepts a category second argument: `:default` (existing behaviour), `:temperature` (e.g. `:US` → `:us` for Fahrenheit), or `:paper_size` (`:US` → `:us_letter`, `:FR` → `:a4`). The category-specific maps in CLDR's `measurementData.json` only enumerate territories whose category system *differs* from their default measurement system, so the lookup falls through to the default for any territory not listed in the category map.

* `Localize.Unit.decompose/3` accepts an optional third `format_options` argument and stamps it on the trailing (smallest) decomposed unit; intermediate units whose integer part rounds to zero are now skipped, matching cldr_units' behaviour. This is what `Localize.Unit.localize/2` uses internally to thread CLDR preference skeletons through to `to_string/2`.

* `Localize.Unit.to_string/2` documents `:grammatical_gender` and `:grammatical_case` as accepted options, matching the naming used by `Cldr.Unit.to_string/3`. `:grammatical_case` selects a case-keyed pattern variant (existing functionality, now documented). `:grammatical_gender` is accepted for cldr_units API parity but only meaningful for compound-unit patterns; for simple units the gender is fixed by CLDR data and the option has no effect on output.

* `Localize.Unit.Preference.preferred_units/2` documents `:scope` and `:alt` as forward-compatible placeholder options accepted but unused, matching `cldr_units` API surface. CLDR 48 ships no `<unitPreference>` carrying these attributes.

## [0.34.0] — May 14th, 2026

### Bug Fixes

* `Localize.Utils.Http` now resolves the HTTPS trust store via `:public_key.cacerts_get/0` before falling back to the existing `cacertfile` chain (configured path → `CAStore` → `:certifi` → well-known Unix paths). `mix localize.download_locales` previously failed on Windows because the resolver only searched Unix file paths even though the OS-native trust store was reachable. Thanks to @LostKobrakai for the report. Closes #30.

* `Localize.Number.System` no longer bakes the build host's absolute ETF path into its compiled BEAM which caused exceptions when the build host and deployment host were different. The lookup now happens at runtime via `Application.app_dir/2` from a function body. Thanks to @neilberkman for the PR. Closes #28.

### Enhancements

* `Localize.Supervisor` is now a publicly documented module that owns the library's runtime supervision tree and runs the one-time post-start work (supplemental-atom interning, `:supported_locales` resolution). Consumers can keep the default OTP auto-start, or mark the dependency `runtime: false` and mount `Localize.Supervisor` directly under their own application supervisor. See the new `guides/supervision.md` for the full pattern.

## [0.33.0] — May 13th, 2026

### Breaking Changes

* `Localize.Message.Sigil` is renamed to `Localize.Message.Sigils` to make room for additional MF2 sigils. Update any `import Localize.Message.Sigil` to `import Localize.Message.Sigils`.

### Enhancements

* `Localize.Message.Sigils` adds a new `~t` sigil for compile-time MF2 translation. Elixir `#{expr}` interpolations are rewritten as MF2 `{$name}` placeholders with bindings derived automatically (`fruit.name → fruit_name`, `String.upcase(x) → string_upcase`, etc.), the canonical msgid is registered with Gettext for translation lookup, and modules opt in via `use Localize.Message.Sigils, backend: MyApp.Gettext`. Requires the backend to use `Localize.Gettext.Interpolation`.

* `Localize.Gettext.Interpolation.skip_interpolation_sentinel/0` — public sentinel used by `Localize.HTML.t/1` (and other markup-aware renderers) to retrieve a translated MF2 source without running the markup-stripping interpolation. Both `runtime_interpolate/2` and `compile_interpolate/3` short-circuit when this sentinel is passed as bindings.

### Bug Fixes

* `Localize.Application.start/2` now eagerly reads every bundled supplemental dataset (languages, scripts, territories, variants, subdivisions, units, currency codes, calendars, timezones, territory subdivisions, locale ids, number systems) so the atoms they reference are interned at app start. The 0.30.0 atom-DOS hardening switched many lookups to `binary_to_existing_atom`, which assumes the legitimate atoms already exist. Without the eager-load, valid input like `numberingSystem=arab` could surface as a bogus "unknown numbering system" error on a fresh BEAM where no prior code path had triggered the relevant `binary_to_term/1` read. Manifested as a transient CI failure in `Localize.Message.NumberOptionsTest`; cause was identical in shape to issue #26.

* `Localize.default_locale/0` no longer hangs when `LANG`/`LC_*` hold values that fail validation (e.g. `POSIX` on minimal CI runners): the resolver pre-seeds the `:persistent_term` cache with `:en` before walking the env-var/app-config chain so a recursive locale lookup during warning formatting short-circuits, and the two warning sites now use a non-localised message to avoid the `Exception.message/1` → Gettext-backend → `get_locale/0` recursion that produced the original 60-second hang in `localize_translate` CI.

## [0.32.0] — May 12th, 2026

### Bug Fixes

* `mix localize.download_locales` no longer evaluates `config/runtime.exs` of the consumer application. Previously the task ran `Mix.Task.run("app.config")`, which transitively evaluated `runtime.exs`, which was not necessary. The task now loads only compile-time config (`config/config.exs` and any imported env-specific file), matching the build-time contract its docstring already advertised. Thanks to @whatyouhide for the PR.

* Hardened two further sites that pattern-matched `{:ok, _} = <fallible Localize call>` and could have surfaced the same `MatchError` class as issue #26: the per-unit format loop in `Localize.Duration.to_string/2` now short-circuits on the first formatter error, and `Localize.Number.Formatter.Decimal`'s digit-transliteration step now uses `with` to fall through to untransliterated digits if either the requested or `:latn` number-system data is unavailable.

* New `Localize.LintTest` source-level lint that scans `lib/` and fails the test suite if any file pattern-matches `{:ok, _} =` against a known-fallible Localize call. The list of fallible calls and an empty allowlist live in the test; future occurrences fail loudly on the offending PR rather than waiting for a runtime regression report.

* New `Localize.Locale.FallbackResilienceTest` exercises the load → store → get pipeline for seven representative regional locales under a provider that only serves `:en`, asserting that the data ends up under the canonicalised requested key and that `provider.get/3` succeeds.

* New `Mix.Tasks.Localize.DownloadLocalesTest` calls `DownloadLocales.banner/2` directly with `default_locale: :"en-ZA"` set, reproducing the exact scenario from issue #26 without invoking the network. `banner/2` is now `@doc false` so the test can reach it.

* New `Localize.AtomInterningTest` exercises the public lookup paths that previously surfaced the supplemental-atom bug — `Localize.Number.System.system_name_from/2` and friends, plus `Localize.Currency.validate_currency/1`, `Localize.validate_calendar/1`, `Localize.validate_territory/1`, `Localize.validate_script/1` — each driven with binary input. A regression in `intern_supplemental_atoms/0` would surface here as a structured error from one of these accessors.

## [0.31.0] — May 12th, 2026

### Bug Fixes

* `Localize.Locale.Loader` now stores fallback locale data under the *requested* locale id rather than the *resolved* fallback id, restoring 0.29 behaviour. The regression introduced in 0.30.0 caused `provider.get(requested_locale, _)` to miss in-memory fallback data and surface as a spurious `ItemNotFoundError` — most visibly crashing `mix localize.download_locales` with a `MatchError` when `default_locale` named an unavailable locale. Locked down with `test/localize/locale/loader_fallback_test.exs`. Closes #26.

* `mix localize.download_locales` no longer pattern-matches on the result of `Localize.Message.format/2` when building its progress banner; if formatting fails for any reason the task falls back to a plain ASCII banner and continues with the actual download.

### Behaviour Changes

* `Localize.InvalidValueError` gained an `:allowed_values` field and a new `Localize.NoCertificateStoreError` carries the searched paths; previously prose-stuffed `:expected`/`:currency` fields and bare-string `:reason` codes are now structural.

* Eight option-validation sites across `Localize.Language`, `Localize.Script`, `Localize.Collation`, `Localize.Utils.Map`, and `Localize.Utils.Http` now raise structured Localize exceptions rather than `ArgumentError`/`RuntimeError`.

## [0.30.1] — May 12th, 2026

### Bug Fixes

* Revert the `[:safe]` option on `:binary_to_term/2` since we cannot guarantee all the required atoms are materialized at application start. Thanks to @bigardone for the report. Closes #25.

## [0.30.0] — May 12th, 2026

### Security

* `Localize.LanguageTag.parse/1` no longer calls `String.to_atom/1` on raw parser output, closing an atom-table-exhaustion DOS vector on untrusted locale inputs. Atomisation is now gated behind the CLDR validity sets after alias resolution, and unrecognised language/script/territory subtags return `Localize.InvalidSubtagError`.

* `Localize.Locale.to_locale_id/1` renamed to `Localize.Locale.cldr_locale_id_from/1` and now returns `{:ok, atom()} | {:error, Exception.t()}`, gating atom creation behind `Localize.validate_locale/1` and closing a second atom-table-exhaustion vector on locale inputs.

* `Localize.Currency.validate_currency/1`, `territory_currencies/1`, `current_currency_for_territory/1`, and the binary-code branch of `currencies_for_locale/3`'s filter no longer atomise input before checking validity. Unknown currency or territory binaries are rejected via `Helpers.existing_atom/1` and never grow the atom table.

* `Localize.Script.display_name/2` and `Localize.Unit.Formatter` no longer atomise binary input before checking validity. Unknown script codes return `Localize.UnknownScriptError` without growing the atom table; the unit formatter's currency atomisation is gated as defence-in-depth behind the upstream `Localize.Unit.validate_currency_codes/1` check.

* MF2 `:list` function and unit parser no longer atomise user-controlled binaries. The `:list` function's binary `style=` fallthrough now sets a sentinel atom that surfaces as an `InvalidValueError` in `Localize.List`, and SI prefix names are resolved through a compile-time lookup map (`Localize.Unit.Data.si_prefix_atom/1`) rather than `String.to_atom/1` at parse time.

* `Localize.Number.System` (`system_name_from/2`, `number_system_digits/1`, `to_system/2`), `Localize.Number.Symbol.number_symbols_for/2`, and the datetime-formatter's `time_preferences_for/1` no longer atomise user-supplied binary number-system or locale names before validation. Lookups go through `Helpers.existing_atom/1` against pre-atomised CLDR data sets.

* Closed additional Atom DOS vectors in `Localize.Locale.LocaleDisplay.display_name/2` (now routes through `cldr_locale_id_from/1`), `Localize.Territory.Subdivision.display_name/2`, the `-u-co-` and `-u-kr-` extension parsers in `Localize.Collation.Options`, and the redundant `String.to_atom(to_string(...))` round-trip in plural-rule fallback.

* Closed three further atom-DOS sites called out by the security audit's findings 1.4 and 1.5: `LocaleDisplay.U.find_exemplar_city/2` (`-u-tz-` IANA region/city splitter), `LocaleDisplay.T.to_atom_safe/1` (`-t-` extension subtag normalisation), and `Gettext.Interpolation.safe_to_atom/1` (missing-binding name reporting). All three previously fell through to `String.to_atom/1` on a miss, which defeated the helper's name; they now return the original binary unchanged when no atom exists.

* Locale cache files and downloaded ETFs are decoded with `:erlang.binary_to_term(_, [:safe])`. Closes a node-crash vector for any deployment with `:locale_cache_dir` set to a writable directory: a malicious or corrupted cache file can no longer resurrect arbitrary atoms, funs, or refs. Failed safe decodes surface as `LocaleNotFoundInCacheError` (or `LocaleDownloadError` for the download path) and the file is treated as stale.

* Public parser entry points now reject oversized input before invoking the grammar, capping the parser's CPU exposure on hostile input. Defaults are 256 bytes for `Localize.LanguageTag.parse/1` and `Localize.Unit.Parser.parse/1`, 64 KB for `Localize.Message.Parser.parse/1`, and 1 KB for `Localize.Number.Parser.parse/2`. Each cap is configurable via app env (`:max_locale_id_bytes`, `:max_message_bytes`, `:max_unit_bytes`, `:max_number_bytes`). `Number.Parser.parse/2` additionally rejects `Decimal` results whose exponent magnitude exceeds `:max_decimal_exponent` (default ±100) so downstream multiplication or formatting cannot materialise huge mantissas.

* `Localize.FormatCache` ETS table switched from `:public` to `:protected`; writes are routed through the cache GenServer. The size cap (`:format_cache_max_entries`, default 2 000) is now enforced **synchronously on each insert** rather than by a 10-second sweeper, replacing the previous biased-random eviction that could leave the cache oversized. New `Localize.FormatCache.clear/0` and `size/0` helpers added for tests and maintenance.

* NIF (ICU bindings) hardened. All NIF entries except `nif_plural_rule` now run on the dirty CPU scheduler pool (`ERL_NIF_DIRTY_JOB_CPU_BOUND`); the collator pool is sized for `schedulers + dirty_cpu_schedulers` and `reserve_coll` refuses overflow rather than reading past the array end. The reorder-codes branch caps `numCodes` at 256 and checks `enif_alloc` before use; every `std::stoll`/`std::stod`/`std::stoi` is wrapped in `try/catch` so out-of-range C++ exceptions cannot unwind through the NIF boundary; the hand-rolled JSON arg parser guards each access after `skip_ws`; per-call input lengths are capped at the NIF boundary (`MAX_MF2_BYTES = 64 KB`, `MAX_COLLATION_BYTES = 1 MB`, `MAX_NUMBER_STR_BYTES = 1 KB`).

* `Localize.Unit.CustomRegistry.load_file/1` now refuses to evaluate the file in `:prod` (or any environment without a loaded `Mix` module — typical for releases) unless `config :localize, :allow_runtime_unit_files, true` is explicitly set. Outside `:prod` the function works as before. The flag exists so an unintended feature switch in production cannot accidentally surface arbitrary code execution via `Code.eval_file/1`.

* `:localize_locale_cache` ETS table switched from `:public` to `:protected`, owned by `Localize.Locale.Loader`. Writes are routed through the owner via `cast` (so the hot validate path doesn't block and writes triggered from inside the owner's own `handle_call` cannot deadlock). Reads remain direct ETS lookups. Combined with the format cache fix above, both ETS caches are now `:protected` against multi-tenant or other-library interference.

* `Localize.Utils.Http.get/2` and `get_with_headers/2` now reject responses larger than 50 MB by default (configurable via `:max_http_body_bytes` app env or per-call `:max_body_bytes` option). Without the cap a malicious or compromised CDN could feed a multi-gigabyte response and OOM the BEAM. Oversized responses log an error and return `{:error, :response_too_large}`. Additionally, when peer certificate verification has been disabled (via `LOCALIZE_UNSAFE_HTTPS`), a one-time `Logger.warning` is emitted so a misconfigured production deployment cannot silently downgrade TLS without leaving an audit trail.

## [0.29.0] — May 11th, 2026

### Behaviour Change

* `Localize.Currency.currency_for_code/2` now returns the new `Localize.CurrencyNotLocalizedError` (instead of `UnknownCurrencyError`) when the currency code is valid but the locale has no display data for it. `UnknownCurrencyError` is now reserved for codes that aren't recognised ISO 4217 or registered custom currencies.

### Enhancements

* `Localize.Currency.currency_for_code/2` accepts a new `:fallback` option which walks the CLDR parent locale chain and the application default locale before failing. Thanks to @neilberkman for the PR.

* `Localize.Locale.get/3` accepts a new `:fallback_to_default` option for a final-step fallback after any `:fallback` parent walk. Accepts `true` (use `Localize.default_locale/0`), or an atom/string/`Localize.LanguageTag` for a specific locale.

* Add `:iso_3166` option to `Localize.Territory.territory_codes/1` to return only ISO 3166 codes (not aggregate territories).

## [0.28.0] — May 9th, 2026

### Behaviour Change

* `Localize.Interval.to_string/3` Date intervals (style `:date`, the default) now resolve their skeleton **per-locale** instead of using a hard-coded locale-independent mapping. The interval looks up `Localize.DateTime.Format.date_formats(locale_id)[format]` — the same mapping `Localize.Date.to_string/2` uses — so date intervals follow the same conventions as single dates for the same `:format`. Visible effect on locales whose single-Date skeletons differ from the previous Interval table — most notably:

  - **ja `:medium`** is now numeric (`"2012/01/05～2012/01/06"`), aligning with single Date `:medium` (`"2012/01/05"`); was previously the abbreviated month form `"2012年1月5日～6日"`. The richer Japanese-character form is now `:long` (matching single Date `:long`).
  - **de `:medium`** is now numeric (`"15.01.2022 – 20.03.2022"`); was previously the abbreviated month form. To get `"15. Jan. – 20. März 2022"` request the `:yMMMd` skeleton explicitly.
  - **en `:long`** uses full month name with no weekday (`"January 5, 2012 – January 6, 2012"`); was previously the `:yMMMEd` form `"Thu, Jan 5 – Fri, Jan 6, 2012"`. The weekday now appears at `:full`. Per-locale skeletons that aren't shipped in CLDR's `interval_formats` data fall back to formatting each endpoint with `Localize.Date.to_string/2` and joining via the locale's `interval_format_fallback` template. Non-`:date` styles (`:month`, `:month_and_day`, `:year_and_month`) remain locale-independent — they describe a deliberate field selection unrelated to standard date styles. The static `Localize.Interval.date_styles/0` no longer includes a `:date` entry.

### Bug Fixes

* Strip zone token for NaiveDateTime too in `Localize.Time.to_string/2` since they also do not have a time zone field. Relates to #22.

* Fix `Localize.Interval.to_string/3` silently ignoring the `:date_format` option on Date-only intervals. The option now overrides `:format` on the date axis, mirroring the precedence used for `:time_format` on time intervals. Relates to #22.

* Fix `Localize.Interval.to_string/3` raising `Localize.DateTimeIntervalFormatError` when called with `format: :full` on a Date interval. Relates to #22.

* `Localize.Utils.Math.sqrt/2` now respects the current `Decimal.Context.get/0` precision when called with a `Decimal` — the result is rounded to the configured precision and Newton's-method convergence scales accordingly.

* Added the test suite for `Localize.Utils` that are derived from the `Cldr.Util` equivalents.

## [0.27.0] — May 8th, 2026

### Bug Fixes

* Fix `Localize.Interval.to_string/3` `:short` time-interval format using the wrong hour cycle on 24-hour locales. `:short` now picks `:hm` or `:Hm` per the locale's preferred hour cycle (honouring any `-u-hc-` Unicode-extension override), matching the cycle used by `Localize.Time.to_string/2` `:short`. Thanks to @woylie for the follow-up report. Fixes #22.

* Fix `Localize.Time.to_string/2` silently ignoring the `-u-hc-` Unicode-extension override on the locale. The override now applies to both standard formats (`:short`/`:medium`/`:long`/`:full`) — remapped to the locale's cycle-appropriate `:hm`/`:hms`/`:hmsv` (12-hour, with the locale's AM/PM marker) or `:Hm`/`:Hms`/`:Hmsv` (24-hour) skeleton — and to user-supplied skeleton atoms like `:Hms`, where the hour symbols are substituted.

* Fix zone-field artefacts on `%Time{}` standard formats. A `Time` carries no zone information, so `Localize.Time.to_string/2` now strips zone characters (`z`, `Z`, `O`, `v`, `V`, `x`, `X`) from the resolved skeleton ID before formatting. `Localize.Time.to_string!(~T[21:00:00], format: :long, locale: :ja)` returns `"21:00:00"` (was `"21:00:00 "` — trailing space), and `:es` `:full` returns `"21:00:00"` instead of `"21:00:00 ()"` (parens around the empty zone field).

* Adds support for `Decimal` version 3.0 to address a [CVE](https://github.com/ericmj/decimal/security/advisories/GHSA-rhv4-8758-jx7v). Thanks to @mitchellhenke for the PR.

### Enhancements

* Add `Localize.Time.hour_format_from_locale/1` (and `!/1`) returning the locale's preferred hour cycle (`:h11`/`:h12`/`:h23`/`:h24`), honouring any `-u-hc-` Unicode-extension override.

## [0.26.0] — May 6th, 2026

This release fixes user-reported bug #22 in time interval formatting and a number of RBNF conformance bugs arising from a more complete conformance testing process. The RBNF bugs have been around unreported and undiagnosed for many years.

### Breaking Change

* The default `Localize.Interval.to_string/3` format output (which is `:medium`) for time-only inputs now includes seconds. `Localize.Interval.to_string!(~T[12:00:00], ~T[14:00:00], locale: :ja)` shifts from `午後0時00分～2時00分` to `12:00:00～14:00:00`. `:en`'s `:medium` shifts from `12:00 – 2:00 PM` to `12:00:00 PM – 2:00:00 PM`. Users who relied on no-seconds output should explicitly pass time_format: `:short`.

### Bug Fixes

* Fix `Localize.Interval.to_string/3` collapsing the `:short`, `:medium`, `:long`, and `:full` time styles to the same `:hm` skeleton on Time inputs. `:short` keeps CLDR's interval-format dispatch (collapsed AM/PM); `:medium` and above route through the locale's per-style time-format pattern, restoring per-style differentiation and including seconds in the default `:medium` output. Thanks to @woylie for the report. Fixes #22.

* Fix `:time_format` being silently ignored on `Localize.Interval.to_string/3` for Time inputs. The option now takes precedence over `:format`, matching the precedence used on datetime intervals. Thanks to @woylie for the report. Fixes #22.

* Fix `Localize.Interval.to_string/3` crashing with `FunctionClauseError` when called with a binary `:format` (or `:time_format`) on Time inputs. Binary patterns are now applied to both endpoints and joined via the locale's interval-format fallback template, matching the behaviour of datetime intervals. Thanks to @woylie for the report. Fixes #22.

* RBNF parser now distinguishes `>>` from `>>>` so CJK locales emit fractional digits without an inter-digit separator — `Localize.Number.Rbnf.to_string(3.14, "spellout-numbering", locale: :zh)` is `三点一四` instead of `三点一 四`.

* RBNF leading and embedded zeros in fractional digits, and very small magnitudes, are now preserved — `0.05 en` is `"zero point zero five"`, `3.04 zh` is `三点〇四`, and `0.000001 en` is `"zero point zero zero zero zero zero one"`.

* RBNF `0.x` special-base rule now matches when the integer part is zero and the value is non-zero, routing ko `0.5 spellout-numbering` through its locale-correct sino-Korean `영점오` instead of the previous `x.x`-fallback `공점공오`.

* RBNF negative floats no longer double their output or silently drop the sign — ko `-0.5 spellout-numbering` is `-영점오` instead of `공점공점오`, and locales that lack a `-x` rule now get an ASCII `-` prefix.

* RBNF integer `<#,##0<` quotient and float `>%name>` / `>#,##0>` / `<%name<` modulo and quotient no longer crash, completing case-clause coverage for every TR35 substitution-argument shape.

* RBNF `$(cardinal,…)` and `$(ordinal,…)` plural-keyed substitutions now use the requested locale's plural rules instead of hard-coding English — fr `Localize.Number.Rbnf.to_string(21, "digits-ordinal-masculine", locale: :fr)` is `"21e"` instead of `"21er"`.

* RBNF fraction-with-rule numerator/denominator algorithm is now spec-correct — ky `1.5 spellout-cardinal` is `бир бүтүн ондон беш` instead of `бир бүтүн беш`.

### Enhancements

* Add `:minimum_significant_digits` and `:maximum_significant_digits` options to `Localize.Number.to_string/2`.

* `Localize.Number.Rbnf.to_string/3` now accepts `Decimal` inputs in addition to native integers and floats, with whole-valued Decimals routed through the integer path with no precision loss.

* RBNF `>>>` integer modulo now applies the source-preceding rule per TR35 §RBNF_Syntax, closing a latent gap; no current CLDR locale exercises this path.

## [0.25.0] — May 1st, 2026

### Bug Fixes

* Fix en-CA :short date crash; teach :prefer about CLDR variant/standard alts. Thanks to @dabaer for the report. Closes #21.

### Enhancements

* Module refactoring to remove many compile-time cycles.

## [0.24.0] — April 29th, 2026

### Bug Fixes

* `Localize.DateTime.Formatter` stand-alone pattern helpers now pass `context: :stand_alone` to `Localize.Calendar.localize/3` instead of an invalid `type:` option. Thanks to @timpritlove for the PR. Closes #20.

* Rename calendar `:format`/`:stand_alone` typespec and docs from `:type` to `:context`.

* Clarify `Unit.display_name/2` vs `to_string/2` in docs.

## [0.23.0] — April 25th, 2026

### Bug Fixes

* Fix `Cldr.Number.to_string/2` for `Decimal` numbers to produce the correct decimal digits.

* Fix `LOCALIZE_UNSAFE_HTTPS` env-var contract — values like `"FALSE"`, `"nil"`, an empty string, or unset all keep TLS verification on; only a truthy value disables it. Thanks to @rubas for the PR. Closes #15.

* Fix `Localize.Locale.load/2` and `Localize.Locale.get/3` to honor the `:provider` option — `load/2` no longer calls `provider.store/2` with the locale id, and `get/3` now loads through the same provider it reads from. Thanks to @rubas for the PR. Closes #16.

* `Localize.Locale.get/3` now honors the `:fallback` option by walking the CLDR parent locale chain when a key is missing in the requested locale. Fallback is handled in `Localize.Locale` so provider modules stay focused on store-and-fetch semantics. Thanks to @rubas for the PR. Closes #17.

* Public formatters (`Localize.Date`, `Localize.Time`, `Localize.DateTime`, `Localize.DateTime.Relative`, `Localize.Interval`, `Localize.List`, `Localize.Calendar`) now accept raw parsed `Localize.LanguageTag` structs whose `:cldr_locale_id` is not yet populated. The seven per-module locale resolvers collapse to one shared `Localize.Locale.cldr_locale_id_from/1`. Thanks to @rubas for the PR. Closes #18.

* Fix `Localize.available_locale_id?/1`, `Localize.validate_calendar/1`, and `Localize.validate_number_system/1` to never intern caller-supplied strings as new atoms. Lookups now use compile-time string→atom maps for O(1) safe membership. Thanks to @rubas for the PR. Closes #19.

* `Localize.supported_locales/0` now lazily resolves `config :localize, supported_locales: [...]` from the application environment when the `:persistent_term` cache has not yet been populated, instead of falling back to the full CLDR locale list. The cache is populated on application startup, but callers that run before the application has started — notably compile-time macro expansion in dependent applications like `localize_web`'s `~q` sigil — previously saw the full CLDR list during partial recompiles. This caused `Localize.validate_locale/1` to best-match against all CLDR locales rather than the configured subset, producing incorrect `cldr_locale_id` resolutions.

## [0.22.0] — April 22nd, 2026

### Bug Fixes

* Fix Cldr.Number.to_string/2 for Decimal numbers to produce the correct decimal digits.

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
