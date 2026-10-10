# Self-hosting locale data

Localize downloads locale data as needed from a CDN at `https://elixir-localize.com`. Some deployments cannot depend on third-party hosting at build time, or must keep every build input inside their own infrastructure. This guide covers provisioning the data into your own application, verifying it, and serving it from your own CDN.

## Hosting the data is not the same as building it

Two different goals are easy to conflate, and only one of them is a supported path:

* **Hosting the data yourself** means serving the bytes Localize published, from your own infrastructure. This is fully supported, needs no rebuild, and is what the rest of this guide describes. The published files are byte-identical to what the hash manifest expects, so verification keeps working unchanged.

* **Building the data yourself** means running the locale-data generation pipeline against a CLDR checkout to produce your own ETF files. This is possible — see [Architecture](https://hexdocs.pm/localize/architecture.html) — but it is a much larger surface to maintain, and data built from a different CLDR tag will not match the bundled hashes. If your goal is simply to avoid the Localize CDN, you want the first option.

If you reached this guide because a rebuild produced different hashes, the answer is almost certainly to mirror the published bytes rather than to reproduce them.

## 1. Add the dependency

For a released version:

```elixir
{:localize, "~> 1.3"}
```

To track the development branch, a shallow clone is enough and avoids fetching the full history:

```elixir
{:localize, github: "elixir-localize/localize", branch: "main", depth: 1}
```

Mix's `:depth` option requires a `:branch`, a `:tag`, or a full 40-character `:ref`; a short ref is refused.

```bash
mix deps.get
```

## 2. Configure where the data lives — before downloading

Order matters here. The download target is whatever the configuration resolves to, so configuring after downloading puts the files somewhere you did not intend.

```elixir
config :localize,
  otp_app: :my_app,
  supported_locales: [:en, :fr, :de, :ja]
```

`otp_app: :my_app` is the part that matters. It resolves the cache to `Application.app_dir(:my_app, "priv/localize/locales")`, and because Mix symlinks an application's build-directory `priv` back to the project's own, downloaded files land in `my_app/priv/localize/locales/` where they can be committed to source control or cached by CI. Without it, the files go to Localize's own `priv` inside `_build` and are lost on `mix clean`.

`:supported_locales` bounds what gets downloaded. Omit it and the download task asks for confirmation before fetching all 657 locales.

Two further forms — `:otp_app` with a relative `:locale_cache_dir`, and an absolute `:locale_cache_dir` — are described under [Architecture](https://hexdocs.pm/localize/architecture.html). A relative `:locale_cache_dir` with no `:otp_app` anchor is refused at application start, because a path with no anchor resolves differently in a mix task, under `mix test`, and in a release.

## 3. Download the data

```bash
mix localize.download_locales
```

Every file is verified against the bundled SHA-256 manifest as it is written, so the cache only ever holds data that matches this release. Inflection data for the supported languages is fetched in the same step, so one command provisions both.

In CI or a Dockerfile, where there is no terminal to answer a prompt, add `--force`:

```bash
mix localize.download_locales --force
```

## 4. Verify the data

```bash
mix localize.verify_locales
```

With no argument the task checks the directory configured in step 2. Pass a path to check a different one. The report opens with the provenance of the manifest it is checking against:

```
Localize version:  1.4.0
CLDR version:      49.0.0
CLDR repo tag:     release-49-beta3
Reference CDN:     https://elixir-localize.com/locales/v49.0.0

657 file(s) in /path/to/my_app/priv/localize/locales
  657 verified
  0 mismatched
  0 not in manifest
0 of 657 manifest entries have no file here

All files verify against the bundled manifest.
```

Each file is reported as `ok`, `MISMATCH` (the locale is known but the bytes differ) or `NOT IN MANIFEST` (no entry exists for that locale). Manifest entries with no corresponding file are counted but not listed, because a cache holding only the locales an application configured is the normal case. The task exits non-zero on any mismatch, so it works as a build gate.

Verification covers locale data. Inflection data carries its own manifest and is verified on download, but is not part of this check.

## 5. Serve the data from your own CDN

Mirror the files downloaded in step 3, preserving the version segment in the path. Print the segments rather than hard-coding them:

```elixir
iex> Localize.Locale.Provider.version_segment()
"v49.0.0"

iex> Localize.Inflection.Provider.data_version()
"ae92d425e57a-r3"
```

A mirror must therefore serve the two trees at these paths:

```
https://cdn.example.com/locales/v49.0.0/fr.etf
https://cdn.example.com/inflection/ae92d425e57a-r3/ru.etf
```

Then point Localize at them:

```elixir
config :localize,
  otp_app: :my_app,
  supported_locales: [:en, :fr, :de, :ja],
  locale_base_url: "https://cdn.example.com/locales",
  inflection_base_url: "https://cdn.example.com/inflection",
  allow_runtime_locale_download: true
```

Downloads are verified against the bundled hash manifest regardless of where they came from, so a mirror serving the published bytes passes verification and a mirror serving anything else fails it.

### The CDN is only a fallback once the cache is populated

With step 3 done, a locale already in the cache is never fetched over the network. `:locale_base_url` matters only for a locale outside `:supported_locales`, and that fallback additionally needs `allow_runtime_locale_download: true`, which defaults to `false`. A deployment that pre-provisions every locale it uses can leave both keys unset and make no network call at all.

## The version segment tracks the data, not the package

`Localize.version/0` is not the Localize package version. It is the CLDR release version with Localize's own data patch counter as its patch component — `49.0.0` for CLDR 49 at patch 0 — and `version_segment/0` prefixes it with `v`. A mirror published under `v49.0.0` therefore keeps working across Localize package upgrades.

The segment moves only when the locale data itself is regenerated, which happens in two cases:

* The upstream CLDR release version changes, which resets the patch counter to zero.

* The data generation pipeline changes and the patch counter is bumped deliberately.

After upgrading Localize, re-check the segment rather than assuming it moved:

```bash
mix run -e 'IO.puts Localize.Locale.Provider.version_segment()'
```

`mix localize.verify_locales` prints the same value in its header, so one run after an upgrade shows whether anything needs re-mirroring. If the data did move and the mirror is stale, verification fails loudly rather than silently serving data from a different CLDR release.

## Why the hashes cannot be overridden

There is deliberately no configuration key to supply your own hash manifest, and none to disable verification.

The manifest does two jobs. The first is transport integrity: the bytes arrived as published. The second, and the more important one, is pinning the data to the *shape* that this release's accessors were written against. A locale file built from a different CLDR release can decode perfectly well and still be missing a key, or carry a restructured map, that a formatting call reaches only much later — surfacing as an unexplained `nil` or a `Localize.ItemNotFoundError` thrown from somewhere unrelated to the data.

A user-supplied manifest authenticates whatever happens to be on disk, which removes exactly that guarantee. Mirroring the published bytes keeps it, costs nothing extra, and is why this guide treats mirroring rather than rebuilding as the supported path for self-hosting.

## A build-time recipe

Provisioning and verification in a Dockerfile or CI job, after configuration is in place:

```dockerfile
RUN mix localize.download_locales --force
RUN mix localize.verify_locales --quiet
```

`--quiet` reports only failures and the summary. The second step is what turns a corrupted cache, a stale mirror, or data from the wrong CLDR release into a failed build rather than a runtime error in production.
