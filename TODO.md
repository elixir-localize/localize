# TODO

## Pre-release blockers

### Remove ex_cldr runtime dependency

The `PersistentTerm` data provider currently calls
`Cldr.Locale.Loader.get_locale/2` to load per-locale JSON
data at runtime. This must be replaced with a standalone
locale loader that reads JSON files directly from
`priv/cldr/locales/` without depending on `ex_cldr`.

* [ ] Implement standalone JSON locale loader in
      `Localize.Locale.Loader` that reads and decodes locale
      JSON files from `priv/cldr/locales/`.

* [ ] Update `Localize.Locale.Provider.PersistentTerm.load/1`
      to use the new loader instead of
      `Cldr.Locale.Loader.get_locale/2`.

* [x] `Localize.Number.System` loads `@number_systems` at
      compile time via `Cldr.Config.number_systems()`. Extracted
      to `priv/cldr/supplemental_data/number_systems.etf` and
      loaded at runtime via `:persistent_term`.

* [ ] `Localize.Collation` checks for `Cldr.LanguageTag` at
      runtime via `Code.ensure_loaded?/1`. Remove this
      compatibility shim.

* [ ] Remove `{:ex_cldr, path: "../cldr"}` from `mix.exs`
      dependencies.

* [ ] Copy locale JSON files from `../cldr/priv/cldr/locales/`
      into `priv/cldr/locales/` so the library is
      self-contained.

### Compile warnings

Resolve all compile warnings before release. Currently 17
warnings:

* [ ] Unused module attributes: `@date_field_names` (date.ex),
      `@time_field_names` (time.ex), `@prefer_cycle_12`
      (format/match.ex), `@unit_quantities` (unit/data.ex).

* [ ] Unused functions: `resolve_date_format/3`,
      `resolve_time_format/3`, `resolve_wrapper/3` default
      values (datetime.ex).

* [ ] Unused variables: `datetime`, `locale_id`, `rule`,
      `bcp47_key` — prefix with underscore or remove.

* [ ] Unused alias: `Expression` (unit/data.ex).

* [ ] Ungrouped clauses: `find_rule_set/2`
      (rbnf/processor.ex).

* [ ] Leex/yecc compiler warnings — add `:leex` and `:yecc`
      to compilers in `mix.exs` project definition.

### Placeholder code

* [ ] Remove `Localize.hello/0` — placeholder function from
      project generation.

### Documentation

* [ ] Write `Localize` moduledoc — currently a stub. Should
      describe the library's purpose, list the main domain
      modules, and explain the locale management API.

* [ ] Review and update all public module `@moduledoc`
      sections for completeness and accuracy.

* [ ] Write a `README.md` with installation, quick start,
      and links to documentation.

* [ ] Write a `CHANGELOG.md`.

* [ ] Ensure all public functions have `@doc` in the standard
      format described in `CLAUDE.md`.

### Hex publishing

* [ ] Set version in `mix.exs`.

* [ ] Add `:description`, `:package`, `:source_url` to
      `mix.exs` for Hex.

* [ ] Add license file.

* [ ] Run `mix docs` and review generated documentation.

* [ ] Run `mix dialyzer` and resolve any errors.

## Remaining merge work

### Currency

* [x] `currency_history_for_locale/1` — implemented with
      `territory_from_locale/1` that resolves territory via
      `rg` extension → explicit territory → likely subtags.

### Currency inheritance — completed

* [x] `territory_from_locale/1` — resolves territory via
      `rg` extension → explicit territory → likely subtags.
* [x] `current_currency_from_locale/1` updated to use
      `territory_from_locale/1`.
* [x] `currency_history_for_locale/1` implemented.

### Collation tailoring — completed

Expanded from 11 hardcoded locale/type pairs to 110 entries
covering 97 languages, extracted from CLDR XML.

* [x] Audited all 135 CLDR collation XML files.
* [x] Created `scripts/extract_collation_tailoring.exs` to
      parse CLDR XML and produce
      `priv/cldr/supplemental_data/collation_tailoring.etf`.
* [x] `@tailorings` now loaded from ETF at compile time.
* [x] Extended `locale_defaults.ex` with `cu`, `mt`, `no`.
* [x] Tailoring lookup walks parent locale chain via
      `Localize.Locale.parent/1` (e.g., `nb` → `no`).
* [x] Overlay keys use NFD form to match the collation
      engine's internal normalisation.
* [x] Forced `normalization: true` when tailoring is active
      so input is decomposed to NFD before overlay lookup.
* [x] `[reorder]` directives fully supported — script reorder
      mapping preserves relative offsets for tailored weights
      by finding the nearest base weight and adding the offset.
* [x] Fixed FastLatin shortcut to be bypassed when an overlay
      is present (comment-only — the guard already handled it).
* [x] All 205 collation tests pass (14 doctests + 191 tests).

### Remaining collation work

* [x] Slash expansion notation (e.g., `ccs/cs` in Hungarian)
      fully supported — the target characters produce collation
      elements derived from the expansion's elements at the
      specified level. Works for all 11 languages that use it
      (hu, fi, sv, no, se, fo, kl, ja, zh, en-US-POSIX).

* [ ] CJK star syntax overlays (ja, ko, zh) generate very
      large overlay maps (thousands of entries). Performance
      impact on sort key generation has not been assessed.

* [ ] `search` collation type — currently excluded from
      extraction. Search collations use `[import und-u-co-search]`
      to import root search rules (~600 lines) which provide
      loose matching (accent/case insensitive). Requires:
      (1) extracting and bundling root search collation rules,
      (2) resolving `[import]` directives at extraction time,
      (3) merging imported rules with locale-specific overrides.
      Used by ko, hr, and many other locales for search/filter
      operations as opposed to display sorting.

* [x] `[suppressContractions]` directive fully supported —
      parsed from tailoring rules, stored as a codepoint list
      in Options, and checked during collation element
      production to skip contraction lookups for specified
      characters. Used by cu, sr, mk (Cyrillic И/и).
* [x] Continuation lines — multi-line CLDR rules are joined
      before parsing. Lines starting with `<`, `<<`, `<<<`,
      `<*`, `=` without `&` are appended to the previous line.
* [x] Equivalence operator (`=`) — `&X=Y` maps Y to the same
      collation elements as X. Used by Arabic (presentation
      forms) and Japanese (kana).
* [x] Bidi mark stripping — U+200E/U+200F marks in Arabic
      rules are stripped before parsing.
* [x] Inline comment stripping — `# comment` suffixes on rule
      lines are removed before parsing.

## Performance

### Pre-compile NimbleParsec parsers — completed

All three parsers are pre-compiled using
`mix nimble_parsec.compile`. Runtime helper functions (wrapper
functions called by the generated parser code) are extracted
into `Helpers` modules. NimbleParsec combinator modules are
in `dev/parsers/` and only compiled in `:dev` env.

* [x] `Localize.Unit.Parser` — template in
      `lib/localize/unit/parser.ex.exs`, runtime helpers in
      `lib/localize/unit/parser/helpers.ex`, combinator in
      `dev/parsers/combinators.ex`.

* [x] `Localize.Message.Parser` — template in
      `lib/localize/message/parser/parser.ex.exs`, runtime
      helpers in `lib/localize/message/parser/helpers.ex`,
      combinator in `dev/parsers/combinator.ex`.

* [x] `Localize.Rfc5646.Parser` — already pre-compiled.
      Grammar files moved to `dev/parsers/`.

* [x] `nimble_parsec` marked `only: :dev, runtime: false`.
      `sweet_xml` already `only: :dev, runtime: false`.

## Data and scripts

* [ ] Consolidate ad-hoc territory data conversion scripts
      into a single reusable script in `scripts/`. Currently
      `territories.etf`, `territory_codes.etf`,
      `territory_containers.etf`, `territory_containment.etf`,
      `territory_subdivision_containment.etf`, and
      `territory_subdivisions.etf` were generated by throwaway
      `mix run` scripts. See `DATA_SOURCES.md` for details.

* [ ] Clean up `scripts/convert_currency_data.exs` or
      integrate the JSON-to-ETF conversion into the build
      process.

## Design review

* [ ] Revisit `Localize.Locale.to_locale_id/1` — currently
      coerces `LanguageTag`, atom, and binary inputs to a
      locale id atom. The nil-cldr_locale_id fallback path
      (`LanguageTag.to_string |> String.to_atom`) may produce
      atoms that don't correspond to known CLDR locales.
      Consider whether this function should validate against
      known locales, return `{:ok, id} | {:error, _}`, or
      remain a best-effort coercion. Also consider whether
      callers that previously had only the 3-clause version
      (no nil fallback) are affected by now inheriting the
      4-clause behaviour.

* [ ] Review error return consistency — most functions return
      `{:error, %Exception{}}` but some (like
      `Language.to_string/2`) return bare `:error`. Standardise
      on one pattern.

* [ ] Review whether `Localize.Territory.parent/1` should
      return `{:error, %UnknownParentError{}}` for territories
      with no parents (like `:"001"`) instead of reusing
      `UnknownTerritoryError`.

* [ ] Consider whether data accessor functions in
      `Localize.SupplementalData` should be `@doc false` and
      accessed only through domain modules, or remain public.

## Completed

### Cldr public API merges

* [x] `validate_locale/1`, `validate_territory/1`,
      `validate_script/1`, `validate_calendar/1`,
      `validate_number_system/1`,
      `validate_territory_subdivision/1`,
      `validate_measurement_system/1`,
      `validate_currency/1`
* [x] `quote/2`, `ellipsis/2`
* [x] `all_locale_names/0`, `available_locale_name?/1`,
      `known_territories/0`, `known_calendars/0`,
      `known_number_systems/0`, `known_currencies/0`
* [x] `get_locale/0`, `put_locale/1`, `with_locale/2`,
      `default_locale/0`, `put_default_locale/1`
* [x] All formatting functions default `:locale` to
      `Localize.get_locale()`.

### Library merges

* [x] `ex_cldr_collation` → `Localize.Collation`
* [x] `ex_cldr_currencies` → `Localize.Currency`
* [x] `ex_cldr_messages` → `Localize.Message`
* [x] `ex_cldr_numbers` → `Localize.Number`
* [x] `ex_cldr_dates_times` → `Localize.Date`,
      `Localize.Time`, `Localize.DateTime`,
      `Localize.Interval`
* [x] `ex_cldr_units` → `Localize.Unit`
* [x] `ex_cldr_lists` → `Localize.List`
* [x] `ex_cldr_territories` → `Localize.Territory`
* [x] `ex_cldr_languages` → `Localize.Language`
* [x] `ex_cldr_locale_display` → `Localize.LocaleDisplay`

### Data and performance

* [x] Supplemental data cached in `:persistent_term`
* [x] Compiled number format metadata cached in
      `:persistent_term`
* [x] Compiled datetime format tokens cached in
      `:persistent_term`
* [x] Plural rules `@rules` attribute removed from
      Cardinal/Ordinal BEAM files
* [x] `Localize.Locale.to_locale_id/1` consolidated into
      single canonical implementation
