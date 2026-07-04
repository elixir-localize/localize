# List Formatting Guide

This guide explains how to use `Localize.List` to join lists of items into locale-aware strings using CLDR list patterns.

## Overview

`Localize.List.to_string/2` is the primary function. It joins a list of elements with the connectors a locale actually uses — English separates with commas and inserts "and" before the last element, French uses "et" with no Oxford comma, Japanese uses the ideographic comma throughout:

```elixir
iex> Localize.List.to_string(["apple", "banana", "cherry"])
{:ok, "apple, banana, and cherry"}

iex> Localize.List.to_string(["pommes", "poires", "cerises"], locale: :fr)
{:ok, "pommes, poires et cerises"}

iex> Localize.List.to_string(["Berlin", "Hamburg", "Munich"], locale: :de)
{:ok, "Berlin, Hamburg und Munich"}

iex> Localize.List.to_string(["東京", "大阪", "京都"], locale: :ja)
{:ok, "東京、大阪、京都"}
```

Lists of zero, one, and two elements are handled with the appropriate pattern:

```elixir
iex> Localize.List.to_string(["tea", "coffee"], locale: :en)
{:ok, "tea and coffee"}

iex> Localize.List.to_string(["tea"], locale: :en)
{:ok, "tea"}

iex> Localize.List.to_string([], locale: :en)
{:ok, ""}
```

## List styles

The `:list_style` option selects which CLDR list pattern joins the elements. There are three base styles, each in three widths (regular, `_short`, `_narrow`):

* `:standard` — conjunction ("and") lists. The default.

* `:or` — disjunction ("or") lists.

* `:unit` — measurement lists with no final conjunction, used for composed quantities like "3 feet, 7 inches".

```elixir
iex> Localize.List.to_string(["red", "green", "blue"], locale: :en, list_style: :or)
{:ok, "red, green, or blue"}

iex> Localize.List.to_string(["rouge", "vert", "bleu"], locale: :fr, list_style: :or)
{:ok, "rouge, vert ou bleu"}

iex> Localize.List.to_string(["3 feet", "7 inches"], locale: :en, list_style: :unit)
{:ok, "3 feet, 7 inches"}

iex> Localize.List.to_string(["a", "b", "c"], locale: :en, list_style: :standard_short)
{:ok, "a, b, & c"}

iex> Localize.List.to_string(["a", "b", "c"], locale: :en, list_style: :standard_narrow)
{:ok, "a, b, c"}

iex> Localize.List.to_string(["3′", "7″"], locale: :en, list_style: :unit_narrow)
{:ok, "3′ 7″"}
```

The full set of style names is fixed across CLDR:

```elixir
iex> Localize.List.known_list_styles()
[:or, :or_narrow, :or_short, :standard, :standard_narrow, :standard_short, :unit, :unit_narrow, :unit_short]
```

`known_list_styles/0` is the locale-independent universe; `list_styles_for/1` returns the styles a specific locale's data actually provides (for CLDR locales these coincide):

```elixir
iex> Localize.List.list_styles_for(:en)
{:ok, [:or, :or_narrow, :or_short, :standard, :standard_narrow, :standard_short, :unit, :unit_narrow, :unit_short]}
```

An unknown style returns an error rather than silently falling back:

```elixir
iex> {:error, error} = Localize.List.to_string(["a", "b"], list_style: :fancy)
iex> error.value
:fancy
```

## Why the option is `:list_style`, not `:style`

`Localize.List` formats each non-string element through `Localize.to_string/2`, which dispatches on the `Localize.Chars` protocol — numbers, dates, units, currencies, and any type with a `Localize.Chars` implementation are formatted with the same locale as the outer list call. Only the options that belong to the list itself (`:list_style` and `:treat_middle_as_end`) are consumed by `Localize.List`; everything else passes through to the per-element formatters. The namespaced name keeps the list's style selection from colliding with a `:style` or `:format` option intended for the elements.

That pass-through is what makes one option list format the whole structure:

```elixir
iex> Localize.List.to_string([1234, 5678], locale: :de)
{:ok, "1.234 und 5.678"}

iex> Localize.List.to_string([1234.56, 5678.90], locale: :en, currency: :USD)
{:ok, "$1,234.56 and $5,678.90"}

iex> Localize.List.to_string([~D[2025-07-10], ~D[2025-08-15]], locale: :en, format: :long)
{:ok, "July 10, 2025 and August 15, 2025"}
```

Here `:currency` and `:format` mean nothing to the list layer — they are forwarded to `Localize.Number.to_string/2` and `Localize.Date.to_string/2` respectively, while `:locale` is shared by both layers. Strings pass through unchanged; types with no `Localize.Chars` implementation fall through to `Kernel.to_string/1`.

## Interspersing without flattening

`Localize.List.intersperse/2` returns the list with separator strings inserted between the original elements instead of producing a single binary. This is the right tool when the elements must survive intact — building Phoenix safe HTML, iodata, or any structured output:

```elixir
iex> Localize.List.intersperse(["a", "b", "c"], locale: :en)
{:ok, ["a", ", ", "b", ", and ", "c"]}

iex> Localize.List.intersperse([1, 2], locale: :en)
{:ok, [1, " and ", 2]}

iex> Localize.List.intersperse(["a", "b", "c"], locale: :en, list_style: :unit_narrow)
{:ok, ["a", " ", "b", " ", "c"]}
```

Note that `intersperse/2` performs no element formatting — the original terms come back untouched between the locale's separator strings. `to_string/2` is implemented as `intersperse/2` followed by per-element formatting and concatenation.

## Custom patterns

A CLDR list pattern has four components: `:two` (exactly two elements), `:start` (first join), `:middle` (interior joins), and `:end` (final join). `Localize.List.Pattern.new/1` builds a custom pattern from `{0}`/`{1}` template strings, and the resulting struct can be passed directly as the `:list_style`:

```elixir
iex> {:ok, pattern} = Localize.List.Pattern.new(
...>   two: "{0} + {1}",
...>   start: "{0} | {1}",
...>   middle: "{0} | {1}",
...>   end: "{0} + {1}"
...> )
iex> Localize.List.to_string(["a", "b"], list_style: pattern)
{:ok, "a + b"}
iex> Localize.List.to_string(["a", "b", "c", "d"], list_style: pattern)
{:ok, "a | b | c + d"}
```

`Localize.List.list_patterns_for/1` returns a locale's full pattern map as `Localize.List.Pattern` structs, which is useful as a starting point for tweaking a single component of a stock style.

## Options reference

All options accepted by `Localize.List.to_string/2` and `Localize.List.intersperse/2`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:locale` | atom, string, or `LanguageTag` | `Localize.get_locale()` | Locale whose list patterns are used, and forwarded to per-element formatters. |
| `:list_style` | atom or `Localize.List.Pattern` | `:standard` | One of `known_list_styles/0` or a custom pattern struct. |
| `:treat_middle_as_end` | boolean | `false` | When `true`, the `:middle` pattern is used for the final join instead of the `:end` pattern, producing "a, b, c" instead of "a, b, and c" in English. |

All other options are forwarded unmodified to the per-element formatters via `Localize.to_string/2`.
