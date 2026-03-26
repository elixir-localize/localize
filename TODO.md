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

### Compile warnings — resolved

All compile warnings have been resolved. Zero warnings on
`mix compile --force`.

* [x] Unused module attributes removed or prefixed.

* [x] Unused functions removed.

* [x] Unused variables prefixed with underscore.

* [x] Unused alias removed.

* [x] Ungrouped clauses reordered.

* [x] Leex/yecc compiler directives added to `mix.exs`.

* [x] NimbleParsec typing violations in generated parser
      fixed by simplifying dead `{:error, reason}` branches.

### Merge localize_data into localize

The `localize_data` project (at `../localize_data`) generates and manages all CLDR data consumed by Localize. It is currently a separate path dependency. Merging it into Localize eliminates the two-repo workflow and makes CLDR data updates self-contained.

#### Current architecture

`localize_data` has two compilation targets:

* **Dev/build modules** (`lib/`) — 30 modules that read CLDR JSON/XML source files and generate ETF. These include `LocalizeData.Supplemental`, `LocalizeData.Locale`, `LocalizeData.Collation`, `LocalizeData.Validity`, `LocalizeData.PluralRules`, `LocalizeData.XmlExtractors`, `LocalizeData.ScriptMetadata`, 18 `LocalizeData.Normalize.*` modules, and 5 Mix tasks.

* **Production/runtime modules** (`production/`) — 4 modules: `LocalizeData.Application` (supervisor), `LocalizeData.DataLoader` (GenServer for serialized ETF loading), `LocalizeData.SupplementalData` (public API), `LocalizeData.LocaleTransformer` (map → struct conversion at load time).

The generated data lives in `priv/localize/` (supplemental ETF, locale ETF, validity ETF). Localize already has its own parallel runtime data access layer (`Localize.SupplementalData`, `Localize.DataLoader`) that reads ETF from `priv/cldr/`. Localize does NOT reference any `LocalizeData.*` module at runtime.

#### Merge plan

**Phase 1: Move generated data under localize priv/**

* [ ] Copy `localize_data/priv/localize/locales/` into `localize/priv/cldr/locales/` (766 ETF files, ~120 MB). The supplemental and validity ETF files are already in `localize/priv/cldr/`.

* [ ] Update `Localize.Locale.Provider.PersistentTerm.load/1` to read locale ETF directly from `priv/cldr/locales/<locale_id>.etf` instead of calling `Cldr.Locale.Loader.get_locale/2`. This removes the ex_cldr runtime dependency (already a TODO item).

* [ ] Remove the `{:ex_cldr, path: "../cldr"}` dependency from `mix.exs`.

* [ ] Verify all tests pass with the new locale loading path.

**Phase 2: Move build/generation modules into localize**

* [ ] Create `lib/localize/data/` directory for the data generation modules.

* [ ] Move the 5 Mix tasks from `localize_data/lib/mix/tasks/` to `localize/lib/mix/tasks/`, renaming from `localize_data.*` to `localize.*`:
  - `mix localize.copy_sources` — copies raw CLDR JSON/XML into priv/
  - `mix localize.generate_supplemental` — generates supplemental ETF files
  - `mix localize.generate_locales` — generates locale ETF files
  - `mix localize.download_iso_currencies` — downloads ISO 4217 list
  - `mix localize.upload_locale` — uploads locale ETF to CDN

* [ ] Move the generation modules to `lib/localize/data/`:
  - `LocalizeData` → `Localize.Data` (main orchestrator)
  - `LocalizeData.Supplemental` → `Localize.Data.Supplemental`
  - `LocalizeData.Locale` → `Localize.Data.Locale`
  - `LocalizeData.Collation` → `Localize.Data.Collation`
  - `LocalizeData.Validity` → `Localize.Data.Validity`
  - `LocalizeData.PluralRules` → `Localize.Data.PluralRules`
  - `LocalizeData.XmlExtractors` → `Localize.Data.XmlExtractors`
  - `LocalizeData.ScriptMetadata` → `Localize.Data.ScriptMetadata`
  - 18 `LocalizeData.Normalize.*` → `Localize.Data.Normalize.*`

* [ ] Add `{:sweet_xml, "~> 0.7", only: :dev, runtime: false}` (already present in localize mix.exs).

**Phase 3: Merge runtime modules**

All four runtime modules in `localize_data/production/` are either duplicated in localize or unnecessary:

* [ ] `LocalizeData.DataLoader` — already duplicated as `Localize.DataLoader`. Drop.

* [ ] `LocalizeData.SupplementalData` — already duplicated as `Localize.SupplementalData`. Drop.

* [ ] `LocalizeData.Application` — the supervisor that starts `DataLoader`. Localize already has `Localize.Application`. Drop.

* [ ] `LocalizeData.LocaleTransformer` — converts raw maps to `Localize.Number.Symbol`, `Localize.Number.Format`, and `Localize.Currency` structs. This is already called in the build pipeline (`LocalizeData.Locale` line 77) so the generated locale ETF files already contain pre-built structs. It only lives in `production/` because the current localize code loads raw maps via `Cldr.Locale.Loader.get_locale` and would need runtime transformation. Once Phase 1 switches to reading the pre-built ETF files directly, this module is not needed at runtime. Move to `lib/localize/data/` as a build-only module.

**Phase 4: Move CLDR source data**

* [ ] Move `localize_data/priv/cldr/` (raw JSON/XML source files) into `localize/priv/cldr_sources/` to keep source data separate from generated data. This is ~500 MB and should be gitignored; the Mix task `mix localize.copy_sources` populates it from the CLDR repository.

* [ ] Add `priv/cldr_sources/` to `.gitignore`.

* [ ] Move the `ldml2json` shell script to `scripts/ldml2json`.

**Phase 5: Remove localize_data dependency**

* [ ] Remove `{:localize_data, path: "../localize_data", env: Mix.env()}` from `mix.exs`.

* [ ] Remove the `localize_data` application from `extra_applications` if present.

* [ ] Move the CI workflow (`upload-locales.yml`) to localize's `.github/workflows/`.

* [ ] Write `CLDR_DATA.md` documenting the data update process.

* [ ] Run full test suite + dialyzer.

#### Files summary

| Source (localize_data) | Destination (localize) | Action |
|---|---|---|
| `production/localize_data/data_loader.ex` | — | Drop (already have `Localize.DataLoader`) |
| `production/localize_data/supplemental_data.ex` | — | Drop (already have `Localize.SupplementalData`) |
| `production/localize_data/application.ex` | — | Drop (already have `Localize.Application`) |
| `production/localize_data/locale_transformer.ex` | `lib/localize/data/localize/data/locale_transformer.ex` | Move to dev-only (build pipeline only) |
| `lib/localize_data.ex` | `lib/localize/data/localize/data.ex` | Move + rename |
| `lib/supplemental.ex` | `lib/localize/data/localize/data/supplemental.ex` | Move + rename |
| `lib/locale.ex` | `lib/localize/data/localize/data/locale.ex` | Move + rename |
| `lib/collation.ex` | `lib/localize/data/localize/data/collation.ex` | Move + rename |
| `lib/localize_data/validity.ex` | `lib/localize/data/localize/data/validity.ex` | Move + rename |
| `lib/plural_rules.ex` | `lib/localize/data/localize/data/plural_rules.ex` | Move + rename |
| `lib/xml_extractors.ex` | `lib/localize/data/localize/data/xml_extractors.ex` | Move + rename |
| `lib/localize_data/script_metadata.ex` | `lib/localize/data/localize/data/script_metadata.ex` | Move + rename |
| `lib/normalize/*.ex` (18 files) | `lib/localize/data/localize/data/normalize/*.ex` | Move + rename |
| `lib/mix/tasks/*.ex` (5 files) | `lib/mix/tasks/*.ex` | Move + rename prefix |
| `priv/localize/locales/*.etf` (766 files) | `priv/cldr/locales/*.etf` | Move |
| `priv/cldr/` (source JSON/XML) | `priv/cldr_sources/` | Move (gitignored) |
| `.github/workflows/upload-locales.yml` | `.github/workflows/upload-locales.yml` | Move |
| `ldml2json` | `scripts/ldml2json` | Move |

### Placeholder code

* [x] Remove `Localize.hello/0` — placeholder function from
      project generation.

### Documentation

* [x] Write `Localize` moduledoc — expanded with domain module
      list, locale management summary, data loading strategy,
      and NIF mention.

* [x] Review and update all public module `@moduledoc`
      sections — expanded `DateTime`, `Unit`, and `Locale`
      moduledocs. Others verified as adequate.

* [x] Write a `README.md` with installation, quick start,
      and links to documentation.

* [x] Write a `CHANGELOG.md`.

* [x] Ensure all public functions have `@doc` in the standard
      format described in `CLAUDE.md` — audited all 15 main
      public modules; all public functions documented.
### Hex publishing

* [ ] Set version in `mix.exs`.

* [ ] Add `:description`, `:package`, `:source_url` to
      `mix.exs` for Hex.

* [ ] Add license file.

* [ ] Define docs structure in `mix.exs` including topic
      grouping and user guides (`guides/number_formatting.md`,
      `guides/date_time_formatting.md`,
      `guides/unit_formatting.md`,
      `guides/message_formatting.md`,
      `guides/collation.md`,
      `guides/architecture.md`,
      `guides/migration.md`,
      `guides/conformance.md`).

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

* [x] CJK star syntax overlays (ja, ko, zh) generate large
      overlay maps (ja: 7,164, ko: 7,476, zh: ~525 entries).
      Performance assessed: sub-microsecond per lookup (575ns
      for 7,476-entry map), ~630KB memory per CJK locale.
      Codepoints are scattered (not contiguous ranges) so
      range-based arithmetic derivation is not feasible.
      Current flat map approach is acceptable.

* [x] `search` collation type — root search rules extracted
      from CLDR XML (Arabic form equivalences, Korean jamo
      decomposition, `[suppressContractions]`). `[import]`
      directives resolved at extraction time by inlining
      referenced rules. 20 locale-specific search entries with
      merged imports. Parent chain fallback reaches `und:search`
      for all locales. Accessed via `type: :search` option.

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

* [ ] Determine minimum supported Elixir and OTP versions.
      Currently `mix.exs` specifies `elixir: "~> 1.19"`. Decide
      whether to support earlier versions (1.17+, 1.18+) and
      which OTP versions (26, 27, 28). This affects availability
      of the `:json` module (OTP 27+), `+0.0` pattern matching
      (OTP 27+), and other language features.

* [ ] MF2 JSON interchange format (`Localize.Message.JSON`)
      requires a JSON library. OTP 27+ includes the `:json`
      module natively. Decide whether to support only OTP 27+
      or provide a fallback (e.g., conditional `Code.ensure_loaded?(:json)`
      with a dependency like `jason` for earlier versions).
      Currently `mix.exs` specifies `elixir: "~> 1.19"` which
      implies OTP 27+, so this may already be resolved.

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

## CLDR 48.2 Migration

CLDR 48.2 introduces changes to locale display names, key fallback behavior, and MF2 function stability. The data format changes are minimal but the algorithm changes in `LocaleDisplay` require code updates.

Reference: https://www.unicode.org/reports/tr35/tr35-modifications.html#modifications

### 1. Nested Bracket Replacement (new data + algorithm)

CLDR 48.2 formalizes the nested bracket replacement as structured data rather than ad-hoc string replacement. The data is:

```xml
<nestedBracketReplacement bracket="(">[</nestedBracketReplacement>
<nestedBracketReplacement bracket=")">]</nestedBracketReplacement>
<nestedBracketReplacement bracket="（">［</nestedBracketReplacement>
<nestedBracketReplacement bracket="）">］</nestedBracketReplacement>
```

Reference: https://www.unicode.org/reports/tr35/tr35-general.html#Character_Nested_Bracket_Replacement

**Current state:** We already replace parentheses with brackets in `LocaleDisplay.replace_parens_with_brackets/1` (locale_display.ex:377-382) with hardcoded `String.replace` calls. This produces the correct output but doesn't use the CLDR data.

**Changes needed:**

* [ ] Load `nestedBracketReplacement` data from CLDR locale data (likely in `locale_display_names` or `characters` section).

* [ ] Replace the hardcoded `replace_parens_with_brackets/1` with a data-driven implementation that reads the bracket mapping from the locale data. This allows locale-specific bracket replacement if CLDR ever adds locale-specific mappings.

* [ ] Apply bracket replacement only when nesting is detected (inner brackets within outer brackets), not unconditionally as we do now. The algorithm should detect when a subtag display name contains the same bracket characters as the `localePattern` and only then apply replacement.

**Risk:** Low. The current hardcoded behavior already produces the correct output for all known CLDR locales. This is a formalization of existing behavior.

### 2. Locale Display Name Algorithm — reorder -u- before -t-

CLDR 48.2 changes the display order so that `-u-` (Unicode locale extension) names appear **before** `-t-` (transform extension) names. We currently display `-t-` first, then `-u-`.

**Current state:** In `extension_display_names/4` (locale_display.ex:276-314), T extension is processed at lines 279-288, then U extension at lines 290-301.

**Changes needed:**

* [ ] Swap the order in `extension_display_names/4` so that U extension is processed first and T extension second.

**Risk:** Low. Simple reorder of two code blocks.

### 3. Locale Display Name Algorithm — flatten -t- language names

CLDR 48.2 specifies that `-t-` transform language names should be flattened to avoid nested parentheses. Instead of recursively calling `display_name` (which wraps in parentheses via `localePattern`), the transform language's subtags should be appended directly to the locale qualifying string (LQS).

**Current state:** In `locale_display/t.ex:104-107`, the `:language` display value calls `Localize.LocaleDisplay.display_name!/2` which recursively generates a full display name including `localePattern` wrapping. This produces nested parentheses like "English (Transform: German (Germany))".

**Changes needed:**

* [ ] Modify `display_value(:language, ...)` in `locale_display/t.ex` to NOT call `display_name!` recursively. Instead, parse the transform language tag and collect its subtag display names (script, region, variants) as a flat list, then join them with the locale separator.

* [ ] The flattened result should be something like "Transform: German, Germany" instead of "Transform: German (Germany)".

**Risk:** Medium. This changes visible output for locales with `-t-` extensions. Need to verify against CLDR test data.

### 4. Missing key translations fallback to key identifier

CLDR 48.2 specifies that when a `<keys>` translation is missing, the key identifier should be used as the fallback rather than omitting the key name.

**Current state:** In `locale_display/t.ex:117-124` and `locale_display/u.ex`, when `key_name` is nil, the code falls back to showing just the value without any key label. In some cases it returns the raw value string.

**Changes needed:**

* [ ] When `get_in(display_names, [:keys, field])` returns nil, fall back to the BCP 47 key identifier string (e.g., "ca" for calendar, "nu" for numbering system) instead of omitting the key.

* [ ] Apply this fallback in both `locale_display/t.ex` and `locale_display/u.ex` in the `display_value` functions.

**Risk:** Low. Adds a fallback where previously there was none. Improves output for incomplete locale data.

### 5. MF2 :currency and :percent — mark as Stable

CLDR 48.2 promotes `:currency` and `:percent` MF2 functions from Draft to Stable status, with the same implementations as previously.

**Current state:** Both functions are implemented in `message/interpreter.ex` (lines 285-297) and work correctly. They are not explicitly documented with a stability status.

**Changes needed:**

* [ ] Add documentation to the MF2 function registry or interpreter noting that `:currency` and `:percent` are Stable per MF2 specification.

* [ ] No implementation changes needed — the spec says implementations are unchanged.

**Risk:** None. Documentation-only change.

### 6. MF2 u:locale option — remove

CLDR 48.2 drops the `u:locale` option from the MF2 specification (it was previously in Draft).

**Current state:** Need to check if we implemented the `u:locale` option.

**Changes needed:**

* [ ] Search for any `u:locale` handling in the MF2 interpreter. If present, remove it. If not present, no action needed.

**Risk:** Low.

### 7. Data update

* [ ] Update CLDR data files from 48.1 to 48.2 in `priv/cldr/`.

* [ ] Verify any new data keys in the locale JSON files (e.g., `nestedBracketReplacement` data).

* [ ] Run the full test suite against the new data to catch any format string changes or new locale additions.

### Migration order

1. Update CLDR data files (item 7)
2. Swap -u- / -t- ordering (item 2) — simple, low risk
3. Flatten -t- language names (item 3) — medium complexity
4. Missing key fallback (item 4) — low risk
5. Nested bracket replacement from data (item 1) — low risk
6. MF2 stability docs and u:locale removal (items 5, 6) — trivial
7. Run full test suite + update expected test outputs
