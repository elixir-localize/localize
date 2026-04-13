# Localize

Locale-aware formatting, validation, and data access for Elixir, built on the [Unicode CLDR](https://cldr.unicode.org/) repository.

Localize consolidates the functionality of the `ex_cldr_*` library family into a single package. No compile-time backend modules or code generation is required — all CLDR data is loaded at runtime and cached in `:persistent_term`.

## Features

* **Numbers** — format integers, decimals, percentages, and currencies with locale-appropriate grouping, decimal separators, and symbols.

* **Dates and times** — format `Date`, `Time`, `DateTime`, and `NaiveDateTime` values using CLDR calendar patterns.

* **Intervals** — format date, time, and datetime ranges.

* **Units** — format units of measure with plural-aware patterns and territory-based usage preferences.

* **Lists** — join items with locale-appropriate conjunctions (e.g., "a, b, and c").

* **Territories** — display names, containment hierarchies, subdivisions, and emoji flags.

* **Languages** — localized language display names.

* **Currencies** — validation, territory-to-currency mapping, and currency history.

* **Collation** — locale-sensitive string sorting using the Unicode Collation Algorithm with CLDR tailoring.

* **Locale display** — full locale display names (e.g., "English (United States)").

* **Calendars** — era names, month names, day names, and day period names for all CLDR calendars.

* **MessageFormat 2** — parse and evaluate ICU MessageFormat 2 message strings.

## Supported Elixir and OTP versions

Localize requires **Elixir 1.17+** and **Erlang/OTP 26+**.

## Installation

Add `localize` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:localize, "~> 0.1.0"}
  ]
end
```

## Quick start

```elixir
iex> # Numbers
iex> Localize.Number.to_string(1_234_567.89)
{:ok, "1,234,567.89"}

iex> Localize.Number.to_string(0.456, format: :percent)
{:ok, "46%"}

iex> # Dates
iex> Localize.Date.to_string(~D[2025-03-22])
{:ok, "Mar 22, 2025"}

iex> Localize.Date.to_string(~D[2025-03-22], format: :long)
{:ok, "March 22, 2025"}

iex> # Units
iex> Localize.Unit.to_string(Localize.Unit.new!(3.5, "kilometer"))
{:ok, "3.5 kilometers"}

iex> # Lists
iex> Localize.List.to_string(["apple", "banana", "cherry"])
{:ok, "apple, banana, and cherry"}

iex> # Territories and languages
iex> Localize.Territory.display_name(:US)
{:ok, "United States"}

iex> Localize.Language.display_name(:fr)
{:ok, "French"}

iex> # Collation
iex> Localize.Collation.sort(["banana", "apple", "Cherry"])
["apple", "banana", "Cherry"]
```

## Locale management

Localize maintains a per-process current locale and an application-wide default:

```elixir
iex> # Get the current locale (defaults to :en)
iex> Localize.get_locale()

iex> # Set the process locale
iex> Localize.put_locale(:de)

iex> # Temporarily use a different locale
iex> Localize.with_locale(:ja, fn ->
...>   Localize.Number.to_string(1234)
...> end)
{:ok, "1,234"}
```

The default locale is resolved from (in order):
1. `LOCALIZE_DEFAULT_LOCALE` environment variable.
2. `config :localize, default_locale: :fr` in application config.
3. `LANG` environment variable.
4. `:en` as a final fallback.

All formatting functions default their `:locale` option to `Localize.get_locale()` when no locale is explicitly passed.

## Configuration

Localize requires no compile-time configuration. All options are set in your application config and take effect at runtime. Its also perfectly reasonable to have no configuration, at least when you are just exploring the library. The `:en` locale is always installed so that will be used for formatting and parsing until you add some configuration.

```elixir
config :localize,
  default_locale: :fr,
  supported_locales: [:en, :fr, :de, :ja, :es, "zh-*"],
  locale_provider: MyApp.LocaleProvider,
  locale_cache_max_entries: 2_000,
  format_cache_max_entries: 5_000,
  locale_cache_dir: "/path/to/locale/cache",
  nif: true,
  cacertfile: "/path/to/cacerts.pem",
  https_proxy: "http://proxy.example.com:8080"
```

| Option | Default | Description |
|--------|---------|-------------|
| `:default_locale` | Derived from `LOCALIZE_DEFAULT_LOCALE` env var, then `LANG` env var, then `:en`. | The application-wide default locale. Can also be set at runtime with `Localize.put_default_locale/1`. |
| `:supported_locales` | `nil` | A list of locale identifiers that your application supports. Each entry is an atom matching a known CLDR locale (e.g., `:en`, `:"fr-CA"`), a wildcard string (e.g., `"en-*"`), a coverage-level keyword (`:modern`, `:moderate`, `:basic`), or a Gettext-style string (e.g., `"pt_BR"`, `"zh_Hans"`). POSIX-style underscores are normalised to hyphens and entries are resolved to their CLDR canonical form via likely-subtag resolution (e.g. `"pt_BR"` → `:pt`). Only exact matches (score 0) are accepted — entries that cannot be resolved log a warning with `domain: :localize` and are skipped. When set, `validate_locale/1` resolves locale identifiers against this list rather than all ~766 CLDR locales. Accessible at runtime via `Localize.supported_locales/0`. |
| `:locale_provider` | `Localize.Locale.Provider.PersistentTerm` | Module that implements the `Localize.Locale.Provider` behaviour for loading and caching per-locale data. |
| `:locale_cache_max_entries` | `1_000` | Maximum number of validated locales to hold in the ETS cache. A background sweeper runs every 10 seconds and evicts excess entries to prevent unbounded growth. |
| `:format_cache_max_entries` | `2_000` | Maximum number of compiled format patterns (number and date/time) to hold in the ETS cache. A background sweeper runs every 10 seconds and evicts excess entries to prevent unbounded growth. |
| `:locale_cache_dir` | `Application.app_dir(:localize, "priv/localize/locales")` | Directory where downloaded per-locale ETF data files are cached. See `Localize.Locale.Provider.locale_cache_dir/0`. |
| `:allow_runtime_locale_download` | `false` | When `true`, locales not found in the on-disk cache are downloaded from the Localize CDN on first access. When `false` (the default), missing locales return an error. Use `mix localize.download_locales` to pre-populate the cache at build time. |
| `:nif` | `false` | Enable the optional NIF for faster Unicode normalisation and collation sort-key generation. Can also be enabled with the `LOCALIZE_NIF=true` environment variable at compile time. See `Localize.Nif` for details. |
| `:mf2_functions` | `%{}` | Map of custom MF2 formatting function modules. See `Localize.Message.Function`. |
| `:cacertfile` | System default | Path to a custom CA certificate file for HTTPS connections (used when downloading locale data). |
| `:https_proxy` | `nil` | HTTPS proxy URL. Also reads the `HTTPS_PROXY` environment variable. |

### Using Gettext locales

If your application uses Gettext, you can derive `:supported_locales` from your Gettext backend in `config/runtime.exs` (where the module is already compiled and available):

```elixir
# config/runtime.exs
config :localize,
  supported_locales: Gettext.known_locales(MyApp.Gettext)
```

POSIX-style locale names returned by Gettext (e.g. `"pt_BR"`, `"zh_Hans"`) are automatically normalized to BCP 47 and resolved to their CLDR canonical form (`:pt`, `:zh`). No manual mapping is needed.

### Pre-populating the locale cache

Use `mix localize.download_locales` at build time to download locale data into the on-disk cache. By default it downloads the configured `:supported_locales`:

```bash
# Dockerfile
RUN mix localize.download_locales
```

Specific locales can also be downloaded explicitly: `mix localize.download_locales en fr de`. Use `--all` for all CLDR locales. Locale data is loaded lazily into `:persistent_term` on first access from the cache.

When `:supported_locales` is **not** configured (the default), `validate_locale/1` matches against all ~766 CLDR locales.

## Environment variables

The following environment variables influence Localize behaviour.

### Runtime

| Variable | Description |
|----------|-------------|
| `LOCALIZE_DEFAULT_LOCALE` | Sets the application-wide default locale (e.g., `en-AU`, `ja`). Takes precedence over the `LANG` variable and the `:default_locale` application config. Evaluated once on first call to `Localize.get_locale/0` or `Localize.default_locale/0`. |
| `LANG` | Standard POSIX locale variable (e.g., `en_US.UTF-8`). Used as a fallback when `LOCALIZE_DEFAULT_LOCALE` is not set and no `:default_locale` is configured. The value is converted from POSIX format (underscores replaced with hyphens, encoding suffix stripped). |
| `LOCALIZE_UNSAFE_HTTPS` | When set to any value, disables SSL certificate verification for HTTPS connections (e.g., locale data downloads). Intended for development behind corporate proxies with self-signed certificates. Do not use in production. |
| `LOCALIZE_HTTP_TIMEOUT` | HTTP request timeout in milliseconds for locale data downloads. Overrides the default timeout. |
| `LOCALIZE_HTTP_CONNECTION_TIMEOUT` | HTTP connection timeout in milliseconds for locale data downloads. Overrides the default connection timeout. |
| `HTTPS_PROXY` / `https_proxy` | HTTPS proxy URL for outbound connections. Also configurable via the `:https_proxy` application config key. |

### Compile time

| Variable | Description |
|----------|-------------|
| `LOCALIZE_NIF` | Set to `true` to compile the optional NIF extension (e.g., `LOCALIZE_NIF=true mix compile`). Enables ICU4C-based Unicode normalisation, collation sort-key generation, and number/message formatting. Can also be enabled with `config :localize, nif: true`. |

### Default locale resolution order

When `Localize.get_locale/0` is called and no process-level locale has been set, the default locale is resolved in this order:

1. `LOCALIZE_DEFAULT_LOCALE` environment variable.

2. `:default_locale` application config (`config :localize, default_locale: :fr`).

3. `LANG` environment variable (POSIX format converted to BCP 47).

4. `:en` as the final fallback.

The resolved locale is cached in `:persistent_term` after first resolution so this lookup happens only once per BEAM lifetime.

## Optional NIF Backend

Localize includes an optional NIF backend powered by ICU4C. When enabled, specific functions can use the NIF for formatting by passing `backend: :nif`. The default backend is always `:elixir` — no NIF is required.

| Function | `:backend` option | NIF implementation |
|----------|------------------|--------------------|
| `Localize.Number.to_string/2` | `backend: :nif` | ICU4C NumberFormatter |
| `Localize.Unit.to_string/2` | `backend: :nif` | ICU4C NumberFormatter (unit) |
| `Localize.Number.PluralRule.plural_type/2` | `backend: :nif` | ICU4C PluralRules |
| `Localize.Message.format/3` | `backend: :nif` | ICU4C MessageFormat 2 |
| `Localize.Collation.compare/3` | `backend: :nif` | ICU4C Collator |

If `:nif` is specified but the NIF is not compiled or not available, it silently falls back to the pure Elixir implementation. See the [Performance Guide](https://hexdocs.pm/localize/performance.html) for benchmarks and guidance.

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/localize).

### Migrating from ex_cldr

If you are migrating from the `ex_cldr` family of libraries, see the [Migration Guide](https://hexdocs.pm/localize/migration.html) for a detailed walkthrough of configuration changes, API differences, and upgrade steps.

## Additional Localize libraries

Localize is the core CLDR-backed formatting and validation library. The following companion packages build on top of it and cover domains that fall outside the core CLDR data model:

### Supplemental localization libraries

* [localize_person_names](https://hex.pm/packages/localize_person_names) — Locale-aware person name formatting implementing the CLDR TR35 person names specification. Uses Unicode word segmentation to handle given, middle, surname, and generation components across locales.

* [localize_phonenumber](https://hex.pm/packages/localize_phonenumber) — Parsing, validation, and locale-aware formatting of international phone numbers, including territory detection and E.164 canonicalisation.

* [localize_address](https://hex.pm/packages/localize_address) — Postal address parsing and locale-aware formatting using CLDR territory data and locale-specific address layouts.

* [intl](https://hex.pm/packages/intl) — A higher-level, ergonomic API layer over `Localize` modeled on the ECMAScript `Intl` object. Provides a unified interface for number, date, time, relative time, list, and plural formatting.

### Libraries that depend on Localize

* [ex_money version 6.0](https://hex.pm/packages/ex_money) which is updated to be based upon `Localize`.

## Acknowledgements

* `Localize.Language` is based upon the [ex_cldr_language](https://github.com/elixir-cldr/cldr_languages) library by [@lostkobraki](https://github.com/lostkobrakai).

* `Localize.Territory` is based upon the [ex_cldr_territories](https://github.com/elixir-cldr/cldr_territories) library by [@Schultzer](https://github.com/Schultzer).

## License

Apache License 2.0. See the [LICENSE](https://github.com/elixir-localize/localize/blob/main/LICENSE.md) file for details.
