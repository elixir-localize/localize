# Locale inheritance

**Status:** planning, 2026-11-27

Localize works out a locale's parent, or a chain of them, in nine places, with six different algorithms. Each answers TR35's question ("which locale's data does this locale inherit?") a little differently, and four of them are wrong for some locales. This plan makes one implementation of TR35 inheritance, `Localize.Locale.parent/2` and `Localize.Locale.fallback_chain/2`, and moves every consumer onto it. Resolution follows: which CLDR locale's data a locale gets is found by the same inheritance, as ICU's resource lookup does, and language matching is kept for negotiating among the configured locales.

## What TR35 says

TR35 Part 1, *Parent Locales* (`docs/ldml/tr35.md` at `release-49`):

* **Truncation.** Remove the extensions, then the last subtag: `sr-Cyrl-ME` → `sr-Cyrl` → `sr` → root.

* **`parentLocales` overrides truncation.** `es-AR` → `es-419`, `pt-AO` → `pt-PT`, `nb` → `no`, `hi-Latn` → `en-IN`.

* **The non-likely-script rule.** `localeRules="nonlikelyScript"` makes root the parent of every `lang-Script` whose script is not the likely script for `lang`, "programmatically": `ru-Latn` is covered although it is not listed. CLDR's explicit list (`az-Cyrl`, `sr-Latn`, `zh-Hant`, …) is kept "for migration" and is "slated for removal". The rule applies to the main component only.

* **Components.** `parentLocales` with a `component` attribute (`collations`; `segmentations grammaticalFeatures plurals`) gives those components their own parents. TR35 says these are "now not merged, but instead are treated as stand-alone", and the non-likely-script rule does not apply to them. In CLDR 49 the `collations` component names `yue` → `zh-Hant` and `yue-Hans` → `zh-Hans`; the other component group is empty, so plurals, grammatical features and segmentation inherit by truncation alone.

* **Invariants.** No cycles; every path reaches root; for the main component a parent is root or has the child's script.

## The implementations today

| Where | Algorithm | Defect |
|---|---|---|
| `Localize.Locale.parent/1` | Truncates the tag's own fields, `parentLocales` by full and script-less key | Given a validated (maximized) tag it truncates the maximized subtags: an `az` tag gives `az-Latn`, its child. No programmatic non-likely-script rule: `ru-Latn` gives `ru`. No components. |
| `Localize.Locale.fallback_chain/2` | Table of CLDR id chains from `parentLocales` and truncation (1.11.0) | Relies on CLDR's explicit non-likely-script list, which is to be removed. No components. |
| `Localize.Locale` data lookup (`fallback_through_parents/4`) | `parent/1` of the id string, each parent through `validate_locale/1` | Each parent resolves among the configured locales, so the chain depends on `supported_locales`. |
| `Localize.Locale.Provider.walk_parent_chain/4` | Same as the data lookup | Same. |
| `Localize.Number.Rbnf` `locale_chain/2`, `nearest_rules_ancestor/1` | `parent/1` of the validated tag | The maximized-tag defect: 21 chains gain the default-script id. No output changes, measured over all 656 ids (2026-11-27). Configuration-dependent. |
| `Localize.Collation.Tailoring` chains | Built by the data pass (`data/collation.ex`) from the main and `collations` entries merged, minus the non-likely-script rule | Merges the main entries, where TR35 says component entries stand alone: `nb` takes `no`'s collation through the main entry. To be checked against CLDR's own collation inheritance. |
| `Localize.Collation.Tailoring.LocaleDefaults` | `parent/1` of the validated tag | The maximized-tag defect; no output changes, measured. |
| `data/locale.ex` `locale_chain/1` (the data pass, for subdivisions) | `parentLocales` and truncation over names | No non-likely-script rule. Build time only. |
| `Localize.Inflection.Locale.parent/1` | Truncation of the caller's spelling, underscored | Ignores `parentLocales` and the non-likely-script rule: `sr_Latn` gives `sr`, so Latin Serbian reads the Cyrillic inflection data. Keys by the spelling, not the resolved locale. |

Outside Localize, `localize_translate` walks parents itself (`Localize.Translate.Locale.expand_one/1`), through `validate_locale/1`, and is moving to `fallback_chain/2`.

Inflection is separate because its data comes from the Unicode inflection project, not CLDR: resource files named by underscored language (`sr.etf`, `pt.etf`), read with string operations so that no atom is made before a file is known to exist. Neither reason needs its own inheritance: the chain is a list of CLDR locale ids, all existing atoms, mapped to resource names.

## Design

1. **One parent function, over identifiers.** `Localize.Locale.parent(locale, options)` returns the TR35 parent of the identifier as written, canonicalized but never maximized. Extensions are dropped and restored, as TR35 says. A validated tag is read as the CLDR locale its request resolves to among every CLDR locale, so an `az` tag's parent is root, never `az-Latn`. Not by its `canonical_locale_id` as written: a validated `zh-TW`, whose data is `zh-Hant`'s, would go to `zh`. Not by its `cldr_locale_id` field either: that can name a configured locale, and a walk through `supported_locales` cycled. `parentLocales` is looked up under the name and under the name without a script likely subtags imply, since TR35 treats `en-Latn-RO` and `en-RO` as one locale. Option `:component` — `:main` (default), `:collations`, `:plurals`, `:grammatical_features`, `:segmentations`.

2. **The non-likely-script rule computed from likely subtags**, for the main component: a `lang-Script` identifier, no territory or variant, whose script differs from the script `lang` maximizes to, has root as its parent. CLDR's explicit list is then redundant; a test checks every listed locale is one the rule gives.

3. **`parentLocales` by component.** The data pass writes `parent_locales.etf` as `%{main: %{...}, collations: %{...}, plurals: %{...}, ...}` from `parentLocales.json`, which carries every component, read stand-alone per component.

4. **One chain function.** `fallback_chain(locale, options)` resolves the locale to its CLDR locale by the bundle lookup (6), then iterates `parent/2` over CLDR ids for the component, from a table per component built on first use. `:supported` filters, as now.

5. **Consumers move onto them,** one per step: the data lookup and the provider walk (chains filtered to the locales whose data is installed, so a parent that is not downloaded is skipped rather than resolved to a neighbour); RBNF (`fallback_chain` filtered to RBNF locales); collation (the `:collations` component, and the data pass derives its chains from the same function); inflection (resolve, take the chain, map ids to resource names, delete `Localize.Inflection.Locale.parent/1` and `chain/1`); `localize_translate`.

6. **Resolution is TR35's bundle lookup.** `LanguageTag.new/1` sets `cldr_locale_id` to the first CLDR locale on the identifier's way up: start without a script likely subtags imply (`ar-Arab-EG` → `ar-EG`), read `lang-Region` as its likely `lang-Script-Region` unless `parentLocales` names its parent, then step by `parent/2`; root when none is found. It never calls the matcher. This replaces the exact and minimized-form lookups added in 1.11.0 and the matcher fallback behind them.

7. **Negotiation is ICU's `LocaleMatcher`.** `validate_locale/1`, choosing among the configured locales, accepts a match only below distance 50, CLDR's default script distance, and otherwise takes the default locale. `LanguageTag.best_match/3` keeps its distance argument; its default changes to match. The matcher breaks ties by CLDR's `paradigmLocales` (`en en_GB es es_419 pt_BR pt_PT`), as ICU does (`pt-ES` → `pt-PT`, not `pt-AO`).

## Decisions

* 2026-11-27 — Component parents stand alone, as TR35 says; collation sort keys are compared over every locale before that step lands (user).

* 2026-11-27 — A parent whose data is not installed is skipped, not resolved to a neighbour (user).

* 2026-11-27 — The chain table stays computed on first use until [persistent-term-writes.md](persistent-term-writes.md) settles that category (user).

* 2026-11-27 — Resolution follows ICU's split (user): `new/1` finds a locale's data by TR35's bundle lookup and never matches; `validate_locale/1` negotiates as `LocaleMatcher` does, below distance 50, falling back to the default locale. Because matching against every CLDR locale with a cutoff of 80 gave another script's data (`ru-Latn` → `ru`), a regional sibling for the parent (`en-QA` → `en-GB`) and another language (`gsw-LU` → `de-LU`), 9,935 inputs in all, measured below.

* 2026-11-27 — An `und` with a script or territory resolves by the language likely subtags give it (`und-TW` is `zh-Hant`, `und-FR` is `fr`), where ICU's resource lookup gives the root (user). Because TR35's Lookup canonicalizes by likely subtags first, and Localize has resolved them so all along.

## Resolution, measured against ICU

`LanguageTag.new/1` chooses a locale's CLDR data by language matching against every CLDR locale, rejecting only at distance 80, CLDR's language distance. ICU keeps two answers apart: `ures_open` finds a locale's data by TR35 inheritance and never matches, and `LocaleMatcher` negotiates among an application's supported locales with a threshold of 50, CLDR's default script distance, exclusive (`localematcher.cpp`, `locdistance.cpp`, `uresbund.cpp` at `release-78.1`).

Measured 2026-11-27 over 75,144 inputs (every CLDR id, its maximized and extension forms, variant forms, and every language with every script and territory CLDR uses) against ICU 79.1, which carries CLDR 49.0 as Localize does. Differences only by a default-content locale (`kok-Deva` and `kok`) and the 14 CLDR locales ICU does not build (`ady`, `cop`, `kbd`, `kek`, `lld`, `quc`, `suz-Sunu`, `bal-Latn`, `ca-ES-valencia`, `be-tarask`, `el-polyton` and their regions) are set aside.

| Comparison | Other differences |
|---|---|
| ICU `ures_open` vs `new/1` today | 9,935: 9,561 another script's data (`ru-Latn` → `ru`, where ICU gives root), 361 a regional sibling for the parent (`en-QA` → `en-GB`, `pt-NG` → `pt-AO`, where ICU gives `en` and `pt`), 13 another language (`gsw-LU` → `de-LU`, `lb-AT` → `de-AT`, `no-SJ` → `nb-SJ`, `bs-HR` → `hr`) |
| ICU `ures_open` vs a TR35 bundle-lookup prototype | 17, each where ICU departs from TR35 or CLDR's data (below) |
| ICU `LocaleMatcher` vs Localize's matcher, cutoff 80 | 9,464, of which 9,273 are script mismatches ICU refuses |
| ICU `LocaleMatcher` vs Localize's matcher, cutoff 50 | 192: 190 `pt-XX` → `pt-AO` where ICU gives `pt-PT`, `bs-HR` → `hr` where ICU gives `bs`, `und` → `en` where ICU finds no match |

The prototype is TR35's plain bundle lookup: start from the identifier with a script likely subtags imply removed (`de-Latn-LI` → `de-LI`, `ar-Arab-EG` → `ar-EG`); take the first CLDR locale on the way up, where `lang-Region` is read as its likely `lang-Script-Region` (TR35 *Lookup*: "lang_region (aliases to lang_script_region based on likely subtags)") unless `parentLocales` names its parent, and each step is `parentLocales`, then the non-likely-script rule, then truncation; root when none is found. Its 17 differences from ICU:

* **ICU drops the region where TR35 aliases it** — `ff-NG`, `ff-GW`, `ff-LR`, `yue-MO`: ICU's fallback for a bundle it lacks replaces the region with the script (`ff_NG` → `ff_Latn`), losing the CLDR locale `ff-Latn-NG`, which the prototype finds.

* **ICU's default-script table disagrees with CLDR 49's likely subtags** — `sr-RO`, `sr-TR` (ICU `sr-Cyrl`; likely subtags give `sr-Latn`), `ky-TR` (ICU `ky`; likely subtags give `ky-Latn-TR`, a non-likely script, so root).

* **Default content ICU does not build** — `ku-Latn-TR` and `kk-Cyrl-KZ` give `ku-TR` and `kk-KZ`, which hold no data of their own; ICU gives `ku` and `kk`.

So resolution follows ICU's split (adopted 2026-11-27): `new/1` finds a locale's data by the TR35 bundle lookup, which is `parent/2` and never matches; `validate_locale/1` negotiates as `LocaleMatcher` does, accepting distances below 50 and falling back to the default locale. The matcher's `pt-PT` tie-break is CLDR's `paradigmLocales` (`en en_GB es es_419 pt_BR pt_PT`), which Localize's matcher does not apply; that is a matcher defect of its own.

The ICU harness (`icu_measure.cpp`, the input generator and the comparison) was a scratch measurement, not kept in the repository.

## Tasks

Each step lands on its own, with its output compared over every CLDR locale before and after. The ICU harness is rebuilt for the resolution steps.

* [x] **`parent/2` over identifiers** — `parent/1` for now (`:component` comes with the next step). Measured over every CLDR id and 75,144 inputs: validated-tag walks equal `fallback_chain/2` for all 656 ids (474 differed); RBNF lookup locales and collation defaults unchanged; input parents change only for the 9,577 non-likely `lang-Script` inputs, now root. 2026-11-27.

* [x] **`parent_locales.etf` by component** — generated from `parentLocales.json`, which carries the components and `_localeRules` (the XML was not needed), as `%{main: ..., collations: ..., grammatical_features: ..., plurals: ..., segmentations: ...}`; the main map byte-identical to the old file; the data pass fails on a component or locale rule it does not know; `parent/2` takes `:component`. 2026-11-27.

* [x] **`LanguageTag.new/1` resolves by bundle lookup** — `Localize.Locale.Inheritance.bundle_locale_id/2`, shared with `parent/2`; the exact, minimized-form and matcher paths are gone. Against ICU 79.1 over the 75,144 inputs: the same 17 differences as the prototype, plus `be-tarask` and `el-polyton`, which ICU does not build. An `und` with a script or territory keeps the language likely subtags give (`und-TW` is `zh-Hant`), where ICU gives the root. Plural rules found the regression this exposed: a locale whose data is the root's lost its language's rules (`ars`, `bal`, `ny`); 22 more languages had lost them before. 2026-11-27.

* [x] **`validate_locale/1` negotiates below distance 50** — `best_match/3`'s default is 49 with ICU's fallback to the first supported locale (ICU's implicit default; reading `Localize.default_locale/0` instead would leave cached results stale after `put_default_locale/1`), scored 80 as no match; an explicit distance is strict. Against ICU 79.1's `LocaleMatcher` over the 75,144 inputs and three supported lists: identical on two, and on the third 312 regional ties left for the paradigm step; the root, always supported, is Localize's own. Three curated CLDR matcher fixtures predating CLDR-14355 now expect what ICU 79's own test data does. `localize_web`'s 642 tests pass against steps 1–4 unchanged. 2026-11-27.

* [ ] **Paradigm locales in the matcher** — ties broken by CLDR's `paradigmLocales`; compared with ICU's `LocaleMatcher` over the same inputs, the 190 `pt` differences gone.

* [ ] **`fallback_chain/2` from `parent/2`** — per-component tables; chains for all 657 ids unchanged for `:main`.

* [ ] **Data lookup and provider walk** — onto `fallback_chain/2`, skipping parents whose data is not installed; every locale's lookups compared before and after.

* [ ] **RBNF** — `locale_chain/2` and `nearest_rules_ancestor/1` onto `fallback_chain/2`; formatting unchanged for every RBNF locale and rule set.

* [ ] **Collation** — `LocaleDefaults` and the data pass onto `parent(_, component: :collations)`; sort keys compared over every locale.

* [ ] **The data pass** — `data/locale.ex`'s `locale_chain/1` onto `parent/2`; every generated locale file byte-identical, or each difference explained.

* [ ] **Inflection** — resolve, chain, map to resource names; remove its own `parent/1` and `chain/1`; `sr-Latn` no longer reads `sr`.

* [ ] **`localize_web`** — drop its own matching, fallback and parent calculations (its `@max_match_distance` of 79, the distance re-test and root handling in `closest_supported/2`, `supported_match/2`'s language comparison) and call `Localize` alone (user, 2026-11-27). Its own repository.

* [ ] **`localize_translate`** — onto `fallback_chain/2`, dropping its walker (its own repository).
