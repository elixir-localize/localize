# Inflection lexicon packing — plan

Date: July 27, 2026. **Post-1.0 work on the `inflection` branch**, targeting 1.1. Goal: cut the in-memory footprint of the inflection lexicons by roughly an order of magnitude by replacing the per-locale `Map` with a packed binary representation, without changing any public behaviour.

## Status: Phase 1 implemented

`Localize.Inflection.Lexicon` packs each locale's lexicon at load time and `Localize.Inflection.Data` stores and reads that form. Measured outcome against the map representation, isolating the lexicon itself across an 11-locale spread:

* **Lexicon memory: 433.1 MB → 40.0 MB, 10.8× smaller** — better than the 8.8× estimate below, because value interning compresses more than the model assumed.

* **Literal area: 433.1 MB → effectively zero.** This was not anticipated and is the most useful result. Packed sections are large refc binaries, which live in the global binary heap rather than the BEAM literal area — and the literal area is exactly what `+MIscs` sizes. The flag pressure from lexicons therefore disappears; what remains in the literal area is the non-lexicon metadata (see *Remaining hot spot*).

* **All 48 locales resident: ~838 MB → 203.7 MB total**, of which ~114 MB is literal area (measured one locale per fresh VM; sequential in-process deltas are unreliable at this scale because the binary allocator frees asynchronously).

* Lookup cost rose from a single map read to ~4–9 µs (binary search plus a block scan), against 8–21 µs for the surrounding inflection work — immaterial in context.

* Correctness: every key of `tr`, `fi` and `pl` plus 2,000-key samples of `de`, `ru` and `ar` resolve identically to the map, and the full inflection and pronoun conformance suites pass unchanged.

* **Regression to fix: first-touch load time roughly tripled** (German ~700 ms → ~2.9 s, Arabic ~620 ms → ~3.6 s) because packing adds a sort plus a linear pass on top of building the map that is then discarded. The full test suite, which loads every locale, went from 47.1 s to 61.9 s. This makes Phase 2 (pack in the generator, so loading is a plain binary read) a priority rather than the optional nicety it is described as below, and it is the natural next step: the packer already exists and simply needs to run in `data/inflection_gen/generate.ex` instead of at load.

### Remaining hot spot

Arabic still costs ~112 MB, of which ~85 MB is literal area, because its **14,121 inflection patterns** — not its lexicon — dominate. Hebrew is the same shape at a smaller scale. Packing `patterns` the same way is the obvious follow-on if Arabic's footprint matters.

## The problem, measured

Loading all 48 locales costs ≈838 MB of BEAM literal area, which is why dev/test/CI must set `ELIXIR_ERL_OPTIONS="+MIscs 3072"`. The measurement below (11-locale spread, OTP 29, `:persistent_term.info().memory` deltas) shows that footprint is **not** the linguistic data — it is per-entry BEAM structure.

| locale | entries | in memory | raw key bytes | front-coded keys | distinct values | mask bits | packed estimate | ratio |
|--------|--------:|----------:|--------------:|-----------------:|----------------:|----------:|----------------:|------:|
| en | 127,524 | 12.4 MB | 1.1 MB | 0.6 MB | 4,963 | 48 | 1.7 MB | 7.5× |
| fr | 257,114 | 25.3 MB | 2.6 MB | 1.0 MB | 8,236 | 46 | 3.3 MB | 7.8× |
| es | 559,750 | 55.7 MB | 5.7 MB | 2.1 MB | 23,615 | 50 | 7.6 MB | 7.3× |
| de | 1,280,915 | 123.0 MB | 16.0 MB | 5.9 MB | 6,836 | 54 | 18.0 MB | 6.9× |
| ru | 917,072 | 97.6 MB | 18.6 MB | 3.9 MB | 11,257 | 55 | 12.9 MB | 7.6× |
| cs | 248,422 | 23.0 MB | 2.7 MB | 1.1 MB | 6,362 | 50 | 3.3 MB | 7.0× |
| pl | 26,483 | 2.9 MB | 0.2 MB | 0.1 MB | 4,378 | 52 | 0.3 MB | 8.8× |
| ar | 813,579 | 166.4 MB | 15.7 MB | 4.3 MB | 741,064 | 41 | 11.6 MB | 14.4× |
| he | 147,770 | 25.5 MB | 1.6 MB | 0.6 MB | 104,618 | 37 | 1.7 MB | 14.6× |
| fi | 12,416 | 1.9 MB | 0.1 MB | 0.1 MB | 6,521 | 43 | 0.2 MB | 11.4× |
| tr | 3,685 | 0.3 MB | 0.0 MB | 0.0 MB | 231 | 43 | 0.0 MB | 7.2× |
| **total** | | **534.1 MB** | | | | | **60.5 MB** | **8.8×** |

Three findings drive the design:

* **~7× of the footprint is BEAM overhead, not data.** German holds 1.28M entries in 123 MB, but its key bytes total 16 MB and its entire packed form is 18 MB. The remaining ~105 MB is per-entry structure — HAMT nodes, binary headers, value tuples, list cells — paid 1.28M times. Collapsing to a handful of binaries is what recovers it.

* **Front-coding compresses sorted keys 2–5×** (ru 18.6 MB → 3.9 MB, de 16.0 MB → 5.9 MB). Morphologically rich languages compress most, because inflected forms of a lemma sort adjacently and share long stems.

* **Values are highly redundant outside Semitic.** German has 6,836 distinct `{mask, pattern_indexes}` values across 1.28M entries, so interning the value table and pointing entries at it by index is a large additional win. Arabic and Hebrew are the opposite (741K distinct across 814K entries — root-and-pattern morphology), where interning is a wash rather than a win. Interning is therefore applied unconditionally: a big win where dedup exists, neutral where it does not, and one code path either way.

Extrapolating 8.8× to the full set puts all 48 locales at **≈95 MB, down from ≈838 MB**.

## Why not a trie, DAWG, or FST

A prefix trie built from nested Elixir maps would be **worse** than the status quo: it multiplies per-node term and HAMT overhead across millions of nodes, and the overhead is exactly what we are trying to remove.

A DAWG/DAFSA (shares suffixes as well as prefixes) or a serialized FST would compress keys further than front-coding — ru might go from 3.9 MB to ~2 MB. But once the map overhead is gone, keys are already the minority of the packed size, so the incremental gain is small against a large increase in build complexity. Front-coding plus value interning is the point of diminishing returns; a DAWG is the escalation to consider only if many locales must be resident simultaneously and ~95 MB is still too much.

## Representation

One `Localize.Inflection.Lexicon` struct per locale, holding a small number of binaries rather than one binary with internal offsets. Separate binaries avoid all offset arithmetic in the reader, and cost only a few words of struct overhead per locale.

```
%Lexicon{
  keys:          binary,   # front-coded, sorted by byte order
  blocks:        binary,   # block_count × uint32 offsets into keys
  values:        binary,   # interned value records
  value_offsets: binary,   # value_count × uint32 offsets into values
  ord_to_value:  binary,   # entry_count × uint(value_width) value numbers
  entry_count:   integer,
  value_count:   integer,
  mask_width:    integer,  # bytes per grammeme mask
  index_width:   integer,  # bytes per pattern index
  value_width:   integer,  # bytes per value number
  block_size:    integer   # keys per block (32)
}
```

**Keys.** Keys are sorted by byte order (the same ordering Elixir's `<`/`>` use on binaries, so search and build agree). Each key is emitted as `varint(shared_prefix_len) varint(suffix_len) suffix_bytes`, where the shared prefix is measured against the preceding key. The first key of every block is forced to `shared_prefix_len = 0` so decoding can start at any block boundary without prior context.

**Blocks.** One `uint32` per block giving the byte offset in `keys` where that block starts. With `block_size = 32` a 1.28M-entry locale needs 40K blocks = 160 KB. Larger blocks shrink this index *and* improve front-coding (fewer forced-full keys), at the cost of more linear decoding per lookup; 32 balances the two.

**Values.** The distinct `{mask, pattern_indexes}` values, each emitted as `mask(mask_width) varint(index_count) index(index_width)*`. `value_offsets` gives each value number its byte offset. Pattern indexes keep their original list order, which `Dictionary.patterns_for_word/2` depends on.

**Ordinal → value.** A fixed-width array so the *n*-th key's value number is a constant-time slice.

Widths are computed per locale from the data (`mask_width` from the largest mask, `index_width` from the largest pattern index, `value_width` from `value_count`), so no locale pays for another's range.

## Lookup

`Lexicon.lookup(lexicon, word)` returns `{mask, pattern_indexes}` or `nil`:

1. Binary search `blocks` for the last block whose first key is `<= word`. Each probe decodes one full key (the block's first key is stored whole).

2. Linearly decode that block's keys, reconstructing each from the running prefix, comparing against `word`, and stopping early once a key sorts past it. This yields the ordinal.

3. Slice `ord_to_value` at `ordinal × value_width` for the value number, `value_offsets` at `value_number × 4` for the record offset, then decode the record.

Cost is O(log n) probes plus at most `block_size` short binary reconstructions — a few microseconds, against near-O(1) for the map. Lookups happen per word during formatting, not in a tight inner loop, so this is an acceptable trade for an ~8× memory reduction. `Data.lookup/2` keeps its lowercase fallback by calling `Lexicon.lookup/2` a second time.

## Call sites

The lexicon is already fully encapsulated, which makes this change small and low-risk:

* `Localize.Inflection.Data.load/1` builds the artifact — the one place the lexicon is constructed.

* `Localize.Inflection.Data.lookup/2` is the **only** reader, via its private `lookup_form/2`.

* `Localize.Inflection.Dictionary` calls `Data.lookup/2` at three sites (`combined_grammemes/2`, `patterns_for_word/2`, and the grammeme-set reader) and never touches the map itself.

* Every other `Data.metadata!/1` caller reads a different key (`grammeme_bits`, `grammeme_names`, `patterns`, `features`, `suffix_exemplars`, `contractions`, `pronouns`) and is unaffected.

## Phasing

**Phase 1 — pack at load time (this plan).** `Data.load/1` reads the ETF exactly as today and packs the lexicon before the `:persistent_term.put`. This delivers the full memory win with **no data regeneration, no CDN re-upload, and no inflection data version bump**, so it cannot disturb published artifacts. Packing costs a sort plus a linear pass at first touch, offset by no longer building a million-entry map.

**Phase 2 — pack at generation time (later, optional).** Emit the packed sections directly into each locale's `.etf` so loading is a pure binary slurp and first-touch load time drops to near-zero. This requires regenerating all 48 locales, re-uploading to R2, and bumping `priv/localize/localize_inflection_sha`, so it should ride along with a data refresh rather than being done for its own sake.

## Testing

* **Differential equivalence** is the primary gate: for each covered locale, pack the lexicon and assert `Lexicon.lookup/2` returns exactly what `Map.get/2` returns for **every** key in the lexicon, plus a set of known misses. This is exhaustive rather than sampled, so an encoding bug cannot hide.

* **Round-trip** of pattern index order and mask values, including the widest masks (ru at 55 bits) and multi-pattern entries.

* **Edge cases**: empty lexicon, single entry, keys that are prefixes of one another (`"cat"` / `"cats"`), non-ASCII keys (ru, ar, he), keys spanning block boundaries, and the lowercase fallback path.

* The existing inflection and pronoun conformance suites are the end-to-end backstop: they exercise real lookups across every supported locale and must stay green unchanged.

## Risks

* **Lookup latency** rises from map-constant to O(log n) plus a short scan. Mitigation: measure warm lookup before and after; if a hot path regresses materially, raise `block_size` or add a small per-locale cache. Inflection is already tens of microseconds per call, so a few microseconds is within noise.

* **Encoding bugs are silent** — a mis-decoded value returns a wrong inflection rather than crashing. Mitigation: the exhaustive differential test above, which compares every key rather than a sample.

* **Load-time cost** shifts from map building to sort + pack. Mitigation: measure first-touch load per locale before and after; the sort is the only new O(n log n) step and map building was never free.
