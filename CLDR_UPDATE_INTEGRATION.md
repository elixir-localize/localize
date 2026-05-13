# CLDR Data Management

This document describes the CLDR data ingestion pipeline used by Localize: how to update to a new Unicode CLDR release, and how to ship a patch revision of Localize's data within the same CLDR release.

CLDR data drives all locale-aware formatting, validation, and display functions. At runtime Localize reads only from `priv/localize/` (compiled ETF) and `priv/unicode/` (Unicode Character Database tables). The raw CLDR sources in `priv/cldr/` are build-time inputs and are not included in Hex packages.

## Directory layout

```
priv/
├── cldr/                          # Build-time source data (JSON, XML, CSV)
│   ├── bcp47/                     # BCP 47 extension key definitions (XML)
│   ├── collation/                 # Collation tailoring (XML) + FractionalUCA.txt
│   ├── external_sources/          # Script_Metadata.csv, iso_currencies.xml
│   ├── locales/<locale>/          # Per-locale JSON from CLDR production data
│   ├── supplemental_data/         # Supplemental JSON and XML
│   └── validity/                  # Validity XML for subtag validation
│
├── localize/                      # Runtime data (ETF)
│   ├── locales/<locale>.etf       # Per-locale compiled data
│   ├── supplemental_data/*.etf    # Supplemental compiled data
│   ├── validity/*.etf             # Validity compiled data
│   ├── all_locale_names.etf
│   ├── collation_table.etf
│   ├── known_territories.etf
│   ├── unicode_script_to_subtag_mapping.etf
│   ├── version                    # CLDR version (e.g. "48.2")
│   └── localize_patch_version     # "{cldr_version}:{patch}" (e.g. "48.2:1")
│
├── unicode/                       # Unicode Character Database tables
│   ├── combining_class.txt
│   └── general_category.txt
│
data/
├── data.ex                        # Pipeline entry points (Localize.Data.*)
├── locale.ex                      # Per-locale generation
├── locale_transformer.ex          # Struct transforms applied during generation
├── supplemental.ex                # Supplemental generation
├── validity.ex                    # Validity generation
├── collation.ex                   # Collation extraction
├── plural_rules.ex                # Plural rule parser
├── script_metadata.ex             # Script metadata loader
├── unicode_data.ex                # UCD table builders
├── xml_extractors.ex              # SweetXml helpers
├── normalize/                     # JSON normalizers per CLDR domain
└── mix/tasks/                     # Mix tasks (see below)

scripts/
├── ldml2json                      # Wrapper around CLDR's Ldml2JsonConverter
└── ldml2json_v2                   # v2 wrapper
```

`priv/cldr/` is gitignored (it is large and reproducible from upstream) except for a small number of essential files. `priv/localize/locales/*.etf` is gitignored except for `en.etf` (needed for tests). `priv/localize/supplemental_data/`, `priv/localize/validity/`, and the top-level ETF files in `priv/localize/` are committed.

## Prerequisites

Two external sources must be available on disk:

* **CLDR production data** — the pre-built JSON locale files from a CLDR release. Point `CLDR_PRODUCTION_DATA` at the directory, or place it at `../cldr_production_data`.

* **CLDR repository** — a checkout of `github.com/unicode-org/cldr` at the matching release tag. Used for XML sources (supplemental, collation, validity, BCP 47). Point `CLDR_REPO` at it, or place it at `../cldr_repo`.

| Variable | Description | Default |
|----------|-------------|---------|
| `CLDR_PRODUCTION_DATA` | Path to CLDR production data directory | `../cldr_production_data` |
| `CLDR_REPO` | Path to Unicode CLDR repository checkout | `../cldr_repo` |
| `R2_ACCOUNT_ID` | Cloudflare R2 account ID (upload only) | — |
| `R2_ACCESS_KEY_ID` | Cloudflare R2 access key (upload only) | — |
| `R2_SECRET_ACCESS_KEY` | Cloudflare R2 secret key (upload only) | — |
| `R2_BUCKET` | Cloudflare R2 bucket name (upload only) | — |

## Mix tasks

| Task | Description |
|------|-------------|
| `mix localize.copy_sources` | Copies raw CLDR source files into `priv/cldr/` and writes the CLDR version to `priv/localize/version`. Supports `--supplemental` and `--locales` to copy subsets. |
| `mix localize.generate_supplemental` | Generates supplemental, validity, and top-level ETF files in `priv/localize/`. |
| `mix localize.generate_locales` | Generates per-locale ETF files in `priv/localize/locales/`. Pass locale names as positional arguments to generate a subset (e.g. `mix localize.generate_locales en fr de`). |
| `mix localize.bump_patch_version` | Increments the Localize-side patch counter in `priv/localize/localize_patch_version`. Auto-resets to `0` when the CLDR version changes; the first bump after a CLDR upgrade goes `0 → 1`. |
| `mix localize.download_iso_currencies` | Downloads ISO 4217 currency codes from SIX Group into `priv/cldr/external_sources/iso_currencies.xml`. |
| `mix localize.download_unicode_data` | Downloads UCD `DerivedCombiningClass.txt` and `DerivedGeneralCategory.txt` into `priv/unicode/`. |
| `mix localize.upload_locale` | Generates one or more locales and uploads them to Cloudflare R2. Requires `--version` and the R2 environment variables above. |

## Data flow

```
   CLDR production data (JSON)        CLDR repository (XML)
              │                               │
              └──────────────┬────────────────┘
                             ▼
                  mix localize.copy_sources
                             │
                             ▼
                  priv/cldr/ (source files)
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
mix localize.        mix localize.        UCD downloads /
generate_            generate_locales     SIX downloads
supplemental                              (priv/unicode/,
        │                    │             priv/cldr/external_sources/)
        ▼                    ▼
priv/localize/        priv/localize/
  supplemental_data/    locales/<locale>.etf
  validity/
  *.etf (top-level)
```

## Updating to a new CLDR release

1. **Update upstream sources.** Check out the desired release tag in `$CLDR_REPO`, and refresh `$CLDR_PRODUCTION_DATA` with the matching production-data archive.

2. **Copy sources into the project.**

   ```bash
   mix localize.copy_sources
   ```

   This writes the new CLDR version string to `priv/localize/version`. Because the version changed, the patch counter in `priv/localize/localize_patch_version` automatically resets to `0` on the next generation. You can scope the copy with `--supplemental` or `--locales`.

3. **Regenerate supplemental data.**

   ```bash
   mix localize.generate_supplemental
   ```

   Reads `priv/cldr/supplemental_data/`, `priv/cldr/validity/`, `priv/cldr/bcp47/`, and `priv/cldr/collation/` and writes ETF files under `priv/localize/`.

4. **Regenerate locale data.**

   ```bash
   mix localize.generate_locales         # all locales
   mix localize.generate_locales en fr   # specific locales
   ```

   Reads `priv/cldr/locales/<locale>/` and writes `priv/localize/locales/<locale>.etf`. Each locale ETF contains pre-built structs for number symbols, number formats, currency data, etc. (see `Localize.Data.LocaleTransformer`), eliminating runtime struct construction.

5. **Refresh auxiliary downloads if upstream has moved.**

   ```bash
   mix localize.download_unicode_data       # UCD tables for collation
   mix localize.download_iso_currencies     # ISO 4217 currency list
   ```

   These have their own release cadences independent of CLDR. Run them when their upstream sources publish a new version, not on every CLDR upgrade.

6. **Verify.**

   ```bash
   mix test
   mix dialyzer
   ```

   Investigate test failures before continuing — they typically indicate that the new CLDR release changed a data shape that the normalizers or transformers need to accommodate.

## Patch releases against the same CLDR data

The patch counter in `priv/localize/localize_patch_version` tracks Localize-side changes to the data pipeline (new normalizers, struct transforms, extra fields, bug fixes in extraction) within a single CLDR release. It is stored as `"{cldr_version}:{patch}"` (for example `"48.2:1"`) so an old patch file is unambiguously associated with its CLDR release.

The counter is **not** bumped automatically by `mix localize.generate_locales` — generation can therefore run unattended in CI without producing phantom version bumps.

Typical workflow when changing the pipeline without changing the upstream CLDR version:

1. Make the pipeline change (e.g. extend `Localize.Data.LocaleTransformer` to pre-compute a new struct field, fix a normalizer in `data/normalize/`, etc.).

2. Bump the patch counter:

   ```bash
   mix localize.bump_patch_version
   ```

3. Regenerate the affected data:

   ```bash
   mix localize.generate_supplemental   # if supplemental shape changed
   mix localize.generate_locales        # if locale shape changed
   ```

4. Verify:

   ```bash
   mix test
   mix dialyzer
   ```

5. Commit the regenerated ETF files alongside the pipeline change. Consumers that fetch locale data from R2 will pick up the new patch version on next refresh; the version string they see is `{cldr_version}:{patch}` (e.g. `48.2:2`).

When the upstream CLDR version next changes (step 2 of the CLDR-upgrade workflow above writes a new value to `priv/localize/version`), the patch counter automatically resets to `0`, and the first `mix localize.bump_patch_version` after the upgrade takes it from `0` to `1`.

## Uploading to Cloudflare R2

For distribution of large locale ETF files outside the Hex package:

```bash
export R2_ACCOUNT_ID=…
export R2_ACCESS_KEY_ID=…
export R2_SECRET_ACCESS_KEY=…
export R2_BUCKET=…

mix localize.upload_locale --version 48 en fr de
```

The uploaded object key is `<version>/<locale>.etf`. `--bucket` overrides `R2_BUCKET`; `--version` is required (it is the path prefix used in R2, not the patch version).
