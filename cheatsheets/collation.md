# Collation Cheatsheet

## Basic usage

```elixir
Localize.Collation.sort(["banana", "apple", "Cherry"])
#=> ["apple", "banana", "Cherry"]

Localize.Collation.compare("a", "b")
#=> :lt
```

## Why not `Enum.sort/1`?

```elixir
# Codepoint sorting — wrong for users
Enum.sort(["résumé", "resume", "Résumé", "RESUME"])
#=> ["RESUME", "Résumé", "resume", "résumé"]

# UCA sorting — correct
Localize.Collation.sort(["résumé", "resume", "Résumé", "RESUME"])
#=> ["resume", "RESUME", "résumé", "Résumé"]
```

## Strength levels

Strength controls how many comparison levels are used. Each level adds more distinction.

### Input: `["résumé", "resume", "Résumé", "RESUME", "café", "Cafe", "caff"]`

| Strength | Result | Ignores |
|---|---|---|
| `:tertiary` (default) | `["Cafe", "café", "caff", "resume", "RESUME", "résumé", "Résumé"]` | — |
| `:secondary` | `["Cafe", "café", "caff", "resume", "RESUME", "résumé", "Résumé"]` | Case |
| `:primary` | `["café", "Cafe", "caff", "résumé", "resume", "Résumé", "RESUME"]` | Case + accents |

```elixir
Localize.Collation.sort(words, strength: :primary)     # ignore case and accents
Localize.Collation.sort(words, strength: :secondary)    # ignore case only
Localize.Collation.sort(words, strength: :tertiary)     # default — full comparison
```

### Shorthand options

```elixir
Localize.Collation.compare("cafe", "café", ignore_accents: true)    #=> :eq
Localize.Collation.compare("a", "A", ignore_case: true)             #=> :eq
Localize.Collation.compare("a", "A", casing: :insensitive)          #=> :eq
```

## Case ordering

```elixir
# Uppercase first
Localize.Collation.sort(["apple", "Apple", "APPLE"], case_first: :upper)
#=> ["APPLE", "Apple", "apple"]

# Lowercase first (default for most locales)
Localize.Collation.sort(["apple", "Apple", "APPLE"], case_first: :lower)
#=> ["apple", "Apple", "APPLE"]
```

## Locale-specific tailoring

### German: standard vs phonebook

```elixir
# Standard: Ä sorts as a variant of A
Localize.Collation.sort(["Ärger", "Anger", "Azur"], locale: "de")
#=> ["Anger", "Ärger", "Azur"]

# Phonebook: Ä expands to AE, sorts between AD and AF
Localize.Collation.sort(["Ärger", "Anger", "Azur"], locale: "de", type: :phonebook)
#=> ["Ärger", "Anger", "Azur"]
```

### Swedish: Ä sorts after Z

```elixir
Localize.Collation.sort(["Ärger", "Anger", "Azur"], locale: "sv")
#=> ["Anger", "Azur", "Ärger"]
```

### Croatian: č is a separate letter between c and d

```elixir
Localize.Collation.sort(["č", "c", "d"], locale: "hr")
#=> ["c", "č", "d"]
```

### Spanish: ñ sorts between n and o

```elixir
Localize.Collation.sort(["ñ", "n", "o"], locale: "es")
#=> ["n", "ñ", "o"]
```

### French Canadian: backwards accent comparison

```elixir
Localize.Collation.sort(["côte", "coté", "cote", "côté"], locale: "fr-CA")
#=> ["cote", "côte", "coté", "côté"]
```

### Danish: uppercase first by default

```elixir
Localize.Collation.sort(["apple", "Apple"], locale: "da")
#=> ["Apple", "apple"]
```

## Numeric sorting

```elixir
# Without numeric — "10" < "2" by codepoint
Localize.Collation.sort(["file10", "file2", "file1"])
#=> ["file1", "file10", "file2"]

# With numeric — 2 < 10
Localize.Collation.sort(["file10", "file2", "file1"], numeric: true)
#=> ["file1", "file2", "file10"]
```

## Ignoring punctuation (shifted)

```elixir
Localize.Collation.sort(["black bird", "blackbird", "black-bird"], alternate: :shifted)
#=> ["black bird", "blackbird", "black-bird"]
```

## BCP 47 locale strings with embedded options

```elixir
# German phonebook via locale string
Localize.Collation.sort(["Ärger", "Anger", "Azur"], locale: "de-u-co-phonebk")
#=> ["Ärger", "Anger", "Azur"]

# Case-insensitive via locale string
Localize.Collation.compare("a", "A", locale: "en-u-ks-level2")
#=> :eq

# Numeric via locale string
Localize.Collation.sort(["file10", "file2", "file1"], locale: "en-u-kn-true")
#=> ["file1", "file2", "file10"]
```

## Sort keys (for database indexing)

```elixir
key = Localize.Collation.sort_key("café")
# Binary that preserves collation order when compared with <, >, ==
```

## Options reference

| Option | Values | Default | Description |
|---|---|---|---|
| `:locale` | locale atom or string | `Localize.get_locale()` | Locale for tailoring |
| `:type` | `:standard`, `:search`, `:phonebook`, etc. | `:standard` | Collation type |
| `:strength` | `:primary`, `:secondary`, `:tertiary`, `:quaternary`, `:identical` | `:tertiary` | Comparison depth |
| `:alternate` | `:non_ignorable`, `:shifted` | `:non_ignorable` | Punctuation handling |
| `:case_first` | `:upper`, `:lower`, `false` | `false` | Case sort order |
| `:numeric` | `true`, `false` | `false` | Numeric-aware sorting |
| `:backwards` | `true`, `false` | `false` | Reverse accent comparison |
| `:case_level` | `true`, `false` | `false` | Extra case-comparison level |

### Shorthand options

| Shorthand | Equivalent |
|---|---|
| `ignore_accents: true` | `strength: :primary` |
| `ignore_case: true` | `strength: :secondary` |
| `ignore_punctuation: true` | `strength: :tertiary, alternate: :shifted` |
| `casing: :insensitive` | `strength: :secondary` |
