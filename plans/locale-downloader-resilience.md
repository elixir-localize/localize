# Locale downloader resilience

**Status:** implemented (v1.4.0), 2026-09-24

Every locale other than `en` and `und` is fetched at runtime from the CDN (Cloudflare R2, `https://elixir-localize.com/locales/v<version>/<locale>.etf`) by `Localize.Utils.Http` and verified by `Localize.Locale.Provider` against the bundled hash manifest. A transient CDN 500 on 2026-09-19 surfaced as a hard failure for a user, because the downloader treated any non-200 as final. R2 documents occasional internal errors that clients are expected to retry, so a single-attempt downloader kept converting brief upstream blips into user-visible breakage.

`Localize.Utils.Http.get_with_headers/2` now retries, and every download goes through it: locale data and the hash tooling. The retry decision lives in `request_with_retries/5`, the classification in `retryable?/1`, and a local scripted server (`test/support/scripted_http_server.ex`) drives the tests end to end.

## Tasks

### Done

* [x] **Retry transient failures with backoff** — a retried failure waits `:retry_delay` (500 ms by default) doubled per attempt, capped at 8 s, plus up to one base delay of jitter, for up to `:retries` (3) retries. `retries: 0` keeps the single attempt. Each retried failure logs a warning and the last an error.

* [x] **Classify errors as retryable or final** — 408, 429, 500, 502, 503 and 504, request and connection timeouts, dropped connections and failed connects are retried; a 404 or any other status, an unknown host and an oversized body fail at once.

* [x] **Keep conditional requests working** — a retry resends the same request, headers included, so an `if-none-match` survives it, and a `304` is an outcome rather than a failure. Tested with a 503 followed by a 304.

* [x] **Distinguish network failure from integrity failure** — they were already separate: a transport failure is a `Localize.LocaleDownloadError` carrying its reason and HTTP status, a bad download a `Localize.LocaleIntegrityError`. A test now shows an outage that outlasts the retries staying a download error.

* [x] **Reconsider the IPv6-first connection strategy** — `:ip_family` (per call) and `config :localize, :http_ip_family` choose `:inet6fb4`, `:inet` or `:inet6`. `:httpc` has no happy-eyeballs race, so pinning `:inet` is the remedy for a host with a broken IPv6 route; `:inet6fb4` stays the default. The connect-failure handling now reads the last attempt of either shape `:httpc` reports.

### Deferred

* [ ] **A bounded number of parallel downloads with shared retry state** — `mix localize.download_locales` already continues past a failed locale and reports it, and a blip is now retried in place, so the run no longer loses objects to one. Parallel workers would multiply the load on a CDN that is already failing and would need a shared breaker to avoid that; revisit if download time for `--all` becomes a complaint.

## Related operational work, outside this library

The library-side retry reduces user impact but does not detect an outage. The companion work lives in the `elixir-localize` repository and the Cloudflare account: enable Workers observability on the `localize-blog` Worker so a 500 is recorded with its exception, and add an external uptime check that fetches a real locale object rather than the site homepage, from outside Cloudflare so it does not share fate with the thing it monitors.
