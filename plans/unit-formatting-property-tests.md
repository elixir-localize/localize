# Plan: Unit formatting property tests (ICU differential + invariants)

Status: DONE. Layer 1 = `test/localize/unit/formatter_property_test.exs` (3 properties, gates CI). Layer 2 = differential property added to `test/localize/unit/nif_cross_validation_test.exs`, tagged `:nif_differential` and excluded by default in `test/test_helper.exs` (run with `mix test --include nif_differential`). Both green across multiple seeds; full suite 31,227 pass, credo/format clean.

## Findings from the discovery/triage pass

1. **Per-compound formatter fell back to English — FIXED.** When a per-compound's denominator had no `per_unit_pattern`, the path emitted hardcoded English `"per <denominator>"` with the untranslated denominator (`yard-per-millimeter` pl → `"5 jardów per millimeter"` vs ICU `"5 jardów na milimetr"`; ~50% of random common-unit per-pairs). Fixed in `formatter.ex`: `format_per_denominator` now routes the no-`per_unit_pattern` case through `compose_per_compound`, which combines the numerator with the localized denominator noun via the locale `compound.per.compound_unit_pattern`. A second fix made `denominator_nouns` fall back `:one`→`:other` for no-plural locales (zh/ja), which had left the denominator in English. Result: per-compound divergence 0/1680 (was ~50%).
2. **`-person` units rendered raw — FIXED.** `year/month/week/day-person` are single CLDR units (the parser handles them atomically — the earlier "parser splits them" diagnosis was wrong) but carry no display data; ICU shows them as their base (`year-person`→"years"). Fixed in `formatter.ex`: `find_unit_formats` now strips a trailing recognized suffix component (`unitIdComponent type="suffix"`, e.g. `-person`) and retries against the base, and treats a metadata-only entry (`%{gender: …}`, present for `day-person` in es/it/ar) as a miss so the fallback fires. Result: `-person` divergence 0/144. Round-trip property excludes them (they display identically to their base, so parse is legitimately ambiguous). Still open: `dot`, `percent`, `permille` diverge in some locales — separate, smaller.
3. **Version skew is real but tiny for common units.** Common base units match ICU 100%; the only curated-compound skew is `tonne-kilometer` in es/ar/zh (accent / plural-form / 公里-vs-千米), all data-version, all quarantined. See memory `nif-uses-system-icu-version-skew`.

Both fixes are locked in as regression guards: the differential pool in `nif_cross_validation_test.exs` now includes the `-person` units and runtime-composed per-compounds.

---

Original plan below (retained for reference).

## Goal

Add property-based tests for `Localize.Unit` formatting — especially **compound units** (times and per) — to close the gap left by CLDR conformance data. CLDR ships conformance vectors only for unit *conversion* and *preferences* (`common/testData/units/{unitsTest,unitPreferencesTest,unitLocalePreferencesTest}.txt`), never for *formatting* or *parsing*. That gap is why #42 (symbol parsing) and #43 (times-compound formatting) reached 1.0-rc.4 uncaught. This harness is the pre-1.0-final confidence booster.

## Key constraint (drives the whole design)

The NIF is **system ICU (icu4c@78 ≈ CLDR 48)**, version-skewed from the project's pinned **CLDR 48.2**. A naive `assert elixir == icu` WILL flake on data-version differences (not algorithm bugs). Confirmed skew cases at time of writing:

* `es` long `tonne-kilometer`: elixir `"5 tonelada-kilómetros"` vs ICU `"5 tonelada-kilometros"` (accent). Our pinned data has no accent-less es form; simple + precomposed units match, so ours is the data-faithful one.
* `ar` long/short `tonne-kilometer`: different plural-form selection for the trailing component.

So the harness must separate **algorithm/regression bugs (must fail)** from **known data-version skew (must not flake)**. See memory `nif-uses-system-icu-version-skew.md`.

## Design — two complementary layers

### Layer 1 — version-independent invariants (hard CI gate, no NIF, cannot flake)

New file: `test/localize/unit/formatter_property_test.exs`, `use ExUnitProperties` (StreamData is already a dep; existing examples: `test/localize/adversarial_test.exs`, `test/localize/utils/math_test.exs`).

Generators:
* `unit` — one of the 155 base units (`Localize.Unit.known_units_by_category/0`, flattened) PLUS generated compounds:
  * times: `"#{a}-#{b}"` for two distinct base units,
  * per: `"#{a}-per-#{b}"`.
  * Bias toward compounds (that is the gap).
* `locale` — a representative set, e.g. `~w(en fr de es it pt ru ja nl pl ar zh)`.
* `style` — `:long | :short | :narrow`.
* `number` — integers + a few decimals incl. 0, 1, 2, 42, 1000 (plural-category coverage).

Invariants to assert (all version-independent):
1. `to_string` returns `{:ok, _}` (never crashes) for every generated unit/locale/style/number.
2. A **known compound never formats to its raw hyphenated identifier** — e.g. result for `tonne-kilometer` must not be `"5 tonne-kilometer"`. Direct #43 regression guard. (Guard: assert the raw id string is not a substring, allowing that legitimate names may share tokens — compare against the exact `"<num> <name>"` fallback shape.)
3. The formatted number appears in the output (the value was actually rendered).
4. Round-trip for symbols/names: for units reachable via `parse`, `parse(value <> " " <> format_result)` resolves back to the same canonical unit where unambiguous. Direct #42 guard. (Scope carefully — ambiguous names like narrow "w" need `:only`; may restrict this property to a curated unambiguous set.)
5. Plural agreement: for `number` whose plural is `:other` in the locale, the trailing component uses its `:other` noun (spot-check via the known plural pattern).

Layer 1 is the gate. It runs without the NIF and can't flake on ICU version.

### Layer 2 — differential vs. the NIF (confidence booster; tagged `:nif`)

Extend `test/localize/unit/nif_cross_validation_test.exs` (already gated on `Localize.Nif.available?()` and `@moduletag :nif`).

* Same generated space (bias to compounds), `assert elixir_result == icu_result`.
* **Quarantine set** — a module attribute of `{unit, locale}` (and maybe style) pairs known to diverge from ICU due to version skew, each with an inline comment citing the reason. Seed with the confirmed cases:
  * `{"tonne-kilometer", "es"}` — accent (kilómetros vs kilometros); pinned 48.2 has no accent-less form.
  * `{"tonne-kilometer", "ar"}` — trailing plural-form selection differs under ICU 78.
* Divergence **outside** the quarantine fails the test (catches real regressions). Divergence **inside** is skipped (documented skew).
* The quarantine shrinks when the pin and system ICU realign; keep it small and commented.

## Execution steps

1. Write Layer 1 (`formatter_property_test.exs`); run `mix test test/localize/unit/formatter_property_test.exs`; fix any real issues it surfaces.
2. Write Layer 2 (extend `nif_cross_validation_test.exs`); run with `--include nif`; **triage every diff** — classify as (a) elixir bug → fix, or (b) data-version skew → add to quarantine with a comment. Do NOT blanket-quarantine; each entry needs a verified reason.
3. Run the full six-gate stack (format / compile --warnings-as-errors / test / credo --strict / dialyzer / docs) on the mise-current toolchain.
4. Report the final diff triage (what matched, what's quarantined and why).

## Open decisions (default in bold)

* Gating: **Layer 1 gates CI; Layer 2 is `:nif`-tagged (run locally / where ICU present), non-gating** — because system-ICU skew makes it environment-dependent. Revisit if a pinned-ICU CI image exists.
* Oracle choice: NIF (live ICU) chosen over `ex_cldr_units` (bench-only dep) for arbitrary-unit coverage. `ex_cldr_units` could be a future *stable* oracle if pinned to a matching CLDR, but it is `only: :bench` today.
* Generation counts: start ~200 examples/property; raise if cheap.

## Files

* NEW `test/localize/unit/formatter_property_test.exs` (Layer 1)
* EDIT `test/localize/unit/nif_cross_validation_test.exs` (Layer 2 + quarantine)

## Context references

* Fixes that motivated this: commit `a28da2f` (#42 name_index hyphenation, #43 times-compound formatting + grammaticalFeatures pipeline, #44 derived base_unit folding).
* Memory: `nif-uses-system-icu-version-skew.md`.
* CLDR fixture gap discussion: only conversion/preference vectors exist; `conversion_test.exs` already ingests `unitsTest.txt` via `test/support/data/conversion_test_data.txt`.
