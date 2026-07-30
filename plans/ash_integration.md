# Underpinning Ash with Localize

An assessment of how Ash Framework (v3.30.1, commit `27af998`) could take on intrinsic localization, and what Localize would need to provide.

## Summary

**Ash already ships Localize.** `ash_money`'s committed `mix.lock` contains `localize 0.41.0`, because `ex_money` 6.x is Localize-backed — the migration off ex_cldr is done and published on hex. The proposal below is therefore not "adopt a new dependency"; it is "use, deliberately, the one that is already in the tree."

What Ash lacks is a presentation layer. It has a rich, 54-callback type system for getting values *in* and *stored*, and nothing at all for getting them *out* in front of a human. Money displays correctly only because `ex_money`'s struct implements `String.Chars` and reaches into the process locale — a side effect of a protocol, not a contract Ash knows about. Every other consumer improvises: `ash_admin` falls back to `to_string/1` and re-implements gettext's `%{var}` interpolation by hand, `ash_phoenix` declines the problem entirely, and the serializers emit canonical values with no display path at all.

That absence is the opportunity. Localization in Ash is not a matter of adding a `:localized_string` type; it is a matter of giving Ash the two boundary callbacks it is missing — render and parse — and standardizing where the locale lives. `Localize.Chars` is already `{:ok, binary} | {:error, exception}` over precisely the set of types Ash treats as builtins, which is close to a drop-in fit for the render side.

Three things make this timely. Ash's error-message pipeline was built recently and is gettext-shaped in a way that provably cannot produce correct plurals or locale-correct numbers. `Ash.Scope` already uses `locale:` as its canonical documentation example without anything in Ash consuming it. And across all 61 repositories in the `ash-project` organisation there is no i18n package, and zero occurrences of "i18n", "internationalization" or "localization" in Ash's `documentation/` tree.

## The Localize ecosystem

The pieces an Ash integration would draw on already exist as separate, published packages. This matters for the proposal below, because most of what Ash needs is integration work rather than new capability.

| Package | Provides | Relevant to |
|---|---|---|
| `localize` | CLDR core — numbers, dates, units, lists, collation, MF2, 766 locales, no compile-time backend | everything |
| `calendrical` | Locale-aware date/time/interval **parsing**, 17 CLDR calendar systems, fiscal years | `cast_input`, non-Gregorian types |
| `localize_ecto` | PostgreSQL ICU `COLLATE` via CLDR language matching, collation migrations, text search config | `ash_postgres`, `ash_sql`, sorting |
| `localize_web` | `Accept-Language` / session / cookie / TLD locale plugs, localized routing (`~q`), localized `<select>` helpers for currency, territory, locale, unit, month | `ash_phoenix`, `ash_admin` |
| `localize_number_inputs`, `localize_datetime_inputs`, `money_input` | LiveView components that format *and parse* in-locale, multi-calendar date pickers | `AshPhoenix.Form`, `ash_admin` forms |
| `localize_units_sql` | Composite storage for `Localize.Unit` values, as `ex_money_sql` does for money | a `:unit` Ash type |
| `ex_money` 6.x | Money, Localize-backed | `ash_money` (already) |
| `localize_lua` | `localize.*` table for Luerl scripts | `ash_lua`, and `ash_cms`, which the package already names |
| `intl` | `Intl`-shaped ergonomic API | `ash_typescript` parity |

## Findings

### 1. There is no display callback on `Ash.Type`

`Ash.Type` declares callbacks for `cast_input`, `cast_stored`, `dump_to_native`, `dump_to_embedded`, `cast_from_embedded`, `apply_constraints`, `cast_atomic`, `handle_change`, `prepare_change`, `load`, `rewrite`, `generator` and more — and `describe/1`, which documents the *type*, not a value. Nothing renders a value for a human.

The consequences are visible downstream. `ash_admin` reduces every attribute to `to_string/1` (`lib/ash_admin.ex:48`, `lib/ash_admin/components/resource/show.ex:605`), so a `:decimal` price renders `1234.5` in every locale on earth. `ash_phoenix` contains no reference to gettext or translation anywhere in `lib` — the responsibility is left entirely to the application.

This is the single highest-leverage change, and it is small.

### 2. Input parsing is locale-blind

`cast_input/2` for `:integer`, `:float`, `:decimal`, `:date` and `:datetime` delegates to `Ecto.Type.cast/2`. A German user typing `1.234,5` into a form bound to a `:decimal` attribute gets a cast error, because Ecto reads `.` as the decimal separator. A user typing `10/07/2025` gets whatever Elixir's ISO-8601 parser makes of it, with no reference to whether their locale is day-first or month-first.

Localization is usually treated as an output concern. It is at least as much an input concern, and getting it wrong here produces validation errors that users cannot act on — the field looks correct to them.

Both halves are already solved outside Ash. `Localize.Number.Parser.parse/2` handles numbers and `Calendrical.parse/2` handles dates, times, datetimes and intervals, dispatching to the right sub-parser and honouring the locale's CLDR patterns:

```elixir
iex> Calendrical.parse("10/07/2025", locale: :"en-GB")
{:ok, ~D[2025-07-10]}

iex> Calendrical.parse("10/07/2025", locale: :"en-US")
{:ok, ~D[2025-10-07]}

iex> Calendrical.parse("16. Mai 2026", locale: :de)
{:ok, ~D[2026-05-16]}

iex> Localize.Number.Parser.parse("1.234,5", locale: :de)
{:ok, 1234.5}
```

The `10/07/2025` pair is the case worth showing to the Ash team: same input, same type, two locales, two different correct dates, and no way for Ash to express the difference today. `Calendrical.parse/2` also takes `as: :map` to return the unresolved partial (`%{month: 5, day: 5}` for `"May 5"`), which is what a form library wants when it needs to distinguish "user omitted the year" from "user meant this year".

### 3. The error-message pipeline cannot localize correctly

Ash's mechanism is a marker macro plus a mix task. `Ash.Gettext.error_message/1` returns its argument unchanged at runtime and exists so `mix ash.gettext.extract` can scan for it; messages land in `priv/gettext/ash.pot`, applications copy that file with `mix ash.gen.gettext`, and render via `Gettext.dgettext(MyApp.Gettext, "ash", msg, vars)`.

The workflow is sound. The message format is not. Three defects are structural, not oversights:

* **No plural selection — verifiably, in every locale.** Gettext selects a plural form from a variable named `count`. There are **zero occurrences of `count` in Ash's shipped `priv/gettext/ash.pot`**. Ash's counted messages name their variable after the constraint instead: `"at least %{at_least} of %{keys} must be present"` (`lib/ash/resource/validation/present.ex:185`), `"must have no more than %{precision} significant digits"`, `"Expected %{expected_length} elements, got %{value_length}"`. `ash_admin` does implement the correct pattern — `if count = opts[:count], do: Gettext.dngettext(...), else: Gettext.dgettext(...)` (`lib/ash_admin/components/core_components.ex:646`) — but that branch is dead code for Ash errors, because the count is never called `count`. So every Ash error message today renders through singular-only `dgettext`, and Russian, Polish and Arabic get one form where they need three, three and six. Fixing this within gettext means renaming variables at every call site and nominating a count per message; MF2 selects on any variable by name.

* **Interpolated values are not formatted.** `%{max}` is substituted with `to_string(value)`. Ash's own `decimal.ex` and `float.ex` pass raw numbers into `"must be less than or equal to %{max}"`, so a `de-DE` user reads `1234.5` where they expect `1.234,5`. `ash_admin` re-implements this substitution by hand (`lib/ash_admin/components/resource/form.ex:363`), with the same `to_string/1`.

* **Lists are joined with a hard-coded English comma.** `lib/ash/type/atom.ex:60` and `lib/ash/resource/validation/present.ex:186` both call `Enum.join(list, ", ")`, and the value is baked into the interpolation variable before the translator ever sees it — so no `.po` file can correct it. CLDR list patterns are locale-specific in both separator and final conjunction.

There is a fourth, smaller friction: Ash ships its template under the `ash` domain while `ash_admin` renders under `errors`, which is why `mix ash.gen.gettext --domain errors` exists to merge one into the other.

MessageFormat 2 addresses all of it in one move, and Localize implements MF2 with a `~M` sigil that validates at compile time, a `mix format` plugin that canonicalises messages so gettext keys stay stable, and gettext extraction. Taking Ash's own message verbatim and re-expressing it in MF2:

```
.input {$at_least :integer}
.input {$keys :list}
.match $at_least
  one {{at least {$at_least} of {$keys} must be present}}
  *   {{at least {$at_least} of {$keys} must be present}}
```

Both branches hold the same untranslated English, to isolate what MF2 fixes *before* a translator touches anything:

```elixir
iex> Localize.Message.format(msg, %{"at_least" => 3, "keys" => ["name", "email", "phone"]}, locale: :en)
{:ok, "at least 3 of name, email, and phone must be present"}

iex> Localize.Message.format(msg, %{"at_least" => 3, "keys" => ["name", "email", "phone"]}, locale: :de)
{:ok, "at least 3 of name, email und phone must be present"}

iex> Localize.Message.format(msg, %{"at_least" => 1234, "keys" => ["name", "email", "phone"]}, locale: :de)
{:ok, "at least 1.234 of name, email und phone must be present"}
```

The list gains a locale-correct conjunction and the number gains locale-correct grouping without a single word being translated. Neither is reachable from a `.po` file today at any level of translator effort, because `Enum.join/2` has already run.

Plural selection then works on any named variable, not one called `count`:

```elixir
iex> for n <- [1, 3, 5, 21], do: Localize.Message.format(ru_msg, %{"at_least" => n}, locale: :ru)
[{:ok, "нужно указать минимум 1 поле"},     # one
 {:ok, "нужно указать минимум 3 поля"},     # few
 {:ok, "нужно указать минимум 5 полей"},    # many
 {:ok, "нужно указать минимум 21 поле"}]    # one — 21 takes the singular in Russian
```

All output above was executed against Localize `1.0.0-rc.6`, not composed by hand.

### 4. Locale is already in Ash's vocabulary, with no semantics attached

`Ash.Scope`'s canonical example is, verbatim:

```elixir
defmodule MyApp.Scope do
  defstruct [:current_user, :current_tenant, :locale]

  defimpl Ash.Scope.ToOpts do
    def get_context(%{locale: locale}), do: {:ok, %{shared: %{locale: locale}}}
  end
end
```

`Ash.Query`'s docs use `Ash.Query.put_context(:locale, "en_US")` as their illustration too. So the plumbing exists and the idiom is already documented: scope → `context.shared` → `Ash.Resource.Calculation.Context.source_context`. Nothing in Ash reads it. Standardizing the key and its type is a documentation-and-conventions change more than a code change.

### 5. Async work silently loses the locale

`Ash.ProcessHelpers.get_context_for_transfer/1` transfers **only tracer span context** — that is the entire body of the function. Localize stores the current locale in the process dictionary (`Process.put(:localize_locale, tag)`, `lib/localize.ex:367`), as does ex_cldr and as does Gettext.

So any value formatted inside an async calculation, a parallel relationship load, or anything routed through `Ash.ProcessHelpers.task_with_timeout/5` will format in the **application default locale**, not the request locale. The same applies to `ash_oban` jobs and Reactor steps. This is a live latent bug for `ash_money` today, not a hypothetical.

There are two fixes and both are worth doing: `ash_localize` should never read the process locale internally, always resolving from context; and `get_context_for_transfer/1` should carry the locale so that *user* code inside async work behaves.

### 6. Sorting is not linguistic — and this is fixable in the data layer, not just at runtime

`Ash.Sort` supports `:asc`, `:desc` and the four nils variants. There is no collation concept. `Ash.Sort.runtime_sort/3`'s own documentation concedes the problem and treats it as unfixable:

> Keep in mind that it is unrealistic to expect this runtime sort to always be exactly the same as a sort that may have been applied by your data layer. This is especially true for strings.

It is fixable. `localize_ecto` resolves a language tag to the best-matching PostgreSQL ICU collation using the CLDR Language Matching algorithm and emits a `COLLATE` clause inside an ordinary Ecto query:

```elixir
from p in Product, order_by: collate(p.name, "sv")
from p in Product, where: collate(p.name < "münchen", "de")
from p in Product, order_by: collate(p.name, collation: "german_phonebook")
```

Unknown locales degrade gracefully (`"zh-TW"` → `zh-Hant-x-icu`), and BCP 47 collation types such as `de-u-co-phonebk` resolve to collations created once via `Localize.Ecto.Migration.create_collation/2`.

This matters more than the runtime-sort fix, because `ash_postgres` and `ash_sql` are Ecto-based: collation belongs in the generated SQL, where it composes with indexes, keyset pagination and large result sets. A runtime sort cannot do any of that — it can only reorder the page it has already fetched, which is the wrong answer whenever the sort determines *which* rows are on the page. So the recommendation inverts: the primary integration is `ash_postgres` emitting `COLLATE`, and `Localize.Collation.sort/2` at runtime is the fallback for non-SQL data layers, not the main event.

`Localize.Ecto.TextSearch` additionally supplies per-locale full-text search configuration, which is the same class of problem one layer up.

### 7. `Ash.Type.Enum` labels work, via a documented workaround the user has to write

This is weaker than it first appears, and the history is instructive. `label/1` and `description/1` resolve against a compile-time map, so the obvious `label: gettext("Open")` silently freezes the default locale at compile time. A user reported exactly that in [ash#2172](https://github.com/ash-project/ash/issues/2172); Zach Daniel's reply was "Yes, good call. Someone else just ran into this and I meant to fix it" — so at least two people hit it independently.

The fix landed, and `lib/ash/type/enum.ex:114-139` now documents a working two-pass pattern: use the Gettext macro in `values` so the msgid is extracted at compile time, then override `label/1` to translate at runtime.

```elixir
use Ash.Type.Enum, values: [open: [label: gettext("Open")], ...]

def label(value) do
  with label when is_binary(label) <- super(value),
    do: Gettext.gettext(MyApp.Gettext, label)
end
```

So enum labels are localizable today. What remains is real but modest: the override is per-enum boilerplate the user writes by hand, `description/1` gets no worked example despite having the same trap, and the pattern is invisible unless you read that docs section. A locale-aware arity would remove the boilerplate, which is worth proposing — but as ergonomics, not as a missing capability. I originally scored this as a gap; it isn't one.

### 8. `ash_money` already runs on Localize, and its lock file has a stale ex_cldr entry

`ex_money` 6.x depends on `{:localize, "~> 0.27"}` and nothing from the ex_cldr family — that is the published 6.1.1 release on hex, not a branch. `ash_money` requires `{:ex_money, "~> 6.0"}`, so its committed `mix.lock` pins `localize 0.41.0`. Every Ash application using money today already has Localize resolved, loaded and formatting its currency values.

The lock also still carries `ex_cldr_currencies 2.17.0`, which nothing in the tree requires — `ex_cldr` itself is not even present. It is a dead entry left from the pre-migration ex_money 5.x days, cleared by:

```bash
mix deps.unlock --unused
```

That one-line cleanup is a good opening move with the Ash team: it is trivially verifiable, costs them nothing, and makes the point that the Localize relationship is already real rather than prospective.

Two things follow. First, the version pin needs attention — `ex_money` asks for `~> 0.27` and resolves to 0.41, while Localize is at `1.0.0-rc.6`; aligning that is a release-coordination task across `ex_money`, `ash_money` and Localize, and it should happen before any of this is proposed as a platform.

Second, `AshMoney.Types.Money` accepts formatting options in *type constraints*:

```elixir
attribute :charge, :money do
  constraints: [ex_money_opts: [no_fraction_if_integer: true, format: :short]]
end
```

Display configuration living in constraints is a reasonable response to there being nowhere else to put it, but it binds presentation to the schema. The same attribute cannot render as `:short` in a summary table and long-form on a detail page. A display callback taking runtime options fixes that; type constraints then set *defaults* rather than *the* format. `ash_money` is the worked example for what a display callback should look like, precisely because it is the one type that already half-has one.

## Prior art: what the Ash team has already said

There is no `ash_localize`. It does not exist in the `ash-project` organisation (61 repositories, none private that I can see), it is not on hex, and a GitHub-wide code search for `AshLocalize` and `ash_localize` returns no Elixir hits other than this document. A private repository would return the same 404 as a nonexistent one, so treat that as "no public evidence" rather than proof.

The issue history is more useful than a package would have been, because it shows the demand is already articulated by users and acknowledged by the maintainers.

[ash#1771 — "Generate gettext file for various error messages"](https://github.com/ash-project/ash/issues/1771) is the origin of `Ash.Gettext` and `mix ash.gettext.extract`. It opens with "Being able to translate error messages into different languages is quite important as most of the world speaks another language, natively", asks for humanized field names as well, and the comments record the workarounds people built in the meantime — a community blog post on wrapping Ash validation errors in Gettext, and this, from `allenwyma`:

> I've just been overwriting some and including my own Gettext inside. Probably not good cause now we have the web mixed with the domains.

That is a user independently deriving the argument for Phase 1. Reaching for a web-layer Gettext backend inside domain code is exactly the coupling that a locale on `Ash.Scope` and a display callback on `Ash.Type` are there to prevent. It is worth quoting back.

[ash#2172](https://github.com/ash-project/ash/issues/2172) is the enum label trap in finding 7, with a maintainer confirming multiple people hit it.

The pattern across both: Ash's localization surface has been built reactively, one accepted patch at a time, in response to users who needed something specific. Nobody has yet proposed the shape it should have. That is the opening — not a missing package, but a missing architecture, with a documented trail of people asking for it.

## Architectural principle

**Localization is a boundary concern, not a storage concern.** The data layer stores canonical values — `Decimal`, `Date`, UTC `DateTime`, an atom currency code. Localization applies on the way out (render) and on the way in (parse). Serialization formats aimed at machines — JSON:API, GraphQL scalars, `ash_typescript` — must keep emitting canonical values; localized display is an *additional*, explicitly-requested field, never a substitution.

Conflating the two is how you end up with `"1.234,5"` in a database column. Any proposal that makes an attribute *store* a localized string should be rejected. The one legitimate exception is a genuinely translated content field (a product name per language), which is a relationship-modelling problem, not a type problem, and should be kept out of scope.

## Proposal

### Phase 1 — Ship `ash_localize` with zero changes to Ash

Everything here is possible against Ash 3.30 as it stands, which means it can be validated with real applications before asking the Ash core team to accept anything.

**Locale resolution.** A single, cached entry point that reads the Ash context and falls back sensibly:

```elixir
AshLocalize.locale(context)   # context.shared.locale -> validated %Localize.LanguageTag{}
```

backed by `Localize.validate_locale/1`, which is ETS-cached at roughly 1µs after first call. Add `AshLocalize.Scope` as a ready-made scope implementation. The discovery half needs no new code — `localize_web` already ships `Localize.Plug.PutLocale` with a `:from` option that checks the accept-language header, query params, URL params, body params, cookies, the route, the session and the hostname TLD in a configurable order, plus `Localize.Plug.PutSession` for persistence into LiveView. `ash_localize` only has to bridge the resolved locale into the Ash scope.

**A drop-in error translator.** `AshLocalize.translate_error/1` matching the shape `AshPhoenix.Form` expects, rendering Ash's existing msgids through `Localize.Message.format/3` with MF2 translations. This is the fastest visible win: correct plurals, locale-formatted interpolations and CLDR list joins, with no change to Ash and no change to application code beyond one config line. Ship MF2 translations for Ash's shipped `.pot` messages for a first tranche of locales.

**Display helpers.** `AshLocalize.display/3` over a record and field, dispatching through `Localize.Chars` using the attribute's type and constraints. Plus `AshLocalize.Calculation.Display` so a resource can declare a display field where that is genuinely wanted:

```elixir
calculate :price_display, :string, {AshLocalize.Calculation.Display, field: :price, format: :currency}
```

The calculation reads `context.source_context[:locale]`, so it is correct under async — which is the point.

**New types that genuinely belong.** These are canonical-storage types whose *display* is inherently locale-dependent, which is exactly the case Ash has no answer for:

* `:language_tag` — a validated locale as an attribute. User language-preference fields are ubiquitous and currently modelled as a free string or a hand-maintained enum. `Localize.validate_locale/1` gives canonicalization, likely-subtag resolution and validation against `:supported_locales`, and `Localize.Chars` renders it as an endonym.
* `:unit` — a measurement, stored composite as `{value, unit}` exactly as `ash_money` stores `{amount, currency}`, rendered via `Localize.Unit.to_string/2`. `localize_units_sql` already provides the composite storage, mirroring `ex_money_sql`, so this follows `ash_money`'s existing pattern almost exactly — including its `ash_postgres` extension shape. Ash has no measurement type at all today.
* `:currency_code` and `:territory` — validated codes with localized display names and, for territories, flags.
* A display path for the existing `:duration` type via `Localize.Duration`, which joins parts with CLDR unit list patterns per ECMA-402.

**Collation.** An `ash_postgres` extension emitting `COLLATE` via `localize_ecto` for sortable string attributes, with `Localize.Collation.sort/2` as the runtime fallback for other data layers. See finding 6 — this is the piece with the largest gap between "obvious" and "correct", because runtime sorting cannot fix a paginated query.

**Forms.** This is where the ecosystem pays off most visibly and where I would expect the Ash team to engage fastest. `ash_admin` generates forms from resource attributes; `localize_number_inputs` and `localize_datetime_inputs` supply LiveView components that format *and* parse in-locale, and `localize_web` supplies localized `<select>` helpers for currency, territory, locale, unit and month. Mapping Ash attribute types onto those components gives a multilingual admin UI — including multi-calendar date entry — largely by wiring rather than by writing.

### Phase 2 — Upstream the callbacks

Once Phase 1 has users, four changes to Ash are worth proposing. Each is small and independently useful even to applications that never install Localize.

**A display callback on `Ash.Type`:**

```elixir
@callback to_display(term(), constraints(), opts :: Keyword.t()) ::
            {:ok, String.t()} | {:error, term()}
```

Optional, defaulting to `{:ok, to_string(value)}`, so nothing breaks. `ash_localize` then supplies implementations for the builtins, and `ash_admin` / `AshPhoenix` / `ash_typescript` get one call site instead of three hand-rolled ones. The signature is deliberately the same shape as `Localize.Chars.to_string/2`.

**A parse callback**, the input mirror: `cast_display/3`, tried before `cast_input/2` when a locale is present in context, delegating to `Localize.Number.Parser.parse/2` and `Calendrical.parse/2`. This is what makes `1.234,5` and the `10/07/2025` ambiguity from finding 2 resolve correctly instead of erroring or silently picking the wrong month.

**Locale in `get_context_for_transfer/1`**, so async work inherits it. A few lines, and it fixes a class of bug that is otherwise invisible until someone reports that their invoice PDF is in English.

**`:locale` on `Ash.Sort.runtime_sort/3`**, routing string comparison through a pluggable collator — with the `ash_postgres` `COLLATE` path from finding 6 as the more consequential half of the same change.

Two smaller ones worth raising at the same time: a locale-aware arity on `Ash.Type.Enum.label/1`, and — the one genuinely delicate item — whether Ash's shipped messages should migrate from gettext-style `%{var}` to MF2. That migration is mechanical for the msgids but changes the translator workflow, so it should be opt-in per domain and probably lags everything else.

### Phase 3 — Calendars, and the rest of the ecosystem

Non-Gregorian calendars are the capability with no competing answer anywhere in Elixir, and the one that would most clearly distinguish Ash. `calendrical` implements 17 CLDR-aligned calendar systems — Persian, Hebrew, four Islamic variants, Japanese imperial eras, Buddhist, ROC (Minguo), Indian National, Ethiopic, Chinese, Korean Dangi and more — with `Date.shift/2` arithmetic working across all of them, plus fiscal-year calendars for around 50 territories.

For Ash this means a `:date` attribute whose *storage* stays an ISO `Date` while its display and input follow the user's calendar. An application serving Thailand, Japan, Saudi Arabia, Iran or Israel currently has to build that itself. `localize_datetime_inputs` already renders multi-calendar date pickers against `calendrical`, so the client half exists.

The fiscal-year support is a quieter but genuinely commercial angle: reporting resources that need "Q3" to mean the right three months in the right territory.

Two smaller items belong here. `localize_lua` exposes a curated, sandboxed `localize.*` table to Luerl scripts — relevant to `ash_lua`, and the package already names `ash_cms` as a consumer, so there is an existing Ash-adjacent integration to point at. And `intl` provides an `Intl`-shaped API that would give `ash_typescript` a way to keep client and server formatting consistent.

Money is **not** a phase-3 item, because it is already done — see finding 8. The work there is version alignment, not architecture.

## What is genuinely missing

Being straight about the gaps, since the Ash team will ask:

* **Version alignment.** `ex_money` pins `localize ~> 0.27` and resolves to 0.41; Localize is at `1.0.0-rc.6`. Coordinating a 1.0 across `ex_money`, `ex_money_sql`, `calendrical`, `localize_ecto`, `localize_web` and the inputs family is the real prerequisite, and it is release management rather than design.
* **Package sprawl.** Ten-plus packages is a lot of surface for a framework team to evaluate. An `ash_localize` that depends on the right subset and documents one coherent story is as much a packaging exercise as an engineering one.
* **Process-dictionary locale.** Correct and conventional for Elixir, but it means every framework that spawns processes must opt in to carrying it — see finding 5. This is a constraint the integration has to respect explicitly, not a defect.
* **`localize_ecto` is PostgreSQL-only.** Fine for `ash_postgres`, no answer for `ash_sqlite` or `ash_mysql`, where the runtime-collation fallback is all there is.
* **No date/time parsing in Localize core.** It lives in `calendrical`, which is the right place, but it means the input story requires a second dependency rather than falling out of `localize` alone.

## Risks

* **Ash moves fast and guards its core.** A 54-callback behaviour is already a lot to implement; adding two more, even optional ones, needs a clear argument that they belong in core rather than in an extension. The argument is that display is not optional in a framework that ships an admin UI, a form library and three serializers — it is currently just implicit and inconsistent.
* **Localize is pre-1.0.** Currently `1.0.0-rc.6`, while the tree resolves 0.41 through `ex_money`. Ash will not take a hard dependency on an rc, which is fine — Phase 1 needs no dependency from Ash at all, and Phase 2's callbacks are Localize-agnostic by design. But the version story needs to be tidy before the conversation, not during it.
* **The MF2 migration is the one breaking-shaped change.** Keep it opt-in and last.
* **Serialization boundaries must hold.** The most likely way this goes wrong is a well-meaning PR that makes `ash_json_api` emit localized numbers. The principle needs stating in the guides, loudly, before the code lands.
* **Breadth can read as sprawl.** Presenting ten packages at once invites "this is a lot of surface area to depend on". Lead with one problem and one fix.

## What to take to the Ash team first

The error-message translator, framed as a follow-up to [ash#1771](https://github.com/ash-project/ash/issues/1771) rather than as a new proposal. That issue asked for translatable error messages and got the extraction half; the rendering half is still singular-only, and I verified Ash's `.pot` contains no `count` variable anywhere, so no amount of translation effort fixes plurals within gettext. It needs no change to Ash, it demonstrates in a screenshot, and it answers a request the Ash team has already accepted in principle.

Two things to pair with it:

* The `mix deps.unlock --unused` observation on `ash_money` — Localize is already in your dependency tree; here is a dead ex_cldr entry to prove how long it has been true.
* `allenwyma`'s comment on #1771 about web concerns leaking into domain code, as the motivation for putting locale on `Ash.Scope` instead of a Gettext backend.

Together those make the opening point without asking for anything: you already ship Localize, your users have already asked for this twice, and here is the piece that cannot be built the current way. Everything else follows more easily once that is on the table.
