# Developing Localize

This document is for developers maintaining `Localize` itself, not for end users of the library. End-user documentation lives in `README.md`, the guides under `guides/`, and on HexDocs.

## Repository layout

```
.
├── lib/                          # Runtime library code shipped to users
│   └── localize/
│       ├── number/               # Number formatting + parsing
│       ├── datetime/             # Date, Time, DateTime, Interval, Relative, Formatter
│       ├── calendar/             # Calendar systems and display names
│       ├── currency/             # Currency data, store, validation
│       ├── unit/                 # Unit parser, formatter, conversion, math
│       ├── locale/               # LanguageTag parser, validation, providers, cache
│       ├── collation/            # UCA implementation, tailoring, FastLatin, table, NIF wrapper
│       ├── message/              # MessageFormat 2 parser, interpreter, JSON, gettext bridge
│       ├── exception/            # All Localize.*Error exception modules
│       ├── utils/                # Helpers, Http, Json, Math, Decimal compat, etc.
│       ├── validity/             # Language/script/territory/variant validity
│       └── ...
├── data/                         # Compile-time-only code: data generation pipeline
│   ├── data.ex                   # Localize.Data — source layout, copy, version handling
│   ├── locale.ex                 # Localize.Data.Locale — per-locale ETF generation
│   ├── normalize/                # Per-domain CLDR-JSON-to-Elixir normalizers
│   └── mix/tasks/                # mix localize.* tasks
├── priv/
│   ├── cldr/                     # Raw CLDR JSON/XML source files (committed)
│   │   ├── supplemental_data/
│   │   ├── locales/
│   │   ├── collation/
│   │   ├── validity/
│   │   ├── bcp47/
│   │   └── external_sources/
│   └── localize/                 # Generated ETF files Localize loads at runtime
│       ├── version               # CLDR release version (e.g. "48.2")
│       ├── localize_patch_version# Localize patch counter "{cldr_version}:{patch}"
│       ├── locales/              # Per-locale ETF files (only en.etf is committed)
│       ├── supplemental_data/    # Generated supplemental ETF
│       └── validity/             # Generated validity ETF
├── c_src/                        # Optional ICU4C NIF (LOCALIZE_NIF=true)
│   ├── localize_nif.cpp
│   └── Makefile
├── src/                          # leex/yecc grammars (parsers)
├── test/                         # ExUnit test suite
│   └── support/                  # Test fixtures, generators, conformance data
├── guides/                       # End-user HexDocs guides
├── usage-rules.md                # LLM coding-agent instructions for end users
├── CLAUDE.md                     # Per-project instructions for the Claude harness
└── mix.exs
```

The `data/` tree is loaded only in `:dev` and `:test` environments (see `elixirc_paths/1` in `mix.exs`). It is not part of the Hex package and never loaded at runtime by an end user.

## Build, test, format, docs

These are the standard commands for any session:

```bash
mix compile                    # Compile lib/ and (in :dev/:test) data/
mix test                       # Full test suite (~58s)
mix format                     # Format Elixir code
mix dialyzer                   # Static type analysis
MIX_ENV=release mix docs       # Generate HexDocs
```

* `mix test` must run from the project root.

* `mix docs` must always be run with `MIX_ENV=release`. Running it in the default `:dev` environment pulls in the `data/` modules and produces spurious doc-reference warnings.

* `mix dialyzer` is configured in `mix.exs` with `:underspecs`, `:extra_return`, `:missing_return`, and `:error_handling` flags. Treat new dialyzer warnings as build failures.

## Project conventions

These conventions are enforced across the codebase. New code must follow them.

### Module attributes

All `@attr value` declarations must appear after `import`/`alias`/`require`/`use` and before any function definitions. No inline module attributes between functions.

### Variable and option names

* Use complete names for variables and parameters where possible.

* Always use `options`, never `opts`.

### No `try/rescue` as control flow

Use pattern matching, `case`, `with`, or tagged tuples (`{:ok, _}` / `{:error, _}`) instead. `try/rescue` is reserved for true system boundaries (e.g. NIF calls, external library calls that raise on invalid input with no other API).

### Public function documentation template

Every public function needs:

* A short description of the function's purpose.

* `### Arguments` — bullet list naming each argument.

* `### Options` — when the last argument is a keyword list, list each option.

* `### Returns` — describe the alternative return values.

* `### Examples` — one or two doctest examples.

* Bullets use `*`, not `-`.

* Each bullet ends with a period.

* A blank line before the closing `"""`.

### Public module documentation

Public modules (those without `@moduledoc false`) must have a heredoc moduledoc that describes the module's purpose and primary public API. Blank line before the closing `"""`.

### Markdown documents

* Do not wrap multiline text. Each paragraph is a single long line.

* Code examples in markdown use doctest format (`iex>` prompts and expected results), even when they are not actually run as tests.

### Error returns

Public API functions return `{:ok, value}` on success and `{:error, %Localize.SomethingError{}}` on failure. The error tuple **always** carries a struct, never a string or `{Module, message}` tuple. Exception modules live in `lib/localize/exception/` and are named `Localize.<Something>Error`.

Each exception:

```elixir
defmodule Localize.MyAppError do
  defexception [:binding_one, :binding_two]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{binding_one: a, binding_two: b}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "context_string",   # e.g. "locale", "number", "currency"
      "Human-readable message with %{binding_one} and %{binding_two}.",
      binding_one: inspect(a),
      binding_two: inspect(b)
    )
  end
end
```

The `domain` is always `"localize"`. The `msgctxt` should be one of `"locale"`, `"language_tag"`, `"number"`, `"datetime"`, `"currency"`, `"unit"`, `"message"`, etc., matching the area of the library.

## Locale data generation pipeline

`Localize` ships with an on-disk ETF representation of CLDR for each of the 766 locales. Only `priv/localize/locales/en.etf` is committed; the rest are generated on demand in `:dev`/`:test` and downloaded on demand in `:prod`.

### Source data

Raw CLDR JSON and XML lives under `priv/cldr/`. It is copied from a CLDR checkout via `mix localize.copy_sources`, which uses two environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `CLDR_PRODUCTION_DATA` | `../cldr_production_data` | The `production` directory with merged JSON locale files |
| `CLDR_REPO` | `../cldr` | The full CLDR git checkout for XML and test data |

You normally only need a CLDR checkout when upgrading to a new CLDR release.

### Producing `CLDR_PRODUCTION_DATA` from a fresh CLDR release

CLDR ships its primary data as XML in the `unicode-org/cldr` repository. Localize consumes a JSON-converted "production" view of that data. The conversion is the responsibility of the CLDR Java tool `ldml2json`, wrapped by the helper script `scripts/ldml2json` in this repository.

The script does the following:

1. Verifies that three directories exist: `CLDR_REPO` (a clone of `unicode-org/cldr`), `CLDR_STAGING` (working area for the production-data layout), and `CLDR_PRODUCTION` (where the final JSON is written).

2. Builds the CLDR Java tools jar via `mvn package -pl cldr-code` from `$CLDR_REPO/tools/`.

3. Runs `org.unicode.cldr.tool.GenerateProductionData` to create the production view of `common/` under `$CLDR_STAGING/common/`. This is the same filtering CLDR applies before publishing the `cldr-json` release artifacts.

4. Runs `ldml2json` three times against `$CLDR_STAGING`, writing to `$CLDR_PRODUCTION`:
   * Default `-t` invocation — produces locale-specific JSON in the `cldr-numbers-full`, `cldr-dates-full`, `cldr-cal-*-full`, `cldr-localenames-full`, `cldr-misc-full`, `cldr-units-full`, and `cldr-person-names-full` directories. Each holds `main/{locale}/*.json` files.
   * `-t supplemental` — produces `cldr-core/supplemental/*.json` and `cldr-core/coverageLevels.json`.
   * `-t rbnf` — produces `cldr-rbnf/rbnf/{locale}.json`.

5. Copies CLDR test data files from `$CLDR_REPO/common/testData/` and `$CLDR_REPO/tools/cldr-code/src/test/resources/` to `$EX_CLDR/test/support/data/`. (See "Issues with the script" below — this part is wrong for Localize.)

The script has a TODO at the top to migrate to [`cldr-generate-json.sh`](https://github.com/unicode-org/cldr-json/blob/main/cldr-generate-json.sh) — the official script the `cldr-json` project itself uses — for CLDR 49+. That would replace the manual `mvn` + `ldml2json` invocation with the upstream-supported flow and is the right long-term direction.

### What `ldml2json` produces vs. what Localize consumes

`mix localize.copy_sources` reads from two distinct sources:

**From `CLDR_PRODUCTION_DATA`** (the JSON output of `ldml2json`):

| Path | Used by | Notes |
|---|---|---|
| `cldr-core/supplemental/aliases.json` | `Localize.Data.Supplemental.generate_aliases/0` | One of 15 supplemental JSON files in `@supplemental_json_files` in `data/data.ex` |
| `cldr-core/supplemental/{calendarPreferenceData,codeMappings,currencyData,languageMatching,likelySubtags,measurementData,numberingSystems,ordinals,parentLocales,plurals,territoryContainment,territoryInfo,timeData,weekData}.json` | various supplemental generators | |
| `cldr-core/coverageLevels.json` | `Localize.Data.Supplemental.generate_coverage_levels/0` | |
| `cldr-numbers-full/main/en/currencies.json` | currency code generator | One-off; only the `en` copy is needed |
| `cldr-{cal-*,dates,localenames,misc,numbers,person-names,units}-full/main/{locale}/*.json` | `Localize.Data.copy_locale_sources/0` and the per-locale normalizers in `data/normalize/` | 766 locales × ~17 packages |
| `cldr-rbnf/rbnf/{locale}.json` | RBNF generator | Optional per-locale; only present for locales with RBNF rules |

**From `CLDR_REPO`** (the raw git checkout) — `ldml2json` is *not* involved with these:

| Path | Used by |
|---|---|
| `common/supplemental/{pluralRanges,subdivisions,units}.xml` | `copy_supplemental_sources/0` |
| `common/subdivisions/{locale}.xml` | `copy_locale_sources/0` (per-locale subdivision names) |
| `common/bcp47/timezone.xml` | `copy_supplemental_sources/0` |
| `common/collation/*.xml` | `copy_collation_sources/0` |
| `common/validity/*.xml` | `copy_validity_sources/0` |
| `common/bcp47/*.xml` | `copy_bcp47_sources/0` |
| `tools/cldr-code/src/main/resources/org/unicode/cldr/util/data/Script_Metadata.csv` | `copy_script_metadata/0` |
| `common/testData/**` and various test resources | `copy_test_data/0` |

These XML files and test data are read from `CLDR_REPO` directly because Localize either parses XML in-process or because no JSON form is published. **`ldml2json` does not need to do anything for them.** In particular, the per-locale subdivision XML files (`common/subdivisions/{locale}.xml`) are not converted to JSON by `ldml2json` and are not included in the upstream `cldr-json` release artifacts, so Localize sources them straight from the CLDR repository.

### Issues with the current `scripts/ldml2json`

When you upgrade to a new CLDR release, verify the following before relying on the script:

1. **`-t` with no argument value.** The first `ldml2json` invocation ends with `-t` and no value. This relies on `ldml2json`'s default behavior to process all main/locale types. If a future CLDR release tightens this argument, you may need to specify `-t main` (or run a loop over individual locales — see the commented per-locale loop in the script).

2. **`mvn package` requires JDK 11+.** The script builds `cldr-code.jar` from source on every run. Build failures are usually JDK version mismatches. CLDR 47+ requires JDK 11 or newer.

3. **`-Xmx16g` heap.** Required because processing all locales in a single `ldml2json` run pushes the JVM heap. If you hit `OutOfMemoryError` even at 16 GB, fall back to the commented per-locale loop in the script.

### CLDR upgrade checklist

The end-to-end flow for adopting a new CLDR release:

```bash
# 1. Update CLDR sources
cd $CLDR_REPO && git fetch && git checkout release-NN

# 2. Regenerate production JSON from XML
$LOCALIZE/scripts/ldml2json     # Or use cldr-generate-json.sh from cldr-json

# 3. Bring sources into the Localize repo
cd $LOCALIZE
mix localize.copy_sources   # Copies JSON from CLDR_PRODUCTION_DATA and XML
                            # (including per-locale subdivisions, validity,
                            # bcp47, collation, and supplemental) directly
                            # from CLDR_REPO. Writes priv/localize/version
                            # and auto-resets localize_patch_version to
                            # {new_cldr}:0 if the CLDR major version
                            # actually changed.

# 4. The on-disk version may now be just the major component (e.g. "48").
#    If you want to record a more-specific sub-release, edit it by hand:
echo -n "48.3" > priv/localize/version

# 5. Regenerate supplemental and locale ETF files
mix localize.generate_supplemental
mix localize.generate_locales

# 6. Run tests — expect breakage from CLDR data changes
mix test

# 7. Bump the patch counter if you also changed any normalizer or transform
mix localize.bump_patch_version
```

### Generation flow

```
priv/cldr/  →  data/normalize/  →  data/locale.ex  →  priv/localize/locales/*.etf
```

1. `data/normalize/*.ex` — one normalizer per CLDR domain (calendar, currency, number, units, etc.). Each takes the raw CLDR JSON for a locale and returns an Elixir map in the runtime shape Localize expects.

2. `data/locale.ex` — orchestrates all normalizers, runs struct transforms, and writes a single ETF file per locale. The `add_version/1` step injects the current `Localize.version/0` into every ETF under the `:version` key so the cache can detect stale files.

3. `mix localize.generate_locales` — runs the full pipeline for all 766 locales. Takes a few minutes.

4. `mix localize.generate_supplemental` — generates the supplemental ETF files (plural rules, territory containment, currency data, etc.) under `priv/localize/supplemental_data/`.

### Mix tasks

```bash
mix localize.copy_sources               # Copy CLDR sources from CLDR_PRODUCTION_DATA / CLDR_REPO
mix localize.download_unicode_data      # Download UCD files for collation
mix localize.download_iso_currencies    # Download ISO 4217 currency data
mix localize.generate_supplemental      # Regenerate supplemental ETF
mix localize.generate_locales           # Regenerate all 766 locale ETFs
mix localize.generate_locales en fr de  # Regenerate specific locales
mix localize.bump_patch_version         # Increment the Localize patch counter
mix localize.upload_locale              # Generate one locale and upload to Cloudflare R2
```

## Versioning: CLDR + Localize patch

Localize has a runtime version distinct from its Hex package version:

* The **CLDR release version** is recorded in `priv/localize/version` (e.g. `48.2`).

* The **Localize patch counter** is recorded in `priv/localize/localize_patch_version` in the format `{cldr_version}:{patch}` (e.g. `48.2:1`). It tracks Localize-side changes to the data-generation pipeline within a single CLDR release.

* `Localize.version/0` returns a `%Version{}` assembled from the two: `48.2:1` becomes `%Version{major: 48, minor: 2, patch: 1}`. CLDR sometimes records only the major component in `aliases.json` (e.g. `"48"`), so the parser pads missing minor/patch with `0`.

* Every locale ETF carries this version under its `:version` key. `Localize.Locale.Provider.Cache.stale?/1` re-downloads any cached file whose version does not match `Localize.version/0`.

### When the patch version changes

| Trigger | Behaviour |
|---|---|
| `mix localize.generate_locales` (CI or dev) | Generates ETFs with the *current* on-disk version. **No automatic patch bump.** |
| `mix localize.bump_patch_version` (developer, explicit) | Increments the patch counter for the current CLDR version (e.g. `48.2:1 → 48.2:2`) and clears the cached `Localize.version/0` term. |
| `mix localize.copy_sources` when CLDR upgrades | Detects a new CLDR major version, writes the new value to `priv/localize/version`, and resets the patch counter to `{new}:0`. |
| `mix localize.copy_sources` with no CLDR change | Leaves both files alone, even when the on-disk file carries a more-specific sub-version (e.g. `48.2`) than `aliases.json` reports (`48`). |

**Why the auto-bump was removed.** The Cloudflare upload workflow regenerates locales from CI on every push to `main`. Auto-bumping on every run would produce phantom version increments. The patch counter is now strictly developer-driven and meaningful: it goes up only when a human runs `mix localize.bump_patch_version` after editing a normalizer or transform.

### Typical developer workflows

**Editing a normalizer or transform:**

```bash
# 1. Make pipeline changes
$EDITOR data/normalize/number.ex

# 2. Bump the patch version explicitly
mix localize.bump_patch_version    # 48.2:1 → 48.2:2

# 3. Regenerate locales so the ETFs carry the new version
mix localize.generate_locales

# 4. Run tests
mix test

# 5. Commit
```

**Upgrading CLDR:**

```bash
# 1. Update your local CLDR checkout
cd ../cldr && git pull && cd ../localize

# 2. Copy fresh sources (auto-resets patch to {new}:0 if major changed)
mix localize.copy_sources

# 3. If the on-disk version was a more-specific sub-version you want
#    to preserve, set it manually:
echo -n "48.3" > priv/localize/version

# 4. Regenerate everything
mix localize.generate_supplemental
mix localize.generate_locales

# 5. Run the full test suite — expect breakage from CLDR data changes
mix test
```

## Locale download, cache, and provider

`Localize.Locale.Provider` defines a behaviour with four callbacks (`load/1`, `store/2`, `loaded?/1`, `get/3`) and a number of helper functions for the URL/cache infrastructure.

### Provider helpers

* `locale_cache_dir/0` — returns the on-disk cache directory. Defaults to `Path.join(:code.priv_dir(:localize), "localize/locales")`. Configurable via `config :localize, :locale_cache_dir, "/path/to/cache"`.

* `base_url/0` — `"https://elixir-localize.com/locales"`.

* `version_segment/0` — current `Version.to_string(Localize.version())`, used to scope URLs to a release.

* `locale_url/1` — `https://elixir-localize.com/locales/{version}/{locale_id}.etf`.

* `download_locale/1` — downloads via `Localize.Utils.Http.get/2` (which uses `:httpc` with secure SSL by default).

### Cache module

`Localize.Locale.Provider.Cache` reads/writes ETF files in the cache dir:

* `path/1` — `{cache_dir}/{locale_id}.etf` (no version subdirectory).

* `get/1` — returns `{:ok, locale_data}` if present and version matches, `{:error, LocaleIsStaleError}` if version mismatches, `{:error, LocaleNotFoundInCacheError}` if missing.

* `store/2` — writes the binary ETF and creates the cache directory if needed.

* `stale?/1` — `true` if missing or version mismatch.

Version comparison uses `Version.compare/2`.

### Default provider

`Localize.Locale.Provider.PersistentTerm.load/1` is compile-time specialized:

* In `:dev`/`:test`: cache miss falls back to `Localize.Data.Locale.generate_and_transform/1`. This means dev and test never need a network and never need pre-generated ETF files for locales other than `:en`.

* In `:prod`: cache miss falls back to `Provider.download_locale/1` and stores the result.

## Optional NIF (ICU4C)

The `c_src/` directory contains an optional NIF binding to ICU4C. It is opt-in:

```bash
LOCALIZE_NIF=true mix compile
```

or:

```elixir
config :localize, :nif, true
```

When enabled, certain functions accept `backend: :nif` and delegate to ICU4C. Pure Elixir is the default and is faster for everything except MessageFormat 2 (see `guides/performance.md`).

`Localize.Nif.available?/0` returns whether the NIF was actually compiled and loaded.

The NIF requires ICU4C development headers at compile time:

* macOS: `brew install icu4c`
* Ubuntu/Debian: `apt install libicu-dev`

The build is gated through `mix.exs` `maybe_elixir_make/0`, which only adds `:elixir_make` as a compiler when `LOCALIZE_NIF=true` or `config :localize, :nif, true`.

## Testing

* The full test suite is ~23,500 tests / ~590 doctests / ~13 properties / ~58 seconds.

* Test files mirror `lib/`: a module at `lib/localize/foo/bar.ex` is tested by `test/localize/foo/bar_test.exs`.

* `test/support/` holds fixtures, generators, conformance data, and test-only support modules. Loaded via `elixirc_paths(:test)` in `mix.exs`.

* Property-based tests use `stream_data` and live in `test/localize/adversarial_test.exs` and a few domain-specific files. Adversarial tests intentionally fuzz format atoms, locales, and dates to find edge cases. Treat any failing seed as a real bug — the failure is deterministic given its inputs.

* CLDR conformance test data lives in `test/support/data/` (collation, locale-display, etc.).

* Doctests are validated as part of `mix test`. Markdown guide examples are not run as doctests but are checked manually before release; see the release review section.

* Test tag `@moduletag :nif` marks tests that require the NIF to be loaded. They are skipped automatically when the NIF is unavailable.

## CI

Three GitHub Actions workflows live in `.github/workflows/`:

* `ci.yml` — runs `mix test`, `mix format --check-formatted`, and `mix dialyzer` against a matrix of Elixir/OTP versions on every PR and push.

* `upload-locales.yml` — regenerates all 766 locale ETFs and uploads them to Cloudflare R2 (the CDN behind `https://elixir-localize.com/locales`). Triggered on pushes of `v*` tags. The workflow:

  1. Reads the current `data_version` (e.g. `v48.2.1`) directly from `priv/localize/version` and `priv/localize/localize_patch_version` before any compile or generation.

  2. Configures `rclone` for R2 and checks whether the target prefix `r2:locales/{data_version}/` already contains ETF files.

  3. If the prefix is already populated, the workflow logs a notice and **skips the Elixir setup, compile, generate, and upload steps entirely** — nothing is regenerated or re-uploaded.

  4. If the prefix is empty, the workflow sets up Elixir, runs `mix localize.generate_locales`, uploads via `rclone sync`, and verifies the upload count.

  This short-circuit exists so that release tags can be re-pushed or re-applied (for example to trigger a Hex publish retry) without accidentally overwriting data that is already live on the CDN. The only way to publish a new set of ETFs is to bump either the CLDR version or the Localize patch counter (via `mix localize.bump_patch_version`) and then tag the commit. `mix localize.generate_locales` itself does not bump the patch — for exactly this reason.

* `delete-locales.yml` — manually triggered (`workflow_dispatch`) workflow for removing a previously-uploaded data version from R2. Useful when pulling a broken release or retiring old versions. Inputs:

  * **`data_version`** — the version to delete, e.g. `v48.2.1`. Must match the strict `v{major}.{minor}.{patch}` format; anything else is rejected by a regex check before any rclone call runs.
  * **`confirmation`** — must literally equal `data_version`. This is a two-field typed confirmation so a one-click accident from the Actions UI is not sufficient to destroy data.
  * **`dry_run`** (default `true`) — lists the objects at the target prefix without touching anything. You must explicitly set it to `false` to actually delete.
  * **`allow_current`** (default `false`) — the workflow refuses to delete the data version currently recorded on `main` unless this is explicitly set. Protects the live release from being wiped by accident.

  The delete itself uses `rclone purge`, which removes both the objects and the empty prefix. After deletion, the workflow verifies that the prefix is empty and fails loudly if anything remains. Every step logs to the Actions output so there is an audit trail of who initiated the delete, what was listed, and what was removed.

  **Typical usage.** To retire `v48.2.0` after publishing `v48.2.1`:

  1. Run the workflow with `data_version: v48.2.0`, `confirmation: v48.2.0`, `dry_run: true`. Confirm from the log that the object list matches expectations.
  2. Re-run with the same inputs but `dry_run: false`. The objects are removed and the run verifies the prefix is empty.

  To delete the live version (rarely needed, usually only after a security incident or a publish that needs to be pulled immediately):

  1. First dry-run as above.
  2. Re-run with `dry_run: false` **and** `allow_current: true`. Be ready to re-upload immediately — end users downloading that version will start getting 404s.

## Release process

Before publishing a new Hex version:

1. Function docs follow the standard template (see "Public function documentation template" above).

2. README is clear and approachable for new users.

3. Doc examples in the README and guides match actual execution. Spot-check the iex> blocks in the guides; the full set is quite large.

4. Moduledocs are complete and clear.

5. CHANGELOG is up to date and groups changes under `### Added`, `### Changed`, `### Fixed`, etc. The unreleased version sits at the top under `## [x.y.z] — Unreleased`.

6. All tests pass: `mix test`.

7. Static analysis passes: `mix dialyzer`.

8. Docs build cleanly with no reference warnings: `MIX_ENV=release mix docs`.

9. The Hex package files list in `mix.exs` includes everything needed at runtime and nothing from `data/` or raw CLDR sources. The package ships only `priv/localize/locales/en.etf` — other locales are downloaded by end users on demand.

10. `usage-rules.md` is up to date — this is the LLM-agent guidance file shipped to end users via the `usage_rules` Hex package convention.

## Companion packages

Some functionality is intentionally split into separate packages so that Localize stays focused on CLDR core data:

* [`localize_person_names`](https://hex.pm/packages/localize_person_names) — TR35 Part 8 person name formatting. Uses Localize's locale data under the `:person_names` key.

* [`localize_phonenumber`](https://hex.pm/packages/localize_phonenumber) — phone number parsing, validation, and formatting.

* [`localize_address`](https://hex.pm/packages/localize_address) — postal address formatting.

* [`intl`](https://hex.pm/packages/intl) — higher-level ergonomic API modeled on the JavaScript `Intl` object, layered on top of `Localize`.

When extending Localize, ask whether new functionality belongs in the core library or in one of these (or a new) companion package. Anything that requires non-CLDR data sources (e.g. Google libphonenumber, postal-address-data, person-name segmenters) belongs in a companion package, not in `Localize` itself.

## Where to ask

For questions about:

* **CLDR semantics** — read [Unicode TR35](https://www.unicode.org/reports/tr35/) (LDML).

* **Conformance gaps** — see `guides/conformance.md` for the implementation status matrix.

* **Performance** — see `guides/performance.md` for benchmarks and the Elixir-vs-NIF tradeoff.

* **Architecture** — see `guides/architecture.md` for the rationale behind the no-backend / runtime-loading design.

* **Migration from `ex_cldr`** — see `guides/migration.md`.
