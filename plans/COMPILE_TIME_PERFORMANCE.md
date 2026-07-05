# Compile-Time Performance Plan

Measured 2026-07-05 on Elixir 1.20.1-otp-29 / OTP 29.0.1 (Apple Silicon), `mix compile --force` in `:dev`.

## Baseline measurements

* Full forced compile: **65.8s wall, 83.7s user, 136% CPU** — the low CPU utilisation shows the build is heavily serialised behind a few chokepoints.

* Erlang phase (`mix compile.erlang --force`, the 7 generated `.erl` files): **54.0s**, of which `src/rbnf_lexer.erl` alone is **51s**. The generated file is **891KB** (its six siblings are 35–47KB). `yecc` and `leex` generation themselves are fast (0.35s + 0.61s); the cost is `erlc` compiling the exploded lexer.

* Elixir phase, top entries from `--profile time`: `validity/language.ex` **11.0s**, `validity/subdivision.ex` **10.5s**, `message/parser/parser.ex` 2.1s, `rfc5646_parser.ex` 1.8s, `validity/u.ex` 0.8s, everything else ≤0.5s.

* All of the above is **consumer-facing**: the hex package ships `src/*.xrl`/`*.yrl` and `lib/`, so every consumer pays the full cost on first compile. The `data/` pipeline (6,200 LOC) compiles only for maintainers (dev/test) and is not a factor for consumers.

## P1 — rbnf_lexer DFA explosion (−51s, ~77% of total; small effort, low risk)

The `Plural_rules` definition in `src/rbnf_lexer.xrl` is six optional groups each containing a greedy `.+`:

```
Plural_rules = (zero\{.+\})?(one\{.+\})?(two\{.+\})?(few\{.+\})?(many\{.+\})?(other\{.+\})?
```

Each `.+` overlaps the literal prefixes of every following optional group, so the leex DFA product construction explodes (891KB of state tables) and `erlc` takes 51s on the result.

**Fix (prototype verified in scratch):** a repeated single group producing the identical token text for well-formed input:

```
Plural_rules = ((zero|one|two|few|many|other)\{[^}]*\})+
```

Result: generated `.erl` drops to **41KB**, `erlc` to **0.22s**. The `plural_rules` token still carries the same `TokenChars` string into `rbnf_parser.yrl`'s `to_map/1`, so no parser change is needed. The new rule is stricter on malformed input (a plural body may not contain `}`, which CLDR RBNF bodies never do) and no longer accidentally matches interleaved garbage between groups.

**Verification gate:** full RBNF suite including the vendored ICU conformance data (en/de/es/fr), the spellout determinism tests, and a byte-diff of tokens for every RBNF rule in the shipped locale data (tokenize all rules with old and new lexer, assert identical token streams).

## P2 — Validity.Language / Validity.Subdivision clause generation (−15–20s; medium effort, needs a design decision)

`use Localize.Validity, :languages` / `:subdivisions` expands validity data (25KB / 35KB of codes) into large generated function-clause sets. The two modules alone cost 21.5s of Elixir compile time and, because `Localize.Validity` sits early in the dependency graph, they serialise much of the build (the 136% CPU).

Options, in preference order:

1. **Single map/MapSet literal + one lookup function.** Replace the per-code clause fan with one module attribute holding a map of code → status (ranges pre-expanded or kept as a small range list checked after the map miss) and a single `valid/1` that does a `Map.get`. Compiles in milliseconds; runtime is a hash lookup instead of clause dispatch — for sets this size that is equal or faster. Beam stays self-contained (no load-order concern).

2. **Runtime load into `:persistent_term`.** Zero compile cost, smallest beams, tiny one-time startup cost. Slightly more moving parts (load ordering, test seams) — the pattern already exists for the collation table.

3. Keep clauses but split the modules so they compile in parallel. Least value; does not reduce total CPU.

Recommendation: option 1 for `Language` and `Subdivision` (and any other validity module that grows); it keeps the current "no runtime state" property while removing effectively all the compile cost. Verify with the validity test suite (added this sprint, ~200 tests) and benchmark `validate_locale/1` before/after since it sits on the hot path.

## P3 — Build parallelism (free after P1+P2; verify only)

With P1 and P2 done, the projected full compile is **~10–12s** (from 65.8s). Re-profile afterwards; if CPU utilisation is still low, produce the compile dependency graph (`mix xref graph --format dot`) and look for remaining chokepoints. No action planned beyond verification.

## P4 — NimbleParsec parsers (keep as-is)

`Message.Parser` (2.1s), `Rfc5646.Parser` (1.8s) and `Unit.Parser` (0.3s) are the price of compiled parser combinators; the `runtime: false` dependency and the `defparsecp` extraction already minimise the cost. The runtime benefit (fast, allocation-light parsing on hot paths like `validate_locale/1`) is worth 4s of compile time. No change.

## P5 — Compile-time data embedding (beam size, not compile time; October window)

The big-beam modules cost little compile time (`Collation.Tailoring` 434ms/1.7MB beam, `DateTime.Timezone` 257ms/612KB) — the tradeoff here is memory and load size rather than compile speed, and the runtime benefit (zero-cost access, no startup decode) is real. Two follow-ups:

* **Correctness, cheap, do anytime:** `DateTime.Timezone` and `DateTime.Format.Match` read ETF files at compile time **without `@external_resource`**, so an ETF regeneration does not trigger recompilation — stale data risk at the October CLDR refresh. Add the attribute to both (and audit for other unmarked compile-time `File.read!` sites).

* **Optional, October:** move the `Collation.Tailoring` table to a runtime `:persistent_term` load from the ETF it already ships. Halves the largest beam; only worth doing while the collation ETF is being regenerated anyway (task #17).

## Sequencing

1. **P1 now-ish** (post-stability or as an 0.45.1 if consumer compile-time complaints arrive — it is a one-line grammar change with a 77% compile-time win and a strong verification gate).

2. **P5 `@external_resource` fix** rides with any next release; it is a correctness guard for October.

3. **P2 in the October window** alongside task #17, since validity data regeneration happens then anyway.

4. **P3 verification** after P1+P2 land.

Projected end state: consumer full compile from ~66s to ~10–12s, with no runtime regression (P1 is token-equivalent; P2's map lookup matches or beats clause dispatch at this set size).
