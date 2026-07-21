# Localize 1.0 Readiness

Updated: July 22, 2026, after the full 1.0.0-rc.0 release review. This document lists only what stands between the current state and the 1.0.0 final release. The full historical assessments (July 4 baseline audit, July 15 fresh assessment, per-item verification notes) live in the git history of this file and of `RELEASE_1.0_READINESS_2026-07-15.md`.

## Outstanding blockers for 1.0.0

**None.** Every item from the July 4 and July 15 plans is done and verified: TR35 conformance fixes, packaging and security items, the API freeze (renames, visibility, error shapes), the deprecated-delegate removal sweep, test-gap closures, and the rc.0 review (all six gates clean, `mix hex.build` verified, ~600 documentation examples execution-verified). There are no open GitHub issues.

## Remaining release steps (mechanical, in order)

1. Tag `v1.0.0-rc.0` and push the tag (the docs `source_ref` and the README source links expect it), then `mix hex.publish`.

2. Soak the RC. Any issue reported during the soak is triaged here; a fix ships as rc.1.

3. Publish **1.0.0 final — target August 1, 2026** — after a standard release review of whatever changed during the soak. Bump the README install snippet from the pre-release requirement `{:localize, "~> 1.0.0-rc.0"}` to `{:localize, "~> 1.0"}` as part of this step.

## Post-1.0 backlog (explicitly not blockers)

* MF2: `u:dir` / `u:id` expression *options* and the WG-default bidi strategy (the `:isolate` deviation). Documented as exclusions in `guides/conformance.md`.

* Multi-`¤` currency patterns (`¤¤` ISO code, `¤¤¤` display name, `¤¤¤¤` narrow symbol) in the number formatter.

* Digital tokens (ISO 24165, e.g. BTC) — needs a digital-token identifier registry.

* `localize_mcp` version bump to track localize 1.0 (its examples runner is verified against 0.50).

## Scheduled: drop OTP 26 support on December 31st, 2026 (announced)

On or after 2026-12-31: remove `maybe_json_polyfill/0` from mix.exs; remove the three OTP 26 rows from the CI matrix; update the README supported-versions section to OTP 27+ and delete the json_polyfill consumer instructions; remove (or downgrade) the supervisor `ensure_json_module!` check; changelog entry. Until then the `only: [:dev, :test]` json_polyfill conditional stays so OTP 26 CI compiles warning-free. This coincides with the December 2026 outer bound that was announced for the deprecated-delegate removals (already removed in 1.0.0-rc.0).
