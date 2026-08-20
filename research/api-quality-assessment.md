# Localize measured against discoverable / hard-to-get-wrong / documented

**Assessed 2026-08-20 against Localize 1.2.0** and 24 sibling packages.

## Why this rubric

[Report 1](localization-adoption.md) concluded that developers overwhelmingly take the unlocalized path even when a good localized one exists — 64:1 in Java, where the platform is fully CLDR-backed and free. The obvious explanation, "make it easier," is too glib. The usable-security literature that has actually studied this question ([Acar et al., IEEE S&P 2017](https://ieeexplore.ieee.org/document/7958576/)) found that *simplicity alone is not sufficient*: overly simple APIs produced functional failures, while comprehensive documentation improved correctness but sometimes worsened outcomes.

The shape that survives their evidence is three properties, not one:

1. **Hard to get wrong** — the obvious call produces the correct result, and mistakes are refused rather than absorbed.
2. **Discoverable** — a developer who does not know the function name can find it by guessing.
3. **Adequately documented** — every reachable thing is explained, and the explanations are true.

This report measures Localize against each. Every number is reproduced from the shipped package, not estimated.

## Scorecard

| Quality | Verdict | Principal gap |
|---|---|---|
| Hard to get wrong | **Strong**, one systemic defect | Unknown option keys are silently ignored — *open* |
| Discoverable | **Good**, gaps closed | `parse`/`to_string` asymmetry — *fixed in 1.3*; `usage-rules.md` now 9 of 25 packages |
| Adequately documented | **Strong**, gaps closed | Guide examples now gated in CI; every shippable non-macro function carries a `@spec` |

**Status.** Recommendations 2–6 were implemented on 2026-08-20; recommendation 1 remains open by choice, being a breaking change that needs its own design. Sections below record the original measurement and, where it has changed, what it is now.

---

## 1. Hard to get wrong

### The headline strength

With the process locale set to `:de`, the shortest call a developer can write is the localized one:

| Call | Result |
|---|---|
| `Localize.Number.to_string(1234567.89)` | `{:ok, "1.234.567,89"}` |
| `Localize.Date.to_string(~D[2026-03-22])` | `{:ok, "22.03.2026"}` |
| `Localize.List.to_string(["a","b","c"])` | `{:ok, "a, b und c"}` |

**There is no shorter, wronger option.** This is the exact inverse of the languages measured in report 1, where `f"{n:,.2f}"` and `printf("%f")` are both shorter *and* unlocalized. Localize has no equivalent of the trap where the lazy path silently produces US formatting.

This property is the single strongest thing about the library and it is currently undersold.

### Errors are refused, not absorbed

| Input | Result |
|---|---|
| `locale: :klingon` | `{:error, %Localize.InvalidLocaleError{}}` |
| `locale: "de"` (string) | `{:ok, "1.234"}` — accepted, correctly lenient |
| `locale: :de_DE` (POSIX form) | `{:ok, "1.234"}` — accepted, correctly lenient |
| `format: :enormous` | `{:error, %Localize.DateTimeUnresolvedFormatError{}}` |
| `Localize.Unit.new(1, "zorkmid")` | `{:error, %Localize.UnknownUnitError{}}` |
| `Localize.Territory.display_name(:QQ)` | `{:error, %Localize.UnknownTerritoryError{}}` |

Return shapes are consistent — `{:ok, value}` or `{:error, exception}` carrying a typed struct, per the project's own convention. Bad option *values* fail loudly.

### The defect: unknown option keys are silently dropped

| Call | Result | Should be |
|---|---|---|
| `Number.to_string(1234.5, fractional_digits: 2)` | `{:ok, "1,234.50"}` | ✓ |
| `Number.to_string(1234.5, fractionaldigits: 2)` | `{:ok, "1,234.5"}` | **error** |
| `Number.to_string(1234.5, currancy: :USD)` | `{:ok, "1,234.5"}` | **error** |
| `Date.to_string(d, formatt: :long)` | `{:ok, "Mar 22, 2026"}` | **error** |
| `List.to_string(l, styl: :or)` | `{:ok, "a and b"}` | **error** |
| `Unit.to_string(u, formt: :short)` | `{:ok, "3 meters"}` | **error** |

A developer who types `currancy: :USD` asks for a currency and receives a bare number, with **no signal of any kind**. The call succeeds. A test asserting "it returns `{:ok, _}`" passes. The defect surfaces as a wrong-looking number in production, at which point the typo is nowhere near the symptom.

This is systemic — it reproduces across Number, Date, List and Unit — and it is precisely the failure mode the security-API literature identifies as decisive: the API permits a silently wrong outcome.

---

## 2. Discoverable

### Two consistent families — the good part

A developer who learns one module can guess the rest:

| Family | Members | Shared verb |
|---|---|---|
| Formatters | Number, Date, Time, DateTime, Unit, List, Interval, Duration | `to_string/2` + `to_string!/2` |
| Display names | Currency, Territory, Language, Script, Calendar | `display_name/2` |

Thirteen of the sixteen entry-point modules fall into one of these two shapes. That is a genuinely guessable API.

### Gap 1 — you can format what you cannot parse

| Module | `to_string` | `parse` |
|---|---|---|
| `Localize.Number` | ✓ | ✓ |
| `Localize.Unit` | ✓ | ✓ |
| `Localize.Date` | ✓ | **✗** |
| `Localize.Time` | ✓ | **✗** |
| `Localize.DateTime` | ✓ | **✗** |
| `Localize.Duration` | ✓ | **✗** |

`Localize.Number.parse/2` exists, so the developer forms the rule "formatters parse too" — and then `Localize.Date.parse/2` does not exist. The capability *does* exist, in `Calendrical.Date.parse/2`, in a different package. Nothing in `Localize.Date` says so.

This is the highest-frequency discoverability failure available: parsing a date is not an exotic requirement.

**Fixed in 1.3.** `Localize.Date.parse/2`, `Localize.Time.parse/2` and `Localize.DateTime.parse/2` now delegate to `calendrical`, resolved at runtime because `calendrical` depends on Localize and cannot be depended on in return. When it is absent they return `%Localize.DependencyRequiredError{}` naming the package rather than failing obscurely, and each function's documentation names `calendrical` — the in-code signpost that was the real gap.

`Localize.Duration.parse/2` was *not* added: `Calendrical.Duration` does not exist, so there is nothing to delegate to. The original recommendation named four functions and should have named three.

### Gap 2 — package boundaries are invisible

The ecosystem is 24 packages. From inside `Localize`, there is no signpost to any of them. A developer needing person names, addresses, phone numbers, or date parsing has to already know that `localize_person_names`, `localize_address`, `localize_phone_number` and `calendrical` exist.

An ecosystem index does exist — [`elixir-localize/profile/README.md`](https://github.com/elixir-localize), the GitHub organisation landing page, naming 24 packages. But it is reachable only by someone already browsing the org, which is the wrong end of the funnel.

### Gap 3 — discovery aids are concentrated in the flagship

| Aid | Coverage |
|---|---|
| `README.md` | 23 of 24 |
| `guides/` | 9 of 24 (Localize has 17 files; most siblings have none) |
| `usage-rules.md` | **3 of 24** — `localize`, `localize_debug`, `localize_lua` |
| Claude Code skill | **1 of 24** — `localize` |
| MCP server | 1, covering the Localize API |

`usage-rules.md` is the Elixir ecosystem's convention for telling AI coding assistants how to use a library correctly. Given that a large and growing share of first contact with an API is now mediated by an assistant, three out of twenty-four is a discovery gap with compounding cost.

**Partly closed.** Six more were written on 2026-08-20 — `calendrical`, `localize_web`, `localize_sql`, `localize_person_names`, `localize_phone_number`, `localize_address` — taking coverage to **9 of 25**.

One thing that nearly made the exercise pointless: none of the six listed the file in its package `files` list, so all six would have published without it. Verified by building each tarball and checking the file is inside. Anyone adding `usage-rules.md` to a package should check the same thing — writing the file is not the same as shipping it.

---

## 3. Adequately documented

### Coverage is near-total

Measured from the compiled docs chunks of the shipped package:

| Metric | Value |
|---|---|
| Modules | 271 (136 public, 128 `@moduledoc false`) |
| Public functions | 1,540 |
| Documented | 750 |
| `@doc false` (internal) | 536 |
| Undocumented | 254 |
| **Undocumented in a *public* module** | **3** |

The 254 undocumented functions are almost entirely inside `@moduledoc false` modules and never appear in hexdocs. The genuine public gap is **three functions** in `Localize.Gettext` — `handle_missing_translation/5`, `handle_missing_plural_translation/7`, `handle_missing_bindings/2`.

**Correction.** The original text said these "should carry `@doc false` or a line each". They should not. All three are `Gettext.Backend` behaviour callbacks, generated by `use Gettext.Backend` — `Gettext.Backend.behaviour_info(:callbacks)` lists them. Every Gettext backend in the ecosystem has the same three undocumented, and overriding generated functions to attach `@doc false` would be churn for a cosmetic metric. Left alone deliberately.

By the measure that matters — *can a user reach something undocumented?* — coverage is effectively complete. Few libraries of this size can say that.

### Verification is strong where it is automated

| Artefact | Count | Verified in CI? |
|---|---|---|
| Doctests | 1,037 | ✓ every run |
| Tests | 30,000+ | ✓ every run |
| Guide / README `iex>` examples | **631** | **✗ none** |

### Gap 1 — 631 guide examples have no CI coverage

The guides are the front door: 17 files, and by volume more example code than the module docs. Nothing checks them. The established practice is to execute them and compare — 589 of 631 match, with the remaining 42 being known harness artefacts, not defects (the mismatches are inspect-notation differences, docs showing an equivalent expression rather than a literal, and references to other packages). But that sweep is run by hand when someone thinks to.

This is not an argument for restructuring the guides so `doctest_file/1` compiles them — that would mean rewriting correct, readable documents to suit a tool, and bindings that cross fence boundaries make it invasive. The sweep should become a test that pins the counts.

**Closed.** `test/guides_examples_test.exs` runs every example as one test per file, and all 18 files pass. Three things made it low-noise enough to be a gate rather than a nuisance:

* **Compare terms, not strings.** `[text: "here"]` and `[{:text, "here"}]` are the same value inspected two ways. Evaluating the documented text and comparing terms also removes map key ordering and whitespace as sources of false failure.
* **Decode both escape notations.** A guide writing `\uXXXX` and `inspect/1` emitting the character itself are the same codepoint.
* **Reset the process locale per file, not per example.** A guide that narrates `put_locale(:de)` expects it to hold for the examples that follow, exactly as a reader following along would see.

Eight examples remain excused, each with its reason recorded in the test: references to other packages, `:observer` in a headless run, and examples documented as an equivalent expression rather than a literal. Not a single guide was edited to make this pass.

### Gap 2 — missing `@spec`, and a correction to the count

The original figure, "116 documented functions carry no `@spec`", counted every module including internal ones. Restricted to functions a user can actually reach it was **47 across 11 modules**, and of those **37 were in `Localize.Data.*`**, which compiles only in `:dev` as part of the locale-data pipeline and never enters the published package.

The real shippable gap was **ten functions**. Five were worth specifying and now carry one: the four arithmetic operators in `Localize.Unit.Operators` and `Localize.Nif.nif_collation_cmp/10`.

The remaining five are all **macros** — `__using__/1` twice, and the `sigil_M/2`, `sigil_t/2` and `sigil_l/2` sigils — where `@spec` is legal but not idiomatic and carries no useful information.

So: **every documented, shippable, non-macro function in the public API now has a `@spec`.** Dialyzer remains at zero errors with them in place.

The lesson for the metric rather than the code: a raw count across all modules overstated the gap by an order of magnitude. Measure the surface a user can reach.

---

## Recommendations

Ordered by leverage, with the phase in mind: the library is feature-complete and the effort is moving to documentation, video and conference talks.

### 1. Reject unknown option keys — *highest leverage, "hard to get wrong"* — **OPEN**

The one systemic defect, and the one the literature says matters most. Validate option keys at the public boundary and return `{:error, %Localize.UnknownOptionError{}}` naming the unknown key. Include a suggestion — `String.jaro_distance/2` against the known keys turns `currancy` into *"unknown option :currancy. Did you mean :currency?"* for a few lines of code.

This is a breaking change: code that today passes a typo and silently succeeds would start failing, which is the point. Ship it as 2.0, or land it behind `strict_options: true` for a release first and flip the default at the major.

The recommendation is stronger than "add validation" — it is that **this becomes a talking point**. "The library refuses your typo" is a demo that takes fifteen seconds and lands with an audience that has been bitten.

### 2. Close the parse/format asymmetry — **DONE** (1.3)

Add `Localize.Date.parse/2`, `Localize.Time.parse/2`, `Localize.DateTime.parse/2` and `Localize.Duration.parse/2`, delegating to `Calendrical` where it already does the work — exactly as `Localize.Unit.parse/2` is a thin delegation today. If a delegation is unacceptable for dependency reasons, the minimum is a `@doc` in each module naming where parsing lives.

The rule a developer forms after seeing `Number.parse/2` should hold everywhere.

### 3. `usage-rules.md` in every package — **PARTLY DONE** (9 of 25)

Three of twenty-four. Each file is short and mostly mechanical: what the package is for, the two or three calls that matter, the mistakes to avoid. For libraries whose first contact is increasingly an AI assistant reading the package, this is now documentation for the primary reader.

Start with the packages most likely to be reached for cold: `calendrical`, `localize_web`, `localize_sql`, `localize_person_names`, `localize_phone_number`, `localize_address`.

### 4. Pin the guide examples in CI — **DONE**

Add the extraction sweep as a test asserting the matched count does not regress from 589/631, with the 42 known artefacts enumerated so a new mismatch is visibly new. **Do not restructure the guides to fit `doctest_file/1`.** This converts a manual release-review step into a gate, and it protects the artefacts most visible to newcomers.

### 5. `@spec` the remainder — **DONE**; the Gettext callbacks — **withdrawn**

Five specs added; five macros left alone. The Gettext half of this recommendation was withdrawn on inspection — see the correction in section 3.

### 6. Surface the ecosystem from inside the flagship — **ALREADY DONE**

Already present: Localize's README carries an "Additional Localize libraries" section covering the family by problem area. The recommendation was written without checking, and the genuine gap it was reaching for — a signpost *in the code*, where a developer looking for `Localize.Date.parse/2` actually is — was closed by recommendation 2 instead.

---

## For the documentation, video and talk phase

Three assets fall out of this assessment directly.

**The opening demo writes itself.** Report 1 established that Python, C and JavaScript all make the unlocalized path shorter than the localized one, and that Java developers bypass a good CLDR API 64:1. Localize's answer is a three-line demo: set the locale, call `to_string`, watch it change. *The shortest thing you can type is the correct thing.* That is a stronger opening than any feature list, and it is a claim the audience can check.

**The "why should I care" is measured, not asserted.** [Report 2](accept-language-honouring.md) has 17 of 18 global brands ignoring an explicit language preference, with Samsung redirecting a German request to an Australian site. That is a concrete, checkable grievance most of the audience has personally experienced — better motivation than an abstract appeal to correctness.

**Be honest about the ergonomics claim.** Report 1 marks "the binding constraint is ergonomics" as a hypothesis with four named confounds. A talk that presents it as a hypothesis and says what would settle it is more credible than one that overstates it — and this audience contains people who will check.

The gaps above are worth closing *before* the talks rather than after, for one reason: every one of them is something an interested developer hits in the first hour. A conference talk's yield is measured in people who try the library that evening, and the typo that silently succeeds and the `Date.parse` that does not exist are both first-hour experiences.
