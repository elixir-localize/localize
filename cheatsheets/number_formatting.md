# Number Formatting & Parsing Cheatsheet

## Formatting numbers

```elixir
Localize.Number.to_string(1234567.89)
#=> {:ok, "1,234,567.89"}
```

### Locale-specific decimal formatting

| Locale | `1234567.89` | Grouping style |
|---|---|---|
| `:en` | `"1,234,567.89"` | Western (groups of 3) |
| `:de` | `"1.234.567,89"` | Period grouping, comma decimal |
| `:ja` | `"1,234,567.89"` | Western (same as English) |
| `:hi` | `"12,34,567.89"` | Indian (lakhs/crores) |
| `:fr` | `"1 234 567,89"` | Thin-space grouping, comma decimal |

### Currency formatting

```elixir
Localize.Number.to_string(1234.56, currency: :USD, locale: :en)
#=> {:ok, "$1,234.56"}

Localize.Number.to_string(1234.56, currency: :EUR, locale: :de)
#=> {:ok, "1.234,56\u00A0€"}

Localize.Number.to_string(1234, currency: :JPY, locale: :ja)
#=> {:ok, "￥1,234"}
```

### Accounting format (negative in parentheses)

```elixir
Localize.Number.to_string(1234.56, format: :accounting, currency: :USD)
#=> {:ok, "$1,234.56"}

Localize.Number.to_string(-1234.56, format: :accounting, currency: :USD)
#=> {:ok, "($1,234.56)"}
```

### Percentage

```elixir
Localize.Number.to_string(0.456, format: :percent, locale: :en)
#=> {:ok, "46%"}

Localize.Number.to_string(0.456, format: :percent, locale: :de)
#=> {:ok, "46\u00A0%"}
```

### Scientific notation

```elixir
Localize.Number.to_string(1234567.89, format: :scientific)
#=> {:ok, "1.23456789E6"}
```

### Compact / short formats

```elixir
Localize.Number.to_string(1234567, format: :decimal_short)
#=> {:ok, "1.2M"}

Localize.Number.to_string(1234567890, format: :decimal_short)
#=> {:ok, "1.2B"}

Localize.Number.to_string(1234567, format: :decimal_long)
#=> {:ok, "1.2 million"}

Localize.Number.to_string(1234567, format: :currency_short, currency: :USD)
#=> {:ok, "$1.2M"}
```

### Fractional digit control

```elixir
Localize.Number.to_string(42, fractional_digits: 2)
#=> {:ok, "42.00"}

Localize.Number.to_string(3.14159, max_fractional_digits: 2)
#=> {:ok, "3.14"}

Localize.Number.to_string(3.1, min_fractional_digits: 3)
#=> {:ok, "3.100"}
```

### Number ranges

```elixir
Localize.Number.to_range_string(3..5, [])
#=> {:ok, "3–5"}

Localize.Number.to_range_string(3, 5, locale: :de)
#=> {:ok, "3–5"}
```

### Format options summary

| Option | Values | Default | Description |
|---|---|---|---|
| `:locale` | atom, string, `LanguageTag` | `Localize.get_locale()` | Formatting locale |
| `:format` | `:standard`, `:percent`, `:scientific`, `:currency`, `:accounting`, `:decimal_short`, `:decimal_long`, `:currency_short`, or a pattern string; `:short` / `:long` alias the compact decimal (or currency) formats | `:standard` | Number format style |
| `:currency` | ISO 4217 atom (`:USD`, `:EUR`, etc.) | `nil` | Currency code (auto-selects currency format) |
| `:number_system` | `:default`, `:native`, `:traditional`, or a system name | `:default` | Digit system |
| `:rounding_mode` | `:half_even`, `:half_up`, `:down`, `:up`, `:ceiling`, `:floor` | `:half_even` | Rounding mode |
| `:fractional_digits` | integer | from format pattern | Sets both min and max fractional digits |
| `:min_fractional_digits` | integer | from format pattern | Minimum fractional digits (trailing zeros) |
| `:max_fractional_digits` | integer | from format pattern | Maximum fractional digits (rounds to fit) |

## Parsing numbers

```elixir
Localize.Number.parse("1,234.56")
#=> {:ok, 1234.56}

Localize.Number.parse("1.234,56", locale: :de)
#=> {:ok, 1234.56}

Localize.Number.parse("-42.5")
#=> {:ok, -42.5}
```

### Scanning for numbers in text

```elixir
Localize.Number.scan("The price is $1,234.56 per unit")
#=> ["The price is $", 1234.56, " per unit"]
```

## Pre-validated options (hot-loop performance)

```elixir
# Validate once
{:ok, options} = Localize.Number.Format.Options.validate_options(0, locale: :en, currency: :USD)

# Reuse for many calls — skips per-call option resolution
{:ok, _} = Localize.Number.to_string(1234.56, options)
{:ok, _} = Localize.Number.to_string(9876.54, options)
```
