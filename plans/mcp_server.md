# Localize + Calendrical MCP server — plan

## Motivation

AI agents that work with Localize today discover the API the same way humans do — `rg`, `Read`, `grep` across `lib/`, then re-read moduledocs and `@spec`s to figure out which function takes which options. The surface is large (currencies, languages, scripts, territories, calendars, numbers, dates, times, intervals, durations, units, lists, messages, collation, locale displays, plural rules…) and each domain has its own options vocabulary. Three failure modes recur in transcripts:

1. **Wrong function chosen**, because the names overlap (`Localize.Number.to_string` vs `Localize.Number.System.to_system`, `Localize.Date.to_string` vs `Localize.Calendar.localize`).
2. **Wrong option shape**, because the same atom means different things in different contexts (`:format` is a CLDR pattern in numbers, a style atom in dates, an axis selector in intervals).
3. **Wrong locale/atom**, because the agent guesses `"en-au"` when CLDR canonicalises to `:"en-AU"`, or `"arab"` when the active locale exposes `:"arab"` only via supplemental.

An MCP server turns each of those probes — *what functions exist*, *what options does this one take*, *what atom does this string canonicalise to* — into a single typed tool call, with the answer coming from BEAM introspection rather than regex. Agents stop reading whole moduledocs to extract a list of three atoms; humans stop maintaining a parallel cheat-sheet.

This document plans the server. It does **not** implement it. Open design questions are flagged inline; the implementation phases at the end are the proposed ordering once the questions are settled.

---

## Scope

### In scope

* Static API introspection — modules, functions, specs, docs, options, exception types and their reason atoms.
* The closed atom collections — locales, calendars, currencies, languages, scripts, territories, number systems, units, measurement systems, plural categories.
* Locale-input canonicalisation — given an input, show how Localize resolves it (`cldr_locale_id_from/1`, validity, parent walk).
* Curated example library — for each major formatter, a small set of "here's the canonical call" snippets keyed by capability.
* Live invocation of a whitelisted set of read-only formatter / validator functions, returning structured `{:ok, result} | {:error, exception_struct}` outputs.

### Out of scope (initial cut)

* Anything that mutates global state — `put_default_locale/1`, `put_locale/1`, `Localize.Locale.Provider.Cache.store/2`.
* The Mix tasks — `mix localize.download_locales`, `mix gettext.extract`. Those are CLI surfaces; the MCP server should not shell out to Mix.
* The NIF — collation comparisons that run on the dirty scheduler. The benefit/risk ratio is poor at this stage.
* Compile-time code generation (sigils, `use Localize.Validity`). Agents that need this can still grep.

---

## Optional integrations

Two sibling packages extend Localize's API. The MCP server detects each at boot and exposes additional tool surface only when the package is loaded. Both are declared as `optional: true` in `localize_mcp`'s `mix.exs`.

### `Calendrical`

Ships the non-Gregorian calendars (Japanese, Hebrew, Islamic, Persian, …) that Localize formats. The two libraries already work together via the standard `Calendar` behaviour, so the MCP can expose a unified view:

* `localize_atoms` with `collection: "calendars"` returns the union of `Localize.Calendar.known_calendars/0` and whichever Calendrical-specific calendar modules are loaded.
* `localize_examples` for date / interval capabilities includes Calendrical snippets (`Calendrical.Japanese.new(2024, 5, 13)` → formatted under `:"ja-JP"`).
* `localize_doc` accepts `Calendrical.*` module names and routes through `Code.fetch_docs/1` the same way.

### `localize_web`

Adds the Phoenix / Plug surface — request-locale resolution from `Accept-Language` and cookies, route helpers, view interpolation, content negotiation. AI agents working in a Phoenix codebase need to discover these helpers as readily as the core formatter API. When `localize_web` is loaded, the server exposes:

* The `LocalizeWeb.*` modules in `localize_search` and `localize_browse` under a new `"Web"` group.
* `localize_examples` capabilities `"resolve_request_locale"`, `"negotiate_locale"`, `"render_in_view"`, `"link_locale_switcher"` (names tentative; finalised against the actual `localize_web` API at scaffold time).
* The whitelist in `priv/mcp/invocable.exs` extends to read-only `localize_web` helpers (locale negotiation from a synthetic `Plug.Conn`, header parsing, etc.).

Both `Calendrical` and `localize_web` get an entry in `localize_search`'s ranking so agents naming them directly always get a hit even if the user's current project doesn't depend on them — the server explains the package is not loaded and how to install it.

---

## Tool surface

Eleven tools organised into five groups. Each is a JSON-RPC tool in the MCP sense; names use the `localize_*` prefix so they don't collide with other servers a host might have loaded.

### Discovery

1. **`localize_search`** — keyword search across modules, functions, and docs. Args: `query` (string), optional `kind` (`"module"` | `"function"` | `"type"`), optional `limit`. Returns ranked matches with one-line summaries. Backed by a precomputed index built at server startup from `Code.fetch_docs/1` plus the `groups_for_modules` regex map in `mix.exs`.

2. **`localize_browse`** — list modules in a documentation group. Args: `group` (one of `"Numbers"`, `"Dates and Times"`, `"Locale"`, …, exactly the keys from `Localize.MixProject.groups_for_modules/0`). Returns the modules in that group with their moduledoc first line.

### Documentation

3. **`localize_doc`** — fetch the full doc + spec for a module or function. Args: `module` (required), optional `function`, optional `arity`. Returns moduledoc / funcdoc / `@spec` / `@callback` / examples. Uses `Code.fetch_docs/1` so this is one-shot and BEAM-accurate.

4. **`localize_examples`** — curated example snippets keyed by capability. Args: `capability` (one of `"format_number"`, `"format_date"`, `"format_currency"`, `"format_unit"`, `"format_duration"`, `"format_interval"`, `"format_message"`, `"format_list"`, `"collate"`, …). Returns a list of `{title, code, expected_output}` triples. Source of truth: a static `priv/mcp/examples/<capability>.exs` file shipped with the server, so the curation lives in a reviewable artefact and not in code.

### Schema / contracts

5. **`localize_options`** — for a formatter function, return its accepted options with types and (where applicable) allowed values. Args: `module`, `function`, `arity`. Returns a list of `%{name, type, allowed_values, default, description}`. Backed by a curated per-function metadata file at `priv/mcp/options/<module>.exs`, generated at first run by walking the docs and `@spec`s and refined by hand. **Open question:** can we infer option contracts mechanically from `@spec`? Probably partially — for atom-keyword options the spec gives the keyset but not the allowed-value enumeration. Plan: hybrid (auto-generate scaffold, hand-curate the allowed values).

6. **`localize_atoms`** — return the closed atom collection for a known kind. Args: `collection` (one of `"locales"`, `"calendars"`, `"currencies"`, `"languages"`, `"scripts"`, `"territories"`, `"number_systems"`, `"measurement_systems"`, `"plural_categories"`, `"units"`, `"unit_categories"`, `"unit_usages"`). Returns the list of atoms with each one's first-line display name (`:"en-AU"` → `"English (Australia)"`). Backed by the existing `Localize.X.known_*` accessors plus `Localize.Calendar.known_calendars/0` and Calendrical's `Calendrical.calendars/0`.

7. **`localize_errors`** — list all `Localize.*Error` modules with their documented `:reason` atoms (via the existing `Localize.Exception` behaviour we already shipped). Args: optional `module` to scope to one exception type. Returns each module's struct shape, `reason_atoms/0`, and one example bound exception.

### Resolution

8. **`localize_resolve_locale`** — given an input, show how Localize canonicalises it. Args: `input` (string or atom). Returns `%{requested, parsed_tag, cldr_locale_id, validity_status, parent_chain, supported?, atom_interned_at_runtime?}`. Backed by `Localize.LanguageTag.parse/1`, `Localize.validate_locale/1`, `Localize.Locale.parent/1`, `Localize.supported_locales/0`. This is the single highest-value tool — it answers half the "which locale string do I use" questions agents currently ask via three rounds of `Read` + `Bash`.

9. **`localize_validate`** — generic kind-aware validator. Args: `kind` (`"currency"`, `"calendar"`, `"territory"`, `"script"`, `"number_system"`, `"language"`), `value` (string or atom). Returns `%{kind, input, canonical, valid?, error}`. Backed by the existing `Localize.validate_*` family.

### Live invocation

10. **`localize_invoke`** — execute one of the whitelisted read-only functions and return the result. Args: `mfa` (string like `"Localize.Number.to_string/2"`), `args` (JSON-encoded Elixir terms with a documented mini-grammar — atoms as `{"$atom": "name"}`, dates as `{"$date": "2024-05-13"}`, Decimals as `{"$decimal": "1.5"}`). Returns `{:ok, %{result, term_kind}}` or `{:error, %{exception: struct, reason: atom_or_nil, message: string}}`. The whitelist is a static list — every formatter / parser / validator the team chooses to expose. **Open question:** is the whitelist's first cut public-by-default with a denylist, or denied-by-default with a curated allowlist? Recommendation: allowlist, because the safety story is straightforward and the curation cost is one entry per shipped function.

11. **`localize_term_grammar`** — return the term-encoding grammar used by `localize_invoke`. Static reference output. Lets agents bootstrap themselves without reading the server's source.

---

## Architecture

### Distribution: a separate hex package

A new package `localize_mcp` (depending on `:localize` and optionally `:calendrical`). **Not** bundled inside `:localize` itself, because:

* The MCP protocol library brings transitive deps Localize callers shouldn't have to compile.
* MCP iteration speed (tool catalogue, examples, options metadata) is much higher than Localize's release cadence.
* Users who never use the MCP shouldn't carry it.

Sets up cleanly as `{:localize_mcp, "~> 0.1", only: :dev}` for end users, or as a Mix archive (`mix archive.install hex localize_mcp`) for system-wide install with Claude Desktop / similar hosts.

### MCP SDK choice — open question

Three viable options:

* **Hermes-MCP** (Erlang/Elixir, actively maintained) — most complete, includes transport adapters for stdio + SSE.
* **Anthropic's official MCP SDKs** — none for Elixir today, so a wrapper around the JSON-RPC layer would be hand-rolled.
* **Roll our own** — MCP is JSON-RPC 2.0 over stdio, ~200 LOC of dispatcher + framer. Tempting because the deps are zero, but throws away schema-validation work the SDK gives us for free.

Recommendation: **Hermes-MCP**, fall back to roll-our-own if its dep tree is heavy or its abstractions don't fit. The plan does not depend on this choice — the tool surface above is SDK-agnostic.

### Transport

Stdio only, initially. That covers Claude Desktop, Claude Code, and Zed. SSE / WebSocket comes later if multi-host usage emerges.

### Server lifecycle

```
mix localize_mcp.start
  ↓
GenServer boots, reads priv/mcp/options + priv/mcp/examples into ETS, builds the
search index over Code.fetch_docs(Localize.*) and Calendrical.*  if loaded.
  ↓
Stdio framer reads JSON-RPC frames from stdin, dispatches to tool handlers,
writes responses to stdout. Logs go to stderr.
```

No process supervision tree of its own — the OS process is the supervision boundary. The server runs `Application.ensure_all_started(:localize)` at boot so the supplemental atoms are interned exactly as they would be in any other consumer.

### Safety model

* **Live invocation is whitelisted.** Anything not in the allowlist returns a `not_invokable` error pointing at `localize_doc` / `localize_options`.
* **No process state is mutated.** The whitelist is read-only by construction; `localize_invoke` runs each call inside a `Task.async/1` so the caller's process dictionary (current locale, etc.) is isolated.
* **No filesystem writes.** The server reads from `priv/mcp/` and the bundled `priv/localize/`; it never writes outside `_build/`.
* **Resource caps.** Each `localize_invoke` runs under a 5s timeout and a 64 MB heap limit; the term grammar accepts inputs up to 16 KB.

---

## Index / metadata files

Shipped under `priv/mcp/` in the new package:

```
priv/mcp/
  examples/
    format_number.exs
    format_date.exs
    format_currency.exs
    ...
  options/
    Elixir.Localize.Number.exs
    Elixir.Localize.Date.exs
    Elixir.Localize.Unit.exs
    ...
  invocable.exs        # the whitelist
  capabilities.exs     # capability → suggested mfas
  search_index.etf     # precomputed at hex publish time
```

These are deliberately exposed as plain `.exs` so they review in PRs and a maintainer can fix a misleading example without a release.

---

## Test strategy

Three layers:

1. **Schema tests.** For each tool, an example request → expected response shape (not exact content). Runs under `mix test`.
2. **Round-trip tests.** Build a request, dispatch through the tool registry, decode the response, assert the structured fields. Catches drift between the JSON encoding and the tool handler.
3. **Live-invocation tests.** For each whitelisted MFA, a representative call + expected `{:ok, _}` and (where realistic) a representative bad call + expected `{:error, %SomeError{}}` so a future Localize behavioural change surfaces as a failure in `localize_mcp` rather than as a silent agent confusion.

The `priv/mcp/examples/*.exs` files are also test fixtures: a doctest-style runner asserts each `code` snippet produces the `expected_output`. That guards against curation drift.

---

## Implementation phases

Five phases, each landable independently. Phases 1 and 2 deliver enough value to justify shipping a 0.1 release; later phases extend rather than replace.

* **Phase 1 — Static surface (1 week).** New package skeleton, MCP SDK wired, tools 1–4 (`localize_search`, `localize_browse`, `localize_doc`, `localize_examples`). Search index from `Code.fetch_docs/1`. Example library bootstrapped from existing `iex>` doctests, then trimmed.

* **Phase 2 — Schema + atoms (3–5 days).** Tools 5–7 (`localize_options`, `localize_atoms`, `localize_errors`). Per-module options metadata auto-scaffolded from `@spec` then hand-curated for the top-ten formatters. Atoms come straight from existing `known_*` accessors.

* **Phase 3 — Resolution (2–3 days).** Tools 8–9 (`localize_resolve_locale`, `localize_validate`). Smallest amount of new code — these are thin façades over existing validators.

* **Phase 4 — Live invocation (1 week).** Tools 10–11 (`localize_invoke`, `localize_term_grammar`). The bulk is the term grammar (parse → Elixir term + the inverse), the whitelist, and the round-trip tests.

* **Phase 5 — Polish & release (1 week).** Documentation guide, Claude Desktop config snippet in the README, an `examples/` directory of recorded sessions, a small benchmark suite that compares "grep-based discovery" cost (Bash tool calls, bytes read) against "MCP-based discovery" cost for a fixed set of agent tasks.

Total estimated effort: roughly 4 weeks of focused work, plus review time.

---

## Decisions (settled)

1. **Separate package.** New hex package `localize_mcp`, depending on `:localize`.
2. **Optional integrations.** `Calendrical` and `localize_web` are both optional deps. Each is detected at boot via `Code.ensure_loaded?/1`, and tools that surface their API only appear when the corresponding package is loaded. The MCP server itself runs identically with neither, either, or both.
3. **Hermes-MCP** unless a concrete blocker emerges during Phase 1 (e.g. licence conflict, broken stdio transport, unsupported OTP version). Roll-our-own is the fallback.
4. **Allowlist** for `localize_invoke`. Every invokable MFA is enumerated in `priv/mcp/invocable.exs`; anything not listed returns `not_invokable`.
5. **Manual curation** of `priv/mcp/options/*.exs` and `priv/mcp/examples/*.exs`. The build will auto-scaffold initial files from `@spec` and existing `iex>` doctests; the maintainer refines from there.
6. **Two distribution channels.** Standard hex package for `mix.exs`-based use, plus a publishable Mix archive (`mix archive.install hex localize_mcp` and a downloadable `.ez`) so users can install once and reference from any Claude Desktop / Claude Code / Zed config without per-project deps.

Phase 1 is unblocked.

---

## Repo layout

`localize_mcp` lives in a **sibling repo** at `/Users/kip/Development/localize/localize_mcp/`, alongside the existing `localize/`. The hex package and the Mix archive are both produced from that single repo. The current `localize/` repo stays untouched.
