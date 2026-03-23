# Migrating from ex_cldr to Localize

This guide is for developers currently using one or more `ex_cldr_*` libraries who want to migrate to Localize.

## No compile-time configuration

The most significant change is that Localize requires no compile-time backend module. In `ex_cldr` you define a backend:

```elixir
# ex_cldr — remove this entirely
defmodule MyApp.Cldr do
  use Cldr,
    locales: [:en, :fr, :de, :ja],
    default_locale: :en,
    providers: [Cldr.Number, Cldr.DateTime, Cldr.Unit, Cldr.List, Cldr.Territory]
end
```

In Localize there is no equivalent. Delete your backend module. All 766+ CLDR locales are available at runtime without pre-declaration, and all formatting modules are ready to use immediately.

## Configuration

Localize has minimal configuration. The only supported setting is the default locale.

### Default locale resolution

The default locale is resolved once on first access using this precedence chain:

1. `LOCALIZE_DEFAULT_LOCALE` environment variable.

2. `config :localize, default_locale: :fr` in your application config.

3. The `LANG` environment variable (e.g., `en_US.UTF-8`), with the charset suffix stripped and POSIX underscores converted to BCP 47 hyphens.

4. `:en` as a final fallback.

The resolved locale is validated and cached as a `Localize.LanguageTag` struct in `:persistent_term`.

If any source provides an invalid locale, a warning is logged with `domain: :localize` metadata and the next source is tried.

### Process locale

Set the locale for the current process:

```elixir
iex> {:ok, _} = Localize.put_locale(:de)
iex> Localize.get_locale().cldr_locale_id
:de
```

All formatting functions default their `:locale` option to `Localize.get_locale()`. In a Phoenix application you would typically call `Localize.put_locale/1` in a plug early in your pipeline.

Use `Localize.with_locale/2` for temporary locale changes:

```elixir
iex> Localize.with_locale(:ja, fn ->
...>   Localize.Number.to_string(1234)
...> end)
{:ok, "1,234"}
```

## Dependency changes

Replace all `ex_cldr_*` dependencies with a single dependency:

```elixir
# mix.exs
defp deps do
  [
    # Remove all of these:
    # {:ex_cldr, "~> 2.0"},
    # {:ex_cldr_numbers, "~> 2.0"},
    # {:ex_cldr_dates_times, "~> 2.0"},
    # {:ex_cldr_units, "~> 2.0"},
    # {:ex_cldr_lists, "~> 2.0"},
    # {:ex_cldr_currencies, "~> 2.0"},
    # {:ex_cldr_territories, "~> 2.0"},
    # {:ex_cldr_languages, "~> 2.0"},
    # {:ex_cldr_locale_display, "~> 2.0"},
    # {:ex_cldr_messages, "~> 2.0"},
    # {:ex_cldr_collation, "~> 2.0"},

    # Add this:
    {:localize, "~> 0.1"}
  ]
end
```

## Module mapping

| ex_cldr module | Localize module |
|---|---|
| `MyApp.Cldr.Number` | `Localize.Number` |
| `MyApp.Cldr.DateTime` | `Localize.DateTime` |
| `MyApp.Cldr.Date` | `Localize.Date` |
| `MyApp.Cldr.Time` | `Localize.Time` |
| `MyApp.Cldr.Unit` | `Localize.Unit` |
| `MyApp.Cldr.List` | `Localize.List` |
| `MyApp.Cldr.Territory` | `Localize.Territory` |
| `MyApp.Cldr.Language` | `Localize.Language` |
| `MyApp.Cldr.Currency` | `Localize.Currency` |
| `Cldr.LocaleDisplay` | `Localize.LocaleDisplay` |
| `Cldr.Message` | `Localize.Message` |
| `Cldr.Collation` | `Localize.Collation` |
| `Cldr` (core) | `Localize` |

## API differences

### No backend argument

In `ex_cldr`, most functions require a backend module as an argument. In Localize, remove it:

```elixir
# ex_cldr
Cldr.Territory.display_name(:GB, backend: MyApp.Cldr)
Cldr.Territory.from_territory_code(:GB, MyApp.Cldr, locale: "pt")

# Localize
iex> Localize.Territory.display_name(:GB)
{:ok, "United Kingdom"}

iex> Localize.Territory.display_name(:GB, locale: :pt)
{:ok, "Reino Unido"}
```

### Error tuple format

`ex_cldr` returns `{:error, {ExceptionModule, message}}`. Localize returns `{:error, %ExceptionStruct{}}`:

```elixir
# ex_cldr
{:error, {Cldr.UnknownTerritoryError, "The territory :ZZ is unknown"}}

# Localize
{:error, %Localize.UnknownTerritoryError{territory: :ZZ}}
```

Update any `case` or `with` clauses that pattern match on the two-element error tuple.

### Locale option defaults

All formatting functions default their `:locale` option to `Localize.get_locale()` (which returns a `LanguageTag`). You no longer need to pass `:locale` if you have set the process locale.

## Formatting examples

### Numbers

```elixir
# ex_cldr
MyApp.Cldr.Number.to_string(1234.5)
MyApp.Cldr.Number.to_string(0.56, format: :percent)
MyApp.Cldr.Number.to_string(100, currency: :USD)

# Localize
iex> Localize.Number.to_string(1234.5)
{:ok, "1,234.5"}

iex> Localize.Number.to_string(0.56, format: :percent)
{:ok, "56%"}

iex> Localize.Number.to_string(100, currency: :USD)
{:ok, "$100.00"}
```

### Dates

```elixir
# ex_cldr
MyApp.Cldr.Date.to_string(~D[2025-07-10])
MyApp.Cldr.Date.to_string(~D[2025-07-10], format: :full, locale: "fr")

# Localize
iex> Localize.Date.to_string(~D[2025-07-10])
{:ok, "Jul 10, 2025"}

iex> Localize.Date.to_string(~D[2025-07-10], format: :full, locale: :fr)
{:ok, "jeudi 10 juillet 2025"}
```

### Times

```elixir
# ex_cldr
MyApp.Cldr.Time.to_string(~T[14:30:00])

# Localize
iex> Localize.Time.to_string(~T[14:30:00])
{:ok, "2:30:00 PM"}

iex> Localize.Time.to_string(~T[14:30:00], format: :short)
{:ok, "2:30 PM"}
```

### DateTimes

```elixir
# ex_cldr
MyApp.Cldr.DateTime.to_string(~N[2025-07-10 14:30:00])

# Localize
iex> Localize.DateTime.to_string(~N[2025-07-10 14:30:00])
{:ok, "Jul 10, 2025, 2:30:00 PM"}

iex> Localize.DateTime.to_string(~N[2025-07-10 14:30:00], format: :short)
{:ok, "7/10/25, 2:30 PM"}
```

### Units

```elixir
# ex_cldr
MyApp.Cldr.Unit.new!(100, :meter)
MyApp.Cldr.Unit.to_string(unit)
MyApp.Cldr.Unit.convert!(unit, :kilometer)

# Localize
iex> {:ok, unit} = Localize.Unit.new(100, "meter")
iex> Localize.Unit.to_string(unit)
{:ok, "100 meters"}

iex> Localize.Unit.to_string(unit, style: :short)
{:ok, "100 m"}

iex> {:ok, converted} = Localize.Unit.convert(unit, "kilometer")
iex> converted.value
0.1
```

### Lists

```elixir
# ex_cldr
MyApp.Cldr.List.to_string(["a", "b", "c"])

# Localize
iex> Localize.List.to_string(["a", "b", "c"])
{:ok, "a, b, and c"}

iex> Localize.List.to_string(["a", "b", "c"], locale: :fr)
{:ok, "a, b et c"}
```

### Territories

```elixir
# ex_cldr
Cldr.Territory.from_territory_code(:GB, MyApp.Cldr)
Cldr.Territory.from_territory_code(:GB, MyApp.Cldr, locale: "pt")
Cldr.Territory.parent(:FR)
Cldr.Territory.children(:EU)
Cldr.Territory.info(:US)

# Localize
iex> Localize.Territory.display_name(:GB)
{:ok, "United Kingdom"}

iex> Localize.Territory.display_name(:GB, locale: :pt)
{:ok, "Reino Unido"}

iex> Localize.Territory.parent(:FR)
{:ok, [:"155", :EU, :EZ, :UN]}

iex> Localize.Territory.children(:EU)
{:ok, [:AT, :BE, :CY, ...]}

iex> Localize.Territory.info(:US)
{:ok, %{gdp: 24660000000000, population: 341963000, ...}}
```

### Languages

```elixir
# ex_cldr
MyApp.Cldr.Language.to_string("de")
MyApp.Cldr.Language.to_string("en", locale: "de")

# Localize
iex> Localize.Language.to_string("de")
{:ok, "German"}

iex> Localize.Language.to_string("en", locale: :de)
{:ok, "Englisch"}

iex> Localize.Language.to_string("en-GB", style: :short)
{:ok, "UK English"}
```

### Text formatting

```elixir
# ex_cldr
Cldr.quote("Hello", MyApp.Cldr)
Cldr.ellipsis("And so on", MyApp.Cldr)

# Localize
iex> Localize.quote("Hello")
{:ok, "\u201CHello\u201D"}

iex> Localize.ellipsis("And so on")
{:ok, "And so on\u2026"}
```

### Messages (ICU MessageFormat 2)

```elixir
# ex_cldr
Cldr.Message.format("You have {count} items", %{"count" => 3}, MyApp.Cldr)

# Localize
iex> Localize.Message.format(
...>   "{{You have {$count} items}}",
...>   %{"count" => 3}
...> )
{:ok, "You have 3 items"}
```

Note that Localize uses the MF2 (MessageFormat 2) syntax which differs from ICU MessageFormat 1. See the MF2 specification for syntax details.

## Function renaming

Some functions have been renamed for clarity:

| ex_cldr | Localize |
|---|---|
| `Territory.from_territory_code/3` | `Territory.display_name/2` |
| `Territory.from_subdivision_code/3` | `Territory.subdivision_name/2` |
| `Territory.to_unicode_flag/1` | `Territory.unicode_flag/1` |

## Locale validation

```elixir
# ex_cldr
Cldr.validate_locale("en", MyApp.Cldr)

# Localize
iex> {:ok, tag} = Localize.validate_locale("en")
iex> tag.cldr_locale_id
:en
```

The returned `LanguageTag` struct can be passed directly to any function that accepts a locale.

## Gettext integration

Use `Localize.Locale.gettext_locale_id/2` to find the best-matching Gettext locale for a CLDR locale:

```elixir
iex> Localize.Locale.gettext_locale_id(:en, MyApp.Gettext)
{:ok, "en"}
```

## Optional NIF

Localize includes an optional NIF binding for ICU4C that provides native-speed implementations of some operations. Currently the NIF supports MessageFormat 2 parsing and formatting. Future releases will extend NIF support to additional formatting functions.

The NIF is opt-in. Enable it by setting:

```elixir
# config/config.exs
config :localize, :nif, true
```

Or via environment variable:

```bash
export LOCALIZE_NIF=true
```

When the NIF is not available, Localize falls back to pure Elixir implementations automatically. You can check availability with `Localize.Nif.available?/0`.

## Collation

```elixir
# ex_cldr
Cldr.Collation.sort(["banana", "apple", "cherry"], MyApp.Cldr, locale: "en")

# Localize
iex> Localize.Collation.sort(["banana", "apple", "cherry"])
["apple", "banana", "cherry"]
```

The collation table is loaded into `:persistent_term` on first use. No compile-time configuration is needed.

## Summary of key differences

| Aspect | ex_cldr | Localize |
|---|---|---|
| Setup | `use Cldr` backend module | None required |
| Available locales | Pre-configured list | All 766+ CLDR locales |
| Locale data loading | Compile-time embedding | Runtime lazy loading |
| Locale argument | Backend module required | Not needed |
| Default locale | Per-backend config | Process dictionary + app config |
| Error format | `{:error, {Module, string}}` | `{:error, %Exception{}}` |
| Dependencies | 11+ packages | Single package |
| NIF support | None | Optional (MF2, expanding) |
