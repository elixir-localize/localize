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

In Localize there is no equivalent. Delete your backend module. All 766 CLDR locales are available at runtime without pre-declaration, and all formatting modules are ready to use immediately.

## Configuration

Localize requires no compile-time configuration. All options are set in your application config and take effect at runtime.

### Recommended migration config

Most ex_cldr projects configure a fixed set of locales in the backend module. The Localize equivalent is `:supported_locales` (constrains validation) plus `mix localize.download_locales` (pre-populates the cache at build time):

```elixir
# config/config.exs
config :localize,
  default_locale: :en,
  supported_locales: [:en, :fr, :de, :ja]
```

```bash
# At build time (Dockerfile, CI, or local)
mix localize.download_locales
```

In ex_cldr, locales were declared inside `use Cldr, locales: [...]` and embedded at compile time. In Localize, `:supported_locales` is an application environment key (no recompilation needed), and locale data is downloaded once at build time and loaded lazily into `:persistent_term` on first access.

### Using Gettext locales

If your application uses Gettext, you can derive `:supported_locales` from your Gettext backend. Since the Gettext module must be compiled first, use `config/runtime.exs`:

```elixir
# config/runtime.exs
config :localize,
  supported_locales: Gettext.known_locales(MyApp.Gettext)
```

POSIX-style locale names returned by Gettext (e.g. `"pt_BR"`, `"zh_Hans"`) are automatically normalised to BCP 47 and resolved to their CLDR canonical form via likely-subtag resolution. For example, `"pt_BR"` resolves to `:pt` (CLDR treats bare `pt` as Brazilian Portuguese) and `"zh_Hans"` resolves to `:zh`. No manual mapping is needed.

Only exact matches (distance score 0 in the CLDR matching algorithm) are accepted for `:supported_locales` — this ensures that misspelled or unrecognised locale names are caught at startup rather than silently mapping to a distant locale. Entries that cannot be resolved log a warning with `domain: :localize` and are skipped.

Coverage-level keywords (`:modern`, `:moderate`, `:basic`) are also accepted and expand to all CLDR locales at or above that level:

```elixir
config :localize,
  supported_locales: [:modern]  # ~104 locales with modern CLDR coverage
```

### Full options reference

| Option | Default | Description |
|---|---|---|
| `:default_locale` | Derived from `LOCALIZE_DEFAULT_LOCALE` env var → `LANG` env var → `:en` | Application-wide default locale. |
| `:supported_locales` | `nil` (all 766 CLDR locales) | List of locale atoms, wildcard strings (e.g. `"en-*"`), coverage-level keywords (`:modern`, `:moderate`, `:basic`), or Gettext-style strings (e.g. `"pt_BR"`). POSIX underscores are normalised and entries are resolved via likely-subtag resolution — only exact matches (score 0) are accepted. Invalid entries log a warning and are skipped. When set, `validate_locale/1` resolves against this list instead of all CLDR locales. |
| `:preload_locales` | **deprecated** | Deprecated and ignored. Use `:supported_locales` and `mix localize.download_locales`. |
| `:otp_app` | `nil` | **Recommended.** Atom naming your application. Localize caches downloaded locale data under `Application.app_dir(<otp_app>, "priv/localize/locales")` — the same convention as `Ecto.Repo`, `Phoenix.Endpoint`, and `Gettext.Backend`. Resolved at every read so mix tasks, `mix test`, and releases all see the right path. |
| `:locale_cache_dir` | `Application.app_dir(:localize, "priv/localize/locales")` | Path to the on-disk cache. Absolute paths are used verbatim and override `:otp_app`. **Relative** paths are valid only when paired with `:otp_app`, in which case they resolve against `Application.app_dir(<otp_app>, <relative>)`. A bare relative path with no `:otp_app` raises `Localize.LocaleCacheDirError` at app start. |
| `:allow_runtime_locale_download` | `false` | When `true`, locales not in the cache are downloaded from the CDN on first access. Default `false` — use `mix localize.download_locales` to pre-populate at build time. |
| `:locale_provider` | `Localize.Locale.Provider.PersistentTerm` | Module implementing `Localize.Locale.Provider` for locale data loading. |
| `:nif` | `false` | Enable the optional ICU4C NIF backend. Also settable via `LOCALIZE_NIF=true`. |
| `:mf2_functions` | `%{}` | Map of custom MF2 function modules (see `Localize.Message.Function`). |
| `:cacertfile` | System default | Path to a custom CA certificate file for HTTPS connections. |
| `:https_proxy` | `nil` | HTTPS proxy URL. Also reads `HTTPS_PROXY` env var. |

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

### Pre-populating the locale cache

Run `mix localize.download_locales` at build time to download locale data for all configured `:supported_locales`. Locale data is then loaded lazily into `:persistent_term` on first access — no runtime downloads needed.

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
    {:localize, "~> 0.29"}
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
| `Cldr.LocaleDisplay` | `Localize.Locale.LocaleDisplay` |
| `Cldr.Message` | `Localize.Message` |
| `Cldr.Collation` | `Localize.Collation` |
| `Cldr.Calendar` | `Localize.Calendar` (localized name/part strings) **and** `Calendrical` (date conversion, intervals) — see [Calendar conversion and intervals moved to Calendrical](#calendar-conversion-and-intervals-moved-to-calendrical) |
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

### Calendar conversion and intervals moved to Calendrical

`ex_cldr_calendars` bundled two distinct kinds of functionality under `Cldr.Calendar`: producing localized *strings* for calendar parts (era, month, day-of-week names), and *calendar arithmetic* (converting a date into a locale's calendar, generating date sequences). Localize splits these across two packages. The string functions live in `Localize.Calendar`; the calendar arithmetic lives in the `calendrical` package, whose `Calendrical` module builds on top of Localize.

If you use `Cldr.Calendar.localize/1` (date-to-calendar conversion) or `Cldr.Calendar.interval/3`, add `calendrical` as a dependency:

```elixir
# mix.exs
{:calendrical, "~> 0.9"}
```

Function mapping:

| ex_cldr_calendars | Localize replacement |
|---|---|
| `Cldr.Calendar.localize(date)` (convert date to locale's calendar) | `Calendrical.localize/1`, `Calendrical.localize/2` |
| `Cldr.Calendar.localize(date, part, options)` (localized part string) | `Localize.Calendar.localize/3` or `Calendrical.localize/3` |
| `Cldr.Calendar.interval(date, date_or_count, precision)` | `Calendrical.interval/3` |
| `Cldr.Calendar.interval_stream(date, date_or_count, precision)` | `Calendrical.interval_stream/3` |

Note the return shape of the conversion function changed — `Calendrical.localize/1,2` wraps `Date.convert/2` and returns an `{:ok, date}` tuple rather than a bare date:

```elixir
# ex_cldr_calendars — returns the date directly
MyApp.Cldr.Calendar.localize(~D[2022-06-09], locale: "fr")
#=> %Date{year: 2022, month: 6, day: 9, calendar: Cldr.Calendar.FR}

# Localize — returns {:ok, date}
iex> Calendrical.localize(~D[2022-06-09], locale: "fr")
{:ok, %Date{year: 2022, month: 6, day: 9, calendar: Calendrical.FR}}
```

`interval/3` keeps the same `date_from`, `date_to`-or-`count`, `precision` signature (`:years`, `:quarters`, `:months`, `:weeks`, `:days`):

```elixir
iex> Calendrical.interval(~D[2019-01-31], 3, :months)
[~D[2019-01-31], ~D[2019-02-28], ~D[2019-03-31]]

iex> Calendrical.interval(~D[2019-01-31], ~D[2019-05-31], :months)
[~D[2019-01-31], ~D[2019-02-28], ~D[2019-03-31], ~D[2019-04-30], ~D[2019-05-31]]
```

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
{:ok, "2:30:00\u202FPM"}

iex> Localize.Time.to_string(~T[14:30:00], format: :short)
{:ok, "2:30\u202FPM"}
```

### DateTimes

```elixir
# ex_cldr
MyApp.Cldr.DateTime.to_string(~N[2025-07-10 14:30:00])

# Localize
iex> Localize.DateTime.to_string(~N[2025-07-10 14:30:00])
{:ok, "Jul 10, 2025, 2:30:00\u202FPM"}

iex> Localize.DateTime.to_string(~N[2025-07-10 14:30:00], format: :short)
{:ok, "7/10/25, 2:30\u202FPM"}
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

iex> Localize.Unit.to_string(unit, format: :short)
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

# Localize (renamed from to_string to display_name)
iex> Localize.Language.display_name("de")
{:ok, "German"}

iex> Localize.Language.display_name("en", locale: :de)
{:ok, "Englisch"}

iex> Localize.Language.display_name("en-GB", style: :short)
{:ok, "UK English"}
```

### Calendar

```elixir
# ex_cldr
MyApp.Cldr.Calendar.localize(~D[2024-01-15], :month, type: :stand_alone)

# Localize (option :type renamed to :context)
iex> Localize.Calendar.localize(~D[2024-01-15], :month, context: :stand_alone)
"Jan"

# New unified display_name API
iex> Localize.Calendar.display_name(:month, 1)
{:ok, "January"}

iex> Localize.Calendar.display_name(:calendar, :gregorian)
{:ok, "Gregorian Calendar"}

iex> Localize.Calendar.display_name(:date_time_field, :year)
{:ok, "year"}
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
| `Territory.country_codes/0` | `Territory.individual_territories/0` |
| `List.known_list_formats/0` | `List.known_list_styles/0` |
| `List.list_formats_for/1` | `List.list_styles_for/1` |

Note that `Localize.Territory.individual_territories/0` returns a sorted list of leaf territory code atoms (actual territories, excluding macro-regions such as `:"001"` or `:"150"`). This is distinct from `Localize.Territory.territory_codes/1`, which returns a map of ISO 3166 Alpha-2 codes to their Alpha-3 and numeric equivalents for all territories.

## Option renaming

| Function | ex_cldr option | Localize option |
|---|---|---|
| `Localize.List.to_string/2`, `Localize.List.intersperse/2` | `:format` | `:list_style` |

The `:format` option on `Localize.List.to_string/2` and `Localize.List.intersperse/2` has been renamed to `:list_style`. This frees up the `:format` keyword to be passed through to per-element formatters when the list contains values like dates or numbers — for example, `Localize.List.to_string([~D[2025-07-10], ~D[2025-08-15]], locale: :en, format: :long)` now produces `"July 10, 2025 and August 15, 2025"` because `:format` is forwarded to `Localize.Date.to_string/2` for each element while the list join uses the default `:standard` style. Migration is mechanical:

```elixir
# ex_cldr
Cldr.List.to_string(["a", "b", "c"], MyApp.Cldr, format: :unit_narrow)

# Localize
iex> Localize.List.to_string(["a", "b", "c"], locale: :en, list_style: :unit_narrow)
{:ok, "a b c"}
```

The companion helpers `Localize.List.known_list_styles/0` and `Localize.List.list_styles_for/1` (renamed from `known_list_formats/0` and `list_formats_for/1`) return the available `:list_style` values.

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

Localize includes an optional NIF binding for ICU4C. When enabled, specific functions can use the NIF for formatting by passing `backend: :nif`. The default backend is always `:elixir` — no NIF is required. Functions that support the NIF include `Localize.Number.to_string/2`, `Localize.Unit.to_string/2`, `Localize.Number.PluralRule.plural_type/2`, `Localize.Message.format/3`, and `Localize.Collation.compare/3`.

Enable by setting:

```elixir
config :localize, :nif, true
```

Or: `export LOCALIZE_NIF=true` at compile time. When the NIF is not available, Localize falls back to pure Elixir automatically. Check availability with `Localize.Nif.available?/0`.

## Collation

```elixir
# ex_cldr
Cldr.Collation.sort(["banana", "apple", "cherry"], MyApp.Cldr, locale: "en")

# Localize
iex> Localize.Collation.sort(["banana", "apple", "cherry"])
["apple", "banana", "cherry"]
```

The collation table is loaded into `:persistent_term` on first use. No compile-time configuration is needed.

## Polymorphic formatting

Localize provides `Localize.to_string/2` and `Localize.to_string!/2`, which format any supported value type through the `Localize.Chars` protocol. This replaces the need to dispatch to the correct module by hand:

```elixir
# Format any value — the protocol picks the right formatter
iex> Localize.to_string(1234.5, locale: :de)
{:ok, "1.234,5"}

iex> Localize.to_string(~D[2025-07-10], locale: :en)
{:ok, "Jul 10, 2025"}

iex> {:ok, unit} = Localize.Unit.new(42, "kilometer")
iex> Localize.to_string(unit, format: :short, locale: :en)
{:ok, "42 km"}
```

Built-in implementations cover `Integer`, `Float`, `Decimal`, `Date`, `Time`, `DateTime`, `NaiveDateTime`, `Range`, `BitString`, `List`, `Localize.Unit`, `Localize.Duration`, `Localize.LanguageTag`, and `Localize.Currency`. Add implementations for your own types with `defimpl Localize.Chars, for: MyApp.Money`.

## Summary of key differences

| Aspect | ex_cldr | Localize |
|---|---|---|
| Setup | `use Cldr` backend module | None required |
| Available locales | Pre-configured list | All 766 CLDR locales (constrainable via `:supported_locales`) |
| Locale data loading | Compile-time embedding | Runtime lazy loading + on-demand download |
| Locale argument | Backend module required | Not needed — defaults to `Localize.get_locale()` |
| Default locale | Per-backend config | Process dictionary + app config + env vars |
| Error format | `{:error, {Module, string}}` | `{:error, %Exception{}}` |
| Dependencies | 11+ packages | Single package |
| Polymorphic API | None | `Localize.to_string/2` via `Localize.Chars` protocol |
| Custom MF2 functions | None | `Localize.Message.Function` behaviour + `:functions` option |
| NIF support | None | Optional (number, unit, plural, MF2, collation) |
