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

iex> Localize.Language.to_string(:fr)
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

Localize requires no compile-time configuration. All options are set in your application config and take effect at runtime.

```elixir
config :localize,
  default_locale: :fr,
  supported_locales: [:en, :fr, :de, :ja, :es, "zh-*"],
  preload_locales: [:en, :de, :ja, "fr-*"],
  locale_provider: MyApp.LocaleProvider,
  locale_cache_max_entries: 2_000,
  data_dir: "/path/to/locale/data",
  nif: true,
  cacertfile: "/path/to/cacerts.pem",
  https_proxy: "http://proxy.example.com:8080"
```

| Option | Default | Description |
|--------|---------|-------------|
| `:default_locale` | Derived from `LOCALIZE_DEFAULT_LOCALE` env var, then `LANG` env var, then `:en`. | The application-wide default locale. Can also be set at runtime with `Localize.put_default_locale/1`. |
| `:supported_locales` | `nil` | A list of locale identifiers that your application supports. Each entry is an atom matching a known CLDR locale (e.g., `:en`, `:"fr-CA"`) or a wildcard string (e.g., `"en-*"`) that expands to all matching CLDR locales. Invalid entries log a warning and are skipped. When set, `validate_locale/1` resolves locale identifiers against this list rather than all ~766 CLDR locales. Accessible at runtime via `Localize.supported_locales/0`. See below for how this interacts with `:preload_locales`. |
| `:preload_locales` | `nil` | A list of locale identifiers to load at application startup. Accepts atoms and wildcard strings like `:supported_locales`. Locale data is fetched and cached in `:persistent_term` before any formatting calls. Invalid entries log a warning and are skipped. See below for how this interacts with `:supported_locales`. |
| `:locale_provider` | `Localize.Locale.Provider.PersistentTerm` | Module that implements the `Localize.Locale.Provider` behaviour for loading and caching per-locale data. |
| `:locale_cache_max_entries` | `1_000` | Maximum number of validated locales to hold in the ETS cache. A background sweeper runs every 10 seconds and evicts excess entries to prevent unbounded growth. |
| `:data_dir` | `Path.join(:code.priv_dir(:localize), "cldr/locales")` | Directory where per-locale JSON data files are stored. |
| `:nif` | `false` | Enable the optional NIF for faster Unicode normalisation and collation sort-key generation. Can also be enabled with the `LOCALIZE_NIF=true` environment variable at compile time. See `Localize.Nif` for details. |
| `:cacertfile` | System default | Path to a custom CA certificate file for HTTPS connections (used when downloading locale data). |
| `:https_proxy` | `nil` | HTTPS proxy URL. Also reads the `HTTPS_PROXY` environment variable. |

### Supported and preload locale interaction

When `:supported_locales` is configured, the effective supported locale list is the **union** of `:supported_locales` and `:preload_locales`. This means any locale you preload is automatically considered supported — you don't need to list it in both places.

```elixir
config :localize,
  supported_locales: [:en, :fr, :de],
  preload_locales: [:ja]

# Effective supported locales: [:en, :fr, :de, :ja]
# Locale data for :ja is preloaded at startup
```

When `:supported_locales` is **not** configured (the default), `validate_locale/1` matches against all ~766 CLDR locales and `:preload_locales` simply controls which locale data is loaded eagerly.

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/localize).

## License

Apache License 2.0. See the [LICENSE](LICENSE) file for details.
