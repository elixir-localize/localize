# CLDR 49 Cycle

## RBNF rule format in CLDR JSON

RBNF rules are in a new text format in the source XML. They may also be diffrently formatted in the generated JSON.

We need to move to using the new format. This means:

1. Investigate the source data for RBNF in our pipeline
2. Review any changes to the rule layout in the source data
3. Adapt to the new format (but generate the same output in our pipeline)

## New package: localize_emoji

Add a new package to the localize umbrella that provides locale-aware emoji
lookup based on CLDR annotations and annotationsDerived data.

### Scope

Consume both annotations (human-curated) and annotationsDerived
(algorithmically composed sequences such as ZWJ and skin-tone variants)
from CLDR 49.
Provide forward lookup: emoji → %{tts: binary, keywords: [binary]}.
Provide reverse lookup keyed by keyword, optimised for multi-keyword
queries (AND, OR, and ranked relevance).
Parameterise all data by locale.

### Recommended data structures

* Compile-time inverted index per locale: %{keyword => MapSet.t(emoji)}, embedded as module attributes so the data resides in the BEAM literal pool.
* Forward index as %{emoji => annotation_record}, also compile-time.
* Multi-keyword intersection sorted by cardinality (smallest set first) to minimise intermediate work.
* Optional scored index variant (%{keyword => %{emoji => score}}) to support ranking where tts matches outrank keyword matches.
* Defer bitset/bitstring representation unless benchmarks identify the inverted index as a bottleneck; reconsider if real-time autocomplete over the full emoji set becomes a use case.

### Module layout

One module per locale (e.g. Localize.Emoji.Index.En) to keep individual
literal pools tractable and allow unused locales to be excluded from a
release via configuration.

### Open questions

Fuzzy/substring matching: defer to a later cycle unless there is demand.
Provenance tracking: decide whether consumers need to distinguish
human-translated annotations from derived ones at lookup time, or whether
the merge can be opaque.