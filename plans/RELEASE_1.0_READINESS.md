# Localize 1.0 Readiness Report

Date: July 4, 2026. Baseline: v0.41.3 (commit fd352f1b), CLDR 48.2.1, Elixir 1.20.1-otp-29. Method: Credo 1.7 strict, `mix test --cover`, AST-based doc audit, and four deep reviews (security, TR35 conformance, documentation, API surface) with all findings verified against source.

## Executive summary

The library is in genuinely strong shape for a pre-1.0: zero critical/high security findings, uniformly applied error conventions, 100% moduledoc / 98% @doc / 92% @spec coverage, and real CLDR data-driven conformance suites at the identifier layer. The gaps cluster in five places: (1) two release-engineering bugs that break hex consumers (NIF source not packaged, publish-machine-dependent json_polyfill dep), (2) five concrete TR35 nonconformances in the formatting layer (compact-number plurals worst), (3) API-surface decisions that freeze at 1.0 (known_/available_ semantics, ~30 internal modules with public docs, option-name divergences), (4) a conformance guide that overstates day-period support, and (5) test coverage that is solid at the identifier layer but thin in the formatting engines (DateTime.Formatter 36%, Unit.Formatter 48%) and near-zero in the download path (Utils.Http 14%).

Recommended sequence: fix the consumer-breaking packaging bugs and TR35 formatting bugs first (they are bugs regardless of 1.0), then make the API-freeze decisions (renames/hiding — the most disruptive, so before any RC), then drive coverage and docs depth, then RC.

---

## 1. Security and robustness

Verdict: **good**. 0 critical, 0 high. TLS is properly hardened (verify_peer, pinned ciphers, hostname check), parsers are input-capped (1KB number parse, bounded Decimal exponents, MF2 byte cap), atom creation is validity-gated, and the C++ NIF boundary is defensively written (capped strings, badarg on bad input, no exception unwind into the BEAM).

Findings to fix:

| # | Finding | Where | Severity |
|---|---|---|---|
| S1 | Downloaded ETF decoded with `binary_to_term` (no integrity check beyond TLS). Add SHA-256 manifest verification before decode; `:safe` is impractical for atom-bearing locale data. | provider/persistent_term.ex:74, provider.ex:504-621 | Med |
| S2 | Corrupt/truncated cache file raises `ArgumentError` instead of being treated as a cache miss. Wrap both decodes. | provider/cache.ex:104, 205 | Med |
| S3 | Cache writes are not atomic; a mid-write crash leaves a torn file (the input to S2). Write temp + `File.rename/2`. | provider/cache.ex:162-178 | Med |
| S4 | httpc follows redirects to arbitrary hosts; the CDN URL is versioned and known. Set `autoredirect: false`. | utils/http.ex:247 | Low/Med |
| S5 | Unbounded `String.to_atom` on the user-supplied `:usage` option — the one path the 0.30.0 atom-hardening pass missed. Use `Helpers.existing_atom/1`. | unit/preference.ex:173 | Low/Med |
| S6 | `Utils.Map.atomize_keys` and `Utils.Json.decode!(keys: :atoms)` default to unbounded atom creation. Flip default to `only_existing: true` (moot if Utils goes internal, see §7). | utils/map.ex:398, utils/json.ex:56 | Low |
| S7 | Locale id interpolated into cache file path without shape validation (defense-in-depth; not currently reachable with unvalidated input). | provider.ex:527, cache.ex:47 | Low |

## 2. Code consistency, clarity, complexity (Credo)

Credo strict: 628 findings, but the number overstates. Composition: 353 are one check (nested-module aliasing — a single style-policy decision to adopt or disable), 63 deep-nesting sites, ~15 functions over complexity 9, 38 number-literal underscores, 22 `Enum.map |> Enum.join` → `map_join`, 19 redundant `with` clauses, 16 `apply/2,3` with known arity, 15 `Logger` metadata `domain` not declared in Logger config (one config line), 10 `length/1` on emptiness checks, 3 consistency nits.

Hotspot files: unit.ex (38), datetime.ex (16), message/interpreter.ex (14), time.ex/interval.ex/date.ex (13 each), language_tag.ex (12).

Actions: commit a `.credo.exs` that encodes house policy (decide the alias-nesting question once; disable or accept), fix the mechanical categories (map_join, length/1, underscores, redundant with — ~90 sites, low risk), add the Logger `domain` metadata config, then burn down deep-nesting/complexity in the hotspot files opportunistically. Add `mix credo --strict` to CI lint once clean.

## 3. Locale validation in public APIs

Verdict: **done** (this was the focus of recent releases). The audit of ~146 public locale-accepting functions found all now route through `Localize.validate_locale/1` or `Localize.Locale.cldr_locale_id_from/1` (which validates internally). Remaining, both deliberate deferrals:

* NIF-backend branches pass the raw locale string to ICU (number.ex, plural_rule.ex:105, unit/formatter.ex:37, message.ex nif path). Decide policy: validate-then-hand-canonical-id to ICU (backend parity), or document ICU as the resolver on that path. Recommendation: validate first — cheap, and makes `backend: :nif` behaviourally identical.

* `Collation.Tailoring.LocaleDefaults` helpers are public-doc'd but operate on raw strings; callers now pass validated values. Resolve by making the module internal (§7 hiding pass).

## 4. TR35 spec conformance

Identifier layer is genuinely strong (real CLDR test files, zero-skip: canonicalization 1,774 cases, likely subtags 1,802, matching/distance, display names, root collation at zero-failure thresholds). The formatting layer has five concrete nonconformances, all in paths the data-driven suites don't reach:

| # | Nonconformance | Where | User impact |
|---|---|---|---|
| C1 | Compact-number plural selection: pluralizes unrounded mantissa, never sets the `e` operand; the `{number, e}` plural clauses are dead code and compute `i` wrongly. es 1.2M → "1 millones" (impossible Spanish). | number/formatter/short.ex:179-193, cardinal.ex:219-307 | High — visibly wrong output |
| C2 | Flexible day periods: `B`/`b` are AM/PM stubs; no dayPeriods rule data in the pipeline. Guide claims Implemented — factually wrong today. | datetime/formatter.ex:581-596 | Med |
| C3 | Week fields `w`/`Y` always ISO; `W` not even ISO-correct; locale firstDay/minDays data exists but is never consulted. 2023-01-01 en-US `w` → "52" (CLDR: "1"). | datetime/formatter.ex:326-341, 451-470 | Med |
| C4 | Era-relative year for BC dates: year −1 → "-1 BC" (should be "2 BC"). Calendar.ISO wrongly excluded from `year_of_era`. | datetime/formatter.ex:304-321 | Med |
| C5 | Multi-replacement territory aliases take first entry instead of TR35 Annex C likely-subtags disambiguation: `hy-SU` → `hy-RU` (should be `hy-AM`). | language_tag.ex:1240-1252 | Low/Med |
| C6 | Significant digits force min-1 fraction on float input: 1234.567 @ 3 sig → "1,230.0" (ICU: "1,230"). | number/formatter/decimal.ex:914-916 | Low |

Test-wiring gaps (cheap wins): rbnf de/fr/es reference data vendored but dark (`@test_locales ["en"]`); `icu_test_cases.txt` (25KB) vendored, no test consumes it; MF2 conformance is syntax-only (vendor the WG `tests/functions/*.json` + data-model-errors to test the formatter, not just the parser); likely-subtags FAIL rows skipped rather than asserted; favor-region removal parsed but untested/unimplemented.

Guide correction (do immediately, independent of fixes): `guides/conformance.md` rows for "Day periods" and "Day period rules" claim Implemented; downgrade until C2 lands. Refresh the stale known-failures comment in collation/conformance_test.exs:7-13.

## 5. Documentation completeness

Baseline (AST-audited): 192 modules — 0 missing moduledoc. 759 public function heads — 13 missing @doc (98.3%), 60 missing @spec (92%). Template census: Returns 86%, Arguments 86%, Examples 62%, Options 53% of options-taking functions.

Remediation, in effort order:

* (S) Wire `doctest` for 6 modules with Examples but no doctest (Collation.Table.Parser, Locale.Provider, Provider.Cache, Message.JSON, ParseError, Unit.Preference) — doc-rot protection.
* (S) 13 missing @doc — `Number.to_range_string/3,!/3` are the user-facing ones; several others should be `@doc false`.
* (S) README feature list omits shipped features: durations, relative time, plural rules, RBNF/spellout, number parsing, scripts. Fix "Its" typo (line 122).
* (S) CHANGELOG: standardize on Keep-a-Changelog section names (Added/Changed/Fixed/Removed) — history uses "Bug Fixes"/"Enhancements".
* (M) 7 modules in no docs group (land in ex_doc misc): Localize, DataLoader, Exception, FormatCache, Substitution, Supervisor, the mix task. Several resolve via the §7 hiding pass.
* (M) 60 missing @spec — over half in Utils.* (moot if hidden); PluralRule.Cardinal/Ordinal first.
* (M) `### Options` sections for the 60 gaps (Number 6, Message 5, List 3…).
* (L) `### Examples` for ~216 functions — triage user-facing first (Currency 17, Number.System 9, Number.Format 9).
* (L) New guides: plural rules, list formatting, locale validation/matching + `-u-` extensions; a display-names guide (Territory/Language/Script/LocaleDisplay).

## 6. Test coverage (target ≥90%)

Raw `mix test --cover`: **37.95%** — misleading. Decomposition of 268 measured modules: 73 below 25% (37 of them build-time tooling: `Localize.Data.*` normalizers, mix tasks, compile-time parser generators that cover cannot see), 21 at 25–50%, 60 at 50–75%, 55 at 75–90%, 59 at ≥90%.

Plan to make the number meaningful, then raise it:

1. Configure `test_coverage: [ignore_modules: [...]]` in mix.exs for the data pipeline (`Localize.Data.*`), mix tasks, compile-time-only modules (parser combinators, PluralRule.Loader/Transformer, rbnf_lexer, Macros, Rfc5646 grammar), and generated protocol impls. Re-baseline: the honest runtime number is likely ~55–65%.
2. Close the real runtime gaps, priority order: DateTime.Formatter 36% (core engine; the C2–C4 fixes come with tests), Unit.Formatter 48%, Utils.Http 14% (download path — also the S1–S4 security surface; needs a local-server or Bypass-style test), Timezone.Builder 0%, Collation.FastLatin 18%, Message.JSON 0%, Number.Parser 65%, exception `message/1` rendering (most exceptions untested → gettext msgid drift risk).
3. Wire the dark conformance data (§4) — rbnf ×3 locales and the ICU number cases add real coverage cheaply.
4. Set the CI threshold at the re-baselined honest number and ratchet upward; 90% on runtime modules is achievable, 90% raw including tooling is not meaningful.

## 7. API surface and release hygiene (freezes at 1.0)

Blockers — decide/fix before any RC:

* B1 **NIF not buildable from hex**: `c_src/` absent from package files while `LOCALIZE_NIF=true` is documented. Add `c_src/Makefile`, `c_src/*.cpp`, headers (exclude `*.o`), or document NIF as git-only.
* B2 **json_polyfill dep resolved on the publishing machine**: publishing from OTP ≥ 27 drops it from the package while README promises OTP 26. Make it `optional: true` unconditionally, or raise the floor to OTP 27 and delete the polyfill path.
* B3 **`Unit.to_string(format:)` vs `Duration.to_string(style:)`** — same concept, same values, different key. Unify on `:format` (matches Date/Time/DateTime/Number); Duration's separate `:format` pattern-string in `to_time_string/2` needs care.
* B4 **known_/available_ semantics**: `known_*` is CLDR-global in Currency/Calendar/Unit/List but locale-dependent in Language/Script; `available_*` means three unrelated things. Reserve `known_*` = global; use the existing `X_for(locale)` pattern for per-locale (e.g. `languages_for/1`, `language_names_for/1`); `Territory.available_styles` → `known_styles`. Add public `Territory.known_territories/0` (currently only on hidden SupplementalData).
* B5 **Internal-module hiding pass** (~30 modules): Utils.* (all but Code), DataLoader, Substitution, FormatCache, Collation internals (keep Options — it appears in public specs), and verify Locale.Loader, List.Pattern, Number.Format.Meta, LanguageTag.Parser, Message.Interpreter. Keep public: Nif, Chars, Locale.Provider(+PersistentTerm), Message.Function/Formatter.Plugin/JSON, Unit.Math/Preference/Operators/Parser/CustomRegistry, Number.Format.Options/Compiler, LocaleDisplay. Fix the inverse defect: guides/conformance.md references `@moduledoc false` SupplementalData and Validity.

Should-fix: Language/Script `display_name` raise on bad options but tuple on bad locale (and @spec omits the raise) — return `{:error, %InvalidValueError{}}`; `Localize.quote/2` silently accepts unknown `:style` (worst of the three inconsistent enum-option behaviors) and uses `:style` while `ellipsis/2` uses `:format` in the same module; 5 missing bang variants (`Number.to_at_least_string!`/`to_at_most_string!`/`to_approximately_string!`, `Calendar.display_name!`, `Unit.display_name!`); `Currency.currencies_for_locale/3` positional filter args → options; `Localize.validate_currency/1` delegate (only validator not on the top module); hex package links → hexdocs URLs; Nif moduledoc "functions will be added" instability wording.

Nice-to-have: document Collation's deliberate bare-return deviation; `:list_style` rationale; parse/new/validate_locale "which one" table in public docs; drop dead `max_variable_primary` field; remove stray `c_src/localize_nif.o`; tidy `src/*xrl` glob and redundant `.etf` entry.

Confirmed good: zero TODO/FIXME/@deprecated in lib; exception convention uniform (41 files, one behaviour); option vocabulary otherwise consistent (`:locale` everywhere, no `opts`); extension points (Chars, Provider, Message.Function, Formatter.Plugin) well-designed; elixir floor `~> 1.17` correct; bench deps don't leak.

---

## The plan

### Milestone 1 — Bugs and consumer breakage (independent of 1.0; ship as 0.42.x)

1. B1 NIF packaging, B2 json_polyfill/OTP-26 (release engineering; test by publishing to a local hex or `mix hex.build` + unpack).
2. C1 compact-number plurals (fix short.ex plural key + the `{number, e}` operand clauses; wire the CLDR `c`-suffixed samples as regression).
3. C4 BC-year era fix, C6 significant-digits trailing zero (small, isolated).
4. S2+S3 cache robustness (rescue decode + atomic write), S4 autoredirect off, S5 usage-option atom.
5. Guide truthfulness: downgrade day-period rows in conformance.md; stale comment cleanup.

### Milestone 2 — API freeze decisions (the disruptive renames; one minor release, loud changelog)

6. B4 known_/available_ renames (with deprecated delegates for one release), B3 Unit/Duration option unification, B5 hiding pass (+ docs-group cleanup, guide reference fixes).
7. Error-shape policy: validators return tuples not raises; fix `quote/2` silent fallback and `:style`→`:format`; add the 5 bang variants; `validate_currency` delegate; Currency positional args.
8. NIF-branch locale validation (close the last §3 deferral); LocaleDefaults goes internal with B5.

### Milestone 3 — Conformance and coverage depth — DONE (July 4, 2026)

9. ~~C2 day periods and C3 week fields~~ — done: B/b select from the CLDR day-period rules (data in the supplemental pipeline); w/Y/W honour locale firstDay/minDays. ICU-verified.
10. ~~C5 alias disambiguation~~ — done per Annex C with SU/YU/CS tests.
11. Coverage: ignore_modules re-baseline done (honest runtime baseline 70.42%); rbnf de/es/fr wired (found and fixed the RBNF process-locale separator bug); likely-subtags FAIL rows asserted (found and fixed the und-fallback fabrication for private-use languages); unwired icu_test_cases.txt deleted — re-vendor with a dedicated harness is an M4 candidate alongside the MF2 formatter suite and the DateTime.Formatter / Unit.Formatter / Utils.Http coverage push.
12. ~~S1 download integrity~~ — done as Option C: SHA-256 manifest bundled in the package (`priv/localize/locale_hashes.etf` via `mix localize.generate_locale_hashes`), verified in `download_locale/1` before decode and cache write; fail-closed with `LocaleIntegrityError` when the manifest is present, warn-once transitional when absent. Add manifest generation to the release checklist.
13. Bonus from this sprint: `LanguageTag.U.parse/1`/`parse!/1` public entry point (for Tempo); `Validity.U` encode prefers non-deprecated BCP 47 spellings and decode accepts atom keys + hyphenated calendar values (needs validity data regen); wrong-language locale resolution now falls back to root instead of the nearest wrong language.

### Milestone 4 — Polish and RC

13. Credo: .credo.exs policy, mechanical fixes, Logger domain config, hotspot refactors; add to CI.
14. Docs depth: doctest wiring, missing @doc/@spec, Options/Examples backfill, README feature list, CHANGELOG normalization, new guides (plurals, lists, locale matching, display names).
15. Full release review per house checklist; 1.0.0-rc.1; soak; 1.0.0.

### Scheduled: drop OTP 26 support on December 31st, 2026 (announced)

On or after 2026-12-31: remove `maybe_json_polyfill/0` from mix.exs; remove the three OTP 26 rows from the CI matrix; update the README supported-versions section to OTP 27+ and delete the json_polyfill consumer instructions; remove (or downgrade) the supervisor `ensure_json_module!` check; changelog entry. Until then the `only: [:dev, :test]` json_polyfill conditional stays so OTP 26 CI compiles warning-free. This coincides with the removal window for the deprecated `known_/available_` delegates ("no later than December 2026").

Sizing (rough): M1 ≈ days; M2 ≈ days but decision-heavy; M3 ≈ the long pole (day periods + week fields + coverage are real builds); M4 ≈ steady background work. The only item needing genuine design discussion before work starts is S1 (integrity manifest) and the B4 naming scheme.
