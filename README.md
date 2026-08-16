# Localize

![Build status](https://github.com/elixir-localize/localize/actions/workflows/ci.yml/badge.svg)
[![Hex.pm](https://img.shields.io/hexpm/v/localize.svg)](https://hex.pm/packages/localize)
[![Hex.pm](https://img.shields.io/hexpm/dw/localize.svg?)](https://hex.pm/packages/localize)
[![Hex.pm](https://img.shields.io/hexpm/dt/localize.svg?)](https://hex.pm/packages/localize)
[![Hex.pm](https://img.shields.io/hexpm/l/localize.svg)](https://hex.pm/packages/localize)

Locale-aware formatting, validation, and data access for Elixir, built on the [Unicode CLDR](https://cldr.unicode.org/) repository.

Localize consolidates the functionality of the `ex_cldr_*` library family into a single package. No compile-time backend modules or code generation is required — all CLDR data is loaded at runtime and cached in `:persistent_term`.

Try it without installing anything at the [Localize playground](https://playground.elixir-localize.com).

## Features

* **Numbers** — format integers, decimals, percentages, and currencies with locale-appropriate grouping, decimal separators, and symbols.

* **Number parsing** — parse locale-formatted strings back into numbers, including scanning numbers out of arbitrary text.

* **RBNF** — rule-based number formatting: spell-out ("one hundred twenty-three"), ordinals ("42nd"), Roman numerals, and other algorithmic systems.

* **Plural rules** — classify numbers into CLDR cardinal and ordinal plural categories for grammatically correct pluralization.

* **Dates and times** — format `Date`, `Time`, `DateTime`, and `NaiveDateTime` values using CLDR calendar patterns.

* **Relative times** — format time differences as human-readable phrases like "2 hours ago" or "in 3 days".

* **Intervals** — format date, time, and datetime ranges.

* **Durations** — format elapsed time as calendar-unit strings ("11 months, 30 days") or numeric time strings ("37:48:12").

* **Units** — format units of measure with plural-aware patterns and territory-based usage preferences.

* **Lists** — join items with locale-appropriate conjunctions (e.g., "a, b, and c").

* **Territories** — display names, containment hierarchies, subdivisions, and emoji flags.

* **Languages** — localized language display names.

* **Scripts** — localized script display names.

* **Currencies** — validation, territory-to-currency mapping, and currency history.

* **Collation** — locale-sensitive string sorting using the Unicode Collation Algorithm with CLDR tailoring.

* **Locale display** — full locale display names (e.g., "English (United States)").

* **Calendars** — era names, month names, day names, and day period names for all CLDR calendars.

* **MessageFormat 2** — parse and evaluate ICU MessageFormat 2 message strings.

## Claude Code skill

Localize ships a [Claude Code](https://claude.com/claude-code) skill that teaches Claude the library's APIs and localization-first patterns — every example execution-verified against the library. With the skill installed, Claude writes plural-correct, currency-correct, collation-correct Elixir by default, even for single-locale applications.

```
/plugin marketplace add elixir-localize/localize
/plugin install localize@localize
```

The skill source lives in [skills/localize](https://github.com/elixir-localize/localize/blob/v1.2.0/skills/localize/SKILL.md).

## MCP server

The companion [localize_mcp](https://hexdocs.pm/localize_mcp/readme.html) package is a Model Context Protocol server that lets any MCP host — Claude Code, Claude Desktop, Codex, Zed — search, browse, and invoke the Localize API through eleven typed tools, so agents discover the right function, options, and atom forms without grepping source. Add `{:localize_mcp, "~> 0.1", only: :dev}` to your project and run `claude mcp add localize -- mix localize_mcp`; the [host configuration guide](https://hexdocs.pm/localize_mcp/host_configuration.html) covers the other hosts.

## Supported Elixir and OTP versions

Localize requires **Elixir 1.17+** and **Erlang/OTP 26+**.

On OTP 26, also add the [json_polyfill](https://hex.pm/packages/json_polyfill) package — it provides the OTP 27+ `:json` module that Localize uses for JSON decoding. OTP 27 and later need no extra dependency.

## Installation

Add `localize` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:localize, "~> 1.0"}
  ]
end
```

On OTP 26 only:

```elixir
def deps do
  [
    {:localize, "~> 1.0"},
    {:json_polyfill, "~> 0.2 or ~> 1.0"}
  ]
end
```

By default the `:localize` OTP application starts automatically and brings up its own supervision tree. Applications that prefer to mount Localize under their own supervisor can do so by marking the dependency `runtime: false` and adding `Localize.Supervisor` to their `children` list — see the [Supervision](https://hexdocs.pm/localize/supervision.html) guide.

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

Localize requires no compile-time configuration. All options are set in your application config and take effect at runtime. It is also perfectly reasonable to have no configuration, at least when you are just exploring the library. The `:en` locale is always installed so that will be used for formatting and parsing until you add some configuration.

```elixir
config :localize,
  default_locale: :fr,
  supported_locales: [:en, :fr, :de, :ja, :es, "zh-*"],
  locale_provider: MyApp.LocaleProvider,
  locale_cache_max_entries: 2_000,
  format_cache_max_entries: 5_000,
  otp_app: :my_app,
  nif: true,
  cacertfile: "/path/to/cacerts.pem",
  https_proxy: "http://proxy.example.com:8080"
```

### Configuring the locale cache directory

Where Localize writes downloaded locale ETF files is controlled by two application-environment keys, `:otp_app` and `:locale_cache_dir`. **There are three supported forms** — pick the one that matches your situation:

**1. `:otp_app` only (recommended).** Caches under your app's runtime `priv/` directory at the conventional subpath:

```elixir
config :localize, otp_app: :my_app
# → Application.app_dir(:my_app, "priv/localize/locales")
```

**2. `:otp_app` + a relative `:locale_cache_dir`.** Same app-anchored resolution, but you choose the subpath:

```elixir
config :localize,
  otp_app: :my_app,
  locale_cache_dir: "priv/i18n/cache"
# → Application.app_dir(:my_app, "priv/i18n/cache")
```

**3. An absolute `:locale_cache_dir`.** Used verbatim — `:otp_app` is ignored. Use this for a shared mount or a fixed system path:

```elixir
config :localize, locale_cache_dir: "/var/lib/localize/locales"
```

Why `:otp_app` is the recommended anchor: `Application.app_dir/2` is re-resolved on every read, so a single config value works correctly in every runtime phase — mix tasks land files in `_build/<env>/lib/<app>/priv/...`, `mix test` reads the same path, and releases read from `/path/to/release/lib/<app>-X.Y.Z/priv/...`. No `config/runtime.exs` duplication is needed.

> **Why a bare relative `:locale_cache_dir` is refused.** A relative path *without* an `:otp_app` anchor resolves against the BEAM's current working directory, which differs between mix tasks (project root), `mix test`, and a release (release root) — one value cannot be correct in all phases. If you set a relative `:locale_cache_dir` without `:otp_app`, Localize raises `Localize.LocaleCacheDirError` at app start. Fix it by pairing the relative path with `:otp_app` (form 2 above) or by switching to an absolute path (form 3).

* `:default_locale` is the application-wide default locale. It can also be set at runtime with `Localize.put_default_locale/1`. The default is derived from the `LOCALIZE_DEFAULT_LOCALE` environment variable, then the `LANG` environment variable, then `:en`.

* `:supported_locales` is a list of locale identifiers that your application supports. Each entry is an atom matching a known CLDR locale (e.g. `:en`, `:"fr-CA"`), a wildcard string (e.g. `"en-*"`), a coverage-level keyword (`:modern`, `:moderate`, `:basic`), or a Gettext-style string (e.g. `"pt_BR"`, `"zh_Hans"`). POSIX-style underscores are normalised to hyphens and entries are resolved to their CLDR canonical form via likely-subtag resolution (e.g. `"pt_BR"` → `:pt`). Only exact matches (score 0) are accepted — entries that cannot be resolved log a warning with `domain: :localize` and are skipped. When set, `validate_locale/1` resolves locale identifiers against this list rather than all ~766 CLDR locales. Accessible at runtime via `Localize.supported_locales/0`. The default is `nil`.

* `:locale_provider` is a module implementing the `Localize.Locale.Provider` behaviour, for loading and caching per-locale data. The default is `Localize.Locale.Provider.PersistentTerm`.

* `:locale_cache_max_entries` is the maximum number of validated locales to hold in the ETS cache. A background sweeper runs every 10 seconds and evicts excess entries to prevent unbounded growth. The default is `1_000`.

* `:format_cache_max_entries` is the maximum number of compiled format patterns (number and date/time) to hold in the ETS cache. A background sweeper runs every 10 seconds and evicts excess entries to prevent unbounded growth. The default is `2_000`.

* `:otp_app` is an atom naming your application, and is **recommended**. Localize stores downloaded locale data under `Application.app_dir(<otp_app>, "priv/localize/locales")` — the same `:otp_app` convention used by `Ecto.Repo`, `Phoenix.Endpoint` and `Gettext.Backend`. It is resolved at every read, so it works correctly in mix tasks, `mix test` and releases without per-phase config. See [Configuring the locale cache directory](#configuring-the-locale-cache-directory) above for all three supported forms. The default is `nil`.

* `:locale_cache_dir` is the path to the on-disk cache. Absolute paths are used verbatim and override `:otp_app`. **Relative** paths are valid only when paired with `:otp_app` — they resolve against the app's runtime root via `Application.app_dir/2`. A bare relative path with no `:otp_app` raises `Localize.LocaleCacheDirError` at app start. See `Localize.Locale.Provider.locale_cache_dir/0`. The default is `Application.app_dir(:localize, "priv/localize/locales")`.

* `:allow_runtime_locale_download` determines whether locales not found in the on-disk cache are downloaded from the Localize CDN on first access. When `false`, missing locales return an error; use `mix localize.download_locales` to pre-populate the cache at build time. The default is `false`.

* `:nif` enables the optional NIF for faster Unicode normalisation and collation sort-key generation. It can also be enabled with the `LOCALIZE_NIF=true` environment variable at compile time. See `Localize.Nif` for details. The default is `false`.

* `:mf2_functions` is a map of custom MF2 formatting function modules. See `Localize.Message.Function`. The default is `%{}`.

* `:cacertfile` is the path to a custom CA certificate file for HTTPS connections, used when downloading locale data. The default is the system certificate store.

* `:https_proxy` is an HTTPS proxy URL. The `HTTPS_PROXY` environment variable is also read. The default is `nil`.

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
| `LOCALIZE_UNSAFE_HTTPS` | When set to a truthy value, disables SSL certificate verification for HTTPS connections (e.g., locale data downloads). The values `nil`, `NIL`, `false`, `FALSE`, an empty string, or unset all keep verification enabled. Intended for development behind corporate proxies with self-signed certificates. Do not use in production. |
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

* [localize_phone_number](https://hex.pm/packages/localize_phone_number) — Parsing, validation, and locale-aware formatting of international phone numbers, including territory detection and E.164 canonicalisation.

* [localize_address](https://hex.pm/packages/localize_address) — Postal address parsing and locale-aware formatting using CLDR territory data and locale-specific address layouts.

* [calendrical](https://hex.pm/packages/calendrical) — Localized month- and week-based calendars, and locale-aware parsing of dates, times, datetimes and date ranges across the CLDR calendars (Gregorian, Buddhist, Japanese imperial, Islamic, Persian, Hebrew, ROC).

* [localize_web](https://hex.pm/packages/localize_web) — Plugs that resolve the locale from an incoming request, localized routes, and HTML helpers for Phoenix applications.

* [localize_sql](https://hex.pm/packages/localize_sql) — Ecto types for the Localize data types, locale-aware `COLLATE` for PostgreSQL and SQLite queries, and PostgreSQL composite types with tag-guarded `sum`/`avg`/`min`/`max` aggregates for money and units of measure.

* [intl](https://hex.pm/packages/intl) — A higher-level, ergonomic API layer over `Localize` modeled on the ECMAScript `Intl` object. Provides a unified interface for number, date, time, relative time, list, and plural formatting.

### Form input components

Locale-aware Phoenix LiveView inputs, so a user can enter a value under their own conventions rather than fighting a browser control. These are the newest part of the family and still `0.1.x`. The [inputs playground](https://localize-inputs-playground.fly.dev) demonstrates them live against any locale.

* [localize_inputs_core](https://hex.pm/packages/localize_inputs_core) — Shared base for the input family: common exception types, Gettext backend, CSS variable tokens, and JS bootstrap helpers.

* [localize_number_inputs](https://hex.pm/packages/localize_number_inputs) — `<.number_input>` for decimals and integers, and `<.unit_input>` with a `<.unit_picker>` for a number paired with a unit of measure. AutoNumeric-backed live formatting.

* [localize_datetime_inputs](https://hex.pm/packages/localize_datetime_inputs) — `<.date_input>`, `<.date_range_input>`, `<.date_range_picker>` and `DatePickerLive`, built on `calendrical` for multi-calendar support.

### MessageFormat 2 tooling

* [mf2_treesitter](https://github.com/elixir-localize/mf2_treesitter) — The tree-sitter grammar for MessageFormat 2, giving incremental parsing and error recovery suitable for an editor.

* [mf2_wasm_editor](https://hex.pm/packages/mf2_wasm_editor) — That grammar compiled to WASM with a Phoenix LiveView hook, so an MF2 textarea highlights syntax in the browser with no per-keystroke round trip.

### Libraries that depend on Localize

* [ex_money version 6.0](https://hex.pm/packages/ex_money) which is updated to be based upon `Localize`.

* [ex_money_sql](https://hex.pm/packages/ex_money_sql) — Database serialization for `Money`, building its composite type and aggregates on `localize_sql`.

* [ex_money_input](https://hex.pm/packages/ex_money_input) — `<.money_input>` and `<.currency_picker>` components with an Ecto changeset bridge.

## Acknowledgements

* `Localize.Language` is based upon the [ex_cldr_language](https://github.com/elixir-cldr/cldr_languages) library by [@lostkobraki](https://github.com/lostkobrakai).

* `Localize.Territory` is based upon the [ex_cldr_territories](https://github.com/elixir-cldr/cldr_territories) library by [@Schultzer](https://github.com/Schultzer).

## License

Apache License 2.0, together with the Unicode License v3 for the CLDR and UCD data embedded in the package. See the [LICENSE](https://github.com/elixir-localize/localize/blob/v1.2.0/LICENSE.md) file for details, including which Unicode data is used and what it becomes.
