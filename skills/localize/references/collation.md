# Collation — sorting and comparing text

Most common calls:

| Task | Call |
|------|------|
| Sort user-visible strings | `Localize.Collation.sort(strings, locale: :de)` |
| Compare two strings | `Localize.Collation.compare(a, b)` → `:lt` / `:eq` / `:gt` |
| Case-insensitive equality | `Localize.Collation.compare(a, b, ignore_case: true)` |
| Natural number ordering | `Localize.Collation.sort(names, numeric: true)` |
| DB-persistable key | `Localize.Collation.sort_key(string)` → binary |

Implements the Unicode Collation Algorithm with CLDR locale tailoring. Use it wherever people see the ordering; `Enum.sort/1` is codepoint order, which puts all uppercase before all lowercase and all accented letters after "z":

```elixir
Enum.sort(["résumé", "resume", "Résumé", "RESUME"])                     # wrong for humans
#=> ["RESUME", "Résumé", "resume", "résumé"]
Localize.Collation.sort(["résumé", "resume", "Résumé", "RESUME"])
#=> ["resume", "RESUME", "résumé", "Résumé"]
```

## Strength — how much difference matters

Comparison is multi-level; `:strength` sets how deep it goes. Each level down ignores more:

| Strength | Compares | Ignores |
|----------|----------|---------|
| `:primary` | base letters only | accents, case |
| `:secondary` | + accents | case |
| `:tertiary` (default) | + case | punctuation weight nuances |
| `:quaternary` | + variable characters (with `:shifted`) | — |
| `:identical` | everything incl. codepoints | nothing |

```elixir
Localize.Collation.compare("résumé", "resume", strength: :primary)       # accent- and case-blind
#=> :eq
Localize.Collation.compare("a", "A", strength: :secondary)               # case-blind
#=> :eq
Localize.Collation.compare("a", "A")                                     # :tertiary sees case
#=> :lt
```

Shorthand options map onto these and read better at call sites: `ignore_accents: true` (→ `:primary`), `ignore_case: true` / `casing: :insensitive` (→ `:secondary`), `ignore_punctuation: true` (→ `:tertiary` + `alternate: :shifted`).

```elixir
Localize.Collation.compare("cafe", "café", ignore_accents: true)
#=> :eq
Localize.Collation.compare("a", "A", ignore_case: true)
#=> :eq
```

## Punctuation and whitespace — alternate: :shifted

`alternate: :shifted` demotes "variable" characters (spaces, hyphens, punctuation) so they only break ties at the quaternary level — "blackbird", "black-bird", and "black bird" all match through tertiary:

```elixir
Localize.Collation.compare("blackbird", "black-bird", alternate: :shifted)
#=> :eq
Localize.Collation.compare("blackbird", "black-bird", alternate: :shifted, strength: :quaternary)
#=> :gt
Localize.Collation.sort(["black bird", "blackbird", "black-bird"], ignore_punctuation: true)
#=> ["black bird", "blackbird", "black-bird"]
```

`:max_variable` widens what counts as variable: `:space` < `:punct` (default) < `:symbol` < `:currency`. With `:currency`, even `$` is ignorable:

```elixir
Localize.Collation.compare("a$b", "ab", alternate: :shifted)              # $ is a symbol, not punct
#=> :lt
Localize.Collation.compare("a$b", "ab", alternate: :shifted, max_variable: :currency)
#=> :eq
```

## Case ordering

`case_first: :upper | :lower` decides which case wins ties (some locales default to upper — Danish, Norwegian, Maltese). `case_level: true` adds a case level between secondary and tertiary, enabling case-sensitive but accent-insensitive matching.

```elixir
Localize.Collation.sort(["apple", "Apple", "APPLE"], case_first: :upper)
#=> ["APPLE", "Apple", "apple"]
Localize.Collation.sort(["apple", "Apple"], locale: :da)                  # Danish default is upper-first
#=> ["Apple", "apple"]
```

## Numeric sorting

`numeric: true` compares embedded digit runs by value — the fix for "file10" sorting before "file2". Works for digits in any script:

```elixir
Localize.Collation.sort(["file10", "file2", "file1"])
#=> ["file1", "file10", "file2"]
Localize.Collation.sort(["file10", "file2", "file1"], numeric: true)
#=> ["file1", "file2", "file10"]
```

## Locale tailoring

Locales reorder letters, promote digraphs to letters, and expand characters. The tailoring applies automatically from `:locale`:

```elixir
Localize.Collation.sort(["ñ", "n", "o"], locale: :es)                     # ñ is a letter between n and o
#=> ["n", "ñ", "o"]
Localize.Collation.sort(["č", "c", "d"], locale: :hr)
#=> ["c", "č", "d"]
Localize.Collation.sort(["ö", "z", "a"], locale: :sv)                     # Swedish: ö after z
#=> ["a", "z", "ö"]
Localize.Collation.sort(["ö", "z", "a"], locale: :en)                     # English: ö with o
#=> ["a", "ö", "z"]
```

`:type` selects an alternative tailoring where the locale has one — German phonebook expands ä→ae, Spanish traditional treats "ch" as a letter after "c":

```elixir
Localize.Collation.sort(["Ärger", "Anger", "Azur"], locale: :de)          # standard: Ä near A
#=> ["Anger", "Ärger", "Azur"]
Localize.Collation.sort(["Ärger", "Anger", "Azur"], locale: :de, type: :phonebook)
#=> ["Ärger", "Anger", "Azur"]
Localize.Collation.sort(["cuenta", "charla", "dama"], locale: :es)
#=> ["charla", "cuenta", "dama"]
Localize.Collation.sort(["cuenta", "charla", "dama"], locale: :es, type: :traditional)
#=> ["cuenta", "charla", "dama"]
```

Chinese offers several orderings — pinyin (pronunciation), stroke (stroke count), zhuyin (Bopomofo), unihan:

```elixir
Localize.Collation.sort(["中", "北", "上"], locale: "zh-u-co-pinyin")      # běi, shàng, zhōng
#=> ["北", "上", "中"]
Localize.Collation.sort(["中", "北", "上"], locale: "zh-u-co-stroke")
#=> ["上", "中", "北"]
```

`type: :search` applies loose-matching tailoring (Arabic presentation-form equivalences, Korean jamo decomposition) — pair with `strength: :primary` for user-facing search matching:

```elixir
Localize.Collation.compare("cafe", "café", type: :search, strength: :primary)
#=> :eq
```

## Options in the locale identifier (-u-)

Every option has a BCP 47 key, so a user's saved locale string can carry their collation preferences: `co` → `:type` (`phonebk`, `pinyin`, `stroke`, `zhuyin`, `trad`, `search`), `ks` → `:strength` (`level1`..`level4`, `identic`), `kn` → `:numeric`, `kf` → `:case_first`, `ka` → `:alternate`, `kb` → `:backwards`, `kv` → `:max_variable`, `kr` → `:reorder`. Explicit keyword options beat locale-encoded ones.

```elixir
Localize.Collation.sort(["Ärger", "Anger", "Azur"], locale: "de-u-co-phonebk")
#=> ["Ärger", "Anger", "Azur"]
Localize.Collation.compare("a", "A", locale: "en-u-ks-level2")
#=> :eq
Localize.Collation.sort(["file10", "file2"], locale: "en-u-kn-true")
#=> ["file2", "file10"]
Localize.Collation.sort(["apple", "Apple", "APPLE"], locale: "en-u-kf-upper")
#=> ["APPLE", "Apple", "apple"]
```

## Backwards accents (French)

`backwards: true` (or `-u-kb-true`) compares accents from the end of the string — the traditional French Canadian dictionary rule. Note it must be requested explicitly; the `fr-CA` locale alone does not currently enable it:

```elixir
Localize.Collation.sort(["côte", "coté", "cote", "côté"])
#=> ["cote", "coté", "côte", "côté"]
Localize.Collation.sort(["côte", "coté", "cote", "côté"], backwards: true)
#=> ["cote", "côte", "coté", "côté"]
```

## Script reordering

`:reorder` moves whole script groups ahead of the default order — e.g. Cyrillic before Latin for a Russian-first list:

```elixir
Localize.Collation.sort(["б", "b"])                                       # default: Latin first
#=> ["b", "б"]
Localize.Collation.sort(["б", "b"], reorder: [:Cyrl, :Latn])
#=> ["б", "b"]
```

## Sort keys for databases

`sort_key/2` encodes all comparison levels into one binary whose plain byte order equals the collation order. Compute once per row, store in a column, and let the database `ORDER BY` it — the DB never needs to know about collation:

```elixir
Localize.Collation.sort_key("café") < Localize.Collation.sort_key("caff")
#=> true
```

Keys are only comparable when generated with the same options and library version; regenerate the column if either changes. Use the same options for the key as the app uses for in-memory `sort/2` or the two orderings will disagree.

## Error behavior

Collation is lenient, unlike the formatters: there are no `{:ok, _}`/`{:error, _}` tuples. An unknown locale or invalid option value falls back to the default (DUCET / option default) rather than raising or erroring. Validate locales upstream with `Localize.validate_locale/1` if silent fallback is not acceptable.

```elixir
Localize.Collation.compare("a", "b", locale: "xx-INVALID!")               # silently falls back to root
#=> :lt
```

## Performance

Collation tables load into `:persistent_term` on first use; per-locale tailorings are computed once and cached. When the optional NIF is compiled in (`LOCALIZE_NIF=true`), sort-key generation uses ICU4C automatically — no code change, same API. For sorting large lists repeatedly, prefer stored `sort_key/2` binaries over re-sorting strings.
