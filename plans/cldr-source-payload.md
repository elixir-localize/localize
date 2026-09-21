# CLDR source payload

**Status:** planning, 2026-09-22

`priv/cldr` holds 554 MB of CLDR build input across 24,787 files. It is never shipped — `package.files` does not list it — and nothing under `lib/` reads it. `main` tracks it, `cldr-49` gitignores it, and that disagreement is what makes switching between the two branches slow and error-prone: git silently overwrites the ignored copy on the way in and deletes it on the way out, so the working branch's sources have to be moved aside by hand and restored afterwards. Losing them once already cost a rebuild.

## What the payload actually is

Measured on `cldr-49` at CLDR 49 alpha2, 2026-09-22.

| Part | Files | Size | Source |
|---|---|---|---|
| `locales/**/*.json` | 24,360 | **465.0 MB** | cldr-json release |
| `locales/**/subdivisions.xml` | 95 | 19.8 MB | CLDR repo `common/subdivisions` |
| `FractionalUCA.txt` | 1 | 5.3 MB | CLDR repo `common/uca` |
| `collation/` | — | 1.8 MB | CLDR repo `common/collation` |
| `supplemental_data/` | — | 1.5 MB | mixed |
| `bcp47`, `validity`, `Script_Metadata.csv` | — | 0.2 MB | CLDR repo |

So 465 MB — 96% of the apparent total — is JSON that upstream already publishes, and roughly 29 MB comes from the CLDR XML repository.

## Three things that were believed and are not true

* **The test suite does not need `priv/cldr`.** `.gitignore` says it does. Renaming the directory aside and running the suite gives 31,360 of 31,361 passing, and the single failure is `ReadmeLinksTest` reacting to the `1.4.0-dev` version bump. The three test files that mention `priv/cldr` do so only in comments, two of them noting that they run without it. The data is needed by the generation pipeline alone.

* **The repository is not carrying 500 MB.** `git count-objects -vH` reports `size-pack: 42.63 MiB` for the whole object store, including all of main's tracked history for this path — CLDR JSON compresses roughly 13:1. The cost is working-tree churn on checkout, not repository weight, so rewriting history is not warranted.

* **`upload-locales.yml` cannot work on `cldr-49`.** It runs checkout → compile → `mix localize.generate_locales` with no step that produces `priv/cldr`. It succeeds on `main` only because the sources are tracked there. This asymmetry, not the byte count, is the real defect.

## Why not cache the pipeline in CI

The obvious fix is to build the data in CI and cache it, on the reasoning that CLDR changes twice a year so a cache would almost always hit. The opposite is true: GitHub Actions evicts cache entries after seven days without access, so a job that runs twice a year finds a cold cache essentially every time and pays the slow path anyway. Building also needs JDK 21, Maven and a clone of `unicode-org/cldr`.

## Proposal — fetch the published artefact instead

`unicode-org/cldr-json` publishes the production data as a release asset, for pre-release versions as well as final: `cldr-49.0.0-ALPHA2-json-full.zip`, 80 MB. Its top level is exactly the 25 `cldr-*` packages that `Localize.Data.cldr_source_dir/0` expects, and the package set is identical to the locally built `cldr_production_data` — verified by diffing the two listings. Unzipping it and pointing `CLDR_PRODUCTION` at the result needs no adaptation.

That gives a clean split. The JSON is fetched on demand, by CI and by a developer restoring a checkout, keyed to the version already recorded in `priv/localize/version`. The remaining ~29 MB of XML is small enough to vendor and track on both branches, which removes the path from the branch-switch problem entirely. Caching becomes an optimisation rather than load-bearing, since a miss costs an 80 MB download rather than a 20-minute build.

`scripts/build_cldr_production_data` stays as the escape hatch for a CLDR commit that has no published release yet.

### Open questions

* The zip ships `cldr-subdivisions-full` as JSON while the pipeline reads subdivisions from the repository's XML. Moving to the JSON would cut the vendored footprint from ~29 MB to ~9 MB, but it is a behavioural change to the generated data and needs validating against the current output rather than assuming.

* `Localize.Data.generate_all/0` calls `derive_all_locale_names/0`, which lists the directory names under `priv/cldr/locales` without opening a file. `generate_supplemental` therefore needs the 657 directories to exist but none of their contents. Deriving that list from the vendored locale data instead would let the supplemental pipeline run with no JSON present at all.

* Whether the released zip is byte-identical to a local build from the same tag, which decides whether generated ETFs stay reproducible across the two routes. The hash manifest already provides the check.

## Tasks

* [ ] **Confirm the released zip reproduces the current ETFs.** Fetch `cldr-49.0.0-ALPHA2-json-full.zip`, run `copy_sources` and `generate_locales` from it, and verify every file against `priv/localize/locale_hashes.etf`. Nothing else proceeds until this passes.

* [ ] **Add a `mix localize.fetch_sources` task** that downloads and unpacks the release asset for the version in `priv/localize/version`, with a `CLDR_TAG` override, so CI and a developer restore take the same path.

* [ ] **Decide the subdivisions question** — keep the repo XML at ~29 MB vendored, or move to `cldr-subdivisions-full` and vendor ~9 MB.

* [ ] **Retire `derive_all_locale_names/0`'s directory walk** so the supplemental pipeline does not need the locales tree to exist.

* [ ] **Vendor the XML inputs** on both branches and narrow `.gitignore` to the fetched JSON alone, correcting the comment that claims the test suite needs the sources.

* [ ] **Untrack `priv/cldr` on `main`** once CI no longer depends on it being in the checkout, making both branches agree.

* [ ] **Add the fetch step to `upload-locales.yml`** ahead of `generate_locales`, which also makes the workflow usable on `cldr-49` for the first time.
