# Map order

**Status:** in progress, 2026-09-26

On OTP 26 and later a map with at most 32 atom keys iterates in the order its atoms were created, which differs between VMs and with what the host application loads first; a larger map iterates in hash order. Tests pass, so order is changed only where something depends on it: a selection that takes the first or last candidate, a test or doctest whose expected value depends on the order, or generated output that must be reproducible. A list returned in no documented order stays as it is.

The audit of 2026-09-26 covered every map enumeration under `lib/` on `main`. Code that exists only on `cldr-49` has not been audited yet.

## Tasks

* [ ] **Territory name to code where names collide** — `Localize.Territory.to_territory_code/2` keeps whichever territory it visits last when two names are equal after normalisation (10 locales; in `rm`, "America dal Nord" is `:"003"` and "America dal nord" is `:"021"`). Needs an exact match first, then a tie rule to be chosen.

* [ ] **Fuzzy currency matches that tie** — with `:fuzzy`, `Localize.Number.Parser` takes the first of equally distant currency strings in map order: "usx" ties "ugx", "usd", "usn" and "uss". Needs a tie rule to be chosen: alphabetical, or current tender first.

### Deferred

These selections walk a map but are deterministic only because today's CLDR data never gives them two candidates. Recheck each one whenever the data is regenerated.

* [ ] **Unit patterns by category** — `Localize.Unit.Formatter`'s direct-format and per-unit pattern lookups take the first unit category that holds the unit. No unit is in two categories in any locale and style.

* [ ] **Day-period rules** — the `at` and `flex` day-period lookups in `Localize.DateTime.Formatter` take the first matching rule. No two rules share an `at` time, and TR35 forbids overlapping flexible rules.

* [ ] **Collation reordering ranges** — `Localize.Collation.Reorder` sorts ranges by their start byte alone. Every start byte has a single range.

* [ ] **Language-distance exclusion rules** — `Localize.Locale.DistanceTrie` returns the first matching "not in" rule. Each table has at most one rule of each shape.

* [ ] **Currency names shared three ways** — `Localize.Currency` resolves a shared name or symbol pairwise, which depends on order once three or more currencies share it. None do.

* [ ] **Unit validity of `karat`** — `concentr-karat` is regular and `proportion-karat` deprecated, and `Localize.Validity` keeps the status of whichever group the compiling VM enumerates first: regular, because `:regular` exists at boot before `:deprecated`.

* [ ] **RBNF rule groups** — `Localize.Number.Rbnf` merges rule groups last-wins. No rule-set name is in two groups.

### Done

* [x] **A territory's primary currency** — `Localize.Currency.current_currency_for_territory/1` took the first current tender in atom-creation order, so LS gave LSL and ZW gave USD. The generated data now keeps each currency's CLDR position as `:order`, and a currency listed for two periods keeps its current one, which gives ML its XOF. 2026-09-26, v1.4.0.

* [x] **Shared narrow currency symbols** — a narrow symbol such as "kr" went to whichever currency the map yielded first. It now follows the rule for shared strings: one current currency among historic ones takes it, otherwise it stays unassigned. 2026-09-26, v1.4.0.

* [x] **The parser's longest match** — `Localize.Number.Parser` compared grapheme counts, which tie between a currency's singular and plural in 17 locales. It compares byte size, which cannot tie. 2026-09-26, v1.4.0.

* [x] **Number systems in type order** — `number_system_names_for/1` and `format_system_types_for/1` return default, native, traditional, finance, as their doctests say. 2026-09-26, v1.4.0.

## Decided not to change

Nothing depends on the order of these, so they stay as they are:

* **Lists in no documented order** — `Localize.Number.System.known_number_systems/0`, `Localize.Number.Format.format_styles_for/2` and `short_format_styles_for/2`, `Localize.Currency.strings_for_currency/2`, `Localize.Collation.Tailoring.supported_locales/0`, `Localize.DateTime.Timezone.timezones_for_territory/1`, `Localize.Unit.known_units_by_category/0`, `Localize.Validity`'s `all_valid/1` and `known/1`, and the generated `known_units/0` of `mix localize.unit.gen_conversions`.

* **Error payloads** — the allowed values in `number_symbols_for/2`'s error, the field order in an `InvalidLocaleError` for a hand-built tag, which invalid entry an ANSI palette error names, which invalid argument `Localize.Nif.mf2_format/3` names, and the first invalid `-u-`/`-t-` key of a tag with more than 32 of them.

* **Unreachable collisions** — bindings given as both `:x` and `"x"`, and expressions with more than 32 options.

* **`Localize.Utils.Map`** — nothing calls it.
