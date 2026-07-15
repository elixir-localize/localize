# Localize 1.0 Readiness — Fresh Assessment

Date: July 15, 2026. Baseline: v0.49.0 + unreleased (commit 8c4235d7), Elixir 1.20.1-otp-29 / Erlang 29.0.1. Method: full quality-gate run, `mix hex.build` package inspection, and four verification passes (API freeze, API hygiene/security, documentation, test wiring) re-checking every item in the July 4 plan (`RELEASE_1.0_READINESS.md`) against current source.

## Executive summary

The July 4 plan is almost entirely executed. Milestones 1–3 are done and verified: all six TR35 nonconformances (C1–C6) fixed, all consumer-breaking packaging bugs (B1/B2) fixed and verified in the built hex tarball, security items S1–S6 resolved, the API-freeze renames (B3/B4) shipped in 0.43.0 with deprecated delegates, and the hiding pass (B5) applied. All five quality gates pass clean and coverage is 91.23% (gated at Mix's default 90% threshold on the CI lint row). What remains before an RC is one API decision, four visibility-deviation confirmations, one genuine test gap (the download happy path), a handful of doc nits, and the `localize_mcp` release plumbing.

## Quality gates (July 15, Elixir 1.20.1-otp-29)

| Gate | Result |
|---|---|
| `mix format --check-formatted` | ✅ clean |
| `mix compile --warnings-as-errors` | ✅ clean |
| `mix test --cover` | ✅ 29,069 passed (945 doctests, 17 properties), 0 failures, 2 excluded; coverage 91.23% |
| `mix dialyzer` | ✅ Total errors: 0 |
| `MIX_ENV=release mix docs` | ✅ no localize-owned doc warnings (deps emit their own; see nits) |

`mix hex.build`: 264 files; `c_src/Makefile`, `c_src/env.mk`, `c_src/localize_nif.cpp` present (B1 verified at the artifact level), no stray `.o` files, `priv/localize/locale_hashes.etf` integrity manifest bundled (S1 verified), Elixir floor `~> 1.17` retained.

## Verified done since the July 4 baseline

* **C1–C6 conformance fixes** — shipped across 0.42.0–0.44.0 (compact plurals + operands, BCE era years, significant digits, day periods, locale week configuration, Annex C alias disambiguation).

* **B1 NIF packaging** — fixed and verified in the tarball. **B2 json_polyfill** — resolved by policy: `only: [:dev, :test]` stays until the announced OTP 26 drop on December 31, 2026.

* **B3 option unification** — `Unit.to_string` and `Duration.to_string` both take `:format`; `:style` is a documented deprecated alias on Duration ("removed by Localize 1.0"). `Unit.display_name` and `Localize.quote/2` settled on the naming-vs-formatting split (0.43.0).

* **B4 known_/available_ semantics** — implemented in 0.43.0: `known_*` = locale-independent universe, `supported_*` = configuration, `*_for` = localized inventories. Deprecated delegates in place for every renamed function (removal window "no later than December 2026"). `Territory.known_styles/0` and public `Territory.known_territories/0` exist.

* **B5 hiding pass** — all `Localize.Utils.*`, `DataLoader`, `Substitution`, `FormatCache`, `Locale.Loader`, `LanguageTag.Parser`, `Message.Interpreter`, `LocaleDefaults`, `SupplementalData`, `Validity` are `@moduledoc false`; the keep-public list is public; `guides/conformance.md` no longer references hidden modules; the ex_doc group map covers everything except the bare `Localize` module (conventional).

* **Error-shape policy** — Language/Script `display_name` return `{:error, %InvalidValueError{}}` on bad options; `Localize.quote/2` errors on unknown format; all 5 missing bang variants exist; `Localize.validate_currency/1` delegate exists (all 0.43.0).

* **Security** — S1 hash manifest (0.44.0, fail-closed with `LocaleIntegrityError`); S2 corrupt cache decode → miss/stale at both sites; S3 atomic write-temp-then-rename; S4 `autoredirect: false`; S5 `existing_atom` for `:usage`; S6 resolved via Utils modules going internal. NIF-backend locale validation closed (0.43.0).

* **Docs** — all four planned guides exist (plural_rules, list_formatting, locale_validation, display_names); README feature list complete, install snippet hex-correct, all guide links hexdocs; CHANGELOG fully Keep-a-Changelog; `to_range_string/3` and `!/3` documented; doctests wired for 5 of the 6 flagged modules; conformance.md day-period rows accurate; collation known-failures comment refreshed to zero-threshold reality; `usage-rules.md` spot-checked accurate.

* **Test wiring** — RBNF reference data exercised for en/de/es/fr; MF2 working-group suite runs against the formatter (with documented exclusion groups); likely-subtags FAIL rows asserted with zero skips; every exception module's `message/1` exercised, multi-reason exceptions enumerated per reason atom (gettext msgid-drift guard); coverage ignore-list guarded against orphaned entries; OTP 26 CI rows present pending the December drop.

* **Credo strict** — zero findings, enforced in CI (0.45.0).

## Remaining before RC

### A. API decisions (freeze at 1.0)

1. **`Currency.currencies_for_locale/3` and `!/3` positional filter args** — DONE July 15, including `currency_strings/3` and `!/3` which shared the pattern. All four take `:only` / `:except` options; the positional arity-3 forms remain as `@deprecated` delegates (house message, removal by 1.0 / December 2026) and a positional second argument warns at runtime via `IO.warn`. Note a bare `is_list/1` guard could not discriminate the forms because a `filter()` may itself be a list (`[:current, :ZWR]`) — discrimination is by keyword shape (`[{atom, _} | _]`), with a plain list still treated as a positional `:only` filter.

2. **Four deviations from the frozen B5 visibility list** — RESOLVED July 15. Three confirmed correct: `List.Pattern` public (its struct is documented API in `Localize.List`), `Number.Format.Meta` public (its type appears in the public `Format.Compiler` specs), `Utils.Code` hidden (nothing public references it). One was wrong: `Number.Format.Options` was hidden while `validate_options/2` is a documented performance idiom in the Performance guide, the number cheatsheet and usage-rules.md — its moduledoc is restored and its doctest wired.

3. **Deprecated-delegate removal timing** — Duration `:style` says "removed by Localize 1.0"; the B4 delegates say "no later than December 2026". If 1.0 ships before December, decide whether 1.0 removes all of them in one breaking sweep (cleanest) or carries them to a 1.1.

### B. Test gaps

4. **`Provider.download_locale/1` happy path has no end-to-end test.** — DONE July 15: `test/localize/locale/download_test.exs` drives HTTP 200 → integrity verify → cache write → read-back against a local `:httpd` server, plus 404, tampered-content and missing-manifest-entry failure paths. Required a `:locale_base_url` config seam in `Provider.base_url/0` (also useful for self-hosted mirrors).

5. **MF2 formatter conformance exclusion groups** — CLOSED July 15 (second pass): the error-strictness gaps are implemented (unknown-function errors, duplicate declaration/option/variant data-model validation with NFC keys, literal-only `select`, digit-size and number-literal validation, non-selectable functions rejected as selectors — new `FormatError` reasons `:duplicate_declaration`, `:duplicate_option_name`, `:duplicate_variant`, `:unknown_function`), and the WG `:test:*` registry functions are implemented so the suite's selection cases run. Remaining exclusions are the additive bucket only: re-annotation binding, `u:dir`/`u:id` options, bidi default strategy, `signDisplay`, implicit locale-aware number formatting.

6. **Favor-region column parsed but never asserted** — DONE July 15: `remove_likely_subtags/2` accepts `favor: :script | :region` and the RemoveFavorRegion column is asserted across the full CLDR test file (~1,800 cases).

### C. Documentation nits

7. **`Message.JSON.from_json/1` docstring example is wrong** — DONE July 15. The example had in fact already been corrected; only the doctest was still unwired and the test comment stale. `doctest Localize.Message.JSON` is now enabled and passing.

8. **Collation's bare-return deviation** — DONE July 15: the `Localize.Collation` moduledoc now has a "Return value convention" section explaining the bare returns and that unrecognised option values fall back to defaults (verified: they do not raise).

9. **README has no MCP section.** The skill is documented; `localize_mcp` (complete, 52 tests passing, 11 tools) is unpublished and unmentioned. Once it's on hex, add a section beside the skill one.

### D. Mechanical nits

10. ~~`mix.exs` deprecated `xref: [exclude: ...]` shape~~ — WITHDRAWN July 15: the warning in the gates log came from compiling the `earmark_parser` dep in the docs stage; localize's own mix.exs has no `xref` key and a fresh release-env compile is clean.

11. Two always-true type warnings in `test/localize/unit/data_test.exs` — DONE July 15 (`refute Enum.empty?(...)`).

12. `.github/workflows/upload-locales.yml` cache key — DONE July 15: OTP/Elixir pins moved to workflow `env` and included in the cache key and restore-keys.

13. S7 locale-id shape validation — DONE July 15: `Provider.locale_file_name/1` (the single choke point for both cache paths and download URLs) raises `ArgumentError` unless the id matches `^[A-Za-z0-9_-]+$`, with tests for traversal-shaped atoms.

## Companion deliverables

* **Claude Code skill** — shipped in 0.47.0, committed, README-documented, marketplace manifest in place. Done.

* **`localize_mcp`** — RELEASED July 15: 0.1.0 published to hex after a full release review. The review found and fixed release blockers: the hermes_mcp stdio transport was broken (migrated to anubis_mcp 1.6, Elixir 1.18 floor), logs polluted the protocol stdout (redirected to stderr), and the escript/archive channel could not work (`Application.app_dir` fails inside archives — removed; the hex dep + `mix localize_mcp` is the supported channel). Verified end-to-end over live stdio JSON-RPC; docs cover Claude Code, Claude Desktop, Codex CLI, ChatGPT and Zed; CI added; tracks localize 0.50 with an execution-verified examples runner; cross-linked from the localize README.

## Suggested order

Updated July 15 (second pass): items 1, 2, 4, 5, 6, 7, 8, and 10–13 are all done as annotated above. Remaining:

1. Item 3 — delegate removal timing: decide whether 1.0 removes all deprecated delegates (the known_/available_ set, Duration `:style`, and the new Currency positional forms) in one sweep or carries them to a later release. All messages promise removal by 1.0 and no later than December 2026.
2. The MF2 additive bucket — mostly CLOSED July 15 (third pass): `signDisplay` on all numeric functions, implicit locale-aware `:number` formatting of unannotated numeric operands, and re-annotation of declared variables (pattern expressions operate on the declaration's original value with numeric option inheritance). Remaining: `u:dir`/`u:id` expression options and the WG-default bidi strategy (five excluded suite cases in total).
3. ~~Item 9 — `localize_mcp` release~~ — DONE July 15: 0.1.0 on hex, README MCP section published.
4. Full house release review; 1.0.0-rc.1; soak; 1.0.0.

Nothing found in this pass contradicts the stability-period intent: items 1–3 are decisions plus small diffs, and everything else is additive tests/docs.
