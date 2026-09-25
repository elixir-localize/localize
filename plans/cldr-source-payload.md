# CLDR source payload

**Status:** in progress, 2026-09-25

Decided 2026-09-25: Localize no longer carries CLDR sources in its working tree. The generation pipeline reads the cldr-json release bundle (`CLDR_PRODUCTION`) and the CLDR repository (`CLDR_REPO`) where they sit, and nothing is copied into `priv/cldr` any more. Which cldr-json release and which CLDR ref the committed data was generated from is recorded in the repository, the way `data/inflection` is pinned by `priv/localize/localize_inflection_sha`, and the generated ETFs stay verified by the tracked hash manifest.

## Why

`priv/cldr` held 554 MB of build input across 24,787 files. It is never shipped — `package.files` does not list it — and nothing under `lib/` reads it. `main` tracks it and `cldr-49` ignores it, and it is the only path where the two branches collide: checking out `main` overwrites the ignored copy and checking `cldr-49` out again deletes it, so every visit to `main` meant moving the sources aside and restoring them.

None of it is original. On 2026-09-25 all 24,787 files were byte-identical to the files they were copied from — the cldr-json `49.0.0-BETA1` bundle and the CLDR repository at `release-49-beta1` — and the bundle held no locale file the copy lacked. Reading the upstream files in place therefore generates the same data without a second copy of them.

## Corrections to the first analysis

* **A fresh checkout does need the sources, as things stood.** The first draft of this plan said the test suite did not, from a run with `priv/cldr` renamed aside — but all 657 locale ETFs were already generated on that machine. In `:dev` and `:test`, `Localize.Locale.Provider.PersistentTerm` generates any locale missing from the cache from the sources, `test_helper.exs` pre-downloads only 43 locales, and the conformance suites alone reach 17 more. Without the sources that path has to fall back to the CDN, as production does.

* **The repository is not carrying 500 MB.** `git count-objects -vH` reports `size-pack: 42.63 MiB` for the whole object store, including all of `main`'s tracked history for this path — CLDR JSON compresses roughly 13:1. Rewriting history is not warranted.

* **`upload-locales.yml` cannot work without the sources in the checkout.** It runs checkout → compile → `mix localize.generate_locales` with no step that produces them. It succeeds on `main` only because they are tracked there, and only has to generate when the data version is new to the CDN.

## Design

* **The pipeline reads in place.** Locale JSON, supplemental JSON and the RBNF rule files come from the bundle; supplemental, bcp47, validity, collation and subdivision XML, `FractionalUCA.txt` and `Script_Metadata.csv` come from the repository. A locale's JSON files are merged in the order the copy step produced — sorted by `<package>__<file>` — so the output is unchanged.

* **The pairing is recorded and checked.** `priv/localize/cldr_json_version` names the cldr-json release and `priv/localize/cldr_repo_ref` the CLDR tag or commit. cldr-json re-spins a release under a new name (`48.2.0-BETA0b`) and publishes packaging-only patches such as 48.2.1 that CLDR never tags, so neither can be derived from the other. Generation refuses a bundle or checkout that disagrees with them unless it is the run that records new ones.

* **CLDR's conformance fixtures are still copied** into `test/support/data`, where they are tracked and, for two files, curated.

* **`:dev` and `:test` generate a locale only when the sources are present,** and otherwise download it as production does, so a checkout without them — CI, or a machine that has never fetched them — still runs.

* **The test helper repairs its own locales.** A locale ETF that fails the manifest, which is what running `main`'s tests leaves behind, is regenerated from the sources when they are present.

* **`mix localize.fetch_sources` fetches the pinned pair**: the release zip from cldr-json, and the repository paths the pipeline reads at the pinned ref. `upload-locales.yml` runs it before `generate_locales`.

## Why not cache the pipeline in CI

The obvious alternative is to build the data in CI and cache it, on the reasoning that CLDR changes twice a year so a cache would almost always hit. The opposite is true: GitHub Actions evicts cache entries after seven days without access, so a job that runs twice a year finds a cold cache essentially every time and pays the slow path anyway. Building also needs JDK 21, Maven and a clone of `unicode-org/cldr`. Fetching the published artefact needs none of that; `scripts/build_cldr_production_data` stays as the escape hatch for a CLDR commit that has no published release yet.

## Tasks

* [ ] **Untrack `priv/cldr` on `main`** — the merge of `cldr-49` does this, since that branch removed it in `371d1f33`. Until then `main` still writes it on checkout and removes it again on the way back, which touches nothing `cldr-49` uses.

### Done

* [x] **Read the sources in place** — every read of `priv/cldr` now reads the bundle or repository path its copy came from; `mix localize.copy_sources` became `mix localize.prepare_sources`, which records the sources and still copies the fixtures. 2026-09-25.

* [x] **Prove the output unchanged** — with `priv/cldr` moved aside, the supplemental data, collation table and validity data regenerated byte-identical, and all 657 locales regenerated to a hash manifest identical to the tracked one. 2026-09-25.

* [x] **Record and check the pairing** — `priv/localize/cldr_json_version` (`49.0.0-BETA1`) and `priv/localize/cldr_repo_ref` (`release-49-beta1`); both generate tasks refuse other sources. 2026-09-25.

* [x] **Fall back to the CDN without sources** in `:dev` and `:test`, and let the test helper regenerate a stale test locale — verified by putting `main`'s published 48.2.2 `de` and `fr` into the cache: they were regenerated byte-identical and the tests passed. 2026-09-25.

* [x] **Add `mix localize.fetch_sources`** — from empty directories it fetched the release zip (identical to the local bundle) and a sparse checkout of the tag in under a minute, and generated a spread of locales byte-identical to the committed ones; `upload-locales.yml` runs it before `generate_locales`. 2026-09-25.

* [x] **Correct the documentation** that described copying the sources: `CLDR_UPDATE_INTEGRATION.md`, `.gitignore`, the task docs and the guides. 2026-09-25.
