# Locale Validation Guide

This guide explains how to turn a locale identifier — a string, an atom, or a `Localize.LanguageTag` — into a validated, canonical form, and which of the several entry points (`Localize.validate_locale/1`, `Localize.LanguageTag.parse/1`, `Localize.LanguageTag.new/1`) you actually want.

## Overview

`Localize.validate_locale/1` is the one canonical path. Every Localize formatting function resolves its `:locale` option through it, and application code that accepts locale identifiers from users, HTTP headers, or configuration should do the same:

```elixir
iex> {:ok, tag} = Localize.validate_locale("en-US")
iex> tag.cldr_locale_id
:en
iex> tag.canonical_locale_id
"en-US"

iex> {:ok, tag} = Localize.validate_locale(:"fr-CA")
iex> tag.cldr_locale_id
:"fr-CA"
```

Validation performs, in one pass:

* **Parsing** — the identifier is parsed against the BCP 47 grammar, with POSIX-style underscores normalized to hyphens first (`"pt_BR"` is accepted as `"pt-BR"`).

* **Alias resolution** — deprecated subtags are replaced by their canonical successors per TR35: `"iw"` becomes `"he"`, `"sr-YU"` becomes `"sr-RS"`.

* **Likely-subtag resolution** — the `language`, `script`, and `territory` fields are populated with the maximized form, so downstream code can always read them.

* **`-u-` extension parsing** — Unicode extension keywords are validated and decoded into a `Localize.LanguageTag.U` struct on the tag's `:locale` field.

* **CLDR locale matching** — the tag is matched against the candidate locales (all ~657 CLDR locales, or your configured `:supported_locales`) to populate `:cldr_locale_id`, the key used for all data lookup.

* **Caching** — the result is cached in ETS, so repeated validation of the same identifier costs about a microsecond.

```elixir
iex> {:ok, tag} = Localize.validate_locale("iw")
iex> {tag.language, tag.canonical_locale_id, tag.cldr_locale_id}
{:he, "he", :he}

iex> {:ok, tag} = Localize.validate_locale("en")
iex> {tag.language, tag.script, tag.territory}
{:en, :Latn, :US}

iex> {:ok, tag} = Localize.validate_locale("pt_BR")
iex> {tag.canonical_locale_id, tag.cldr_locale_id}
{"pt-BR", :pt}
```

Note the last example: `canonical_locale_id` preserves the caller's request in canonical syntax (`"pt-BR"` stays `"pt-BR"`), while `cldr_locale_id` is the CLDR data locale that serves it (`:pt`, because Brazilian Portuguese is CLDR's base `pt`). Locale identity and data lookup key off `cldr_locale_id`; display and round-tripping key off `canonical_locale_id`.

### The three id fields

| Field | Content | Example for input `"iw-US"` |
|-------|---------|------------------------------|
| `:requested_locale_id` | The input, verbatim. | `"iw-US"` |
| `:canonical_locale_id` | Canonical syntax: aliases resolved, subtags ordered — neither maximized nor minimized. | `"he-US"` |
| `:cldr_locale_id` | The matched CLDR data locale, as an atom. | `:he` |

### Unmatchable languages resolve to root

When the language is valid but CLDR has no data for it, the tag resolves to the root locale `:und` rather than to a wrong language:

```elixir
iex> {:ok, tag} = Localize.validate_locale("tlh")
iex> {tag.canonical_locale_id, tag.cldr_locale_id}
{"tlh", :und}
```

A string that is not a well-formed BCP 47 tag, or whose subtags are not in the CLDR validity sets, returns an error:

```elixir
iex> {:error, error} = Localize.validate_locale("xyzzy")
iex> error.__struct__
Localize.InvalidLocaleError
```

## `-u-` extensions

BCP 47 `-u-` extension keywords — calendar, numbering system, hour cycle, collation, region override, and the rest — are decoded into a `Localize.LanguageTag.U` struct during validation. Formatting functions honour them automatically:

```elixir
iex> {:ok, tag} = Localize.validate_locale("th-u-nu-thai-ca-buddhist")
iex> {tag.locale.nu, tag.locale.ca}
{:thai, :buddhist}

iex> {:ok, tag} = Localize.validate_locale("en-u-hc-h23")
iex> tag.locale.hc
:h23
```

`Localize.LanguageTag.to_string/1` re-encodes the whole tag, extensions included, in canonical order:

```elixir
iex> {:ok, tag} = Localize.validate_locale("th-u-nu-thai-ca-buddhist")
iex> Localize.LanguageTag.to_string(tag)
"th-u-ca-buddhist-nu-thai"
```

### Standalone `-u-` strings

Some interchange formats carry the extension subtags without a full locale identifier. `Localize.LanguageTag.U.parse/1` parses such a string on its own, with or without the leading `u-` singleton, applying the same validation and canonicalization as `validate_locale/1`; `Localize.LanguageTag.U.encode/1` goes back to canonical BCP 47 key/value pairs:

```elixir
iex> {:ok, u} = Localize.LanguageTag.U.parse("ca-gregory-hc-h23")
iex> {u.ca, u.hc}
{:gregorian, :h23}

iex> {:ok, u} = Localize.LanguageTag.U.parse("u-nu-thai")
iex> u.nu
:thai

iex> {:ok, u} = Localize.LanguageTag.U.parse("ca-gregory-hc-h23")
iex> Localize.LanguageTag.U.encode(u)
[{"ca", "gregory"}, {"hc", "h23"}]
```

Note that decoding canonicalizes values (`"gregory"` decodes to `:gregorian`) and encoding restores the BCP 47 spelling.

## Which one do I want?

`Localize.LanguageTag` also exposes `parse/1` and `new/1`, which do progressively less than `validate_locale/1`:

| | `LanguageTag.parse/1` | `LanguageTag.new/1` | `Localize.validate_locale/1` |
|---|---|---|---|
| BCP 47 grammar parse | Yes | Yes | Yes |
| Subtag validity check | Yes | Yes | Yes |
| Alias resolution / canonicalization | Partial (subtag aliases) | Yes | Yes |
| Likely-subtag maximization | No | Yes | Yes |
| `-u-` keyword decoding into `LanguageTag.U` | No | Yes | Yes |
| `cldr_locale_id` resolution | No | Yes | Yes |
| Respects `:supported_locales` config | No | No | Yes |
| ETS result cache | No | No | Yes |
| Accepts atoms and `LanguageTag` structs | No (binary only) | No (binary only) | Yes |

```elixir
iex> {:ok, parsed} = Localize.LanguageTag.parse("en-US")
iex> {parsed.script, parsed.cldr_locale_id}
{nil, nil}

iex> {:ok, tag} = Localize.LanguageTag.new("zh-TW")
iex> {tag.language, tag.script, tag.territory, tag.cldr_locale_id}
{:zh, :Hant, :TW, :"zh-Hant"}
```

In short: use `validate_locale/1` unless you have a specific reason not to. `parse/1` is the raw syntactic layer, useful when you need to inspect exactly what the caller wrote before any resolution. `new/1` is a fully resolved tag without the supported-locales restriction or the cache — useful in build tooling that must see all CLDR locales regardless of application configuration.

## Supported vs available vs known

Localize uses a consistent vocabulary for locale (and other) inventories:

* **known** — the locale-independent CLDR universe, e.g. `Localize.all_locale_ids/0` (~657 locales, or filtered by coverage level with `Localize.all_locale_ids(:modern)`).

* **available** — present in the CLDR release: `Localize.available_locale_id?/1` answers whether an identifier is a CLDR locale id.

* **supported** — what *your application* is configured to serve: `Localize.supported_locales/0` reflects `config :localize, supported_locales: [...]`, falling back to all CLDR locales when unset. When configured, `validate_locale/1` matches only against this list.

```elixir
iex> Localize.available_locale_id?(:en)
true

iex> Localize.available_locale_id?("tlh")
false
```

Restricting `:supported_locales` is the recommended production setup — it bounds locale matching to what you can actually serve and makes `validate_locale/1` resolve near-miss identifiers to your supported set. See the [README configuration section](https://hexdocs.pm/localize/readme.html#configuration) for the accepted entry forms (atoms, wildcards, coverage levels, Gettext backends).

## Locale matching

`Localize.LanguageTag.best_match/3` implements the CLDR language matching algorithm directly, for cases like negotiating an `Accept-Language` header against the locales your application ships:

```elixir
iex> Localize.LanguageTag.best_match("en-AU", ["en", "en-GB", "fr"])
{:ok, "en-GB", 3}

iex> Localize.LanguageTag.best_match("pt-PT", ["pt-BR", "es", "fr"])
{:ok, "pt-BR", 5}
```

The score is the CLDR match distance — `0` is exact, small values are regional variants, and `80`+ means a different language. With the default threshold the algorithm always returns some supported locale (a distant match beats no match, per the CLDR specification); pass an explicit threshold for strict matching:

```elixir
iex> Localize.LanguageTag.best_match("de", ["en", "de", "fr"], 0)
{:ok, "de", 0}

iex> {:error, _} = Localize.LanguageTag.best_match("ja", ["en", "fr"], 20)
```

`Localize.LanguageTag.match_distance/2` returns the raw distance between two locales:

```elixir
iex> Localize.LanguageTag.match_distance("en-AU", "en-GB")
3

iex> Localize.LanguageTag.match_distance("en", "fr")
84
```
