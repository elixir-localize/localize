# RBNF rule sets chosen by grammatical features

**Status:** in progress, 2026-11-27

Issue 72 reports that `Localize.Number.to_string(3, format: :ordinal, locale: :ru)` returns `"3"`. The plan is to choose an RBNF rule set by grammatical case, gender, number and definiteness, as named options, rather than by matching rule-set names against a fixed list of patterns. It also covers how option values are taken without making atoms.

## The problem

`format: :ordinal` and `format: :spellout` are resolved by `resolve_rule_name/3` in `lib/localize/number/rbnf.ex`. It sorts the locale's public rule-set names and takes the first match from a list: an exact name (`digits-ordinal`, then `spellout-ordinal`), then a pattern (`~r/^digits-ordinal-/`, `~r/^spellout-ordinal-/`, `~r/-ordinal(-|$)/`). Four things follow from treating the names as plain strings.

* **Digits or words depends on the locale** — `:ordinal` is digits ("3rd") where the locale has a `digits-ordinal` rule set and words ("dritte", "trzecia") where it does not. 18 CLDR locales have no `digits-ordinal` but have gendered spelled-out ordinals: be, cs, de, de_CH, fr_BE, fr_CH, hr, lb, lt, ne, no, pl, pt_PT, sk, sl, sr, sr_Latn, vec.

* **Gender and case are chosen alphabetically** — a pattern match takes the first name in sort order, so `feminine` wins over `masculine`, `neuter` and `plural`, and the nominative wins over the other cases only because it is the shortest name. Polish `:ordinal` is "trzecia" (feminine) for this reason alone.

* **The caller cannot ask for a gender or case** — agreement depends on the noun, which only the caller knows. Today the only way to choose is to name the rule set, and the names differ by language: `digits_ordinal_masculine_genitive` (ru), `spellout_ordinal_r` (de), `spellout_ordinal_masculine_personal_plural` (pl).

* **The ungendered rule set is taken as it is** — CLDR's Russian `%digits-ordinal` is `0: =#,##0=;`, the number with no suffix. Of the 15 locales with gendered digit ordinals, 12 point the ungendered set at the masculine (uk, es, it, fr, pt, ca, hi, …), Swedish at the feminine, Bulgarian adds `.`, and Russian alone writes bare digits. That is a CLDR data question; this plan follows CLDR and makes the gendered forms reachable.

The same pattern fallback serves `:spellout` (`~r/^spellout-cardinal-/`), and `Localize.Inflection.Quantify.Numeral` builds rule-set names such as `"cardinal-masculine-genitive"` by string concatenation from hand-kept per-language tables. Both would use the resolver this plan adds.

## What CLDR's names hold

CLDR 49 has 254 public rule-set names. The ones in the `digits-ordinal`, `spellout-ordinal` and `spellout-cardinal` families number 1,022 across all locales. Splitting each on `-` after the family prefix and reading every segment through a fixed table gives the following.

* **967 names parse into features**, with no two names in one locale and family giving the same set of features, and no name giving two values on one dimension. Segment order varies (`masculine-animate-accusative` beside `masculine-accusative-animate` in upstream tables), so features are read as a set, not by position.

* **55 names carry a style rather than a feature** — `financial` (zh), `verbose`, `sinokorean`, `native`, `count`, `attributive`, `adjective`, `connective`, `standalone`, `stressed`, `alternate2`, `before-consonant`, `class-o`, and German `-n`, `-r`, `-s`, `-m`. These stay reachable by name only and never take part in feature resolution.

The segments that parse:

| Dimension | Segments |
|---|---|
| Case | nominative, genitive, dative, accusative, instrumental, prepositional, locative, vocative, ablative, oblique, partitive, essive, translative, inessive, elative, illative, adessive, allative |
| Gender | masculine, feminine, neuter, common (`reale`, Swedish utrum, read as `common`) |
| Number | plural, dual |
| Definiteness | definite |
| Masculine animacy | animate, personal, human |

CLDR's `grammaticalFeatures.xml` defines `grammaticalCase`, `grammaticalGender` and `grammaticalDefiniteness`, and gives Swedish genders as `common neuter`, which is why `reale` reads as `common`. It treats Slavic masculine animacy as gender values in place of `masculine`: `animate inanimate feminine neuter` for cs, sk, hr, sr and ml, and `animate inanimate personal feminine neuter` for pl. The RBNF names mark the same thing as `masculine` plus `animate`, `personal` or `human` (sk), and once without `masculine` (uk `plural-animate-accusative`). They are read in CLDR's model: `masculine-animate` and a bare `animate` give the gender `animate`, `masculine-personal` and `masculine-human` give `personal`, and a plain `masculine` gives `masculine`, which a request for `inanimate` also matches, since the inanimate masculine is the unmarked one. Read this way the 967 names still give no collisions. CLDR has no number dimension; the RBNF names need one, because a Russian `plural` ordinal has no gender.

## Vocabulary

Localize already uses two vocabularies:

* **The `grammatical_` prefix** — `Localize.Unit.to_string/2` takes `:grammatical_case` and `:grammatical_gender`. `Localize.Number.Format.Options` accepts the same two keys, but `Localize.Number.to_string/2` passes neither to RBNF today. MF2's `:unit` takes `localize:grammaticalCase` and `localize:grammaticalGender`.

* **Bare names** — `Localize.Inflection.inflect/3` takes `case:`, `gender:`, `number:` and `definiteness:`, as the upstream inflection project names its features, and MF2's `:i:` functions take `case=` and `gender=` for the same reason.

The proposal uses the prefixed form for RBNF, since `Localize.Number.to_string/2` already reserves `:grammatical_case` and `:grammatical_gender`, and a bare `:number` option on a number-formatting function would be ambiguous:

* `:grammatical_case`, default `:nominative`.

* `:grammatical_gender`, no default (see "Resolution").

* `:grammatical_number`, default `:singular`; also `:plural`, `:dual`.

* `:grammatical_definiteness`, default `:indefinite`; also `:definite`, `:construct`, `:unspecified`. The name and values follow CLDR's `grammaticalDefiniteness`.

The values of `:grammatical_gender` are CLDR's: `masculine`, `feminine`, `neuter`, `common`, `animate`, `inanimate` and `personal`. Those of `:grammatical_case` are CLDR's 28 cases, the union of `grammaticalFeatures.xml` and the RBNF names.

In MF2 the same options are `localize:grammaticalCase`, `localize:grammaticalGender`, `localize:grammaticalNumber` and `localize:grammaticalDefiniteness`, in the namespace Localize already uses.

`Localize.Inflection.inflect/3` keeps its bare names, as the upstream API it mirrors. Whether it should also accept the prefixed names is a separate decision, recorded under "Open questions".

## No arbitrary atoms

Nothing in this work turns caller input into an atom, and nothing derives a new atom from data at run time.

* **One table of values, compiled in** — a new internal module, `Localize.GrammaticalFeature`, holds each dimension's values as literal atoms in a module attribute, with a map from each value's string to its atom. It is the only source of these atoms. MF2's `@mf2_unit_grammar` in `lib/localize/message/interpreter.ex` moves to it, so `:unit` and RBNF accept the same values.

* **Caller values are checked, never converted** — an atom is accepted only if it is in the dimension's list (`value in @grammatical_cases`). A string is looked up in the compiled string-to-atom map. Anything else returns `{:error, %Localize.InvalidValueError{}}`. No `String.to_atom/1`, `String.to_existing_atom/1`, `:erlang.binary_to_atom/2` or `Localize.Utils.Helpers.existing_atom/1` is applied to an option value: an existing atom is no evidence of a valid value.

* **Rule-set names are parsed, not created** — the names are already atoms in Localize's generated RBNF data. A name is parsed by splitting `Atom.to_string/1` on `_` and looking each segment up in the compiled table. A name with any segment not in the table is marked unresolvable by features. The parsed features hold only the table's atoms.

* **`format:` strings keep their existing path** — family names (`"ordinal"`, `"digits_ordinal"`, `"spellout_ordinal"`) are compared as strings before anything else; any other string goes through the existing `existing_atom/1` lookup and the locale's rule-set keys, as today.

* **Errors carry what is already known** — an error names the rejected value as given and lists the locale's available values from the index. It builds no atom.

* **A test proves it** — format with many generated option strings and `format:` strings, and assert that `:erlang.system_info(:atom_count)` has not changed.

## Resolution

A request is a family and a set of features. `format:` names the family:

* `:ordinal` — the `digits-ordinal` family, else `spellout-ordinal`, as today.

* `:digits_ordinal` and `:spellout_ordinal` — that family only.

* `:spellout` — `spellout-numbering`, else `spellout-cardinal`, as today.

* `:spellout_cardinal` — that family only.

* Any other rule-set name — that rule set exactly. A grammatical option given with it is an error, since it would be silently ignored.

With no grammatical options, a family with its unmarked rule set (`digits-ordinal`, `spellout-ordinal`, …) uses it, as CLDR intends. Russian `:ordinal` therefore stays `"3"`.

Otherwise, the candidates are the family's names that parse into features. Each has a value or nothing on each dimension. An unmarked case, number or definiteness means its default (nominative, singular, indefinite). An unmarked gender means the form does not vary on that dimension: the Russian `plural` ordinal serves every gender.

1. **Fill the request** with the defaults of the dimensions the caller left out.

2. **Ignore a dimension the family does not vary on.** English digits ordinals have no gender, so `grammatical_gender: :feminine` with `locale: :en` gives `"3rd"`. `Localize.Unit` treats `:grammatical_gender` the same way.

3. **Keep the candidates that agree** on every remaining dimension: equal, or unmarked for gender; a requested `inanimate` agrees with `masculine`.

4. **Choose the most specific** — the candidate that marks the most requested values.

5. **Choose a gender only if the caller did not.** Where the family has no unmarked rule set and no gender was asked for, choose in a fixed, documented order: masculine, common, neuter, feminine. Masculine first follows the convention 12 of CLDR's 15 gendered digits-ordinal locales use. The order is a list in code, not the alphabet.

6. **Return an error rather than guess.** A requested value the family varies on but does not have (Polish has `locative`, not `prepositional`) returns `{:error, %Localize.UnknownRbnfRuleError{}}` listing the values the locale has.

Rule-set names are parsed when a lookup needs them, by `Localize.Number.Rbnf.RuleSetName`, and nothing is stored. Storing the features in the generated RBNF data was the first idea, but locale files are published and checked against `priv/localize/locale_hashes.etf`, so it would mean regenerating and republishing every locale file, and files already downloaded would lack the features. Parsing is a few dozen string splits and map lookups a call, and writes nothing.

## Changes in behaviour

* **Polish and 11 other locales** — `:ordinal` chooses the masculine nominative in place of the alphabetically first rule set: Polish 3 becomes "trzeci", not "trzecia", and Slovenian "tretji", not the dative "tretjemu". Measured over every RBNF locale, the 12 are be, hr, lb, lt, ne, pl, pt-PT, sk, sl, sr, sr-Latn and vec; `:spellout` changes in none. This is a fix and goes under `### Fixed`.

* **A family's own name resolves** — `format: :spellout_cardinal` or `:spellout_ordinal` in a locale with only gendered rule sets returned `UnknownRbnfRuleError`; it now takes the masculine nominative (Russian 3 is "три", French 3rd "troisième"). Across the 99 RBNF locales, 41 gain `spellout_cardinal` and 34 `spellout_ordinal`; Korean, whose rule sets are all style variants, still errors.

* **French `:spellout_ordinal` of 1** — was "unième", from the private `%%spellout-ordinal` helper the exact lookup reached without checking access; the family sees public rule sets only, and gives "premier". 21 is still "vingt-et-unième".

* **Russian `:ordinal`** — unchanged (`"3"`); `grammatical_gender: :masculine` gives `"3-й"`, and with `grammatical_case: :genitive` gives `"3-го"`.

* **`:grammatical_case` and `:grammatical_gender` on `Localize.Number.to_string/2`** — accepted today and ignored; they now choose the rule set. A value outside the table, accepted silently today, becomes an error.

## Tasks

* [ ] **MF2** — the `localize:grammatical*` options on the functions that reach RBNF.

* [ ] **`Localize.Inflection.Quantify.Numeral`** — build its rule-set choices through the resolver in place of string concatenation. German cardinals need the `-n`, `-r`, `-s`, `-m` sets read as case and gender, from that module's existing table.

* [ ] **Docs and CHANGELOG** — the RBNF section of the number formatting guide, the `:format` docs, the atom test, and a reply to issue 72.

### Done

* [x] **The round-trip test** — all 1,065 rule sets that read as features, in the 99 RBNF locales, resolve from their own features to themselves and format as their own names do. 2026-11-27.

* [x] **Options through `Localize.Number.to_string/2`** — validated in `Localize.Number.Format.Options` (which gains `:grammatical_number` and `:grammatical_definiteness`, and holds each as its atom) and passed to RBNF; `Localize.Unit` passes its own on, so they are validated there too. 2026-11-27.

* [x] **The resolver** — `Localize.Number.Rbnf.Resolver`, called from `Localize.Number.Rbnf.to_string/3`, which takes the four grammatical options; the pattern preferences are gone. 2026-11-27.

* [x] **Parse rule-set names** — `Localize.Number.Rbnf.RuleSetName.parse/1`, at lookup time; of the 1,022 family names in Localize's data, 967 read and none collide, and the rest carry a style segment. 2026-11-27.

* [x] **`Localize.GrammaticalFeature`** — compiled tables of CLDR's case, gender, number and definiteness values, and `cast/2`; MF2's `:unit` options read through it. 2026-11-27.

* [x] **Confirm the open questions** — recommendations accepted. 2026-11-27.

## Decisions

The user accepted the recommended answers to the four open questions on 2026-11-27:

* **Vocabulary** — the `grammatical_` prefix for RBNF and `Localize.Number`. `Localize.Inflection.inflect/3` keeps its bare names for now; accepting the prefixed names there is a separate decision.

* **Animacy** — first accepted as a dimension of its own, then changed the same day, after `grammaticalFeatures.xml` showed CLDR treats Slavic masculine animacy as gender values (`animate`, `inanimate`, `personal`). Animacy follows CLDR's model: no `:grammatical_animacy` option, and MF2's `:unit` gender table keeps its values.

* **`:ordinal` falling back to words** — kept, with `:digits_ordinal` for callers who need digits or an error.

* **Russian's unmarked digits ordinal** — CLDR is followed, so `:ordinal` stays `"3"`; the user reports the bare-digits rule and the Latin `e` to CLDR.

## Open questions as drafted

* **Vocabulary** — the `grammatical_` prefix for RBNF and `Localize.Number` (recommended), and whether `Localize.Inflection.inflect/3` should also accept the prefixed names.

* **Animacy** — a dimension of its own (recommended, since Polish and Czech names mark gender and animacy together), or left reachable only by name. MF2's `:unit` table lists `animate`, `inanimate` and `personal` as gender values; with a separate animacy dimension, that table would change too.

* **`:ordinal` falling back to words** — keep it (recommended, since changing it breaks the 18 locales above), with `:digits_ordinal` for callers who need digits or an error.

* **Russian's unmarked digits ordinal** — follow CLDR (recommended) and report it to CLDR, with the Latin `e` in `digits-ordinal-plural` and `digits-ordinal-plural-accusative`; or prefer the masculine over an unmarked set that adds no suffix.
