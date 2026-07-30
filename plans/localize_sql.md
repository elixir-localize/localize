# localize_sql — rename, merge, and shared SQL machinery

Consolidate all SQL/Ecto-adjacent work behind one foundational package, `localize_sql`, and have the money serialization package build on it instead of duplicating the plumbing.

## Goal

1. Rename `localize_ecto` → `localize_sql` (Ecto ≠ a database; the package is about SQL databases: collations, serialization, migrations).
2. Fold `localize_units_sql` into `localize_sql`.
3. Extract the generic `{tag, decimal}` SQL machinery into `localize_sql`; refactor `ex_money_sql` to depend on `localize_sql` and delegate to it, keeping its public API frozen.

"One place for the SQL plumbing" — without dragging `ex_money` into `localize_sql` (money sits *above* localize; folding it in would force every collation/unit user to pull all of ex_money).

## Locked decisions

- Package/app renamed to `localize_sql`; the `Localize.Ecto.*` module namespace and the `mix localize.ecto.audit` task name are **kept** (rename package only).
- Unit-serialization Ecto types keep their names: `Localize.Unit.Ecto.{Composite,Map}.Type`, `Localize.UnitWithUsage.Ecto.{Composite,Map}.Type`.
- Shared machinery lives at `Localize.Ecto.TaggedDecimal.*`.
- `ex_money_sql` stays its own package (own consumers e.g. `tradex`, own release cadence tied to `ex_money`); it depends on `localize_sql`. Money keeps `Money.Ecto.*`.

## Scope: five type families

`localize_sql` is the one place for SQL-backed localized types. Address, phone number and ranges join money and units.

| Family | Storage | Operations |
|---|---|---|
| Money (`ex_money_sql`) | composite `money_with_currency` / jsonb | tag-guarded `sum`, `avg`, `min`, `max`; `+`, `-`, unary `-` |
| Unit (`localize_sql`) | composite `cldr_unit`, `cldr_unit_with_usage` / jsonb | same four aggregates (previously `sum` only) |
| Address (`localize_address`) | **jsonb default**, composite optional | none arithmetic; sorts/searches via existing ICU collation + text search |
| Phone number (`localize_phonenumber`) | **E.164 text only** (one indexed column) | uniqueness/equality; parse on load, format on dump |
| Ranges | PostgreSQL built-in range types | contains, overlaps, adjacent, union, intersection; exclusion constraints |

Address and phone are *records*, not tagged decimals — no arithmetic applies. Neither library has any Ecto code today, so both are greenfield with no deployed contract to preserve.

## Framing: the four operations

Localize is converging on four operations applying to every type — **format**, **parse**, **order**, **inflect** — across both the Elixir standard types (`Date`, `Time`, `DateTime`, numbers) and the structured types (money, unit, address, phone number, ranges). That symmetry is the release storyline: an expanded set of types, each supporting the same four operations.

Two consequences for this work:

* It is a statement of symmetry, **not** a requirement to push formatting or parsing into SQL. Locale formatting needs CLDR data the database does not have. Ecto types own parse (`cast`) and hand back a struct that `to_string/2` formats; the database contributes ordering (ICU collation) and the aggregates.
* **Inflection is out of scope here.** It lives on the inflection branch, and per standing policy inflection work stays there — nothing inflection-related belongs in this main-line `localize_sql` work.

Completing format/parse/order for address and phone belongs in `localize_address` and `localize_phonenumber` themselves, not in `localize_sql`. This plan covers only their SQL serialization.

## The governing rule: DDL strategy central, Ecto layer local

Generalizing the `ex_money_sql` shape to every type family:

* **`localize_sql` owns the common DDL strategy** — the tagged-decimal specification and SQL generator, collations, ranges, and the migration plumbing.
* **Each type's Ecto layer lives in that type's own library**, depending on `localize_sql` only when it actually needs DDL.

| Type | Ecto layer lives in | Needs localize_sql? |
|---|---|---|
| Money | `ex_money_sql` | Yes — composite type, aggregates, operators |
| Unit | `localize_sql` itself (`Localize.Unit` is in `localize`, already a dependency) | n/a |
| Address | `localize_address` | **No** — `jsonb` is built in, no DDL |
| Phone number | `localize_phonenumber` | **No** — `text` is built in, no DDL |
| Ranges | `localize_sql` | Built-in PostgreSQL types |

This also resolves a hard dependency conflict: `localize_address` and `localize_phonenumber` both pin `{:localize, "~> 0.14"}` while `localize` is at 1.0.0-rc.7 and `localize_sql` requires `~> 1.0-rc`, so `localize_sql` **cannot** depend on either. Since their Ecto types need nothing from `localize_sql`, each adds only `{:ecto, optional: true}` and gates on `Code.ensure_loaded?(Ecto.Type)`. It also keeps libpostal and libphonenumber — both built unconditionally via `compilers: [:elixir_make]` — out of `localize_sql` and its consumers.

Bumping those two libraries to `localize ~> 1.0-rc` remains separate work in their own repos.

### Ecto type dispatch is schema-driven

Worth recording because it is counter-intuitive: Ecto does **not** read the database type to decide which Ecto type module to call, and never introspects the catalog. The direction is `schema field declaration → Ecto type module → type/0 → database type`. A `field :phone, Localize.PhoneNumber.Ecto.Type` declaration is what dispatches to that module; its `type/0` returning `:string` is what tells Ecto how to encode. So a custom PostgreSQL type is never needed merely to make an Ecto type work — money and unit have composite types because they need SQL-side aggregates and operators, which jsonb cannot support.

## Layering of the shared machinery

```
Localize.Ecto.Record        — struct ↔ composite type or jsonb, N fields   [address; base for tagged decimals]
└── TaggedDecimal           — + tag-guarded sum/avg/min/max, +/-/negate    [money, unit]
Localize.Ecto.Range         — query API + constraint helpers                [no serialization layer needed]
Phone number                — scalar Ecto type over text; bypasses Record entirely
```

## PostgreSQL range support — investigated 2026-07-30 against PostgreSQL 17.4

Built-in range types, all with a PG14+ multirange counterpart and `range_agg` / `range_intersect_agg`:

| Range | Subtype | Decodes to |
|---|---|---|
| `int4range` | integer | integer |
| `int8range` | bigint | integer |
| `numrange` | numeric | `Decimal` |
| `daterange` | date | `Date` |
| `tsrange` | timestamp without time zone | `NaiveDateTime` |
| `tstzrange` | timestamp with time zone | `DateTime` |

**Number ranges: yes** — `numrange`, `int4range`, `int8range`.

**The one gap is `time`.** There is no built-in range over time-of-day. `CREATE TYPE ... AS RANGE (subtype = time)` fills it, and Postgrex auto-discovers it: it matches ranges generically by `send: "range_send"` and bootstraps from `pg_type LEFT JOIN pg_range`. Verified by round-tripping through a fresh connection — a custom range decoded to `%Postgrex.Range{lower: ~T[09:00:00], upper: ~T[17:00:00]}` with no Postgrex configuration. Caveat: the type must exist before the connection pool bootstraps, i.e. create it in a migration, not at runtime.

**Storage needs nothing from us.** Postgrex ships `%Postgrex.Range{lower, upper, lower_inclusive, upper_inclusive}` and `%Postgrex.Multirange{ranges: [...]}` with encode/decode for every built-in range type. So range work is query API + constraints + the time type, and we use `Postgrex.Range` directly rather than wrapping it (an Elixir-native struct was considered and declined: `Date.Range` cannot express unbounded or exclusive-lower bounds).

### Naming collisions found while building the query API

Two are forced, and both are worth knowing:

* `Ecto.Query` already exports **`union/2`** (and `intersect/2`, `except/2`) for combining result sets. A range `union/2` cannot coexist with the `import Ecto.Query` every query module has, so the value-level set operations are `range_union/2`, `range_intersection/2` and `range_difference/2`.
* `Localize.Ecto.Postgres` exports `lower/1,2` and `upper/1,2` for locale-aware case mapping, so the range bound accessors are `lower_bound/1` and `upper_bound/1`.

Both are covered by tests asserting the two modules can be imported together.

### Ecto cannot express a partial exclusion constraint

`Ecto.Migration.Constraint` has fields `name`, `table`, `check`, `exclude`, `prefix`, `comment`, `validate` — there is no `:where`. Ecto emits `CONSTRAINT <name> EXCLUDE USING <exclude>`, and PostgreSQL's grammar puts the predicate after the element list, so `no_overlap/3` folds a `:where` option into the exclude expression itself: `gist ("period" WITH &&) WHERE (status <> 'cancelled')`.

## Dependency layering

```
localize
├── ex_money            → localize
├── localize_sql        → localize          (collations, units, shared {tag,decimal} core)
└── ex_money_sql        → ex_money + localize_sql
```

## Shared core (all under localize_sql's owned `Localize.Ecto.*`)

- `Localize.Ecto.TaggedDecimal` — spec describing one tagged-decimal type: `type_name`, `tag_field`, `value_field`, optional `extra_fields` (units' `usage`), `fn_prefix`, `aggregates`, `operators`, error text.
- SQL generator — emits composite-type DDL + aggregates (`sum`/`avg`/`min`/`max`) + operators from a spec. Parallel-safe template (money's), dormant bugs fixed. Replaces the static `priv/SQL/*.sql` files. **Golden-tested to reproduce money's existing SQL byte-for-byte.**
- `Localize.Ecto.TaggedDecimal.{Composite,Map}` — `Ecto.ParameterizedType` bases; generic load/dump/cast/embed_as/equal?, delegating domain semantics to an injected adapter.
- Migration plumbing — shared `parse_repo`/`ensure_repo`/`migrations_path`/`format_string!`, timestamped `embed_template` emit, `execute`/`execute_each` with the optional append hook money's `adjust_for_type` needs.

Domain layer supplies only a spec + adapter (build-struct, to-parts, cast-from-string, compare, tag-key-per-representation).

## Frozen contracts (no downstream migration; keep byte-for-byte)

- Money: composite `money_with_currency(currency_code varchar, amount numeric)`; the five `mix money.gen.postgres.*` task names; `Money.Ecto.{Composite,Map}.Type` + parameterized options; `Money.Migration.adjust_for_type/2` (called at migration runtime by generated files in consumer repos); `Money.Validate.validate_money/3`; `Money.Ecto.Query.API`; `Money.DDL` public functions. Money's modules become thin wrappers over the shared base.
- Units DB objects `cldr_unit(unit, value)` / `cldr_unit_with_usage(unit, value, usage)` stay stable. Units has no external consumers, so its SQL may be *upgraded* to the parallel-safe template and its Ecto types ported to `ParameterizedType` (changes `embed_as` `:self` → `:dump`).

## SQLSTATE 22033

Both libraries raise `ERRCODE = '22033'` on a tag mismatch, with messages reading like `invalid_parameter_value` — but that code is `22023`. Since PostgreSQL 16, `22033` is `invalid_sql_json_subscript`, so `Postgrex.Error` surfaces `code: :invalid_sql_json_subscript` (verified against PostgreSQL 17). Kept `22033` as the default: deployed functions and money's README already use it, and changing it would leave new installs inconsistent with existing ones. Overridable per type via the `:errcode` option. **Open question for Kip:** switch to `22023` in a future major version?

## Known bugs to fix (not replicate) when lifting the SQL

- Units `drop_aggregate_functions.sql`: drops `unit_state_function(... cldr_unit_with_usage ...)` but the created fn is `unit_with_usage_state_function` → orphaned. Same mismatch baked into its committed test-fixture migration. **Fixed** — drops are generated from the same spec that generates the creates, so the names cannot drift.
- Money `define_negate_operator.sql`: defines `money_negate` but the operator/drop reference `money_neg` (dormant — no mix task emits it). **Fixed** by the same mechanism.
- Money's `sum`, `min` and `max` `*_combine_function` bodies all reference `expected_currency` in the exception branch without `DECLARE`ing it — would raise on a tag mismatch during a parallel combine. **Fixed**; combine functions are now covered by tests that call them directly, since PostgreSQL will not parallelise a small test table.
- Money's `min`/`max` used bare `CREATE AGGREGATE` while `sum` used `CREATE OR REPLACE AGGREGATE`; re-running the former fails. Now uniformly `CREATE OR REPLACE`.
- Units' `sum` had no `combinefunc` and no `parallel = SAFE`, so it could not parallelise. It now gets money's stronger template.

Not a bug: the `IS NULL` branch seeding `aggregate := 0` looks like it would make `min` return 0, but a STRICT state function with no `initcond` is never called until PostgreSQL has seeded the state from the first non-null row, so the branch is unreachable in aggregate use. Covered by a regression test (`do not treat zero as a lower bound`).

## Phases

- [x] **A. Rename** localize_ecto → localize_sql. Green (compile-WAE, format, credo, 202 tests incl. SQLite ICU, dialyzer, docs). CI env var + gitignore tarball updated; cache keys already OTP+Elixir-scoped.
- [x] **B. Shared core** in localize_sql.
  - [x] `Localize.Ecto.TaggedDecimal` — the spec (`new/1`, `new!/1`, `function_name/2`, `fields/1`).
  - [x] `Localize.Ecto.TaggedDecimal.DDL` — generates composite type, tag-guarded `sum`/`min`/`max`/`avg`, `+`/`-`/unary-`-` operators, and the `execute`/`execute_each` migration wrappers. 264 tests green, including 26 executed against live PostgreSQL.
  - [x] Shared mix-task/migration plumbing — `Localize.Ecto.Migration.Generator` (`render/3`, `create_migration/5`, `timestamp/0`).
  - ~~`Localize.Ecto.Record` — generic struct ↔ composite/jsonb + ParameterizedType bases.~~ **Superseded** — per Kip, only the Ecto callbacks are needed and there is one consumer per type, so each Ecto type is written directly (money/unit keep per-domain types; only the DDL and migration machinery are shared). No generic Record/base layer was built.
- [x] **Ranges** — `Localize.Ecto.Range` (operator/accessor/aggregate macros) and `Localize.Ecto.Range.Migration` (`create_time_range/1`, `drop_time_range/1`, `create_btree_gist/0`, `no_overlap/3`). 294 tests green, including a real Ecto migration that creates the time range type and proves the exclusion constraint rejects overlapping bookings in the same room while allowing them across rooms.
- [x] **Address** — `Localize.Address.Ecto.Map.Type` (jsonb) in `localize_address`. Casts struct/atom-map/string-map, omits nil components on dump, tolerates retired keys on load. Needs no `localize_sql` dependency (jsonb is built in). 24 tests. The speculative generic `Record` layer was dropped per Kip: only the Ecto callbacks are needed, and there is one consumer each.
- [x] **Phone number** — `Localize.PhoneNumber.Ecto.Type` (E.164 text, `Ecto.ParameterizedType` with a `:territory`/`:locale` field option) in `localize_phonenumber`. 23 tests. Needs no `localize_sql` dependency (text is built in).

### localize 1.0-rc bump (done for both type libraries)

`localize_address` and `localize_phonenumber` were pinned to `{:localize, "~> 0.14"}` (resolving to 0.41.0). Both bumped to `~> 1.0-rc`:

* `localize_phonenumber` → clean, no API changes.
* `localize_address` needed `{:unicode_string, "~> 2.0"}` → `~> 2.3` first, because unicode_string 2.0 required `localize "~> 0.8 or ~> 1.0"` and `~> 1.0` excludes pre-releases in Hex. The bump also pulled major transitive bumps (`decimal 2→3`, `unicode 1→2`). One real 0.x→1.0 API break fixed: `Localize.Territory.Subdivision.known_subdivisions/0` is gone; `subdivision_names_for(locale:)/1` replaces it (and returns names, removing per-entry `display_name` calls and a `try/rescue`).

### Dialyzer + credo aligned to Localize (done)

All three libraries now carry Localize's dialyzer flags (`:error_handling, :unknown, :underspecs, :extra_return, :missing_return`) and a `.credo.exs` mirroring Localize's policy (`strict: true`, only `Design.AliasUsage` disabled). Fixes made to reach zero:

* `localize_sql` — the `:underspecs` flag surfaced four pre-existing `contract_supertype` specs in `Localize.Ecto.Audit` (`report/1`, `unicode_versions/1`, `timezone_audit/1`, `database_collation_drift/1`) returning bare `map()`. Fixed with proper `@type` definitions.
* `localize_address` — new `.credo.exs` surfaced ten findings (two mine, eight pre-existing nesting/pipe issues in the formatter and download task); all fixed by extracting helper clauses.

Environment note (not a code change): the prebuilt phone and address NIFs failed to load until libphonenumber and its protobuf were upgraded (Homebrew's `libphonenumber.9.0.dylib` referenced a `libprotobuf.34.1.0` that protobuf 35.1 had removed). Kip upgraded both; NIFs rebuilt.
- [x] **C. Fold units in.** The four unit Ecto types (`Localize.Unit.Ecto.{Composite,Map}.Type`, `Localize.UnitWithUsage.Ecto.{Composite,Map}.Type`) moved into localize_sql. `Localize.Unit.DDL` delegates to `TaggedDecimal.DDL` with two specs and now offers `sum`/`min`/`max`/`avg` for both `cldr_unit` and `cldr_unit_with_usage` (was sum-only). `Localize.Ecto.Migration.Generator` (shared migration-writing plumbing, `render/3` + `create_migration/5` + `timestamp/0`) and a `mix localize.unit.gen.migration` task. The `unit_with_usage_state_function` drop-name bug is gone (drops generated from the same spec). 327 tests green, including live-PostgreSQL `avg` over `cldr_unit_with_usage` (exercises the extra-field avg state type). All six gates clean.
  - Note: copied unit types kept legacy `@behaviour Ecto.Type` (they work; no consumers). Credo/dialyzer brought to zero — single-clause `with/else` → `case`, `def type()` → `def type`, and a `db_type` type to fix a `contract_supertype`. The remaining `with/else` (8, all two-step `Decimal.parse` + `Localize.Unit.new`) are legitimate Ecto-boundary adapters mapping distinct failures to Ecto's `:error`/`{:error, keyword}` contract.
- [x] **D. Refactor ex_money_sql** onto localize_sql. `Money.DDL` keeps every public function but each delegates to `TaggedDecimal.DDL` with a money spec — no name overrides needed (money already uses the default `money_<role>_function` names), so the regenerated SQL matches deployed signatures while fixing the dormant bugs (`money_neg`→`money_negate`, the undeclared combine var, and the incorrect `commutator = -` on minus). money's mix tasks, `Money.Migration` and the frozen Ecto types are otherwise untouched; `execute`/`execute_each` kept byte-identical for their doctests. **Money's full suite passes: 112 passed, 5 skipped.** money_sql's own credo/dialyzer aligned to Localize (single-clause `with/else`→`case` in the Ecto types, a nesting extraction in `Validate`, `format_string!` → `binary()`, and `Money.Migration` now matches `%{rows: ...}` rather than the `Postgrex.Result` struct so it compiles without postgrex). All six gates green.
  - **Kept separate, not folded into ex_money** (Kip's call): money's DB layer (Query API DSL, DDL, migrations, Validate, 5 tasks) is a substantial sub-library, unlike the one-module address/phone types, and a separate package bundles the ecto/ecto_sql/localize_sql deps cleanly.
  - **Dependency coordination (temporary):** money_sql references `ex_money` and `localize_sql` by **path** during the localize 1.0 migration — published ex_money 6.0 caps `localize "~> 0.27"`, and localize_sql isn't published. Local ex_money is 6.2.0 on localize 1.0-rc. Added `{:postgrex, "~> 0.20", only: [:dev, :test]}` (it was only ever transitive). Switch both path deps to hex (`{:ex_money, "~> 6.2"}`, `{:localize_sql, "~> 1.0"}`) once published, and run `mix deps.clean --build ecto ecto_sql` after any postgrex change.
  - **Not a Phase D regression:** the 4 initial money test failures were stale `:AAA`→`"AAA"` unknown-currency message expectations from the ex_money 6.2 bump; fixed in money's tests.
- [x] **Finalize (docs).** localize_sql README rewritten (two-capability framing: collation + serialization; a "Serializing Localize types" section with the type table and the tagged-decimal aggregate story). All `localize_ecto`/`Localize Ecto`/`LOCALIZE_ECTO` references across README + guides fixed; `using_localize_ecto.md` → `using_localize_sql.md` (mix.exs extra updated). CHANGELOG `[Unreleased]` section documents the rename + the serialization expansion; historical entries left intact. Docs build clean.
  - Deferred to Kip: the **version** number (still `1.0.0-rc.0` in mix.exs — the rename + expansion warrants a bump). Dedicated per-type guides (tagged decimals, serialization) could follow the module docs, which are complete.
  - **localize core change:** `Localize.validate_territory/1` now accepts integer M49 codes (`1` → `:"001"`) as its typespec/docs always claimed — the validator's guard omitted `is_integer/1` though `normalize/1` already zero-padded. Fixed in `Localize.Validity.Territory`, doctest added, localize CHANGELOG updated. localize's full suite (31262 tests) green. The Territory Ecto type accepts M49 as **strings** for now (it uses hex localize rc.7, which predates the fix); integer support there lands when localize republishes.

## Serializable types (the expanded type set)

Every serializable Localize/Elixir type now has an Ecto type. Those whose struct lives in `localize` itself keep their Ecto layer in **localize_sql** (so `localize` stays ecto-free — the same rule as units); those whose struct lives in a separate library keep it there.

| Type | Ecto type | Column | Lives in | DDL |
|---|---|---|---|---|
| Money | `Money.Ecto.{Composite,Map}.Type` | composite / jsonb | ex_money_sql | yes (aggregates) |
| Unit | `Localize.Unit.Ecto.{Composite,Map}.Type` (+ WithUsage) | composite / jsonb | localize_sql | yes (aggregates) |
| Currency | `Localize.Currency.Ecto.Type` | text (code) | localize_sql | no |
| LanguageTag | `Localize.LanguageTag.Ecto.Type` | text (`to_string/1`) | localize_sql | no |
| Integer range | `Localize.Ecto.Type.IntegerRange` | `int8range` | localize_sql | no (built-in) |
| Date range | `Localize.Ecto.Type.DateRange` | `daterange` | localize_sql | no (built-in) |
| Localize.Duration | `Localize.Duration.Ecto.Type` | `interval` | localize_sql | no (built-in) |
| Elixir Duration | `Localize.Ecto.Type.Duration` | `interval` | localize_sql | no (built-in) |
| Territory | `Localize.Territory.Ecto.Type` | text (code) | localize_sql | no |
| Script | `Localize.Script.Ecto.Type` | text (code) | localize_sql | no |
| Address | `Localize.Address.Ecto.Map.Type` | jsonb | localize_address | no |
| Phone number | `Localize.PhoneNumber.Ecto.Type` | text (E.164) | localize_phonenumber | no |
| Time zone | `Localize.Ecto.Type.TimeZone` | text | localize_sql | no |

* **Duration** (both the `Localize.Duration` struct and Elixir's built-in `Duration`) → PostgreSQL `interval`. `interval` keeps months/days/time as separate components, so interchangeable units normalize on load (90 minutes → 1h30m, a week → 7 days) while month vs day stays distinct; the microsecond value round-trips and its precision normalizes (0 when there are no fractional seconds, else 6). Verified with live-PostgreSQL round-trips. Gated on `Postgrex.Interval`.
* **Territory / Script** → validated code atoms (`:US`, `:Latn`) stored as text, exactly like Currency, via `Localize.validate_territory/1` and `Localize.validate_script/1`. **Language was requested but skipped:** there is no standalone `validate_language` — a language subtag is only validated within a `LanguageTag`, which already has its own Ecto type. (Note: `validate_territory`'s `@spec` claims `integer()` M49 support but the implementation raises on integers — a spec bug in localize; the Ecto type accepts atoms/strings only.)

Notes on the additions (all in localize_sql, 373 tests green):

* **Currency** stores the validated ISO code atom (`:USD`) as text; cast accepts an atom/string code or a `Localize.Currency` struct.
* **LanguageTag** stores the canonical BCP 47 string; loads back through `Localize.validate_locale/1` (canonicalized, `-u-` populated, likely-subtags resolved, cached).
* **IntegerRange / DateRange** map Elixir's inclusive `Range`/`Date.Range` to PostgreSQL `int8range`/`daterange`. `load/1` normalizes whatever inclusivity PostgreSQL canonicalizes to (`[lower, upper)`) back to Elixir's inclusive-both form; only ascending unit-step ranges are storable (stepped/descending are rejected). Verified with live-PostgreSQL round-trips. These reference `Postgrex.Range`, so the modules gate on `Code.ensure_loaded?(Postgrex.Range)` and postgrex is `optional: true` (creates the consumer compile-order edge without forcing it on SQLite-only users; also keeps it available for localize_sql's own tests and release-env docs).

## Git / logistics (Kip runs all git + GitHub)

- GitHub repo renames: `localize_ecto` → `localize_sql`; archive/redirect `localize_units_sql`.
- Local dir rename optional (build uses the app name, not the dir).
- All commits/branches/tags by Kip; exact steps handed over at finalize.
