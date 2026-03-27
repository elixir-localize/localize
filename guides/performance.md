# Performance Guide

This guide compares the performance of Localize's pure Elixir implementation against the optional NIF (Native Implemented Functions) backend, and provides guidance on when each is appropriate.

## Overview

Localize ships with two execution backends:

* **Pure Elixir** (default) — no compilation dependencies, works everywhere Elixir runs. Uses CLDR data loaded from ETF files and cached in `:persistent_term`.

* **Optional NIF** — binds to ICU4C via Erlang NIFs. Requires ICU4C to be installed at compile time. Enable with `config :localize, :nif, true` or `LOCALIZE_NIF=true`.

The NIF is not a drop-in replacement for all operations. Some operations are faster with the NIF, some are faster in pure Elixir, and some are comparable. The NIF overhead of crossing the Erlang/C boundary means that lightweight operations with pre-cached data are often faster in pure Elixir.

## Benchmark Results

All benchmarks run on Apple M4 Max, Elixir 1.19.5, OTP 28, CLDR 48.2. Times are median per-call over 10,000+ iterations after warmup.

### MessageFormat 2

MF2 formatting involves parsing, function dispatch, and string assembly. The NIF delegates to ICU4C's `MessageFormatter` which handles all three in a single C call.

| Operation | Elixir | NIF | Winner |
|-----------|--------|-----|--------|
| Simple message (`"Hello {$name}!"`) | 23 µs | 11 µs | **NIF 2.1×** |
| Complex message (`.match` + plural) | 125 µs | 73 µs | **NIF 1.7×** |
| Parse only (validate) | 10 µs | 7 µs | **NIF 1.5×** |

**Recommendation:** Use the NIF for MF2-heavy workloads. The NIF advantage grows with message complexity because ICU4C handles the entire pipeline in C, avoiding repeated Erlang↔Elixir boundary crossings for nested expressions.

### Number Formatting

Number formatting in Elixir uses pre-compiled format metadata cached in `:persistent_term`, making it very fast. The NIF must convert Elixir terms to C types, call ICU, and convert back.

| Operation | Elixir | NIF | Winner |
|-----------|--------|-----|--------|
| Decimal (`1234567.89`) | 5 µs | 10 µs | **Elixir 2×** |
| Currency (`$1,234.56`) | 11 µs | 13 µs | **Elixir 1.1×** |
| Percent (`56%`) | 4 µs | 9 µs | **Elixir 2×** |

**Recommendation:** Pure Elixir is faster for number formatting. The pre-compiled format metadata and `:persistent_term` caching eliminate the overhead that the NIF would need to offset.

### Plural Rules

Plural rule evaluation determines the plural category (`:one`, `:other`, etc.) for a number in a given locale. The Elixir implementation uses generated function clauses from CLDR plural rule definitions.

| Operation | Elixir | NIF | Winner |
|-----------|--------|-----|--------|
| Cardinal rule (`1234, "en"`) | 1.9 µs | 2.9 µs | **Elixir 1.5×** |

**Recommendation:** Pure Elixir is faster. The generated pattern-matching clauses are extremely efficient and avoid the NIF boundary crossing overhead.

### Unit Formatting

Unit formatting combines number formatting with unit pattern lookup and substitution.

| Operation | Elixir | NIF | Winner |
|-----------|--------|-----|--------|
| Simple unit (`100 meters`) | 5 µs | 16 µs | **Elixir 3×** |

**Recommendation:** Pure Elixir is significantly faster. The Elixir implementation benefits from pre-built locale data and cached format patterns.

### Collation (String Sorting)

Collation implements the Unicode Collation Algorithm for locale-sensitive string comparison. This is the most compute-intensive operation and where NIF acceleration typically provides the largest benefit in other libraries. However, Localize's Elixir implementation uses a pre-computed collation table cached in `:persistent_term` which is very efficient.

| Operation | Elixir | NIF | Winner |
|-----------|--------|-----|--------|
| Sort 100 ASCII strings | 145 µs | 502 µs | **Elixir 3.5×** |
| Sort 20 CJK strings | 14 µs | 58 µs | **Elixir 4×** |

**Recommendation:** Pure Elixir is substantially faster. The pre-computed collation element table avoids the per-comparison NIF overhead. Each NIF comparison call crosses the Erlang/C boundary, and for sorting (which requires O(n log n) comparisons), this overhead dominates.

## When to Use the NIF

Based on the benchmarks, the NIF provides a measurable advantage only for **MessageFormat 2** operations:

| Use NIF | Use Elixir |
|---------|-----------|
| MF2 formatting (simple messages) | Number formatting |
| MF2 formatting (complex messages with match/plural) | Currency formatting |
| MF2 validation/parsing | Plural rule evaluation |
| | Unit formatting |
| | Collation / string sorting |
| | Date/time formatting |

## Why Pure Elixir is Competitive

Localize's Elixir implementation uses several techniques that minimize the advantage of native code:

* **Pre-compiled format metadata.** Number and datetime format patterns are parsed once and cached as Elixir terms in `:persistent_term`. Subsequent calls do pattern substitution without re-parsing.

* **Pre-built locale data.** Currency structs, number symbols, and format patterns are built at data-generation time and stored as ETF. There is no runtime struct construction.

* **Collation table in `:persistent_term`.** The Unicode collation element table (~2 MB) is loaded once and shared across all processes without copying. Each comparison is a series of map lookups, which the BEAM optimizes well.

* **Generated function clauses.** Plural rules compile to pattern-matching clauses that the BEAM JIT optimizes to near-native speed.

* **NIF boundary cost.** Each NIF call has a fixed overhead of approximately 1–3 µs for argument marshalling and result conversion. For operations that complete in 5 µs in pure Elixir, this overhead is significant.

## Enabling the NIF

To enable the NIF backend:

```elixir
# config/config.exs
config :localize, :nif, true
```

Or via environment variable:

```bash
export LOCALIZE_NIF=true
```

The NIF requires ICU4C development headers at compile time. On macOS: `brew install icu4c`. On Ubuntu: `apt install libicu-dev`.

You can check NIF availability at runtime:

```elixir
iex> Localize.Nif.available?()
true
```

## Selecting a Backend

All NIF-capable functions accept a `:backend` option. The default is always `:elixir`. When `:nif` is specified and the NIF is available, the ICU4C implementation is used. If the NIF is not available, it silently falls back to the pure Elixir implementation.

| Function | `:backend` option | NIF implementation |
|----------|------------------|--------------------|
| `Localize.Number.to_string/2` | `backend: :nif` | ICU4C NumberFormatter |
| `Localize.Unit.to_string/2` | `backend: :nif` | ICU4C NumberFormatter (unit) |
| `Localize.Number.PluralRule.plural_type/2` | `backend: :nif` | ICU4C PluralRules |
| `Localize.Message.format/3` | `backend: :nif` | ICU4C MessageFormat 2 |
| `Localize.Collation.compare/3` | `backend: :nif` | ICU4C Collator |

Example:

```elixir
iex> Localize.Number.to_string(1234.5, locale: :de, backend: :nif)
{:ok, "1.234,5"}

iex> {:ok, unit} = Localize.Unit.new(100, "meter")
iex> Localize.Unit.to_string(unit, format: :short, backend: :nif)
{:ok, "100 m"}
```

## Optimizing Pure Elixir Performance

### Pre-validate options

For number formatting, pre-validate options once and reuse the struct:

```elixir
# Validate once
{:ok, options} = Localize.Number.Format.Options.validate_options(0, locale: :en, currency: :USD)

# Use many times — skips option validation on each call
for price <- prices do
  Localize.Number.to_string(price, options)
end
```

This saves approximately 5–10 µs per call by avoiding repeated locale resolution, number system lookup, and symbol loading.

### Locale caching

`Localize.validate_locale/1` caches results in an ETS table. The first call for a locale takes ~50 µs; subsequent calls take ~1 µs. Call `Localize.validate_locale/1` during application startup for locales you know you will need.

### Process locale

Set the process locale once rather than passing `:locale` on every call:

```elixir
Localize.put_locale(:de)

# All subsequent calls use :de without option resolution
Localize.Number.to_string(1234.5)
Localize.Date.to_string(~D[2025-07-10])
```
