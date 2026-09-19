# Inflection upstream tracking and porting notes — plan

Date: September 19, 2026. `Localize.Inflection` began life as the standalone `unicode_inflection` library, whose engine was ported here in `fdeb0795`. That library was never published and is being retired. This file carries forward everything it knew that the code does not record: the upstream pin and how to move it, prepared work for two open upstream PRs, and the porting lessons from all 31 languages.

## Status

* **Pin:** `ae92d425` (data version `ae92d425e57a-r2`), upstream `main` head as of 2026-09-19.
* **Conformance at this pin:** all 31 upstream inflection suites (6,290 assertions) and all 25 pronoun suites (1,217) pass in full.
* **Upstream PR #198** (Serbian, all four declension classes): open, CI green, review requested but none submitted. Port plan ready below; blocked only on the merge.
* **Upstream PR #196** (German compound tokenizer): open. Adopting it means porting the Germanic decompounder first, which we have never done. Assessment below; not scheduled.

Recheck both at the start of any session that intends to pick this up:

```
gh pr view 198 --repo unicode-org/inflection --json state,mergedAt,mergeCommit
gh pr view 196 --repo unicode-org/inflection --json state,mergedAt,mergeCommit
```

Never pin to a PR branch. The CDN path carries the pin, so a branch SHA publishes a data version that later has to be abandoned. Re-pin only to a commit on upstream `main`.

## The upstream pin

The pin lives in `priv/localize/localize_inflection_sha` (40 hex digits, no trailing newline). `Localize.Inflection.Provider` reads it at compile time and derives the data version from its first 12 characters plus `@data_revision`; the CDN path is `inflection/<data_version>/<locale>.etf`.

### History

| pin | consumed data | note |
|---|---|---|
| `2333a964` | — | the original port |
| `ae92d425` | unchanged | six upstream commits, one of which moved every path |

The six commits between the two: `15d6e210`, `b2feac0f` and `e3d79c2f` (release packaging workflows), `af2510d7` (the restructure below), `4f4da559` (`.clang-format`, which is why open upstream PRs carry large whitespace-only hunks) and `ae92d425` (#207, C++ header and build fixes). Every file we consume has the same git object ID at both pins: all 217 under `resources/org/unicode/inflection/` and all 56 under `test/resources/inflection/dialog/`. The re-pin was then checked end to end: a full re-download at the new layout rewrote all 205 source files with none missing, git saw no change to any committed fixture, and all 48 regenerated artifacts hashed identical to `priv/localize/inflection_hashes.etf`, so the manifest was left alone.

### The #204 restructure

Upstream `af2510d7` (PR #204) lifted the whole source tree out of the `inflection/` subdirectory to the repository root. The path constants in `data/mix/tasks/localize.inflection.download.ex` were updated to match, so they are only valid for pins at or after that commit — raw and media URLs for an older pin still serve the old layout and would need the prefix back. `data/` moved to `tools/wikidata/` and `fst/` was deleted; neither is an input.

### Does a new pin change the data?

Compare git object IDs rather than downloading. For each commit, list the blobs and diff the consumed paths:

```
gh api "repos/unicode-org/inflection/git/trees/<sha>?recursive=1" \
  --jq '.tree[] | select(.type=="blob") | "\(.sha) \(.path)"' | sort
```

When both commits share a layout, the compare API is quicker: `gh api repos/unicode-org/inflection/compare/<old>...<new>` and filter `.files[].filename` for the two consumed prefixes. Any consumed path whose blob changed needs regenerating; if none did, the artifacts will regenerate byte-identical.

### Re-pin procedure

1. Check what the new pin changes (above).
2. Write the new SHA to `priv/localize/localize_inflection_sha` and update the two doctests in `Localize.Inflection.Provider` that spell out the data version (`data_version/0`, `file_url/1`).
3. `mix localize.inflection.download` fetches every supported locale's sources into `data/inflection/`. The conformance fixtures under `data/inflection/test/` are committed, so `git status` shows exactly which upstream suites changed.
4. `mix localize.inflection.generate` rebuilds all 48 artifacts into `priv/localize/inflection/`. It runs one locale per scheduler; 32 GB was comfortable.
5. Hash every regenerated artifact against `priv/localize/inflection_hashes.etf`. If all match, the manifest stays as it is. If any differ, the manifest must follow the canonical CDN bytes: publish first, then `mix localize.inflection.generate_hashes --from-cdn` and commit the result.
6. Publish the new data version before anything needs it. **`ci.yml` does not run `upload-inflection.yml`** (despite that workflow's header comment saying it is reused from there), and `test/test_helper.exs` downloads the fixture locales' data from the CDN at the pinned data version. So until the new version is on R2, CI's inflection suites fail on the download. After pushing the branch, run `gh workflow run upload-inflection.yml --ref <branch>`, or push to the `inflection` branch, which triggers it.

A local green run proves less than it appears to. `Mix.Tasks.Localize.DownloadInflection.download_for/2` skips any file already present in `priv/localize/inflection/` and does not check its version, so after a pin change the tests read whatever is on disk. That is exactly what step 4 wants, but it also means a stale directory passes silently.

## Serbian — upstream PR #198

Two files: `SrGrammarSynthesizer_SrDisplayFunction.cpp` (+245/-81) and the `sr.xml` conformance suite (28 → 65 cases). It fills in the rule branches that were TODO stubs upstream when we ported `lib/localize/inflection/synthesizer/sr.ex`, which is why our `inflect_with_rule/2` only implements rule A. **Measured on 2026-09-19 against the PR head (`9c10ca46`): 43/65.** The 22 failures are exactly the four unported branches: Class I masculine consonant (cases 10–20, 11 cases), Class I neuter -о/-е (21–26, 6), Class II stem extension (29 and 32, 2) and Class IV feminine consonant (59, 64 and 65, 3).

All the work is confined to `sr.ex` — no new data inputs, no generator change, and no data version bump beyond the pin itself. Estimated at 150–200 lines. Everything needed is below; the C++ does not need re-reading.

**Dispatch order in `inflect_with_rule/2`.** Order matters: Class II is tested before the -о/-е branch.

1. Gender is neuter and the lemma ends `ме`, `те` (but not `ште`), `же`, `ле`, `че` or `бе` → rule E (Class II).
2. The lemma ends `о` or `е` and gender is masculine or neuter → rule OE (Class I neuter).
3. The lemma ends `а` → rule A (Class III, already implemented).
4. Otherwise → the consonant rule. It returns the lemma unchanged for singular nominative, then routes feminine to Class IV and everything else to Class I masculine.

**Suffix tables**, indexed `[nominative, genitive, dative, accusative, vocative, instrumental, locative]`. `soft` is `soft_stem?(base)`, where `base` is the lemma with its final vowel dropped (rules E and OE) or the lemma after fleeting-а removal (masculine consonant). `{x|y}` means a soft stem takes the first and a hard stem the second.

| rule | singular | plural |
|---|---|---|
| A (existing) | `а е и у а ом и` | `е а ама е е ама ама` |
| OE, lemma ends `е` | `е а у е е {ем\|ом} у` | `а а има а а има има` |
| OE, lemma ends `о` | `о а у о о {ем\|ом} у` | `а а има а а има има` |
| E (Class II) | `е а у е е ом у` | `а а има а а има има` |
| masculine consonant | `"" а у а {у\|е} {ем\|ом} у` | `и а има е и има има` |
| feminine consonant | `"" и и "" и и и` | `и и има и и има има` |

**Helpers to add:**

* `soft_stem?(stem)` is false when the stem is empty, true when it ends `шт`, and otherwise true when its last character is one of `ж ч ш ћ ђ љ њ ј ц`.
* Rule E stem extension drops the final `е`, then appends `ен` for `-ме` lemmas, or `ет` for `-те` (not `-ште`), `-же`, `-ле`, `-че` and `-бе`.
* Masculine fleeting -а-: when the lemma ends `ац`, `нак`, `лак` or `цак` and is longer than two characters, delete the second-to-last character (`уранак` → `уранк`, `клинац` → `клинц`), then compute `soft` on the result.
* Feminine instrumental singular iotation, checked in this order before falling through to the table: ends `в`, `б`, `м` or `п` → append `љу`; ends `ст` → replace it with `шћ` and append `у`; ends `т` → replace it with `ћ` and append `у`; ends `ћ`, `ч`, `ш`, `ж`, `ђ`, `љ` or `њ` → append `у`; ends `р` → append `ју`.

**Easy to get wrong:**

* Upstream's `getCaseIndex` falls back to index 0 (nominative) for an unrecognised case, whereas `rule_a/3` returns the lemma unchanged when the case is missing from `@case_index`. Match upstream's fallback when generalising the suffix application, or the new rules diverge on odd input.
* Rule A gains a real semantic fix: the vocative `-ица` branch and the proper-noun branch become `if`/`else if`. Today both can fire and the second overwrites the first. Port it even though the suite does not cover it.
* The PR does not implement vocative palatalisation (к→ч). It deletes the commented-out `уранак → уранче` and `пашњак → пашњаче` cases rather than making them pass. Do not add it speculatively.
* The cases that already pass do so because Serbian's lexicon is tiny (1,186 entries) and words such as љубав, памет, младост, дете, дугме, име, време and ствар resolve through the dictionary path. Only the rule path changes, so a regression there shows up as a dictionary-path failure.

**Verifying.** Fetch the PR's `sr.xml` to a scratch path and, under `MIX_ENV=test`, run `Localize.Inflection.Conformance.run_file(:sr, path)`. After the port it must reach 65/65. Once #198 merges and the pin moves past it, the re-pin procedure's download step replaces the committed `data/inflection/test/inflection_sr.xml` and the regular suite covers it.

## German compound tokenizer — upstream PR #196

This is a subsystem port, not a language port. Its red CI is misleading: every failing job died on an HTTP 503 fetching Catch2 during CMake `FetchContent`, not on the code.

The PR is small in code because it reuses `GermanicWordAndDelimiterTokenExtractor`, the decompounder already driving da, fi, nl, no and sv upstream. `DeTokenizer` is an 18-line subclass. `DeDictionaryTokenizerConfig` sets the Fugenelemente `{s, se, e, n, ne, re, sne}` — reversed, because the splitter works right to left — and six tuning constants: `minCandidateLength 3`, `minSegmentLength 3`, `maxCompoundFreq 4000`, `lowerMinScoreRatio 0.25`, `upperMinScoreRatio 0.6` and `minCompoundLengthForCredibility 20`. **We have never ported the decompounder.** `Localize.Inflection.Tokenizer` is one regex with an `:nl` special case.

Scope if we take it on:

* Port `src/inflection/tokenizer/dictionary/` (`GermanicDecompounder`, `ParsingsScorer`, `Segment`, `SegmentValidator`, `DictionaryTokenizerConfig`) plus `locale/GermanicTokenExtractorIterator` and `locale/GermanicWordAndDelimiterTokenExtractor`. Roughly 35–40 KB of C++, comparable to the largest synthesizer port so far.
* Skip `trie/SerializedTrie`, which only exists to read the compiled binary `.tokd`. The text `tokenizer.dictionary` is in the tree, so the generator can read that and pack its own section.
* The dictionary format is `word\t<8 hex digits>`, where the flags carry frequency plus `isNoCompound`, `isNoAtomic` and `isSegment`. German is 4.1 MB; da 5.7, fi 11.6, nl 2.8, no 4.7 and sv 2.3 MB — 31 MB across all six, a large addition to the published data.
* `mix localize.inflection.download` fetches nothing from `tokenizer/` today; it would need each locale's `config_<locale>.properties` and dictionary. German's dictionary is not LFS (it is missing from `tokenizer/.gitattributes`, unlike the other five), so the raw endpoint serves it — probably an upstream oversight, worth a comment on the PR.
* The tokenizer gains a per-locale compound-splitting mode.

**It imposes no conformance obligation.** The PR leaves `dialog/inflection/de.xml` untouched; its 20 new cases land in `test/resources/inflection/tokenizer/de.xml`, a directory we do not consume and have no runner for. Its `DeGrammarSynthesizer_DeDisplayFunction` hunk (a lowercase head-word segment looked up capitalised, then re-lowercased after inflection) is inert on its own: it only fires when a lowercase head token follows an uppercase compound-start token inside one word, and our tokenizer never splits a compound. Do not port that hunk without the decompounder.

So the decision is not "adopt #196" but "port the Germanic decompounder once and unlock de, da, fi, nl, nb and sv together". Schedule it on its own merits. If it happens, the upstream tokenizer suites (`test/resources/inflection/tokenizer/{ar,da,en,fi,he,ml,nb,nl,sv}.xml`, plus `de.xml` from this PR) are the natural conformance gate, and a runner for them is part of the work.

## Porting lessons

Carried over from `unicode_inflection`, with module references updated to where the same code lives here.

### Adding or re-porting a language

1. `mix localize.inflection.download <locale>`, then `mix localize.inflection.generate <locale>`. Upstream needs `dictionary_<locale>.lst` and `inflectional_<locale>.xml`; a few languages ship empty or tiny lexicons (`et`, `id`, `ja`), and generation handles whatever exists. Add the locale to `Localize.Inflection.Locale` if it is new.
2. The download writes the upstream suite to `data/inflection/test/inflection_<locale>.xml`, and `test/localize/inflection/conformance_test.exs` discovers it through `Localize.Inflection.Conformance.fixtures/0`. No per-language test file.
3. Port `<Xx>GrammarSynthesizer.cpp` — `addSemanticFeatures` plus its lookup and display functions — to `lib/localize/inflection/synthesizer/<locale>.ex` and register it in the `@synthesizers` map in `Localize.Inflection.Synthesizer`. A language with no upstream synthesizer is dictionary-only and needs no module.
4. Iterate until the suite passes in full.

### Engine semantics — do not rediscover

* Dictionary lookups fall back to the locale-lowercased word (`Localize.Inflection.Data.lookup/2`). Grammeme masks are bignums; more than 64 bits is fine.
* `Localize.Inflection.Lookup.determine` mirrors upstream `DictionaryLookupFunction`. The popcount check is on the full property mask, not the category-masked one, and disambiguation buckets return the first non-empty bucket's masked name even when it is `""`.
* `Localize.Inflection.Inflector.reinflect` scores by optional-constraint score, then overlap with the source grammemes, then fewest extra grammemes; the strip is the longest matching suffix of the source row.
* Candidate ordering: disambiguation score descending, then the priority tables, inflectable candidates first, fewer grammeme bits, more inflections in the pattern.
* Inflector options: `:ignore` drops readings (Russian drops `{proper-noun, plural}`), and `:tie_break` defaults to `:first`. Do not flip `:tie_break` globally — it regressed 56 cases when tried.
* Upstream opens the ICU break iterator with the `fi` locale for every `DefaultTokenizer` language, and the clean value is a locale lowercase only. The regex tokenizer is enough for space-separated languages. Hyphens and apostrophes are token boundaries (`d'action` → `d` + `action`), except that Dutch keeps apostrophes inside words (`auto’s` is a dictionary key). UAX #29 keeps periods only between alphanumerics (`nowy.` → `nowy` + `.`). Indic combining marks need `\p{M}` in the continuation classes, or multi-word phrases split mid-word.
* Conformance driver semantics: `<source attr>` is a constraint; `<meta attr>` seeds the display value's initial constraint map; `<result attr>` is a feature query (`""` expects nil, `exists` asks `Concept.exists?`); `<result>text</result>` compares against the speakable string; `<text print= speak=>` is a speakable string pair. The xmerl SAX start event is `{:startElement, uri, local_name_charlist, qname, attrs}`.
* `grammar.xml`: the `default` attribute is dead data, and a feature with `<value>` children is bounded. Language categories merge with the common categories (Russian `pos` adds `adposition`). Aliasing is declared by an explicit `aliasable="false"` attribute (`numberPronoun`, `genderPronoun`, `copula`, Turkish `pronoun`), not computed from cross-category uniqueness — the computed heuristic broke Arabic `plural` and Turkish `third`. `Localize.Inflection.FeatureModel` aliases only aliasable categories; on a collision the first category in name order wins.
* An explicit `speak` constraint once vanished when it was the only constraint, because the display path skipped the synthesizer. The private `apply_speak/2` in `Localize.Inflection.Concept` now applies it to every display value.
* Deliberate deviation (en): possessive `’` versus `’s` is decided by per-reading noun analysis — a plural-only, non-proper-noun reading takes the bare `’`. Upstream's exact behaviour depends on its binary dictionary and was not reproducible from the source data.
* Elixir precedence around `||` and `&&&` caused two real bugs. Always bind `mask = x || 0` to a variable first.

### Generator and data

* Upstream merges `supplemental_<locale>.lst` (curated proper nouns and the like) into the dictionary, and so does the generator. The file is optional; en, fr and tr have one.
* Upstream inserts every dictionary entry under both its exact key and its lowercased key, first one wins. `add_lowercase_variants` in `data/inflection_gen/generate.ex` does the same — it is how `albanischs` finds `Albanischs` with its patterns.
* Every `.lst` dictionary ends with a `====` statistics footer that must not be parsed as entries; `data/inflection_gen/lexicon.ex` stops there. The footer once invented grammemes (`definite` for Arabic, from its options line), which masked a semantics bug. `Localize.Inflection.Dictionary.binary_properties` skips unknown names and ORs the known ones, returning nil only when none resolve — matching upstream `getBinaryProperties`, because the Arabic definiteness lookup asks for `definite` although no Arabic entry carries it.
* The download tries the media endpoint, falls back to raw, and rejects git-lfs pointer bodies. `ca` is raw-only.
* Suffix-exemplar guessing reads `exemplar/suffix_<locale>.csv`, which upstream ships only for fi, pl and ru: Russian caps the suffix at 5, Polish at 7 with a minimum stem of 2, both splicing on the common prefix.
* `yue` is a features-only artifact: a `grammar.xml` section with no dictionary.

### Per-language notes

* **fr** — `@words_preventing_inflection ~w(d de des du en par à)` blocks inflection of the following token. The capital-H rule lives in `PhraseProperties.starts_with_vowel?`: a known word starting with `H` is not a vowel start (`le Havre`). The definite article is copied without a space (articles carry their own spacing: `le `, `l’`), the indefinite with one (`un`, `une`, `des`); elision never adds a space. Gender uses `Localize.Inflection.GrammemeLookup` (upstream `GrammemeLookupFunction`: default value, first- or last-word-determines, suffix-guess hook).
* **de** — the dependent token is the one before the last whitespace gap, so hyphenated compounds stay in the head group. Eight article tables keyed by number, gender and case; declension suffix tables where the strong plural is case-sensitive and the weak and mixed plurals are always `en`; determiner-and-noun deduction of case, number and gender through the best reading; a genitive rule for proper nouns.
* **nl** — unknown compounds decompound by longest known suffix.
* **da** — the definite singular common article is the speakable pair `{den, dén}`; an attribute before the noun forces the indefinite (unsuffixed) form; a freestanding article appears only for indefinite singular or definite multi-word phrases.
* **sv, nb** — articles are never prepended (definiteness is suffixed). Swedish genitive after a colon (`USA:s`). Norwegian has three genders with a masculine default and rules suppressing the neuter `-t`.
* **it** — verbs are protected across the past-participle boundary; definiteness updates with the merged constraints.
* **ru** — ablative maps to instrumental and locative to prepositional (`FeatureModel.canonicalize` does this at the Concept boundary); takes `values[0]`; phrases inflect right to left, joining with hyphens; the static `X, Y` suffix path applies only to the prepositional.
* **pl** — virility is a three-rule system.
* **sr** — nominative is requested by omitting the case constraint; only rule A exists until #198 (above).
* **he** — the position of the definiteness prefix `ה` depends on the phrase: before a preposition it covers the whole phrase, in a multi-word phrase it goes on the last word.
* **tr** — suffix chains are synthesised with vowel harmony, starting from the normalised stem. Digit-final words harmonise over the `Localize.Inflection.TurkishNumbers` spell-out, including `virgül` fractions; the number scanner falls back to the final digit and keeps zero parses.
* **fi** — guessing uses harmony-matched suffix exemplars (candidate lists in the artifact; the generator substitutes in-lexicon words for missing CSV targets); compounds use the longest known noun suffix-word with a prefix of at least three characters; the in-lexicon fallback lemmas are aamu, keräily, filmi, ihme, aapelus and diesel; an unknown nominative singular stays unchanged; phrase-level guessing applies only to oblique cases.
* **ar** — no sun- or moon-letter assimilation; `ل` elides the alef of `ال`; pronoun-suffixed unknown tokens are split before inflection; case falls back genitive → accusative → nominative.
* **Indic** — ur, gu, kn, mr, pa and te (and variants of bn and ta) share `Localize.Inflection.PhraseDisplay`, upstream `PhraseDisplayFunction`: no heuristic guessing, and `guess=true` just keeps the original string.
* **hi** — words before an adposition are forced oblique (gender suppressed; an explicit case wins), and only का, के and की inflect among adpositions; a plural feminine becomes singular before a trailing plural verb.
* **ko** — pure particle switching from a key table. Vowel or consonant is decided by the final Hangul syllable's jongseong, `(cp - 0xAC00) rem 28`: 0 is a vowel, 8 is rieul, and rieul counts as a vowel only for 로/으로-type particles. Latin-ending words use the phonetic vowel test, except that a dictionary `rieul-end` tag overrides it as a consonant (`Apple` → 애플 → `Apple은`).
* **ml** — only the last significant token inflects, and upstream's doubled-respacing quirk is replicated; verb guessing appends packed-key suffixes (the future tense has a leading space); strings that are not Malayalam, or that contain `[\p{Latin}\p{Nd}\p{P}]`, pass through; an unchanged inflection returns nil.
* **Pronouns** — `Localize.Inflection.PronounConcept` parses the upstream `pronoun_<locale>.csv` tables against the feature model and caches the result in `:persistent_term`. A supported locale's table is folded into its artifact; script-only tables that no shipped locale owns (`zh_Hant`) stay CSV files in the data directory. Cells are grammeme aliases; a bare feature name is the generic empty value; `name=value` pairs and an optional `dependency=` prefix (keyed `dependency=<feature>`) are allowed. Matching prefers fewer generic matches, then fewer unmatched defaults, and the first entry wins ties. An initial pronoun (case-folded, one trailing space trimmed) seeds the defaults, with ambiguous values dropped, and is returned verbatim when the constraints match its entry exactly. `dependency=sound` matches the referenced concept's rendered string through `PhraseProperties` (French elision `t’` / `te `). Table fallback takes the special pairs `wuu_CN → zh`, `yue_HK → yue_Hant`, `zh_HK → yue_Hant` and `zh_TW → zh_Hant` first, then the parent locale. The upstream pronoun suites drive a possessee concept from the `codependent` element as `dependency=` constraints, with `a` standing in for vowel-sound tests.
