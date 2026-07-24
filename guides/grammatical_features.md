# Grammatical features

This guide explains every grammatical feature and grammeme value used by this library, in plain language with examples. It assumes no grammar training. For the concepts behind inflection itself, see [What is inflection?](https://hexdocs.pm/localize/what_is_inflection.html); for the API, see the [user guide](https://hexdocs.pm/localize/inflection.html).

Each language defines its own inventory — use `Localize.Inflection.features/1` and `Localize.Inflection.feature_values/2` to discover what a locale supports. Feature names and values are atoms (`case: :genitive`); strings are also accepted.

## Number

How many of the thing there are.

* `:singular` — one: English *cat*, Russian *дом*.

* `:plural` — more than one: *cats*, *дома́*. Some languages use the plural form with all numbers above a threshold, others (through CLDR plural rules) select among several plural classes — that selection happens in the message system; the inflection engine just produces the requested form.

* `:dual` — exactly two, in the languages that mark it. Arabic كتابان ("two books") is neither singular كتاب nor plural كتب.

## Gender

A grammatical classification of nouns that other words must agree with. It is a property of the word, not of any real-world sex: Spanish *el puente* (bridge) is masculine, German *die Brücke* (bridge) is feminine.

* `:masculine` / `:feminine` — the two-way split of Romance languages (Spanish *el gato* / *la gata*), also used by Hindi, Urdu, Arabic and Hebrew.

* `:neuter` — the third class of German (*das Haus*), Russian (*окно*) and others.

* `:common` — in Danish, Swedish and Dutch, the historical masculine and feminine merged into one "common" gender that contrasts with neuter: Danish *en hund* (common) versus *et hus* (neuter).

## Case

The noun's role in the sentence, marked on the word itself. English marks almost nothing (only the genitive *cat's* and pronoun forms like *he/him*), which is why case is the least familiar feature to English speakers — and the most important one everywhere else. The values below are grouped by how they are used.

### The core cases

* `:nominative` — the subject of the sentence; the "dictionary form" in most languages. German *der Hund schläft* (the dog sleeps).

* `:accusative` — the direct object, the thing acted on. German *ich sehe den Hund* (I see the dog) — *der* becomes *den*.

* `:genitive` — possession or close association: English *the cat's toy*, German *das Haus des Vaters*, Russian *дом отца*. Also the case many prepositions require.

* `:dative` — the indirect object, the receiver: German *ich gebe dem Hund einen Ball* (I give the dog a ball).

* `:vocative` — direct address: calling someone. Czech *Marku!* when calling Marek. Used by Czech, Bulgarian, Croatian, Serbian, Ukrainian, Romanian, Kannada, Gujarati, Korean and others.

* `:instrumental` — the tool or means: Russian *я пишу карандашом* (I write with-a-pencil). "With X" in Slavic languages, Kazakh, Kannada and Korean is the instrumental of X.

* `:locative` — location, "in/at X", in Czech, Croatian, Lithuanian, Kazakh, Kannada, Bengali and others.

* `:prepositional` — the Russian, Spanish and Portuguese name for the case used after prepositions (in Russian it replaces a general locative: *в доме*, in the house).

### Direct and oblique

Hindi, Urdu, Marathi, Punjabi and Telugu simplify their older case systems into a two-way split:

* `:direct` — the unmarked form used for subjects: Hindi *दरवाज़ा* (door).

* `:oblique` — the form required before a postposition: *दरवाज़े में* (in the door). The library applies this automatically when a phrase contains a postposition.

* `:ergative` — in Hindi and Urdu, the special subject case used with perfective transitive verbs (the *ने* construction), applied to pronouns.

### The Finnish and Hungarian locative family

Finnish and Hungarian mostly do without prepositions: the case ending says what English says with *in*, *out of*, *into*, *on*, *off*, *onto*.

* `:inessive` — inside: Finnish *talossa* (in the house).

* `:elative` — out of: *talosta* (out of the house).

* `:illative` — into: *taloon* (into the house).

* `:adessive` — at/on: *pöydällä* (on the table).

* `:ablative` — off/from: *pöydältä* (off the table). In Turkish, Tamil, Kazakh and Hungarian, ablative is the general "from X" case.

* `:allative` — onto/toward: *pöydälle* (onto the table).

* `:essive` — in the role or state of: *lapsena* (as a child).

* `:translative` — becoming: *opettajaksi* (turning into a teacher).

* `:partitive` — a partial amount or incomplete action, ubiquitous in Finnish: *juon kahvia* (I drink [some] coffee).

* `:abessive` — without: *rahatta* (without money).

* Hungarian adds finer distinctions the same way: `:sublative` (onto), `:superessive` (on), `:delative` (off/about), `:causal` (for/because of), `:terminative` (up to, until).

### Other cases

* `:comitative` — together with: the Korean 와/과 particle ("X and", "with X").

* `:sociative` — along with, in Malayalam, Tamil and Telugu: Malayalam -ഓടെ.

* `:benefactive` — for the benefit of, in Tamil.

* `:exclusive` / `:inclusive` — Korean marks its nominative by information structure instead of pure grammar: `:exclusive` selects the topic particle 은/는 ("as for X"), `:inclusive` the subject particle 이/가 (introducing new information). The library maps `case: :nominative` plus a `clusivity` constraint onto these.

## Definiteness

Whether the noun refers to a specific, known thing. This is the standard linguistic term (also used by CLDR and the upstream project) — there is no simpler synonym that stays accurate.

* `:definite` — a specific one: English *the cat*, Spanish *la universidad*, Arabic الكتاب (with the ال prefix), Danish *hunden* (with the suffixed article).

* `:indefinite` — any one: *a cat*, *una universidad*, كتاب, *en hund*.

* `:construct` — the Semitic "construct state": the special form an Arabic or Hebrew noun takes when it is possessed by the following noun, as in بيت الرجل (the-house-of the man). Neither definite nor indefinite by itself.

## Person

Who the pronoun or verb form refers to, relative to the speaker.

* `:first` — the speaker: *I*, *we*.

* `:second` — the addressee: *you*.

* `:third` — anyone else: *he*, *she*, *they*, *it*.

## Pronoun-specific features

These mostly select among pronoun forms (see `Localize.Inflection.PronounConcept`):

* `pronounType` — `:personal` (ordinary pronouns) versus `:reflexive` (*myself*, *themselves*).

* `determination` — for possessives, `:dependent` when the pronoun modifies a noun (*my book*) versus `:independent` when it stands alone (*the book is mine*).

* `clusivity` — `:inclusive` versus `:exclusive`. For "we" in some languages it distinguishes whether the addressee is included; in Korean it selects between the subject and topic particles (see the case section above).

* `register` / `formality` — social register: `:intimate`, `:informal`, `:casual`, `:formal`, `:high`. Korean, Hindi, Urdu, Malayalam and others choose different pronouns (and verb forms) by the relationship between speaker and addressee.

* `gender`, `number`, `case`, `person` as above — the same features select pronoun forms: `person: :first, case: :genitive, determination: :independent` selects *mine*.

## Part of speech

The `pos` feature (`:noun`, `:verb`, `:adjective`, `:adposition`, `:pronoun`, `:proper-noun`, …) is not something you usually request; it disambiguates. English *lights* is both a plural noun and a verb form — constraining `pos: :noun` steers the engine to the noun reading when a word is ambiguous.

## Sound features

`:vowel-start`, `:consonant-start`, `:vowel-end`, `:consonant-end` describe how a word sounds at its edges, not how it is spelled — English *hour* starts with a vowel sound, *university* with a consonant sound. They drive article selection (*a cat* / *an apple*, French *la maison* / *l'appareil*) and Korean particle alternation, and are mostly consumed internally by the language synthesizers and pronoun tables rather than set as constraints.

## What is valid where

Not every language has every value, and constraining a feature the language does not mark is rejected. Query the inventory at runtime:

```elixir
iex> Localize.Inflection.feature_values(:ru, :case)
{:ok, [:accusative, :dative, :genitive, :instrumental, :nominative, :prepositional]}

iex> Localize.Inflection.feature_values(:ar, :number)
{:ok, [:dual, :plural, :singular]}

iex> Localize.Inflection.feature_values(:hi, :case)
{:ok, [:accusative, :direct, :ergative, :genitive, :oblique]}
```
