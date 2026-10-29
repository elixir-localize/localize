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

A compact number is written to two significant digits by default, as ECMA-402's compact notation is. Significant-digit or fraction-digit options replace that default, and a value that rounds up to the next magnitude moves to it:

```elixir
iex> Localize.Number.to_string(36_437_123, format: :short, maximum_significant_digits: 4)
{:ok, "36.44M"}

iex> Localize.Number.to_string(999_950, format: :short, maximum_significant_digits: 4)
{:ok, "1M"}
```

### Long (word) formats

Spell out the magnitude in words:

```elixir
iex> Localize.Number.to_string(1234567, format: :decimal_long)
{:ok, "1.2 million"}

iex> Localize.Number.to_string(1234567, format: :decimal_long, locale: :de)
{:ok, "1,2 Millionen"}

iex> Localize.Number.to_string(1234567, format: :currency_long, currency: :USD)
{:ok, "1,234,567.00 US dollars"}
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
["digits_ordinal", "spellout_cardinal", "spellout_cardinal_verbose",
 "spellout_numbering", "spellout_numbering_verbose", "spellout_numbering_year",
 "spellout_ordinal", "spellout_ordinal_verbose"]
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
| `:currency_long` | (pattern) | Pluralized: "123.00 US dollars". |

The aliases `:short` and `:long` resolve to `:decimal_short` and `:decimal_long`, or to `:currency_short` and `:currency_long` when a `:currency` is specified.

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
| `¤` | Currency symbol placeholder. | `¤#,##0` → "$1,234.00" |
| `¤¤` | ISO currency code, with a no-break space before the digits. | `¤¤#,##0` → "USD 1,234.00" |
| `¤¤¤` | Currency display name, in the plural form for the number as displayed. | `#,##0 ¤¤¤` → "1,234.00 US dollars" |
| `¤¤¤¤¤` | Narrow currency symbol. | `¤¤¤¤¤#,##0` → "$1,234.00" |
| `;` | Separates positive and negative subpatterns. | |
| `+` | Plus sign in exponent. | `0E+0` → "1E+3" |
| `-` | Minus sign. | |
| `@` | Significant digit. | `@@##` → "12.34" |

### Grouping

The grouping pattern is read from right to left in the integer part. `#,##0` means groups of 3. The Indian pattern `#,##,##0` means the first group is 3 digits and subsequent groups are 2 digits, producing "12,34,567" for Hindi.

### Currency symbol

The `¤` placeholder is replaced at format time with the currency symbol, and the currency's decimal places replace the pattern's. The placement varies by locale — English puts it before the number (`$1,234.00`), German puts it after with a non-breaking space (`1.234,00 €`). Where a symbol that begins or ends with a letter meets the digits, CLDR's currency spacing inserts a non-breaking space, so `¤#,##0.00` formats Swiss francs as "CHF 1,234.00".

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

Following TR35, any numbering system in the CLDR inventory may be requested by name — via the `:number_system` option or the `-u-nu-` locale keyword — even when the locale does not list it. The digits come from the requested system, and its symbols and patterns from CLDR's inheritance: root's own for `arab` and `arabext`, which have symbols and some patterns of their own, and otherwise the locale's `latn` ones. For an algorithmic system, the standard format is produced by the system's RBNF rules; other formats (currency, percent, scientific, compact) fall back to the locale's `latn` patterns.

```elixir
iex> Localize.Number.to_string(1234.5, locale: "en-u-nu-thai")
{:ok, "๑,๒๓๔.๕"}

iex> Localize.Number.to_string(1234.5, locale: "en-u-nu-arab")
{:ok, "١٬٢٣٤٫٥"}

iex> Localize.Number.to_string(1234, locale: :en, number_system: :roman)
{:ok, "MCCXXXIV"}
```

## How locale influences formatting

### Locale-specific patterns

Different locales use different format patterns, grouping rules, and symbols:

| Locale | Standard pattern | Decimal | Grouping | Example |
|--------|-----------------|---------|----------|---------|
| `:en` | `#,##0.###` | `.` | `,` | 1,234,567.89 |
| `:de` | `#,##0.###` | `,` | `.` | 1.234.567,89 |
| `:fr` | `#,##0.###` | `,` | ` ` (narrow no-break space) | 1 234 567,89 |
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
| `:minimum_integer_digits` | integer | `nil` | Minimum integer digits (1–21); zero-pads and groups the padding. Mirrors ECMA-402 `minimumIntegerDigits`. |
| `:minimum_significant_digits` | integer | `nil` | Minimum significant digits (1–21). Takes precedence over fractional digit settings. |
| `:maximum_significant_digits` | integer | `nil` | Maximum significant digits (1–21). Values are rounded to fit. |
| `:rounding_priority` | atom | `:auto` | How significant and fraction bounds combine: `:auto` (significant digits win), `:more_precision`, or `:less_precision` (both bounds compared, a missing one at its default). Mirrors ECMA-402 `roundingPriority`. |
| `:trailing_zero_display` | atom | `:auto` | `:strip_if_integer` drops the fraction when the rounded value is an integer. Mirrors ECMA-402 `trailingZeroDisplay`. |
| `:sign_display` | atom | `:auto` | When to show the sign: `:auto`, `:always`, `:except_zero`, `:negative`, or `:never`. Mirrors ECMA-402 `signDisplay`. |
| `:exponent_style` | atom | `:e` | Scientific exponent rendering: `:e` (`1.234E3`) or `:superscript` (`1.234 × 10³`). |
| `:rounding_mode` | atom | `:half_even` | One of `:down`, `:up`, `:half_up`, `:half_down`, `:half_even`, `:ceiling`, `:floor`. |
| `:round_nearest` | integer | `nil` | Round to nearest increment (e.g., 5 for rounding to nearest 5). |
| `:minimum_grouping_digits` | integer | `0` | Minimum integer digits before grouping is applied. |
| `:currency_symbol` | atom or string | `nil` | Override currency symbol display: `:symbol`, `:narrow`, `:variant`, `:iso`, or a custom string. |
| `:currency_digits` | atom | `:accounting` | How to determine currency decimal places: `:accounting`, `:cash`, or `:iso`. They apply to currency formats and to pattern strings with a currency sign; `:fractional_digits` overrides them. |
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

### Sign display examples

`:sign_display` mirrors ECMA-402's `signDisplay` option. `:auto` (the default) shows the sign for negative numbers only; `:always` shows a sign on every number, using the locale's plus sign for positive numbers and zero; `:except_zero` shows a sign on everything except values that round to zero; `:negative` suppresses the sign on negative values that round to zero; `:never` shows no sign at all. Zero-ness is judged after rounding.

```elixir
iex> Localize.Number.to_string(1234, sign_display: :always)
{:ok, "+1,234"}

iex> Localize.Number.to_string(0, sign_display: :except_zero)
{:ok, "0"}

iex> Localize.Number.to_string(-1234, sign_display: :never)
{:ok, "1,234"}

iex> Localize.Number.to_string(-0.2, sign_display: :negative, fractional_digits: 0)
{:ok, "0"}

iex> Localize.Number.to_string(0.5, format: :percent, sign_display: :always)
{:ok, "+50%"}
```

The sign is placed where the format's negative subpattern places the minus sign, so `format: :accounting` keeps parentheses for negative numbers and prefixes the plus sign for positive ones.

### Integer width, trailing zeros, and rounding priority

Three options mirror their ECMA-402 counterparts for fine control over digit display. `:minimum_integer_digits` zero-pads the integer part (the padding digits group normally); `:trailing_zero_display` with `:strip_if_integer` drops the fraction when the rounded value is an integer; and `:rounding_priority` resolves the conflict when both fraction-digit and significant-digit bounds are given — `:auto` (the default) lets significant digits win, while `:more_precision` and `:less_precision` pick the bound yielding more or fewer digits for the value at hand.

```elixir
iex> Localize.Number.to_string(123, minimum_integer_digits: 5)
{:ok, "00,123"}

iex> Localize.Number.to_string(1000, fractional_digits: 2, trailing_zero_display: :strip_if_integer)
{:ok, "1,000"}

iex> Localize.Number.to_string(1000.5, fractional_digits: 2, trailing_zero_display: :strip_if_integer)
{:ok, "1,000.50"}

iex> Localize.Number.to_string(1.23456, max_fractional_digits: 3, maximum_significant_digits: 2, rounding_priority: :more_precision)
{:ok, "1.235"}

iex> Localize.Number.to_string(1.23456, max_fractional_digits: 3, maximum_significant_digits: 2, rounding_priority: :less_precision)
{:ok, "1.2"}
```

### Structured format parts

`Localize.Number.to_parts/2` mirrors ECMA-402's `formatToParts`: it produces the same output as `to_string/2` but as a list of typed segments, so callers can style or wrap individual pieces. Part types follow ECMA-402 in snake_case; compact affixes are tagged `:compact` and currency spacing surfaces as `:literal`.

```elixir
iex> Localize.Number.to_parts(1234.5, currency: :USD)
{:ok,
 [
   %{type: :currency, value: "$"},
   %{type: :integer, value: "1"},
   %{type: :group, value: ","},
   %{type: :integer, value: "234"},
   %{type: :decimal, value: "."},
   %{type: :fraction, value: "50"}
 ]}

iex> Localize.Number.to_parts(1234567, format: :decimal_short)
{:ok,
 [
   %{type: :integer, value: "1"},
   %{type: :decimal, value: "."},
   %{type: :fraction, value: "2"},
   %{type: :compact, value: "M"}
 ]}
```

The RBNF rule-name formats (`:spellout_cardinal` and friends) do not decompose into parts and return an error from `to_parts/2`.

One known deviation from `Intl.NumberFormat.formatToParts`: the compact affix is a single `:compact` part including any adjoining space (`" million"`), where JS emits the space as a separate `:literal` part. Callers needing exact JS part boundaries can split leading/trailing whitespace off the `:compact` part.

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

`to_string/2` accepts either a keyword list or a pre-validated `Localize.Number.Format.Options` struct. The keyword list path validates the options on every call and resolves the locale's number system, symbols, format patterns and minimum grouping digits. That resolution is kept per locale and number system in the format cache, so after the first call for a locale it is one ETS read; locale validation is cached too (~1µs). What remains on every call is checking each option and, for a currency, resolving the currency's data, which is why the struct helps most for currency formatting.

For high-throughput formatting (rendering a table of thousands of numbers, batch processing), call `Localize.Number.Format.Options.validate_options/2` once to build an options struct, then pass it to `to_string/2` for each number. The first argument is a representative number such as `0`; the struct formats numbers of either sign:

```elixir
iex> alias Localize.Number.Format.Options
iex> {:ok, options} = Options.validate_options(0, locale: :en, currency: :USD)

iex> # Reuse for many calls — bypasses all options resolution
iex> {:ok, _} = Localize.Number.to_string(1234.56, options)
iex> {:ok, _} = Localize.Number.to_string(9876.54, options)
```

### Performance comparison

Formatting `1234.56` in `en`, measured in reductions (the BEAM's unit of work, the same on every machine) and in time on an Intel Xeon desktop; a current laptop CPU is about twice as fast:

| Approach | Simple decimal | Currency |
|---|---|---|
| Keyword options | 541 reductions, ~18 µs | 730 reductions, ~33 µs |
| Validated `Options` struct | 310 reductions, ~9 µs | 366 reductions, ~17 µs |
| Speedup | ~1.7x | ~2x |

The difference is larger for currency formatting because the keyword path also resolves the currency's data (its symbol, decimal places and spacing rules) on each call. Most of the struct path's own cost is the formatting itself: an integer such as `12345` formats in about 170 reductions, and a float costs more for the digits it has to find.

For simple decimal formatting the keyword path costs about twice the struct path. The difference is small enough that keyword options are fine for most use cases.

**When to use `Options.validate_options/2`:**

* Formatting many numbers with the same locale and format (reports, tables, batch processing).

* Currency formatting in hot loops, where the struct path is about half the cost.

* Server-side rendering where latency matters.

**When keyword options are fine:**

* One-off formatting calls.

* Simple decimal formatting, where the keyword path is about 540 reductions, twice the struct path.

* When the locale or format changes between calls.

## Optional NIF

When the NIF is enabled (`LOCALIZE_NIF=true`), `Localize.Nif.number_format/3` provides ICU4C-based number formatting:

```elixir
Localize.Nif.number_format(1234.56, "en-US", currency: "USD")
#=> {:ok, "$1,234.56"}
```

### NIF vs Elixir differences

The NIF is ICU4C's `icu::number::NumberFormatter`, so it produces ICU's answers rather than Localize's wherever the two differ. Those differences are not edge cases in the vague sense — they are enumerated, with the CLDR evidence for each, in the [ICU divergences guide](icu_divergences.md). In short: Localize renders the format CLDR ships and ICU sometimes overrides it, which shows up in the scientific notation of several Indic locales, the Urdu percent sign, Galician grouping, and the compact forms of `af`, `bn`, `en-IN`, `ig`, `ps` and `ta`.

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

A number is digits joined by the locale's separators, read leniently: CLDR's look-alike characters fold onto the locale's own, so a Unicode minus or a typographic apostrophe reads, bidi marks are ignored, and a trailing sign or accounting parentheses negate the number, though not both at once. Text that is not a number of the locale is refused rather than guessed: a space between digits in `en`, a grouping separator after the decimal mark, or a period in `fr` that could group thousands, as in `1.234`. A period the locale does not write reads as the decimal point only where it can be nothing else, so `fr` `100.00` is 100.

```elixir
iex> Localize.Number.parse("1’234.56", locale: :"de-CH")
{:ok, 1234.56}

iex> Localize.Number.parse("(1 234,56)", locale: :fr)
{:ok, -1234.56}

iex> {:error, error} = Localize.Number.parse("1 2", locale: :en)
iex> Exception.message(error)
"Expected a parseable number string for Localize.Number.Parser, got: \"1 2\""
```

### Currency amounts

`Localize.Number.parse_currency_amount/2` reads a whole currency amount into its currency and a `t:Decimal.t/0`. The currency may stand before or after the number, a sign before the currency, between them or after the number, and the number is read with the separators the locale writes that currency with.

```elixir
iex> Localize.Number.parse_currency_amount("€ 1.234,56", locale: :"de-AT")
{:ok, {:EUR, Decimal.new("1234.56")}}

iex> Localize.Number.parse_currency_amount("(CHF 1'234.56)", locale: :"de-CH")
{:ok, {:CHF, Decimal.new("-1234.56")}}

iex> Localize.Number.parse_currency_amount("kr-127,54", locale: :da)
{:ok, {:DKK, Decimal.new("-127.54")}}
```

Most applications read money through [ex_money](https://hexdocs.pm/ex_money), whose `Money.parse/2` is built on this function; its [parsing guide](https://hexdocs.pm/ex_money/parsing.html) describes what is read and what is refused, with examples.

An amount is money, so an amount that could be read as two amounts is refused rather than read as one of them:

* **Groups the locale does not write** — `de` `1.23 EUR` is refused, where a lenient reading of the grouping would make it 123 euros.

* **Two sets of separators** — `de-AT` and `fr-CH` write a currency amount with other separators than a plain number. Either is read, and text the two would read as different numbers is refused. `de-AT` groups the euro with a period, so `1.234 EUR` is 1234 euros, and a period is never its decimal point: `100.00 EUR` is refused, as in `de`.

* **Compatibility characters** — the currency text is matched after NFKC normalization, as TR35's loose matching asks, so `ja` `¥1.00` is the yen, which `ja` writes `￥`, and a fullwidth `＄` is the dollar. The number is not normalized, since NFKC would turn the footnote of `$5²` into a digit; such text is refused.

* **Another country's narrow symbol** — CLDR writes a currency's narrow symbol where the context makes the currency clear, so an amount reads a letter abbreviation only for the locale's own currency: `id` `Rp 15.000` is the rupiah, but Swiss `15 Rp.` is 15 Rappen and is refused, and `en` `Kč 100` is refused where `cs` `100 Kč` reads. A currency sign is read in any locale when it names one currency there and in CLDR's root data, so `en-AU` `€5` and `de-CH` `€ 15.40` are euros, while `bg` `₩5` is refused, since root gives `₩` to both wons, and `en-AU` `₱5`, since `en-AU` gives `₱` to the Philippine and the Cuban peso.

* **A symbol several currencies share** — `fr` `$2.00` is refused, since the Canadian, US and other dollars all write `$` there; `resolve_currency/2` takes the nearest locale's, the Canadian dollar, but an amount is not read in a currency that is a guess.

* **Three fraction digits in a currency of fewer** — `de` `1,599 €` is a fuel price, but a shop writing English separators means 1599, so one to three digits, a decimal mark and three more are refused in a currency of fewer than three decimal places. `0,123 €`, `1.234,567 €` and `KWD 1.599` have one reading and are read.

* **A historic currency's symbol** — symbols are reused, so a currency no longer in use is read only by its code or its name: `ru` `6 300 Р` is refused rather than read as the ruble of 1991–1998, whose symbol is `р.`, while `100 RUR` reads.

* **A fuzzy match two currencies share** — with `:fuzzy`, currency text as close to one currency's name as to another's is refused: `fr` `100 dollars` is as close to the Fiji dollar as to the Rhodesian dollar.

* **A dash for the zero** — Swiss `Fr. –.15` and Dutch `€ -,50` write a dash before the decimal mark for a zero, where a minus would stand, so a minus there is refused: `-$.50` is neither -0.50 nor 0.50 dollars.

* **A sign and parentheses together** — `($-5)` is refused, where some would read it as -5 dollars and others as 5.

* **A mark between currency and digits** — it is the currency's where CLDR writes the currency with it, as `da` writes `kr.`, and the number's where it is the decimal mark, so `$.50` is fifty cents; otherwise the amount is refused.

* **Currencies of the caller's own** — the `:caller_currency` option names them, such as digital tokens. Their amounts are read with the locale's separators and the root locale's, and text that names both a CLDR currency and one of the caller's, as `₮` names the tugrik and Tether, is refused. A caller's currency text may have digits in it, as a digital token identifier such as `"Q9PB7XDNF"` does; it is then the first word or the last, separated from the number by a space, and an amount that also reads another way is refused.

```elixir
iex> {:error, error} = Localize.Number.parse_currency_amount("1.23 EUR", locale: :de)
iex> Exception.message(error)
"The amount \"1.23\" of currency :EUR is not a number."
```
