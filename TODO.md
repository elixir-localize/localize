# TODO

Outstanding work on Localize. The design detail behind these items lives under [plans/](plans/); the shipped history is in [CHANGELOG.md](CHANGELOG.md), and the release standing is in [STATUS.md](STATUS.md).

## Open

* [ ] **Make the locale downloader resilient to transient CDN failures** — `Localize.Utils.Http` treats any non-200 as final, so a CDN 500 on 2026-09-19 became a hard failure for a user. Needs retry with backoff, retryable-versus-final classification, and a look at the IPv6-first connect. Analysis in [plans/locale-downloader-resilience.md](plans/locale-downloader-resilience.md).

* [ ] **Stop carrying the 554 MB CLDR source payload in the working tree** — 96% of it is JSON that `unicode-org/cldr-json` already publishes as an 80 MB release asset, and `main` tracking it while `cldr-49` ignores it is what makes switching between them error-prone. Analysis in [plans/cldr-source-payload.md](plans/cldr-source-payload.md).

* [ ] **Decide what `dddd` means before 1.4.0 ships** — CLDR 49 gives `ddd` the ordinal day, but `dddd` still renders a zero-padded day ("0006") under the pre-49 numeric rule, and TR35 hints that a future `wide` `dayOfMonth` width may claim it. Settling it after release would be a breaking change.

* [ ] **Report the cldr-json `scope="core"` defect upstream** — plan item 16a: cldr-json collapses display names marked `scope="core"`, so they never reach the pipeline. To report rather than work around. [plans/cldr-49.md](plans/cldr-49.md).

* [ ] **Decide whether root's `arab` and `arabext` blocks become a pipeline source** — plan item 38: CLDR JSON does not carry them, so `en-u-nu-arab` formats with the locale's `latn` symbols until `common/main/root.xml` is read directly.

## In progress

* [ ] **CLDR 49 upgrade** — the plan's items are closed bar those listed here; what remains is the beta refresh below and the `dddd` decision above. Work lives on the `cldr-49` branch, which does not merge to `main` until the final beta. [plans/cldr-49.md](plans/cldr-49.md).

## Blocked

* [ ] **Refresh to CLDR 49 beta1 and re-run the conformance suites** — blocked on the CLDR 49 beta1 release, expected 2026-10. The next drop is beta1, not alpha3: the newest tag is `release-49-alpha2` and "CLDRModify for beta1" landed on CLDR `main` on 2026-09-17. The refresh also picks up the new AED, MVR and OMR currency signs with no code change.

* [ ] **Interval patterns inherited from a different locale level than the single date** — plan item 35: whether to glue or keep the inherited pattern. Blocked on CLDR-14207.

## Deferred

* [ ] **`localize_emoji` sibling library** — plan item 11, a separate package on its own schedule. A Phoenix LiveView picker (`localize_emoji_live`) is out of scope for its 0.1.0.

## Done

* [x] **Numeric date and time separators** — `Localize.DateTime.numeric_separators/2`, plus `:numeric_date_separator` and `:numeric_time_separator` on `Localize.Date`, `Localize.Time`, `Localize.DateTime` and `Localize.Interval`. 2026-09-20.

* [x] **Ordinal days (`ddd`) reviewed against the committed CLDR spec** — conforms on every normative point, and ships as a technical preview while CLDR's spec is pre-beta. 2026-09-20.

* [x] **Variant currency symbols** — `Localize.Currency.variant_symbol` and `currency_symbol: :variant`, which pick up the new Unicode 18 currency signs at the next data refresh. 2026-09-20.

* [x] **Public functions return errors instead of raising on wrong-type input** — plan item 41, swept across the public API. 2026-09-20.
