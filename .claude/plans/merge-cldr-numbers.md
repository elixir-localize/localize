# Plan: Merge and Adapt ex_cldr_numbers into Localize

## Overview

Migrate the number formatting functionality from `ex_cldr_numbers` into `Localize.Number` and supporting modules. Replace the backend code-generation architecture with runtime map lookups via `Localize.Locale.get/3`. Preserve the public API as closely as possible, removing only the `backend` parameter.

## Data Access Pattern

All locale-specific data is accessed at runtime via the provider:
```elixir
Localize.Locale.get(locale_id, [:number_formats])
Localize.Locale.get(locale_id, [:number_symbols])
Localize.Locale.get(locale_id, [:number_systems])
Localize.Locale.get(locale_id, [:minimum_grouping_digits])
```

NO ETF files, NO JSON files, NO compile-time locale data loading.

## Modules to Create

### Phase 1: Data Access Modules

**1. `Localize.Number.Symbol`** (`lib/localize/number/symbol.ex`)
* Struct: `decimal`, `group`, `exponential`, `infinity`, `list`, `minus_sign`, `nan`, `per_mille`, `percent_sign`, `plus_sign`, `superscripting_exponent`, `time_separator`
* `number_symbols_for(locale)` → `{:ok, %{system => Symbol.t()}}`
* `number_symbols_for(locale, number_system)` → `{:ok, Symbol.t()}`
* Data via `Localize.Locale.get(locale_id, [:number_symbols])`

**2. `Localize.Number.System`** (`lib/localize/number/system.ex`)
* `number_systems/0` — all known systems (supplemental, compile-time)
* `number_systems_for(locale)` → `{:ok, %{default: system, native: system}}`
* `number_system_for(locale, system_type)` — resolve type to name
* `number_system_from_locale(locale)` — from `-u-nu-` extension
* `to_system(number, system_name)` — transliterate digits
* `number_system_digits(system_name)` — digit string for system
* Data via `Localize.Locale.get(locale_id, [:number_systems])`

**3. `Localize.Number.Format`** (`lib/localize/number/format.ex`)
* Struct for format definitions (standard, currency, accounting, percent, etc.)
* `formats_for(locale, number_system)` → `{:ok, Format.t()}`
* `all_formats_for(locale)` — all formats keyed by number system
* `minimum_grouping_digits_for(locale)` — integer
* `default_grouping_for(locale)` — grouping metadata
* `currency_spacing(locale, number_system)` — spacing rules
* Data via `Localize.Locale.get(locale_id, [:number_formats])` and `[:minimum_grouping_digits]`

### Phase 2: Format Infrastructure

**4. `Localize.Number.Format.Compiler`** — parses format pattern strings into metadata (pure string parsing, no locale data)

**5. `Localize.Number.Format.Meta`** — struct for parsed format metadata (grouping, padding, rounding)

**6. `Localize.Number.Format.Options`** — validates/normalizes formatting options; removes `backend` param; default locale `:en`

### Phase 3: Utilities

**7. `Localize.Number.String`** — string utilities (padding, chunking)

**8. `Localize.Number.Transliterate`** — transliterate between number systems

### Phase 4: Formatters

**9. `Localize.Number.Formatter.Decimal`** — core decimal formatter

**10. `Localize.Number.Formatter.Short`** — short/long format (e.g., "1.2K")

**11. `Localize.Number.Formatter.Currency`** — currency-specific formatting

### Phase 5: Main Module and Parsing

**12. `Localize.Number`** (`lib/localize/number.ex`) — main public API:
* `to_string(number, options \\ [])` — main entry point (what MF2 interpreter calls)
* `to_string!(number, options \\ [])`
* `to_at_least_string/2`, `to_at_most_string/2`, `to_approx_string/2`, `to_range_string/2`
* `scan/2`, `parse/2`
* `resolve_currencies/2`, `resolve_currency/2`, `resolve_pers/2`, `resolve_per/1`

**13. `Localize.Number.Parser`** — locale-aware number parsing

### Phase 6: RBNF (deferred)

**14. `Localize.Number.Rbnf`** — rules-based number formatting (Roman numerals, spellout). Complex; defer to later phase.

## Key Conversion: Generated Function Heads → Map Lookups

**ex_cldr pattern (generated per locale):**
```elixir
def number_symbols_for(%LanguageTag{cldr_locale_name: "en"}) do
  {:ok, %{latn: %Symbol{decimal: ".", group: ",", ...}}}
end
def number_symbols_for(%LanguageTag{cldr_locale_name: "de"}) do
  {:ok, %{latn: %Symbol{decimal: ",", group: ".", ...}}}
end
```

**Localize pattern (single function, runtime lookup):**
```elixir
def number_symbols_for(locale) do
  locale_id = to_locale_id(locale)
  Localize.Locale.get(locale_id, [:number_symbols])
end
```

## Error Format

* `{:error, %ExceptionStruct{}}` (not ex_cldr's `{:error, {Module, message}}`)
* Reuse: `Localize.UnknownLocaleError`, `Localize.InvalidValueError`
* New if needed

## Implementation Order

1. Symbol → System → Format (data layer)
2. Format.Compiler → Format.Meta → Format.Options (format infrastructure)
3. String → Transliterate (utilities)
4. Formatter.Decimal → Formatter.Short → Formatter.Currency (engines)
5. Number → Parser (top-level API)
6. RBNF (optional/deferred)

## Files

```
lib/localize/number.ex
lib/localize/number/symbol.ex
lib/localize/number/system.ex
lib/localize/number/format.ex
lib/localize/number/format/compiler.ex
lib/localize/number/format/meta.ex
lib/localize/number/format/options.ex
lib/localize/number/formatter/decimal.ex
lib/localize/number/formatter/short.ex
lib/localize/number/formatter/currency.ex
lib/localize/number/transliterate.ex
lib/localize/number/string.ex
lib/localize/number/parser.ex
test/localize/number_test.exs
test/localize/number/symbol_test.exs
test/localize/number/system_test.exs
test/localize/number/format_test.exs
test/localize/number/transliterate_test.exs
test/localize/number/parser_test.exs
```
