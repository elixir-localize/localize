# Semantic skeletons design plan

**Status:** design draft, last updated 2026-05-05. No implementation yet.

**Owner:** Localize maintainers

**Scope:** the public-API design and runtime resolver for TR35 *Semantic Skeletons*, expanding item 4 of [plans/cldr-49.md](cldr-49.md). The implementation lands in the CLDR 49 cycle (Localize 0.27); this document settles the design questions ahead of time so the code arc is mechanical when CLDR 49 alpha drops.

**Spec:** <https://www.unicode.org/reports/tr35/dev/tr35-dates.html#Semantic_Skeletons>

## Why this matters

Today `Localize.DateTime.to_string/2` accepts three `:format` shapes:

* a standard CLDR style atom — `:short`, `:medium`, `:long`, `:full`;
* a CLDR field-skeleton atom — `:yMMMd`, `:Hms`, `:EEEEMMMd`, etc.;
* a literal CLDR pattern string — e.g. `"y-MM-dd HH:mm"`.

All three force the caller to think in CLDR field-symbol terms. The user typing `format: :yMMMd` already knows they want a "year, month-abbreviated, day" date — the CLDR shorthand is an implementation detail leaking through the API. *Semantic skeletons* let the caller express the **intent** ("year-month-day with weekday, long form, with specific time-zone") in a locale-independent way; the resolver picks the field-skeleton (and ultimately the pattern) that the locale ships for that intent.

For users this is closer to ECMA-402 / `Intl.DateTimeFormat`'s component selectors. For Localize, it's the API surface that lets us route through CLDR's own preferred-form data without callers needing to memorise field-symbol shorthand.

## Spec recap (TR35-dev §Semantic_Skeletons)

A semantic skeleton has up to four orthogonal axes:

| Axis | Values | What it controls |
|---|---|---|
| **Length** | `:short`, `:medium`, `:long` | Overall verbosity envelope. Maps to CLDR's standard date format buckets. |
| **Date component** | `:year`, `:year_month`, `:year_month_day`, `:year_quarter`, `:auto` (no date) | Which date fields are rendered, and their granularity. |
| **Time component** | `:hour`, `:hour_minute`, `:hour_minute_second`, `:auto` (no time) | Which time fields are rendered, and their granularity. |
| **Zone component** | `:specific`, `:generic`, `:location`, `:offset`, `:auto` (no zone) | How the time zone is rendered (or whether it is). |

Plus two modifiers:

* **`:alignment`** — `:auto` or `:column` for tabular contexts (right-align numerals).
* **`:year_style`** — `:auto`, `:full`, `:with_era` to control how aggressively the year is shortened.

The locale ships a *semantic-skeleton table* mapping each (length × date × time × zone) tuple to a concrete CLDR pattern (or to a field-skeleton that the resolver then expands through the existing best-match logic). When a tuple isn't directly populated, TR35 specifies a deterministic fallback algorithm: drop modifiers, fall through to broader length, then to the closest field-skeleton.

## Open questions and recommended answers

The CLDR-49 plan flagged seven open questions for this item. This section resolves each.

### Q1 — Final canonical-atoms vocabulary

The vocabulary below mirrors TR35-dev's component names verbatim, with snake-case rendering for Elixir. Each value matches exactly one TR35 component identifier so a future translation table is unnecessary.

* **Lengths:** `:short`, `:medium`, `:long`. (Not `:full` — TR35 semantic skeletons cap at three lengths; `:full` is a CLDR standard-format-only term.)
* **Date components:** `:year`, `:year_month`, `:year_month_day`, `:year_month_day_weekday`, `:year_quarter`, `:auto`. (`:auto` means "infer from caller's context"; equivalent to leaving the date axis unset.)
* **Time components:** `:hour`, `:hour_minute`, `:hour_minute_second`, `:auto`.
* **Zone components:** `:specific`, `:generic`, `:location`, `:offset`, `:auto`.
* **Alignment:** `:auto`, `:column`.
* **Year style:** `:auto`, `:full`, `:with_era`.

For each axis the absence of a key in the constructor call means `:auto`. Convenience top-level atoms (`:year_month_day`, `:hour_minute`, etc.) at the `:format` option boundary expand to the corresponding default-modifier semantic-skeleton struct (see Q4).

### Q2 — CLDR JSON shape for the data

CLDR 48.2 ships *no* semantic-skeleton data (verified — `grep -l semantic priv/cldr/locales/en/*.json` returns nothing). The data is a CLDR 49 addition. The expected shape per the TR35-dev grammar is a new sub-tree under each calendar:

```
"main": {
  "<locale>": {
    "dates": {
      "calendars": {
        "gregorian": {
          "semanticSkeletons": {
            "yearMonthDay": { "short": "...", "medium": "...", "long": "..." },
            "yearMonthDayWeekday": { ... },
            "hourMinute": { ... },
            ...
          }
        }
      }
    }
  }
}
```

Values can be either a CLDR pattern string (when the locale prescribes an exact form) or a *reference* to an existing field-skeleton (the spec is still finalising this — the alpha drop will tell us). The normalizer (`data/normalize/date_time.ex`) treats both forms uniformly: parse pattern strings via `Localize.DateTime.Format.Compiler`; resolve field-skeleton references via the existing `available_formats` lookup.

The exact JSON-key naming will need a final check against CLDR 49 alpha — the spec uses `dateFormatItem` extensions in some sections and a fresh `semanticSkeletons` top-level key in others. The normalizer is the only file that cares.

### Q3 — Resolver algorithm

Given a `%SemanticSkeleton{}` struct, a locale, and a calendar, the resolver:

1. **Direct lookup.** Build a key tuple `{length, date_component, time_component, zone_component, modifiers}` and look it up in the locale's `semantic_skeletons.etf`. Most callers hit this path.
2. **Modifier fallback.** If the direct lookup misses, drop modifiers (`:alignment`, `:year_style`) and retry.
3. **Length fallback.** If still missing, walk lengths in TR35 order: requested → `:medium` → `:long` → `:short`.
4. **Field-skeleton fallback.** If the semantic-skeleton table has no entry for the (length × date × time × zone) tuple at all, the resolver constructs a CLDR field-skeleton from the components and dispatches through the existing `Localize.DateTime.Format.Match.best_match/3` path. For example, `{:medium, :year_month_day, :auto, :auto, _}` → field-skeleton `:yMMMd` → existing best-match logic.
5. **Combined date+time composition.** When both date and time components are non-`:auto`, the resolver composes the locale's date-time wrapper pattern (`"{1}, {0}"` style, already handled today in `Localize.DateTime.format_with_skeleton/4`) with the resolved date and time pieces.
6. **Zone composition.** `:specific`/`:generic`/`:location`/`:offset` plug into the existing zone formatter (`Localize.DateTime.Timezone.non_location_format/3` and friends) and append to the date-time result.

The path that's new here is steps 1–3 (the lookup + length fallback). Step 4 is the bridge to existing infrastructure; steps 5–6 reuse what we already ship.

### Q4 — Public API design (refining option B from cldr-49.md)

The CLDR 49 plan offered three options:

* **A.** Single new option `:semantic` on `Localize.DateTime.to_string/2`.
* **B.** Overload the existing `:format` option to accept a `%Localize.DateTime.SemanticSkeleton{}` struct.
* **C.** New top-level function `Localize.DateTime.to_semantic_string/3`.

The plan recommended B. This document confirms B as the primary path **with a sugar shorthand** for the most common cases.

The `:format` option accepts:

| Value                                       | Meaning                                                        | Status              |
|---------------------------------------------|----------------------------------------------------------------|---------------------|
| `:short`/`:medium`/`:long`/`:full`          | Existing standard CLDR style                                   | Existing            |
| `<skeleton-atom>` e.g. `:yMMMd`             | Existing CLDR field-skeleton best-match                        | Existing            |
| `<binary>`                                  | Literal CLDR pattern string                                    | Existing            |
| `%Localize.DateTime.SemanticSkeleton{…}`    | Built via `semantic/1,2`; full TR35 expressivity               | New in CLDR 49 work |
| `<canonical-atom>` e.g. `:year_month_day`   | Sugar atom that resolves to the corresponding default-modifier struct | New |

The struct is built via `Localize.DateTime.SemanticSkeleton.semantic/1,2`:

```elixir
import Localize.DateTime.SemanticSkeleton, only: [semantic: 1, semantic: 2]

semantic(:year_month_day)
# %Localize.DateTime.SemanticSkeleton{
#   length: :auto,
#   date: :year_month_day,
#   time: :auto,
#   zone: :auto,
#   alignment: :auto,
#   year_style: :auto
# }

semantic(:year_month_day_weekday, length: :long, zone: :specific)
# %Localize.DateTime.SemanticSkeleton{
#   length: :long,
#   date: :year_month_day_weekday,
#   time: :auto,
#   zone: :specific,
#   alignment: :auto,
#   year_style: :auto
# }
```

The constructor validates components against the TR35 vocabulary at build time, raising `ArgumentError` on unknown keys. Compile-time validation isn't possible (the struct is built at runtime) but a `dialyxir`-friendly `@type` keeps the contract explicit.

#### Resolution order in `find_format/3` (and friends)

1. If `:format` is a binary → existing pattern path.
2. If `:format` is a `%SemanticSkeleton{}` → new semantic resolver.
3. If `:format` is an atom in `@standard_formats` (`:short`/`:medium`/`:long`/`:full`) → existing standard-format path.
4. If `:format` is an atom in `@semantic_atoms` (the canonical sugar atoms — `:year_month_day`, `:year_month_day_weekday`, `:year_month`, `:hour_minute`, `:hour_minute_second`, `:year_month_day_hour_minute`, `:year_month_day_hour_minute_second`, `:auto`) → promote to default-modifier `SemanticSkeleton` and dispatch as in step 2.
5. Otherwise → existing field-skeleton best-match path.

The canonical sugar atoms are a deliberate, finite set. They are disjoint from existing CLDR field-skeleton atoms (`:yMMMd`, `:Hms`, etc. — all start with a lowercase ASCII letter that's also a CLDR symbol; semantic atoms have at least one underscore). No ambiguity.

This preserves 100% backwards compatibility: every value that worked pre-change resolves to the same path post-change.

### Q5 — Interaction with `:prefer` and other existing options

`:prefer` (currently a list of CLDR `alt` keys — `[:variant, :ascii, :unicode, :standard]`, default `[:standard, :unicode]`) governs CLDR variant selection. It applies after the resolver picks a pattern.

Three cases:

* **Caller passes `:format` as a standard atom or field-skeleton.** Existing behaviour: variant selection runs over the resolved pattern. Unchanged.
* **Caller passes `:format` as a binary.** Existing behaviour: pattern is used verbatim, no variant selection. Unchanged.
* **Caller passes `:format` as a `%SemanticSkeleton{}` or canonical-atom.** New behaviour: semantic resolver picks a pattern (or a field-skeleton that downstream picks a pattern), then variant selection runs over that pattern. The semantic-skeleton lookup itself does NOT consume `:prefer` — TR35's semantic-skeleton table doesn't have variant alts. `:prefer` only kicks in after the lookup, on the chosen pattern.

`:locale`, `:calendar`, `:number_system`, `:currency` (where applicable for date-time number rendering): all unchanged. The semantic resolver routes through the same `Localize.Locale.get/2` and the same `Localize.DateTime.Format.available_formats/2` infrastructure.

### Q6 — Calendar dependency

Semantic skeletons are calendar-specific. CLDR 49 ships data for `gregorian` (and likely `iso8601`) directly; non-Gregorian calendars (Buddhist, Hebrew, Persian, Japanese, etc.) inherit from Gregorian with calendar-specific glyph substitutions handled by the existing pattern formatter.

The runtime path:

1. Caller passes `:calendar` (defaults to `Localize.Calendar.default/0`, typically `:gregorian`).
2. The resolver looks up `dates.calendars.<calendar>.semantic_skeletons` for that calendar.
3. If the table is missing for the requested calendar, the resolver falls back to `:gregorian`'s table. (CLDR's standard inheritance pattern.)
4. The chosen pattern is passed to the existing pattern formatter, which substitutes calendar-specific glyphs.

No new calendar-handling code is required — the existing infrastructure already does the right thing once the resolver hands off a pattern.

### Q7 — `Localize.Interval` opt-in

`Localize.Interval.to_string/3` formats date / time / datetime *intervals* (e.g. "Jan 1 – Jan 5, 2026"). It currently uses field-skeleton-based interval formats (`yMMMd → yMMMd`, `Hms → Hms`).

**Decision: `Localize.Interval` is OUT of scope for the initial 0.27 implementation.**

Rationale:

* TR35 §Semantic_Skeletons addresses single-instant date-time formatting; CLDR's interval-format data is keyed by field-skeletons, not semantic skeletons.
* Adding semantic-skeleton support to `Localize.Interval` would require a translation step from the resolved semantic skeleton back to a field-skeleton suitable for interval lookup.
* No CLDR interval-skeleton table is keyed by semantic vocabulary today.

The `:format` option on `Localize.Interval.to_string/3` continues to accept field-skeleton atoms, standard format atoms, and binary patterns — same as today. We can revisit this in a future cycle if CLDR adds semantic-skeleton support to its interval data.

## Public API surface

The new module `Localize.DateTime.SemanticSkeleton` exposes:

```elixir
defmodule Localize.DateTime.SemanticSkeleton do
  @moduledoc """
  Builds locale-independent date-time format intents (TR35 §Semantic_Skeletons).
  """

  defstruct length: :auto,
            date: :auto,
            time: :auto,
            zone: :auto,
            alignment: :auto,
            year_style: :auto

  @type length :: :short | :medium | :long | :auto
  @type date_component :: :year | :year_month | :year_month_day | :year_month_day_weekday | :year_quarter | :auto
  @type time_component :: :hour | :hour_minute | :hour_minute_second | :auto
  @type zone_component :: :specific | :generic | :location | :offset | :auto
  @type alignment :: :auto | :column
  @type year_style :: :auto | :full | :with_era

  @type t :: %__MODULE__{
          length: length(),
          date: date_component(),
          time: time_component(),
          zone: zone_component(),
          alignment: alignment(),
          year_style: year_style()
        }

  @spec semantic(date_component()) :: t()
  def semantic(date_component) when is_atom(date_component)

  @spec semantic(date_component(), keyword()) :: t()
  def semantic(date_component, options) when is_atom(date_component) and is_list(options)
end
```

The constructors raise `ArgumentError` on unknown atoms. The struct is opaque to callers but `inspect/1`-friendly.

The new resolver `Localize.DateTime.Format.Semantic` exposes a single internal entry point:

```elixir
@spec resolve(SemanticSkeleton.t(), atom(), atom(), keyword()) ::
        {:ok, String.t()} | {:error, Exception.t()}
def resolve(%SemanticSkeleton{} = skeleton, locale_id, calendar_type, options)
```

This is the function the existing `Localize.Date.find_format/3`, `Localize.Time.find_format/3`, and `Localize.DateTime.format_with_skeleton/4` dispatch into when they detect a `%SemanticSkeleton{}` value in `:format` (resolution-order step 2).

## Worked examples

### Example 1 — locale-default year-month-day

```elixir
Localize.DateTime.to_string(~U[2026-04-30 19:42:26Z],
  locale: "en",
  format: :year_month_day)
```

Resolution:

1. `:format` is `:year_month_day` → in `@semantic_atoms` → promote to `semantic(:year_month_day)`.
2. `SemanticSkeleton{length: :auto, date: :year_month_day, ...}`.
3. Direct lookup in `dates.calendars.gregorian.semantic_skeletons[year_month_day]` for `en`. Length `:auto` → try `:medium` (TR35 default).
4. Locale provides medium pattern `"MMM d, y"`.
5. Format → `"Apr 30, 2026"`.

### Example 2 — long form with weekday and specific zone

```elixir
import Localize.DateTime.SemanticSkeleton, only: [semantic: 2]

Localize.DateTime.to_string(~U[2026-04-30 19:42:26Z],
  locale: "en",
  format: semantic(:year_month_day_weekday, length: :long, zone: :specific))
```

Resolution:

1. `:format` is a `%SemanticSkeleton{}` → dispatch to `Localize.DateTime.Format.Semantic.resolve/4`.
2. `{:long, :year_month_day_weekday, :auto, :specific, _, _}` direct lookup.
3. Locale's pattern (hypothetical CLDR 49 data): `"EEEE, MMMM d, y 'at' h:mm:ss a zzzz"` — but wait, this has a time component too. Since the request was `time: :auto`, the resolver enters the date-only path: `"EEEE, MMMM d, y"`.
4. Zone `:specific` is non-`:auto` but date-only requests don't render zones. **The resolver detects this contradiction and silently drops the zone component**, treating the call as `time: :auto, zone: :auto` for resolution purposes.
5. Format → `"Thursday, April 30, 2026"`.

This drop-with-warning behaviour matches ICU's `DateTimeFormat` resolved-options model. We may want to log a warning at debug level rather than silently dropping; TBD during implementation.

### Example 3 — convenience atom for date-time combination

```elixir
Localize.DateTime.to_string(~U[2026-04-30 19:42:26Z],
  locale: "ja",
  format: :year_month_day_hour_minute)
```

Resolution:

1. Atom in `@semantic_atoms` → promote to `semantic(:year_month_day, time: :hour_minute)`. (Or equivalently the constructor expands the compound atom into the two-axis spec.)
2. `SemanticSkeleton{date: :year_month_day, time: :hour_minute, ...}`.
3. ja's date pattern + ja's time pattern + ja's date-time wrapper → final pattern.
4. Format → `"2026年4月30日 19:42"`.

### Example 4 — fallback through field-skeleton best-match

```elixir
Localize.DateTime.to_string(~U[2026-04-30 19:42:26Z],
  locale: "en-CA",
  format: semantic(:year_quarter, length: :short))
```

Resolution:

1. SemanticSkeleton struct.
2. Direct lookup in en-CA's table — assume CLDR 49 doesn't ship a short-year-quarter entry for en-CA.
3. Length fallback: try `:medium` then `:long`. Still missing.
4. Field-skeleton fallback: construct `:Qy` (quarter + year), dispatch through existing `Localize.DateTime.Format.Match.best_match/3`.
5. Best-match returns `Qy` from en-CA's available formats → pattern `"Q yyyy"` → format → `"2 2026"`.

This is the safety net: any semantic-skeleton call that can't be resolved through CLDR's semantic table falls through to today's working code path.

## Implementation steps

1. **Stub the module skeleton.** Create `Localize.DateTime.SemanticSkeleton` with the struct and `semantic/1,2` constructors plus exhaustive `ArgumentError` validation. Doctests for every canonical atom + invalid input. No data plumbing yet.
2. **Stub the resolver.** Create `Localize.DateTime.Format.Semantic` with `resolve/4` returning `{:error, :not_implemented}` when the table is missing (which it will be, on 48.2 base data). Ship this so dispatch wiring can land before CLDR 49 alpha.
3. **Wire the dispatch.** Add the `%SemanticSkeleton{}` and canonical-atom branches to `Localize.Date.find_format/3`, `Localize.Time.find_format/3`, and `Localize.DateTime.format_with_skeleton/4`. Steps 1–3 ship in 0.27 even if the table is empty: callers get a clear error rather than silent fallback to field-skeleton best-match. (Or the inverse — silent fallback may be the better UX; decide during implementation.)
4. **Extend the normalizer.** Once CLDR 49 alpha lands, audit the JSON shape, then extend `data/normalize/date_time.ex` to ingest `dates.calendars.<cal>.semanticSkeletons` into the locale ETF. Regenerate. Folds into the same ETF refresh as item 5 (date-time append items) and item 9 (RBNF rule-removal).
5. **Implement the resolver.** Replace step 2's stub with the full algorithm: direct lookup → modifier fallback → length fallback → field-skeleton fallback. ~150 lines of Elixir, mostly mechanical.
6. **Public API docs.** Update `Localize.DateTime.to_string/2`'s `### Options` section to document the new `:format` shapes (semantic struct + canonical atoms). Add a "Semantic skeletons" section to the `Localize.DateTime` moduledoc with the worked examples above.
7. **Tests.** ~30–40 tests covering each canonical atom, struct constructors, dispatch order, all four resolver paths (direct lookup, modifier fallback, length fallback, field-skeleton fallback), calendar inheritance, zone composition, contradictions (e.g. `time: :auto` with `zone: :specific`), `:prefer` interaction, and backwards-compat regression checks for every existing `:format` shape.

## Migration story

The implementation is purely additive. Existing callers using `format: :short`, `format: :yMMMd`, or `format: "y-MM-dd"` see no behavioural change. New callers can adopt semantic skeletons incrementally — typical adoption arc:

1. **Replace `format: :short`/`:medium`/`:long`/`:full` with semantic-atom equivalents** in code that benefits from intent-driven sizing. The existing standard-format atoms still work; both paths produce locale-correct output, but semantic skeletons make the *intent* explicit.
2. **Replace `format: :yMMMd` and similar field-skeletons with `format: semantic(:year_month_day, length: :medium)`** in code that's currently relying on knowledge of CLDR field-symbol mnemonics.
3. **Adopt struct-based formatting in libraries** that already cache `Localize.Number.Format.Options` structs across calls — the same pattern of "validate once, use many" applies.

The README and the "Date and time formatting" guide get a new section explaining the three-shape API and recommending semantic skeletons for new code, with a "field-skeletons remain supported" note for backward compatibility.

## Testing strategy

Three test layers, mirroring the RBNF-fixes test architecture:

* **Unit-level (constructors).** Every canonical atom; every modifier; every invalid input raising `ArgumentError`. ~15 tests.
* **Resolver-level.** Direct path for each (length × date × time × zone) tuple that CLDR 49 ships for en, de, fr, ja, ar (representative locale set). ~20 tests.
* **End-to-end formatter tests.** Full `Localize.DateTime.to_string/2` invocations with semantic-skeleton `:format` values, asserting exact output strings. Includes the worked examples above plus a sweep across the canonical-atom shorthand. ~15 tests.

CLDR ships its own semantic-skeleton test data alongside the spec; we should ingest that as fixture inputs once CLDR 49 lands, similar to how we treat CLDR's RBNF test data.

## Open risks

1. **CLDR 49 JSON shape.** The exact path under `dates.calendars.<cal>` is provisional in the dev draft. The alpha drop will fix the shape; the normalizer is the only file that needs to know.
2. **Calendar coverage.** TR35 prescribes Gregorian-first; non-Gregorian calendars inherit. If CLDR 49 ships semantic skeletons for non-Gregorian calendars too, the inheritance path may differ from our current calendar-fallback logic. Re-verify during implementation.
3. **Time-zone composition.** TR35's spec for combining a date+time pattern with a zone component is loosely defined. ICU's behaviour will be the de-facto reference; we'll cross-check against ICU's `DateTimeFormat` output for a handful of locales as part of resolver-level tests.
4. **Performance.** Each lookup does a few `Map.get` calls plus the existing pattern formatting. Should be similar to today's standard-format path. If benchmarks show regression, we add `:persistent_term` caching at the locale + calendar + tuple key — exact same shape as the existing data-loader caching.

## Review cadence

* **CLDR 49 alpha** — verify JSON shape against this plan, update the normalizer audit (Q2). If the shape diverges materially from `dates.calendars.<cal>.semanticSkeletons`, re-write Q2 accordingly.
* **CLDR 49 beta** — start data ingestion against beta drop; add fixture-based tests using CLDR's own semantic-skeleton test data.
* **CLDR 49 RC** — lock the API surface. After RC any further design questions should be answered through code review, not plan revision.
* **CLDR 49 final** — ship Localize 0.27 with full implementation.

## Change log for this plan

* 2026-05-05 — Initial design draft. Resolves the seven open questions from item 4 of `plans/cldr-49.md`. Implementation deferred to the CLDR 49 cycle (Localize 0.27).

