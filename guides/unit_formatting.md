# Unit of Measure Formatting Guide

This guide explains how to use `Localize.Unit` for creating, converting, and formatting units of measure with locale-aware patterns.

## Overview

`Localize.Unit` represents CLDR units of measure and formats them with plural-aware, locale-specific patterns. Units support conversion between compatible types, arithmetic operations, and measurement system preferences.

```elixir
iex> {:ok, unit} = Localize.Unit.new(42, "meter")
iex> Localize.Unit.to_string(unit)
{:ok, "42 meters"}

iex> Localize.Unit.to_string(unit, format: :short)
{:ok, "42 m"}

iex> Localize.Unit.to_string(unit, format: :narrow)
{:ok, "42m"}
```

## Creating units

### With a value

`Localize.Unit.new/2` and `new/3` create a unit with a numeric value. The value can be an integer, float, or `Decimal`:

```elixir
iex> {:ok, unit} = Localize.Unit.new(100, "meter")
iex> unit.value
100

iex> {:ok, unit} = Localize.Unit.new(3.14, "kilogram")
iex> unit.value
3.14

iex> {:ok, unit} = Localize.Unit.new(Decimal.new("99.99"), "liter")
iex> unit.value
#Decimal<99.99>
```

### Without a value

`Localize.Unit.new/1` creates a unit definition without a numeric value, useful for display names:

```elixir
iex> {:ok, unit} = Localize.Unit.new("meter")
iex> unit.value
nil
```

### Bang variants

`new!/1`, `new!/2`, and `new!/3` return the struct directly or raise on error:

```elixir
iex> unit = Localize.Unit.new!(42, "kilogram")
iex> unit.value
42
```

## Unit naming

Unit identifiers follow CLDR syntax. Names are lowercase, hyphen-separated strings.

### Simple units

Basic unit names from the CLDR unit registry:

```
meter, kilometer, foot, mile, inch, yard
kilogram, gram, pound, ounce, stone, ton
second, minute, hour, day, week, month, year
celsius, fahrenheit, kelvin
liter, milliliter, gallon, cup, pint
hectare, acre
watt, kilowatt, megawatt
joule, kilowatt-hour
hertz, kilohertz, megahertz
pascal, bar, atmosphere
```

### SI prefixes

Standard SI prefixes are applied automatically: `kilo`, `milli`, `micro`, `nano`, `mega`, `giga`, `tera`, `centi`, `deci`, and others.

```elixir
iex> {:ok, _} = Localize.Unit.new(1, "kilometer")
iex> {:ok, _} = Localize.Unit.new(1, "centimeter")
iex> {:ok, _} = Localize.Unit.new(1, "millisecond")
iex> {:ok, _} = Localize.Unit.new(1, "megawatt")
```

### Powers

Prefix a unit with `square-` or `cubic-` for powers:

```elixir
iex> {:ok, area} = Localize.Unit.new(100, "square-meter")
iex> Localize.Unit.to_string(area, format: :short)
{:ok, "100 m\u00B2"}

iex> {:ok, vol} = Localize.Unit.new(5, "cubic-meter")
iex> Localize.Unit.to_string(vol, format: :short)
{:ok, "5 m\u00B3"}
```

### Compound units (per-expressions)

Use `-per-` to create rate units:

```elixir
iex> {:ok, speed} = Localize.Unit.new(60, "mile-per-hour")
iex> Localize.Unit.to_string(speed)
{:ok, "60 miles per hour"}

iex> Localize.Unit.to_string(speed, format: :short)
{:ok, "60 mph"}

iex> {:ok, density} = Localize.Unit.new(1000, "kilogram-per-cubic-meter")
iex> Localize.Unit.to_string(density, format: :short)
{:ok, "1,000 kg/m\u00B3"}
```

Complex compounds with multiple numerator and denominator components are also supported, such as `kilogram-meter-per-square-second` (force).

## Formatting

### Styles

The `:format` option controls the verbosity of the output:

| Style | Description | Example (42 meters) |
|-------|-------------|---------------------|
| `:long` | Full name (default) | 42 meters |
| `:short` | Abbreviated | 42 m |
| `:narrow` | Most compact | 42m |

```elixir
iex> unit = Localize.Unit.new!(42, "meter")
iex> Localize.Unit.to_string(unit, format: :long)
{:ok, "42 meters"}

iex> Localize.Unit.to_string(unit, format: :short)
{:ok, "42 m"}

iex> Localize.Unit.to_string(unit, format: :narrow)
{:ok, "42m"}
```

### Plural-aware patterns

CLDR formatting automatically selects the correct plural form for the locale:

```elixir
iex> Localize.Unit.to_string(Localize.Unit.new!(1, "kilometer"))
{:ok, "1 kilometer"}

iex> Localize.Unit.to_string(Localize.Unit.new!(5.5, "kilometer"))
{:ok, "5.5 kilometers"}
```

### Locale-specific formatting

Different locales produce different unit names, number formatting, and patterns:

```elixir
iex> unit = Localize.Unit.new!(2.5, "kilogram")
iex> Localize.Unit.to_string(unit, locale: :en)
{:ok, "2.5 kilograms"}

iex> Localize.Unit.to_string(unit, locale: :de)
{:ok, "2,5 Kilogramm"}

iex> Localize.Unit.to_string(unit, locale: :fr)
{:ok, "2,5\u00A0kilogrammes"}
```

## Unit conversion

### Basic conversion

`Localize.Unit.convert/2` converts between compatible units. Units are compatible when they reduce to the same base dimensions (e.g. meter and foot are both length):

```elixir
iex> {:ok, km} = Localize.Unit.new(1, "kilometer")
iex> {:ok, m} = Localize.Unit.convert(km, "meter")
iex> m.value
1000.0

iex> {:ok, mi} = Localize.Unit.new(1, "mile")
iex> {:ok, m} = Localize.Unit.convert(mi, "meter")
iex> Float.round(m.value, 1)
1609.3
```

### Temperature conversion

Temperature conversions handle offsets correctly:

```elixir
iex> {:ok, c} = Localize.Unit.new(0, "celsius")
iex> {:ok, f} = Localize.Unit.convert(c, "fahrenheit")
iex> Float.round(f.value, 0)
32.0

iex> {:ok, c100} = Localize.Unit.new(100, "celsius")
iex> {:ok, k} = Localize.Unit.convert(c100, "kelvin")
iex> Float.round(k.value, 2)
373.15
```

### Compound unit conversion

Compound units convert each component independently:

```elixir
iex> {:ok, mph} = Localize.Unit.new(60, "mile-per-hour")
iex> {:ok, mps} = Localize.Unit.convert(mph, "meter-per-second")
iex> Float.round(mps.value, 2)
26.82
```

### Incompatible units

Attempting to convert between incompatible dimensions returns an error:

```elixir
iex> {:ok, m} = Localize.Unit.new(1, "meter")
iex> {:error, _} = Localize.Unit.convert(m, "kilogram")
```

## Measurement system preferences

`Localize.Unit.convert_measurement_system/2` converts a unit to the preferred unit for a measurement system. CLDR defines preferences for three systems:

| System | Region | Example preferences |
|--------|--------|-------------------|
| `:metric` | International (001) | kilometer, kilogram, celsius |
| `:us` | United States (US) | mile, pound, fahrenheit |
| `:uk` | United Kingdom (GB) | mile, stone, celsius |

```elixir
iex> {:ok, meters} = Localize.Unit.new(1000, "meter")
iex> {:ok, result} = Localize.Unit.convert_measurement_system(meters, :us)
iex> result.name
"mile"
```

### Usage preferences

The optional `:usage` parameter on `new/3` provides context for more specific conversions. For example, "person-height" in the US uses feet and inches rather than miles:

```elixir
iex> {:ok, height} = Localize.Unit.new(180, "centimeter", usage: "person-height")
iex> height.usage
"person-height"
```

Common usage values: `"default"`, `"person"`, `"person-height"`, `"person-weight"`, `"road"`, `"food"`, `"vehicle-fuel"`, `"cooking-volume"`.

## Arithmetic operations

`Localize.Unit.Math` provides dimensional arithmetic on units.

### Addition and subtraction

Add or subtract compatible units. The result uses the first unit's type, converting the second unit automatically:

```elixir
iex> a = Localize.Unit.new!(1, "kilometer")
iex> b = Localize.Unit.new!(500, "meter")
iex> {:ok, sum} = Localize.Unit.Math.add(a, b)
iex> {sum.name, sum.value}
{"kilometer", 1.5}
```

### Multiplication

Multiply by a scalar or by another unit (creating a compound):

```elixir
iex> u = Localize.Unit.new!(5, "meter")
iex> {:ok, result} = Localize.Unit.Math.mult(u, 3)
iex> result.value
15
```

### Division

Divide by a scalar or by another unit (creating a per-expression):

```elixir
iex> distance = Localize.Unit.new!(100, "meter")
iex> time = Localize.Unit.new!(10, "second")
iex> {:ok, speed} = Localize.Unit.Math.div(distance, time)
iex> speed.name
"meter-per-second"
iex> speed.value
10.0
```

### Negation and inversion

```elixir
iex> u = Localize.Unit.new!(5, "meter")
iex> {:ok, neg} = Localize.Unit.Math.negate(u)
iex> neg.value
-5

iex> speed = Localize.Unit.new!(4, "meter-per-second")
iex> {:ok, inv} = Localize.Unit.Math.invert(speed)
iex> inv.name
"second-per-meter"
iex> inv.value
0.25
```

## Supported unit categories

Units are organized into dimensional categories. Common categories and representative units:

| Category | Example units |
|----------|--------------|
| Length | meter, kilometer, foot, mile, inch, yard, nautical-mile |
| Mass | kilogram, gram, pound, ounce, stone, ton |
| Duration | second, minute, hour, day, week, month, year |
| Temperature | celsius, fahrenheit, kelvin |
| Area | square-meter, square-kilometer, hectare, acre |
| Volume | liter, milliliter, cubic-meter, gallon, cup, pint |
| Speed | meter-per-second, kilometer-per-hour, mile-per-hour |
| Energy | joule, kilowatt-hour |
| Power | watt, kilowatt, megawatt |
| Pressure | pascal, bar, atmosphere, inch-of-mercury |
| Frequency | hertz, kilohertz, megahertz, gigahertz |
| Force | newton, kilogram-force, pound-force |
| Concentration | percent, permille, part-per-million |
| Consumption | liter-per-100-kilometer, mile-per-gallon |
| Acceleration | meter-per-square-second, g-force |

## Options reference

### `Localize.Unit.to_string/2`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:locale` | atom, string, or `LanguageTag` | `Localize.get_locale()` | Locale for unit names and number formatting. |
| `:format` | atom | `:long` | Display format: `:long`, `:short`, or `:narrow`. |

### `Localize.Unit.new/3`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:usage` | string | `nil` | Usage context for measurement system preferences (e.g., `"person-height"`, `"road"`). |

### `Localize.Unit.convert_measurement_system/2`

| Argument | Type | Description |
|----------|------|-------------|
| `unit` | `Localize.Unit.t()` | Unit with a value to convert. |
| `system` | atom | Target measurement system: `:metric`, `:us`, or `:uk`. |
