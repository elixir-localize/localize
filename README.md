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

## Optional NIF

An optional NIF provides faster Unicode normalisation and collation sort-key generation. Enable it at compile time:

```bash
LOCALIZE_NIF=true mix compile
```

Or in your config:

```elixir
config :localize, :nif, true
```

See `Localize.Nif` for details.

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/localize).

## License

Apache License 2.0. See the [LICENSE](LICENSE) file for details.
