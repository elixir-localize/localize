# Units of measure

Most common calls:

| Task | Call |
|------|------|
| Create a unit | `Localize.Unit.new!(3.5, "kilometer")` |
| Format | `Localize.Unit.to_string(unit)` → `{:ok, "3.5 kilometers"}` |
| Abbreviated | `Localize.Unit.to_string(unit, format: :short)` → `{:ok, "3.5 km"}` |
| Convert | `Localize.Unit.convert(unit, "mile")` |
| Regional units | `Localize.Unit.to_string(unit, usage: :road, locale: "en-US")` |
| Unit label only | `Localize.Unit.display_name("kilometer")` → `{:ok, "kilometers"}` |

Values are integers, floats, or `Decimal` (no other numeric types). `new/2` returns `{:ok, unit}` / `{:error, exception}`; `new!/2` returns the struct or raises. `new/1` with just a name creates a value-less unit for display names.

```elixir
Localize.Unit.new(1, "flibber")
#=> {:error, %Localize.UnknownUnitError{unit: "flibber"}}
```

## Unit identifiers

Identifiers are lowercase, hyphen-separated CLDR names and compose freely — the grammar builds units you will not find in any list:

* Simple: `meter`, `pound`, `celsius`, `liter`, `hour`, `byte`, `hertz`.
* SI prefixes apply automatically: `kilometer`, `centimeter`, `millisecond`, `megawatt`, `gibibyte`.
* Powers: `square-meter`, `cubic-foot`.
* Rates with `-per-`: `mile-per-hour`, `kilogram-per-cubic-meter`.
* Products (times-compounds) by juxtaposition: `kilowatt-hour`, `newton-meter`.
* Constants: `liter-per-100-kilometer`, `curr-usd-per-100-kilometer`.
* Currencies as units: `curr-usd`, `curr-eur-per-hour` (any ISO code after `curr-`).
* Mixed units with `-and-`: `foot-and-inch`, `hour-and-minute` (see below).

## Formatting

`to_string/2` styles: `:long` (default, full plural-aware names), `:short`, `:narrow`. Plural selection and unit names are locale data.

```elixir
Localize.Unit.new!(3.5, "kilometer") |> Localize.Unit.to_string()
#=> {:ok, "3.5 kilometers"}
Localize.Unit.new!(1, "kilometer") |> Localize.Unit.to_string()                     # plural-aware
#=> {:ok, "1 kilometer"}
Localize.Unit.new!(3.5, "kilometer") |> Localize.Unit.to_string(format: :short)
#=> {:ok, "3.5 km"}
Localize.Unit.new!(3.5, "kilometer") |> Localize.Unit.to_string(format: :narrow)
#=> {:ok, "3.5km"}
Localize.Unit.new!(2.5, "kilogram") |> Localize.Unit.to_string(locale: :de)         # number format follows too
#=> {:ok, "2,5 Kilogramm"}
Localize.Unit.new!(5, "kilowatt-hour") |> Localize.Unit.to_string()
#=> {:ok, "5 kilowatt-hours"}
Localize.Unit.new!(5, "kilowatt-hour") |> Localize.Unit.to_string(format: :short)
#=> {:ok, "5 kWh"}
Localize.Unit.new!(10, "meter-per-second") |> Localize.Unit.to_string(format: :short)
#=> {:ok, "10 m/s"}
Localize.Unit.new!(5, "liter-per-100-kilometer") |> Localize.Unit.to_string()
#=> {:ok, "5 liters per 100 kilometers"}
Localize.Unit.new!(5, "curr-usd-per-100-kilometer") |> Localize.Unit.to_string()    # money as a unit numerator
#=> {:ok, "$5.00 per 100 kilometers"}
Localize.Unit.new!(5, "curr-eur-per-hour") |> Localize.Unit.to_string(locale: :de)  # NBSP before the euro sign
#=> {:ok, "5,00\u00A0€ pro Stunde"}
```

## Conversion

`convert/2` and `convert!/2` convert between units that reduce to the same base dimensions; temperature offsets are handled. Incompatible dimensions return `UnitConversionError`.

```elixir
{:ok, km} = Localize.Unit.new!(1, "mile") |> Localize.Unit.convert("kilometer")
km.value
#=> 1.609344
Localize.Unit.new!(60, "mile-per-hour") |> Localize.Unit.convert!("kilometer-per-hour") |> Localize.Unit.to_string(format: :short)
#=> {:ok, "96.561 km/h"}
Localize.Unit.new!(1, "meter") |> Localize.Unit.convert("kilogram")
#=> {:error, %Localize.UnitConversionError{from: "meter", to: "kilogram", reason: :not_convertible}}
```

`convert_measurement_system/2` targets `:metric`, `:us`, or `:uk` preferred units (1000 meters → mile for `:us`).

## Usage-based preferences

Pass `usage:` to `to_string/2` and the value renders in the unit people actually use for that context in the locale's territory — CLDR picks by territory AND magnitude (US road distances are feet when short, miles when long).

```elixir
Localize.Unit.new!(2000, "meter") |> Localize.Unit.to_string(usage: :road, locale: "en-US", format: :short)
#=> {:ok, "1.243 mi"}
Localize.Unit.new!(2000, "meter") |> Localize.Unit.to_string(usage: :road, locale: "de-DE")
#=> {:ok, "2 Kilometer"}
Localize.Unit.new!(1.83, "meter") |> Localize.Unit.to_string(usage: :person_height, locale: "en-US")
#=> {:ok, "6 feet and 0.047 inches"}
Localize.Unit.new!(1.83, "meter") |> Localize.Unit.to_string(usage: :person_height, locale: "en-US", list_options: [list_style: :unit])
#=> {:ok, "6 feet, 0.047 inches"}
```

Common usages: `:default`, `:person_height`, `:person_weight`, `:road`, `:food`, `:vehicle_fuel` (also accepted as hyphenated strings, and as `usage:` on `new/3`, which sticks to the struct). To see what a usage resolves to, or to pick a territory independent of the locale:

```elixir
Localize.Unit.Preference.preferred_units(Localize.Unit.new!(180, "centimeter"), usage: :person_height, territory: :US)
#=> {:ok, [:foot, :inch], []}
{:ok, parts} = Localize.Unit.localize(Localize.Unit.new!(1.83, "meter"), usage: :person_height, territory: :US)
Localize.Unit.to_string(parts, locale: :de)                                          # US units, German words
#=> {:ok, "6 Fuß und 0,047 Zoll"}
```

## Mixed units and decompose

`decompose/2` splits one value across a unit ladder (integer part per rung, remainder to the last); the result is a list of units that `to_string/2` accepts directly:

```elixir
{:ok, parts} = Localize.Unit.new!(1.83, "meter") |> Localize.Unit.decompose(["foot", "inch"])
Localize.Unit.to_string(parts)
#=> {:ok, "6 feet and 0.047 inches"}
```

Converting to an `-and-` identifier also works — the value becomes a list — but a list-valued unit cannot be passed to `to_string/2` (it returns `InvalidValueError`). For rendering, prefer `decompose/2`, `usage:`, or `localize/2`:

```elixir
{:ok, mixed} = Localize.Unit.new!(180, "centimeter") |> Localize.Unit.convert("foot-and-inch")
mixed.value
#=> [5, 10.866141732283467]
```

## Arithmetic

`Localize.Unit.Math` does dimensional arithmetic. Add/subtract converts the second operand to the first's unit; multiplying different dimensions builds a product unit; dividing different dimensions builds a `-per-` unit; dividing same dimensions cancels to a bare scalar; multiplying same dimensions consolidates to a square.

```elixir
{:ok, sum} = Localize.Unit.Math.add(Localize.Unit.new!(1, "kilometer"), Localize.Unit.new!(500, "meter"))
{sum.name, sum.value}
#=> {"kilometer", 1.5}
{:ok, speed} = Localize.Unit.Math.div(Localize.Unit.new!(100, "meter"), Localize.Unit.new!(10, "second"))
{speed.name, speed.value}
#=> {"meter-per-second", 10.0}
{:ok, product} = Localize.Unit.Math.mult(Localize.Unit.new!(2, "meter"), Localize.Unit.new!(3, "second"))
product.name
#=> "meter-second"
```

`use Localize.Unit.Operators` in a module rebinds `+`, `-`, `*`, `/` to unit-aware versions (raising on error) while passing plain numbers through to the standard operators — natural syntax for physics-style code:

```elixir
defmodule Physics do
  use Localize.Unit.Operators
  def speed(distance, time), do: distance / time
end
Physics.speed(Localize.Unit.new!(100, "meter"), Localize.Unit.new!(10, "second")).name
#=> "meter-per-second"
```

Also available: `Math.negate/1`, `Math.invert/1` (4 m/s → 0.25 s/m), `Math.round/2`.

## Display names

`display_name/2` returns the unit's label without a value — for table headers, axis labels, pickers:

```elixir
Localize.Unit.display_name("kilometer")
#=> {:ok, "kilometers"}
Localize.Unit.display_name("kilometer", locale: :fr)
#=> {:ok, "kilomètres"}
Localize.Unit.display_name("kilometer", format: :short)
#=> {:ok, "km"}
```

## Grammatical case

Inflected languages change the unit word by grammatical case; pass `:grammatical_case` when the formatted unit sits in a sentence position other than nominative. Wrong case reads as broken grammar to native speakers even though the default looks fine in isolation.

```elixir
Localize.Unit.new!(2, "kilometer") |> Localize.Unit.to_string(locale: :de, grammatical_case: :dative)
#=> {:ok, "2 Kilometern"}
Localize.Unit.new!(2, "day") |> Localize.Unit.to_string(locale: :uk)                 # Ukrainian nominative
#=> {:ok, "2 дні"}
Localize.Unit.new!(2, "day") |> Localize.Unit.to_string(locale: :uk, grammatical_case: :instrumental)
#=> {:ok, "2 днями"}
```

`:grammatical_gender` is accepted for compatibility (it selects gender-keyed compound patterns where CLDR provides them); for simple units the gender is fixed by the unit's CLDR data, so the option usually changes nothing.

## Custom units

`define_unit/2` registers runtime units that then convert, format, and do arithmetic like built-ins. Linear units need `:base_unit`, `:factor`, `:category`; `:offset` and per-locale `:display` patterns are optional (without `:display`, formatting falls back to the raw name):

```elixir
Localize.Unit.define_unit("smoot", %{base_unit: "meter", factor: 1.7018, category: "length"})
#=> :ok
converted = Localize.Unit.new!(3, "smoot") |> Localize.Unit.convert!("meter")
Float.round(converted.value, 4)
#=> 5.1054
Localize.Unit.new!(3, "smoot") |> Localize.Unit.to_string()
#=> {:ok, "3 smoot"}
```

Custom units automatically accept SI prefixes (`kilosmoot`) and powers (`square-smoot`). Nonlinear scales (decibel, hydrometer degrees) register with `factor: :special` plus `forward: {Module, :fun}` / `inverse: {Module, :fun}` arity-1 conversions to/from the base unit. Bulk registration: `Localize.Unit.CustomRegistry.register_batch/1`; file loading: `Localize.Unit.load_custom_units("priv/custom_units.exs")` where the file evaluates to a list of definition maps each including a `:unit` key.

## The struct

`%Localize.Unit{}` has `:name`, `:value`, `:usage`, `:format_options`, and a `:parsed` AST. Read `:name` and `:value`; treat `:parsed` as opaque. Store quantities as `Localize.Unit` (or value + unit name) and format at the presentation edge — never store the formatted string.
