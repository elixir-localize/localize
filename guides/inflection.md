# User guide

This guide covers the practical use of `Localize.Inflection`: inflecting words and phrases, querying grammatical features, and selecting pronouns. If you are new to grammatical inflection itself, start with [What is inflection?](https://hexdocs.pm/localize/what_is_inflection.html).

## Inflection data

Inflection is part of Localize, and its data is optional: nothing is downloaded unless you ask for it. Each locale ships as a single `<locale>.etf` carrying its dictionary, grammatical metadata, and pronoun table, built from the [Unicode inflection project](https://github.com/unicode-org/inflection) at a pinned commit.

`mix localize.download_locales` downloads inflection data alongside the locale data, so the usual one command provisions both — no separate step:

```
mix localize.download_locales            # locales + inflection for the configured :supported_locales
mix localize.download_locales en de ru   # locales + inflection for these
```

Locales the inflection project does not support are skipped, and regional locales map to their parent language (`en-AU` uses `en`). To fetch inflection data on its own, `mix localize.download_inflection` takes the same arguments. Each file is verified against a SHA-256 manifest shipped in the package before it is written. Locales you never download cost nothing; inflection functions return `{:error, %Localize.InflectionDataNotAvailableError{}}` when a locale's data is not present — distinct from `%Localize.InflectionNotSupportedError{}` for languages the Unicode inflection project does not cover.

The data directory follows the locale-cache configuration convention:

```elixir
# Recommended: anchor to your application
config :localize, otp_app: :my_app

# Or a fully custom absolute location
config :localize, inflection_data_dir: "/var/lib/localize/inflection"
```

### On-demand download

Beyond the build-time task, a missing locale can be fetched the first time it is used, reusing the same gate as CLDR locale data (off by default):

```elixir
config :localize, allow_runtime_locale_download: true
```

With downloads permitted, resolving a locale whose artifact is not present fetches `<locale>.etf` from the CDN, verifies it against the manifest, writes it to the data directory, and continues. Regional locales fall back to their parent language (`en-AU` uses `en`). An application that provisions its locales at build time leaves this off and never fetches at runtime.

### Memory and the literal area

A locale's artifact loads lazily: the first operation on a locale loads its lexicon and metadata into `:persistent_term`, where reads are copy-free; subsequent operations are lookups measured in microseconds.

The lexicon — the bulk of the data — is held in a packed binary form rather than a map, which keeps it out of the BEAM *literal area*: binaries of any size are stored in the shared binary heap, and only the small wrapper is a literal. What remains in the literal area is each locale's metadata, principally its inflection patterns. That matters because `:persistent_term` holds terms in the literal area, and exhausting the default literal super carrier aborts the emulator with `literal_alloc: Cannot allocate ...`.

Most applications use a handful of locales and need no tuning. Loading **all 48 at once** needs roughly 114 MB of literal area (and ~195 MB in total), which still exceeds the default. Raise it with an emulator flag (`vm.args`, `rel/env.sh`, or `ELIXIR_ERL_OPTIONS`) sized to the locales you actually load, with headroom:

```
+MIscs 3072
```

Arabic is the outlier: its ~14,000 inflection patterns account for ~82 MB of its ~109 MB, nearly all of it literal area, so an application loading Arabic should budget for it specifically.

## Quick start

The three top-level functions cover most needs:

```elixir
iex> Localize.Inflection.inflect("light on the patio", :en, number: :plural)
{:ok, "lights on the patio"}

iex> Localize.Inflection.feature("luces", :es, :number)
{:ok, :plural}

iex> Localize.Inflection.pronoun(:en, person: :first, case: :genitive)
{:ok, "mine"}
```

## Inflecting words and phrases

`Localize.Inflection.inflect/3` takes a word or phrase, a locale atom, and constraints as a keyword list or map. Constraint names are feature names; values are grammemes. The common features are `number`, `gender`, `case`, `definiteness`, `person` and `pos` (part of speech); each language defines its own inventory in the upstream `grammar.xml`.

```elixir
iex> Localize.Inflection.inflect("universidad", :es, number: :plural, definiteness: :definite)
{:ok, "las universidades"}

iex> Localize.Inflection.inflect("новый дом", :ru, case: :instrumental)
{:ok, "новым домом"}

iex> Localize.Inflection.inflect("talo", :fi, case: :inessive)
{:ok, "talossa"}

iex> Localize.Inflection.inflect("집", :ko, case: :nominative)
{:ok, "집은"}

iex> Localize.Inflection.inflect("दरवाज़ा में", :hi, number: :singular)
{:ok, "दरवाज़े में"}
```

Each of these exercises a different part of the machinery: Spanish selects an agreeing article, Russian inflects both the adjective and the noun to the instrumental case, Finnish replaces a preposition with the inessive case suffix, Korean attaches the topic particle in its consonant-final form (은 rather than 는), and Hindi shifts the noun into the oblique case because it stands before the postposition में.

Gender inflection produces the counterpart form where one exists in the data — *gato* / *gata*, *लड़का* (boy) / *लड़की* (girl) — and features compose freely, so an adjective can move to feminine and dative in one call:

```elixir
iex> Localize.Inflection.inflect("gato", :es, gender: :feminine)
{:ok, "gata"}

iex> Localize.Inflection.inflect("लड़का", :hi, gender: :feminine)
{:ok, "लड़की"}

iex> Localize.Inflection.inflect("кошка", :ru, case: :dative)
{:ok, "кошке"}

iex> Localize.Inflection.inflect("новый", :ru, gender: :feminine, case: :dative)
{:ok, "новой"}
```

A noun with fixed gender and no counterpart form comes back unchanged rather than being forced.

Phrases are handled by each language's synthesizer: significant words are identified, agreement rules applied, and the original separators preserved. Unknown words fall back to suffix-based guessing where the language supports it, and the original string is preserved when no inflection applies.

## Querying grammatical features

`Localize.Inflection.feature/3` asks the dictionary (and the language's heuristics) about a word or phrase:

```elixir
iex> Localize.Inflection.feature("cats", :en, :number)
{:ok, :plural}

iex> Localize.Inflection.feature("universidad", :es, :gender)
{:ok, :feminine}

iex> Localize.Inflection.feature("дом", :ru, :gender)
{:ok, :masculine}
```

The result is `{:ok, nil}` when the feature cannot be determined. Feature queries are the building block for grammar-dependent message selection — choosing a message variant by the gender or number of a runtime value.

## Discovering the valid features

Every language defines its own feature inventory (from the upstream `grammar.xml`): German has four cases, Russian seven, Finnish a dozen, and English just three (with only the genitive marked on nouns). `Localize.Inflection.features/1` returns the full inventory for a locale, and `Localize.Inflection.feature_values/2` the valid grammemes of one feature — useful both for validation and for building UIs or tooling over the grammar:

```elixir
iex> Localize.Inflection.feature_values(:de, :case)
{:ok, [:accusative, :dative, :genitive, :nominative]}

iex> Localize.Inflection.feature_values(:fi, :case)
{:ok, [:abessive, :ablative, :adessive, :allative, :elative, :essive, :genitive, :illative, :inessive, :nominative, :partitive, :translative]}

iex> {:ok, features} = Localize.Inflection.features(:es)
iex> features.gender
%{type: :bounded, values: [:feminine, :masculine, :neuter]}
```

Constraints put on a concept are validated against this inventory, so an invalid grammeme fails fast with `{:error, {:invalid_feature_value, ...}}` rather than silently not inflecting. Feature names and grammeme values are atoms at the API surface; strings are also accepted (MessageFormat 2 option values arrive as strings) and are normalized internally. What each grammeme means, with examples, is covered in the [grammatical features guide](https://hexdocs.pm/localize/grammatical_features.html).

## The Concept API

[Localize.Inflection.Concept](https://hexdocs.pm/localize/Localize.Inflection.Concept.html) is the lower-level API behind `inflect/3` and `feature/3`, mirroring the upstream `InflectableStringConcept`. Use it when you apply several constraints stepwise, query features of the inflected form, or need the spoken-form channel.

```elixir
iex> {:ok, concept} = Localize.Inflection.Concept.new(:de, "Haus", constraints: %{case: :dative, number: :plural})
iex> Localize.Inflection.Concept.to_speakable_string(concept)
"Häusern"
```

* `new/3` accepts `:constraints` (features to apply when rendering) and `:initial` (features known to hold for the value itself, such as a proper noun's gender, used when deriving other features).

* `put_constraint/3` adds one constraint, validating the feature name and value against the locale's feature model.

* `feature_value/2` returns a stored constraint or computes the feature from the display string.

* `exists?/1` returns true when the constraints can be satisfied without guessing — useful to decide between a grammatical message variant and a neutral fallback.

* `to_speakable_string/1` renders the concept.

### Speakable strings

Rendered values are speakable strings: a plain binary when the printed and spoken forms agree, or a `{print, speak}` tuple when they differ. Danish renders the stressed definite article *dén* as the spoken form of *den*; an explicit `"speak"` constraint sets the spoken channel directly:

```elixir
iex> {:ok, concept} = Localize.Inflection.Concept.new(:en, "light", constraints: %{number: :plural, speak: "lites"})
iex> Localize.Inflection.Concept.to_speakable_string(concept)
{"lights", "lites"}
```

Use `Localize.Inflection.SpeakableString.print/1` and `speak/1` to take either channel.

## Pronouns

`Localize.Inflection.pronoun/2,3` selects a pronoun from the locale's pronoun table by grammatical constraints, optionally reinflecting an existing pronoun:

```elixir
iex> Localize.Inflection.pronoun(:en, person: :first, case: :genitive)
{:ok, "mine"}

iex> Localize.Inflection.pronoun(:en, "they", gender: :feminine)
{:ok, "she"}

iex> Localize.Inflection.pronoun(:en, "him", case: :nominative)
{:ok, "he"}
```

Reinflection preserves what you do not override: "him" carries third person and singular number into the nominative request, yielding "he" rather than the generic "they". A pronoun passed back with no changed constraints is returned as-is.

[Localize.Inflection.PronounConcept](https://hexdocs.pm/localize/Localize.Inflection.PronounConcept.html) exposes the full model:

* **Custom pronoun entries** are searched before the locale table — the mechanism for neopronouns or dialect forms:

```elixir
iex> display_data = [{"y'all", %{person: :second, number: :plural, case: :nominative}}]
iex> {:ok, concept} = Localize.Inflection.PronounConcept.new(:en, display_data: display_data)
iex> {:ok, concept} = Localize.Inflection.PronounConcept.put_constraint(concept, :person, :second)
iex> Localize.Inflection.PronounConcept.to_speakable_string(concept)
"y'all"
```

* **Sound-dependent selection** matches a pronoun against the word it stands next to. French elides *je* to *j'* before a vowel:

```elixir
iex> {:ok, pronoun} = Localize.Inflection.PronounConcept.new(:fr)
iex> {:ok, pronoun} = Localize.Inflection.PronounConcept.put_constraint(pronoun, :person, :first)
iex> {:ok, pronoun} = Localize.Inflection.PronounConcept.put_constraint(pronoun, :number, :singular)
iex> {:ok, pronoun} = Localize.Inflection.PronounConcept.put_constraint(pronoun, :case, :nominative)
iex> {:ok, verb} = Localize.Inflection.Concept.new(:fr, "appareil")
iex> Localize.Inflection.PronounConcept.to_speakable_string(pronoun, verb)
"j’"
```

* `exists?/1` reports whether any pronoun matches the constraints exactly (rendering falls back to the most generic entry when none does), and `custom_match?/1` reports whether a custom entry matched.

Regional locales resolve through a fallback chain: `:"zh-TW"` uses the Traditional Chinese pronoun table, `:"zh-HK"` the Cantonese one, and both use the base language's feature model. Locale atoms are canonically BCP47 (`:"zh-TW"`); the underscore form (`:zh_TW`) is also accepted.

## Locale coverage

31 languages have full inflection synthesizers, each passing its complete upstream conformance suite: ar, bn, cs, da, de, en, es, fi, fr, gu, he, hi, it, kn, ko, ml, mr, nb, nl, pa, pl, pt, ro, ru, sr, sv, ta, te, tr, uk and ur. 25 languages pass the upstream pronoun suites. A further 17 locales (bg, ca, el, hr, hu, id, is, ja, kk, lt, ms, or, sk, th, vi, yue, zh) ship dictionary and feature data without a language-specific synthesizer: feature queries and pronoun selection work; language-specific phrase synthesis does not.

## Quantifying: numbers with agreeing nouns

`Localize.Inflection.quantify/4` joins a pre-formatted number with a noun that agrees grammatically with the count — the foundation for units of measure. The plural category drives a number constraint (singular, dual or plural where the language has them), per-language rules govern the noun's case, and a per-language join places number, noun and any measure word:

```elixir
iex> Localize.Inflection.quantify("2", "kilometer", :en, plural: :other)
{:ok, "2 kilometers"}

iex> Localize.Inflection.quantify("2", "час", :ru, plural: :few)
{:ok, "2 часа"}

iex> Localize.Inflection.quantify("5", "час", :ru, plural: :many)
{:ok, "5 часов"}

iex> Localize.Inflection.quantify("3", "talo", :fi, plural: :other)
{:ok, "3 taloa"}

iex> Localize.Inflection.quantify("2", "رسالة", :ar, plural: :two)
{:ok, "رسالتان"}

iex> Localize.Inflection.quantify("3", "개", :ko, plural: :other)
{:ok, "3개"}
```

The Russian examples show numeral government: two takes the genitive singular paucal, five the genitive plural. Finnish counts above one take the partitive. Arabic renders two as the dual form of the noun alone — the number disappears because the dual carries it. Korean joins without a space after a Hangul noun, and a `measure: "개"` constraint places a classifier.

Formatting the number (including spelled-out numerals) stays with the caller — the number arrives as a string or `{print, speak}` speakable, so it composes with any of Localize's number formats. The CLDR plural category comes from Localize's own plural rules when you pass the numeric value as `number:`, or can be supplied directly as `plural:` when the category has already been selected (for example by a MessageFormat 2 `.match`). Without either, quantify returns `{:error, %Localize.NoPluralCategoryError{}}` rather than guessing.

Every quantification behavior is verified against the upstream project's QuantifyTest expectations: 286 assertions across 21 languages, all passing.

## And/or lists with grammatical agreement

`Localize.Inflection.ConceptList` renders lists of concepts with locale-correct conjunctions — beyond `Localize.List`'s pattern formatting, the conjunctions here are grammatical: Spanish *y* becomes *e* before an i-sound (*Jane e Ivan*) except before a diphthong (*Jane y Hierro*), *o* becomes *u* before an o-sound; Italian *e* becomes *ed* before a vowel (*aereo ed elicottero*); Hebrew prefixes ו directly to Hebrew words but hyphenates Latin ones (3 ו-4); and the Korean particle 과/와 follows the final sound of the preceding word (John과 / Angela와). Constraints put on the list propagate to every member:

```elixir
iex> concepts =
...>   for word <- ["gato", "gata"] do
...>     {:ok, concept} = Localize.Inflection.Concept.new(:es, word)
...>     concept
...>   end
iex> {:ok, list} = Localize.Inflection.ConceptList.and_list(:es, concepts)
iex> {:ok, list} = Localize.Inflection.ConceptList.put_constraint(list, :number, :plural)
iex> Localize.Inflection.ConceptList.to_speakable_string(list)
"gatos y gatas"
```

Base separators come from Localize's own CLDR list patterns; every behavior is verified against the upstream project's ListTest expectations (351 assertions across 19 language groups, all passing).

## Units of measure

Unit formatting integrates with the engine through the `:inflect` option of `Localize.Unit.to_string/2`: when a requested `:grammatical_case` has no CLDR pattern, the engine inflects the nominative pattern text using the same numeral-government rules as `Localize.Inflection.quantify/4`. `inflect: :safe` never emits a guessed form; `inflect: :always` also enables suffix-exemplar guessing. `Localize.Unit.grammatical_gender/2` resolves a unit's gender from CLDR data or the engine. The MF2 `:unit` function accepts the same controls as `grammaticalCase` and `inflect` options. See the [unit formatting guide](https://hexdocs.pm/localize/unit_formatting.html) for details.

```elixir
iex> unit = Localize.Unit.new!(2, "kilometer")
iex> Localize.Unit.to_string(unit, locale: :ru, grammatical_case: :prepositional, inflect: :safe)
{:ok, "2 километрах"}
```

## In MessageFormat 2 messages

Inflection is available inside MF2 messages through the `l:` namespace: `:l:inflect` inflects its operand phrase, `:l:pronoun` selects or re-inflects a pronoun, and `:l:quantify` joins a `count` with a noun operand so the noun agrees with the number. Grammatical constraints are passed as `grammatical*` options — `grammaticalCase`, `grammaticalGender`, `grammaticalNumber`, `grammaticalDefiniteness`, `grammaticalPerson` — mirroring the `:unit` function's naming:

```elixir
iex> Localize.Message.format("{$w :l:inflect grammaticalNumber=plural}", %{w: "light on the patio"}, locale: :en)
{:ok, "lights on the patio"}

iex> Localize.Message.format("{|he| :l:pronoun grammaticalCase=accusative}", %{}, locale: :en)
{:ok, "him"}

iex> Localize.Message.format("{$noun :l:quantify count=5}", %{noun: "час"}, locale: :ru)
{:ok, "5 часов"}
```

The functions need the locale's inflection data present; a missing locale or absent data resolves to an error rather than crashing the format.

## Error handling

All entry points return tagged tuples. Unknown features and invalid grammeme values are rejected against the locale's feature model:

```elixir
iex> Localize.Inflection.inflect("cat", :en, number: "dual")
{:error, {:invalid_feature_value, "number", "dual"}}

iex> Localize.Inflection.inflect("cat", :en, sizzle: "plural")
{:error, {:unknown_feature, "sizzle"}}

iex> Localize.Inflection.pronoun(:en, "garbage", person: :first)
{:error, {:unknown_pronoun, "garbage"}}
```

## Performance

Operations are in-memory lookups and suffix rewrites: feature queries and pronoun selection run in about 2 µs, phrase inflection in 8–21 µs depending on the language (measured with `mix run bench/inflection.exs`). A dictionary lookup against the packed lexicon costs a few microseconds — a binary search over a block index followed by a short scan, rather than a single map read — which is immaterial beside the surrounding inflection work.

Loading a locale's artifact on first use is a plain read of its packed form: a few milliseconds for most locales, 17 ms for German (~1.3M entries) and 208 ms for Arabic, whose several thousand inflection patterns dominate its load. It is a one-time cost per locale, after which reads are copy-free from `:persistent_term`. See the *Memory and the literal area* section above for the footprint of loading many locales at once.

## Per-locale size and memory

Each locale is a single compressed `.etf` downloaded from the CDN; loading it expands the lexicon and metadata into `:persistent_term`, where it stays resident for the life of the node. The in-memory footprint is typically 4–8× the download. Analytic languages (`zh`, `ja`, `vi`, `id`, `ms`, `th`, `yue`) ship no dictionary, so they cost almost nothing.

Size the `+MIscs` literal-area flag (see *Memory and the literal area*) against the locales you actually load. Loading **all 48 at once needs ~195 MB**, of which ~114 MB is literal area; most applications use only a handful and need no change. The figures below are measured on OTP 29 (64-bit), each locale loaded into a fresh VM: *Download* is the `.etf` byte size, and *In memory* is the combined literal-area and binary-heap growth when the locale is loaded. Figures under a megabyte are approximate, since allocator granularity dominates at that scale.

Two locales are dominated by their inflection **patterns** rather than their lexicon: Arabic (~14,000 patterns) and Hebrew (~5,300). That is why Arabic costs far more than German despite having fewer entries.

| Locale | Download | In memory | Lexicon entries |
|--------|----------|-----------|-----------------|
| `ar` | 11.4 MB | 108.5 MB | 813,579 |
| `de` | 3.4 MB | 12.9 MB | 1,280,915 |
| `he` | 1.5 MB | 14.8 MB | 147,770 |
| `ru` | 1.3 MB | 8.1 MB | 917,072 |
| `da` | 1.2 MB | 6.4 MB | 613,052 |
| `ml` | 1.0 MB | 9.1 MB | 749,381 |
| `es` | 943 KB | 6.0 MB | 559,750 |
| `it` | 655 KB | 3.3 MB | 414,575 |
| `sv` | 608 KB | 2.4 MB | 342,776 |
| `cs` | 562 KB | 2.4 MB | 248,422 |
| `en` | 424 KB | 2.0 MB | 127,524 |
| `bn` | 399 KB | 3.9 MB | 71,755 |
| `fr` | 347 KB | 2.0 MB | 257,114 |
| `nb` | 342 KB | 831 KB | 166,627 |
| `el` | 273 KB | 1.5 MB | 39,070 |
| `sk` | 253 KB | 1.9 MB | 129,290 |
| `uk` | 213 KB | 2.0 MB | 238,954 |
| `nl` | 193 KB | 2.1 MB | 17,318 |
| `pl` | 117 KB | 1.0 MB | 26,483 |
| `fi` | 103 KB | 161 KB | 12,416 |
| `pt` | 96 KB | 773 KB | 36,095 |
| `pa` | 67 KB | 561 KB | 9,545 |
| `ur` | 62 KB | 516 KB | 7,573 |
| `hi` | 61 KB | 524 KB | 7,514 |
| `ta` | 53 KB | 523 KB | 6,526 |
| `hr` | 33 KB | 327 KB | 5,556 |
| `tr` | 18 KB | 79 KB | 3,685 |
| `sr` | 11 KB | 117 KB | 1,351 |
| `ko` | 8 KB | 29 KB | 1,409 |
| `or` | 5 KB | 34 KB | 1,220 |
| `mr` | 5 KB | 51 KB | 287 |
| `ca` | 5 KB | 38 KB | 480 |
| `ro` | 4 KB | 40 KB | 151 |
| `bg` | 4 KB | 39 KB | 211 |
| `te` | 3 KB | 26 KB | 72 |
| `hu` | 3 KB | 25 KB | 65 |
| `lt` | 2 KB | 18 KB | 67 |
| `gu` | 2 KB | 24 KB | 47 |
| `is` | 2 KB | 15 KB | 60 |
| `kn` | 2 KB | 18 KB | 36 |
| `kk` | 2 KB | 19 KB | 35 |
| `th` | 831 B | 6 KB | 0 |
| `vi` | 722 B | 5 KB | 0 |
| `id` | 678 B | 5 KB | 0 |
| `ms` | 665 B | 5 KB | 0 |
| `ja` | 567 B | 4 KB | 0 |
| `zh` | 556 B | 4 KB | 0 |
| `yue` | 503 B | 3 KB | 0 |
| **all 48** | **25.6 MB** | **195.0 MB** | **7,255,828** |
