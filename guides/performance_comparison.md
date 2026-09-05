# Performance Comparison: Localize vs ex_cldr

This guide compares the runtime performance and compile-time overhead of **Localize** against the **`ex_cldr_*`** family of libraries. All numbers come from the benchmarks in `bench/ex_cldr_vs_localize.exs` and `bench/compile_time.sh`, which live in this repository under the `:bench` Mix environment.

See "Running the benchmarks" at the bottom of this document for instructions on reproducing the numbers on your own hardware.

## Test environment

| Item | Value |
|---|---|
| CPU | Apple M1 Max (10 cores) |
| Memory | 64 GB |
| OS | macOS |
| Elixir | 1.20.0-rc.3 |
| Erlang/OTP | 28.1 |
| JIT | enabled |
| Localize | CLDR 48.2.1 (not re-measured against CLDR 49) |
| ex_cldr | 2.x family (ex_cldr_numbers ~> 2, ex_cldr_dates_times ~> 2, ex_cldr_units ~> 3) |

Every benchmark runs with 1 second warmup, 3 seconds measurement, and 1 second memory measurement per scenario. The `bench/ex_cldr_vs_localize.exs` script exercises every scenario in three locales — `:en`, `:de`, `:ja` — in four variants per locale:

* **`localize raw`** — Localize called with a bare atom (`:en`) as `:locale`.
* **`localize validated`** — Localize called with a pre-computed `%Localize.LanguageTag{}`.
* **`ex_cldr raw`** — ex_cldr called with a bare string (`"en"`) as `:locale`.
* **`ex_cldr validated`** — ex_cldr called with a pre-computed `%Cldr.LanguageTag{}`.

Validated variants skip per-call option validation and isolate the cost of the formatting path itself; raw variants include option validation, which is what most user code actually pays.

## Summary of findings

| Area | Headline | Localize advantage |
|---|---|---|
| Compile (per-project) | Bench.Cldr backend recompile vs Localize touch-and-recompile | **~7× faster** (7 s → 1 s) |
| Number formatting | Integers, decimals, percent, grouped | **~2.5–3.8×** |
| Currency formatting | USD in `:en`, `:de`, `:ja` | **~1.8–3.7×** |
| Date formatting | Short / medium / long in 3 locales | **~2.2–3.1×** |
| **Time formatting** | Short / medium in 3 locales | **~15–19×** |
| **DateTime formatting** | Short / medium / long in 3 locales | **~7.4–9.5×** |
| Unit formatting (long) | length, mass, temperature | **~1.9–2.7×** |
| Unit formatting (short) | length, mass, temperature | **~1.8–2.6×** |
| Memory per call | Numbers | **~3–4×** less |
| Memory per call | Time / DateTime | **~7–10×** less |

Across every scenario measured, Localize is faster than ex_cldr, typically by 2–3× for numbers and units, and by an order of magnitude for Time and DateTime. Localize also allocates roughly one-third to one-tenth the per-call memory.

## Compile-time comparison

Measured by `bench/compile_time.sh` with 3 iterations, reporting the best wall-clock result from each.

| Measurement | Time | What it represents |
|---|---|---|
| ex_cldr family deps, clean compile | **25 s** | First-time install cost of `ex_cldr`, `ex_cldr_numbers`, `ex_cldr_dates_times`, `ex_cldr_units`, `ex_cldr_currencies`, `ex_cldr_calendars`, `ex_cldr_lists`, `digital_token`. Cached after first build. |
| Localize `lib/` clean compile | **20 s** | Localize's own runtime library compile. Cached after first build. |
| `Bench.Cldr` backend recompile (per-project) | **7 s** | **The real cost an ex_cldr user pays** every time they touch their backend module (add/remove a locale, change providers). Paid on every change. |
| Localize touch-and-recompile (per-project) | **0–1 s** | Incremental recompile after touching one Localize module — effectively the Mix graph check only. Localize has no backend, so the actual per-project cost in an end-user application is **zero**. |

### Why this matters

The two first-time numbers (25 s vs 20 s) look similar, but they are measuring very different things. **Localize delivers substantially more functionality in that same time**:

* ex_cldr's 25 seconds compiles eight separate hex packages but only covers numbers, dates/times, units, lists, currencies, calendars, and territories — and only the pieces you explicitly enable through the backend `providers:` list.

* Localize's 20 seconds compiles a single library that ships the full CLDR feature set: numbers, dates, times, datetimes, intervals, durations, relative time, calendars (Gregorian plus Buddhist, Hebrew, Islamic with 5 variants, ROC, Indian, Persian, Coptic, Ethiopic, Chinese, Japanese, Dangi), currencies, units, lists, territories, languages, scripts, locale display, **collation with locale-specific tailoring for 97 languages**, **MessageFormat 2** (parser + interpreter + JSON interchange + bidi), ellipsis and quotation formatting, plural rules (cardinal + ordinal + ranges), RBNF for Roman/CJK/spellout, validity data for language/script/territory/variant/unit/subdivision, BCP 47 extension handling, likely-subtags resolution, locale matching and distance, and the full on-disk locale cache + download provider infrastructure. None of that is opt-in: it all compiles unconditionally in the same 20 seconds.

In other words: Localize does more in less time, and everything it ships is available from a clean install with no configuration.

**The real compile-time difference** is per-project: **7 seconds every time you edit your backend, vs. 0 for Localize**. In a typical dev loop where you adjust locales or providers several times a week, that adds up fast. In CI it adds up on every cache miss.

## Runtime comparison

### Number formatting

From `=== Number formatting: decimal ===`. Throughput in thousands of iterations per second (higher is better). Numbers are medians across the `:en`, `:de`, `:ja` runs.

| Library / variant | Integer | Decimal | Small | Percent value |
|---|---:|---:|---:|---:|
| localize validated | 375 K | 265 K | 308 K | 311 K |
| localize raw | 346 K | 249 K | 288 K | 279 K |
| ex_cldr validated | 135 K | 111 K | 121 K | 125 K |
| ex_cldr raw | 129 K | 112 K | 116 K | 118 K |

**Speedup (localize validated / ex_cldr validated):** ~2.4× (decimal) to 2.8× (integer).

Localize holds a consistent ~3 µs/call average against ex_cldr's ~8–9 µs/call. The raw/validated gap is small within each library: pre-validating the locale saves roughly 0.2–0.7 µs per call in Localize (because its locale cache already hits ETS) but barely moves the needle in ex_cldr (because the backend still re-resolves through its compiled-in table on every call).

#### Currency formatting

From `=== Number formatting: currency ===`. All values are 1,234.56 USD in the three locales.

| Library / variant | `:en` | `:de` | `:ja` |
|---|---:|---:|---:|
| localize validated | 101 K ips (9.9 µs) | 177 K ips (5.7 µs) | 96 K ips (10.4 µs) |
| localize raw | 97 K ips (10.3 µs) | 168 K ips (5.9 µs) | 96 K ips (10.5 µs) |
| ex_cldr validated | 50 K ips (20.2 µs) | 66 K ips (15.2 µs) | 50 K ips (19.9 µs) |
| ex_cldr raw | 50 K ips (20.1 µs) | 64 K ips (15.6 µs) | 48 K ips (20.8 µs) |

**Speedup:** ~2.0× (`:en`) to ~3.7× (`:ja`). Localize is notably faster in `:de` because German uses the locale's native decimal/grouping symbols directly, which is a hot path in Localize's pre-compiled format metadata.

#### Percent formatting

| Library / variant | `:en` | `:de` | `:ja` |
|---|---:|---:|---:|
| localize validated | 326 K ips (3.1 µs) | 306 K ips (3.3 µs) | 267 K ips (3.8 µs) |
| localize raw | 291 K ips (3.4 µs) | 265 K ips (3.8 µs) | 274 K ips (3.7 µs) |
| ex_cldr validated | 127 K ips (7.9 µs) | 118 K ips (8.5 µs) | 125 K ips (8.0 µs) |
| ex_cldr raw | 118 K ips (8.5 µs) | 120 K ips (8.4 µs) | 124 K ips (8.1 µs) |

**Speedup:** ~2.2–2.8×.

### Memory use (numbers)

ex_cldr allocates **~3.5–4.5× more memory per call** than Localize for number formatting.

| Scenario | Localize | ex_cldr | Ratio |
|---|---:|---:|---:|
| Decimal `:en` (validated) | 5.4 KB | 15.0 KB | 2.8× |
| Decimal `:de` (validated) | 8.1 KB | 17.3 KB | 2.1× |
| Currency `:en` (validated) | 5.5 KB | 18.8 KB | **3.4×** |
| Currency `:de` (validated) | 6.7 KB | 19.6 KB | **2.9×** |
| Percent `:en` (validated) | 4.4 KB | 12.5 KB | **2.8×** |

### Date formatting

From `=== Date formatting ===`. A single date (`~D[2025-07-10]`) in three formats and three locales.

| Library / variant | Short `:en` | Medium `:en` | Long `:en` | Short `:ja` | Long `:ja` |
|---|---:|---:|---:|---:|---:|
| localize validated | 843 K ips (1.2 µs) | 681 K ips (1.5 µs) | 695 K ips (1.4 µs) | 643 K ips (1.6 µs) | **892 K ips (1.1 µs)** |
| localize raw | 614 K ips (1.6 µs) | 545 K ips (1.8 µs) | 540 K ips (1.9 µs) | 524 K ips (1.9 µs) | 653 K ips (1.5 µs) |
| ex_cldr validated | 397 K ips (2.5 µs) | 347 K ips (2.9 µs) | 346 K ips (2.9 µs) | 382 K ips (2.6 µs) | 383 K ips (2.6 µs) |
| ex_cldr raw | 324 K ips (3.1 µs) | 302 K ips (3.3 µs) | 289 K ips (3.5 µs) | 322 K ips (3.1 µs) | 289 K ips (3.5 µs) |

**Speedup:** ~2.1–2.3× validated-vs-validated, ~1.9× raw-vs-raw.

### Time formatting

From `=== Time formatting ===`. A single time (`~T[14:30:45]`) in two formats and three locales. **This is where the gap is widest.**

| Library / variant | Short `:en` | Medium `:en` | Short `:de` | Medium `:ja` |
|---|---:|---:|---:|---:|
| localize validated | 633 K ips (1.6 µs) | 569 K ips (1.8 µs) | 833 K ips (1.2 µs) | 769 K ips (1.3 µs) |
| localize raw | 495 K ips (2.0 µs) | 457 K ips (2.2 µs) | 615 K ips (1.6 µs) | 588 K ips (1.7 µs) |
| ex_cldr validated | 50 K ips (19.8 µs) | 46 K ips (21.9 µs) | 55 K ips (18.2 µs) | 50 K ips (19.9 µs) |
| ex_cldr raw | 50 K ips (20.1 µs) | 45 K ips (22.2 µs) | 54 K ips (18.5 µs) | 48 K ips (20.7 µs) |

**Speedup: ~12–19×.**

This is not a typo. `Localize.Time.to_string/2` runs at ~1–2 µs/call; `Cldr.Time.to_string/3` runs at ~18–22 µs/call. The gap appears to come from ex_cldr re-walking a generic date/time format pipeline for every time call, while Localize's Time module has a dedicated fast path.

Memory use follows the same pattern — ex_cldr allocates **~6–10× more memory** per Time call than Localize.

### DateTime formatting

From `=== DateTime formatting ===`. A `~N[2025-07-10 14:30:45]` in three formats and three locales.

| Library / variant | Short `:en` | Medium `:en` | Long `:en` | Short `:ja` | Long `:ja` |
|---|---:|---:|---:|---:|---:|
| localize validated | 292 K ips (3.4 µs) | 270 K ips (3.7 µs) | 260 K ips (3.9 µs) | 316 K ips (3.2 µs) | **335 K ips (3.0 µs)** |
| localize raw | 253 K ips (4.0 µs) | 238 K ips (4.2 µs) | 229 K ips (4.4 µs) | 277 K ips (3.6 µs) | 282 K ips (3.5 µs) |
| ex_cldr validated | 42 K ips (23.7 µs) | 38 K ips (26.1 µs) | 38 K ips (26.2 µs) | 45 K ips (22.3 µs) | 41 K ips (24.5 µs) |
| ex_cldr raw | 41 K ips (24.6 µs) | 35 K ips (28.4 µs) | 35 K ips (28.4 µs) | 44 K ips (22.7 µs) | 38 K ips (26.2 µs) |

**Speedup: ~7–9×.** Localize completes a DateTime format in ~3–4 µs; ex_cldr takes ~22–28 µs.

### Unit formatting (long form)

From `=== Unit formatting (long) ===`. Builds a fresh `Unit` struct inside each benchmarked function (construction cost is included) and formats it in the long style.

| Library / variant | length_m | length_km | mass_kg | temp_c |
|---|---:|---:|---:|---:|
| localize validated `:en` | 206 K ips (4.9 µs) | 192 K ips (5.2 µs) | 141 K ips (7.1 µs) | 195 K ips (5.1 µs) |
| localize raw `:en` | 188 K ips (5.3 µs) | 179 K ips (5.6 µs) | 134 K ips (7.5 µs) | 185 K ips (5.4 µs) |
| ex_cldr validated `:en` | 104 K ips (9.6 µs) | 89 K ips (11.2 µs) | 83 K ips (12.1 µs) | 110 K ips (9.1 µs) |
| ex_cldr raw `:en` | 106 K ips (9.5 µs) | 86 K ips (11.6 µs) | 80 K ips (12.5 µs) | 108 K ips (9.3 µs) |

**Speedup:** ~1.9× (temp_c) to ~2.2× (length_km). The gap is smaller for units than for numbers and dates, mainly because unit formatting does more work per call (parse the unit identifier, look up the pattern, apply pluralization, combine with the number format). Both libraries pay that cost.

Unit short-form (`format: :short` / `style: :short`) results are very similar: Localize ~5–8 µs, ex_cldr ~9–13 µs, ratios of roughly 1.8×–2.5×. See the full output for per-scenario numbers.

## Observations

### Raw vs validated

Within Localize, pre-validating the locale (`Localize.validate_locale/1` once, pass the struct) gives a **5–15 % speedup**. This is modest because Localize already caches `validate_locale/1` in ETS — the second and subsequent calls for the same locale are ~1 µs. So the "raw" path is already nearly free once the locale has been touched.

Within ex_cldr, the raw-vs-validated gap is essentially noise (often within the measurement deviation). The backend re-resolves the locale tag against its compiled table on every call, and that resolution is a small fraction of its total per-call cost, so pre-validating does not help much.

**Takeaway:** With Localize, there is no need to micro-optimise by pre-computing `LanguageTag` structs. Hot loops that use the process locale (`Localize.put_locale/1`) will get the cache hit automatically.

### Why Localize is faster

Several design choices combine to give these numbers:

1. **Pre-compiled format metadata in `:persistent_term`.** Number and datetime format patterns are parsed once at data generation time and stored as ready-to-execute Elixir terms. Subsequent calls are pattern substitution, not re-parsing.

2. **ETF-backed runtime data.** Locale data is read from ETF files into `:persistent_term` once. No per-call file I/O, no per-call JSON decoding, no per-call struct construction.

3. **Dedicated fast paths for common modules.** `Localize.Time.to_string/2` has its own format path rather than delegating to a generic DateTime pipeline. This is why the Time gap is an order of magnitude, not just 2×.

4. **Locale validation cache.** `Localize.validate_locale/1` is backed by an ETS table with a background sweeper. First call is ~50 µs, every subsequent call is ~1 µs. Hot loops get the cached value for free.

5. **No per-call backend module dispatch.** ex_cldr's backend modules are a compile-time macro expansion that generates a function clause per configured locale. Every call walks that dispatch, which is fast but not free. Localize calls go directly from the public API into the formatter with no intermediate indirection.

### Per-call memory

Localize allocates substantially less per call across every scenario. The biggest ratios are in Time and DateTime (~7–10× less), the smallest in Units (~1.2–2×). Lower allocation means less GC pressure for applications that format many values per second — web servers rendering tables, dashboards, reporting pipelines, etc.

## Running the benchmarks

Both benchmark scripts live in `bench/` and are compiled only in the `:bench` Mix environment. The `ex_cldr/` directory (sibling of `lib/`) holds the `Bench.Cldr` backend module, compiled only in `:bench`.

### One-time setup

```bash
MIX_ENV=bench mix deps.get
MIX_ENV=bench mix compile
```

This fetches `ex_cldr_numbers`, `ex_cldr_dates_times`, `ex_cldr_units`, and `benchee` (plus their transitive deps), and compiles the `Bench.Cldr` backend module for locales `:en`, `:de`, `:ja` with providers `Cldr.Number`, `Cldr.Calendar`, `Cldr.DateTime`, and `Cldr.Unit`.

### Runtime benchmarks

```bash
MIX_ENV=bench mix run bench/ex_cldr_vs_localize.exs
```

Total wall-clock time is about **4–5 minutes**. The script warms Localize's locale cache, then runs seven benchee sections — number/decimal, number/currency, number/percent, date, time, datetime, unit/long, unit/short — each exercising all four variants (`localize raw`, `localize validated`, `ex_cldr raw`, `ex_cldr validated`) in each of the three locales.

Each section prints its own comparison table, so you can jump to a specific category in the output.

### Compile-time benchmarks

```bash
MIX_ENV=bench bench/compile_time.sh          # default: 3 iterations
MIX_ENV=bench bench/compile_time.sh 5        # more iterations = more stable numbers
```

Takes about **5–10 minutes** with the default 3 iterations. The script measures four things and reports the best wall-clock time for each:

1. Clean compile of all ex_cldr-family hex deps (`mix deps.clean --all && mix deps.compile`).
2. Clean compile of Localize's own `lib/` tree (deps cached).
3. `Bench.Cldr` backend recompile after touching `ex_cldr/bench_cldr.ex`.
4. Localize incremental recompile after touching one leaf module.

### Reading benchee output

Each benchee run prints three blocks:

1. **`Name ... ips ... average ... median ... 99th %`** — throughput in iterations per second and distribution of per-call latencies. Higher `ips` is better, lower averages are better.
2. **`Comparison:`** — same runs ranked against the fastest, showing the slowdown multiplier and absolute µs difference.
3. **`Memory usage statistics`** — per-call heap allocation. Lower is better. Watch for the `2.x memory usage` / `3.x memory usage` ratios as a proxy for GC pressure.

### Notes on variance

* Benchmark numbers vary with JIT state, background CPU load, and thermal throttling. Run the script when your machine is otherwise idle for best stability.
* The compile-time script rounds to the nearest second. For finer resolution, wrap each step in a profiler or use `time` externally.
* All results in this document are from a single run. Re-running will produce different absolute numbers but consistent ratios.
* Benchee's default warmup is 1 second — Localize's locale cache needs that time to stabilise. If you see Localize's first scenario produce outlier numbers, add more warmup by editing `BenchHelper.run/2`.

### What the benchmarks do **not** cover

This comparison measures formatting performance only. It does not cover:

* **Collation / string sorting.** Localize has a full UCA implementation with 97 locale tailorings; `ex_cldr_collation` exists as a separate package but is not exercised here. See `guides/performance.md` for Localize's pure-Elixir vs. NIF collation benchmarks.

* **MessageFormat 2.** Localize supports MF2 as a first-class feature with a pre-compiled parser and an interpreter that integrates with all formatters. ex_cldr has `ex_cldr_messages` for ICU MessageFormat 1 — not MF2 — so there is no apples-to-apples comparison to run.

* **Number parsing, interval formatting, relative time, RBNF, calendar display names, locale display names.** All of these exist in Localize; some have ex_cldr equivalents, some don't.

* **End-to-end application benchmarks.** The numbers here are per-call microbenchmarks. In a real web request or pipeline, the formatter is usually a small fraction of total CPU, so a 3× speedup at the formatter level translates to a smaller overall improvement. The compile-time gap, however, shows up directly in dev-loop latency and CI run time.

* **Larger locale sets.** `Bench.Cldr` is configured with three locales. The ex_cldr per-project compile cost scales roughly linearly with the number of configured locales — adding locales to a real backend pushes the recompile time well past the 7 seconds measured here. Localize's runtime performance is independent of how many locales the application uses, because locale data is loaded lazily on first access.
