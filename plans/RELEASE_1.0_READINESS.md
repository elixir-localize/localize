# Localize 1.0 Readiness

Updated: July 22, 2026, after the full 1.0.0-rc.0 release review. This document lists only what stands between the current state and the 1.0.0 final release. The full historical assessments (July 4 baseline audit, July 15 fresh assessment, per-item verification notes) live in the git history of this file and of `RELEASE_1.0_READINESS_2026-07-15.md`.

## Outstanding blockers for 1.0.0

**None blocking a further RC.** The July 4 / July 15 plan items are done and verified (TR35 conformance, packaging/security, API freeze, deprecated-delegate removal, test-gap closures, rc.0 review). rc.0 through rc.4 are published.

During the rc.4 soak an external adopter (migrating from `ex_cldr`) reported a run of unit issues; see the triage below.

## RC-soak triage (issues #42–46)

* **Fixed in `main` (unreleased), landing in the next RC:** #42 (unit-symbol parsing of compound identifiers), #43 (times-compound formatting via a new `grammaticalFeatures.xml` derivation table), #44 (`define_unit/2` derived `base_unit` folding), plus two follow-ups found while adding ICU-differential property tests — per-compound `compound.per` localization and person-duration unit resolution. Changelog updated.
* **Open:** #45 — a *question* about the `convert/2` value-type contract (int → float, Decimal → Decimal); resolve by documenting the contract, not a blocker. #46 — SI-prefixed units without a precomposed CLDR pattern (`megajoule` → `"5 megajoule"` instead of `"5 MJ"`); a real display bug in the same compositional family as #43, small formatter fix. Fix before **1.0.0 final**; shippable-with-note in an interim RC.

## Remaining release steps (in order)

1. Publish the next RC with the #42–44 batch and the two follow-up fixes, after a standard release review.

2. Fix #46 (SI-prefix display composition) and document the #45 value-type contract.

3. Continue the soak; triage new reports here.

4. Publish **1.0.0 final — target August 1, 2026** — after a standard release review. Bump the README install snippet from the pre-release requirement form to `{:localize, "~> 1.0"}` as part of this step.

## Post-1.0 backlog (explicitly not blockers)

* MF2: `u:dir` / `u:id` expression *options* and the WG-default bidi strategy (the `:isolate` deviation). Documented as exclusions in `guides/conformance.md`.

* Multi-`¤` currency patterns (`¤¤` ISO code, `¤¤¤` display name, `¤¤¤¤` narrow symbol) in the number formatter.

* Digital tokens (ISO 24165, e.g. BTC) — needs a digital-token identifier registry.

* `localize_mcp` version bump to track localize 1.0 (its examples runner is verified against 0.50).

## Scheduled: drop OTP 26 support on December 31st, 2026 (announced)

On or after 2026-12-31: remove `maybe_json_polyfill/0` from mix.exs; remove the three OTP 26 rows from the CI matrix; update the README supported-versions section to OTP 27+ and delete the json_polyfill consumer instructions; remove (or downgrade) the supervisor `ensure_json_module!` check; changelog entry. Until then the `only: [:dev, :test]` json_polyfill conditional stays so OTP 26 CI compiles warning-free. This coincides with the December 2026 outer bound that was announced for the deprecated-delegate removals (already removed in 1.0.0-rc.0).
