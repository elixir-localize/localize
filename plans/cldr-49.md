# CLDR 49 upgrade plan

> **Process note (2026-07-06):** the repeatable update mechanics (source refresh, generation, verification gates, CDN upload, hash manifest, release order) are consolidated in [CLDR_UPDATE_INTEGRATION.md](../CLDR_UPDATE_INTEGRATION.md) — the CLDR Update Guide. This plan now carries only the CLDR-49-specific work items. Item 13 (CDN checksum manifests) shipped early in Localize 0.44.0 as the hash-manifest system; see the guide's "Hash manifest and the OTP encoding trap" section.

**Status:** draft, last updated 2026-07-06

**Owner:** Localize maintainers

**Target release:** Localize 0.26+ (CLDR 49.x base data)

**Source:** plans this against the upcoming CLDR 49, expected on the usual late-October Unicode release cadence (~5 months out from this plan's draft date). Track upstream progress at <https://cldr.unicode.org/downloads/cldr-49>.

This plan must be reviewed and revised as CLDR 49 alpha → beta → RC ships and the actual delta lands. See the **Review cadence** section at the end.

## Scope

This document covers the CLDR-49-driven workstream plus a handful of related items the maintainers want to land in the same window:

1. Migrate the LDML→JSON pipeline to `scripts/ldml2json_v2`.
2. Review the CLDR 49 translators' guide for behavioural changes that reach the runtime.
3. Track the formal spec deltas published at <https://cldr.unicode.org/downloads/cldr-49>.
4. Add semantic skeletons for date/time formatting (TR35 §Date_Format_Patterns).
5. Implement flexible date-time append-items correctly.
6. Audit the implementation against TR35 *minimal pairs*.
7. Expose minimum/maximum significant-digit options on number formatting.
8. Audit RBNF parser/runtime against TR35 RBNF syntax (recent additions).
9. Adapt the data ingestion pipeline to TR35's *Remove rule from ruleset* RBNF data-format change.
10. Re-examine the CLDR 48.2 §Modifications log against our base data for items we may have shipped incompletely.
11. Spin up a sibling library `localize_emoji` from CLDR annotations.
12. Audit `$CLDR_REPO/common/testData` for new conformance fixtures we should be exercising — in particular, new decimal-formatting tests expected to ship with CLDR 49.

13. Generate and serve checksum manifests for the downloadable CDN assets so the runtime can validate locale ETFs before decode. Research required — see item 13 for the open design questions around manifest shape, verification path, and hot-path performance budget.

Items 1–13 are the original draft scope. Items 14 onward were added as the cycle progressed — from the alpha release-note reviews, and from defects the test merge itself exposed — and the **Index above is the authoritative list**; this section is kept for the original framing only. Do not read a gap here as a gap in coverage.

For every item below, three things appear:

* **Current conformance** — what Localize ships today and how it compares to the spec.
* **Gap** — what is missing or wrong relative to the standard.
* **Plan** — the steps to close the gap, with explicit notes on API impact and any potential breaking changes.

## Backwards-compatibility commitments

This package is widely used. The following invariants apply to every item in this plan:

* Existing public function signatures (`Localize.Number.to_string/2`, `Localize.DateTime.to_string/2`, `Localize.Unit.to_string/2`, `Localize.Date.to_string/2`, `Localize.Time.to_string/2`, the `Localize.LanguageTag` struct, `Localize.Currency.*`, `Localize.Locale.*`) keep their arities and return shapes.
* Existing option keys keep their meaning. New behaviour is added via *new* option keys, not by changing existing defaults.
* Default outputs for the locales and formats covered by the CLDR test suite must remain stable except where CLDR itself changes the underlying data — those changes are documented in the changelog.
* Where CLDR 49 reshapes data (e.g. RBNF rule removal, see item 9), the on-disk ETF schema stored under `priv/localize/` may change in a major-version release of Localize; the public API is preserved even when ETF schemas evolve.
* Anything that would break the above is called out explicitly under **Breaking risk** in its section.

## Index

| #  | Item                                              | API impact | Breaking risk |
|----|---------------------------------------------------|------------|---------------|
| 1  | Switch pipeline to `scripts/ldml2json_v2`         | None       | None          |
| 2  | Translators-guide review for CLDR 49              | None       | None (data only) |
| 3  | Track CLDR 49 spec changes                        | None       | None          |
| 4  | Semantic skeletons                                | New option | None          |
| 5  | Date-time append items                            | Internal   | None (output may change for under-specified skeletons) — deferred to CLDR 49 cycle (needs `dateFields` data) |
| 6  | Minimal pairs                                     | New module | None          |
| 7  | Min/max significant digits                        | New options | None          |
| 8  | RBNF syntax audit                                 | Internal   | None — ✅ Done in Localize 0.26.0 |
| 9  | RBNF *Remove rule* data-format change             | Internal (ETF) | ETF schema bump (no public API) |
| 10 | CLDR 48.2 §Modifications retrospective            | Mixed      | Per-finding — ✅ Done. See [plans/cldr-48-retrospective.md](cldr-48-retrospective.md). |
| 11 | `localize_emoji` sibling library                  | New package | None          |
| 12 | `common/testData` conformance-fixture audit       | None (tests only) | None      |
| 13 | CDN-asset checksum manifests                       | None       | None — ✅ Done in Localize 0.44.0 |
| 14 | Japanese pre-Meiji eras: keep and curate           | None (data retained) | **Silent data loss if not done** — CLDR 49 drops 232 of 237 eras. See [plans/japanese_eras.md](japanese_eras.md). |
| 15 | POSIX `yesstr` / `nostr` responses                  | New functions | None (additive; ETF schema bump) |
| 16 | `typeValues` On/Off translations (CLDR 49, CLDR-19394) | New functions | None (additive) — added 2026-08-25 |
| 17 | `H24` hour cycle deprecated                        | None       | Output changes for the `k` symbol at midnight |
| 18 | Week-of-year numbering follows ISO by default       | None       | **Rendered week numbers change** for locales whose calendar week is not the ISO week, `en` among them |
| 19 | Supplemental data files reorganized                | None       | Build-time failure if the pipeline meets reorganized sources unadjusted |
| 20 | Iran subdivision codes stale upstream              | None       | None now; a future CLDR change invalidates stored codes |
| 21 | Metazone transitions gain seconds precision        | None       | None — ✅ Fixed. `Africa/Monrovia` resolves 30s earlier, a correction |
| 22 | RBNF rules externalised to ICU text, plus `[A\|B]` alternation | None | None — ✅ Fixed. New reader, lexer and parser rules; output unchanged |
| 23 | `copy_test_data` reverts curated conformance fixtures | None | None — ✅ Fixed. Curated fixtures skipped; upstream drift reported |
| 24 | Plural rule modules never recompile on a data change | None       | None — ✅ Fixed. The test gate was running last release's rules |
| 25 | CLDR 49 drops 114 locales below Basic coverage       | None       | **Breaking** — ✅ Adopted. 114 locales removed; `aa` and `ht` among them |
| 26 | Locale display in `root` falls back to English       | None       | None — ✅ Fixed. 24 new cases pass, plus 44 exclusions retired |
| 27 | Collation data pinned at Unicode 17 by hand         | None       | **Sort keys change** — ✅ Fixed. Full UCA conformance at Unicode 18 |
| 28 | CLDR 49 decimal format conformance suite            | None       | **Output changes** — ✅ Conformant; every difference is a documented CLDR-over-ICU choice |
| 29 | A locale did not always resolve to itself          | None       | **Resolution changes** — ✅ Fixed. 25 locales were served a neighbour's data |
| 30 | CLDR 49 RBNF conformance suite                      | None       | **Output changes** — ✅ 52,685/52,691; eight defects fixed |

The remainder of this file expands each item in turn.

## 1. Switch the data pipeline to `scripts/ldml2json_v2`

### Current conformance

Localize has *two* LDML→JSON conversion scripts:

* `scripts/ldml2json` — the legacy script. Its header carries a `TODO Try to use https://github.com/unicode-org/cldr-json/blob/main/cldr-generate-json.sh for CLDR 49`. It runs the ICU XSL pipeline directly and is known to miss the `annotations` and `annotationsDerived` packages.
* `scripts/ldml2json_v2` — already in the tree. Wraps `unicode-org/cldr-json`'s `cldr-generate-json.sh`. One Maven pass emits all CLDR JSON packages: `main`, `supplemental`, `segments`, `rbnf`, `bcp47`, `transforms`, `subdivisions`, **and** `annotations` + `annotationsDerived`. Output goes to `$CLDR_PRODUCTION` (default `~/Development/cldr/cldr_production_data`).

### Gap

The CHANGELOG and the `Localize.Data` build-time scripts still rely on the v1 path. v2 is functional but un-adopted. v2 is the prerequisite for items 11 (annotations) and any future work that depends on packages v1 misses (transforms, segments edge cases).

### Plan

1. Wire `scripts/ldml2json_v2` into the documented build flow:
   * Update `data/data.ex` (the CLDR ETF generator entry-point) to read from the cldr-json layout produced by v2 — paths under `cldr-core/`, `cldr-numbers-full/`, `cldr-dates-full/`, `cldr-rbnf/`, `cldr-annotations-full/`, etc. Where v1 and v2 produce different layouts, prefer v2's structure.
   * Verify that `data/normalize/*.ex` modules still work against the v2 output by regenerating ETFs and running the existing test suite.
2. Pin a known-good `unicode-org/cldr-json` commit/tag (probably the CLDR 49 release tag once published) and document the override envvars in `data/README.md`.
3. Mark `scripts/ldml2json` deprecated. Remove in the release after the one that ships CLDR 49.
4. Add a `mix data.regenerate` mix task (or extend the existing one) that calls v2 and then runs the normalizer pipeline end-to-end.

### API impact / breaking risk

None. The pipeline is a build-time concern; the runtime API and ETF schemas are unchanged by this work in isolation. Item 9 (RBNF data shape) and item 11 (annotations) will land *through* this pipeline.

## 2. Review the CLDR 49 translators' guide

### Current conformance

We track the runtime impact of CLDR translation guidance ad-hoc, file by file (e.g. last cycle's `:variant`/`:standard` work for date patterns came out of a similar audit). Today: no formal sign-off record per release.

### Gap

The translators' guide at <https://cldr.unicode.org/translation> is the authoritative description of how the data CLDR 49 ships is *meant* to be consumed. Several recent guidance pages have moved behaviour into the runtime — examples from prior cycles include:

* Day-period rules
* Person-name formatting (TR35-personNames)
* "Date-time append items" (item 5 of this plan)
* Variant date patterns (handled in 0.25.0)
* Minimal pairs (item 6 of this plan)
* Plural ranges
* Currency display rules (e.g. `narrow` vs `symbol` selection)

Without a structured pass, behavioural deltas in the guide can ship as silent regressions in our output.

### Plan

1. Once the CLDR 49 translators' guide is published (typically with the alpha), do a section-by-section read of:
   * Numbers (significant digits, minimal pairs, scientific, plural forms — feeds items 6 and 7).
   * Dates and Times (semantic skeletons, append items, hour cycle, timezone names — feeds items 4 and 5).
   * Units (preferences, gender — already largely in place from CLDR 46/47 work).
   * Personal names (gendered rendering, name patterns, prefixes).
   * Currency (display narrow vs symbol, plural names).
   * Locale Identifiers (extension keys/types added in BCP-47).
2. Produce a checklist as a child plan (`plans/cldr-49-translator-guide-checklist.md`) that enumerates each guide section and our current handling. Tick each off explicitly: *correct / partial / missing / N/A*.
3. For each "partial" or "missing" item, file a tracking issue and either link it to one of the work-items in this plan or propose an addition.

### API impact / breaking risk

The audit itself is data-only. Findings may produce per-locale output changes. Any user-visible change is documented in the changelog.

## 3. Track CLDR 49 spec changes

### Current conformance

The CLDR 48.2 base data is in `priv/localize/version` (`48.2`) and `priv/localize/localize_patch_version` (`48.2:1`). We track CLDR patch releases via the `cldr_version()` build helper in `mix.exs`. We do not currently maintain a structured per-release diff log against the LDML/TR35 spec.

### Gap

CLDR 49's release page at <https://cldr.unicode.org/downloads/cldr-49> will list:

* Newly-added BCP 47 extension keys/types (`u-*`, `t-*`).
* New or removed locales.
* Renamed/withdrawn calendar systems, currencies, territories.
* New units of measure.
* New numbering systems.
* Bug fixes that change rendering for specific locales.

Each of these can break customer expectations if it lands silently.

### Plan

1. As soon as CLDR 49 alpha is announced, fork its release page into a child plan `plans/cldr-49-changes.md` with one row per change.
2. Score each row for likely user impact: *cosmetic / output-changing / API-affecting / data-only*.
3. For *API-affecting* changes (e.g. a new BCP 47 extension key), add the key handling to `Localize.LanguageTag.U`/`Localize.LanguageTag.T` under the existing extension struct (additive; no breaking change).
4. For *output-changing* changes, ensure tests document the pre-/post-CLDR-49 output for at least the de-facto reference locales (`:en`, `:de`, `:fr`, `:ja`, `:zh`, `:ar`).
5. Bump `priv/localize/version` and the patch counter on the actual data swap. Update the changelog with a "CLDR 49 base data" entry that links to `plans/cldr-49-changes.md`.

### API impact / breaking risk

None inherent to tracking. Specific CLDR 49 deltas may carry their own risk; those are surfaced through the child plan above.

## 4. Semantic skeletons for date-times

Spec: <https://www.unicode.org/reports/tr35/dev/tr35-dates.html#Semantic_Skeletons>

The detailed design plan — vocabulary, resolver algorithm, public API, worked examples, implementation steps, and risk register — lives in [plans/semantic-skeletons.md](semantic-skeletons.md). This section keeps the high-level scope statement; the child plan resolves the seven open questions and is the source of truth for implementation.

### Current conformance

`Localize.DateTime.to_string/2` accepts:

* `format: :short | :medium | :long | :full` — standard CLDR styles.
* `format: <skeleton-atom>` — e.g. `:yMMMd` — runs through the skeleton best-match resolver in `lib/localize/datetime/format/match.ex`.
* `format: "<pattern>"` — a literal CLDR pattern string.

We do not currently honour the **semantic-skeleton** vocabulary that TR35 (dev) introduces: a higher-level, locale-independent way to ask for a date/time of a particular *meaning* (e.g. "year-month-day with weekday") rather than an opinion about which fields to render. The spec defines length groups (`:short`, `:medium`, `:long`), date components (`year`, `year_month`, `year_month_day`, `year_quarter`, `auto`), time components (`hour`, `hour_minute`, `hour_minute_second`, `auto`), and zone components (`specific`, `generic`, `location`, `offset`, `auto`), all combinable via a small grammar.

### Gap

* No data path: the CLDR JSON for semantic skeletons is in `cldr-dates-full/main/<locale>/dateFields.json` and the new `dateFormatItems` semantic-skeleton extension. Our normalizer ignores it.
* No runtime path: `find_format/3` in `Localize.Date` only knows about standard formats and skeleton atoms.
* No public API surface for callers to express semantic intent.

### Plan — data path

1. Extend `data/normalize/date_time.ex` (or add a sibling normalizer) to extract the semantic-skeleton tables CLDR 49 ships. They live alongside `availableFormats` under each calendar.
2. Persist them under `priv/localize/locales/<locale>/dates/calendars/<cal>/semantic_skeletons.etf` keyed by the semantic-skeleton tuple/atom shape decided below.
3. Add `Localize.DateTime.Format.semantic_skeletons/2` mirroring `available_formats/2` for runtime lookup.

### Plan — public API: three options

The user-facing question is *how* a caller asks for a semantic skeleton. Three candidates, in increasing power and cost:

#### Option A — single new option, atom or tuple value

```elixir
Localize.DateTime.to_string(dt, locale: "en-CA",
  semantic: :year_month_day)

Localize.DateTime.to_string(dt, locale: "en-CA",
  semantic: {:year_month_day, :weekday, length: :long, zone: :specific})
```

The `:semantic` option accepts:

* an atom matching one of the canonical semantic shapes (`:year_month_day`, `:hour_minute`, `:year_month_day_hour_minute`, `:auto`); **or**
* a tuple `{date_component, time_component, opts}` where `opts` is a keyword list with `:length`, `:zone`, `:alignment`, `:year_style`.

Pros:
* Keeps the `:format` option's existing meaning intact (no overload).
* Atom-only form covers ~80% of cases without ceremony.
* The tuple form is fully expressive.

Cons:
* Two parallel options (`:format` and `:semantic`) with overlapping intent. Need a documented precedence rule (see "Resolution order" below).

#### Option B — overload `:format` to accept a semantic-skeleton struct

```elixir
import Localize.DateTime.SemanticSkeleton, only: [semantic: 1, semantic: 2]

Localize.DateTime.to_string(dt, locale: "en-CA",
  format: semantic(:year_month_day))

Localize.DateTime.to_string(dt, locale: "en-CA",
  format: semantic(:year_month_day, length: :long, zone: :specific))
```

`semantic/1,2` returns an opaque `%Localize.DateTime.SemanticSkeleton{}` struct. The dispatch in `Localize.Date.find_format/3` learns about the new struct shape alongside binary patterns and skeleton atoms.

Pros:
* One option key (`:format`). The struct discriminates.
* Compile-time validation possible because the struct constructor can raise on unknown components.
* Mirrors `Localize.Number.Format.Options` validate-once-reuse-many pattern that already exists in this codebase — callers can hold onto a struct and pass it to many `to_string/2` calls.

Cons:
* Slightly more typing; users need an `import` or fully-qualified call to `semantic/1,2`.
* Opaque struct in `:format` means doctests with `format: …` literals read less naturally.

#### Option C — first-class function `Localize.DateTime.to_semantic_string/3`

```elixir
Localize.DateTime.to_semantic_string(dt, :year_month_day,
  locale: "en-CA", length: :long, zone: :specific)
```

A new entry point parallel to `to_string/2`, taking the semantic component as a positional argument.

Pros:
* No overloading at all. Spec-compliant naming closely tracks TR35.
* Maximum clarity in tutorials and documentation.

Cons:
* Doubles the surface area users have to learn (`to_string` *and* `to_semantic_string`). `Localize.Date`, `Localize.Time`, `Localize.Interval` would each grow a parallel function.
* Wrapper helpers like `Localize.DateTime.to_string!/2` would also need parallels.

#### Recommendation

**Option B** for the primary API, with Option A's atom-only form as a sugar shorthand on top.

Concretely, the `:format` option accepts:

| Value                                    | Meaning                                           | Status            |
|------------------------------------------|---------------------------------------------------|-------------------|
| `:short`/`:medium`/`:long`/`:full`       | Standard CLDR style                              | Existing          |
| `<skeleton-atom>` e.g. `:yMMMd`          | CLDR field-skeleton best-match                    | Existing          |
| `<binary>`                               | Literal CLDR pattern string                       | Existing          |
| `%Localize.DateTime.SemanticSkeleton{…}` | Built via `semantic/1,2`, full TR35 expressivity  | New in CLDR 49 work |

And we *also* accept a small set of canonical atoms (`:year_month_day`, `:hour_minute`, `:year_month_day_hour_minute_second`, `:auto`) which the resolver promotes to a default `SemanticSkeleton` struct. These atoms are deliberately disjoint from the existing CLDR field skeletons (`:yMMMd`, `:Hms`, etc.) so there is no ambiguity.

Resolution order in `find_format/3`:

1. If `:format` is a binary → pattern.
2. If `:format` is a `SemanticSkeleton` struct → semantic resolver.
3. If `:format` is an atom in `@standard_formats` → standard CLDR style.
4. If `:format` is an atom in `@semantic_atoms` → promote to `SemanticSkeleton`.
5. Otherwise → existing skeleton best-match.

This keeps `:format` behaviour 100% backwards-compatible: every value that worked before resolves to the same path.

### Plan — implementation steps

1. Create `Localize.DateTime.SemanticSkeleton` with a `defstruct` and `semantic/1,2` constructors that validate components against a compile-time list derived from TR35.
2. Add a resolver in `Localize.DateTime.Format` (or a new `Localize.DateTime.Format.Semantic` sibling) that, given a struct and a locale, returns a CLDR pattern string by consulting the `semantic_skeletons.etf` data and then falling back to the field-skeleton best-match.
3. Plumb the new struct shape through `Localize.Date.find_format/3`, `Localize.Time.find_format/3` and `Localize.DateTime`'s wrapper resolution.
4. Doctests + unit tests for each canonical semantic atom across the reference locale set.

### API impact / breaking risk

* New: `Localize.DateTime.SemanticSkeleton` module, `semantic/1,2` constructor, additional accepted shapes for the `:format` option.
* No breaking change to existing `:format` values.

## 5. Date-time append items (flexible patterns) — deferred to CLDR 49 cycle

Spec: <https://cldr.unicode.org/translation/date-time/date-time-patterns#flexible---datetime-append-items>

This item is **deferred to the CLDR 49 cycle** rather than landing standalone in 0.27. The full implementation needs `dateFields` data that our pipeline doesn't currently ingest, and the CLDR 49 cadence (which already requires regenerating the locale ETFs through `scripts/ldml2json_v2`) is the natural moment to extend the normalizer rather than running an interim pipeline cycle just for this. The detail below stays in the plan so the work is ready to drop in cleanly when CLDR 49 lands.

### Current conformance

The CLDR JSON ships per-locale `appendItems` data and our normalizer in `data/normalize/date_time.ex` already reads it via `compile_items` and stores it under `dates.calendars.<cal>.append_items` in the locale ETF. The on-disk shape is a map keyed by lowercase atom field name with values that are *pre-parsed* substitution lists where integers are placeholders (`{0}`, `{1}`, `{2}`) and strings are literals — for English: `:year` is `[0, " ", 1]` (= `"{0} {1}"`); `:day` is `[0, " (", 2, ": ", 1, ")"]` (= `"{0} ({2}: {1})"`).

### Gaps

Three distinct gaps; only the first is a runtime gap, the other two are data gaps.

1. **No runtime consumer.** `grep -rnE "append_items" lib/` returns nothing. The skeleton best-match algorithm in [lib/localize/datetime/format/match.ex](../lib/localize/datetime/format/match.ex) returns the closest available format ID and the caller silently receives output missing the requested field.

2. **`dateFields` is not loaded.** The CLDR `dates.fields.<field>.displayName` data — which fills the `{2}` placeholder in append-item templates like en's `"{0} ({2}: {1})"` for `:day`, `:month`, `:hour`, `:minute`, `:second`, `:quarter`, `:week` — exists on disk under `priv/cldr/locales/<locale>/cldr-dates-full__dateFields.json` but our normalizer skips it. `Localize.Locale.get(:en, [:dates])` currently returns only `[:calendars, :time_zone_names]`. Without this data the `{2}` substitution renders as a placeholder or empty string for every parenthesised template (which is most of them in en and many other locales).

3. **No symbol-to-field mapping.** The skeleton uses CLDR symbols (`y`, `M`, `d`, `E`, `h`, `m`, …); appendItems are keyed by atom field names (`:year`, `:month`, `:day`, …). The mapping is straightforward but doesn't exist anywhere in the codebase yet.

### TR35 algorithm

Paraphrased from the spec:

1. Caller asks for skeleton `S`.
2. Resolver finds the closest available skeleton `T` in the locale.
3. For each field present in `S` but not in `T` (e.g. caller asks `:yMMMdEEEE` but the locale's closest match is `:yMMMd`, leaving `EEEE` missing), the resolver looks up the append-item template for that field type (e.g. `[0, " ", 1]` for `:day_of_week` in en).
4. Substitute `{0}` = the matched pattern, `{1}` = the missing field's standalone pattern (rendered as-is from the requested skeleton's missing characters), `{2}` = the field's display name from `dates.fields.<field>.displayName`. Iterate field-by-field if more than one is missing — each iteration's output becomes the next iteration's `{0}`.

### Symbol-to-field mapping

| CLDR symbol(s)         | Field key in `append_items` |
|------------------------|-----------------------------|
| `G`                    | `:era`                      |
| `y`, `Y`, `u`, `U`, `r` | `:year`                     |
| `Q`, `q`               | `:quarter`                  |
| `M`, `L`               | `:month`                    |
| `W`, `w`               | `:week`                     |
| `d`, `D`, `F`, `g`     | `:day`                      |
| `E`, `e`, `c`          | `:day_of_week`              |
| `h`, `H`, `k`, `K`     | `:hour`                     |
| `m`                    | `:minute`                   |
| `s`, `S`, `A`          | `:second`                   |
| `v`, `V`, `z`, `Z`, `x`, `X`, `O` | `:timezone`        |
| `a`, `b`, `B`          | (no append-item; day-period gets default space-join fallback) |

### Implementation shape

New module `Localize.DateTime.Format.AppendItems` with the symbol-to-field table, the missing-field algorithm, and an `augment_pattern/5` entry point:

```elixir
defmodule Localize.DateTime.Format.AppendItems do
  @moduledoc false

  @symbol_to_field %{
    "G" => :era, "y" => :year, "Y" => :year, "u" => :year, ...
  }

  @doc """
  Augments a matched pattern with append-item templates for any
  fields present in the requested skeleton but absent from the
  matched format. Iterates field-by-field; each iteration's
  output becomes the next iteration's `{0}` substitution.
  """
  def augment_pattern(matched_pattern, requested_skeleton, matched_skeleton, locale_id, calendar_type)
end
```

Insertion point in the resolver: a new `augment_pattern/5` call right after `Localize.DateTime.Format.Match.best_match/3` returns, threading through the requested skeleton (the matcher already has it) and the chosen format ID. Callers in `Localize.Date.resolve_skeleton/3`, `Localize.Time.resolve_skeleton/3`, and `Localize.DateTime.format_with_skeleton/4` each gain ~3 lines.

### Step-by-step plan

1. **Extend `data/normalize/date_time.ex`** to ingest `dateFields.<field>.displayName` from `cldr-dates-full__dateFields.json` into a new `dates.fields.<field>` shape in the locale ETF. Folds into the regeneration step that ships with CLDR 49 base data, so no interim ETF cycle.
2. **Add `Localize.DateTime.Format.append_items/2` and `Localize.DateTime.Format.field_display_name/3`** as accessors mirroring `available_formats/2`.
3. **Create `Localize.DateTime.Format.AppendItems`** with the symbol-to-field table, the missing-field algorithm, and `augment_pattern/5`.
4. **Wire `augment_pattern/5` into the three skeleton resolvers** (`Localize.Date`, `Localize.Time`, `Localize.DateTime`) after `best_match/3`.
5. **Tests** covering: `:yMMMdEEEE` against an `:yMMMd`-only locale (weekday appended via `:day_of_week`); `:yMMMdh` against `:yMMMd` (hour appended via the `{2}`-using `:hour` template); multiple missing fields (`:yMMMdEEEEha` against `:yMMMd` — `EEEE`, `h`, `a` each iteratively appended); locale where the field has no append-item entry (fallback to space-join); `{2}` substitutes the field display name from the new `dates.fields` data.

### API impact / breaking risk

* Internal change. The public API is unchanged.
* **Output may change** for skeletons that under-specify against the matched format — these previously rendered with the requested field silently dropped. A fix-not-feature; document in the changelog when 0.27 ships.

### Effort / sequencing

Roughly 1–2 days end-to-end once CLDR 49 data ingestion lands. Implementation order inside the cycle: (1) data normalizer change ships with the ETF regeneration; (2) runtime modules and tests follow. Total scope is small enough to be one feature-branch rather than a child plan of its own.

## 6. Minimal pairs

Spec: <https://unicode.org/reports/tr35/tr35-numbers.html#Minimal_Pairs>

### Current conformance

The CLDR JSON ships per-locale `minimalPairs` data inside `cldr-numbers-full__numbers.json` (we have the data on disk under `priv/cldr/locales/<locale>/cldr-numbers-full__numbers.json`).

`grep -rn "minimal" lib/ data/` returns nothing. We do not normalize this data, do not store it in ETF, and do not expose a runtime API.

### Gap

CLDR minimal pairs are short translated phrases that demonstrate plural and ordinal selection in context (e.g. for `:en`, the cardinal `one` minimal pair is `"{0} day"` and `other` is `"{0} days"`). They are the canonical worked examples for plural and ordinal rules and are intended for both translator review and runtime use in libraries that want a "show the user a sample" facility.

TR35 §Minimal_Pairs lists three categories:

* `pluralMinimalPairs[count]` — cardinal forms.
* `ordinalMinimalPairs[count]` — ordinal forms.
* `caseMinimalPairs[case]` — grammatical-case forms (Slavic locales, etc.).
* `genderMinimalPairs[gender]` — grammatical-gender forms.

### Plan

1. Add `data/normalize/minimal_pairs.ex` to extract the four maps from `numbers.minimalPairs`, `numbers.ordinalMinimalPairs`, `numbers.caseMinimalPairs`, `numbers.genderMinimalPairs` into a single normalized structure.
2. Persist under `priv/localize/locales/<locale>/numbers/minimal_pairs.etf`.
3. New module `Localize.MinimalPairs` exposing:
   * `cardinal(locale_id) :: %{plural_type => String.t()}`
   * `ordinal(locale_id) :: %{plural_type => String.t()}`
   * `grammatical_case(locale_id) :: %{atom() => String.t()}`
   * `grammatical_gender(locale_id) :: %{atom() => String.t()}`
   * `format(category, key, locale_id, value) :: String.t()` — picks the right pair for a given numeric value (delegates to `Localize.Number.PluralRule.plural_type/2`) and substitutes `{0}`.
4. Cross-check our plural/ordinal selectors against the minimal-pairs data for the reference locale set: every plural form CLDR ships should round-trip to itself when fed through `plural_type/2`. This is also a useful test of the NIF cross-validation suite.
5. Document the new module in the README's "Numbers" section.

### API impact / breaking risk

* New module `Localize.MinimalPairs`. Purely additive.
* Cross-check audit may surface bugs in our plural-rule implementation. Any fixes there go through the normal changelog.

## 7. Minimum / maximum significant digits

Spec: <https://unicode.org/reports/tr35/tr35-numbers.html#sigdig>

### Current conformance

Internally, `Localize.Number.Format.Compiler` and `Localize.Number.Format.Meta` already understand significant-digit patterns (`@@@`, `@@##`) — see [lib/localize/number/format/compiler.ex:362](lib/localize/number/format/compiler.ex:362) and [lib/localize/number/format/meta.ex:51](lib/localize/number/format/meta.ex:51). The decimal formatter in [lib/localize/number/formatter/decimal.ex:144](lib/localize/number/formatter/decimal.ex:144) applies `round_to_significant_digits/2` and `adjust_fraction_for_significant_digits/2` based on the `%{significant_digits: %{min: …, max: …}}` field of the compiled metadata.

But — the public `Localize.Number.Format.Options` struct does *not* expose these as caller-supplied options. The struct fields are:

```
:locale, :number_system, :currency, :format, :gender,
:grammatical_case, :currency_format, :currency_digits,
:currency_spacing, :currency_symbol, :symbols,
:minimum_grouping_digits, :pattern, :rounding_mode, :fractional_digits,
:min_fractional_digits, :max_fractional_digits, :maximum_integer_digits,
:round_nearest, :wrapper, :separators
```

There is no `:minimum_significant_digits` or `:maximum_significant_digits`. The only way a caller can request significant-digit rounding today is to write a literal pattern (`"@@##"`).

### Gap

* Callers can't say "round to 3 significant figures" through the public option API.
* TR35 specifies these as standard formatting parameters; ECMA-402's `Intl.NumberFormat` exposes them; ex_cldr exposes them. Localize should match.

### Plan

1. Add `:minimum_significant_digits` and `:maximum_significant_digits` to `@options` in [lib/localize/number/format/options.ex:11](lib/localize/number/format/options.ex:11).
2. In `validate_options/2`, when either option is set:
   * Validate ranges (1..21 per ECMA-402; TR35 doesn't cap, but we should refuse 0 except as the documented "unset" sentinel and refuse negatives).
   * Inject `%{min: <min>, max: <max>}` into the resolved struct's `significant_digits` field, using the same shape the compiler already produces. The decimal formatter's existing rounding path picks them up unchanged.
3. New doctests on `Localize.Number.to_string/2`:

```elixir
iex> Localize.Number.to_string(1234.5678, minimum_significant_digits: 3)
{:ok, "1,230"}

iex> Localize.Number.to_string(0.001234, maximum_significant_digits: 2)
{:ok, "0.0012"}
```

4. Ensure interaction with `:fractional_digits`, `:min_fractional_digits`, `:max_fractional_digits` is well-defined (TR35: significant-digit settings *override* fractional-digit settings when both are supplied). Document the precedence rule.

### API impact / breaking risk

* Two new option keys. Purely additive.
* Existing pattern-driven significant-digit behaviour is unchanged.

## 8. RBNF syntax audit — ✅ Done (Localize 0.26.0)

Spec: <https://unicode.org/reports/tr35/tr35-numbers.html#RBNF_Syntax>

The full audit, eleven-bug ledger, fix-by-fix walkthrough, behavioural deltas, and remaining deferred items live in [plans/rbnf.md](rbnf.md). Summary for this CLDR-49 plan:

### Outcome

Eleven bugs identified; nine fixed across nine commits on branch `rbnf-fixes` (Bugs A, B, C, D, E, F, G, H, L) plus three follow-up items (§1 numerator/denominator algorithm, §2 integer `>>>` preceding-rule semantic, §4 Decimal input). All shipped in Localize 0.26.0 (2026-05-05). Three latent bugs are deferred:

* **Bug I** — `Inf` / `NaN` rules unreachable from the public API. Erlang has no native NaN; reaching these would require accepting `:infinity` / `:nan` atoms or threading Decimal-with-error end-to-end. Out of scope.
* **Bug J** — `<<<` parser rejects with syntax error. Zero CLDR locales use `←←←`; close as a parser fix when (if) a future CLDR release adds it. The fix shape mirrors Bug A.
* **Bug K** — `Nx.x` (leading-zero count > 0) rules unsupported. Zero CLDR locales currently use them. Re-review at each CLDR alpha/beta/RC.

### Verification

- 123 RBNF tests in [test/localize/number/rbnf_test.exs](../test/localize/number/rbnf_test.exs); full Number-suite is 564 tests (was 480 pre-audit; 84 new).
- `mix dialyzer` clean.

### CLDR 49 review checklist

Re-run on the CLDR 49 alpha drop:

* Diff `priv/cldr/locales/*/rbnf.json` for any new `>>>` or `<<<` usages, new `Nx.x`-base rules, or any new `Inf`/`NaN` rule shapes.
* Re-run the full RBNF test suite against the new ETF data and surface any unexpected output deltas.
* Update [plans/rbnf.md](rbnf.md)'s coverage matrix and bug ledger with any new findings.

## 9. RBNF data-format change: rule removal

Spec: <https://unicode.org/reports/tr35/tr35-numbers.html#RBNF_Remove_Ruleset_Rule>

### Current conformance

`data/normalize/rbnf.ex` ingests the `rbnf-XXX.json` files emitted by the cldr-json pipeline. Each ruleset is currently treated as *additive* — the rules listed under a ruleset name in the JSON become the rules for that ruleset in our ETF.

### Gap

TR35 introduces (or formalises, depending on when it landed) a "remove rule from ruleset" mechanism. CLDR data may now ship rules that *remove* a specific rule from an inherited ruleset rather than adding to or replacing it. Our pipeline doesn't know about removals; inheriting from a parent locale silently produces a superset.

The on-disk JSON format change to support this (per TR35) usually manifests as either:

* a sentinel value (e.g. an explicit "removed" marker) on the rule; or
* an inheritance key indicating that the rule from the parent should be excluded.

We need to confirm CLDR 49's exact JSON shape during the alpha review (item 2) and adapt accordingly.

### Plan

1. During CLDR 49 alpha, dump a representative `rbnf-XXX.json` and diff it against our 48.2 fixtures. Identify the new shape for removed rules.
2. Update `data/normalize/rbnf.ex` to:
   * Detect the removal marker.
   * When materialising a ruleset, apply removals after the parent-locale merge step.
3. Update the ETF schema for RBNF rulesets (if needed). This is an internal-format change; no public API breakage. The on-disk ETF files change shape, which means a Localize release that ships CLDR 49 also ships fresh ETFs — users simply pick up the new ETFs along with the new code.
4. Re-run the RBNF test suite (already comprehensive after item 8's audit landed in 0.26.0) against the regenerated ETFs and surface any output deltas in the changelog.

### API impact / breaking risk

* No public API change.
* ETF schema for RBNF rulesets may bump. Internal-only; users don't read ETFs directly.
* If a customer has *vendored* our ETFs (very unusual) they would need to regenerate. Mention this in the upgrade-notes section of the release.

### Broader RBNF source-format change (moved from TODO.md, 2026-05-14)

Beyond the rule-removal mechanic above, RBNF rules are in a new text format in the source XML for CLDR 49. They may also be differently formatted in the generated JSON. We need to move to using the new format. This means:

1. Investigate the source data for RBNF in our pipeline.
2. Review any changes to the rule layout in the source data.
3. Adapt to the new format (but generate the same output in our pipeline).

This is more general than the rule-removal change covered above; it should be resolved in the same item-9 work pass once the CLDR 49 alpha drop lets us see the actual XML/JSON shape.

## 10. CLDR 48.2 §Modifications retrospective — ✅ Done

Spec: <https://unicode.org/reports/tr35/tr35-modifications.html#modifications>

The full audit lives in [plans/cldr-48-retrospective.md](cldr-48-retrospective.md). 23 modifications classified; 14 covered as code applied (including person-name validation in the sibling Hex package `localize_person_names`, rational-number formatting via `Localize.Number.to_ratio_string/2`, and mixed-unit precision verified empirically), 4 as data-only, 3 deliberately skipped, 2 follow-up tasks filed (§A `gmtUnknownFormat` consumer, §B `FractionalUCA_blanked.txt` ingestion). Both follow-ups are minor data-consumption gaps and ride the CLDR 49 ETF regeneration; neither blocks the 0.27 cut. The retrospective also defines the format and process for future per-CLDR-version audits — when CLDR 49 ships its own modifications log, the same template applies.

### Current conformance

We adopted CLDR 48.2 as our base. The TR35-modifications page is the canonical "what changed in this CLDR version" log and lists every behavioural change, deprecation, and renaming since 48.0. Our adoption was largely data-driven, with implementation work as needed.

### Gap

We have not produced a structured retrospective comparing our 48.2 implementation against every line of the modifications page. There are likely items we picked up implicitly (because the data carries the change) and items we silently missed (because they require runtime support).

### Plan

1. Walk the TR35 §Modifications log section by section. For each bullet, classify our handling:
   * **Data-only**: covered by the ETF refresh, no code change needed. Tick.
   * **Code change applied**: link the PR / commit. Tick.
   * **Code change pending**: file an item in `plans/`.
   * **Decision: skip**: justify (rare, e.g. an experimental BCP-47 extension we deliberately don't surface).
2. For "code change pending" items, fold them into the CLDR 49 work if they are small; otherwise spin out separate plans.
3. Particular areas worth re-checking based on the kinds of changes typical of a `.x` CLDR release:
   * Currency display selection (`narrow` vs `symbol`).
   * Day-period rules for non-trivial locales.
   * Person-name patterns (CLDR added significant material here in 46/47/48).
   * Locale matching distance tables.
   * Likely-subtags additions/removals.
4. Capture the result as `plans/cldr-48-retrospective.md` so future upgrades have a precedent format.

### API impact / breaking risk

* Per finding. Most are likely additive or data-only. Any that turn out to be breaking are surfaced here before the CLDR 49 ship.

## 11. `localize_emoji` sibling library

### Current conformance

CLDR ships emoji *annotations* and *annotationsDerived* under `common/annotations/<locale>.xml` (and on disk in our cldr-staging clone at `~/Development/cldr/cldr_repo/common/annotations`). `scripts/ldml2json_v2` includes the `cldr-annotations-full` and `cldr-annotations-derived-full` packages; the v1 script does not. Localize itself does not currently ship any annotations data, has no emoji lookup surface, and no normalizer covers `cldr-annotations*`.

### Gap

Customers want to find emoji by:

1. **Name** — short or long English/locale name (e.g. `"smiling face"`).
2. **Tag** — one or more freeform CLDR tags (e.g. `"face"`, `"happy"`, `"man"`).
3. **Boolean tag query** — combinations like `"man and not smiling and dark skin"`.

The third use case is the differentiator. Existing Hex packages expose at most cases 1 and 2.

### Plan — package shape

Create a sibling Hex package `localize_emoji` (separate package, this keeps the main Localize lean and avoids forcing every Localize user to download megabytes of annotation data they don't need). The package depends on `localize` for shared infrastructure (`Localize.LanguageTag`, `Localize.Locale.Provider`, `Localize.DataLoader`) and uses the same ETF caching pattern.

Repository layout:

```
localize_emoji/
├── lib/
│   └── localize_emoji.ex            # main API
│   └── localize_emoji/
│       ├── annotation.ex            # struct: codepoint, names, tags
│       ├── query.ex                 # boolean-query DSL
│       └── data.ex                  # ETF loader (delegates to DataLoader)
├── priv/
│   └── localize_emoji/
│       └── annotations/<locale>.etf
├── data/
│   └── normalize/annotations.ex     # CLDR JSON → ETF
└── mix.exs
```

### Plan — public API

```elixir
@spec all(Localize.locale()) :: [LocalizeEmoji.Annotation.t()]
def all(locale \\ Localize.get_locale())

@spec lookup(String.t(), Localize.locale()) ::
        {:ok, LocalizeEmoji.Annotation.t()} | {:error, :not_found}
def lookup(emoji, locale \\ Localize.get_locale())

@spec search(String.t(), Localize.locale(), keyword()) ::
        [LocalizeEmoji.Annotation.t()]
def search(query_string, locale \\ Localize.get_locale(), opts \\ [])
```

`Annotation.t()`:

```elixir
%LocalizeEmoji.Annotation{
  codepoint: <<...>>,           # the emoji string itself
  short_name: String.t(),       # `"smiling face"` for :en
  tags: [String.t()],           # `["face", "happy", "smile"]`
  derived?: boolean(),          # true for ZWJ/skin-modifier composites
  group: atom(),                # CLDR group e.g. :smileys_emotion
  subgroup: atom()              # e.g. :face_smiling
}
```

### Plan — query DSL

`search/3` accepts either a *natural-language* string parsed into a boolean tree, or a pre-built tree. Natural-language form:

```
"face and (happy or smiling) and not sad"

"man and not smiling and dark skin"

"\"smiling face\""        # quoted exact substring on short_name
```

Operators (case-insensitive):

| Form          | Meaning                                                 |
|---------------|---------------------------------------------------------|
| `term`        | tag or name substring (depends on `:fields` opt)        |
| `"phrase"`    | exact substring match against `short_name`              |
| `a and b`     | both must match                                         |
| `a or b`      | either matches                                          |
| `not a`       | doesn't match                                           |
| `(a or b) and c` | parentheses for precedence                           |

`opts`:
* `:fields` — `[:tags]` (default), `[:short_name]`, or both.
* `:limit` — cap on results.
* `:order` — `:cldr` (default; CLDR's own order, useful for picker UIs) or `:alphabetical`.

Programmatic form, for callers who don't want to parse a string:

```elixir
import LocalizeEmoji.Query

q = and_([tag("man"), not_(tag("smiling")), tag("dark skin tone")])
LocalizeEmoji.search(q, :en)
```

### Plan — data pipeline

1. Add `data/normalize/annotations.ex` (lives in `localize_emoji`'s data directory) to ingest cldr-annotations JSON. Combine `annotations` + `annotationsDerived`; mark derived entries with `derived?: true` on the struct.
2. Build a per-locale tag index: `%{tag => [codepoint, …]}`. Persist it alongside the annotation list so `search/3`'s tag-matching is O(1) per term.
3. Consider a name-substring index (e.g. trigram over `short_name`) — defer until benchmarks demonstrate need; naive substring scan is likely fine for ~3500 entries.

### Plan — release sequencing

1. Stand up the package skeleton on `main` with empty data.
2. Bring up the normalizer once `scripts/ldml2json_v2` is the default (item 1 prerequisite).
3. Hex `0.1.0` release with English data only.
4. Subsequent releases add locales as the data is regenerated.

### API impact / breaking risk

* New package; nothing in `localize` itself changes.
* Boolean-query parser is a new surface; needs care with operator precedence and lookahead. Cover with property tests.

## 12. `common/testData` conformance-fixture audit

Source: `$CLDR_REPO/common/testData/` in the upstream `unicode-org/cldr` checkout. Browseable at <https://github.com/unicode-org/cldr/tree/main/common/testData>.

### Current conformance

We pull selected fixtures from `common/testData` (e.g. number-format, RBNF, plural-rules, transform, units) into `test/cldr_conformance/` and replay them through the Localize runtime. Coverage is partial: directories that existed when each runtime module was first ported got picked up, but no one has done a sweep against the full `common/testData` tree since.

### Gap

CLDR 49 is expected to land new and expanded fixtures, most notably:

* **Decimal formatting** — CLDR 48 added significant-digits coverage and shape-checked rounding-mode behaviour; CLDR 49 is signposted to add more cases (track at <https://cldr.unicode.org/downloads/cldr-49>). These would exercise items 7 (min/max significant digits) and any number-format edge cases the team has not seen.

* New or expanded fixtures for any directory we currently don't ingest. Likely candidates to re-check post-49: `localeIdentifiers/`, `personNameTest/`, `units/`, `transforms/`, `dateTimeFormat/`.

### Plan

1. At CLDR 49 alpha, run `diff -r $CLDR_REPO_48/common/testData $CLDR_REPO_49/common/testData --brief` to list directories with deltas.

2. For each delta directory, decide:

   * Already-ingested fixture file → re-import the new revision, run the existing conformance suite, fix regressions.

   * New fixture file in an ingested directory → add a loader and assertions in `test/cldr_conformance/`.

   * New directory entirely → assess whether the module under test exists in Localize. If yes, add a new conformance test file. If no, log as a future-work item and link to the corresponding plan section.

3. Specifically gate item 7 (min/max significant digits) on the CLDR 49 decimal-formatting fixtures — implementation lands together with the conformance tests that prove it.

4. Record the fixture revision (CLDR version + git SHA) in each `test/cldr_conformance/*.exs` file's header so future audits can tell stale fixtures from current.

### API impact / breaking risk

* None. Test-only work.

* May surface latent bugs that need fixes — those go through the normal changelog.

## 13. CDN-asset checksum manifests for download-time validation — ✅ Done (Localize 0.44.0)

**Status:** shipped early, ahead of the CLDR 49 cycle. `priv/localize/locale_hashes.etf` (packaged) maps locale → SHA-256 of the CDN object bytes; `Localize.Locale.Provider` verifies every download before decode and fails closed with `Localize.LocaleIntegrityError`. The manifest is regenerated with `mix localize.generate_locale_hashes --from-cdn` *after* upload, so it hashes the bytes consumers actually receive. Process and the OTP-encoding trap that motivated `--from-cdn` are documented in [CLDR_UPDATE_INTEGRATION.md](../CLDR_UPDATE_INTEGRATION.md). The research questions below are retained for the record; the signature-scheme options were not pursued — a packaged hash manifest proved sufficient.

**Motivation.** Security audit §4.1 identified that `Localize.Locale.Provider.Cache` decodes downloaded ETFs with `:erlang.binary_to_term/1` (no integrity check, no `[:safe]`). The audit recommended `[:safe]`, but issue [#25](https://github.com/elixir-localize/localize/issues/25) showed that legitimate locale ETFs encode atoms the runtime hasn't yet interned, so `[:safe]` rejects valid input. We reverted `[:safe]` in 0.30.1 (see CHANGELOG). The original DOS surface — a writable `:locale_cache_dir` plus a hostile or compromised CDN serving a maliciously-crafted ETF — is therefore re-opened.

Cryptographic integrity is the right substitute for `[:safe]`: if we can prove the downloaded bytes came from our build pipeline, we don't need to defend against malicious atom payloads inside them.

### Current state

* CDN assets live at `https://elixir-localize.com/locales/v<localize-version>/<locale-id>.etf`. URL versioning is by Localize version (`v0.30.0` etc.), so each Localize release pins a snapshot of locale data.

* No manifest, no signature, no checksum is published alongside the ETFs.

* `Localize.Utils.Http.get/2` already enforces a 50 MB body cap (0.30.0); SSL peer verification is on by default. Those are wire-level defences, not content-level integrity.

### Gap

* **Manifest format.** Likely a JSON or ETF document at `https://elixir-localize.com/locales/v<localize-version>/manifest.{json,etf}` mapping locale id → SHA-256 (or SHA-512) of the corresponding ETF. Signed? Or rely on TLS for transport integrity and only use checksums for content-level tamper detection? Decide.

* **Verification path.** Cache miss → download ETF → check size → compute hash → look up in manifest → match? decode : reject. Manifest itself must be fetched and cached; how often is it re-checked? Once per BEAM lifetime is probably enough.

* **Hot-path budget.** SHA-256 on a typical locale ETF (~100 KB – 5 MB) is sub-millisecond on modern hardware via `:crypto.hash/2`. Acceptable for download path; not on every cache read (we read from the local cache, not from network, on the hot path). Need to confirm with measurement.

* **Manifest staleness vs. partial CDN deploys.** If we ship a hotfix that updates one locale ETF without bumping Localize version, the manifest needs to update too — atomically. Either we treat the URL prefix as immutable (recommended) and never partial-update, or we expose a manifest version separate from the Localize version.

* **Signed manifests.** Optional but cheap to add: sign the manifest at build time with an Ed25519 key, ship the public key in the package, verify on fetch. Closes the "malicious CDN" vector even without TLS trust. Open question: where to store the key, how to rotate.

* **Failure modes.** What happens when the manifest is unreachable or its signature doesn't verify? Hard-fail vs. fall back to bundled-package data. Both have trade-offs.

* **Bundled-data scope.** The bundled `priv/localize/locales/en.etf` (shipped with the package) doesn't need a network checksum — it ships in the package signature itself (Hex package checksum). The check is specifically for CDN-downloaded assets.

### Plan

1. **Measure.** Run `:crypto.hash(:sha256, etf_bytes)` against the 50 largest locale ETFs we ship. Confirm the hot-path budget (target: well under 10 ms even for the biggest).

2. **Decide manifest shape.** Likely JSON for human-readability and easy regeneration:
   ```json
   {
     "version": "0.31.0",
     "generated": "2026-10-25T00:00:00Z",
     "locales": {
       "en":        {"size": 152398, "sha256": "abc123…"},
       "en-AU":     {"size": 156102, "sha256": "def456…"},
       ...
     }
   }
   ```
   Or ETF if we want to use the same loader. Decide.

3. **Wire up the build pipeline.** `scripts/build_cdn_release` (does not yet exist) emits the per-locale ETFs and the manifest in lockstep. Probably a Mix task: `mix localize.build_cdn_release v0.31.0`.

4. **Runtime verification.** Extend `Localize.Locale.Provider.PersistentTerm.load_miss/2` (production branch) to fetch the manifest on first use, cache it in `:persistent_term`, and verify each downloaded ETF against it before passing to `binary_to_term/1`. Reject (or fall back to bundled data) on mismatch.

5. **Signed-manifest option.** If we decide to sign, generate an Ed25519 keypair, store the public key as a module attribute (compile-time, bundled with the package — same trust as the .beam files), sign the manifest at build time. Use `:public_key.verify/4`.

6. **Bundled-package case.** Bundled ETFs (`priv/localize/locales/*.etf`) skip verification — they're trusted by package signature. Code-path: check the cache directory, and if the file came from the bundled `priv` location, skip the hash check.

### API impact / breaking risk

* No public API changes. Internal load path adds a verification step on the download branch only.

* Cache-miss latency increases by `manifest_fetch + hash_compute`. Manifest fetch is one-time per BEAM lifetime; hash compute is per-locale-on-first-fetch. Should be unnoticeable in practice.

* Breaking risk if the manifest URL goes down: deployments without `:allow_runtime_locale_download` are unaffected (they don't fetch). Deployments that opt in need a stable CDN — same dependency as today.

### CLDR 49 hook

Generating a manifest is a natural insertion point when the CLDR 49 ETF pipeline runs. Treat manifest generation as a required output of the build pipeline from 0.31.0 onwards.

### Open research questions

* Is SHA-256 enough, or should we use SHA-512 for forward-compatibility? (Size cost: 32 bytes vs. 64 bytes per locale in the manifest. Trivial.)

* Should the manifest be served via the same URL prefix as the locale data (versioned with Localize), or a separate "data version" axis? The first is simpler; the second supports hotfixes.

* If we sign the manifest, what's the key-rotation story? Probably: publish key fingerprint in the package release notes; verify against any of the last N keys. Need to think.

* For air-gapped deployments: should there be a way to ship a manifest with the package (so download-and-verify works from a local mirror)?

## 14. Japanese pre-Meiji eras: keep and curate

The design plan — validation methodology, primary sources, per-era tracking table, and the JSON research dataset — lives in [plans/japanese_eras.md](japanese_eras.md). This section is the CLDR 49 scope statement and the pipeline hook; the child plan is the source of truth for the curation work.

### Current conformance

`priv/localize/supplemental_data/calendars.etf` carries all 237 CLDR Japanese eras as `[index, %{start: [y, m, d]}]` — indices 0 (大化, 645) through 236 (令和). Localize formats and parses the full range today.

### Gap

CLDR 49 drops era data for every era before Meiji — indices 0–231, which is **232 of the 237 entries**. Only Meiji through Reiwa (232–236) survive upstream.

This is the one item in this plan where doing nothing is not a no-op. A routine Phase 1–3 run against CLDR 49 sources regenerates `calendars.etf` from upstream and silently deletes 232 eras. Nothing fails: no test asserts on ancient era data, the pipeline reports success, and the loss surfaces only when a consumer formats a historical date. Localize's position is that the use cases needing this data — academic publishing, genealogy, museum cataloguing, calendar conversion — are exactly the ones CLDR is stepping back from, so we keep shipping it and own the validation.

### Plan

1. **Before regenerating**, snapshot the current pre-Meiji era set out of `calendars.etf` — it is the last upstream-sourced copy.
2. Add a pipeline merge step so era generation unions the CLDR 49 modern eras with our curated pre-Meiji snapshot, rather than taking upstream wholesale. The curated set becomes source data we maintain, not generated output.
3. Land the corrections already identified by the first-pass research: [plans/japanese_eras.md](japanese_eras.md) records **three confirmed CLDR data errors** and two convention questions across the 237 entries.
4. Add a regression test asserting the era count and the boundary entries (index 0 大化 and index 232 明治), so a future pipeline change cannot silently drop the set again.
5. Continue the per-era validation pass on its own schedule — it does not gate the CLDR 49 release, but the merge step and the regression test do.

### API impact / breaking risk

No API change: the data stays where it is and the era range is unchanged. The risk is entirely in *not* doing this — a silent narrowing of supported dates from 645 CE to 1868 CE.

## 15. POSIX `yesstr` / `nostr` affirmative and negative responses

Spec: <https://unicode.org/reports/tr35/tr35-general.html#POSIX_Elements>

### Current conformance

Not implemented. CLDR ships these under `<posix><messages>` in the locale XML, and cldr-json exposes them as `cldr-misc-full/main/<locale>/posix.json`. All 766 locales in the CLDR 48.2.2 JSON distribution carry the file; 271 locales define the strings in the XML directly, the rest inherit.

`"posix"` is absent from `@required_modules` in [data/locale.ex:13](../data/locale.ex:13), so the values never enter the locale ETFs and there is no API to read them. The existing `POSIX` references in `lib/` are about POSIX-form *locale identifiers* (`"pt_BR"`), which is unrelated.

### Gap

There is no way to ask Localize what a locale's affirmative and negative responses are. A CLI prompt, a terminal confirmation, or anything porting a POSIX `LC_MESSAGES` workflow has to hard-code English `y`/`n`, which is exactly the class of hard-coding this library exists to remove.

The values are a colon-separated list of the forms a locale would accept:

| locale | `yesstr` | `nostr` |
|--------|----------|---------|
| `en`   | `yes:y`  | `no:n`  |
| `de`   | `ja:j`   | `nein:n` |
| `fr`   | `oui:o`  | `non:n` |
| `ja`   | `はい:y` | `いいえ:n` |
| `ar`   | `نعم:ن`  | `لا:ل`  |

### Plan

1. Add `"posix"` to `@required_modules` in [data/locale.ex:13](../data/locale.ex:13) and a normalizer under `data/normalize/` that lifts `messages.yesstr` and `messages.nostr` into a `posix` key, splitting each on `":"` into a list. Regenerate the `:en` and `:und` ETFs per the data-pipeline rule in CLAUDE.md.
2. Expose readers returning the accepted forms, defaulting the locale to `Localize.get_locale/0`:

```elixir
iex> Localize.affirmative_responses(:de)
{:ok, ["ja", "j"]}

iex> Localize.negative_responses(:fr)
{:ok, ["non", "n"]}
```

3. Add a predicate over the two, which is the operation a caller actually wants at a prompt. TR35 is explicit that the stored value carries only the lower-case forms and that a consumer generates the upper-case and abbreviated variants, so matching must case-fold rather than compare literally:

```elixir
iex> Localize.affirmative?("Ja", locale: :de)
true

iex> Localize.affirmative?("y", locale: :de)
false
```

4. Decide whether to follow the rest of TR35's POSIX guidance — "add the English words wherever they do not conflict", so `de` would also accept `yes`/`y` because neither collides with `nein`/`n`. It makes a prompt more forgiving and it is what POSIX tooling does, but it is a judgement call about conflicts rather than data we can read, so it belongs behind an option (`english_fallback: true`) rather than in the default.

### API impact / breaking risk

* New functions and one new locale-data key. Purely additive.
* One ETF schema addition, so the data version bumps; no public API changes shape.

## 17. `H24` hour cycle deprecated

### Current conformance

`Localize.Time` treats `:h24` as a first-class hour cycle: it is in the `@type`, in the options table of the `hour_cycle/2` docs, and `hour_cycle_from_symbol("k")` returns it. Sixteen references across `lib/`.

### Gap

CLDR 49 deprecates `H24` ([CLDR-18303](https://unicode-org.atlassian.net/browse/CLDR-18303)). Where it is encountered it is to behave as `H23`. The release note records no known intentional usage.

### Plan

1. Keep accepting `:h24` and the `k` pattern symbol — deprecated in CLDR does not mean absent from data a consumer already holds, and rejecting it would break input we currently parse.
2. Resolve `:h24` to `H23` behaviour at format time, so a `k` pattern renders midnight as `0` rather than `24`.
3. Document `:h24` as deprecated in `Localize.Time`, noting it resolves to `:h23`.
4. Confirm whether CLDR 49 still emits `k` in any locale's `hourCycle` or preferred-pattern data. If it does not, the resolution is defensive only.

### API impact / breaking risk

No signature change. Output changes for the `k` symbol at midnight, which is the intent of the deprecation.

## 18. Week-of-year numbering follows ISO by default

### Current conformance

Week numbering has two paths in `datetime/formatter.ex`. For `Calendar.ISO` dates, `locale_week_of_year/2` computes the week locally from the locale's CLDR `firstDay` and `minDays` (`week_config/1`). For every other calendar it calls `iso_week_of_year/1`, which delegates to `calendar.iso_week_of_year/3` when the calendar exports it and otherwise falls back to `:calendar.iso_week_number/1`.

That second path is already correct and needs no work: `Calendrical.Gregorian` and its siblings export `iso_week_of_year/3` and Localize honours whatever they return. Only the `Calendar.ISO` path is in scope, and only because `Calendar.ISO` itself has no week support for us to defer to.

### Gap

CLDR 49 changes the default week numbering to follow ISO — weeks numbered by the Thursday rule — while the calendar week is "more clearly targeted at matching usage in displayed month calendars" ([CLDR-18275](https://unicode-org.atlassian.net/browse/CLDR-18275)). The data now says so explicitly: `weekData` in `supplementalData.xml` carries the comment `this firstDay is for the first day of the week in a calendar page view`.

So `firstDay` and `minDays` describe *month-calendar layout*, and using them to number weeks — which is what the `Calendar.ISO` path does — is applying the wrong data to the question. The divergence is real for locales whose calendar week is not the ISO week. Measured against CLDR 48 data:

| date | `en` today | ISO |
| --- | --- | --- |
| 2027-01-01 | 2027-W1 | 2026-W53 |
| 2027-01-03 | 2027-W2 | 2026-W53 |
| 2026-12-31 | 2027-W1 | 2026-W53 |

`en-GB` (`firstDay=mon`, `minDays=4`) already agrees with ISO; `en` (`firstDay=sun`, `minDays=1`) does not. The `Y`, `w` and `W` pattern symbols all render through this path, so the change is a silent difference in output rather than an error.

### Plan

1. Separate the two concepts. Week *numbering* for `Calendar.ISO` follows ISO by default; `firstDay`/`minDays` remain the source for month-calendar layout and for `Localize.Calendar.first_day_for_locale/1`, which is a different question with a different answer.
2. Establish whether CLDR 49 supplies per-locale week-numbering data distinct from `weekData`, or whether ISO is simply the universal default with no locale variation. The `weekOfPreference` element is about which of `weekOfYear`/`weekOfMonth`/`weekOfInterval` a locale prefers to *display*, not how a week is numbered, so it is not that source.
3. Decide whether an option is warranted for callers who want the old calendar-week numbering, or whether following CLDR is sufficient. Prefer following CLDR.
4. Regression-test the year boundary specifically — 1 and 3 January, 31 December — for a locale on each side of the divide (`en`, `en-GB`) and for a non-ISO calendar, to confirm the delegating path is untouched.

### API impact / breaking risk

No signature change. **Rendered week numbers change** for locales whose calendar week is not the ISO week, `en` among them. Anything persisting a formatted `Y`-`w` string, or keying on one, sees different values across the upgrade. Worth a changelog entry in its own right.

## 19. Supplemental data files reorganized

### Current conformance

The pipeline reads `common/supplemental/supplementalData.xml` and `supplementalMetadata.xml` directly, and the normalizers under `data/normalize/` are written against their current element layout.

### Gap

CLDR 49 announces that the major components of both files are to be "organized more logically and moved into separate files", with the release note asking implementations to "plan to update XML and JSON parsers accordingly". The data itself is unchanged; only its location moves.

Whether this lands *in* 49 or is announced *by* 49 for a later release needs confirming — it appears under "V49 advance warnings", which elsewhere in that section describes changes that do land in 49.

### Plan

1. Confirm the timing against the alpha and beta trees: if the files have already split, the new paths are visible under `common/supplemental/`.
2. Inventory which elements the pipeline reads from each file, so a split is a matter of repointing rather than rediscovery.
3. Prefer resolving elements by name across the supplemental directory rather than by file, so a future reorganization is a no-op.

### API impact / breaking risk

None to the public API. A build-time failure if the pipeline is run against reorganized sources without adjustment, which is the good failure mode — loud, and before anything ships.

## 20. Iran subdivision codes are stale upstream

### Current conformance

`Localize.HTML.Subdivision` (in `localize_web`) renders 31 Iranian subdivisions, all named, keyed on numeric codes (`"03"`, `"06"`, `"08"`).

### Gap

CLDR 49 records under Known Issues that the ISO 3166-2 subdivision codes for Iran changed in 2020 and that no equivalent stable codes yet exist ([CLDR-19060](https://unicode-org.atlassian.net/browse/CLDR-19060)). The codes we ship are therefore the pre-2020 set.

This is not ours to fix — there is nothing upstream to adopt — but it matters more than it would have before, because subdivision codes are now a value a user stores in an address rather than an internal identifier.

### Plan

1. No code change. Track [CLDR-19060](https://unicode-org.atlassian.net/browse/CLDR-19060) and adopt whatever CLDR settles on.
2. Note the caveat in the `Localize.HTML.Subdivision` documentation, so an application storing Iranian subdivision codes knows they are expected to change.
3. When new codes arrive, they are a data migration for consumers, not merely a regeneration — worth a prominent changelog entry at that point.

### API impact / breaking risk

None now. A future CLDR change to these codes invalidates stored values, which is a consumer-facing migration whenever it lands.

## 21. Metazone transitions gain seconds precision — ✅ Fixed

### Current conformance

`Localize.Data.Supplemental.metazone_instant/1` parsed the `_from` / `_to` timestamps on `metazoneInfo` entries in `cldr-core/supplemental/metaZones.json`, which CLDR had always written to the minute as `"YYYY-MM-DD HH:MM"`. It appended `":00"` unconditionally to supply the seconds `NaiveDateTime.from_iso8601!/1` requires.

### Gap

CLDR 49 writes one of those timestamps with seconds already present. `Africa/Monrovia` moves to the `GMT` metazone at `"1972-01-07 00:44:30"`, where CLDR 48 rounded it to `"1972-01-07 00:45"` — Liberia ran on UTC−00:44:30 until 1972, the last country to adopt a whole-hour offset, and the true instant is now recorded. Appending the seconds a second time produced `"1972-01-07 00:44:30:00"`, which is not a datetime in any format, and `mix localize.generate_supplemental` aborted on it.

The data is mixed rather than migrated: 487 of the 488 `_from`/`_to` values are still `HH:MM` and exactly one carries seconds, so a parser that simply assumes the new shape fails on everything else.

### Resolution

`metazone_instant/1` appends the seconds only when the value does not already carry them, splitting on `:` and padding the two-field form. Both shapes were confirmed to parse. Worth noting the failure mode this avoided: a lenient parser would have accepted the malformed string, recorded a wrong instant for Monrovia and shipped it. The pipeline stopping dead is the better outcome, and is why the compile gate sits where it does.

### API impact / breaking risk

None. The generated instant for `Africa/Monrovia` is 30 seconds earlier than the CLDR 48 value, which is a correction rather than a regression, and it affects metazone resolution only for timestamps inside that 30-second window in 1972.

## 22. RBNF rules externalised to ICU text, plus `[A|B]` alternation — ✅ Fixed

This is the "broader RBNF source-format change" foreshadowed in item 9, now that CLDR 49 alpha 2 shows the actual shape. The rule-removal mechanic in item 9 remains open; nothing in CLDR 49's data exercises it yet.

### Current conformance

`data/normalize/rbnf.ex` read every ruleset inline from `cldr-rbnf/rbnf/<locale>.json`, and `src/localize_rbnf_lexer.xrl` / `src/localize_rbnf_parser.yrl` tokenised and parsed the rule definitions found there.

### Gap

Two independent changes, either of which alone silently produces a locale with no RBNF at all.

**The JSON no longer carries rules.** A rule group is now a pointer — `%{"_rbnfRulesFile" => "en-SpelloutRules.txt"}` — naming an ICU-syntax text file that sits flat in `cldr-rbnf/rbnf/` beside the JSON. `mix localize.copy_sources` vendored the JSON alone, so the vendored tree held 147 files of pointers to files that were never copied, and every locale normalised to `available: []`. The failure is quiet: no ruleset is malformed, there simply are none.

**Rule bodies gained an alternation operator.** Where CLDR 48 wrote `20: twen→%%tieth→;` and leaned on a private `%%tieth` helper ruleset, CLDR 49 writes `20: twent[y->>|ieth];` — inside the existing optional-substitution brackets, `|` separates the text used when the remainder is non-zero from the text used when it is zero. So `twent[y->>|ieth]` spells both "twenty-first" and "twentieth" from one rule. The construct appears on 2,165 rule lines across 28 of the 147 files, including every `spellout-ordinal` scale rule in `en` from `20` to `1000000000000000`.

### Resolution

* `data/data.ex` — `copy_rbnf_rule_files/3` reads each `_rbnfRulesFile` out of the JSON and copies the named `.txt` beside it, so a vendored locale directory is self-contained. All 147 files now land in `priv/cldr/locales/<locale>/`.

* `data/normalize/rbnf.ex` — `resolve_rule_files/2` swaps a pointer for the parsed contents of the file it names before the existing `rules_from_rule_sets/1` runs, so the rest of the normalizer is untouched and produces the same shape as before. A group that still carries inline rules passes through unchanged, which keeps the normalizer working against CLDR 48 sources.

* `src/localize_rbnf_lexer.xrl` / `src/localize_rbnf_parser.yrl` — `|` is tokenised as `alternate` (ordered before the catch-all `{Char}` rule so it is never absorbed as literal text) and the grammar gains `rule_part -> conditional_start rbnf_rule alternate rbnf_rule conditional_end`, yielding `{:conditional_alternate, {present, absent}}`. No grammar conflicts; the plain `[A]`, `<<`, `>>` and `→%%rule→` forms parse exactly as before.

* `lib/localize/number/rbnf/processor.ex` — `do_operation(:conditional_alternate, …)` mirrors the `:conditional` clause, rendering the second branch where the first renders `""`.

A survey of all 147 files backs the text reader's assumptions: 23,538 lines, of which 1,238 are public ruleset headers, 438 private, and 21,862 rule lines — zero blank, comment or unclassified lines, no rule spanning two lines, and no rule name containing a colon, so the first colon always separates name from definition. Every `|` falls inside exactly one `[...]`, never two to a bracket.

### API impact / breaking risk

None. The generated ETF shape is unchanged, so this is invisible to callers; the CLDR 48 rules and the CLDR 49 rules are two spellings of the same output.

## 23. `copy_test_data` reverts curated conformance fixtures — ✅ Fixed

### Current conformance

`Localize.Data.copy_test_data/0` copies ten conformance fixtures out of `$CLDR_REPO` into `test/support/data/`, overwriting whatever is there.

### Gap

Two of those fixtures are not pristine copies. CLDR's own conformance files disagree with CLDR's own data in a handful of places, and the vendored copies carry corrections with the reasoning written beside them: `nn`/`no` is expected at 10 where the distance rules plainly yield 20; `en-GB-oed` was replaced with `en-GB-oxendict` because the former is deprecated; three expectations carry Jira references (CLDR-14355, CLDR-14635, CLDR-18198) for rules that upstream has since removed or reclassified.

An unconditional copy deletes every one of them, comments included. The timing is what makes it expensive: it happens during a CLDR update, so the resulting failures present as upstream churn to be triaged rather than as our own pipeline undoing our own decisions. This run produced nine such failures, and both fixtures are byte-identical upstream between `release-48` and `release-49-alpha2` — nothing about CLDR 49 caused them.

### Resolution

`@curated_test_data` names the two fixtures. `copy_test_data/0` skips them and instead compares the incoming upstream bytes against the vendored copy, reporting either that they now match (the curation is redundant and can go) or that upstream has moved and a hand merge is due. Silence would be its own trap — new upstream coverage would never be picked up.

The other eight fixtures are pristine and keep copying unconditionally. `locale_display_names.txt` is worth noting as a near-miss: it differs from `release-48` and looks curated, but the difference is that it was already refreshed from a CLDR 49 pre-release, so overwriting it is correct.

### API impact / breaking risk

None. Test-fixture management only.

## 24. Plural rule modules do not recompile when their data changes — ✅ Fixed

### Current conformance

`Localize.Number.PluralRule.Cardinal` and `.Ordinal` read `plural_rules_cardinal.etf` / `plural_rules_ordinal.etf` at compile time and generate one function clause per locale from them.

### Gap

Neither declared the ETF as an `@external_resource`, so `mix` had no dependency edge from the data to the BEAM and a regenerated ETF never triggered a recompile. The sibling modules that do the same thing — `Localize.Validity.Script`, `.T` and `.U` — all declare theirs, which is what makes this an omission rather than a decision.

The consequence lands squarely on the CLDR update pipeline, and lands invisibly. `mix localize.generate_supplemental` rewrites the ETFs; the test gate then runs **last release's compiled rules against this release's data**. The sample tests are themselves generated at compile time from `plural_rules_for/1`, so they assert exactly what fresh CLDR says while the functions under test still answer what the previous CLDR said. This run produced 136 failures across `tg`, `bg`, `af`, `es`, `gl` and `vi` — every one of them a phantom. CLDR 49 does move all six (`tg` and `vi` gain rule sets, `gl` gains `many`), which made the failures look like exactly the genuine data change we were there to review.

The same build was simultaneously correct in `dev` and wrong in `test`, because an unrelated source edit had transitively recompiled the dev copy. A pipeline whose answer depends on which environment last happened to recompile is not one that can gate a release.

The pipeline had in fact been built to catch this. Its second gate is labelled "Compile (picks up `@external_resource` recompiles)" — the mechanism was anticipated and a gate placed to exercise it. It simply had nothing to act on, because the two modules that most needed the declaration did not carry it, and a gate that recompiles nothing reports success.

### Resolution

Both modules now declare their ETF via `@external_resource`. All 12,561 plural rule tests pass against CLDR 49.

### API impact / breaking risk

None at runtime. Consumers who build from source pick up a one-time recompile of the two modules.

## 25. CLDR 49 drops 114 locales below Basic coverage — ✅ Adopted

### Current conformance

`mix localize.copy_sources` vendors every locale directory the conversion produced. Against CLDR 48 that was 766.

### Gap

Against `release-49-alpha2` it is 657. One hundred and fourteen locales fewer — `aa` (Afar), `ab`, `an`, `ann`, `apc`, `arn`, `az-Arab`, `bal`, `bew`, `bgn`, `blt`, `ht` (Haitian Creole) among them.

CLDR has not dropped the source data. `common/main` **grew** from 1,122 to 1,148 XML files across the two releases, and `aa.xml` is byte-identical between them — 231 lines, 86 elements at `draft="unconfirmed"`, unchanged.

The cause is a new gate in `GenerateProductionData`, the staging step that runs before `Ldml2JsonConverter`. CLDR 49 added a `keepPreBasic` option, default `false`, which skips every locale that is absent from ICU and whose calculated coverage is below Basic:

```java
if (!KEEP_PRE_BASIC && localeIsPreBasicNonIcu(localeId)) {
    skippedPreBasicLocales.add(localeId);
    return false;
}
```

`KEEP_PRE_BASIC` does not appear anywhere in CLDR 48's copy of that file. The gate is new and on by default, which is why the same sources yield 766 locales under one release and 657 under the next with nothing in our own configuration to account for the difference. It also explains the arithmetic noticed earlier — 657 is exactly the size of CLDR 49's `effectiveCoverageLevels` map, because that map is what the gate consults.

Verified directly rather than inferred: staging `aa ab an ann apc en fr` at the default emits 2 files, and at `--keepPreBasic true` emits all 7.

Two hypotheses were tested and discarded on the way, both worth recording because each looks like the obvious lever:

* **`-l` (coverage) on `Ldml2JsonConverter`.** Its default is `optional`, and `Level` maps `OPTIONAL` to `COMPREHENSIVE` — already the loosest setting, with nothing above it. `-l comprehensive` is a literal no-op.
* **Draft status.** `DRAFTSTATUS=contributed` matches what the cldr-json project itself ships in `cldr-config.sh`, so it is the same policy the official CLDR JSON packages are built under, not a tightening of our own.

### Resolution

The 114 locales are dropped, deliberately. Not supporting pre-Basic locales keeps our locale set aligned with CLDR and ICU, and CLDR 50 is expected to continue pruning — inheriting that trajectory now is cheaper than tracking a divergence across releases.

`cldr-generate-json.sh` invokes `GenerateProductionData` with a hard-coded argument list and offers no hook for extra flags, so `scripts/ldml2json_v2` now runs the staging step itself and hands the result to the converter through the documented `INDATA` path. It passes `--keepPreBasic false` explicitly rather than relying on the default being false: a default that changes underneath us is precisely what cost this cycle, and stating the value means the next such change shows up in our own diff instead of as a hundred mysterious test failures. `CLDR_KEEP_PRE_BASIC=1` overrides.

### API impact / breaking risk

**Breaking.** One hundred and fourteen locales that resolved under Localize 1.x no longer exist. `Localize.Locale.new/2` and every downstream call will return `{:error, %Localize.InvalidLocaleError{}}` for them. This needs to lead the release notes with the full list, and consumers pinning one of those locales need a migration note pointing at the nearest supported ancestor.

## 26. Locale display in `root` falls back to English — ✅ Fixed

### Current conformance

`Localize.Locale.LocaleDisplay.display_name/2` renders a locale identifier in a requested display locale.

### Gap

CLDR 49 adds two `@locale=root` sections to `localeDisplayName.txt` (one `standard`, one `dialect`, 13 cases each). `root` carries no `localeDisplayNames`, so ICU renders the bare subtags: `nl-BE` is "nl (BE)", `en-u-nu-deva-t-de-mm-fonipa` is "en (deva, t: de, MM, fonipa)". We returned "Dutch (Belgium)" and "English (Devanagari Digits, Transform: German, Myanmar [Burma], IPA Phonetics)". Twenty-four of the 26 failed.

Four separate defects sat behind it, only the first of which is about `root` at all.

**`root` was not a recognised locale identifier.** `cldr_locale_id_from("root")` returned `InvalidLocaleError`, and the display path's `{:error, _} -> :en` fallback then silently answered in English. The same lookup also disagreed with itself on the locale root *is* recognised as: `cldr_locale_id_from(:und)` returned `:und` while `cldr_locale_id_from("und")` fell through to `validate_locale/1`, maximized, and came back `:en`. One locale, two answers, decided by whether the caller happened to hold an atom.

**The language subtag had no code fallback.** TR35 says a subtag with no display name stands in for itself. Script, territory and variants had always done this — `get_subtag_display/4` ends in `|| value` — but the language raised `LocaleDisplayError` instead, which made every locale without language names unrenderable rather than rendered plainly.

**The `-u-` extension prefixed the raw key.** With no display name for a keyword's type, we emitted `ca: buddhist` where TR35 substitutes the type code alone. No line in CLDR's conformance data renders a `-u-` key code as a prefix; `-t-` fields do take one ("s0: ascii"), which is why only the U side changed.

**The `-t-` tlang subtags fell back to the raw parsed form.** A tlang arrives lowercased with numeric regions already reduced to integers, so `-t-en-latn-001` parses as `"latn"` and `1` and rendered as "latn" and "1" where BCP-47 spells them "Latn" and "001". The canonical forms were being computed for the lookup keys and simply not used for the fallback — invisible for as long as every display locale under test had names for those subtags.

### Resolution

All four fixed. The vendored `und.etf` needed no change; it correctly carries zero language entries, as CLDR intends.

The last two were only ever reachable through a locale with no display names, which is why `root` surfaced them. Fixing them also retired exclusions that predate CLDR 49: `locale_display_test.exs` carried 8 root-locale lines in `@unexpected_root_locale_results`, 24 more in `@not_yet_implemented`, and 12 `-t-` variant cases for `ka`, `ko` and `kk`. All 44 now pass and the lists are gone; `@not_yet_implemented` retains only line 47, the `uu` attribute in the U extension, which is genuinely unimplemented.

### API impact / breaking risk

Additive on the display path — the affected spellings previously either raised or silently answered in English, and neither is behaviour worth preserving.

`cldr_locale_id_from/1` is the wider blast radius: `"und"` now resolves to `:und` rather than `:en`, so anything asking for `"und"` explicitly gets root's own (empty) data instead of English names. That is the correct reading of the request and it makes the string agree with the atom, but it is a behaviour change for any caller that was relying on the string form to mean English.

## 27. Collation data was pinned at Unicode 17 by hand — ✅ Fixed

### Current conformance

Both CLDR collation conformance files were failing: 637 of 210,155 pairs under NON_IGNORABLE and 536 under SHIFTED, against a threshold of zero. They had been treated as a floor.

### Gap

Not an implementation defect. The collation implementation reads three data files that are bound to a Unicode version, and all three were vendored by hand and never refreshed:

| File | Was | CLDR 49 ships |
|---|---|---|
| `priv/cldr/FractionalUCA.txt` | UCA/UCD 17.0.0 | 18.0.0 |
| `priv/unicode/combining_class.txt` | DerivedCombiningClass-17.0.0 | 18.0.0 |
| `priv/unicode/general_category.txt` | DerivedGeneralCategory-17.0.0 | 18.0.0 |

The conformance fixtures, meanwhile, *are* refreshed — they sit in `@test_data_files` and come from the same `common/uca/` directory as `FractionalUCA.txt`. So every CLDR update moved the test data forward and left the weight table behind, and the gap between them grew silently with each release. The failures were the arithmetic of that gap: characters Unicode 18 assigns that our table had no weights for, falling to implicit weights and sorting wrongly against characters that did.

`FractionalUCA.txt` was the only file loose in `priv/cldr/`, and no task copied it. `generate_collation_table/0` existed but was in neither `@generators` nor any mix task, so even a refreshed file would not have rebuilt the table.

### Resolution

Refreshing `FractionalUCA.txt` alone took 637 failures to 6 and 536 to 6 — one stale file accounted for 99% of it. The remaining 6 were all canonical-ordering cases (`X 0334` against `0334 Y`) for combining marks new in Unicode 18: `1ADC`, `1ADE`, `1AEC`, `1AEE`, `10D6D`, `10EF9`, `05C8`, `05C9`. With no combining class recorded they defaulted to zero and never reordered. Refreshing the UCD property files closed those. **All 210,155 pairs now pass under both strengths.**

Wired shut so it cannot recur, and wired so it works on a machine other than the one it was fixed on. `copy_sources` copies the UCA table from `$CLDR_REPO` (reporting its `VERSION:` header, since a silent change there moves every sort key in the library), then reads the `UCD=` version out of that header and fetches the two UCD property files from unicode.org if the vendored ones do not match. `generate_all/0` rebuilds the collation table from the result.

No Unicode version is configured anywhere: `mix localize.download_unicode_data` previously hard-coded `@unicode_version "17.0.0"`, which is a second version to keep in step with CLDR and therefore a second thing to forget. CLDR already states which UCD it was generated against, so that is what the pipeline reads. The task is now a thin wrapper over the same code path the pipeline uses, so there is one implementation rather than a manual step and an automatic one that can disagree.

One test carried the same version-coupling and is now derived rather than hard-coded: `reorder_test.exs` asserted "Latin 'a' has primary 0x23EC in allkeys". That primary is not stable — every character UCA assigns ahead of Latin shifts it, and it moved to 0x2485 in Unicode 18. The fractional lead byte, which is what the test is actually about, stayed at 0x2B throughout.

### API impact / breaking risk

**Sort keys change.** `Localize.Collation.sort_key/2` output is not comparable across Unicode versions, so any key persisted by a previous release must be regenerated. `compare/3` results are unaffected for characters that existed before. This wants a prominent note in the release, since a stored-sort-key index is the kind of thing that fails quietly.

## 28. CLDR 49 decimal format conformance suite — ✅ Wired in

### Current conformance

CLDR 49 adds `common/testData/decimal`, three TSV files of roughly 8,900 cases covering standard, percent, scientific and compact (short/long) formatting across 105 locales. We were not reading it. CLDR 49 also adds `common/testData/rbnf` — 99 files, some 87,000 lines — which we are also not reading; that is left open below.

### Gap

Beyond simply not running the suite, the fixtures encode a contract that is easy to get wrong. They are generated by `org.unicode.cldr.tool.GenerateDecimalFormatTestData` from ICU's `NumberFormatter` with **no explicit precision**, and `NumberFormatter`'s default is up to six fraction digits where the CLDR decimal *pattern* `#,##0.###` allows three. Read naively, the suite reports thousands of failures that are about which default applies rather than about formatting. The generator was read rather than the contract inferred, which is why the standard dimensions pass `max_fractional_digits: 6` and compact passes nothing.

### Resolution

`copy_sources` vendors all three files and `test/localize/number/decimal_conformance_test.exs` runs them, with per-file thresholds that ratchet down as fixes land. **8,864 of 8,925 match ICU exactly**, from 7,096 (79.5%) when the suite was first wired up, and the remaining 61 are all cases where CLDR's data and ICU disagree and we follow CLDR. The test reports zero unexplained failures; `decimals.tsv` is exact at 225/225.

Four defects behind the three classes:

* **Negative zero.** `negative?/1` tested `number < 0`, which is false for `-0.0`. The IEEE sign bit is read instead. A second rule then had to be narrowed: in `:auto` mode a value whose digits round away to a bare zero drops its minus (so `-0.4` at no fraction digits is "0"), and that was also swallowing actual negative zero — which is already zero, and whose sign is the only thing it carries.

* **Scientific mantissa.** Rounding was skipped outright when a format had exponent digits, because the `#E0` pattern declares no fraction digits and applying that would round `1.5E0` to `2E0`. A pattern-derived maximum is still ignored; one the caller asked for is now applied.

* **Compact precision.** ICU's compact rule is `Precision.integer().withMinDigits(2)` — round to an integer, never below two significant digits. That was approximated as "one fraction digit while the mantissa has a single integer digit", which agrees for mantissas of 1 or more and diverges below 1, where the significant digits begin after the leading zeros: a compact `0.00831765` is "0.0083", and one fraction digit rounds it away to "0".

* **Compact magnitude and grouping.** The compact rule is chosen from the value's size and the mantissa rounded afterwards, so a carry left the value formatted against a rule it had outgrown — `999.9` matched no rule at all and rendered "1,000" instead of "1K". The rounded value is now scaled back and the rule chosen again. Separately, compact groups on ICU's MIN2 strategy, which resolved two opposite-looking mismatches at once: German renders a compact 5000 as "5000" where the standard format gives "5.000", and Bengali renders 50000 as "৫০,০০০" where an ungrouped compact gives "৫০০০০".

The work also surfaced a latent crash unrelated to CLDR 49 and reachable from the public API: `Localize.Number.to_string(1.0e-308, max_fractional_digits: 400)` raised `ArithmeticError`. `Digits.to_float/1` divides two integers and Erlang converts both to floats to do it, so a scale above 10^308 raised on the divisor even though the quotient was representable. Dividing in steps keeps every intermediate in range. A non-bang function raising on valid input is a defect in its own right; the adversarial property test found it within 230 generated cases once compact precision started asking for more fraction digits.

Working the tail down to zero turned up two further defects, both wider than the decimal suite that exposed them:

* **Swahili compact was wrong by a factor of ten, and of a thousand for some ranges.** The compact divisor comes from the count of zeros in the pattern, and `number_of_zeros/1` counted them across the whole string — including the negative subpattern after a `;`. Swahili is the only family in CLDR 49 that spells one out, so `elfu 0;elfu -0` counted two zeros where it has one, and `elfu 000;elfu -000` counted six where it has three: 123,456 rendered as "elfu 123456". Fixed in the normalizer and the four `sw*` locales regenerated.

* **Plural selection lost its operands whenever a Decimal reached `pluralize/3`.** The final clause converted to a float first, and TR35 selects on the *visible* fraction digits (`v`) and their value (`f`) — operands a float cannot carry, so `plural_rule/2` has to assume a display precision for one. For 1.2 it assumes "1.200", giving `v=3, f=200` and answering `other` where Serbian, Croatian and Bosnian want `few`. This reached every compact format with a fractional mantissa in those languages.

**Every remaining difference is a case where CLDR's data and ICU's `NumberFormatter` disagree and we follow CLDR**, which is the standing rule. They are enumerated in `@divergences` in the conformance test with the CLDR evidence for each — `gl`'s group separator is U+00A0 where ICU emits ".", `ur`'s `percentSign` is `٪` where ICU formats percent as a measure unit whose pattern is `{0}%`, `bn`'s `00000 কোটি` carries no grouping, `af`'s `0 m'.'` quotes a full stop, and `ig`, `ps`, `ta`, `en-IN` and `hi-Latn` ship localised compact patterns ICU does not use. The count of each is asserted rather than merely excluded, so a divergence that resolves upstream — or one that grows — moves the number and the test says so.

### API impact / breaking risk

**Output changes.** `-0.0` now formats as "-0"; compact formatting of values below 1 keeps two significant digits where it used to collapse to "0"; compact values that round up into the next magnitude take that magnitude's rule; and compact grouping follows MIN2, so four-digit compact values lose a separator they used to carry in locales like German. One inherited expectation moved with the last of these — `test/support/number_format_test_data.exs` carried a grouped "1.234" for `de` compact that came across with the ex_cldr data and predates CLDR's own fixtures, which give "-1230" for the same shape.

## 29. A locale did not always resolve to itself — ✅ Fixed

### Current conformance

`Localize.validate_locale/1` sets `cldr_locale_id`, the key every data lookup uses, from `resolve_cldr_locale/1`.

### Gap

That function asked `best_match/3` which of the 657 known locales was closest to the requested tag — including when the requested tag *was* one of the 657. Language matching answers "which of these is closest", and for an exact identity it can legitimately answer with an equally-close different locale:

```
best_match("ar-EG") → {:ok, :ar,      0}   ← tie, and :ar won
best_match("ar-MA") → {:ok, :"ar-MA", 0}
```

`ar` maximizes through likely-subtags to `ar-Arab-EG`, so `ar` and `ar-EG` both score 0 against a desired `ar-EG`. `ar-MA` has no such tie, which is why most locales resolved correctly and hid the problem.

Twenty-five of the 657 resolved to a neighbour: `ar-EG`, `zh-Hans`, `sr-Cyrl`, `pa-Guru`, `bs-Latn`, `az-Latn`, `ca-ES-valencia`, `be-tarask`, `el-polyton` and others. Every one checked ships data that differs from what it collapsed to — `ar-EG` formats in `arab` digits where `ar` deliberately uses `latn`, so the collapse silently swapped the numbering system for 725 of the decimal fixtures.

### Resolution

A tag naming a locale we hold data for now resolves to that locale without consulting the matcher; everything else still goes through `best_match/3`. Verified first that all 657 canonical identifiers index back to their own atom, and the index maps to atoms already present in `all_locale_ids/0`, so nothing creates an atom from input.

One expectation moved with it. `Rbnf.to_string(5, :spellout_cardinal, locale: :und)` used to answer `"five"` because `:und` resolved to `:en`; it now answers `"5"`, which is what root's own public `spellout_cardinal` rule set says. That was the same silent substitution the surrounding tests exist to prevent, pointed the other way — a request for root being served another language's data — and it is consistent with `cldr_locale_id_from(:und)`, which already returned `:und`, and with item 26.

### API impact / breaking risk

**Resolution changes for 25 locales**, each of which now reads its own data instead of a neighbour's. Output changes wherever those differ; `ar-EG` is the visible one, switching to Arabic-Indic digits. This is a correction, but a consumer who had adapted to the old behaviour will see the difference.

## 30. CLDR 49 RBNF conformance suite — ✅ Wired in

### Current conformance

CLDR 49 added `common/testData/rbnf` alongside the decimal suite: 99 `.ssv` files, roughly 53,000 cases, exercising every public rule set in every locale that has one. We were not reading it, and nothing else exercised RBNF at that breadth.

### Gap

Wiring it up took the suite from 49,348 passing to **52,356 of 52,691 (99.4%)**, with **no errors at all** where there had been 1,742. Three defects, in descending order of reach:

* **Alternation branches were evaluated against the remainder rather than the number.** This is the CLDR 49 `[A|B]` construct from item 22. For English's `twent[y->>|ieth]` the distinction is invisible, because the branch carries only a remainder substitution and `>>` reaches the same value either way. It is not invisible for Russian's `200: [<%spellout-cardinal-feminine<сти >>|…]`, where the branch also carries a *quotient* substitution: passing the remainder gave `<<` the value 0, and 201 spelled "нольсти" — "zero-hundred" — instead of "двести". The same fault produced every one of the 162 remaining hard errors, so `pl` and `ca` raised `No matching rule for 0` rather than merely mis-spelling. It accounted for 1,439 mismatches across the Slavic and Baltic locales.

* **`root` was not a valid locale identifier.** TR35 §3.1 makes `root` a synonym for `und`, but CLDR's `languageAlias` data does not carry it, so `validate_locale("root")` failed on an unknown language — 1,580 cases in `root.ssv` alone. Worse, it had become inconsistent: item 26 taught `cldr_locale_id_from/1` to accept `"root"`, so the same string was resolved by one entry point and rejected by another. Resolved once, in alias resolution, where every entry point sees it.

* **A stray leading `;`** on 23 rows of the upstream fixtures (`ga.ssv` line 53 among them) is tolerated rather than read as a malformed row.

### Resolution

`copy_sources` vendors the directory — clearing it first, so a locale that leaves CLDR leaves the fixtures with it — and `test/localize/number/rbnf_conformance_test.exs` runs it. **52,685 of 52,691 cases match ICU exactly**, from 49,348 when the suite was first wired up, with no errors where there had been 1,742.

Eight defects, none of which the previous RBNF tests could have found:

* **Alternation branches were evaluated against the remainder rather than the number** (1,439 cases, plus every hard error). Described above.
* **`root` was not a valid locale identifier** (1,580 cases). Described above.
* **Fraction digits were spelled with `spellout_numbering` in preference to the current rule set** (179). TR35 spells them with the current set, so a case-marked or gendered set carries into the fraction: Finnish `%spellout-cardinal-allative-plural` renders 0.5 as "nollille pilkku viisille", and trying `spellout_numbering` first answered in the nominative for every such set.
* **A fraction rule's bracketed integer part was dropped for every non-integer** (10). `:conditional` returned "" for any float, so Russian's `x.x: [<…< $(cardinal,one{целой}other{целыми})$ ]>%%fractions…>` lost "одной целой" from 1.5.
* **The plural in a fraction-with-rule substitution selected on the denominator** (73). The rule body runs against the denominator with `<<` substituting the numerator, and the plural has to agree with the number actually spelled: `div(10, 10)` gave "one" and Russian's 0.5 came out "пятью десятой" rather than "пятью десятыми".
* **`x.x` was chosen over `x,x` regardless of the locale** (12). A locale may define both, and the one to use is the one matching its own decimal separator; taking whichever came first spelled Catalan's 0.5 as "zero punt cinc" instead of "zero coma cinc".
* **The `>>>` preceding-rule chain was linked one level deep** (38). Japanese year digits are `1000: <<>>>` over `100: <<>>>` over `10: <<>>>` over `0:`, and 1001 spells "一〇〇一" only if each level reaches its own predecessor; a single link left the second `>>>` falling back to ordinary selection, losing a digit.
* **The exact-multiple rule of a pair was never selected** (14). RBNF pairs a rule for exact multiples with one carrying a remainder, numbered one higher — Burmese `100: <<ရာ;` beside `101: <<ရာ့[>>];`, and the Hebrew numbering rules' `3000`/`3001`. Selecting purely on the largest base value not above the number always took the second, so 200 was spelled with the remainder form's suffix and no remainder to justify it.

That last one took three attempts and is worth recording. Preferring the lower rule on an exact division broke 47 cases, because it also matched ordinary neighbours like English's `1:` and `2:`. Restricting the pair to `(divisor, divisor + 1)` fixed those but missed Hebrew's `3000`/`3001`. What actually separates a pair from two unrelated consecutive rules is whether the lower one *spells the quotient*: Burmese's `100: <<ရာ;` does and covers 200, while Hebrew's `10: עשרת;` is a bare literal for ten and pressing it into service for 20 spelled "ten".

### API impact / breaking risk

**Output changes**, and they are corrections. Ordinals in Russian, Ukrainian, Polish, Slovak, Czech, Slovenian and Lithuanian were being spelled with "zero" in place of the hundreds or thousands quotient, and some inputs raised instead of formatting. `root` is now accepted wherever `und` is.

## Open questions

These need answers before the corresponding work item starts. Track them as the plan evolves.

* **Item 4** — Final list of "canonical semantic atoms" we promote inside `:format`. The tentative set is `:year_month_day`, `:year_month`, `:hour_minute`, `:hour_minute_second`, `:year_month_day_hour_minute`, `:year_month_day_hour_minute_second`, `:auto`. Reconcile with the exact vocabulary CLDR 49 ships.
* **Item 4** — Does `Localize.Interval.to_string/3` need a parallel `:semantic` route, or do interval skeletons stay field-based?
* **Item 7** — Confirm rounding precedence with significant-digit options against ECMA-402 behaviour. Document explicitly so users porting from JavaScript get expected results.
* **Item 8** — Confirm whether CLDR 49 actually adds new RBNF syntax beyond `>>>` parity. The audit may surface that we are closer to compliant than the gap matrix suggests.
* **Item 9** — Concrete JSON shape of "remove rule" markers in CLDR 49's rbnf-XXX.json. Resolve at alpha.
* **Item 11** — Should `localize_emoji` ship a Phoenix LiveView picker component as a follow-up package (`localize_emoji_live`)? Out of scope for the initial 0.1.0; flag for later.

## Review cadence

This plan must be revisited at the following checkpoints:

| When                                 | Action                                                                                  |
|--------------------------------------|-----------------------------------------------------------------------------------------|
| **CLDR 49 alpha announced**          | Open child plans `plans/cldr-49-changes.md` and `plans/cldr-49-translator-guide-checklist.md`. Confirm the JSON shape changes for items 4, 5, 9. |
| **CLDR 49 beta**                     | Start data ingestion against the beta drop using `scripts/ldml2json_v2`. Begin running the existing test suite against beta ETFs to surface regressions early. |
| **CLDR 49 RC**                       | Lock the spec deltas in this document. No new "TBD" entries should remain after RC.     |
| **CLDR 49 final**                    | Bump `priv/localize/version`, ship Localize 0.27 with CLDR 49 base data and items 1, 5, 6, 7, 9 landed. (Item 8 already shipped in 0.26.0.) Items 4 and 11 may follow in 0.28 if scope demands. |
| **Quarterly thereafter**             | Sweep this file for stale TBD/check-this items; close out or roll forward into the next plan. |

Each checkpoint should leave a dated entry at the bottom of this file noting what changed and which items advanced.

## Change log for this plan

* 2026-09-05 — Added item 30: CLDR 49's other new fixture directory, `common/testData/rbnf`, is now vendored and run. It found that alternation branches were being evaluated against the remainder instead of the number, which was invisible in English and wrong in every Slavic locale that puts a quotient substitution inside the brackets — 201 spelled "нольсти" rather than "двести", and the same fault raised outright in `pl` and `ca`. It also found `root` rejected as a locale identifier by `validate_locale/1` while `cldr_locale_id_from/1` accepted it, an inconsistency introduced by item 26. 49,348 to 52,356 of 52,691, with no errors remaining.

* 2026-09-05 — Added items 28 and 29, and noted in Scope that the Index is the authoritative item list (Scope stops at the original 13). Wired up CLDR 49's new decimal conformance suite, reading the generator to establish that it encodes ICU `NumberFormatter` defaults rather than CLDR pattern defaults. Doing so exposed item 29: `resolve_cldr_locale/1` asked the language matcher which locale was closest even when the requested locale was itself in the set, and for 25 of the 657 an equally-scored neighbour won the tie — `ar-EG` was being formatted with `ar`'s data, which is the difference between Arabic-Indic and Latin digits. Fixing it took the decimal suite from 79.5% to 86.5%. CLDR 49's other new fixture directory, `common/testData/rbnf`, is still unread.

* 2026-09-05 — Added item 27. The collation conformance failures that had been accepted as a floor were not an implementation limit at all: three Unicode-version-bound data files were vendored by hand and had drifted to Unicode 17 while the conformance fixtures they are tested against refresh with every CLDR update. Refreshing `FractionalUCA.txt` alone cleared 99% of the failures; the UCD property files cleared the rest. All 210,155 pairs now pass under both strengths, and all three files plus the table rebuild are wired into the pipeline. Sort keys change as a result.

* 2026-09-05 — Added items 25 and 26. Item 25 resolved: the 114-locale drop traces to a `keepPreBasic` gate that CLDR 49 added to `GenerateProductionData` and defaults on, not to the converter's `-l` coverage flag (whose default `optional` already maps to `COMPREHENSIVE`, so it is a no-op) and not to draft status (`contributed` is what cldr-json itself ships). Confirmed by staging seven locales at each setting: 2 files at the default, 7 with `--keepPreBasic true`. Decision taken to drop them and stay aligned with CLDR and ICU ahead of CLDR 50's continued pruning; `scripts/ldml2json_v2` now stages production data itself and passes the flag explicitly, so a future default change shows in our diff rather than as a hundred unexplained failures. This also corrects the Alpha 1 reading of the release note, which put locale removal in V50. Item 26 still open.

* 2026-09-05 — Added items 23 and 24, both pipeline defects the Alpha 2 merge exposed rather than CLDR 49 changes, and both of a kind: the pipeline quietly substituting stale or reverted state and letting it present as upstream churn. `copy_test_data/0` deleted the documented corrections in two conformance fixtures whose upstream has not moved since CLDR 48 (9 failures), and the plural rule modules never declared their ETFs as external resources, so the test gate ran the previous release's compiled rules against the new release's samples (136 failures). Between them they accounted for 145 of the 181 gate failures, all phantom.

* 2026-09-05 — Added item 22: CLDR 49 externalises RBNF rules out of the JSON into ICU-syntax `.txt` files the JSON merely points at, and adds an `[A|B]` alternation operator inside the optional-substitution brackets that replaces the private helper rulesets CLDR 48 used for ordinals. The pipeline vendored the pointers without the files, so every locale normalised to `available: []` — a silent total loss of RBNF rather than a build failure. Fixed across `data/data.ex`, `data/normalize/rbnf.ex`, the leex and yecc grammars, and the RBNF processor; this closes the "broader RBNF source-format change" half of item 9, whose rule-removal mechanic remains unexercised by CLDR 49 data.

* 2026-09-05 — Alpha 2 test merge on branch `cldr-49`. Added item 21: CLDR 49 writes one metazone transition with seconds where all 488 had been minute-precision, which aborted `mix localize.generate_supplemental`; fixed in `data/supplemental.ex`. The run also exposed two pipeline defects unrelated to CLDR 49 — the data pipeline read `CLDR_PRODUCTION_DATA` while `scripts/ldml2json_v2` wrote `CLDR_PRODUCTION` (standardised on the latter), and the script neither fetched nor checked out a tag, so `release-49-alpha2` was invisible locally and a mid-stream commit would have built silently. CLDR 49 requires JDK 21, now prechecked.

* 2026-09-01 — Release-note review at Alpha 1. The 2026-08-25 review read `tr35-modifications.md`; the release note carries a "V49 advance warnings" section the modifications log does not, and four items came from it: 17 (`H24` deprecated), 18 (week numbering follows ISO), 19 (supplemental files reorganized) and 20 (Iran subdivision codes stale upstream). Galician's new `many` plural case needs no work — the category lists already enumerate it. `cnr` de-aliasing and the removal of locales without core data are **V50**, not this cycle.

* 2026-05-05 — Initial draft. All 11 items at status *planned*; no child plans written yet.
* 2026-05-05 — Item 8 (RBNF syntax audit) landed in Localize 0.26.0. Nine bugs fixed plus three follow-up items; full audit trail in [plans/rbnf.md](rbnf.md). Three latent items (Inf/NaN, `<<<`, `Nx.x`) deferred with explicit rationale. Index table, item 8, item 9, and the review-cadence-final-row updated to reflect.
* 2026-05-11 — Added item 12: audit `$CLDR_REPO/common/testData` at CLDR 49 alpha for new conformance fixtures, especially decimal-formatting tests that may gate item 7.
* 2026-05-06 — Item 10 (CLDR 48.2 modifications retrospective) complete. Full audit in [plans/cldr-48-retrospective.md](cldr-48-retrospective.md): 23 modifications classified, 6 follow-up tasks filed (§A–§F). Index table and item 10 section updated.
* 2026-05-12 — Added item 13: generate signed/checksummed manifest for CDN-downloaded locale ETFs so the runtime can verify content integrity before decode. Motivated by the 0.30.1 revert of `binary_to_term [:safe]` (issue #25), which re-opened security audit §4.1's writable-cache-dir DOS surface. Research required — manifest format, signature scheme, hot-path budget, key rotation all open.

* 2026-08-02 — Plan audit. Added item 14 (Japanese pre-Meiji eras), which was tracked only in [plans/japanese_eras.md](japanese_eras.md) and referenced nowhere here despite being triggered by CLDR 49 and carrying a silent-data-loss risk during a routine pipeline run. Marked item 13 done (shipped in Localize 0.44.0) — its status still read "research required". Added index rows for items 13 and 14; the index previously stopped at 12 while the file carried a section 13.
* 2026-08-16 — Added item 15: POSIX `yesstr` / `nostr`. CLDR ships affirmative and negative response strings for every locale and Localize reads none of them, so any confirmation prompt hard-codes English `y`/`n`. `"posix"` is absent from the pipeline's `@required_modules`, so this needs a data-key addition as well as an API.

---

## Alpha review — 2026-08-25

Reviewed against `release-49-alpha1` (2026-08-14) at `~/Development/cldr/cldr_repo`. Our pinned base is CLDR 48.2.

**The plan holds.** Nothing in the alpha invalidates an item. Three items get materially stronger, one new item is needed, and the alpha surfaced one pre-existing bug.

### What CLDR 49 actually changes

The official log in `tr35-modifications.md` lists six changes against 48.2. Assessed against our implementation:

| change | our exposure |
|---|---|
| Calendar era `code`s: length limit added | Item 14 territory — covered by [japanese_eras.md](japanese_eras.md) |
| `typeValues` for On/Off translations (CLDR-19394) | **Not in this plan** — see new item 16 |
| `numberFormat` description revised (CLDR-18963) | Needs a read; description-only, no data shape change observed |
| `dateTime`: `gmtZeroOffset` removed | **None.** Not referenced anywhere in `lib/` or `data/` |
| `dateFormatItem` selection and `appendItems` clarified | **Completes item 5** — see below |
| MF2: `:currency`/`:percent` Stable; `u:locale` dropped | **None.** `interpreter.ex` already lists both as Stable, and we never implemented the dropped `u:locale` |

Data-level deltas: **26 new locales** (`ady`, `ary`, `brh`, `hrx`, `isv`, `kbd`, `mrh`, `sus`, `xdq` plus regional variants), **none removed**, 1122 → 1148 locale files. 100 RBNF files changed, net −10,000 lines.

The Japanese era premise is confirmed incidentally: the `japanese` calendar block in `supplementalData.xml` now begins at `<era type="232" code="meiji"/>`, so the 232 earlier eras are gone as the plan anticipated.

### Item 5 is no longer blocked

The plan deferred item 5 because it needed `dateFields` data. CLDR 49 instead supplies the **algorithm**, in full. `tr35-dates.md` now enumerates which fields are date fields and which are time fields, specifies distance ranking when no exact `dateFormatItem` matches, gives the tie-break weighting, and states the glue-pattern selection rules including the `Time-Day-Of-Week` and `Date-Timezone` special cases.

That is the whole of what was missing. **Item 5 moves from deferred to actionable in this cycle.**

### Items 4, 5 and 12 gain a conformance oracle

`common/testData` gains **107 new fixture files**, and three groups matter to us:

| fixture | lines | serves |
|---|---|---|
| `datetime/skeletons.tsv` | 361 | items 4, 5 |
| `datetime/skeletons_all_calendars.tsv` | 1,081 | items 4, 5 |
| `datetime/skeletons_all_locales.tsv` | 4,161 | items 4, 5 |
| `datetime/skeletons_all_skeletons.tsv` | 4,393 | items 4, 5 |
| `datetime/skeletons_random_5percent.tsv` | 11,191 | items 4, 5 |
| `decimal/decimals.tsv` | 226 | item 12 |
| `decimal/decimals_extended_numbers.tsv` | 6,301 | item 12 |
| `decimal/decimals_modern_locales.tsv` | 2,401 | item 12 |
| `rbnf/*.ssv` | 99 files | items 8, 9 |

The skeleton fixtures are `locale → calendar → skeleton → pattern` and cover the hard cases directly: `jjm` (locale-preferred hour), `Bh` (day period), `Cms` (flexible hour), `HmsS` (fractional seconds), `yMdHmsv` (date, time and zone combined), `GyMd` (era), and non-Gregorian calendars.

Item 12 was written speculatively — "new decimal-formatting tests **expected** to ship with CLDR 49". They shipped. Item 12 is now concrete work with known inputs.

### The fixtures already found a bug

Running `decimal/decimals.tsv` against Localize 1.2.0 surfaced one genuine defect, before the fixtures are even adopted:

**`ar-EG` renders Latin digits where CLDR specifies `arab`.** `Localize.Number.to_string(1234.5, locale: "ar-EG")` returns `"1,234.5"`; CLDR expects `١٬٢٣٤٫٥`.

Scope checked: of the **50 locales whose CLDR default numbering system is not `latn`, 49 render correctly** and only `ar-EG` does not. `bn` correctly yields `১,২৩৪.৫`, and every other Arabic regional locale yields Arabic-Indic digits. So the mechanism is sound and this is an isolated anomaly.

It is **not a CLDR 49 regression** — `ar_EG.xml` declares `arab` in 48 and 49 alike. It is a standing bug in our data or resolution, and it should be fixed independently of the 49 upgrade rather than folded into it.

### New item

**16. `typeValues` On/Off translations (CLDR-19394).** CLDR 49 adds centralised On/Off translations under `<typeValues>`, sibling in spirit to the `yesstr`/`nostr` work in item 15. Both are POSIX-adjacent affordances that applications ask for and we do not expose. Worth folding into item 15's release rather than tracking separately.

### Checkout note

`~/Development/cldr/cldr_repo` is at `release-49-alpha1`. `alpha0` was 2026-08-06, `alpha1` 2026-08-14; the beta and RC have not landed, so the delta above may still move. Re-run this review at beta.
