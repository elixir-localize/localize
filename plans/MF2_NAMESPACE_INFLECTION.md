# MF2 namespaces + `unicode_inflection` integration — plan

Date: July 24, 2026 (updated). **Post-1.0 work** — nothing here is a 1.0 blocker. Goal: add MessageFormat 2 function-namespace support to Localize and use the inflection engine behind namespaced MF2 inflection functions, and — optionally, when configured — as a morphological engine under `Localize.Unit.to_string/2`.

> **Direction update (Kip, July 24):** `unicode_inflection` is being **merged into Localize** in a separate session — it lands in-tree as `Localize.Inflection.*` (the supervisor already starts `Localize.Inflection.Data`, which owns the per-locale inflection dictionary ETS tables). So this is **not** an optional-dependency integration; the engine is part of Localize. The namespace + `Localize.Message` wiring below is deferred until that merge completes. Kip's namespace preference is the single letter **`l`** (with `u` aliases added later if the spec goes that way).

References:

* The "Unicode Inflection 0.2 Technical Preview" announcement doc (Google Docs, provided by Kip). **Not accessible to this investigation — auth-gated; only the doc shell loaded.** Its specifics on the proposed MF2 inflection function design must be confirmed with Kip before finalizing names/options (see Open questions).
* [unicode-org/inflection#202](https://github.com/unicode-org/inflection/issues/202) — the MF2 namespace question. **Open, unresolved.**
* MF2 spec: `~/Development/cldr/cldr_repo/docs/ldml/tr35-messageFormat.md`.

## Ground truth

### The inflection engine (from `unicode_inflection` v0.1.0, merging in-tree as `Localize.Inflection.*`)

The API facts below are from the standalone `unicode_inflection` library; as it merges into Localize the module prefix becomes `Localize.Inflection.*` and the "separate dependency / not published" concerns fall away (the engine, and its lazy per-locale ETS/persistent_term data layer, become part of Localize). What carries over unchanged: the function shapes, the string-valued options, the locale handling, and the ~41 MB data bundle that must be installed out-of-package.

* Pure Elixir, **zero runtime dependencies**. Elixir `~> 1.17`. (In-tree, so the former "not yet published to hex" status is moot.)
* Public API: `inflect/3` (`inflect(phrase, locale, constraints)` → `{:ok, binary}`), `feature/3`, `features/1`, `feature_values/2`, `pronoun/2,3`, plus the lower-level `Concept` / `PronounConcept` / `Dictionary` / `Inflector`. **`inflect` is arity-3 only.**
* Constraints are the locale's grammatical features (`number`, `gender`, `case`, `definiteness`, `person`, …), composable in one call, discoverable via `features/1`. **Option *values* may be strings** — MF2 option values arrive as strings and are normalized internally. Value atoms (`:dative`, `:genitive`, …) are shared vocabulary with Localize.
* Locale: accepts atoms and binaries; the binary form is exactly `Localize.LanguageTag.canonical_locale_id`. Resolution walks a fallback chain to shipped per-locale data. **Does not accept `Localize.LanguageTag` structs** — the caller maps `LanguageTag` → bare locale atom.
* Data: `mix unicode_inflection.install` fetches a ~41 MB SHA-256-verified CDN bundle (same pattern as Localize locale data); **no runtime network**. Lazy per-locale load (metadata → `:persistent_term`, lexicon → ETS). Warm inflect ~8–21 µs; first-touch per-locale load a few ms (Arabic ~0.5 s).
* **No MF2 adapter** — deliberately out of scope in its ROADMAP ("NO MF2 integration per user instruction"), but the API is shaped as the building blocks and its `ROADMAP.md:65` writes out the exact shim Localize must build: (a) `LanguageTag` → bare atom, (b) reconcile Localize's `:grammatical_case`/`:grammatical_gender` ↔ the library's bare `:case`/`:gender`.
* **No unit-aware API and no `:quantify`/list-quantity engine** — it inflects arbitrary noun phrases only; assembling number+unit and CLDR pattern/plural selection stays Localize's job, and the `CommonConceptFactory` primitives that a `:quantify` function needs are not implemented.

### Localize MF2 + Unit today

* The MF2 parser **already** parses `:ns:name` into `{:namespace, ns, name}` (`message/parser/combinator.ex:159-170`), carried in the expression AST as `{:function, name, options}` where `name` is a binary or `{:namespace, ns, name}`.
* The interpreter **flattens** the namespace to a `"ns:name"` string (`interpreter.ex:848-852`) and dispatches by flat-string function-clause, with unmatched names falling through to the string-keyed custom registry (`resolve_custom_function/2`, `interpreter.ex:1195-1210`; `:functions` option or `config :localize, :mf2_functions`). **No namespace routing, reservation, or validation exists.** The only namespaced built-ins are the WG `test:*` conformance functions. Unknown → `{:error, {:unknown_function, …}}`.
* Consequence: a `"localize:inflect"` handler can be registered **today** via the existing custom registry — the flattened-string key already works. First-class namespace routing is an ergonomics/semantics upgrade, not a prerequisite for a prototype.
* `Localize.Message.Function` behaviour: single `format(value, func_opts, options)` callback; `func_opts` is a map with string keys/values; `options` carries `:locale` and `:bindings`.
* `Localize.Unit.to_string/2` inflection is **CLDR pattern-variant selection only** — `:grammatical_case` picks a case-keyed pattern, `:grammatical_gender` matters only for compound-unit patterns (`unit/formatter.ex:589-602`). **No morphological engine; no `unicode_inflection` dependency.** MF2 `:unit` doesn't even expose case/gender (`interpreter.ex:1853-1860`).

## Namespace decision (recommendation)

**Decision (Kip): use the single-letter namespace `l` — `:l:inflect`, `:l:pronoun`, later `:l:quantify`** — with `:u:` aliases added if/when the CLDR TC defines them.

Spec context and the one nuance to weigh:

* Bare `:inflect` / `:quantify` are **reserved for the MF2 spec's own use** (issue #202) — we cannot claim them. `l:` avoids that.
* `u:` is a **CLDR-committee-managed** namespace, currently reserved for *options* (`u:dir`/`u:id`/`u:locale`); the spec says it "**might also** be used to define functions in a **future** release" (tr35-messageFormat.md:4186). So `:u:inflect` as a *function* is not valid under the current spec, and `l:` is the right choice for now with `:u:` as the future alias.
* **Nuance worth recording:** the spec splits identifiers into *reserved* (no namespace, or a **single-letter** namespace) and *custom* (a **multi-letter** namespace), and it says non-default implementation functions "SHOULD use an implementation-defined namespace" — which, read strictly, is the *custom* (multi-letter) space (`tr35-messageFormat.md:1223-1235`). `l:` sits in the *reserved* single-letter pool alongside `u:`, not the custom pool. In practice this is low-risk: `u:` is the only single-letter namespace the spec has ever defined, a future `l:` collision is unlikely, `l:` is short and ergonomic, and the choice is fully reversible (adding a multi-letter alias later is trivial). Recorded here so the trade-off is explicit; `l` stands as the decision.

## Phase A — first-class MF2 namespace dispatch

Parsing already exists; the work is routing and semantics. Independent of inflection and a real conformance improvement, so worth doing on its own.

* **Namespace-keyed dispatch.** Add a namespace → handler registry (e.g. `config :localize, :mf2_namespaces, %{"localize" => Localize.Message.Namespace.Inflection}`) so all `:localize:*` functions route to one handler that dispatches on the local name, instead of registering each flattened string separately. Keep the existing flat-string custom registry working (back-compat).
* **Reserved-namespace semantics.** Reject user registration of the default (no-namespace) built-ins and of `u:` (CLDR-managed); an unsupported namespace yields an *Unknown Function* error — which the spec explicitly permits ("implementations are not required to implement namespaces") and which the interpreter already emits on fallthrough.
* **Pass the parsed `{:namespace, ns, name}` through** to namespace handlers rather than only the flattened string, so a handler sees its local name cleanly.
* **Fix the documented precedence bug** noted in the map: `Localize.Message.Function`'s moduledoc claims custom functions take precedence over built-ins, but built-in clauses match first. Either make the docs match reality or route custom/namespace lookup ahead of built-ins deliberately.
* Update `guides/conformance.md` with a namespace row.

## Phase B — `:l:inflect` (and `:l:pronoun`) MF2 functions

* The engine is now in-tree (`Localize.Inflection.*`), so there is **no optional-dependency guard**. What remains is a **data-availability** concern: the ~41 MB inflection data is installed out-of-package, loaded lazily per locale, so `:l:inflect` needs the data present. When it is not installed (or the locale is unsupported), the function must fail cleanly — a clear "inflection data not installed" / Unknown-locale error, or pass the operand through by policy — never a crash.
* Build the adapter shim (the `unicode_inflection` ROADMAP wrote this out): map the message's `Localize.LanguageTag` → the bare locale atom the engine expects — easier now that both live in Localize; pass MF2 option values straight through (already strings, which the engine normalizes); reconcile option *names* — MF2/Localize `grammatical_case`/`grammatical_gender` ↔ the engine's bare `case`/`gender`/`number`/`definiteness`. Value atoms (`:dative`, …) are already shared vocabulary.
* **`:l:inflect`** wraps `Localize.Inflection.inflect/3`: operand = the phrase (literal or variable), options = the grammatical constraints. **`:l:pronoun`** wraps `pronoun/2,3`. `feature/3` is the natural engine for grammar-driven `.match` selectors (a possible `:l:feature` selector function, or a documented recipe).
* **Speakable strings.** `inflect` can return `{print, speak}`; MF2 output is a single string, so resolve to the print form (document the choice; an option could expose the speak channel later).
* **`:l:quantify` is deferred.** The `CommonConceptFactory` list/quantity primitives it needs are unimplemented in the engine, so there is nothing to wrap yet — implement those first or scope Phase B to `:l:inflect`/`:l:pronoun`.

## Phase C — morphology engine under `Localize.Unit.to_string` (optional, configured)

* Today unit inflection is CLDR pattern-variant selection; `unicode_inflection` could inflect a unit's **display-name noun phrase** morphologically for case/number/gender combinations CLDR's pattern data doesn't ship, or for derived/compound units.
* **Gate behind config** (e.g. `config :localize, :unit_inflection_engine, :unicode_inflection`) so the default (CLDR patterns, deterministic, no heavy dep) is unchanged and the dependency stays optional.
* **Precedence:** CLDR pattern data is authoritative when present; the engine fills gaps only. Insertion point is `resolve_pattern/3` and the `:grammatical_case` reads in `unit/formatter.ex`. Caveat: words absent from the inflection lexicon pass through unchanged, so the engine must never *worsen* output vs. the CLDR fallback.
* This is the most speculative phase — recommend prototyping against a few high-value locales (de, ru, pl) and measuring against CLDR output before committing.

## Sequencing and upstream prerequisites

0. **Complete the `unicode_inflection` → `Localize.Inflection` merge** (in progress in another session) — the gate for Phases B and C.
1. **Phase A** (namespace dispatch, `l:`) — standalone, independent of the merge; can proceed first. Unblocks any namespaced function cleanly.
2. **Phase B** (`:l:inflect`/`:l:pronoun`) — after the merge; wires the in-tree engine into `Localize.Message`.
3. **Phase C** (unit engine) — experimental, config-gated, after B proves the adapter.
4. Track **#202**: add the `:u:inflect` alias only when/if CLDR blesses it. Track the in-tree `CommonConceptFactory` work for `:l:quantify`.

## Risks and open questions

* **The Technical Preview doc is unread** (auth-gated). Confirm with Kip: the proposed function names, namespace, and option set — they may differ from the `:localize:inflect` recommendation here, and the doc may pre-empt the #202 decision.
* **Namespace `l:`** is decided (Kip); the only residual is the reserved-vs-custom nuance recorded in the Namespace decision section, accepted as low-risk and reversible.
* **`:l:quantify` has no engine** yet — decide whether to implement `CommonConceptFactory` in-tree or defer the function.
* **Data-availability ergonomics**: the ~41 MB inflection data is out-of-package and installed separately, with a per-locale first-touch load (up to ~0.5 s for Arabic). Document the install path clearly and ensure `:l:inflect` degrades cleanly when the data is absent; consider a warm-up hook.
* **Locale coverage**: 31 languages have synthesizers (100% conformance); 17 more ship data without one; the rest are unsupported — `:localize:inflect` must degrade gracefully (Unknown-locale → pass through or error, by policy) for locales the engine can't inflect.
* **Option-name reconciliation** (`:grammatical_case` vs `:case`) must be consistent between the MF2 functions and any Unit engine use, to avoid two spellings of the same concept.
