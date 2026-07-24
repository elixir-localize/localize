# Parser performance — investigation plan

Date: July 24, 2026. Trigger: a user asked about replacing the leex/yecc parsers with a Rust-based parser. Decision already taken: **we stay pure-Elixir.** This plan is therefore not a migration plan — it is a measurement-and-decision plan that answers, in order, three questions: (1) is a parser change worth it at all; (2) if so, where does the cost actually sit — lexing, parsing, canonicalization, best-matching, or struct construction; (3) since parsed results are already cached, does this matter for real applications?

## Constraints and scope

* **Pure Elixir only.** No Rust, no NIF parser.
* **The only sanctioned replacement is `nimble_parsec`**, which is already a dependency (`~> 1.0`, `runtime: false`) — so a migration adds no new dependency and uses a combinator library already proven in this codebase.
* Any change must keep the parser conformance suites green: CLDR plural-rules reference data, RBNF reference data, the decimal-format test-data suite, and the likely-subtags/canonicalization suites.

## Ground truth (what the code actually is today)

The framing "replace the leex/yecc parsers" is narrower than it sounds, because the high-frequency, user-facing parse surfaces are **already** `nimble_parsec`:

| Parse surface | Implementation | Invoked | Cached |
|---|---|---|---|
| Language tags (RFC 5646) | `nimble_parsec` (`rfc5646_*`) | per `validate_locale/1` | `validate_locale` result cached in `:persistent_term` |
| Units | `nimble_parsec` (`unit/parser/*`) | per `Unit.new`/`parse` | — (grammar only) |
| MF2 messages | `nimble_parsec` (`message/parser/*`) | per parse | caller-dependent |
| Decimal format patterns | **leex/yecc** (`localize_decimal_formats_*`) | `number/format/compiler` | `FormatCache` (ETS, bounded 5k) |
| DateTime format patterns | **leex** (`localize_date_time_format_lexer`) | `datetime/format/compiler` | `FormatCache` (ETS, bounded 5k) |
| Plural rules | **leex/yecc** (`localize_plural_rules_*`) | `number/plural_rules/compiler` | feeds `:persistent_term` locale data |
| RBNF rules | **leex/yecc** (`localize_rbnf_*`) | `number/rbnf/rule` | feeds `:persistent_term` locale data |

Two facts fall out of this table and shape the whole investigation:

1. **A `nimble_parsec` migration could only ever touch the four leex/yecc parsers**, and all four parse CLDR *data* or *format patterns*, not free-form high-frequency user input. Every one of them sits behind a cache (FormatCache for decimal/datetime patterns; persistent_term locale data for plural/RBNF), so in steady state they run on the cold path only.

2. **The user's five candidate cost centers do not all live in a parser.** Mapped to the code: *lexing* and *parsing* are the parsers above; *canonicalization* is post-parse (language tag + unit); *best-matching* is likely-subtags maximization plus the language-distance trie (CLDR graph work, no parser involved); *struct construction* builds `LanguageTag`/`LanguageTag.U`/`Unit`. The hottest realistic path — `validate_locale/1` — is already `nimble_parsec` for the lex/parse step, so if it is ever slow the cost is almost certainly in canonicalize / best-match / struct, i.e. swapping a parser would not help it.

**Working hypothesis (to be proved or disproved, not assumed):** for real applications the parse cost is not a bottleneck because it is cached, and any measurable hot cost is in the language-tag data path (best-match/canonicalize/struct), not in lexing or parsing. If that holds, the recommendation is "no parser change," and the effort redirects to the data path or to closing a cache gap.

## Stage 1 — Is it worth it? (go/no-go gate)

Build parse microbenchmarks on the existing harness (`bench/`, `benchee` already a `:bench` dep) measuring **warm vs cold** for each surface:

* **Warm (steady state):** repeated parse of the same input, cache in effect — what a real app pays after warm-up.
* **Cold (cache miss / bypass):** cache cleared or bypassed each iteration — the true parser+downstream cost.
* **High-cardinality:** a stream of *distinct* inputs (varied locale strings, varied custom format strings, varied MF2 messages, varied unit strings) — the workload where caching stops helping and the parser is genuinely on the hot path.

Define the realistic workload model per surface and record where steady state actually lands. **Gate:** unless a realistic, high-cardinality workload keeps a *leex/yecc* parser on the cold path in steady state, stop here — document "not worthwhile" with the numbers. (Expect the language-tag and unit `nimble_parsec` paths to show up first; those are not leex/yecc and are handled in Stage 3's second branch.)

## Stage 2 — If a hot path exists, decompose the cost

For any surface that clears the Stage 1 gate, attribute time across the pipeline the user named — **lex → parse → canonicalize → best_match → struct** — with `:eprof`/`:fprof` and/or per-step benchee pipelines. This is the direct answer to the user's second question and tells us whether the parser (lex+parse) is even the culprit versus downstream data work.

## Stage 3 — Targeted action, only for the proven bottleneck

* **If lex/parse dominates a hot leex/yecc parser** → prototype a `nimble_parsec` replacement for that *one* parser; A/B benchmark; adopt only on a clear win with the conformance suite still green. (Note the compile-time cost tradeoff: `bench/compile_time.sh` exists — nimble_parsec grammars can raise compile time; measure it.)
* **If canonicalize/best_match/struct dominates** (the likely finding for the language-tag path) → the parser is irrelevant; optimize the data path (distance-trie lookup, likely-subtags resolution, struct build) or widen caching instead.

## Stage 4 — Caching audit (do regardless; cheapest ROI)

Independently of Stages 1–3, verify each parse surface's cache: the hit path, key cardinality, eviction behavior under `format_cache_max_entries`, and whether any public entry point bypasses the cache (e.g. a formatting call that re-parses instead of going through `FormatCache`, or an MF2 render path that reparses per call). Historically the highest-ROI fix here is closing a cache gap, not swapping a parser.

## Deliverables / definition of done

* A `bench/parser_perf.exs` benchmark covering warm/cold/high-cardinality for all seven surfaces.
* A short findings note (numbers + the per-stage decomposition for any hot surface).
* A one-line go/no-go recommendation. Any adopted change ships with its conformance suite green and a compile-time delta recorded.

## Non-goals

* No Rust; no new runtime dependency.
* Not rewriting parsers that are already `nimble_parsec` (language tags, units, MF2) — they are in scope only as *measurement* targets, and only their non-parser stages (canonicalize/best-match/struct) are candidates for optimization.

---

# Findings (July 24, 2026)

Measured on Elixir 1.20.1 / OTP 29, in a throwaway worktree, with `:timer.tc` (median of 5 × 50k-iteration passes; warm loops for uncached raw entry points, single-pass over distinct pools for cached surfaces). Benchmark: `bench/parser_perf.exs` on the `parser-perf-investigation` branch.

## Raw parse cost, per op

| Surface | µs/op | Implementation |
|---|---:|---|
| RBNF rule | 0.51 | leex/yecc |
| DateTime pattern (tokenize) | 0.53 | leex |
| RFC 5646 lex+parse | 0.69 | nimble_parsec |
| Plural rule | 0.81 | leex/yecc |
| Language tag parse (repeated input) | 1.94 | nimble_parsec |
| Unit `new` | 2.05 | nimble_parsec |
| MF2 parse | 2.54 | nimble_parsec |
| **Decimal format pattern** | **14.82** | **leex/yecc** |

Warm (steady state, cache hit): `validate_locale` **0.35 µs**, decimal pattern via FormatCache **0.26 µs** — both sub-microsecond.

## The cold language-tag path, decomposed

`validate_locale` on a novel locale (cache miss): **~4000 µs**, dropping to **0.4 µs** on the second pass (fully cached in `:persistent_term`). Stage-2 decomposition:

| Stage | µs/op |
|---|---:|
| lex + parse | 0.68 |
| + struct build / canonicalize (delta) | 1.4 |
| + likely-subtags / first-touch data load / cache (delta) | ~4000 |

The parser is **~0.02%** of the cold cost. The ~4 ms is dominated by first-touch locale-data loading (ETF read + `binary_to_term`) and likely-subtags resolution — it does not amortize across *distinct* locales (each new locale loads its own data), but is 0.4 µs once cached. No leex/yecc parsing is involved.

## Answers to the three questions

1. **Is a parser change worth it?** **No.** Every parser costs 0.5–15 µs cold; all four leex/yecc parsers sit behind a cache (FormatCache for decimal/datetime patterns, persistent_term locale data for plural/RBNF) and run sub-µs warm. The three high-frequency surfaces (language tags, units, MF2) are already nimble_parsec. Moving the leex/yecc parsers to nimble_parsec would change nothing a real workload could measure.

2. **Where is the cost — lex/parse/canonicalize/best_match/struct?** Not lex or parse. On the only path with meaningful cost (cold language tag), it is **likely-subtags + first-touch data loading**, with canonicalize+struct a distant ~1.4 µs. best_match/data-provisioning dominate; the parser is noise.

3. **Does caching already cover the common case?** **Yes, decisively.** Warm everything is sub-µs; the caches are the load-bearing element. The one caveat is a data-path concern, not a parser one: a workload validating an unbounded stream of *distinct* locales (e.g. per-user Accept-Language with cache eviction) pays multi-ms per novel locale.

## Recommendation

**No-go on replacing the leex/yecc parsers with nimble_parsec (or anything else).** The decimal-pattern yecc parser is a 20× outlier at 14.8 µs, but it is FormatCache-backed (0.26 µs warm) and even cold is ~3% of a novel-pattern `to_string`; it would only matter under a pathological unbounded-distinct-pattern workload that bypasses the cache, which does not exist in practice.

If there is appetite for performance work, the ROI is entirely on the **cold language-tag data path**, independent of the parser:

* `supported_locales/0` falls through to `SupplementalData.all_locale_ids/0` on every cold `validate_locale` when `:supported_locales` is unset (the default), and deliberately does not cache that default — re-scanned per novel locale. Caching the default (or short-circuiting `maybe_restrict_to_supported/1` when unconfigured) removes per-cold-call work.
* First-touch locale-data loading is the real multi-ms cost; if unbounded distinct-locale workloads matter, consider the cache's eviction behavior and/or a warm-up path.

Neither touches lexing or parsing, so this closes the parser question.

---

# Decimal-pattern optimization (July 24, 2026)

Follow-up on the one parser flagged as a 20× outlier. Decomposing `Localize.Number.Format.Compiler.format_to_metadata/1`:

| Stage | µs/op |
|---|---:|
| tokenize (leex) | 0.14 |
| parse from tokens (yecc) | 0.10 |
| **analyse (AST → Meta struct)** | **15.42** |

The leex/yecc parser is **1.5%** of the cost — the same lesson as the language-tag path. The 15 µs lived in `analyse/2`, which used **runtime-interpolated regexes** (`~r/#{@attr}/`) that recompile on every call; `analyse` runs ~8 of them and `Regex.compile` is ~1–2 µs each.

Fix: compile each regex once into `:persistent_term` at supervisor start (`precompile_regexes/0` in `after_start/0`, while the term table is still small so the one-time puts are cheap), read on every use, with a lazy first-touch fallback for callers that skip application start. A compiled regex cannot be a module-attribute literal on OTP 29, so persistent_term rather than a `@attr` constant.

Result: `analyse` **15.42 → 9.55 µs**, full compile **15.7 → 10.0 µs** (~40%). Formatting is unaffected — compiled patterns are already FormatCache-backed (0.26 µs warm). All 1882 number tests green.

The residual ~9.5 µs is genuine analysis work (regex *matching* + string/map building), not compilation. Cutting it further would mean rewriting the regex-based digit-counting helpers to direct charlist scanning — a larger, riskier change whose benefit is cold-path-only (behind FormatCache), so not pursued.
