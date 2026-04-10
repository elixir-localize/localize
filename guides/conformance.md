# TR35 Conformance

This document maps the features defined in [Unicode Technical Standard #35 (LDML)](https://www.unicode.org/reports/tr35/) version 48 against the implementation status of the Localize library.

Two areas are explicitly out of scope:

* **Part 7 — Keyboards.** Not relevant to a formatting library.

* **Part 8 — Person Names.** Implemented as the separate [localize_person_names](https://hex.pm/packages/localize_person_names) package, which uses Localize's person-name locale data (stored under the `:person_names` key in each locale ETF) and implements the full TR35 Part 8 formatting algorithm.

## Legend

* **Implemented** — feature is present and tested.
* **Partial** — core functionality exists but some sub-features are missing.
* **Not implemented** — feature is absent.

---

## Part 1 — Core (tr35.html)

### Unicode Language and Locale Identifiers

| Feature | Status | Notes |
|---------|--------|-------|
| BCP 47 / RFC 5646 language tag parsing | Implemented | `Localize.Rfc5646.Parser`, pre-compiled NimbleParsec grammar. |
| Unicode locale extensions (`-u-`) | Implemented | Calendar (`ca`), collation (`co`), currency (`cu`), number system (`nu`), hour cycle (`hc`), first day (`fw`), region override (`rg`), measurement system (`ms`), and others. |
| Transformed extensions (`-t-`) | Implemented | Parser and struct support in `Localize.LanguageTag`. |
| Private use subtags (`-x-`) | Implemented | |
| Grandfathered and irregular tags | Implemented | |
| Locale ID canonicalization | Partial | Alias resolution via supplemental data. Full Annex C canonicalization algorithm not independently verified. |

### Locale Inheritance and Matching

| Feature | Status | Notes |
|---------|--------|-------|
| Parent locale chain | Implemented | `Localize.Locale.parent/1` uses CLDR parent locale data. |
| Likely subtags | Implemented | `Localize.LanguageTag.add_likely_subtags/1` and `remove_likely_subtags/1`. |
| Locale matching / best match | Implemented | `Localize.LanguageTag.best_match/3` using CLDR language matching data. |
| Default content locales | Not implemented | |
| Locale inheritance for data lookup | Partial | `Locale.get/3` supports `:fallback` option to walk parent chain. Not all data accessors use it consistently. |

### Validity Data

| Feature | Status | Notes |
|---------|--------|-------|
| Language validity | Implemented | `Localize.Validity` with ETF data. |
| Script validity | Implemented | |
| Territory validity | Implemented | |
| Variant validity | Implemented | |
| Unit validity | Implemented | |
| Subdivision validity | Implemented | |
| U and T extension validity | Implemented | |

---

## Part 2 — General (tr35-general.html)

### Display Names

| Feature | Status | Notes |
|---------|--------|-------|
| Language display names | Implemented | `Localize.Language.display_name/2` with `:standard`, `:short`, `:long`, `:menu`, and `:variant` styles. |
| Script display names | Implemented | `Localize.Script.display_name/2` with `:standard`, `:short`, `:stand_alone`, and `:variant` styles. |
| Territory display names | Implemented | `Localize.Territory.display_name/2` with `:standard`, `:short`, `:variant` styles. |
| Variant display names | Not implemented | |
| Key/type display names | Not implemented | |
| Locale display names | Implemented | `Localize.Locale.LocaleDisplay.display_name/2` implements the CLDR locale display name algorithm. |

### Layout

| Feature | Status | Notes |
|---------|--------|-------|
| Character order (LTR/RTL) | Not implemented | |
| Line order | Not implemented | |

### Character Elements

| Feature | Status | Notes |
|---------|--------|-------|
| Exemplar characters | Not implemented | |
| Ellipsis patterns | Implemented | `Localize.ellipsis/2` with `:initial`, `:medial`, `:final`, `:word_initial`, `:word_medial`, `:word_final` styles. |
| Parse lenient characters | Not implemented | |

### Delimiters

| Feature | Status | Notes |
|---------|--------|-------|
| Quotation marks | Implemented | `Localize.quote/2` with locale-appropriate primary and alternate quotation marks. |

### Measurement System Data

| Feature | Status | Notes |
|---------|--------|-------|
| Measurement system per territory | Implemented | `Localize.validate_measurement_system/1` and supplemental data. |
| Paper size per territory | Not implemented | |

### Unit Elements

| Feature | Status | Notes |
|---------|--------|-------|
| Unit identifiers (simple, compound) | Implemented | `Localize.Unit.Parser` parses full CLDR unit identifier syntax including SI prefixes, powers, per-units. |
| Unit formatting with plural patterns | Implemented | `Localize.Unit.to_string/2` with `:long`, `:short`, `:narrow` styles. |
| Compound unit formatting | Implemented | Multiplication, division, and power patterns. |
| Mixed/sequence units | Partial | `Localize.Unit` struct supports mixed units; formatting coverage not fully verified. |
| Duration unit patterns (hms) | Implemented | `Localize.Duration.to_time_string/2` formats durations as `"hh:mm:ss"` with unbounded hours. `to_string/2` formats as localized unit list (e.g., "11 months and 30 days"). |
| Coordinate units (N/S/E/W) | Not implemented | |
| Unit conversion | Implemented | `Localize.Unit.Conversion` with factor/offset mappings to base units. |
| Unit preferences by territory | Implemented | Territory and usage-based unit selection from supplemental data. |
| Grammatical case in units | Partial | `:grammatical_case` option supported in formatter with `:nominative` default. Full case/gender/definiteness coverage depends on locale data. |
| Grammatical gender in units | Partial | Data structures present; not all locales exercised. |

### Transforms

| Feature | Status | Notes |
|---------|--------|-------|
| General character transforms | Separate library | [unicode_transform](https://github.com/elixir-unicode/unicode_transform) implements the CLDR transform rules engine. |
| Script-to-script transliteration | Separate library | Provided by `unicode_transform`. |
| Number digit transliteration | Implemented | `Localize.Number.Transliterate` for numeric digit systems (e.g., Latin → Arabic-Indic). |

### List Patterns

| Feature | Status | Notes |
|---------|--------|-------|
| Conjunction lists ("a, b, and c") | Implemented | `Localize.List.to_string/2` with `:and`, `:and_short` styles. |
| Disjunction lists ("a, b, or c") | Implemented | `:or` style. |
| Unit lists ("3 ft, 7 in") | Implemented | `:unit`, `:unit_short`, `:unit_narrow` styles. |

### Context Transforms

| Feature | Status | Notes |
|---------|--------|-------|
| Capitalization by context | Not implemented | No context-dependent capitalization for display names. |

### Segmentation

| Feature | Status | Notes |
|---------|--------|-------|
| Grapheme cluster boundaries | Separate library | [unicode_string](https://github.com/elixir-unicode/unicode_string) implements Unicode text segmentation. |
| Word boundaries | Separate library | Provided by `unicode_string`. |
| Sentence boundaries | Separate library | Provided by `unicode_string`. |
| Line break boundaries | Separate library | Provided by `unicode_string`. |

### Annotations

| Feature | Status | Notes |
|---------|--------|-------|
| Character/emoji labels | Not implemented | |
| Typographic names | Not implemented | |

### POSIX Elements

| Feature | Status | Notes |
|---------|--------|-------|
| Yes/no strings | Not implemented | |
| POSIX locale identifier conversion | Implemented | `Localize.Locale` handles POSIX-style identifiers (e.g., `en_US.UTF-8`). |

---

## Part 3 — Numbers (tr35-numbers.html)

### Number Systems

| Feature | Status | Notes |
|---------|--------|-------|
| Numeric systems (digit mapping) | Implemented | `Localize.Number.System` with 97 systems loaded from ETF. |
| Algorithmic systems (RBNF) | Implemented | `Localize.Number.Rbnf` for Roman numerals, CJK, spellout, etc. |
| Number system per locale | Implemented | `:default`, `:native`, `:traditional`, `:finance` types resolved per locale. |

### Number Formatting

| Feature | Status | Notes |
|---------|--------|-------|
| Decimal format patterns | Implemented | `Localize.Number.to_string/2` with full pattern support. |
| Percent formatting | Implemented | `format: :percent` option. |
| Currency formatting | Implemented | `format: :currency` with symbol placement, spacing. |
| Accounting format | Implemented | `format: :accounting` for parenthesized negatives. |
| Compact/short formats ("1.2M") | Implemented | `format: :decimal_short`, `:decimal_long`, `:currency_short`, `:currency_long`. |
| Scientific notation | Implemented | Exponent formatting with configurable digits. |
| Significant digits | Implemented | `@` pattern character for significant digit control. |
| Number padding | Implemented | `*` pattern character for fixed-width padding. |
| Grouping separators | Implemented | Primary and secondary grouping sizes. |
| Rounding | Implemented | Pattern-specified increments, half-even default. |
| Special values (NaN, Infinity) | Implemented | |
| Number symbols per locale | Implemented | Decimal, grouping, percent, minus, plus, exponential, etc. |

### Number Parsing

| Feature | Status | Notes |
|---------|--------|-------|
| String to number parsing | Implemented | `Localize.Number.Parser` with locale-aware digit transliteration. |
| Lenient parsing | Not implemented | |

### Number Ranges

| Feature | Status | Notes |
|---------|--------|-------|
| Number range formatting | Implemented | `Localize.Number.to_range_string/3` using locale-specific range patterns. |
| Approximate number formatting | Implemented | `Localize.Number.to_approximately_string/2`, also `to_at_least_string/2` and `to_at_most_string/2`. |

### Rational Numbers

| Feature | Status | Notes |
|---------|--------|-------|
| Fraction formatting | Implemented | `Localize.Number.to_ratio_string/2`. |

### Currencies

| Feature | Status | Notes |
|---------|--------|-------|
| Currency codes and validation | Implemented | `Localize.Currency.validate_currency/1` with ISO 4217. |
| Currency display names (plural) | Implemented | `Localize.Currency.display_name/2`, `pluralize/3`. |
| Currency symbols | Implemented | Via locale data. |
| Currency digits/rounding | Implemented | Supplemental currency data. |
| Territory currency history | Implemented | `Localize.Currency.territory_currencies/1` with date ranges. |
| Current currency for territory | Implemented | `Localize.Currency.current_currency_for_territory/1`. |
| Custom/private currencies | Implemented | `Localize.Currency.Store` GenServer. |

### Plural Rules

| Feature | Status | Notes |
|---------|--------|-------|
| Cardinal plural rules | Implemented | `Localize.Number.PluralRule.Cardinal` with all CLDR operands (n, i, f, t, v, w, c, e). |
| Ordinal plural rules | Implemented | `Localize.Number.PluralRule.Ordinal`. |
| Plural ranges | Implemented | `Localize.Number.PluralRule.Range`. |
| Explicit 0 and 1 | Partial | Standard plural categories used; explicit 0/1 override not independently verified. |

### Rule-Based Number Formatting (RBNF)

| Feature | Status | Notes |
|---------|--------|-------|
| Spellout rules | Implemented | `Localize.Number.Rbnf` with locale-specific rule sets. |
| Ordinal rules | Implemented | |
| Numbering system rules | Implemented | Roman numerals, CJK, etc. via algorithmic number systems. |

---

## Part 4 — Dates (tr35-dates.html)

### Calendar Elements

| Feature | Status | Notes |
|---------|--------|-------|
| Month names (format/standalone, wide/abbreviated/narrow) | Implemented | `Localize.Calendar.months/2`. |
| Day names (format/standalone, wide/abbreviated/narrow) | Implemented | `Localize.Calendar.days/2`. |
| Quarter names | Implemented | `Localize.Calendar.quarters/2`. |
| Era names | Implemented | `Localize.Calendar.eras/2`. |
| Day period names (AM/PM, flexible) | Implemented | `Localize.Calendar.day_periods/2`. |
| Cyclic name sets (Chinese/Dangi) | Not implemented | |
| Month patterns (leap months) | Not implemented | |

### Date/Time Formatting

| Feature | Status | Notes |
|---------|--------|-------|
| Date format patterns (:short/:medium/:long/:full) | Implemented | `Localize.Date.to_string/2`. |
| Time format patterns (:short/:medium/:long/:full) | Implemented | `Localize.Time.to_string/2`. |
| DateTime combined patterns | Implemented | `Localize.DateTime.to_string/2`. |
| All date format pattern symbols (y, M, d, E, G, etc.) | Implemented | Full symbol set in `Localize.DateTime.Formatter`. |
| Hour cycle (h, H, k, K) | Implemented | Including territory-based preferences. |
| Day periods (a, b, B) | Implemented | AM/PM and flexible day periods. |
| Available formats (skeletons) | Implemented | `Localize.DateTime.Format.Match` for skeleton matching. |
| Interval formats | Implemented | `Localize.Interval.to_string/3` for date/time/datetime intervals. |
| Append items (missing fields) | Not implemented | |

### Date/Time Parsing

| Feature | Status | Notes |
|---------|--------|-------|
| String to date/time parsing | Not implemented | |

### Calendar Fields

| Feature | Status | Notes |
|---------|--------|-------|
| Relative date/time formatting | Implemented | `Localize.DateTime.Relative` — "yesterday", "in 3 days", etc. |
| Calendar field display names | Partial | Data accessible via locale data; no dedicated public function for field names. |

### Supplemental Date Data

| Feature | Status | Notes |
|---------|--------|-------|
| Calendar preferences per territory | Implemented | Supplemental data loaded from ETF. |
| Week data (firstDay, minDays) | Implemented | `Localize.SupplementalData.weeks/0`. |
| Weekend data | Implemented | Via week data. |
| Time data (preferred hour cycle) | Implemented | Time preferences data from ETF. |
| Day period rules | Implemented | Day period rule sets loaded from supplemental data. |

### Time Zones

| Feature | Status | Notes |
|---------|--------|-------|
| Timezone format symbols (z, Z, O, v, V, X, x) | Implemented | `Localize.DateTime.Formatter` handles all timezone symbols. |
| GMT offset formatting | Implemented | `hourFormat`, `gmtFormat`, `gmtZeroFormat` patterns. |
| Metazone names | Not implemented | Metazone data is not loaded or used for display name resolution. |
| Exemplar cities | Not implemented | |
| Timezone fallback formatting | Partial | Offset-based fallback works; metazone name fallback chain not implemented. |

### Semantic Skeletons

| Feature | Status | Notes |
|---------|--------|-------|
| Semantic skeleton support | Not implemented | Traditional skeleton matching is implemented but the newer semantic skeleton system from TR35 Section 29-32 is not. |

### Supported Calendars

| Feature | Status | Notes |
|---------|--------|-------|
| Gregorian | Implemented | Primary calendar. |
| Japanese | Implemented | Era data and formatting. |
| Chinese | Implemented | Calendar data present. |
| Persian | Implemented | Calendar data present. |
| Coptic | Implemented | Calendar data present. |
| Ethiopic | Implemented | Including Amete Alem variant. |
| Dangi (Korean) | Implemented | Calendar data present. |
| Buddhist | Implemented | Era (BE), month, and day data tested. |
| Hebrew | Implemented | Era (AM), 13-month calendar with leap year variant tested. |
| Islamic variants | Implemented | `:islamic`, `:islamic_civil`, `:islamic_rgsa`, `:islamic_tbla`, `:islamic_umalqura` — eras (AH) and month names (Muharram, Ramadan, etc.) tested. |
| ROC (Minguo) | Implemented | Era names (B.R.O.C., Minguo) tested. |
| Indian (Saka) | Implemented | Calendar data present and included in `known_calendars/0`. |

---

## Part 5 — Collation (tr35-collation.html)

### Core Collation

| Feature | Status | Notes |
|---------|--------|-------|
| UCA (Unicode Collation Algorithm) | Implemented | `Localize.Collation` with DUCET-based sort key generation. |
| CLDR root collation | Implemented | Uses `allkeys_CLDR` data. |
| Multi-level comparison (L1-L4) | Implemented | Primary through quaternary levels. |
| Variable weighting (shifted) | Implemented | `alternate: :shifted` option. |
| Normalization (NFD) | Implemented | Automatic NFD when tailoring requires it. |
| French secondary sorting | Implemented | `backwards: :level2` / `[backwards 2]` directive. |

### Collation Options (BCP 47 keys)

| Feature | Status | Notes |
|---------|--------|-------|
| Strength (ks) | Implemented | Levels 1-4 and identical. |
| Alternate (ka) | Implemented | `noignore` and `shifted`. |
| Backwards (kb) | Implemented | Level 2 reversal. |
| Normalization (kk) | Implemented | |
| Case level (kc) | Implemented | |
| Case first (kf) | Implemented | `upper` and `lower`. |
| Numeric collation (kn) | Implemented | `Localize.Collation.Numeric` for number-aware sorting. |
| Reorder (kr) | Implemented | Script reordering with weight remapping. |
| Max variable (kv) | Implemented | `space`, `punct`, `symbol`, `currency`. |
| Hiragana quaternary (kh) | Not implemented | Deprecated in recent UCA. |

### Collation Tailoring

| Feature | Status | Notes |
|---------|--------|-------|
| Locale-specific tailoring rules | Implemented | 110 locale/type pairs covering 97 languages, extracted from CLDR XML. |
| Relation operators (`<`, `<<`, `<<<`, `<<<<`, `=`) | Implemented | |
| Contractions (multi-character) | Implemented | |
| Expansions (slash notation) | Implemented | e.g., `ccs/cs` in Hungarian. |
| Star syntax (`<*`) | Implemented | Used for CJK and other large character sets. |
| Context before (`\|`) | Not implemented | |
| `[before N]` positioning | Not implemented | |
| `[suppressContractions]` | Implemented | Used by cu, sr, mk. |
| `[optimize]` | Not applicable | Advisory hint; intentionally ignored. |
| `[import]` | Implemented | Resolved at extraction time — imported rules are inlined into the ETF. Supports BCP47 tags (e.g., `und-u-co-search`, `de-u-co-phonebk`) and short locale tags (e.g., `hr`). |
| `[strength]` directive | Not implemented | Used by ja:private-kana only. |

### Collation Types

| Feature | Status | Notes |
|---------|--------|-------|
| Standard collation | Implemented | Default type for all locales. |
| Search collation | Implemented | Root search rules (Arabic form equivalences, Korean jamo decomposition, `[suppressContractions]`) extracted from CLDR XML. 20 locale-specific search types with resolved imports. Accessed via `type: :search` option. |
| Phonebook (de), Pinyin (zh), etc. | Partial | Some non-standard types extracted; not all verified. |

### Collation Features

| Feature | Status | Notes |
|---------|--------|-------|
| Alphabetic index characters | Not implemented | No UI bucketing support. |
| Collation type fallback chain | Partial | Falls back to standard; full 7-step chain not verified. |

---

## Part 6 — Supplemental (tr35-info.html)

### Territory Data

| Feature | Status | Notes |
|---------|--------|-------|
| Territory containment | Implemented | `Localize.Territory.territory_containers/0`, `territory_containment/0`. |
| Subdivision containment | Implemented | `Localize.Territory.territory_subdivision_containment/0`. |
| Territory information (GDP, population) | Implemented | `Localize.Territory.info/1`. |
| Language population data | Implemented | Via territory info. |
| Emoji flags | Implemented | `Localize.Territory.unicode_flag/1`. |

### Supplemental Language Data

| Feature | Status | Notes |
|---------|--------|-------|
| Scripts per language | Not implemented | Data not exposed as a public API. |
| Language grouping (families) | Not implemented | |

### Code Mappings

| Feature | Status | Notes |
|---------|--------|-------|
| Territory code mappings (alpha-2/3, FIPS, numeric) | Implemented | `Localize.Territory.territory_codes/0`. |
| Currency code mappings | Implemented | ISO 4217 via `Localize.Currency`. |

### Aliases

| Feature | Status | Notes |
|---------|--------|-------|
| Language aliases | Implemented | Supplemental alias data loaded from ETF. |
| Territory aliases | Implemented | |
| Script aliases | Implemented | |
| Variant aliases | Implemented | |

### Parent Locales

| Feature | Status | Notes |
|---------|--------|-------|
| CLDR parent locale data | Implemented | `Localize.Locale.parent/1`. |

### Unit Data (Supplemental)

| Feature | Status | Notes |
|---------|--------|-------|
| Unit conversion factors | Implemented | Extracted from CLDR XML via `scripts/extract_unit_data.exs`. |
| Unit preferences per territory | Implemented | |
| Unit quantities and base units | Implemented | |
| SI and binary prefixes | Implemented | `Localize.Unit.Parser` handles all CLDR prefixes. |

### Coverage Levels

| Feature | Status | Notes |
|---------|--------|-------|
| Coverage level assessment | Not implemented | |

---

## Part 9 — MessageFormat (tr35-messageFormat.html)

### MF2 Syntax

| Feature | Status | Notes |
|---------|--------|-------|
| Simple messages | Implemented | `Localize.Message.Parser` with pre-compiled NimbleParsec grammar. |
| Complex messages | Implemented | |
| Quoted patterns (`{{...}}`) | Implemented | |
| Text and escape sequences | Implemented | |
| Declarations (`.input`, `.local`) | Implemented | `Localize.Message.Interpreter` handles all declaration types. |
| Pattern selection (`.match`) | Implemented | With selector resolution and variant ranking. |
| Expressions (literal, variable, function) | Implemented | |
| Options on functions | Implemented | |
| Markup (open, close, standalone) | Implemented | Parsed and emitted in interpreter output. |
| Attributes | Implemented | Parsed; treated as metadata per spec. |

### MF2 Default Functions

| Feature | Status | Notes |
|---------|--------|-------|
| `:string` | Implemented | |
| `:number` | Implemented | Delegates to `Localize.Number.to_string/2`. |
| `:integer` | Implemented | |
| `:percent` | Implemented | |
| `:currency` | Implemented | |
| `:unit` | Implemented | Delegates to `Localize.Unit.to_string/2`. |
| `:date` | Implemented | Delegates to `Localize.Date.to_string/2`. |
| `:time` | Implemented | Delegates to `Localize.Time.to_string/2`. |
| `:datetime` | Implemented | Delegates to `Localize.DateTime.to_string/2`. |
| `:offset` | Implemented | Subtracts offset from operand for plural selection while formatting the original value. Used for patterns like "you and N other people". |

### Localize-specific MF2 functions (not in the spec)

| Function | Notes |
|----------|-------|
| `:list` | Formats a list operand by delegating to `Localize.List.to_string/2`. Each element is itself formatted via `Localize.Chars`, so a list of dates, numbers, units, etc. picks up the message's locale and forwarded options. Supports a `style` (or `type`) option whose values map to CLDR list styles: `"and"`, `"and-short"`, `"and-narrow"`, `"or"`, `"or-short"`, `"or-narrow"`, `"unit"`, `"unit-short"`, `"unit-narrow"`. Default is `"and"`. |

### MF2 Error Handling

| Feature | Status | Notes |
|---------|--------|-------|
| Syntax errors | Implemented | Parser returns `{:error, reason}`. |
| Resolution errors (unknown function, unresolved variable) | Partial | Unknown functions fall back to string conversion rather than error. |
| Data model errors | Partial | Duplicate declarations and options not explicitly validated. |

### MF2 Data Model

| Feature | Status | Notes |
|---------|--------|-------|
| JSON interchange format | Implemented | `Localize.Message.JSON.to_json/2` and `from_json/1` for round-trip serialization to the TR35 §8 data model. |
| Bidirectional text handling | Implemented | `:bidi` option (`:none`, `:isolate`, `:auto`) wraps placeholder output in Unicode isolate characters (FSI/PDI). Supports `u:dir` attribute for per-expression overrides. |

---

## Summary

### Implemented (core functionality present and tested)

* Language tag parsing and validation (BCP 47 / RFC 5646)
* Locale management (get/put/default/with_locale)
* Likely subtags and locale matching
* Number formatting (decimal, percent, currency, accounting, compact, scientific, RBNF)
* Number parsing
* Date, time, and datetime formatting
* Interval formatting
* Relative date/time formatting
* Unit formatting, conversion, and preferences (also include basic math functions)
* List formatting
* Currency data and validation
* Territory data and display names
* Language display names
* Locale display names
* Plural rules (cardinal, ordinal, ranges)
* Collation with locale tailoring (97 languages)
* MessageFormat 2 parsing and interpretation
* Quotation marks and ellipsis formatting

### Separate libraries

* General character transforms/transliteration — [unicode_transform](https://github.com/elixir-unicode/unicode_transform)
* Text segmentation (grapheme/word/sentence/line) — [unicode_string](https://github.com/elixir-unicode/unicode_string)

### Not implemented

* Date/time parsing (string to date)
* Metazone display names
* Semantic skeletons
* Context-dependent capitalization
* Collation alphabetic index (UI bucketing)
* Coordinate unit formatting (N/S/E/W)
* Layout direction data
* Coverage level assessment
* Cyclic name sets (Chinese/Dangi calendars)
* Append items (missing date/time fields)

### Not in scope for Localize

* Emoji/character annotations and labels
* Keyboards

