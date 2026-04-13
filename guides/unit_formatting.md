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

## Operator syntax

`use Localize.Unit.Operators` overrides `+`, `-`, `*`, and `/` within the calling module so that unit arithmetic reads naturally. Standard Elixir operators are preserved for non-unit types.

```elixir
defmodule MyApp.Physics do
  use Localize.Unit.Operators

  def speed(distance, time), do: distance / time

  def momentum(mass, velocity), do: mass * velocity
end

km = Localize.Unit.new!(1, "kilometer")
m  = Localize.Unit.new!(500, "meter")

km + m          #=> %Localize.Unit{value: 1.5, name: "kilometer"}
km - m          #=> %Localize.Unit{value: 0.5, name: "kilometer"}
km * 3          #=> %Localize.Unit{value: 3, name: "kilometer"}
3 * km          #=> %Localize.Unit{value: 3, name: "kilometer"}
km / 2          #=> %Localize.Unit{value: 0.5, name: "kilometer"}

dist = Localize.Unit.new!(100, "meter")
time = Localize.Unit.new!(10, "second")
dist / time     #=> %Localize.Unit{value: 10.0, name: "meter-per-second"}
dist * time     #=> %Localize.Unit{value: 50, name: "meter-second"}

# Standard operators still work for non-unit types
2 + 3           #=> 5
10 / 2          #=> 5.0
```

The operators raise on error (matching the bang convention) so they can be chained in expressions without unwrapping tuples. Errors from incompatible unit conversions surface as raised exceptions.

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

## Custom units

`Localize.Unit.define_unit/2` registers user-defined units at runtime via the `Localize.Unit.CustomRegistry`. Custom units participate in conversion, formatting, and arithmetic alongside built-in CLDR units.

### Linear custom units

Most custom units are linear conversions of the form `base_value = value * factor + offset`. Register them with a `:base_unit`, `:factor`, and `:category`:

```elixir
iex> Localize.Unit.define_unit("smoot", %{
...>   base_unit: "meter",
...>   factor: 1.7018,
...>   category: "length"
...> })
:ok

iex> {:ok, unit} = Localize.Unit.new(3, "smoot")
iex> {:ok, meters} = Localize.Unit.convert(unit, "meter")
iex> Float.round(meters.value, 4)
5.1054
```

Custom units automatically support SI prefixes (`kilosmoot`, `millismoot`) and power prefixes (`square-smoot`, `cubic-smoot`).

#### Definition fields

* `:base_unit` (required) — the CLDR unit this converts to (e.g., `"meter"`, `"kilogram"`, `"second"`).

* `:factor` (required) — the conversion multiplier: `1 custom_unit = factor × base_unit`.

* `:offset` (optional) — additive offset for the conversion. Defaults to `0.0`.

* `:category` (required) — the unit category (e.g., `"length"`, `"mass"`). Any non-empty string is accepted, allowing domain-specific categories like `"mass-density"` or `"thermal-conductivity"`.

* `:display` (optional) — locale-specific display patterns. A nested map of `locale => style => plural_patterns`:

```elixir
Localize.Unit.define_unit("smoot", %{
  base_unit: "meter",
  factor: 1.7018,
  category: "length",
  display: %{
    en: %{
      long: %{one: "{0} smoot", other: "{0} smoots"}
    }
  }
})
```

### Nonlinear custom units (special conversions)

Some scales cannot be expressed as a linear factor — for example, decibels (logarithmic), wire gauges (exponential), and density hydrometers (reciprocal). These are registered with `factor: :special` and a pair of `{module, function}` tuples that implement the forward and inverse conversions.

#### Building a conversion module

A conversion module provides two public functions of arity 1:

* A **forward** function that converts from the custom scale reading to the base unit value.

* An **inverse** function that converts from the base unit value back to the custom scale reading.

For example, a module for the Baumé hydrometer scale (which measures liquid density):

```elixir
defmodule MyApp.BaumeConversion do
  @baumeconst 145.0
  @g_per_cm3_to_kg_per_m3 1000.0

  @doc "Baumé degrees to kg/m³."
  @spec forward(number()) :: float()
  def forward(degrees) do
    @baumeconst / (@baumeconst - degrees) * @g_per_cm3_to_kg_per_m3
  end

  @doc "kg/m³ to Baumé degrees."
  @spec inverse(number()) :: float()
  def inverse(kg_per_m3) do
    g_cm3 = kg_per_m3 / @g_per_cm3_to_kg_per_m3
    @baumeconst - @baumeconst / g_cm3
  end
end
```

#### Registering a special conversion

Register the unit with `factor: :special` and `:forward` / `:inverse` keys pointing to the conversion functions:

```elixir
iex> Localize.Unit.define_unit("baume", %{
...>   base_unit: "kilogram-per-cubic-meter",
...>   factor: :special,
...>   category: "mass-density",
...>   forward: {MyApp.BaumeConversion, :forward},
...>   inverse: {MyApp.BaumeConversion, :inverse}
...> })
:ok

iex> {:ok, unit} = Localize.Unit.new(10, "baume")
iex> {:ok, density} = Localize.Unit.convert(unit, "kilogram-per-cubic-meter")
iex> Float.round(density.value, 1)
1074.1
```

The conversion pipeline calls the forward function to go from the custom scale to the base unit, then applies standard factor-based conversion to reach the target unit. For the reverse direction, it converts to the base unit first, then calls the inverse function.

#### Definition fields for special conversions

* `:base_unit` (required) — the CLDR unit that the forward function produces (e.g., `"kelvin"` for temperature scales, `"meter"` for wire gauges).

* `:factor` (required) — must be the atom `:special`.

* `:category` (required) — the unit category.

* `:forward` (required) — a `{module, function_name}` tuple. The function must be exported with arity 1, accepting a number and returning the base unit value as a float.

* `:inverse` (required) — a `{module, function_name}` tuple. The function must be exported with arity 1, accepting a base unit value and returning the custom scale reading as a float.

* `:display` (optional) — locale-specific display patterns, same as linear units.

#### Validation

When registering a special conversion, the registry verifies that:

* The module is loaded and the function is exported with arity 1 (for both `:forward` and `:inverse`).

* The `:base_unit` is a valid CLDR base unit.

* The `:category` is a non-empty string.

### Batch registration

For bulk loading, `Localize.Unit.CustomRegistry.register_batch/1` accepts a map of `%{name => definition}` and performs a single `persistent_term` update, avoiding the memory overhead of individual registrations:

```elixir
Localize.Unit.CustomRegistry.register_batch(%{
  "smoot" => %{base_unit: "meter", factor: 1.7018, category: "length"},
  "cubit" => %{base_unit: "meter", factor: 0.4572, category: "length"}
})
```

### Loading from files

`Localize.Unit.load_custom_units/1` loads definitions from an `.exs` file that evaluates to a list of definition maps (each with a `:unit` key):

```elixir
Localize.Unit.load_custom_units("priv/custom_units.exs")
```

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
