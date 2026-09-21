# TODO

Tracked implementation improvements that are not yet scheduled against a release.

## Locale downloader resilience

Every locale other than `en` and `und` is fetched at runtime from the CDN (Cloudflare R2, `https://elixir-localize.com/locales/v<version>/<locale>.etf`) by `Localize.Utils.Http` and verified by `Localize.Locale.Provider` against the bundled hash manifest. A transient CDN 500 on 2026-09-19 surfaced as a hard failure for a user, because the downloader treats any non-200 as final. R2 documents occasional internal errors that clients are expected to retry, so a single-attempt downloader will keep converting brief upstream blips into user-visible breakage.

* **Retry transient failures with backoff.** `get_with_headers/2` makes exactly one attempt: a non-200 is logged as `Failed to download <url>. HTTP Error: (<code>)` and returned as `{:error, code}`. Retry 5xx responses, connection failures, and timeouts a small number of times with exponential backoff and jitter, leaving the existing single-attempt behaviour available for callers that want it.

* **Classify errors as retryable or final.** A 404 means the object is genuinely absent for that version and must fail immediately, while 500, 502, 503, 504 and connection errors should be retried. Retrying a 404 wastes time on the common misconfiguration of a version prefix that was never uploaded.

* **Keep conditional requests working.** The downloader already handles a `304` response as `{:not_modified, headers}`, and the CDN sends both `etag` and `cache-control: public, max-age=3600`. Any retry layer must preserve that path rather than turning a conditional request into an unconditional one.

* **Distinguish network failure from integrity failure in the error surface.** A download that fails to arrive and a download that arrives corrupt are different operational problems, and `LocaleIntegrityError` should remain clearly separable from a transport error so an operator can tell a CDN outage from a stale manifest.

* **Reconsider the IPv6-first connection strategy.** `get_with_headers/2` sets `:inet6fb4`, so `:httpc` attempts IPv6 before falling back to IPv4. The apex publishes AAAA records, and a host that advertises IPv6 without a working route will stall on connect before falling back. Consider making the family configurable, or preferring a happy-eyeballs style race, so a broken IPv6 path costs milliseconds rather than a connect timeout.

* **Consider a bounded number of parallel downloads with shared retry state.** `mix localize.download_locales` fetches many locales in sequence; a CDN blip part-way through currently abandons the run rather than retrying just the affected objects.

### Related operational work, outside this library

The library-side retry reduces user impact but does not detect an outage. The companion work lives in the `elixir-localize` repository and the Cloudflare account: enable Workers observability on the `localize-blog` Worker so a 500 is recorded with its exception, and add an external uptime check that fetches a real locale object rather than the site homepage, from outside Cloudflare so it does not share fate with the thing it monitors.
