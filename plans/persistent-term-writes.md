# Runtime `:persistent_term` writes

**Status:** in progress, 2026-11-10

Rule 14 of the house standards says no code writes `:persistent_term` while it serves calls: no lazy caches, no tables that grow, no configuration mirrors refreshed when they change. Localize writes it at runtime in about forty places. This document lists every `put` and `erase` in `lib/` as of `d5e2111f`, what each costs as measured on Elixir 1.20.5 and OTP 29.1.2, three defects the audit found, and the options. No code has been changed.

## What a write costs

* **A put under a new key** — about 1.3 µs, the same with 1,000 or 50,000 keys stored, and no global GC. The OTP documentation says the cost grows with the number of keys; on OTP 29.1.2 it did not.

* **A replace or an erase** — a term larger than one machine word starts a global GC: every process is made runnable to scan its heap, and a process holding the old term does a full-sweep GC and copies it. With 100,000 idle processes the worst probe round trip after a replace was 49 µs. With 100,000 processes holding the replaced 360-byte language tag it was 3.6 ms against a 1.2 ms baseline. An atom, a boolean or a small integer is replaced or erased with no global GC.

* **A put of an equal value** — does nothing. Two compiles of the same regex are not equal, so two processes racing to fill a regex cache replace the term.

* **Literal memory** — a term stays in the literal area until it is erased. The area is a gigabyte by default, shared with every module's literals. A typical format-and-parse workload writes 2.1 to 2.4 MB a locale, nearly all of it the locale's data, so CLDR's 657 locales do not fit. A binary over 64 bytes in a key or a value lives off-heap and is held for good. `Localize.LiteralMemory` refuses a term the area has no room for, so a full area stops new locales loading (`LiteralMemoryError`) and silently stops every cache caching. It checks the value's size, not the key's.

* **The alternative, ETS** — every read copies the value into the reader, as measured below.

| Value | Size | persistent_term | ETS |
|---|---|---|---|
| A locale's data (`en`) | 2 MB | 0.03 µs | 1,800 µs |
| `Localize.Locale.DistanceTrie` | 512 KB | 0.03 µs | 209 µs |
| `Localize.Unit.NameIndex`, one locale | 419 KB | 0.04 µs | 65 µs |
| `Localize.Date.Parser`, largest entry | 77 KB | 0.03 µs | 13 µs |
| `Localize.Number.Lexicon`, largest entry | 58 KB | 0.04 µs | 10 µs |

A whole currency parse takes about 6 µs, so moving a lexicon to ETS as it stands would more than double it.

## Defects

### Caller input becomes a key

Three options are put into a cache key before anything checks them, and every call with a new value adds a key that is never removed:

* **`:only` and `:except`** of `Localize.Number.Parser.parse_currency_amount/2`, through `Localize.Number.Lexicon.currencies/2`. 1,000 parses with distinct `only: ["zz…"]` strings added 1,000 keys; with `except:` the parse also succeeds. `Money.parse/2` passes its caller's `:only`, `:except` and `:currency_filter` straight through.

* **`:separators`** of `Localize.Number.Parser.parse/2`, through `Localize.Number.Lexicon.fetch/3`. Any value is accepted and the parse succeeds. Ten parses with a 100 KB string held 854 KB of binary memory after every process was garbage collected.

* **`:type`** of `Localize.Collation.compare/3`, through `Localize.Collation.Tailoring.get_tailoring/2`. Any value is accepted and the comparison succeeds.

So a request parameter passed as one of these grows memory without bound, and once the literal area fills, no new locale loads. Accepting an unknown `:separators` or `:type` without an error also breaks rule 2.

### Custom unit registration loses registrations

`Localize.Unit.CustomRegistry.register/2` and `register_batch/1` read the whole map, add to it and put it back, with nothing serialising them. 200 concurrent `register/2` calls all returned `:ok` and left 13 units registered. Each call is also a replace, so a global GC.

### Supported-locale changes erase one term per locale

`Localize.put_supported_locales/1` calls `Localize.Number.Rbnf.clear_locale_chains/0`, which erases each cached locale chain on its own: one global GC per locale used. The OTP documentation advises against exactly that, for the same reason.

## Where the writes are

### Written at start

These comply with rule 14: written once, when the application starts. After start there are 26 keys holding 15.7 MB.

* **Collation tables** — six keys, 15 MB, in `Localize.Collation.Table`'s `handle_continue/2`, with the room checked first.

* **Supplemental data** — `Localize.Supervisor`'s `after_start/0` reads the validity, currency, calendar, time zone and locale-id data through `Localize.DataLoader` (11 keys) and the number systems (3 keys).

* **The rest** — `Localize.Priv`'s data directory, `Localize.Nif`'s loaded flag (`@on_load`), the five number-format regexes (`Localize.Number.Format.Compiler.precompile_regexes/0`) and a configured `:supported_locales`. A supervisor restart reruns `after_start/0`, and its regexes then replace the old ones: five global GCs.

### Constant data computed on first use

One key each, written by the first call that needs it and never changed. Each is a new-key put, so 1.3 µs and no GC, but each is a runtime write.

* **`Localize`** — `version/0`, `cldr_repo_ref/0`, three lookup sets (calendar and number-system names, locale ids) and the default locale. The default locale is first written as `en` and then replaced with the resolved one, a global GC on the first call when the default is not `en`.

* **`Localize.LanguageTag`** — seven tables built from supplemental data: the locale-id index, paradigm locales, four alias tables and the grandfathered tags. They moved here from module attributes so the module has no compile-time dependency on `Localize.SupplementalData`.

* **Other tables** — `Localize.Locale.DistanceTrie` (512 KB), the supplemental files not read at start (six in an `en` workload, 1.9 MB), `Localize.Unit`, `Localize.Unit.BaseUnit` and `Localize.Unit.Canonical`, the locale and inflection hash manifests, `Localize.Utils.Http.ca_trust_option/0`, `Localize.Collation.Variable.primary_range/1` (at most four keys) and `Localize.Number.Parser`'s locales by territory.

### Per-locale data and caches

A key for each locale used, and for some for each calendar, number system or option too. These are the writes rule 14 names: a lazy cache per locale is a runtime write for every key.

| Owner | Keyed by, besides the locale | Size a locale |
|---|---|---|
| Locale data (`Localize.Locale.Provider.PersistentTerm.store/2`) | — | 1.3 to 2.3 MB |
| `Localize.Inflection.Data` | — | megabytes |
| `Localize.Number.Lexicon` | number system, currency, separators, filters | 52 to 71 KB |
| `Localize.Date.Parser` | calendar module | 43 to 148 KB |
| `Localize.Unit.NameIndex` | — | 419 KB |
| `Localize.Time.Parser` | calendars | not measured |
| `Localize.DateTime.Timezone` (zone names) | — | not measured |
| `Localize.Collation.Tailoring` | collation type | 17 KB |
| `Localize.Number.Rbnf` (locale chain) | — | under 1 KB |
| `Localize.Number.Parser` (currency periods) | — | not measured |
| `Localize.Inflection.FeatureModel`, `PronounConcept` | the pronoun table's locale | not measured |

Locale data is written by `Localize.Locale.Loader`, one process, so a locale is loaded once; the caches are filled by whichever process misses first. The date and time parsers' compiled regex caches replace each other when two processes race.

### Replaced or erased at runtime

* **`Localize.put_default_locale/1`** — replaces the default language tag.

* **`Localize.put_supported_locales/1`** — replaces the list, then erases each locale chain (above).

* **`Localize.Unit.CustomRegistry`** — `register/2`, `register_batch/1` and `clear/0` replace the whole map (above).

* **`Localize.Calendar.register_provider/1`** — replaces a module name, an atom, so no global GC.

* **Test seams** — `put_locale_hashes/1`, `reset_locale_hashes/0`, `put_inflection_hashes/1` and `reset_inflection_hashes/0`, called only from tests.

### Warn-once flags

`Localize.Macros.warn_once/3`, the stale-locale warning (one key a locale) and the warnings for a missing locale or inflection hash manifest and for unsafe HTTPS each put `true` or `nil` under a new key after logging. One-word values, so no GC. Each reads, logs and then writes, so two processes can both log.

## Options

### The defects

These are defects whatever is decided about the rest, and all three are in the published 1.6.1.

* **Caller options** — validate each at the public API before it reaches a key, returning `InvalidValueError` for anything else: `:separators` must name a separator set, `:type` one of the documented collation types, and each `:only` and `:except` entry a currency code or status, resolved to its atom. The keys are then bounded by the locales and the values CLDR defines. For the currency filters there is a second way: cache each locale's unfiltered currency strings and filter them on every parse, which takes the filters out of the key altogether at a cost per parse that has not been measured.

* **Custom units** — keep them as rows of an ETS table owned by a supervised process (rule 12), written through it with `GenServer.call/2` and read with `:ets.lookup/2` by unit name. A row is small, so the read copy is cheap, and registration becomes atomic with no global GC.

* **Locale chains** — keep them in ETS too. A chain is a list of a few atoms, so a read copies well under a microsecond, and `put_supported_locales/1` clears them all with one `:ets.delete_all_objects/1`.

### Warn-once flags

Record each flag with `:ets.insert_new/2` in a table owned by a supervised process, and log only when it returns `true`. That is atomic, so a warning is logged exactly once, and it writes no `:persistent_term`.

### Constant data computed on first use

* **At start** — compute them in `Localize.Supervisor`'s `after_start/0`, which complies with rule 14. That costs start time, not measured, and memory for tables an application may never reach (`Localize.Locale.DistanceTrie` is 512 KB).

* **At compile time** — module attributes, which gives back the compile-time dependency on `Localize.SupplementalData` that `Localize.LanguageTag` removed.

* **In the process that uses them** — the hash manifests and `ca_trust_option/0` are needed only to download, which `Localize.Locale.Loader` serialises, so its state can hold them.

Recommended: at start for the tables every application reaches, including the default locale (so its first-call replace goes), and the loader's state for the download-only ones.

### Configuration setters

`put_default_locale/1`, `put_supported_locales/1` and `register_provider/1` are mirrors of configuration refreshed when it changes, which rule 14 names.

* **The application environment** — `Application.get_env/2` read the 360-byte default tag in 0.36 µs, against 0.04 µs now, so the default locale and the calendar provider can live there at little cost. The supported-locale list cannot: reading all 657 ids took 17.5 µs.

* **Keep them as boot-time setters** — documented to be called while the application starts. A replace measured 3.6 ms of worst-case latency with 100,000 holders, so a call at runtime is a stall rather than a failure, but it is still a runtime write.

### Per-locale data and caches

This is the decision for the maintainer, since every option either breaks rule 14 or changes how Localize keeps its data.

1. **An explicit exception for per-locale data**, as rule 11 makes one for the locale: a key is written once per locale, or per locale and a value CLDR defines, through one process or with a value that compares equal; it is never replaced or erased, and its room is checked. That costs 1.3 µs once a key and no GC. It leaves literal memory growing with the locales in use, never returned, and every locale needing `+MIscs`. It holds only once the defects are fixed and the regex caches cannot replace each other.

2. **Load at start** the configured `:supported_locales`, with their caches built, in `after_start/0`. That complies when `:supported_locales` is set, at a start-time cost not measured. Without it (every CLDR locale, the default) it cannot work: 657 locales at about 2.2 MB each exceed the default literal area. So it pairs with 1 rather than replacing it.

3. **Small ETS rows** — split the locale data and the caches into rows by path, so a read copies only what it needs. Every accessor is rewritten, and a row read still costs more than a `:persistent_term.get/1`.

4. **Precompute the caches into the locale files** — the generator writes each locale's lexicons, parser patterns and name indexes into its ETF, so they arrive with the locale and need no key of their own. It is a data-version release (every ETF, the hash manifest and a CDN publish), ties the generator to the parsers' internals, and cannot carry compiled regexes.

5. **A module per locale** — compile-time literals, the model of `ex_cldr`, which Localize left.

Recommended: 1, with 2 for applications that configure `:supported_locales`, after the defects are fixed. Every alternative measured costs 10 µs to 1.8 ms a read or a data-version release, while the write costs 1.3 µs once with no GC, and the risks the audit found, unbounded keys and racing replaces, are what the defect fixes remove.

## Tasks

* [x] **Bound the cache keys that caller options reach** — `:only` and `:except` are reduced to the statuses and known codes they name, and a code filter is kept in `Localize.FormatCache`; an unknown separator set or collation type is keyed as none, an error is not cached, and a non-atom `:separators` or `:type` is `InvalidValueError`. `test/localize/caller_option_keys_test.exs`. 2026-11-10.

* [x] **Make custom unit registration atomic** — `Localize.Unit.CustomRegistry` is a process under `Localize.Supervisor` owning a protected ETS table; writes go through it, reads go to the table, and registering before it starts returns an error. 200 concurrent registrations all kept. 2026-11-10.

* [ ] **Keep locale chains in ETS** — cleared with one call when the supported locales change.

* [ ] **Warn once with `:ets.insert_new/2`** — for `Localize.Macros.warn_once/3` and the four flags.

* [ ] **Compute the constant tables at start** — in `after_start/0`, with the start time measured; the download-only ones in `Localize.Locale.Loader`'s state.

* [ ] **Decide the per-locale data question** — option 1, 2, 3, 4 or 5 above, and the configuration setters.

* [ ] **Count the key's size in `Localize.LiteralMemory`** — `room_for/1` checks only the value.
