# Architecture

Localize is a locale-aware formatting and data library for Elixir built on the Unicode CLDR repository. It provides the same domain coverage as the `ex_cldr` family of libraries but with a fundamentally different architecture.

This document describes the key design decisions and how they differ from `ex_cldr`.

## No backend compile-time modules

### ex_cldr

In `ex_cldr`, every application defines one or more *backend modules* using `use Cldr`:

```elixir
defmodule MyApp.Cldr do
  use Cldr,
    locales: [:en, :fr, :de],
    providers: [Cldr.Number, Cldr.DateTime, Cldr.Territory]
end
```

The `use Cldr` macro triggers a `@before_compile` hook that runs `Cldr.Backend.Compiler.__before_compile__/1`. This generates a large module containing:

* A function clause per configured locale with embedded CLDR data (territory names, number formats, date patterns, etc.).

* Delegation functions for every registered provider (Number, DateTime, Territory, Language, etc.).

* Configuration accessors (`known_locale_names/0`, `default_locale/0`, etc.).

The generated module is compiled into a single BEAM file whose size grows with the number of configured locales and providers. Changing the locale list or adding a provider triggers a full recompilation of the backend.

### Localize

Localize has no backend concept. All public API functions live directly in domain modules (`Localize.Number`, `Localize.Date`, `Localize.Territory`, etc.) and are available immediately without any compile-time setup.

There is nothing to configure to start using the library. All 766+ CLDR locales are available at runtime without pre-declaration.

## Dynamic data loading at runtime

### ex_cldr

Locale data is loaded at compile time by `Cldr.Locale.Loader.get_locale/2` and embedded in the backend module via `Macro.escape/1`. The data becomes part of the compiled bytecode:

```elixir
# Inside the backend compiler (simplified)
for locale_name <- known_locale_names(config) do
  locale_data = Locale.Loader.get_locale(locale_name, config)
  def locale_data(unquote(locale_name)), do: unquote(Macro.escape(locale_data))
end
```

This means:

* Only pre-configured locales are available.

* Adding a locale requires recompilation.

* BEAM file sizes grow linearly with locale count.

### Localize

Locale data is loaded lazily at runtime on first access and cached in `:persistent_term` for zero-copy concurrent reads:

```elixir
# Localize.Locale.Provider.PersistentTerm (simplified)
def load(locale_id) do
  locale_data = read_locale_json(locale_id)
  :persistent_term.put({:localize, locale_id}, locale_data)
end

def get(locale_id, keys, _options) do
  locale_data = :persistent_term.get({:localize, locale_id})
  get_in(locale_data, keys)
end
```

This means:

* All CLDR locales are available without configuration.

* Locale data is loaded only when needed, reducing startup time for applications that use few locales.

* Memory is used only for locales actually accessed.

* No recompilation when locale requirements change.

Supplemental data (plural rules, territory containment, currency codes, etc.) follows the same pattern — stored as ETF files in `priv/cldr/`, deserialized on first access, and cached in `:persistent_term`.

## Configurable data providers

Localize defines a `Localize.Locale.Provider` behaviour that abstracts how locale data is stored and retrieved:

```elixir
defmodule Localize.Locale.Provider do
  @callback load(locale_id :: atom()) :: :ok | {:error, term()}
  @callback store(locale_id :: atom(), data :: map()) :: :ok
  @callback loaded?(locale_id :: atom()) :: boolean()
  @callback get(locale_id :: atom(), keys :: list(), options :: Keyword.t()) ::
              {:ok, term()} | {:error, term()}
end
```

The default provider is `Localize.Locale.Provider.PersistentTerm`, which loads JSON locale files and caches them in `:persistent_term`. Alternative providers could store data in ETS, a database, or a remote service.

`ex_cldr` has no equivalent abstraction — data access is hard-wired through the compiled backend module.

## Consolidated library

### ex_cldr

The `ex_cldr` ecosystem is distributed across many packages:

* `ex_cldr` — core library, backend compiler, locale loading.
* `ex_cldr_numbers` — number formatting.
* `ex_cldr_dates_times` — date, time, datetime, interval formatting.
* `ex_cldr_units` — unit formatting and conversion.
* `ex_cldr_lists` — list formatting.
* `ex_cldr_currencies` — currency data and formatting.
* `ex_cldr_territories` — territory names and metadata.
* `ex_cldr_languages` — language display names.
* `ex_cldr_locale_display` — full locale display names.
* `ex_cldr_messages` — ICU/MF2 message formatting.
* `ex_cldr_collation` — Unicode collation.

Each package registers as a *provider* in the backend and generates its own module namespace (e.g., `MyApp.Cldr.Number`, `MyApp.Cldr.Territory`).

### Localize

All functionality is merged into a single library with domain modules under the `Localize` namespace:

* `Localize.Number` — number formatting.
* `Localize.Date`, `Localize.Time`, `Localize.DateTime` — date/time formatting.
* `Localize.Interval` — date/time interval formatting.
* `Localize.Unit` — unit formatting and conversion.
* `Localize.List` — list formatting.
* `Localize.Currency` — currency data and formatting.
* `Localize.Territory` — territory names, metadata, and relationships.
* `Localize.Language` — language display names.
* `Localize.LocaleDisplay` — full locale display names.
* `Localize.Message` — ICU MessageFormat 2.0 formatting.
* `Localize.Collation` — Unicode collation.
* `Localize.Calendar` — calendar localization.

A single dependency, a single version, and a single compilation unit.

## Process locale management

### ex_cldr

Locale state is per-backend. Each backend has its own current locale stored in the process dictionary:

```elixir
Cldr.put_locale(MyApp.Cldr, "de")
Cldr.get_locale(MyApp.Cldr)
```

Applications with multiple backends can have different current locales simultaneously.

### Localize

There is a single process-wide locale stored in the process dictionary via `Localize.put_locale/1` and `Localize.get_locale/0`. All formatting functions default to this locale.

The default locale is resolved once on first access using a precedence chain:

1. `LOCALIZE_DEFAULT_LOCALE` environment variable.
2. `Application.get_env(:localize, :default_locale)`.
3. `LANG` environment variable (charset stripped).
4. `:en` as final fallback.

Both the process locale and the default locale are `Localize.LanguageTag` structs, validated via `Localize.validate_locale/1`.

## Error handling

### ex_cldr

Errors are returned as two-element tuples containing an exception module and a message string:

```elixir
{:error, {Cldr.UnknownTerritoryError, "The territory :ZZ is unknown"}}
```

### Localize

Errors are returned as exception structs with structured fields and localizable messages via Gettext:

```elixir
{:error, %Localize.UnknownTerritoryError{territory: :ZZ}}
```

Exception messages use `Gettext.dpgettext/5` with domain `"localize"` and context strings, enabling translation of error messages themselves.

## Compiled artifact caching

Number format metadata and datetime format tokens are parsed from CLDR pattern strings at runtime. To avoid repeated parsing, Localize caches compiled artifacts in `:persistent_term`:

* **Number formats** — `Localize.Number.Format.Compiler` output (a `Meta` struct) cached by format string.

* **DateTime formats** — `Localize.DateTime.Format.Compiler` output (a token list) cached by format string.

These are effectively compile-once-use-forever within a VM lifetime, similar to `ex_cldr`'s `precompile_number_formats` option but without requiring explicit configuration.

## Plural rules

Both libraries generate per-locale plural rule functions at compile time from CLDR data. In Localize, the rule data is loaded from ETF at compile time for function generation, but the module attribute is deleted after generation so the raw data is not embedded in the BEAM file. Runtime access to plural rule data goes through `SupplementalData` with `:persistent_term` caching.

## Optional NIF integration

Localize includes an optional NIF binding for ICU4C (`Localize.Nif`) that provides native-speed MessageFormat 2.0 parsing and formatting. The NIF is opt-in via the `LOCALIZE_NIF=true` environment variable and falls back to a pure Elixir implementation when unavailable.

`ex_cldr` does not include NIF support.

## Collation

Localize includes a Unicode Collation Algorithm implementation (`Localize.Collation`) with a pre-built collation table stored in `:persistent_term`. This provides locale-aware string sorting without external dependencies.

`ex_cldr_collation` provides similar functionality as a separate package.
