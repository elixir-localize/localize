# Locales, language tags, and configuration

Most common calls:

| Task | Call |
|------|------|
| Validate user locale input | `Localize.validate_locale("pt-br")` → `{:ok, %LanguageTag{}}` |
| Set process locale | `Localize.put_locale(locale)` |
| Scoped locale | `Localize.with_locale("de", fn -> ... end)` |
| Negotiate Accept-Language | `Localize.LanguageTag.best_match(wanted, supported)` |
| Country name | `Localize.Territory.display_name(:NZ, locale: :fr)` |
| Locale's currency | `Localize.Currency.currency_from_locale(locale)` |

## validate_locale/1

The single entry point for turning any locale identifier (string, atom, or `LanguageTag`) into a validated tag. In one cached pass it parses BCP 47 (accepting POSIX underscores), resolves deprecated aliases (`iw` → `he`), maximizes likely subtags (so `:script`/`:territory` are always populated), decodes `-u-`/`-t-` extensions into structs, and matches against the supported-locales list. Results are ETS-cached (~1µs on repeat), so validating per-request is fine — but pass the resulting `LanguageTag` around rather than re-validating strings.

```elixir
{:ok, tag} = Localize.validate_locale("pt-br")
{tag.canonical_locale_id, tag.cldr_locale_id}
#=> {"pt-BR", :pt}
{:ok, tag} = Localize.validate_locale("iw")                        # deprecated alias resolves
{tag.language, tag.canonical_locale_id, tag.cldr_locale_id}
#=> {:he, "he", :he}
{:ok, tag} = Localize.validate_locale("en")                        # likely subtags always populated
{tag.language, tag.script, tag.territory}
#=> {:en, :Latn, :US}
```

Key `LanguageTag` fields: `:language` / `:script` / `:territory` / `:language_variants` (the parsed subtags); `:locale` (a `LanguageTag.U` struct of `-u-` keywords); `:requested_locale_id` (verbatim input); `:canonical_locale_id` (canonical syntax, preserving what the caller asked for); `:cldr_locale_id` (the CLDR data locale actually serving it — the atom to use as a cache/lookup key).

A real but data-less language resolves to root rather than erroring or guessing wrong; garbage input errors:

```elixir
{:ok, tag} = Localize.validate_locale("tlh")                       # Klingon: valid tag, no CLDR data
{tag.canonical_locale_id, tag.cldr_locale_id}
#=> {"tlh", :und}
Localize.validate_locale("xyzzy")
#=> {:error, %Localize.InvalidLocaleError{locale_id: "xyzzy"}}
```

`validate_locale/1` is safe on untrusted input (no `String.to_atom`); a locale not in `supported_locales` (when configured) returns `Localize.UnknownLocaleError`. `LanguageTag.parse/1` (syntax only) and `LanguageTag.new/1` (resolved, uncached, ignores supported-locales) exist for tooling; prefer `validate_locale/1` in applications.

## -u- extension keys

`-u-` keywords ride along on the tag and are honored automatically by the relevant formatters — one locale string can carry a user's complete formatting preferences:

| Key | Drives | Example |
|-----|--------|---------|
| `nu` | digit system in numbers | `"ar-u-nu-arab"` → arabic digits |
| `hc` | hour cycle | `"en-u-hc-h23"` → 24-hour times |
| `co` | collation type | `"zh-u-co-pinyin"` sorting |
| `cu` | currency | `"en-u-cu-eur"` → € for `format: :currency` |
| `cf` | currency format | `accounting` for negative-parens |
| `ks`/`kn`/`kf`... | collation strength/numeric/case-first | see collation.md |
| `rg` | region override for territory-derived data | `"en-u-rg-dezzzz"` |
| `ca` | calendar preference (parsed; does not convert ISO dates — see dates-times.md) | |
| `fw` | first day (parsed into `tag.locale.fw`; not consumed by `first_day_for_locale/1`) | |

```elixir
Localize.Number.to_string(1234, locale: "ar-u-nu-arab")
#=> {:ok, "١٬٢٣٤"}
Localize.Time.to_string(~T[14:30:00], locale: "en-u-hc-h23")
#=> {:ok, "14:30:00"}
Localize.Number.to_string(100, format: :currency, locale: "en-u-cu-eur")
#=> {:ok, "€100.00"}
{:ok, tag} = Localize.validate_locale("th-u-nu-thai-ca-buddhist")
{tag.locale.nu, tag.locale.ca}
#=> {:thai, :buddhist}
Localize.LanguageTag.to_string(tag)                                # re-encodes in canonical order
#=> "th-u-ca-buddhist-nu-thai"
```

## Process locale — put/get/with

Every formatter's `:locale` option defaults to `Localize.get_locale()`. Set it once per process (a Phoenix plug is the natural place) and drop `:locale` plumbing everywhere else. `with_locale/2` sets and restores around a function:

```elixir
{:ok, _} = Localize.put_locale("fr")
Localize.get_locale().cldr_locale_id
#=> :fr
Localize.with_locale("de", fn -> Localize.Number.to_string(1234.5) end)
#=> {:ok, "1.234,5"}
Localize.get_locale().cldr_locale_id                               # with_locale restored :fr
#=> :fr
{:ok, _} = Localize.put_locale(:en)                                # back to :en for the rest of this file
Localize.get_locale().cldr_locale_id
#=> :en
```

When no process locale is set, `get_locale/0` falls back to the default locale, resolved once in this order: `LOCALIZE_DEFAULT_LOCALE` env var → `config :localize, default_locale:` → `LANG` env var (POSIX form converted) → `:en`. `Localize.put_default_locale/1` changes it at runtime.

## Configuration

Zero config is valid: `:en` and `:und` ship inside the package and always work, even offline. Typical production setup:

```elixir
config :localize,
  default_locale: :en,
  supported_locales: [:en, :fr, :de, :ja, "zh-*"],   # atoms, "wildcards-*", coverage levels (:modern), or "pt_BR" strings
  otp_app: :my_app                                    # anchor for the on-disk locale cache
```

Key config entries:

* `:supported_locales` — bounds `validate_locale/1` matching to what the app can serve (unset = all ~766 CLDR locales). Entries resolve via likely subtags; unresolvable ones log a warning and are skipped. Read back with `Localize.supported_locales/0`. Derive from Gettext in `config/runtime.exs` with `Gettext.known_locales(MyApp.Gettext)`.
* Cache directory (three forms): `otp_app: :my_app` alone (recommended — caches under `Application.app_dir(:my_app, "priv/localize/locales")`, correct in mix tasks, tests, and releases); `otp_app:` + relative `locale_cache_dir:` (custom subpath); absolute `locale_cache_dir:` (used verbatim). A bare relative `locale_cache_dir` without `otp_app` raises `Localize.LocaleCacheDirError` at boot.
* `:allow_runtime_locale_download` — default `false`: locales missing from the cache return an error. Pre-populate at build time with `mix localize.download_locales` (downloads `supported_locales`; or name locales explicitly; `--all` for everything). When `true`, missing locales download from the CDN on first use and are verified against the SHA-256 hash manifest bundled with the package — a tampered or corrupted file fails the download rather than loading.
* `:locale_provider` — module implementing `Localize.Locale.Provider` (default persistent-term provider). `:format_cache_max_entries` — compiled-pattern cache bound (default 2000, swept every 10s).
* `:nif` / `LOCALIZE_NIF=true` — optional ICU4C NIF for normalization, collation sort keys, and `backend: :nif` formatting. Pure Elixir remains the default.
* `:cacertfile`, `:https_proxy` (also `HTTPS_PROXY` env) — TLS/proxy settings for locale downloads.

Supervision: by default the `:localize` OTP app boots its own tree (data loader, locale ETS, cache sweeper, format cache, collation tables). To control ordering yourself, declare the dep `{:localize, "~> x.y", runtime: false}` and put `Localize.Supervisor` in your own `children` list before anything that formats at startup.

## Display names

Every module follows the same shape — `display_name(code, options)` with `:locale` and `:style`, plus a `!` variant. Styles are CLDR-recorded alternatives, not guaranteed widths; a missing style is an error, not a fallback.

```elixir
Localize.Territory.display_name(:NZ, locale: :fr)
#=> {:ok, "Nouvelle-Zélande"}
Localize.Territory.display_name(:GB, style: :short)
#=> {:ok, "UK"}
Localize.Territory.display_name(:US, style: :variant)              # no variant recorded for US
#=> {:error, %Localize.UnknownStyleError{style: :variant, territory: :US}}
Localize.Language.display_name("en-GB")                            # canonical, not maximized: "en" stays "English"
#=> {:ok, "British English"}
Localize.Script.display_name(:Cyrl, locale: :fr)
#=> {:ok, "cyrillique"}
Localize.Currency.display_name(:USD, locale: :de)
#=> {:ok, "US-Dollar"}
Localize.Currency.pluralize(3, :USD)
#=> {:ok, "US dollars"}
Localize.Locale.LocaleDisplay.display_name("en-US-u-ca-buddhist")  # full TR35 composition
#=> {:ok, "English (United States, Buddhist Calendar)"}
Localize.Locale.LocaleDisplay.display_name("nl-BE", language_display: :dialect)
#=> {:ok, "Flemish"}
```

For pickers and select lists, fetch whole inventories at once: `Localize.Territory.territory_names_for/1` (map of code → style-keyed names), `Localize.Language.language_names_for/1`, `Localize.Script.script_names_for/1`. The vocabulary is uniform library-wide: `known_*` = the CLDR universe, `supported_*` = your configuration, `*_for` = localized into a display locale (`Localize.Territory.territories_for/1` returns just the codes with names in that locale).

```elixir
{:ok, names} = Localize.Territory.territory_names_for(locale: :fr)
names[:NZ]
#=> %{variant: "Aotearoa (Nouvelle-Zélande)", standard: "Nouvelle-Zélande"}
{:ok, names} = Localize.Language.language_names_for(locale: :fr)
names["en"]
#=> %{standard: "anglais"}
```

## Territory-derived defaults

The locale's territory (or its `-u-rg-` override) determines sensible defaults — currency, measurement system, week start — so a validated locale answers most regional questions without extra configuration:

```elixir
Localize.Currency.currency_from_locale("ja")
#=> {:ok, :JPY}
Localize.Currency.currency_from_locale("en-u-cu-chf")              # -u-cu wins over territory
#=> {:ok, :CHF}
Localize.Territory.territory_from_locale("en-GB")
#=> {:ok, :GB}
Localize.Territory.territory_from_locale("en-u-rg-dezzzz")         # region-override key
#=> {:ok, :DE}
Localize.Unit.measurement_system_for_territory(:US)                # also :temperature, :paper_size categories
#=> :us
Localize.Unit.measurement_system_for_territory(:DE)
#=> :metric
Localize.Calendar.first_day_for_territory(:DE)                     # ISO day number: 1 = Monday
#=> 1
Localize.Calendar.first_day_for_territory(:US)
#=> 7
```

## Locale negotiation

`best_match/2,3` implements CLDR language matching for negotiating an `Accept-Language` header against the locales you ship. The score is the CLDR match distance: 0 exact, small = regional variant, 80+ = different language. By default some match is always returned (per spec, a distant match beats none); pass a threshold for strictness:

```elixir
Localize.LanguageTag.best_match("en-AU", ["en", "en-GB", "fr"])
#=> {:ok, "en-GB", 3}
Localize.LanguageTag.best_match("pt-PT", ["pt-BR", "es", "fr"])    # pt-BR beats unrelated languages
#=> {:ok, "pt-BR", 5}
Localize.LanguageTag.best_match("ja", ["en", "fr"], 20)            # strict: no acceptable match
#=> {:error, %Localize.LocaleMatchError{desired: "ja", threshold: 20}}
Localize.LanguageTag.match_distance("en", "fr")
#=> 84
```

## Inventory checks

```elixir
Localize.available_locale_id?(:en)                                 # is it a CLDR locale at all?
#=> true
Localize.available_locale_id?("tlh")
#=> false
length(Localize.all_locale_ids())                                  # the full CLDR universe (also all_locale_ids(:modern))
#=> 766
```
