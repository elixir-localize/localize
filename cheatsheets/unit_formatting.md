# Unit Formatting Cheatsheet

## Creating units

```elixir
{:ok, unit} = Localize.Unit.new(42, "meter")
unit = Localize.Unit.new!(42, "meter")          # bang variant

{:ok, unit} = Localize.Unit.new(3.14, "kilogram")
{:ok, unit} = Localize.Unit.new(Decimal.new("99.99"), "liter")
{:ok, unit} = Localize.Unit.new("meter")         # no value (for display names)
```

## Unit naming

### Simple units

```
meter, kilometer, foot, mile, inch, yard
kilogram, gram, pound, ounce, stone
second, minute, hour, day, week, month, year
celsius, fahrenheit, kelvin
liter, milliliter, gallon, cup, pint
```

### SI prefixes

```elixir
Localize.Unit.new!(1, "kilometer")      # kilo-
Localize.Unit.new!(1, "centimeter")     # centi-
Localize.Unit.new!(1, "millisecond")    # milli-
Localize.Unit.new!(1, "megawatt")       # mega-
```

### Powers

```elixir
Localize.Unit.new!(100, "square-meter")
Localize.Unit.new!(5, "cubic-meter")
```

### Compound units (per-expressions)

```elixir
Localize.Unit.new!(60, "mile-per-hour")
Localize.Unit.new!(1000, "kilogram-per-cubic-meter")
```

## Formatting

### Format styles

| Style | Example (42 meters, `:en`) | Example (100 km, `:de`) |
|---|---|---|
| `:long` (default) | `"42 meters"` | `"100 Kilometer"` |
| `:short` | `"42 m"` | `"100 km"` |
| `:narrow` | `"42m"` | `"100 km"` |

```elixir
unit = Localize.Unit.new!(42, "meter")
Localize.Unit.to_string(unit, format: :long)    #=> {:ok, "42 meters"}
Localize.Unit.to_string(unit, format: :short)   #=> {:ok, "42 m"}
Localize.Unit.to_string(unit, format: :narrow)  #=> {:ok, "42m"}
```

### Locale-specific output

```elixir
unit = Localize.Unit.new!(2.5, "kilogram")
Localize.Unit.to_string(unit, locale: :en)   #=> {:ok, "2.5 kilograms"}
Localize.Unit.to_string(unit, locale: :de)   #=> {:ok, "2,5 Kilogramm"}
Localize.Unit.to_string(unit, locale: :fr)   #=> {:ok, "2,5 kilogrammes"}
```

### Plural-aware patterns

```elixir
Localize.Unit.to_string(Localize.Unit.new!(1, "kilometer"))
#=> {:ok, "1 kilometer"}

Localize.Unit.to_string(Localize.Unit.new!(5.5, "kilometer"))
#=> {:ok, "5.5 kilometers"}
```

### Compound unit formatting

```elixir
speed = Localize.Unit.new!(60, "mile-per-hour")
Localize.Unit.to_string(speed)                   #=> {:ok, "60 miles per hour"}
Localize.Unit.to_string(speed, format: :short)   #=> {:ok, "60 mph"}

density = Localize.Unit.new!(1000, "kilogram-per-cubic-meter")
Localize.Unit.to_string(density, format: :short) #=> {:ok, "1,000 kg/m³"}
```

## Conversion

```elixir
{:ok, km} = Localize.Unit.new(1, "kilometer")
{:ok, m} = Localize.Unit.convert(km, "meter")
m.value  #=> 1000.0

{:ok, c} = Localize.Unit.new(100, "celsius")
{:ok, f} = Localize.Unit.convert(c, "fahrenheit")
Float.round(f.value, 1)  #=> 212.0

{:ok, mph} = Localize.Unit.new(60, "mile-per-hour")
{:ok, mps} = Localize.Unit.convert(mph, "meter-per-second")
Float.round(mps.value, 2)  #=> 26.82
```

### Measurement system conversion

```elixir
{:ok, meters} = Localize.Unit.new(1000, "meter")
{:ok, result} = Localize.Unit.convert_measurement_system(meters, :us)
result.name  #=> "mile"
```

| System | Region | Example preferences |
|---|---|---|
| `:metric` | International | kilometer, kilogram, celsius |
| `:us` | United States | mile, pound, fahrenheit |
| `:uk` | United Kingdom | mile, stone, celsius |

## Arithmetic

### Addition and subtraction

```elixir
a = Localize.Unit.new!(1, "kilometer")
b = Localize.Unit.new!(500, "meter")
{:ok, sum} = Localize.Unit.Math.add(a, b)
{sum.name, sum.value}  #=> {"kilometer", 1.5}
```

### Multiplication

```elixir
u = Localize.Unit.new!(5, "meter")
{:ok, result} = Localize.Unit.Math.mult(u, 3)
result.value  #=> 15
```

### Division (creates compound units)

```elixir
distance = Localize.Unit.new!(100, "meter")
time = Localize.Unit.new!(10, "second")
{:ok, speed} = Localize.Unit.Math.div(distance, time)
speed.name   #=> "meter-per-second"
speed.value  #=> 10.0
```

### Negation and inversion

```elixir
u = Localize.Unit.new!(5, "meter")
{:ok, neg} = Localize.Unit.Math.negate(u)
neg.value  #=> -5

speed = Localize.Unit.new!(4, "meter-per-second")
{:ok, inv} = Localize.Unit.Math.invert(speed)
inv.name   #=> "second-per-meter"
inv.value  #=> 0.25
```

## Common options

| Option | Values | Default |
|---|---|---|
| `:locale` | atom, string, `LanguageTag` | `Localize.get_locale()` |
| `:format` | `:long`, `:short`, `:narrow` | `:long` |

## Unit categories

| Category | Example units |
|---|---|
| Length | meter, kilometer, foot, mile, inch, yard |
| Mass | kilogram, gram, pound, ounce, stone |
| Duration | second, minute, hour, day, week, month, year |
| Temperature | celsius, fahrenheit, kelvin |
| Area | square-meter, hectare, acre |
| Volume | liter, milliliter, cubic-meter, gallon, cup |
| Speed | meter-per-second, kilometer-per-hour, mile-per-hour |
| Energy | joule, kilowatt-hour |
| Power | watt, kilowatt, megawatt |
| Pressure | pascal, bar, atmosphere |
| Frequency | hertz, kilohertz, megahertz |
