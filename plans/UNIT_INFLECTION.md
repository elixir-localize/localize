# Plan: Localize.Unit ↔ Localize.Inflection integration

Status: IMPLEMENTED (2026-07-24) on the `inflection` branch. All phases (0, A, B, C, D) landed; see lib/localize/unit/inflection.ex, Localize.Unit.grammatical_gender/2, the custom-registry case patterns, the MF2 grammaticalCase/inflect options and test/localize/unit/unit_inflection_test.exs. Two designs changed during implementation: the confidence gate is a guess-free engine render (Concept `guess: false`) rather than `known?/2` alone (which was too strict for Finnish compounds and is now the multi-word gate only), and the fallback noun renders through the quantify factories (upstream numeral government) with a singular-after-numeral override for az/hu/kk/tr. The prepositional/partitive/inessive/elative/illative normalizer gap ships separately on main.

## Goal

Let unit formatting produce grammatically correct output in locales or cases where CLDR unit patterns run out, by using the inflection engine as an opt-in, confidence-gated fallback — without changing a single byte of current output when the feature is off.

## Current state (verified 2026-07-24)

### How Unit formatting resolves grammar today

* Unit pattern data (per locale ETF, `Localize.Locale.get(locale, [:units])`) is keyed style → category → unit → **grammatical case** → **plural category** → token list, e.g. de `kilometer` `dative: %{other: [0, " Kilometern"]}`. Each simple unit also carries `gender: "masculine"` and `per_unit_pattern`.

* `Localize.Unit.Formatter.resolve_pattern/3` ([formatter.ex:591](../lib/localize/unit/formatter.ex)) resolves `Map.get(unit_formats, grammatical_case) || Map.get(unit_formats, :nominative) || Map.get(unit_formats, :other)`, then plural → `:other`. The fallback to nominative is **silent** — a request for `:instrumental` in a locale without case data quietly returns nominative text. Three call sites: [formatter.ex:561](../lib/localize/unit/formatter.ex) (to_string), [:235](../lib/localize/unit/formatter.ex) (to_parts), [:121](../lib/localize/unit/formatter.ex) (ranges, which pass a plural-range category).

* Only ~33 base locales ship case-keyed unit patterns at all: am, cs, da, de, el, fi, hr, hu, hy, is, kn, lt, lv, ml, mr, nb, nn, no, pl, ro, ru, sk, sl, sr, sv, ta, uk (plus regional variants). Everywhere else, `:grammatical_case` is a no-op.

* `:grammatical_gender` is accepted but documented as having no effect on output. Per-unit `gender:` is stored in the data but never read; `compound_unit_pattern` (times/power2/power3, gender-keyed) and `unit_prefix_pattern` are present in the data but never read by any formatter code — compounds are assembled by string composition via `per_unit_pattern` or a hard-coded English `"per"`.

* Custom units (`Localize.Unit.CustomRegistry`) support only plural-keyed `"{0}"` string patterns — no case, no gender.

* MF2 `:unit` maps only `unitDisplay` → `:format` ([interpreter.ex:1853](../lib/localize/message/interpreter.ex)); no `grammaticalCase` option flows through.

* Known data bug (separate fix, on main): the units normalizer ([data/normalize/units.ex:39-89](../data/normalize/units.ex)) has no clause for `prepositional_count_*`, so ru prepositional patterns stay flat in the ETF and `grammatical_case: :prepositional` silently degrades to nominative. Fix independently of this plan.

### What the inflection engine can and cannot promise

Feasibility spot checks against CLDR expected output:

* ru километр → dative километру ✓, genitive-plural километров ✓, instrumental секундой ✓; de dative plural Kilometern ✓; fi inessive metrissä ✓; de Stunde gender :feminine ✓.

* pl metr → genitive **"mobru"** (garbage). `metr` is not in the pl dictionary; the exemplar-splice guesser mangled it.

* ru час is **also not dictionary-known** (`combined_grammemes` → nil, gender → nil), yet inflects correctly through suffix-exemplar guessing — upstream relies on the same mechanism. Guessing is often right and sometimes catastrophically wrong.

* **`Concept.exists?` is not a sufficient confidence gate**: it returned true for the pl metr genitive that rendered as garbage. The reliable predicate is dictionary membership per word, not "did the synthesizer produce something".

Design consequence: the integration must never put guessed forms into user-visible unit text unless the caller explicitly opts into guessing.

## Design principles

1. CLDR unit patterns are authoritative. The engine is consulted only where CLDR has no answer (missing case variant, missing gender, custom units, unsupported locale/case combination).

2. Strictly opt-in. Default behavior (option absent) is byte-identical to today, verified by test.

3. Dictionary-confidence gating. The safe tier inflects only when every significant word in the pattern text is dictionary-known in that locale. Guessing is a separate, explicitly requested tier.

4. Failures degrade to today's behavior (silent nominative fallback), never to an error, when the feature is a fallback. Direct API calls (e.g. a gender query) return structured `{:error, exception}` per house convention.

## Phase 0 — Engine prerequisites

* `Localize.Inflection.known?/2` — public predicate: every significant word of the phrase is dictionary-known for the locale (per-word `Dictionary.combined_grammemes != nil`, skipping particles/whitespace/digits). This is the confidence gate for all later phases.

* Investigate and document why `Concept.exists?` returns true for guessed garbage (pl metr genitive) — either fix its semantics or document that `exists?` means "a form can be synthesized", not "the form is attested". Also confirm the earlier ru час discrepancy (quantify worked while `combined_grammemes` returned nil) is fully explained by the guess path.

* Decide the inflection option shape used across all phases: `inflect: false | :safe | :always` (default `false`; `:safe` = dictionary-gated; `:always` = allow guessing, documented as risky).

## Phase A — Case fallback for simple units

The highest-value seam: `to_string(unit, locale: :pl, grammatical_case: :genitive, inflect: :safe)` in locales/cases CLDR doesn't cover.

* Detection: in the three `resolve_pattern` call paths, detect *before* the silent `|| :nominative` whether the requested case key is actually present in `unit_formats`. Present → current behavior unchanged. Absent and `inflect:` enabled → engine path.

* Engine path: take the nominative (or `:other`) pattern for the resolved plural category; split its token list into the number placeholder and literal text; inflect the literal's noun phrase via a `Concept` constrained by `case:` and `number:` (plural category → grammatical number, reusing the quantify mapping — ru `:many` → plural etc.); reassemble tokens. Trim/restore the leading space and any NBSP faithfully.

* Gate per pattern: under `:safe`, if `known?/2` fails for the literal text, fall back to today's nominative behavior silently. Under `:always`, inflect regardless.

* Caching: inflected patterns are deterministic per {locale, unit, style, case, plural} — cache in the existing format-cache layer so the engine cost is paid once, not per call.

* Non-goal: ranges (call site 3) pass plural-range categories, not cardinal ones; map conservatively or exclude ranges from Phase A.

## Phase B — Gender

* `Localize.Unit.grammatical_gender/2` (unit, options) → `{:ok, :masculine | :feminine | ...} | {:error, exception}`. Source order: the `gender:` field already in CLDR unit data (currently stored, never read) first; `Localize.Inflection.feature(text, :gender, locale)` as fallback for units/locales without it, gated by `known?/2`.

* Make the existing `:grammatical_gender` option real where data supports it. Full use requires implementing `compound_unit_pattern` assembly (power2/power3 gender-keyed patterns, currently dead data) — that is a pre-existing formatter gap, tracked as its own work item; this plan only requires the gender *query* so callers (and the future compound work) have a source of truth.

## Phase C — Custom units

* Extend `CustomRegistry` display definitions to accept optional case-keyed patterns (same nested shape as CLDR data) — zero engine involvement, pure data plumbing.

* Engine assist: when a custom unit has only a display name and `inflect:` is enabled, quantify/inflect the display name per case/plural via the engine, same `:safe` gating. This gives custom units in ru/pl/fi/etc. correct declension from a single registered lemma when it is dictionary-known.

## Phase D — MF2 option flow

* Extend `map_unit_options/2` ([interpreter.ex:1853](../lib/localize/message/interpreter.ex)) to map MF2 `grammaticalCase` (and `grammaticalGender`) function options onto `:grammatical_case`/`:grammatical_gender`. String values arrive from MF2 literals; normalize to atoms against the known grammeme set (reject unknowns with the standard invalid-option error).

* Whether `inflect:` itself is exposed as an MF2 option is a policy call — default proposal: yes, same values, since MF2 messages are exactly where case-correct units matter (`Расстояние: {$d :unit unit=kilometer grammaticalCase=dative}`).

## Testing strategy

* Golden invariance: with `inflect:` absent/false, outputs are byte-identical to pre-integration for a broad sample (all styles × several locales × several cases × several plurals). This is the non-negotiable regression gate.

* Agreement audit: for the ~33 locales that HAVE case data, run the engine against the same nouns and diff engine output vs CLDR patterns. CLDR is the reference; the diff is both a quality report on the engine and the empirical basis for trusting `:safe` mode in locales without case data.

* Per-language expectation tables for the fallback path (ru/uk/pl/fi/de at minimum), including deliberate dictionary-miss cases asserting the silent fallback under `:safe` and the guessed form under `:always`.

* Property: `:safe` never emits a form containing characters absent from the dictionary lemma's inflection table (guards against pl-metr-style splice garbage escaping the gate).

## Risks and open questions

* Pattern literal ≠ bare noun: unit literals can be multi-word ("миль в час") or carry embedded prepositions; Phase A needs a conservative noun-phrase extractor and must skip patterns it cannot confidently segment (skip = current behavior, so the failure mode is status quo).

* Dictionary coverage varies sharply by language (pl misses `metr`); `:safe` mode's practical coverage needs the agreement audit before we promise anything in docs.

* Plural-category → grammatical-number mapping is per-language (ru `:many`); reuse the quantify tables rather than invent a second mapping.

* Perf: engine synthesis is 2–21 µs/op, fine once cached; ensure the cache key includes the inflect option so modes don't cross-contaminate.

* Inflection data is optional-download: with `inflect:` requested but data absent, degrade silently in fallback contexts and return `InflectionDataNotAvailableError` from direct APIs (`grammatical_gender/2`), consistent with the established error strategy.

## Sequencing

Phase 0 + A land together (A is the deliverable, 0 its foundation), targeted at 1.1.x or 1.2 after the 1.1 inflection release settles. B is small and can ride along. C and D are independent and can follow demand. The prepositional normalizer fix ships on main independently and first.
