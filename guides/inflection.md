# User guide

This guide covers the practical use of `Localize.Inflection`: inflecting words and phrases, querying grammatical features, and selecting pronouns. If you are new to grammatical inflection itself, start with [What is inflection?](https://hexdocs.pm/localize/what_is_inflection.html).

## Inflection data

Inflection is part of Localize, and its data is optional: nothing is downloaded unless you ask for it. The compiled data (per-locale dictionaries and pronoun tables, built from the [Unicode inflection project](https://github.com/unicode-org/inflection) at a pinned commit) downloads per locale from the Localize CDN at build time:

```
mix localize.download_inflection            # the configured :supported_locales
mix localize.download_inflection en de ru   # specific locales
```

Each file is verified against a SHA-256 manifest shipped in the package before it is written. Locales you never download cost nothing; inflection functions return `{:error, %Localize.InflectionDataNotAvailableError{}}` when a locale's data is not present — distinct from `%Localize.InflectionNotSupportedError{}` for languages the Unicode inflection project does not cover.

The data directory follows the locale-cache configuration convention:

```elixir
# Recommended: anchor to your application
config :localize, otp_app: :my_app

# Or a fully custom absolute location
config :localize, inflection_data_dir: "/var/lib/localize/inflection"
```

Once the data is present there are no runtime downloads. Locale data loads lazily: the first operation on a locale loads its artifact into `:persistent_term` and an ETS table; subsequent operations are lookups measured in microseconds.

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

Operations are in-memory lookups and suffix rewrites: feature queries and pronoun selection run in about 2 µs, phrase inflection in 8–21 µs depending on the language (measured with `mix run bench/inflection.exs`). Loading a locale's artifact on first use takes a few milliseconds for most locales, up to about half a second for the largest lexicon (Arabic, with over 800,000 entries).
