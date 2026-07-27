# Display Names Guide

This guide explains how to produce localized, human-readable names for territories, languages, scripts, currencies, calendars, territory subdivisions, and whole locales — the CLDR display name data surfaced by the `display_name/2` family of functions.

## Overview

Every display-name function follows the same shape: pass the code, get `{:ok, name}` back, localized into the `:locale` option (default `:en`):

```elixir
iex> Localize.Territory.display_name(:US)
{:ok, "United States"}

iex> Localize.Territory.display_name(:US, locale: :de)
{:ok, "Vereinigte Staaten"}

iex> Localize.Language.display_name("fr", locale: :de)
{:ok, "Französisch"}

iex> Localize.Script.display_name(:Cyrl, locale: :fr)
{:ok, "cyrillique"}

iex> Localize.Currency.display_name(:USD, locale: :de)
{:ok, "US-Dollar"}
```

Each module also provides a `display_name!/2` variant that raises on error, and per-locale data functions (the `*_for` family) that return the entire name inventory for a locale in one call.

## Territories

`Localize.Territory.display_name/2` names territory codes — ISO 3166 codes, CLDR containment codes like `:EU`, and the world code `:"001"`:

```elixir
iex> Localize.Territory.display_name(:GB)
{:ok, "United Kingdom"}

iex> Localize.Territory.display_name(:EU)
{:ok, "European Union"}

iex> Localize.Territory.display_name(:"001")
{:ok, "world"}

iex> Localize.Territory.display_name("US", locale: :fr)
{:ok, "États-Unis"}
```

The `:style` option selects among the CLDR name alternatives — `:standard` (the default), `:short`, and `:variant`:

```elixir
iex> Localize.Territory.display_name(:GB, style: :short)
{:ok, "UK"}

iex> Localize.Territory.display_name(:CZ)
{:ok, "Czechia"}

iex> Localize.Territory.display_name(:CZ, style: :variant)
{:ok, "Czech Republic"}
```

Not every territory has every style — CLDR only records alternatives where they exist, and a missing style returns an error rather than silently falling back:

```elixir
iex> {:error, error} = Localize.Territory.display_name(:US, style: :variant)
iex> error.__struct__
Localize.UnknownStyleError
```

`Localize.Territory.known_styles/0` lists the style vocabulary and `Localize.Territory.known_territories/0` the full territory universe.

## Languages

`Localize.Language.display_name/2` follows the TR35 display-name algorithm, which **canonicalizes but does not maximize** the input. A bare language keeps its own name — likely subtags are not added, so `"en"` does not become "American English" — while an explicitly supplied region or script resolves to the region-specific CLDR name:

```elixir
iex> Localize.Language.display_name("en")
{:ok, "English"}

iex> Localize.Language.display_name("en-US")
{:ok, "American English"}

iex> Localize.Language.display_name("en-GB")
{:ok, "British English"}

iex> Localize.Language.display_name("pt-BR")
{:ok, "Brazilian Portuguese"}
```

The `:style` option is one of `:standard` (default), `:short`, `:long`, `:menu`, or `:variant`; as with territories, alternatives exist only where CLDR records them:

```elixir
iex> Localize.Language.display_name("en-GB", style: :short)
{:ok, "UK English"}
```

## Scripts

`Localize.Script.display_name/2` names ISO 15924 script codes, with styles `:standard` (default), `:short`, `:stand_alone`, and `:variant`:

```elixir
iex> Localize.Script.display_name(:Latn)
{:ok, "Latin"}

iex> Localize.Script.display_name(:Hant)
{:ok, "Traditional"}

iex> Localize.Script.display_name(:Hant, style: :stand_alone)
{:ok, "Traditional Han"}

iex> Localize.Script.display_name(:Arab, style: :variant)
{:ok, "Perso-Arabic"}
```

The `:stand_alone` style exists because some script names are contextual: "Traditional" reads fine inside "Chinese (Traditional)" but needs "Traditional Han" when it stands on its own.

## Currencies

`Localize.Currency.display_name/2` returns the localized currency name, and `Localize.Currency.pluralize/3` selects the plural-category-appropriate form for a count:

```elixir
iex> Localize.Currency.display_name(:USD)
{:ok, "US Dollar"}

iex> Localize.Currency.display_name(:EUR, locale: :ja)
{:ok, "ユーロ"}

iex> Localize.Currency.pluralize(1, :USD)
{:ok, "US dollar"}

iex> Localize.Currency.pluralize(3, :USD)
{:ok, "US dollars"}
```

## Calendars and calendar fields

`Localize.Calendar.display_name/3` takes a *type* and a *value*, covering both calendar systems and the date/time field and element names:

```elixir
iex> Localize.Calendar.display_name(:calendar, :gregorian)
{:ok, "Gregorian Calendar"}

iex> Localize.Calendar.display_name(:calendar, :japanese, locale: :de)
{:ok, "Japanischer Kalender"}

iex> Localize.Calendar.display_name(:month, 7)
{:ok, "July"}

iex> Localize.Calendar.display_name(:month, 7, locale: :fr)
{:ok, "juillet"}

iex> Localize.Calendar.display_name(:day_of_week, 1)
{:ok, "Monday"}

iex> Localize.Calendar.display_name(:quarter, 2)
{:ok, "2nd quarter"}

iex> Localize.Calendar.display_name(:era, 1)
{:ok, "Anno Domini"}

iex> Localize.Calendar.display_name(:date_time_field, :year, locale: :fr)
{:ok, "année"}
```

## Territory subdivisions

`Localize.Territory.Subdivision.display_name/2` names ISO 3166-2 subdivisions using their CLDR subdivision ids:

```elixir
iex> Localize.Territory.Subdivision.display_name("usca")
{:ok, "California"}

iex> Localize.Territory.Subdivision.display_name("usca", locale: :fr)
{:ok, "Californie"}

iex> Localize.Territory.Subdivision.display_name("gbeng")
{:ok, "England"}
```

## Locale display names

`Localize.Locale.LocaleDisplay.display_name/2` (also reachable as `Localize.Locale.display_name/2`) implements the full TR35 locale display name algorithm, composing the language name with parenthesized qualifiers for script, territory, variants, and `-u-` extensions:

```elixir
iex> Localize.Locale.LocaleDisplay.display_name("en-US")
{:ok, "English (United States)"}

iex> Localize.Locale.LocaleDisplay.display_name("zh-Hant")
{:ok, "Chinese (Traditional)"}

iex> Localize.Locale.LocaleDisplay.display_name("en-US", locale: :fr)
{:ok, "anglais (États-Unis)"}

iex> Localize.Locale.LocaleDisplay.display_name("en-US-u-ca-buddhist")
{:ok, "English (United States, Buddhist Calendar)"}
```

The `:language_display` option chooses between the two TR35 modes. `:standard` (the default) composes language plus qualifiers; `:dialect` prefers the fused regional name where CLDR has one:

```elixir
iex> Localize.Locale.LocaleDisplay.display_name("en-US", language_display: :dialect)
{:ok, "American English"}

iex> Localize.Locale.LocaleDisplay.display_name("nl-BE", language_display: :dialect)
{:ok, "Flemish"}
```

### Canonical, not maximized

Like `Localize.Language.display_name/2`, the locale display algorithm works from the **canonical** form of the request, not the maximized one. Validation resolves `"en"` to the full tag `en-Latn-US` internally, but the display name reflects only what the caller wrote:

```elixir
iex> Localize.Locale.LocaleDisplay.display_name("en")
{:ok, "English"}

iex> Localize.Locale.LocaleDisplay.display_name("en-US")
{:ok, "English (United States)"}
```

This is the TR35-specified behavior: display names answer "what did the user ask for?", so likely subtags never leak into the output. A string and an equivalent validated `Localize.LanguageTag` render identically.

## Per-locale name inventories

Each domain module pairs `display_name/2` with `*_for` functions that return the whole localized inventory at once — useful for building pickers and select lists. The naming rule is uniform across Localize: `known_*` is the locale-independent CLDR universe, `supported_*` reflects your configuration, and `*_for` is data localized into a display locale.

```elixir
iex> {:ok, names} = Localize.Language.language_names_for(locale: :fr)
iex> names["en"]
%{standard: "anglais"}

iex> {:ok, names} = Localize.Script.script_names_for(locale: :en)
iex> names[:Hant]
%{stand_alone: "Traditional Han", standard: "Traditional"}

iex> {:ok, names} = Localize.Territory.Subdivision.subdivision_names_for(locale: :en)
iex> names[:usca]
"California"
```

The name maps carry all recorded style alternatives for each code, which is why the values are style-keyed maps. The companion functions `Localize.Language.languages_for/1`, `Localize.Script.scripts_for/1`, and `Localize.Territory.Subdivision.subdivisions_for/1` return just the codes that have names in the given locale.

## Style option summary

| Module | `:style` values | Default |
|--------|-----------------|---------|
| `Localize.Territory` | `:standard`, `:short`, `:variant` | `:standard` |
| `Localize.Language` | `:standard`, `:short`, `:long`, `:menu`, `:variant` | `:standard` |
| `Localize.Script` | `:standard`, `:short`, `:stand_alone`, `:variant` | `:standard` |
| `Localize.Locale.LocaleDisplay` | `:language_display` option: `:standard`, `:dialect` | `:standard` |

Styles are name *alternatives* recorded by CLDR, not widths that always exist — requesting a style with no data for the given code returns an error.
