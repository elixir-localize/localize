# MF2 message translation via mix task + LLM

**Status:** planning, last updated 2026-05-14

**Owner:** Localize maintainers

**Companion skill:** [.claude/skills/mf2-translation/SKILL.md](../.claude/skills/mf2-translation/SKILL.md) — the "how to translate an MF2 message" guidance that this pipeline encodes into prompts. Read the skill first; this plan is the engineering side of the same problem.

## Goal

Provide `mix localize.translate` such that a maintainer can run

```bash
mix localize.translate priv/gettext/fr/LC_MESSAGES/default.po --target fr --source en
```

and get a French `.po` file whose msgstrs are MF2 translations of the English msgids. The pipeline must produce translations that pass `Localize.Message.parse/1`, render correctly via `Localize.Message.format/3`, and respect the placeholder/selector hazards described in the companion skill.

## Why this is non-trivial

Three independent problems compound:

1. **Placeholder preservation.** MF2 strings carry `{$var}`, `{$var :func attr=val}`, `{#tag}…{/tag}` markup, and `.match` selector blocks that an LLM mishandles when given the raw string. Solution: sentinel substitution with `<x id="N"/>` tags, restored after translation. See the skill for full reasoning.

2. **Selector category divergence.** A source message with `one`/`other` translates into a target locale whose CLDR plural rules require `one`/`few`/`many`/`other` (Russian) or `zero`/`one`/`two`/`few`/`many`/`other` (Arabic). The pipeline must add branches the source doesn't have, driven by `Localize.Number.PluralRule.Cardinal`'s knowledge of the target locale's categories.

3. **Validation.** A translation that compiles and parses but renders wrong (e.g. dropped a placeholder, scrambled a selector) is worse than a missing translation because it ships silently. Every output needs a parse + render round-trip before commit.

Cost and latency matter at the per-locale level (a real project has 100s of messages × ~30 locales = 3,000+ LLM calls per release), so the pipeline must use prompt caching and the Anthropic Batch API.

## Architecture

```
                                                          mix localize.translate
                                                                  │
                              ┌───────────────────────────────────┴───────────────────────────────────┐
                              │                                                                       │
                              ▼                                                                       ▼
            Localize.PoTranslator                                                       Localize.Message.LlmTranslator
            ─────────────────────                                                       ────────────────────────────
            * read .po via :expo                                                        * sentinel-substitute MF2
            * detect MF2 vs plain Gettext                                               * build prompt (system + glossary + table)
            * dispatch to LlmTranslator OR plain                                        * call Anthropic API (batch or sync)
            * write back to .po                                                         * substitute placeholders back
                                                                                        * validate (parse + render)
                                                                                        * retry once with corrective prompt on failure
```

Two new modules; everything else already exists in the project.

## Phase 1 — simple MF2, sentinel approach

Scope: messages with placeholders only (no `.match` selectors). This covers ~70% of typical project messages.

### `Localize.Message.LlmTranslator`

Public API:

```elixir
@spec translate(source :: String.t(), source_locale :: String.t(), target_locale :: String.t(), Keyword.t()) ::
        {:ok, String.t()} | {:error, term()}
def translate(source, source_locale, target_locale, options \\ [])
```

Options: `:model` (default `"claude-sonnet-4-6"`), `:glossary` (per-project terms), `:max_retries` (default 1).

Internal pipeline:

1. **Parse the source MF2.** `Localize.Message.parse/1` returns the AST. If parse fails, return `{:error, :invalid_source}` — do not call the LLM.

2. **Walk the AST extracting placeholders into a numbered table.** Each entry is `{id, original_text, type_hint}` where `type_hint` is derived from the function annotation (e.g. `{$count :number}` → `"a numeric count"`, `{$date :datetime}` → `"a date/time value"`, `{$name}` → `"a value of unknown type — likely a name or label"`).

3. **Substitute sentinels.** Walk the source string (not the AST — preserves whitespace and ordering exactly), replacing each placeholder with `<x id="N"/>`.

4. **Build prompt.** System prompt: skill content (condensed) + glossary if provided + placeholder table + target-locale style notes. User message: "Translate to {target_language_name}:\n\n{sentinel_source}". The system prompt is constant per `(model, glossary, target_locale)` triple — eligible for prompt caching.

5. **Call the API.** Synchronous for `--dry-run` and small jobs; batched (Anthropic Batch API) for full-file runs.

6. **Substitute placeholders back.** Substitute longest-id-first to avoid `<x id="10"/>` matching against `<x id="1"/>`.

7. **Validate.** Run the validation checklist from the skill: parse, sentinel conservation, render round-trip with synthetic bindings.

8. **Retry on validation failure** (once). Build a corrective prompt: "Your previous response was '{previous}'. It failed validation because {reason}. Retry, ensuring …". If retry also fails, return `{:error, {:validation_failed, reason, attempts}}` for the caller to queue for human review.

### `Localize.PoTranslator`

Public API:

```elixir
@spec translate_po_file(path :: String.t(), Keyword.t()) ::
        {:ok, %{translated: integer(), skipped: integer(), failed: [..]}} | {:error, term()}
def translate_po_file(path, options \\ [])
```

Reads via `Expo.PO.parse_file/1` (the `expo` library is already a Localize dep). For each message:

* If the msgstr is non-empty (or non-empty for every plural form), skip.
* If the msgid contains MF2 syntax (heuristic: matches `~r/\{[\$#]|\.match\b/`), dispatch to `LlmTranslator`.
* Else translate as plain Gettext (still LLM, but with a much simpler prompt — no MF2 hazard).

Writes via `Expo.PO.compose/1`. Preserves comments and reference lines (these are roundtrip-stable in `expo`).

### CLI: `mix localize.translate`

```
mix localize.translate <po_file_or_glob> [options]

Options:
  --target LOCALE          target locale (required, e.g. fr, fr-CA, ja)
  --source LOCALE          source locale (default: en)
  --model NAME             Anthropic model (default: claude-sonnet-4-6)
  --glossary PATH          path to a YAML or markdown glossary
  --dry-run                print translations to stdout, don't write
  --only PATTERN           only translate msgids matching PATTERN (regex)
  --review                 emit a unified diff of changes; do not write
  --batch                  use the Anthropic Batch API for cost (24-hour SLA)
  --concurrency N          parallel API calls when not batching (default: 4)
  --no-validate            skip the post-translation parse/render check (debug only)
```

Reads `ANTHROPIC_API_KEY` from env. Hard-fails (not warning) if the key is missing — the task can't do anything useful without it.

## Phase 2 — selector translation

Scope: `.match` blocks. Adds these capabilities to `LlmTranslator`:

1. **AST-driven branch extraction.** Parse the source, walk the `.match` AST, identify the selector variables and the per-category bodies.

2. **Per-branch sentinel substitution.** Each body is a separate translation unit. The placeholder table is shared across branches (same numbering throughout the message).

3. **Target-category determination.** `Localize.Number.PluralRule.Cardinal.known_plural_types(target_locale)` returns the category set the target needs. Diff against the source's categories.

4. **Branch synthesis.**
   * For categories present in both source and target: translate the source branch directly.
   * For categories present only in target: translate the source's `other` branch, plus a prompt-context line "This is the `few` form for {target_language} (used for counts like 2, 3, 4 in Russian)" so the LLM picks the right inflection.
   * For categories present only in source (rare — happens when source language has a finer plural system than target, e.g. Welsh source → English target): collapse extras into target's `other`.

5. **Reassemble** into a `.match` block with target-correct branch ordering (CLDR-canonical).

The synthesised `.match` is then validated as a whole: all branches must parse, every branch must render with a synthetic count value chosen to fall in that branch's category.

## Phase 3 — Batch API + prompt caching

Cost optimisation. Scope: production-quality runs over full PO files.

* **Prompt caching** (Anthropic API): the system prompt (skill content + glossary + per-locale style notes) is identical across all messages in a single locale's translation run. Mark it `cache_control: ephemeral` so subsequent requests in the run hit the cache. Expected cost reduction: 90% of input tokens after the first request.

* **Batch API**: messages are independent. Submit all of them as a single batch (24-hour SLA, 50% cost discount). Phase 3 adds `--batch` to the CLI; Phase 1 starts synchronous-only.

* **Concurrency** for synchronous mode: `Task.async_stream` with a small parallel limit (default 4) to respect API rate limits without going single-threaded.

## Phase 4 — review workflow

Scope: human-in-the-loop for the cases the validator can't catch.

* `--review` mode emits a unified diff (`old_msgstr` → `new_msgstr` per message) for the maintainer to skim.
* Messages flagged by the LLM during translation as "needs review" (e.g. translator wasn't confident, or had to make an unsupported assumption about gender/formality) are emitted to a separate `<file>.review.txt` with the reason.
* A `mix localize.review` task walks the review file interactively — accept, reject, or rewrite each translation.

## API integration

* **SDK**: use the `anthropic` Hex package (Elixir official SDK). Add as a dev/test dep — the mix task only runs at maintenance time, not in production.
* **Models**:
  * Default `claude-sonnet-4-6` — fast and cheap, fine for most languages.
  * `claude-opus-4-7` for high-complexity targets (Arabic, Japanese, locales with rich gender/case systems).
  * Configurable per-message via msgid comment hint `# claude:model=opus-4-7` for hard-to-translate strings.
* **Auth**: `ANTHROPIC_API_KEY` env var only. No file-based key storage.
* **Retries**: SDK-level for HTTP/transport errors; pipeline-level (one retry with corrective prompt) for validation failures.

## Configuration

* `config/dev.exs` example block (committed as comment in `config/config.exs`):

  ```elixir
  config :localize, :translation,
    default_model: "claude-sonnet-4-6",
    glossary: "priv/translation/glossary.md",
    locale_styles: %{
      "ja" => "Use です/ます polite form throughout. Avoid casual contractions.",
      "fr" => "Use vous form. Avoid anglicisms where a native French term exists.",
      "de" => "Use Sie form."
    }
  ```

* **Glossary file format**: markdown table with three columns — source term, target translation per-locale, do-not-translate flag. The pipeline reads this and folds the relevant rows into the system prompt for each locale.

* **Per-locale CLDR plural categories**: derived from `Localize.Number.PluralRule.Cardinal` at runtime, no config needed.

## Testing strategy

* **Unit tests** (no API): mock `LlmTranslator.translate/4` to return canned responses; assert the sentinel substitution, AST walking, validation, and retry logic.
* **Integration tests** (gated): `LOCALIZE_RUN_AI_TESTS=1 mix test --include ai` runs against the real Anthropic API with a small fixture (5–10 messages, 2 locales). Verifies end-to-end behaviour.
* **Golden file tests**: `test/fixtures/translation/golden/<locale>/expected.po` — a known-good translation of a fixture PO. Regenerate intentionally with `mix localize.translate.regenerate_golden` (manual). Diff against golden in CI as a regression detector for prompt drift.
* **Property tests**: for the sentinel substitution (substitute → translate-noop → restore must round-trip exactly).

## Open questions

* **Gender of name-typed placeholders.** In gendered languages, the LLM can't know whether `{$name}` will hold "Alice" or "Bob". Options: (a) emit the masculine form by convention and accept occasional gender errors, (b) require a `:gender` annotation on name-typed placeholders so the runtime can pick the right form, (c) use the `.match $name :gender` selector pattern to render conditionally. The skill currently flags this for human review.

* **Formality detection.** Should the project default to formal forms in target languages with formal/informal distinctions (vous/tu, です-form/だ-form)? Current plan: per-locale config. Alternative: derive from project context (a banking app implies formal; a chat app implies informal).

* **Glossary scope.** A project glossary helps consistency but is non-trivial to maintain. Phase 1 punts on this — glossary file is supported but optional. Phase 4 review workflow could surface candidates for glossary entries when the same source term is translated inconsistently across messages.

* **Translation memory.** Should we cache `(source, target_locale) → translation` and skip the LLM call on exact match? Cheap to add but raises consistency questions when the source is updated. Defer until Phase 4.

* **Markup messages (`{#bold}…{/bold}`).** Phase 1 sentinels handle markup the same way as variables (each opening and closing tag is its own placeholder). Edge case: when the LLM translates "click {#link}here{/link} to continue" into a language where the link text needs to wrap different words, the markup might need to be repositioned around different translated words. Solution: render the markup as `<g id="N">…</g>` paired tags (XLIFF convention for inline markup) so the LLM understands the wrapping semantics. Defer to Phase 2 alongside selector work.

## Phasing

| Phase | Scope                                                       | Effort     | Blocking dependency |
|-------|-------------------------------------------------------------|------------|---------------------|
| 1     | Simple MF2 (no selectors), synchronous API, sentinel core   | ~3–4 days  | none                |
| 2     | Selectors + plural-category synthesis + markup wrapping     | ~2–3 days  | Phase 1             |
| 3     | Batch API + prompt caching + concurrency                    | ~1–2 days  | Phase 1             |
| 4     | Review workflow + interactive accept/reject task            | ~2–3 days  | Phase 1, 2          |

Total: ~8–12 days of work spread across the cycle. Phase 1 is independently shippable as `mix localize.translate` for simple messages; subsequent phases extend coverage and reduce cost.

## Change log for this plan

* 2026-05-14 — Initial draft. All phases at status *planned*; companion skill drafted at `.claude/skills/mf2-translation/SKILL.md`.
