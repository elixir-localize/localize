# CLDR source payload

**Status:** in progress, 2026-09-30

Decided 2026-09-25: Localize no longer carries CLDR sources in its working tree. The generation pipeline reads its sources where they sit, and nothing is copied into `priv/cldr` any more. The CLDR ref the committed data was generated from is recorded in the repository, the way `data/inflection` is pinned by `priv/localize/localize_inflection_sha`, and the generated ETFs stay verified by the tracked hash manifest.

Decided 2026-09-30: the CLDR JSON is built by us, from the CLDR repository at the pinned ref, with CLDR's own converter run with `fullnumbers`, instead of being taken from cldr-json's published release. cldr-json runs the converter without that option, so a locale's symbols and formats for numbering systems other than Latin digits and its own default, native, traditional and finance systems are left out, and cldr-json will not change that (user: "We will need to take back control of json conversion and do it ourselves (pinned at the right commit)"). The JSON is generated, never committed: "We do NOT want to vendor CLDR data."

## Why

`priv/cldr` held 554 MB of build input across 24,787 files. It was never shipped — `package.files` does not list it — and nothing under `lib/` reads it. `main` tracked it and `cldr-49` ignored it, and it was the only path where the two branches collided: checking out `main` overwrote the ignored copy and checking `cldr-49` out again deleted it, so every visit to `main` meant moving the sources aside and restoring them.

None of it was original. On 2026-09-25 all 24,787 files were byte-identical to the files they were copied from — the cldr-json `49.0.0-BETA1` bundle and the CLDR repository at `release-49-beta1` — and the bundle held no locale file the copy lacked. Reading the upstream files in place therefore generates the same data without a second copy of them.

## Corrections to the first analysis

* **A fresh checkout does need the sources, as things stood.** The first draft of this plan said the test suite did not, from a run with `priv/cldr` renamed aside — but all 657 locale ETFs were already generated on that machine. In `:dev` and `:test`, `Localize.Locale.Provider.PersistentTerm` generates any locale missing from the cache from the sources, `test_helper.exs` pre-downloads only 43 locales, and the conformance suites alone reach 17 more. Without the sources that path has to fall back to the CDN, as production does.

* **The repository is not carrying 500 MB.** `git count-objects -vH` reports `size-pack: 42.63 MiB` for the whole object store, including all of `main`'s tracked history for this path — CLDR JSON compresses roughly 13:1. Rewriting history is not warranted.

* **`upload-locales.yml` cannot work without the sources in the checkout.** It runs checkout → compile → `mix localize.generate_locales` with no step that produces them, so it has to fetch them first.

## Design

* **The pipeline reads in place.** Locale JSON, supplemental JSON and the RBNF rule files come from the JSON in `CLDR_PRODUCTION`; supplemental, bcp47, validity, collation and subdivision XML, `FractionalUCA.txt` and `Script_Metadata.csv` come from the repository in `CLDR_REPO`. A locale's JSON files are merged sorted by `<package>__<file>`, the order the old copy step produced, so the output did not change.

* **The JSON is built from the repository** by `mix localize.build_cldr_json` (`Localize.Data.CldrJson`): Maven runs CLDR's `GenerateProductionData` into a temporary directory and `Ldml2JsonConverter` over it, for the `main`, `supplemental` and `rbnf` types, with the options cldr-json's driver passes plus `-n true`. Run with cldr-json's options, the build reproduced all 19 of those packages of the published `49.0.0-BETA1` byte for byte from `release-49-beta1`.

* **Only the ref is recorded.** `priv/localize/cldr_repo_ref` names the CLDR tag or commit. The JSON carries a stamp, `localize_build.txt`, naming the commit it was built from and the options, and generation refuses a repository at another ref or JSON whose stamp does not match the repository and the current options. The JSON and the XML come from one checkout, so they cannot come from different releases; the `cldr_json_version` pin and the check that a pre-release bundle sat beside its tag are gone with the bundle.

* **Every numbering system's data is kept only where it differs.** With `fullnumbers` each locale's resolved JSON carries every numbering system, most of it the locale's `latn` data repeated through root's aliases: `numbers.json` grows from 5 MB to 314 MB across the 657 locales. The number normalizer keeps a system outside the locale's own only where a kind of data differs from its `latn` — 3,102 blocks at `release-49-beta1`: 2,109 are root's `arab` and `arabext` data resolved in each locale, and 993 are 25 locales' own data for other systems. So root's `arab` and `arabext` data no longer has to be read from `root.xml`, and at runtime a system without data takes the locale's `latn`.

* **CLDR's conformance fixtures are still copied** into `test/support/data`, where they are tracked and, for two files, curated.

* **`:dev` and `:test` generate a locale only when the sources are present,** and otherwise download it as production does, so a checkout without them still runs.

* **The test helper repairs its own locales.** A locale ETF that fails the manifest is regenerated from the sources when they are present.

* **`mix localize.fetch_sources` fetches and builds the pinned sources**: a sparse, blobless checkout of the repository at the pinned ref (the data, the keyboard, seed and exemplar data CLDR's tools open beside it, and the tools themselves), then the JSON built from it, for a machine that has never had them.

## Publishing from the maintainer's machine

This plan first ruled out building the data in CI: GitHub Actions evicts a cache after seven days without access, so a cache of a build that runs twice a year is always cold, and building needs JDK 21, Maven and a clone of `unicode-org/cldr` where downloading the published release needed none of that. Once building became the only way to get the data, CI building it was tried and measured, and it does not fit a runner:

* **The converter's memory grows with the files it has processed**, whatever the thread count: CLDR's XML loader caches up to 700 parsed sources, a hard-coded limit, across the 929 files of the `main` type. On 16 threads it peaked at 17 GB resident under the 16 GB heap cldr-json's driver uses and thrashed under 8 GB; on 4 threads, as on a runner, it thrashed under 6 GB before half way. A standard runner has 16 GB in all, and a cold build would take the best part of an hour besides.

* **The maintainer builds the JSON anyway.** The committed hash manifest is generated from the locales, so the data has been built and generated on the maintainer's machine before any push; building it again in CI only reproduced it.

So the maintainer publishes (user, 2026-09-30: "its ok that we manually generate the locale data on this machine and upload it to CDN from this machine rather than CI"). `mix localize.publish_locales` checks the sources and that every file matches the manifest, uploads the files to R2, purges their URLs from the Cloudflare cache, and records the manifest beside them; it refuses a data version the latest release tag carries. CI's `check-locales.yml` only confirms that R2 records the committed manifest before the tests download from it.

If CI publishing is wanted back, the converter can run the `main` type in several locale subsets (`-m`), one JVM each, which bounds the cache; the only files a subset changes are `cldr-core`'s `availableLocales.json` and `defaultContent.json`, which the pipeline does not read.

## Tasks

* [ ] **Publish the CLDR 49 data** — run `mix localize.publish_locales` on the maintainer's machine with the R2 and Cloudflare credentials, then push; until then CI's check fails, since R2 records no manifest for `v49.0.0`.

### Done

* [x] **Build the CLDR JSON ourselves** — `mix localize.build_cldr_json` with `fullnumbers`, the stamp, `fetch_sources` and `prepare_sources` building from the repository, the `cldr_json_version` pin and `scripts/build_cldr_production_data` removed, and root's `arab` and `arabext` data taken from the JSON. 2026-09-30.

* [x] **Untrack `priv/cldr` on `main`** — done by the merge of `cldr-49`, which had removed it in `371d1f33`. 2026-09-28.

* [x] **Read the sources in place** — every read of `priv/cldr` now reads the bundle or repository path its copy came from; `mix localize.copy_sources` became `mix localize.prepare_sources`, which records the sources and still copies the fixtures. 2026-09-25.

* [x] **Prove the output unchanged** — with `priv/cldr` moved aside, the supplemental data, collation table and validity data regenerated byte-identical, and all 657 locales regenerated to a hash manifest identical to the tracked one. 2026-09-25.

* [x] **Record and check the pairing** — then a cldr-json release and a CLDR ref; since 2026-09-30 only the ref. 2026-09-25.

* [x] **Fall back to the CDN without sources** in `:dev` and `:test`, and let the test helper regenerate a stale test locale — verified by putting `main`'s published 48.2.2 `de` and `fr` into the cache: they were regenerated byte-identical and the tests passed. 2026-09-25.

* [x] **Add `mix localize.fetch_sources`** — from empty directories it fetched the release zip and a sparse checkout of the tag in under a minute; since 2026-09-30 it builds the JSON instead of downloading it. 2026-09-25.

* [x] **Correct the documentation** that described copying the sources: `CLDR_UPDATE_INTEGRATION.md`, `.gitignore`, the task docs and the guides. 2026-09-25.
