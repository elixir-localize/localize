# What is inflection?

Inflection is the way a word changes form to express its grammatical role. English speakers meet it every day without noticing: *cat* becomes *cats* when there is more than one, *run* becomes *ran* in the past, and *they* becomes *them* when the pronoun is the object of a verb. The word's core meaning stays the same; what changes is grammatical information layered on top — how many, when, whose, doing what to whom.

English inflects lightly, so English-speaking developers can often get away with string concatenation and an `if count == 1` branch. Most of the world's languages cannot. In Russian, Finnish, Arabic, Hindi or Korean, the form of nearly every noun, adjective and article in a sentence depends on grammatical context, and text assembled by pasting a fixed string into a template is immediately, visibly wrong to a native speaker.

## Grammatical features and grammemes

Linguists describe inflection in terms of features (also called categories) and their values (called grammemes). The features this library works with most often are:

* **Number** — how many: *singular* (cat), *plural* (cats), and in some languages *dual* (Arabic كتابان, exactly two books).

* **Gender** — a grammatical classification of nouns: *masculine*, *feminine*, and in some languages *neuter* or *common*. Grammatical gender is a property of the word, not the thing: in Spanish, *el puente* (bridge) is masculine while in German *die Brücke* is feminine.

* **Case** — the word's role in the sentence: *nominative* for the subject, *accusative* for the direct object, *genitive* for possession, *dative* for the indirect object, and beyond. German has four cases, Russian six, Finnish about fifteen.

* **Definiteness** — whether the noun refers to something specific: *the cat* (definite) versus *a cat* (indefinite). English marks it with articles; Arabic with the prefix ال; Danish and Swedish with a suffix on the noun itself.

* **Person** — the speaker (*first*: I, we), the addressee (*second*: you), or someone else (*third*: he, she, they).

A grammeme is one concrete value of a feature: *plural* is a grammeme of number, *genitive* is a grammeme of case. Every entry in this library's dictionaries is tagged with the grammemes that hold for it, and every inflection request is expressed as a set of grammeme constraints.

## Agreement

Inflection rarely affects one word in isolation. When a noun changes, the words that depend on it — articles, adjectives, sometimes verbs — must change with it. This is agreement, and it is where naïve string interpolation breaks down hardest.

Spanish articles and adjectives agree with the noun's gender and number: *la universidad nueva* but *las universidades nuevas* — four words change to say "the new universities". In Russian, an adjective agrees with its noun in gender, number and case: *новый дом* (new house, nominative) becomes *новым домом* in the instrumental case — both words change. In Hindi, a noun standing before a postposition such as में (in) must shift into the oblique case: *दरवाज़ा* (door) becomes *दरवाज़े में* (in the door).

## A short tour across languages

The same message — inserting a user-supplied noun into a sentence — needs different grammatical work in different languages:

* **English** needs plurals and the possessive: *light* → *lights*, *cat* → *cat's*. Its articles only care about sound: *a cat* but *an apple*.

* **Spanish, French, Italian, Portuguese** need gender agreement and article selection, with sound-dependent forms: French *la maison* but *l'appareil* (elision before a vowel), Spanish *el agua* (feminine noun, but *el* before stressed *a*).

* **German** needs case: *das Haus* is nominative, *dem Haus* dative, and the plural dative adds a suffix to the noun itself: *den Häusern*.

* **Russian, Ukrainian, Polish, Czech, Serbian** decline nearly everything through six or seven cases: writing "with X" requires X in the instrumental; "for X" requires the genitive.

* **Finnish** replaces most prepositions with cases: *talo* (house) becomes *talossa* (in the house), *talosta* (out of the house), *taloon* (into the house).

* **Arabic and Hebrew** attach definiteness to the word: كتاب (a book) versus الكتاب (the book), and Arabic distinguishes exactly-two with the dual.

* **Danish, Swedish, Norwegian** suffix the definite article onto the noun: Danish *hund* (dog), *hunden* (the dog).

* **Hindi, Urdu, Punjabi, Marathi** use postpositions that force the preceding noun into the oblique case.

* **Korean** does not inflect the noun at all but attaches a particle whose form depends on the noun's final sound: 사과는 (vowel-final) but 집은 (consonant-final); the topic, subject, object and direction particles all alternate this way — including for Latin-script brand names embedded in Korean text.

## Pronouns

Pronouns are the most irregular inflected words in most languages: *I / me / my / mine / myself* is a five-way case paradigm that no regular rule produces. Selecting the right pronoun means matching grammatical constraints (person, number, gender, case) against a lexicon of forms, and reinflecting a pronoun ("make this nominative pronoun possessive") means carrying over the properties that were not overridden. Some languages add sound dependency: French *je* becomes *j'* before a vowel-initial verb.

Pronoun selection also carries social weight: honoring a person's pronouns ("they", a neopronoun, or a custom form) requires the message system to treat the pronoun set as data, not as three hard-coded branches. This library's pronoun tables are exactly that kind of data, and custom pronoun entries can be supplied at runtime.

## How this library models it

`Localize.Inflection` is a pure-Elixir port of the [Unicode inflection project](https://github.com/unicode-org/inflection), and it inherits that project's model:

* A **dictionary** per locale maps each surface form to its grammeme set, stored as an integer bitmask.

* **Inflection patterns** (paradigms) describe how families of words trade one suffix for another to move between grammeme sets.

* A per-language **synthesizer** encodes the rules that data alone cannot express: article selection, agreement across a phrase, particle sound alternation, definiteness prefixes.

* A **concept** ([Localize.Inflection.Concept](https://hexdocs.pm/localize/Localize.Inflection.Concept.html)) wraps a word or phrase; you put grammeme constraints on it and render it, or query its grammatical features.

* A **pronoun concept** ([Localize.Inflection.PronounConcept](https://hexdocs.pm/localize/Localize.Inflection.PronounConcept.html)) selects pronouns from the locale pronoun table by the same constraint mechanism.

Every ported language is verified against the upstream project's data-driven conformance suites, so the behavior you get from this library is the behavior the Unicode inflection project specifies.

For the practical API, see the [user guide](https://hexdocs.pm/localize/inflection.html).
