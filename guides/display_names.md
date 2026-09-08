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

The `:prefer` option selects among the CLDR name alternatives — `:standard` (the default), `:short`, and `:variant`. `:style` is accepted as an older spelling of the same option:

```elixir
iex> Localize.Territory.display_name(:GB, prefer: :short)
{:ok, "UK"}

iex> Localize.Territory.display_name(:CZ)
{:ok, "Czechia"}

iex> Localize.Territory.display_name(:CZ, prefer: :variant)
{:ok, "Czech Republic"}
```

Not every territory has every alternative — CLDR only records them where they exist. `Localize.Territory` reports a missing one rather than silently substituting the standard name:

```elixir
iex> {:error, error} = Localize.Territory.display_name(:US, prefer: :variant)
iex> error.__struct__
Localize.UnknownStyleError
```

This is territory-specific. `Localize.Language` and `Localize.Script` fall back to `:standard` instead, so `Localize.Language.display_name("fr", prefer: :variant)` returns `{:ok, "French"}` rather than an error.

`Localize.Territory.known_styles/0` lists the vocabulary and `Localize.Territory.known_territories/0` the full territory universe.

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

The `:prefer` option is one of `:standard` (default), `:short`, `:long`, `:menu`, or `:variant`. Alternatives exist only where CLDR records them, and an absent one falls back to `:standard`:

```elixir
iex> Localize.Language.display_name("en-GB", prefer: :short)
{:ok, "UK English"}
```

## Scripts

`Localize.Script.display_name/2` names ISO 15924 script codes, with `:prefer` values `:standard` (default), `:short`, `:stand_alone`, and `:variant`. As with languages, an absent alternative falls back to `:standard`:

```elixir
iex> Localize.Script.display_name(:Latn)
{:ok, "Latin"}

iex> Localize.Script.display_name(:Hant)
{:ok, "Traditional"}

iex> Localize.Script.display_name(:Hant, prefer: :stand_alone)
{:ok, "Traditional Han"}

iex> Localize.Script.display_name(:Arab, prefer: :variant)
{:ok, "Perso-Arabic"}
```

The `:stand_alone` alternative exists because some script names are contextual: "Traditional" reads fine inside "Chinese (Traditional)" but needs "Traditional Han" when it stands on its own.

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

### Naming the keys themselves

A `-u-` extension renders as "American English (Buddhist Calendar)" because the whole identifier is being named. When you are building a menu rather than naming a locale, you want the two halves separately — the key as the heading, its values as the choices:

```elixir
iex> Localize.Locale.LocaleDisplay.key_name(:ca, locale: :en)
{:ok, "Calendar"}

iex> Localize.Locale.LocaleDisplay.type_name(:ca, :buddhist, locale: :en)
{:ok, "Buddhist Calendar"}
```

Both accept a key in its short BCP 47 form (`:ca`) or CLDR's long form (`:calendar`).

CLDR also records a short name for each type value, marked `scope="core"` — "Buddhist" rather than "Buddhist Calendar" — intended for exactly this use. Those are not currently reachable: cldr-json collapses every core name for a key onto a single entry, so the one belonging to a given value cannot be recovered from the published data. `type_name/3` with `prefer: :menu` therefore reports the absence rather than returning a name belonging to some other calendar.

Boolean keys — `kn` (numeric sorting), `kb` (reversed accent sorting) and the rest — share one pair of translated strings instead of naming each state separately:

```elixir
iex> Localize.Locale.LocaleDisplay.type_value_name(true, locale: :en)
{:ok, "On"}

iex> Localize.Locale.LocaleDisplay.type_value_name("yes", locale: :de)
{:ok, "Ein"}
```

CLDR ships the strings and the key names but no separator between them, so pairing them — "Numeric Sorting: On" — is yours to choose.

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

## Preference option summary

Every display-name function takes the same `:prefer` option, and each module supports the subset its data can supply. `:style` remains accepted as the older spelling.

| Module | `:prefer` values | Default | Absent alternative |
|--------|------------------|---------|--------------------|
| `Localize.Territory` | `:standard`, `:short`, `:variant` | `:standard` | `Localize.UnknownStyleError` |
| `Localize.Language` | `:standard`, `:short`, `:long`, `:menu`, `:variant` | `:standard` | falls back to `:standard` |
| `Localize.Script` | `:standard`, `:short`, `:stand_alone`, `:variant` | `:standard` | falls back to `:standard` |
| `Localize.Locale.LocaleDisplay` | `:standard`, `:short`, `:long`, `:variant`, `:stand_alone`, `:menu` | `:standard` | falls back per subtag |

These are name *alternatives* recorded by CLDR, not widths that always exist. A value outside a module's list is reported rather than resolved silently:

```elixir
iex> {:error, error} = Localize.Script.display_name(:Latn, prefer: :menu)
iex> error.__struct__
Localize.InvalidValueError
```

`Localize.Locale.LocaleDisplay` also takes a separate `:language_display` option — `:standard` or `:dialect` — which decides whether a script or territory is folded into the language name ("American English") or rendered beside it ("English (United States)").
