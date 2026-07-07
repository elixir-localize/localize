# Collation Guide

This guide explains how to use `Localize.Collation` for locale-sensitive string sorting and comparison.

## What Localize.Collation does

`Localize.Collation` implements the [Unicode Collation Algorithm (UCA)](https://www.unicode.org/reports/tr10/) with CLDR locale-specific tailoring. It provides:

* **`sort/2`** — sort a list of strings in locale-appropriate order.

* **`compare/3`** — compare two strings, returning `:lt`, `:eq`, or `:gt`.

* **`sort_key/2`** — generate a binary sort key for external sorting (e.g., database ORDER BY).

These functions handle multi-level comparison (base character, accents, case, punctuation), locale-specific letter ordering, script reordering, and special rules for digraphs, contractions, and expansions.

## Why Enum.sort is not enough

Elixir's `Enum.sort/1` compares strings by Unicode codepoint value. This produces results that are incorrect for most human-facing use cases:

```elixir
iex> # Codepoint sorting — wrong for users
iex> Enum.sort(["résumé", "resume", "Résumé", "RESUME"])
["RESUME", "Résumé", "resume", "résumé"]
```

Problems with codepoint sorting:

* **Case**: uppercase letters (A–Z, U+0041–005A) sort before all lowercase letters (a–z, U+0061–007A), so "RESUME" appears before "resume".

* **Accents**: accented characters sort after all ASCII letters, so "résumé" appears last.

* **Non-Latin scripts**: Cyrillic, Greek, CJK, and other scripts sort in arbitrary codepoint order that doesn't match any language's expectations.

* **Locale conventions**: many languages treat certain character combinations as single letters (e.g., Croatian "dž", Spanish traditional "ch", Hungarian "cs").

UCA-based collation fixes all of these:

```elixir
iex> Localize.Collation.sort(["résumé", "resume", "Résumé", "RESUME"])
["resume", "RESUME", "résumé", "Résumé"]
```

Base letters sort together, case and accents are secondary/tertiary distinctions, and locale-specific rules apply automatically.

## How locale affects collation

Every locale can define:

* **Letter ordering** — which characters sort where. For example, Swedish places å, ä, ö after z; German standard treats ä as a variant of a.

* **Digraphs and contractions** — character sequences that sort as single units. Croatian treats "lj" as a letter between l and m.

* **Expansions** — single characters that sort as if they were multiple characters. German phonebook treats "ä" as "ae".

* **Default options** — some locales set `case_first: :upper` by default (Danish, Norwegian).

You specify the locale with the `:locale` option:

```elixir
iex> # Croatian: č sorts between c and d
iex> Localize.Collation.sort(["č", "c", "d"], locale: "hr")
["c", "č", "d"]

iex> # Spanish: ñ sorts between n and o
iex> Localize.Collation.sort(["ñ", "n", "o"], locale: "es")
["n", "ñ", "o"]
```

When no locale is specified, `Localize.get_locale()` is used.

## Examples

### Basic DUCET sorting

The Default Unicode Collation Element Table (DUCET) provides the base ordering for all characters. Letters sort by base character first, then by accent, then by case:

```elixir
iex> Localize.Collation.sort(["résumé", "resume", "Résumé", "RESUME"])
["resume", "RESUME", "résumé", "Résumé"]

iex> Localize.Collation.sort(["banana", "Apple", "cherry"])
["Apple", "banana", "cherry"]
```

### Case-insensitive sorting

Set `strength: :secondary` to ignore case differences (level 3). Characters that differ only in case compare as equal:

```elixir
iex> Localize.Collation.compare("a", "A", strength: :secondary)
:eq

iex> Localize.Collation.sort(["banana", "Apple", "cherry"],
...>   strength: :secondary)
["Apple", "banana", "cherry"]
```

### Accent-insensitive sorting

Set `strength: :primary` to ignore both accent and case differences. Characters that share the same base letter compare as equal:

```elixir
iex> Localize.Collation.compare("cafe", "café", strength: :primary)
:eq

iex> Localize.Collation.sort(["cafe", "café", "caff"],
...>   strength: :primary)
["cafe", "café", "caff"]
```

### Case-first sorting

Control whether uppercase or lowercase sorts first among otherwise equal strings:

```elixir
iex> # Uppercase first
iex> Localize.Collation.sort(["apple", "Apple", "APPLE"],
...>   case_first: :upper)
["APPLE", "Apple", "apple"]

iex> # Lowercase first (default for most locales)
iex> Localize.Collation.sort(["apple", "Apple", "APPLE"],
...>   case_first: :lower)
["apple", "Apple", "APPLE"]

iex> # Danish defaults to uppercase first
iex> Localize.Collation.sort(["apple", "Apple"], locale: "da")
["Apple", "apple"]
```

### German phonebook sorting

German has two collation types. Standard collation treats ä as a variant of a. Phonebook collation expands ä to "ae", placing it between "ad" and "af":

```elixir
iex> # Standard: Ä sorts near A
iex> Localize.Collation.sort(["Ärger", "Anger", "Azur"], locale: "de")
["Anger", "Ärger", "Azur"]

iex> # Phonebook: Ä expands to AE, sorts between AD and AF
iex> Localize.Collation.sort(["Ärger", "Anger", "Azur"],
...>   locale: "de", type: :phonebook)
["Ärger", "Anger", "Azur"]
```

### French Canadian backwards accent sorting

French Canadian uses "backwards" level-2 comparison, meaning accents are compared from the end of the string rather than the beginning. This affects words that differ in accent position:

```elixir
iex> # French Canadian: accent on later syllable sorts first
iex> Localize.Collation.sort(["côte", "coté", "cote", "côté"],
...>   locale: "fr-CA")
["cote", "côte", "coté", "côté"]

iex> # Default (non-backwards): accent on earlier syllable sorts first
iex> Localize.Collation.sort(["côte", "coté", "cote", "côté"])
["cote", "coté", "côte", "côté"]
```

### Numeric sorting

Enable numeric collation to sort embedded digit sequences by numeric value rather than digit-by-digit:

```elixir
iex> # Without numeric: "10" < "2" (codepoint: "1" < "2")
iex> Localize.Collation.sort(["file10", "file2", "file1"])
["file1", "file10", "file2"]

iex> # With numeric: 2 < 10
iex> Localize.Collation.sort(["file10", "file2", "file1"],
...>   numeric: true)
["file1", "file2", "file10"]
```
This applies to all digits in all scripts - not just indo-arabic digits.

### Search collation

Search collation provides tailored equivalences for loose matching. For example, Arabic presentation forms are equated to their base forms, and Korean composed jamo are decomposed:

```elixir
iex> Localize.Collation.compare("cafe", "café",
...>   type: :search, strength: :primary)
:eq
```

### Ignoring punctuation (shifted)

Set `alternate: :shifted` to treat whitespace and punctuation as ignorable at primary and secondary levels:

```elixir
iex> Localize.Collation.sort(
...>   ["black bird", "blackbird", "black-bird"],
...>   alternate: :shifted)
["black bird", "blackbird", "black-bird"]
```

## Collation options

### Keyword options

All functions accept the following keyword options:

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `:locale` | locale atom or string | `Localize.get_locale()` | Locale for tailoring and defaults. |
| `:type` | `:standard`, `:search`, `:phonebook`, `:pinyin`, `:stroke`, `:traditional`, etc. | `:standard` | Collation type. |
| `:strength` | `:primary`, `:secondary`, `:tertiary`, `:quaternary`, `:identical` | `:tertiary` | Comparison depth. |
| `:alternate` | `:non_ignorable`, `:shifted` | `:non_ignorable` | How to handle variable-weight characters (whitespace, punctuation). |
| `:backwards` | `true`, `false` | `false` | Reverse level-2 (accent) comparison direction. |
| `:normalization` | `true`, `false` | `false` | Force NFD normalisation (auto-enabled when tailoring requires it). |
| `:case_level` | `true`, `false` | `false` | Insert a case-comparison level between secondary and tertiary. |
| `:case_first` | `:upper`, `:lower`, `false` | `false` | Whether uppercase or lowercase sorts first. |
| `:numeric` | `true`, `false` | `false` | Sort embedded digit sequences by numeric value. |
| `:max_variable` | `:space`, `:punct`, `:symbol`, `:currency` | `:punct` | Highest character class treated as variable when `alternate: :shifted`. |
| `:reorder` | list of script atoms | `[]` | Reorder script groups (e.g., `[:Cyrl, :Latn]`). |

### Shorthand options

These convenience options map to the core options above. If a corresponding core option is also provided, the core option takes precedence.

| Shorthand | Equivalent | Description |
|-----------|------------|-------------|
| `ignore_accents: true` | `strength: :primary` | Ignore accent and case differences. |
| `ignore_case: true` | `strength: :secondary` | Ignore case differences but respect accents. |
| `ignore_punctuation: true` | `strength: :tertiary, alternate: :shifted` | Treat whitespace and punctuation as ignorable. |
| `casing: :insensitive` | `strength: :secondary` | Alias for case-insensitive comparison. |
| `casing: :sensitive` | (no change) | Explicit case-sensitive comparison (the default). |

```elixir
iex> Localize.Collation.compare("cafe", "café", ignore_accents: true)
:eq

iex> Localize.Collation.compare("a", "A", ignore_case: true)
:eq

iex> Localize.Collation.compare("a", "A", casing: :insensitive)
:eq
```

### Options encoded in a locale identifier

Collation options can be embedded in a BCP 47 locale identifier using the `-u-` Unicode extension. The BCP 47 collation keys are parsed from the locale tag's `-u-` extension and applied automatically:

```elixir
iex> # German phonebook via locale string
iex> Localize.Collation.sort(["Ärger", "Anger", "Azur"], locale: "de-u-co-phonebk")
["Ärger", "Anger", "Azur"]

iex> # Case-insensitive via locale string
iex> Localize.Collation.compare("a", "A", locale: "en-u-ks-level2")
:eq

iex> # Numeric sorting via locale string
iex> Localize.Collation.sort(["file10", "file2", "file1"], locale: "en-u-kn-true")
["file1", "file2", "file10"]

iex> # Uppercase-first via locale string
iex> Localize.Collation.sort(["apple", "Apple", "APPLE"], locale: "en-u-kf-upper")
["APPLE", "Apple", "apple"]
```

The BCP 47 keys and their mappings:

| BCP 47 Key | Option | Values |
|------------|--------|--------|
| `co` | `:type` | `standard`, `search`, `phonebk`, `pinyin`, `stroke`, `trad`, etc. |
| `ks` | `:strength` | `level1`, `level2`, `level3`, `level4`, `identic` |
| `ka` | `:alternate` | `noignore`, `shifted` |
| `kb` | `:backwards` | `true`, `false` |
| `kk` | `:normalization` | `true`, `false` |
| `kc` | `:case_level` | `true`, `false` |
| `kf` | `:case_first` | `upper`, `lower`, `false` |
| `kn` | `:numeric` | `true`, `false` |
| `kr` | `:reorder` | Script codes (e.g., `latn-arab`) |
| `kv` | `:max_variable` | `space`, `punct`, `symbol`, `currency` |

Keyword options and locale-encoded options can be combined. When both are present, keyword options take precedence.

### How options interact

**Strength** controls how many levels are compared:

| Strength | Compares | Ignores |
|----------|----------|---------|
| `:primary` | Base character | Accents, case, punctuation |
| `:secondary` | Base + accents | Case, punctuation |
| `:tertiary` (default) | Base + accents + case | Punctuation differences |
| `:quaternary` | Base + accents + case + punctuation | Nothing (except NFD ordering) |
| `:identical` | Everything including codepoint | Nothing |

**Case options** interact with strength:

* `case_first: :upper` only has effect at tertiary level or above. At `:primary` or `:secondary` strength, case is already ignored.

* `case_level: true` inserts an extra comparison level between secondary and tertiary. This allows case-sensitive, accent-insensitive sorting.

**Alternate** interacts with `max_variable`:

* `alternate: :shifted` makes characters up to `max_variable` ignorable at primary/secondary levels. With `max_variable: :punct` (default), whitespace and punctuation are ignored.

* Setting `max_variable: :symbol` additionally ignores symbols. Setting `max_variable: :currency` ignores currency symbols too.

**Backwards** only affects level 2 (accents). It reverses the direction of accent comparison — accents at the end of a string take precedence over accents at the beginning.

## Available locale-specific collations

The following table lists all locales with CLDR collation tailoring. Locales not listed here use the default DUCET ordering with no modifications.

| Locale | Types | Description |
|--------|-------|-------------|
| `aa` | standard | Afar. |
| `af` | standard | Afrikaans. |
| `am` | standard | Amharic — Ethiopic script ordering. |
| `ar` | standard, compat | Arabic script ordering with presentation form mappings. |
| `as` | standard | Assamese — Bengali script ordering. |
| `az` | standard, search | Azerbaijani — Latin with Turkish-style dotted/dotless i. |
| `bal` | standard | Baluchi. |
| `bal-Latn` | standard | Baluchi (Latin script). |
| `be` | standard | Belarusian — Cyrillic ordering. |
| `bg` | standard | Bulgarian — Cyrillic ordering. |
| `blo` | standard | Anii. |
| `bn` | standard, traditional | Bengali script ordering. |
| `bo` | standard | Tibetan script ordering. |
| `br` | standard | Breton. |
| `bs` | standard, search | Bosnian — imports Croatian standard rules. |
| `bs-Cyrl` | standard | Bosnian (Cyrillic) — imports Serbian rules. |
| `ca` | standard, search | Catalan. |
| `ceb` | standard | Cebuano. |
| `chr` | standard | Cherokee — Cherokee script ordering. |
| `cs` | standard, digits-after | Czech — č, ř, š, ž as separate letters. `digits-after` places digits after letters. |
| `cu` | standard | Church Slavic — Cyrillic with case-first:upper. |
| `cy` | standard | Welsh — ch, dd, ff, ng, ll, ph, rh, th digraphs. |
| `da` | standard, search | Danish — æ, ø, å after z; case-first:upper by default. |
| `de` | phonebook, eor, search | German — phonebook expands ä→ae, ö→oe, ü→ue. EOR is European Ordering Rules. |
| `de-AT` | phonebook | Austrian German phonebook. |
| `dsb` | standard | Lower Sorbian. |
| `dz` | standard | Dzongkha — Tibetan script ordering. |
| `ee` | standard | Ewe — additional letters ɖ, ɛ, ƒ, ɣ, ŋ, ɔ, ʋ. |
| `el` | standard | Greek script ordering. |
| `en-US-POSIX` | standard | POSIX sort order (codepoint-like). |
| `eo` | standard | Esperanto — ĉ, ĝ, ĥ, ĵ, ŝ, ŭ placement. |
| `es` | standard, search, traditional | Spanish — traditional treats ch and ll as separate letters. |
| `et` | standard | Estonian — š, ž, ö, ä, ü, õ after z. |
| `fa` | standard | Persian — Arabic script with Persian-specific ordering. |
| `fa-AF` | standard | Dari (Afghan Persian). |
| `ff-Adlm` | standard | Fulah (Adlam script). |
| `fi` | standard, search, traditional | Finnish — å after z; traditional differs in w/v ordering. |
| `fil` | standard | Filipino — Spanish-derived letter ordering. |
| `fo` | standard, search | Faroese — Nordic letter ordering. |
| `fr-CA` | standard | French Canadian — backwards level-2 (accent) comparison. |
| `fy` | standard | Western Frisian. |
| `gl` | standard, search | Galician — imports Spanish/Catalan rules. |
| `gu` | standard | Gujarati script ordering. |
| `ha` | standard | Hausa — additional letters ɓ, ɗ, ƙ. |
| `haw` | standard | Hawaiian — ʻokina placement. |
| `he` | standard | Hebrew script ordering. |
| `hi` | standard | Hindi — Devanagari script ordering. |
| `hr` | standard, search | Croatian — č, ć, dž, đ, lj, nj, š, ž as separate letters. |
| `hsb` | standard | Upper Sorbian. |
| `hu` | standard | Hungarian — digraphs cs, dz, dzs, gy, ly, ny, sz, ty, zs; double consonant expansion (ccs→cs). |
| `hy` | standard | Armenian script ordering. |
| `ig` | standard | Igbo — additional letters ị, ọ, ụ, ñ, gb, gw, kp, kw, nw, ny, sh. |
| `is` | standard, search | Icelandic — Nordic letter ordering with ð, þ. |
| `ja` | standard, unihan, private-kana | Japanese — kana ordering with Kanji by radical/stroke. Unihan uses Han reading order. |
| `ka` | standard | Georgian script ordering. |
| `kk` | standard | Kazakh — Cyrillic ordering. |
| `kk-Arab` | standard | Kazakh (Arabic script). |
| `kl` | standard, search | Kalaallisut — Nordic letter ordering. |
| `km` | standard | Khmer script ordering. |
| `kn` | standard, traditional | Kannada script ordering. |
| `ko` | standard, search, unihan | Korean — Hangul jamo decomposition; unihan uses Han reading order. |
| `kok` | standard | Konkani — Devanagari ordering. |
| `ku` | standard | Kurdish. |
| `ky` | standard | Kyrgyz — Cyrillic ordering. |
| `lkt` | standard | Lakota. |
| `ln` | standard, phonetic | Lingala — phonetic variant available. |
| `lo` | standard | Lao script ordering. |
| `lt` | standard | Lithuanian — y between i and j. |
| `lv` | standard | Latvian — č, ģ, ķ, ļ, ņ, š, ž as separate letters. |
| `mk` | standard | Macedonian — Cyrillic ordering. |
| `ml` | standard | Malayalam script ordering. |
| `mn` | standard | Mongolian — Cyrillic ordering. |
| `mr` | standard | Marathi — Devanagari ordering. |
| `mt` | standard | Maltese — ċ, ġ, għ, ħ, ż; case-first:upper by default. |
| `my` | standard | Myanmar (Burmese) script ordering. |
| `ne` | standard | Nepali — Devanagari ordering. |
| `no` | standard, search | Norwegian — æ, ø, å after z; case-first:upper by default. |
| `nso` | standard | Northern Sotho. |
| `om` | standard | Oromo. |
| `or` | standard | Odia script ordering. |
| `pa` | standard | Punjabi — Gurmukhi script ordering. |
| `pl` | standard | Polish — ą, ć, ę, ł, ń, ó, ś, ź, ż as separate letters. |
| `ps` | standard | Pashto — Arabic script ordering. |
| `ro` | standard | Romanian — ă, â, î, ș, ț placement. |
| `ru` | standard | Russian — Cyrillic ordering. |
| `sa` | standard, traditional | Sanskrit — Devanagari ordering. |
| `se` | standard, search | Northern Sami. |
| `sgs` | standard | Samogitian. |
| `si` | standard, dictionary | Sinhala — dictionary variant available. |
| `sk` | standard, search | Slovak — č, ď, ĺ, ľ, ň, ô, ŕ, š, ť, ž, á, ä, é, í, ó, ú, ý. |
| `sl` | standard | Slovenian. |
| `smn` | standard, search | Inari Sami. |
| `sq` | standard | Albanian — ç, dh, ë, gj, ll, nj, rr, sh, th, xh, zh. |
| `sr` | standard | Serbian — Cyrillic ordering. |
| `sr-Latn` | standard, search | Serbian (Latin) — imports Croatian rules. |
| `ssy` | standard | Saho. |
| `sv` | standard, search, traditional | Swedish — å, ä, ö after z. |
| `ta` | standard | Tamil script ordering. |
| `te` | standard | Telugu script ordering. |
| `th` | standard | Thai script ordering. |
| `tk` | standard | Turkmen. |
| `tn` | standard | Tswana. |
| `to` | standard | Tongan. |
| `tr` | standard, search | Turkish — dotted/dotless i distinction; ç, ğ, ı, ö, ş, ü. |
| `ug` | standard | Uyghur — Arabic script ordering. |
| `uk` | standard | Ukrainian — Cyrillic ordering. |
| `und` | search | Root search rules — Arabic form equivalences, Korean jamo decomposition, Thai/Lao contraction suppression. |
| `ur` | standard | Urdu — Arabic script ordering. |
| `uz` | standard | Uzbek. |
| `vi` | standard, traditional | Vietnamese — extensive accent and tone ordering. |
| `vo` | standard | Volapük. |
| `wae` | standard | Walser. |
| `wo` | standard | Wolof. |
| `yi` | standard | Yiddish — Hebrew script ordering. |
| `yo` | standard | Yoruba — additional letters ẹ, ọ, ṣ, gb. |
| `zh` | pinyin, stroke, unihan, zhuyin, private-pinyin | Chinese — pinyin (pronunciation), stroke (stroke count), zhuyin (Bopomofo), unihan (radical-stroke). |

## Sort keys

For bulk sorting or database indexing, generate sort keys once and compare the raw binaries:

```elixir
iex> key_a = Localize.Collation.sort_key("café")
iex> key_b = Localize.Collation.sort_key("caff")
iex> key_a < key_b
true
```

Sort keys are binaries that preserve the collation ordering when compared with `<`, `>`, and `==`. They encode all comparison levels into a single binary, so comparison is a simple byte comparison with no need to re-apply collation rules.

## Performance notes

* **Collation tables** are loaded once into `:persistent_term` on first use. Subsequent calls have no file I/O overhead.

* **Locale tailoring overlays** are computed once per locale/type pair and cached. Overlay lookup is a hash map get (~575ns for 7,000+ entry CJK overlays).

* **Optional NIF** — when `LOCALIZE_NIF=true` is set at compile time, sort key generation uses a C NIF for significantly faster performance. See `Localize.Nif` for details.
