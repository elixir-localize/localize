# TODO

Outstanding work on Localize. The design detail behind these items lives under [plans/](plans/); the shipped history is in [CHANGELOG.md](CHANGELOG.md), and the release standing is in [STATUS.md](STATUS.md).

## Open

* [ ] **Audit `cldr-49`-only code for map-order dependence** — the 2026-09-26 audit covered `main`. [plans/map-order.md](plans/map-order.md).

* [ ] **Report the cldr-json `scope="core"` defect upstream** — plan item 16a: cldr-json collapses display names marked `scope="core"`, so they never reach the pipeline. To report rather than work around. [plans/cldr-49.md](plans/cldr-49.md).

* [ ] **Decide whether root's `arab` and `arabext` blocks become a pipeline source** — plan item 38: CLDR JSON does not carry them, so `en-u-nu-arab` formats with the locale's `latn` symbols until `common/main/root.xml` is read directly.

## In progress

* [ ] **CLDR 49 upgrade** — the plan's items are closed bar those listed here; what remains is the beta refresh below. Work lives on the `cldr-49` branch, which does not merge to `main` until the final beta. [plans/cldr-49.md](plans/cldr-49.md).

## Blocked

* [ ] **Refresh to CLDR 49 beta1 and re-run the conformance suites** — blocked on the CLDR 49 beta1 release, expected 2026-10. The next drop is beta1, not alpha3: the newest tag is `release-49-alpha2` and "CLDRModify for beta1" landed on CLDR `main` on 2026-09-17. The refresh also picks up the new AED, MVR and OMR currency signs with no code change.

* [ ] **Interval patterns inherited from a different locale level than the single date** — plan item 35: whether to glue or keep the inherited pattern. Blocked on CLDR-14207.

## Deferred

* [ ] **Recheck map-order selections that only today's data keeps deterministic** — seven lookups walk a map and never see two candidates in the current CLDR data; recheck them whenever it is regenerated. [plans/map-order.md](plans/map-order.md).

* [ ] **`localize_emoji` sibling library** — plan item 11, a separate package on its own schedule. A Phoenix LiveView picker (`localize_emoji_live`) is out of scope for its 0.1.0.

## Done

* [x] **Selections that followed map order** — a territory's primary currency, shared narrow currency symbols, the parser's longest and fuzzy matches, territory-name lookup and a locale's number-system order no longer depend on map order. [plans/map-order.md](plans/map-order.md). 2026-09-26, v1.4.0.

* [x] **Pattern fields at a width TR35 does not list format as U+FFFD** — `dddd`, `MMMMMM`, `HHH` and the rest follow TR35's Handling Invalid Patterns instead of ICU's padding and clamping; an undefined letter stays an error. 2026-09-25, v1.4.0.

* [x] **Locale downloads retry transient CDN failures** — server errors, timeouts and dropped connections are retried with backoff and jitter, a 404 fails at once, and the address family is configurable. Details in [plans/locale-downloader-resilience.md](plans/locale-downloader-resilience.md). 2026-09-24, v1.4.0.

* [x] **Numeric date and time separators** — `Localize.DateTime.numeric_separators/2`, plus `:numeric_date_separator` and `:numeric_time_separator` on `Localize.Date`, `Localize.Time`, `Localize.DateTime` and `Localize.Interval`. 2026-09-20.

* [x] **Ordinal days (`ddd`) reviewed against the committed CLDR spec** — conforms on every normative point, and ships as a technical preview while CLDR's spec is pre-beta. 2026-09-20.

* [x] **Variant currency symbols** — `Localize.Currency.variant_symbol` and `currency_symbol: :variant`, which pick up the new Unicode 18 currency signs at the next data refresh. 2026-09-20.

* [x] **Public functions return errors instead of raising on wrong-type input** — plan item 41, swept across the public API. 2026-09-20.
