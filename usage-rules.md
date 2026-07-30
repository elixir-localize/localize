# Localize usage rules

Rules for LLM coding agents using `Localize` as a dependency. These are not exhaustive — see the HexDocs guides for full reference.

## Core conventions

* All public functions that take a *message, locale, number, unit or other user value* return `{:ok, result}` or `{:error, exception}`. Pattern match with `case`/`with`, never `try/rescue`. The exception is a struct (e.g. `%Localize.UnknownLocaleError{}`), not a string.

* The exception is the handful of functions that operate on an already-parsed AST rather than on source: they have no message to attach to an exception, so they report a plain reason instead. `Localize.Message.Validator.validate/1` returns `:ok` or `{:error, {reason, detail}}`, and `Localize.Message.JSON.from_json/1` returns `{:error, binary}`. The message-level entry points convert these into a `%Localize.FormatError{}` carrying the source — so `Localize.Message.format/3` and `canonical_message/2` still follow the rule above.

* Bang variants (`to_string!/2`, `validate_locale!/1`, etc.) exist for the rare cases where raising is preferred on error.

* Never construct locale identifiers by hand and pass them around as raw strings. Call `Localize.validate_locale/1` once and pass the resulting `%Localize.LanguageTag{}` struct, or use a validated atom (`:en`, `:"en-AU"`).

* Locale identifiers are atoms in canonical form: `:en`, `:"en-AU"`, `:"zh-Hant"`. Strings (`"en-AU"`) are also accepted by every public function and validated on the way in. Do not mix `_` (POSIX) and `-` (BCP 47) — Localize accepts both but normalizes to `-`.

* There is no compile-time backend module. Do not write `use Localize` or `defmodule MyApp.Localize`. All 766 CLDR locales are available immediately.

## Module map

| Task | Use |
|---|---|
| **Format any supported value (polymorphic)** | `Localize.to_string/2` (delegates via `Localize.Chars` protocol) |
| Numbers, decimals, percentages, currencies | `Localize.Number.to_string/2` |
| Dates | `Localize.Date.to_string/2` |
| Times | `Localize.Time.to_string/2` |
| Datetimes | `Localize.DateTime.to_string/2` |
| Date/time intervals | `Localize.Interval.to_string/3` |
| Relative time ("in 3 days") | `Localize.DateTime.Relative.to_string/2` |
| Units of measure | `Localize.Unit.new/2` + `Localize.Unit.to_string/2` |
| Lists ("a, b, and c") | `Localize.List.to_string/2` |
| Territory display names, flags | `Localize.Territory.display_name/2`, `Localize.Territory.unicode_flag/1` |
| Language display names | `Localize.Language.display_name/2` |
| Locale display names | `Localize.Locale.LocaleDisplay.display_name/2` |
| Currency metadata | `Localize.Currency.*` |
| String sorting / collation | `Localize.Collation.sort/2`, `Localize.Collation.compare/3` |
| MessageFormat 2 / pluralization | `Localize.Message.format/3` |
| Custom MF2 functions | `Localize.Message.Function` behaviour + `:functions` option or `config :localize, :mf2_functions` |
| Calendar names (months, days, eras) | `Localize.Calendar.display_name/3` |

## Locale management

* The current locale is per-process. Set it once at the start of a request (e.g. in a Plug) with `Localize.put_locale(:de)`. Every formatting and parsing function then defaults its `:locale` option to `Localize.get_locale()`.

* For temporary locale changes inside a function, use `Localize.with_locale/2` rather than save/put/restore.

* The application-wide default locale is resolved (in order) from: `LOCALIZE_DEFAULT_LOCALE` env var → `config :localize, default_locale: ...` → `LANG` env var → `:en`. Set this at deploy time, not in code.

## Common idioms

```elixir
# Numbers
{:ok, "1,234.5"}     = Localize.Number.to_string(1234.5)
{:ok, "1.234,5"}     = Localize.Number.to_string(1234.5, locale: :de)
{:ok, "$1,234.56"}   = Localize.Number.to_string(1234.56, currency: :USD)
{:ok, "56%"}         = Localize.Number.to_string(0.56, format: :percent)

# Dates and times
{:ok, "Jul 10, 2025"}        = Localize.Date.to_string(~D[2025-07-10])
{:ok, "10. Juli 2025"}       = Localize.Date.to_string(~D[2025-07-10], locale: :de, format: :long)

# Units
{:ok, unit} = Localize.Unit.new(42, "kilometer")
{:ok, "42 km"}              = Localize.Unit.to_string(unit, format: :short)

# Lists
{:ok, "apple, banana, and cherry"} =
  Localize.List.to_string(["apple", "banana", "cherry"])

# Collation
["apple", "banana", "Cherry"] =
  Localize.Collation.sort(["banana", "apple", "Cherry"])

# Pluralization via MessageFormat 2
Localize.Message.format(
  ~S".input {$count :integer}\n.match $count\n  one {{{$count} item}}\n  *   {{{$count} items}}",
  %{"count" => 3}
)
#=> {:ok, "3 items"}

# Validation
{:ok, %Localize.LanguageTag{cldr_locale_id: :en}} = Localize.validate_locale("en-US")

# Polymorphic formatting via Localize.Chars
# Same call site, different value types — dispatch is by protocol.
{:ok, "1.234,5"} = Localize.to_string(1234.5, locale: :de)
{:ok, "Jul 10, 2025"} = Localize.to_string(~D[2025-07-10], locale: :en)
{:ok, "42 km"} = Localize.to_string(unit, format: :short, locale: :en)
"1.234,5" = Localize.to_string!(1234.5, locale: :de)   # bang variant
```

`Localize.to_string/{1,2}` and `Localize.to_string!/{1,2}` delegate to the `Localize.Chars` protocol, which has built-in implementations for `Integer`, `Float`, `Decimal`, `Date`, `Time`, `DateTime`, `NaiveDateTime`, `Range`, `BitString`, `List`, `Localize.Unit`, `Localize.Duration`, `Localize.LanguageTag`, and `Localize.Currency`. Unknown types raise `Protocol.UndefinedError`. Use the polymorphic entry point when the value's type isn't known until runtime; use the dedicated module functions (`Localize.Number.to_string/2`, etc.) when the type is known and you want unambiguous error messages.

## MF2 in source code

* For MF2 messages embedded in Elixir, use the `~M` sigil (uppercase). It validates the message at compile time with precise line/column errors and canonicalises the string so `gettext` keys stay stable regardless of developer whitespace. Do not use the lowercase `~m` — interpolation via `#{…}` breaks MF2's grammar.

* Enable the formatter plugin in `.formatter.exs` to auto-canonicalise `~M` sigils and `.mf2` files on `mix format`:

  ```elixir
  [plugins: [Localize.Message.Formatter.Plugin]]
  ```

  The plugin is idempotent — `mix format --check-formatted` is safe to run in CI.

## Performance rules

* For hot loops formatting many numbers with the same locale and format, pre-validate options once via `Localize.Number.Format.Options.validate_options/2` and pass the resulting struct. This skips per-call locale resolution and currency lookup. Speedup is ~3x for plain decimals and ~50x for currency formatting.

* Set the process locale once with `Localize.put_locale/1` rather than passing `:locale` as an option on every call.

* `Localize.validate_locale/1` is cached in ETS — first call ~50µs, subsequent calls ~1µs. Pre-validate locales you know you will need at app startup.

## Configuration

```elixir
# config/config.exs — minimum useful config
config :localize,
  default_locale: :en,
  supported_locales: [:en, :fr, :de, :ja, "es-*"]
```

* `:supported_locales` constrains `validate_locale/1` to your declared subset. If unset (the default), all 766 CLDR locales are valid. Wildcard strings (`"es-*"`) expand to every matching locale.

* Runtime locale downloading is **off by default**. Set `allow_runtime_locale_download: true` to enable on-demand downloading from the Localize CDN. Otherwise pre-populate the cache at build time with `mix localize.download_locales` (downloads the configured `:supported_locales`) or `mix localize.download_locales en fr de` for specific locales. Locale data is loaded lazily into `:persistent_term` on first access.

## Things not to do

* Do not write `Localize.Number.to_string!(value)` and discard the locale — at least pass `locale: Localize.get_locale()` if you have not set the process locale, or accept the application default.

* Do not pattern match on the old ex_cldr error shape `{:error, {Module, "string"}}`. Localize returns `{:error, %Exception{}}` — match on the struct or call `Exception.message/1`.

* Do not call `String.to_atom/1` on user-supplied locale strings. Use `Localize.validate_locale/1`, which canonicalizes and validates without atom-table pollution.

* Do not assume `Localize.Territory.territory_codes/1` returns a list of territories — it returns a *map* of ISO 3166 code mappings. Use `Localize.Territory.individual_territories/0` for the sorted list of leaf territory atoms.

* Do not reach for `Cldr.*` modules or backend modules. Localize replaces the entire `ex_cldr_*` family with a single dependency and no compile-time configuration.

## Companion packages

When the user needs functionality outside Localize's core CLDR scope:

* `localize_person_names` — TR35 Part 8 person name formatting.

* `localize_phonenumber` — phone number parsing and formatting.

* `localize_address` — postal address formatting.

* `intl` — higher-level ergonomic API modeled on the JavaScript `Intl` object.
