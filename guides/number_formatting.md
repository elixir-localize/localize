# Number Formatting Guide

This guide explains how to use `Localize.Number` for locale-aware number formatting and parsing.

## Overview

`Localize.Number.to_string/2` is the primary function for formatting numbers. It accepts an integer, float, or `Decimal` value and returns a locale-formatted string. The formatting engine uses CLDR number format patterns, locale-specific symbols (grouping separator, decimal separator, percent sign, etc.), and number system digit sets.

```elixir
iex> Localize.Number.to_string(1234567.89)
{:ok, "1,234,567.89"}

iex> Localize.Number.to_string(1234567.89, locale: :de)
{:ok, "1.234.567,89"}

iex> Localize.Number.to_string(1234567.89, locale: :hi)
{:ok, "12,34,567.89"}
```

## Formatting types

### Standard decimal

The default format. Uses the locale's standard pattern with grouping separators and decimal point:

```elixir
iex> Localize.Number.to_string(1234567.89)
{:ok, "1,234,567.89"}
```

### Percentage

Multiplies by 100 and appends the locale's percent sign:

```elixir
iex> Localize.Number.to_string(0.456, format: :percent)
{:ok, "46%"}
```

### Scientific notation

Formats in exponential notation:

```elixir
iex> Localize.Number.to_string(1234567.89, format: :scientific)
{:ok, "1.23456789E6"}
```

### Currency

Formats with a currency symbol, using the currency's standard decimal places. Specifying `:currency` automatically selects the currency format pattern:

```elixir
iex> Localize.Number.to_string(1234.56, currency: :USD)
{:ok, "$1,234.56"}

iex> Localize.Number.to_string(1234.56, currency: :EUR, locale: :de)
{:ok, "1.234,56\u00A0€"}

iex> Localize.Number.to_string(1234.56, currency: :JPY, locale: :ja)
{:ok, "￥1,235"}
```

### Accounting

Like currency but wraps negative values in parentheses instead of using a minus sign:

```elixir
iex> Localize.Number.to_string(1234.56, format: :accounting, currency: :USD)
{:ok, "$1,234.56"}

iex> Localize.Number.to_string(-1234.56, format: :accounting, currency: :USD)
{:ok, "($1,234.56)"}
```

### Short (compact) formats

Abbreviate large numbers with magnitude suffixes:

```elixir
iex> Localize.Number.to_string(1234567, format: :decimal_short)
{:ok, "1.2M"}

iex> Localize.Number.to_string(1234567, format: :decimal_short, locale: :de)
{:ok, "1,2\u00A0Mio."}

iex> Localize.Number.to_string(1234567, format: :decimal_short, locale: :ja)
{:ok, "123万"}

iex> Localize.Number.to_string(1234567, format: :currency_short, currency: :USD)
{:ok, "$1.2M"}
```

### Long (word) formats

Spell out the magnitude in words:

```elixir
iex> Localize.Number.to_string(1234567, format: :decimal_long)
{:ok, "1.2 million"}

iex> Localize.Number.to_string(1234567, format: :decimal_long, locale: :de)
{:ok, "1,2 Millionen"}

iex> Localize.Number.to_string(1234567, format: :currency_long, currency: :USD)
{:ok, "1,234,567 US dollars"}
```

### Rule-based number formatting (RBNF)

Algorithmic formatting using named rule sets. Used for spellout, ordinals, Roman numerals, and other systems that cannot be expressed as simple patterns:

```elixir
iex> Localize.Number.Rbnf.to_string(123, :spellout_cardinal, locale: :en)
{:ok, "one hundred twenty-three"}

iex> Localize.Number.Rbnf.to_string(42, :spellout_ordinal, locale: :en)
{:ok, "forty-second"}

iex> Localize.Number.Rbnf.to_string(2024, "roman_upper", locale: :und)
{:ok, "MMXXIV"}
```

Available RBNF rules vary by locale. Query them with:

```elixir
iex> {:ok, rules} = Localize.Number.Rbnf.rule_names_for_locale(:en)
iex> rules
["digits_ordinal", "spellout_cardinal", "spellout_numbering",
 "spellout_numbering_year", "spellout_ordinal", "spellout_cardinal_verbose",
 "spellout_numbering_verbose", "spellout_ordinal_verbose"]
```

The root locale (`:und`) provides universal rules like `roman_upper`, `roman_lower`, `hebrew`, `ethiopic`, `greek_upper`, `greek_lower`, `armenian_upper`, `armenian_lower`, `cyrillic_lower`, `georgian`, and `tamil`.

### Range formatting

Format numeric ranges with locale-appropriate separators:

```elixir
iex> Localize.Number.to_range_string(3, 5)
{:ok, "3–5"}

iex> Localize.Number.to_range_string(1000, 5000)
{:ok, "1,000–5,000"}

iex> Localize.Number.to_range_string(3, 5, locale: :ja)
{:ok, "3～5"}
```

Related functions for approximate and bounded values:

```elixir
iex> Localize.Number.to_approximately_string(42)
{:ok, "~42"}

iex> Localize.Number.to_at_least_string(100)
{:ok, "100+"}

iex> Localize.Number.to_at_most_string(50)
{:ok, "≤50"}
```

## How format resolution works

When you call `to_string/2`, the `:format` option determines which CLDR pattern is used. The resolution follows these rules:

### Standard format names

Atom values map to named patterns in the locale's number format data:

| Format atom | Pattern (English) | Description |
|-------------|-------------------|-------------|
| `:standard` | `#,##0.###` | Default decimal format. |
| `:currency` | `¤#,##0.00` | Currency with symbol prefix. |
| `:accounting` | `¤#,##0.00;(¤#,##0.00)` | Parentheses for negative. |
| `:percent` | `#,##0%` | Percentage. |
| `:scientific` | `#E0` | Scientific notation. |
| `:decimal_short` | (magnitude table) | Compact form: "1M", "2K". |
| `:decimal_long` | (magnitude table) | Word form: "1 million". |
| `:currency_short` | (magnitude table) | Compact currency: "$1M". |
| `:currency_long` | (pattern) | Pluralized: "123 US dollars". |

### Custom format patterns

Pass a pattern string directly:

```elixir
iex> Localize.Number.to_string(1234.5, format: "#,##0.00")
{:ok, "1,234.50"}

iex> Localize.Number.to_string(1234.5, format: "0.000")
{:ok, "1234.500"}

iex> Localize.Number.to_string(42, format: "000")
{:ok, "042"}
```

### Currency auto-selection

When the `:currency` option is set and `:format` is `:standard` (or omitted), the format is automatically changed to `:currency`. You only need to explicitly set `format: :accounting` if you want accounting-style negatives:

```elixir
iex> # These are equivalent:
iex> Localize.Number.to_string(42, currency: :USD)
{:ok, "$42.00"}

iex> Localize.Number.to_string(42, format: :currency, currency: :USD)
{:ok, "$42.00"}
```

### RBNF rule names

For rule-based formatting, use `Localize.Number.Rbnf.to_string/3` with a rule name atom:

```elixir
iex> Localize.Number.Rbnf.to_string(42, :spellout_cardinal, locale: :en)
{:ok, "forty-two"}
```

## Format patterns

CLDR format patterns are strings that describe how a number should be rendered. Understanding them is useful when customising output or reading locale data.

### Pattern structure

A pattern has the form `positive_pattern;negative_pattern`. If the negative pattern is omitted, the positive pattern is prefixed with the locale's minus sign for negative values.

Example: `¤#,##0.00;(¤#,##0.00)` — positive values use `¤#,##0.00`, negative values are wrapped in parentheses.

### Symbol reference

| Symbol | Meaning | Example |
|--------|---------|---------|
| `0` | Digit, show zero if absent. | `0.00` → "1.50" |
| `#` | Digit, omit if zero. | `#.##` → "1.5" |
| `.` | Decimal separator (locale-specific). | `#.##` → "1,5" (German) |
| `,` | Grouping separator (locale-specific). | `#,##0` → "1,234" |
| `E` | Exponent separator. | `0.###E0` → "1.235E3" |
| `%` | Multiply by 100 and show percent sign. | `#%` → "46%" |
| `‰` | Multiply by 1000 and show per-mille sign. | `#‰` → "456‰" |
| `¤` | Currency symbol placeholder. | `¤#,##0` → "$1,234" |
| `¤¤` | ISO currency code. | `¤¤#,##0` → "USD1,234" |
| `;` | Separates positive and negative subpatterns. | |
| `+` | Plus sign in exponent. | `0E+0` → "1E+3" |
| `-` | Minus sign. | |
| `@` | Significant digit. | `@@##` → "12.34" |

### Grouping

The grouping pattern is read from right to left in the integer part. `#,##0` means groups of 3. The Indian pattern `#,##,##0` means the first group is 3 digits and subsequent groups are 2 digits, producing "12,34,567" for Hindi.

### Currency symbol

The `¤` placeholder is replaced at format time with the currency symbol. The placement varies by locale — English puts it before the number (`$1,234`), German puts it after with a non-breaking space (`1.234 €`).

## Number systems

CLDR defines two categories of number systems:

* **Numeric** — a set of 10 digit characters. The formatter transliterates Latin digits (0–9) to the target script's digits. Examples: `:latn` (0123456789), `:arab` (٠١٢٣٤٥٦٧٨٩), `:thai` (๐๑๒๓๔๕๖๗๘๙).

* **Algorithmic** — numbers are formatted by rules, not digit substitution. Examples: `:roman` (Roman numerals), `:hans` (Chinese ideographs). Algorithmic systems use RBNF.

Each locale defines up to four number system types: `:default`, `:native`, `:traditional`, and `:finance`. For most Western locales, all four resolve to `:latn`.

```elixir
iex> Localize.Number.System.number_systems_for(:ar)
{:ok, %{default: :latn, native: :arab}}

iex> Localize.Number.to_string(1234, number_system: :arab, locale: :ar)
{:ok, "١٬٢٣٤"}
```

## How locale influences formatting

### Locale-specific patterns

Different locales use different format patterns, grouping rules, and symbols:

| Locale | Standard pattern | Decimal | Grouping | Example |
|--------|-----------------|---------|----------|---------|
| `:en` | `#,##0.###` | `.` | `,` | 1,234,567.89 |
| `:de` | `#,##0.###` | `,` | `.` | 1.234.567,89 |
| `:fr` | `#,##0.###` | `,` | ` ` (narrow no-break space) | 1 234 567,89 |
| `:hi` | `#,##,##0.###` | `.` | `,` | 12,34,567.89 |
| `:ja` | `#,##0.###` | `.` | `,` | 1,234,567.89 |

### Unicode extension keys

BCP 47 locale identifiers can encode number formatting preferences:

**`-u-nu-`** — number system:

```elixir
iex> Localize.Number.to_string(1234, locale: "ar-u-nu-arab")
{:ok, "١٬٢٣٤"}

iex> Localize.Number.to_string(1234, locale: "th-u-nu-thai")
{:ok, "๑,๒๓๔"}
```

**`-u-cu-`** — currency:

When a validated locale has a `-u-cu-` extension and `:currency` is not explicitly provided in options, the locale's currency is used.

### Locale-specific compact forms

Short and long formats vary dramatically by locale. Japanese uses 万 (ten-thousand) and 億 (hundred-million) instead of the Western K/M/B:

```elixir
iex> Localize.Number.to_string(1234567, format: :decimal_short, locale: :en)
{:ok, "1.2M"}

iex> Localize.Number.to_string(1234567, format: :decimal_short, locale: :ja)
{:ok, "123万"}

iex> Localize.Number.to_string(1234567, format: :decimal_short, locale: :de)
{:ok, "1,2\u00A0Mio."}
```

## Options reference

All options accepted by `Localize.Number.to_string/2`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:locale` | atom, string, or `LanguageTag` | `Localize.get_locale()` | Locale for patterns, symbols, and plural rules. |
| `:format` | atom or pattern string | `:standard` | Format style or custom pattern. See format table above. |
| `:currency` | atom | `nil` | ISO 4217 currency code. Automatically selects currency format. |
| `:number_system` | atom | `:default` | Number system name (`:latn`, `:arab`, etc.) or type (`:default`, `:native`). |
| `:fractional_digits` | integer | `nil` | Set both min and max fractional digits. |
| `:min_fractional_digits` | integer | `nil` | Minimum trailing zeros after decimal. Overrides `:fractional_digits` for the minimum. |
| `:max_fractional_digits` | integer | `nil` | Maximum decimal digits (rounds to this). Overrides `:fractional_digits` for the maximum. |
| `:maximum_integer_digits` | integer | `nil` | Maximum integer digits to display. |
| `:rounding_mode` | atom | `:half_even` | One of `:down`, `:up`, `:half_up`, `:half_down`, `:half_even`, `:ceiling`, `:floor`. |
| `:round_nearest` | integer | `nil` | Round to nearest increment (e.g., 5 for rounding to nearest 5). |
| `:minimum_grouping_digits` | integer | `0` | Minimum integer digits before grouping is applied. |
| `:currency_symbol` | atom or string | `nil` | Override currency symbol display: `:symbol`, `:narrow`, `:iso`, or a custom string. |
| `:currency_digits` | atom | `:accounting` | How to determine currency decimal places: `:accounting`, `:cash`, or `:iso`. |
| `:wrapper` | function | `nil` | `fn string, type -> string end` — wrap formatted components for HTML/markup. |

### Fractional digit examples

```elixir
iex> Localize.Number.to_string(1234.5, fractional_digits: 4)
{:ok, "1,234.5000"}

iex> Localize.Number.to_string(1234.56789, max_fractional_digits: 2)
{:ok, "1,234.57"}

iex> Localize.Number.to_string(1234.5, min_fractional_digits: 3)
{:ok, "1,234.500"}

iex> Localize.Number.to_string(1234.56789, min_fractional_digits: 1, max_fractional_digits: 3)
{:ok, "1,234.568"}
```

### Rounding mode examples

```elixir
iex> Localize.Number.to_string(2.5, fractional_digits: 0, rounding_mode: :half_even)
{:ok, "2"}

iex> Localize.Number.to_string(2.5, fractional_digits: 0, rounding_mode: :half_up)
{:ok, "3"}

iex> Localize.Number.to_string(2.5, fractional_digits: 0, rounding_mode: :ceiling)
{:ok, "3"}
```

## Performance and optimization

`to_string/2` accepts either a keyword list or a pre-validated `Localize.Number.Format.Options` struct. The keyword list path resolves the number system, loads format patterns, resolves currency data, and builds metadata on every call. Locale validation itself is cached in ETS and is fast (~1µs), but the remaining options resolution — format pattern lookup, currency data loading, symbol resolution — still adds measurable overhead, especially for currency formatting.

For high-throughput formatting (rendering a table of thousands of numbers, batch processing), call `Localize.Number.Format.Options.validate_options/2` once to build an options struct, then pass it to `to_string/2` for each number. The first argument is a representative number (use `0` for a positive-number format):

```elixir
iex> alias Localize.Number.Format.Options
iex> {:ok, options} = Options.validate_options(0, locale: :en, currency: :USD)

iex> # Reuse for many calls — bypasses all options resolution
iex> {:ok, _} = Localize.Number.to_string(1234.56, options)
iex> {:ok, _} = Localize.Number.to_string(9876.54, options)
```

### Performance comparison

Benchmarks on a typical development machine (Apple Silicon):

| Approach | Simple decimal | Currency |
|----------|---------------|----------|
| Keyword options | ~7 µs/call | ~300 µs/call |
| Normalized `Options` struct | ~2 µs/call | ~6 µs/call |
| Speedup | ~3x | ~50x |

The difference is largest for currency formatting because options resolution must load currency metadata (symbols, decimal places, spacing rules) in addition to the standard format pattern. With normalized options, currency formatting drops from ~300µs to ~6µs.

For simple decimal formatting the keyword path is already fast (~7µs) thanks to the locale validation cache, and the normalized path is ~2µs. The difference is small enough that keyword options are fine for most use cases.

**When to use `Options.validate_options/2`:**

* Formatting many numbers with the same locale and format (reports, tables, batch processing).

* Currency formatting in hot loops — the 50x speedup is significant.

* Server-side rendering where latency matters.

**When keyword options are fine:**

* One-off formatting calls.

* Simple decimal formatting (already ~7µs with keywords).

* When the locale or format changes between calls.

## Optional NIF

When the NIF is enabled (`LOCALIZE_NIF=true`), `Localize.Nif.number_format/3` provides ICU4C-based number formatting:

```elixir
Localize.Nif.number_format(1234.56, "en-US", currency: "USD")
#=> {:ok, "$1,234.56"}
```

### NIF vs Elixir differences

The NIF uses ICU4C's `icu::number::NumberFormatter`, which may produce slightly different output in edge cases:

* Narrow no-break space handling may differ in some locales.

* Short/long compact format abbreviations may use different rounding.

* Some locale-specific patterns (like Indian grouping) may handle large numbers differently.

The NIF is primarily useful for cross-validation and for algorithms like collation sort-key generation where C performance is critical. For number formatting, the pre-built `Options` struct approach already delivers sub-10µs latency in pure Elixir.

### NIF availability

```elixir
iex> Localize.Nif.available?()
false  # unless compiled with LOCALIZE_NIF=true
```

## Number parsing

`Localize.Number` also provides locale-aware parsing from formatted strings back to numbers:

```elixir
iex> Localize.Number.parse("1,234.56")
{:ok, 1234.56}

iex> Localize.Number.scan("The price is $1,234.56 per unit")
["The price is $", 1234.56, " per unit"]
```

Parsing respects locale-specific separators and can resolve embedded currency symbols and percent signs. See `Localize.Number.parse/2` and `Localize.Number.scan/2` for details.
