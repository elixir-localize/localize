# Plan: `units` — An Elixir unit conversion calculator

## Overview

Build an Elixir clone of the Unix/Linux/BSD/macOS `units` utility as a standalone Mix project in `../units`. Uses `Localize.Unit` as the primary engine for unit creation, conversion, arithmetic, and localized output. Adds a NimbleParsec-based expression parser and an interpreter that evaluates unit expressions interactively or from the command line.

## Project structure

```
../units/
├── lib/
│   ├── units.ex                    # Public API
│   ├── units/
│   │   ├── parser.ex               # NimbleParsec expression parser
│   │   ├── interpreter.ex          # AST evaluator
│   │   ├── formatter.ex            # Output formatting (terse, verbose, locale-aware)
│   │   ├── repl.ex                 # Interactive REPL
│   │   ├── cli.ex                  # escript / Mix task entry point
│   │   ├── error.ex                # User-friendly error formatting
│   │   └── aliases.ex              # Unit alias resolution (shorthand → CLDR name)
├── test/
│   ├── units/
│   │   ├── parser_test.exs
│   │   ├── interpreter_test.exs
│   │   └── integration_test.exs
├── mix.exs
├── README.md
└── .formatter.exs
```

## Dependencies

```elixir
{:localize, path: "../localize"},   # or {:localize, "~> 0.1"}
{:nimble_parsec, "~> 1.0"},
```

Optional for the REPL:
```elixir
{:owl, "~> 0.11"},                  # For styled terminal output (optional)
```

## Grammar

The expression language extends GNU `units` syntax with Elixir-friendly conventions. NimbleParsec compiles the grammar to pattern-matching functions at compile time.

### Expression grammar (EBNF-style)

```
expression     = conversion | computation

# "3 meters to feet" or "3 meters in feet" or "3 meters -> feet"
conversion     = computation , ("to" | "in" | "->") , unit_expr

# Arithmetic on quantities
computation    = term , { ("+" | "-") , term }
term           = factor , { ("*" | "/") , factor }
factor         = base , [ "^" , exponent ]
                | base , [ integer ]          # concatenated exponent: cm3
exponent       = number | "(" , expression , ")"
base           = "(" , expression , ")"
                | function_call
                | quantity
                | unit_expr

# "3.5 meters", "3 km/h", just "meters"
quantity       = [ number ] , unit_expr
unit_expr      = unit_name , { ("/" | "per" | "*" | "-" | " ") , unit_name }
unit_name      = identifier , [ prefix_or_power ]

# Functions
function_call  = identifier , "(" , expression , { "," , expression } , ")"

# Literals
number         = float | integer | rational
rational       = integer , "|" , integer      # GNU units style: 1|3 = 1/3
float          = digit+ , "." , digit+ , [ "e" , ["-"] , digit+ ]
integer        = digit+
identifier     = letter , { letter | digit | "_" }
```

### Operator precedence (highest to lowest)

| Precedence | Operators | Associativity | Notes |
|---|---|---|---|
| 1 | `^`, concatenated exponent | right | `cm^3`, `m2` |
| 2 | juxtaposition (space) | left | `kg m` = `kg * m` (higher than `/`) |
| 3 | `*`, `/`, `per` | left | `m/s/s` = `m/s^2` |
| 4 | `+`, `-` | left | Conformable units only |
| 5 | `to`, `in`, `->` | n/a | Conversion (outermost) |

### Key parsing rules

* **Juxtaposition multiplication** has higher precedence than `/`, matching GNU units: `kg m / s^2` = `(kg * m) / s^2`, not `kg * (m / s^2)`.
* **`per`** is a synonym for `/`: `miles per hour` = `miles / hour`.
* **Rational numbers** use `|`: `1|3 meter` = ⅓ meter (GNU convention — avoids ambiguity with division).
* **Concatenated exponents**: `cm3` = `cm^3` but only for single-digit exponents on recognised unit names.
* **Negative exponents**: `s^-2` or `s^(-2)`.
* **Implicit quantity 1**: bare `meter` = `1 meter`.

## Interpreter

The interpreter walks the AST produced by the parser, building `Localize.Unit` structs and applying operations.

### Evaluation rules

| AST node | Action |
|---|---|
| `{:number, n}` | Return bare number |
| `{:quantity, n, unit_ast}` | `Localize.Unit.new!(n, resolve_unit_name(unit_ast))` |
| `{:add, left, right}` | `Localize.Unit.Math.add(eval(left), eval(right))` → unwrap or error |
| `{:sub, left, right}` | `Localize.Unit.Math.sub(eval(left), eval(right))` → unwrap or error |
| `{:mult, left, right}` | `Localize.Unit.Math.mult(eval(left), eval(right))` |
| `{:div, left, right}` | `Localize.Unit.Math.div(eval(left), eval(right))` |
| `{:power, base, exp}` | Repeated multiplication or `Localize.Unit.new!(value, "square-X")` etc. |
| `{:convert, expr, target}` | `eval(expr)` then `Localize.Unit.convert(result, target)` |
| `{:function, name, args}` | Dispatch to built-in math functions |
| `{:negate, expr}` | `Localize.Unit.Math.negate(eval(expr))` |

### Unit name resolution

The parser produces raw identifier strings. The interpreter resolves them against Localize.Unit's known units via an alias table:

```elixir
# Exact CLDR names
"meter" → "meter"
"kilometer" → "kilometer"

# Common aliases / abbreviations
"m" → "meter"
"km" → "kilometer"
"ft" → "foot"
"in" → "inch"
"lb" → "pound"
"oz" → "ounce"
"mph" → "mile-per-hour"
"kph" → "kilometer-per-hour"
"°C" → "celsius"
"°F" → "fahrenheit"
"K" → "kelvin"
"N" → "newton"
"Pa" → "pascal"
"J" → "joule"
"W" → "watt"
"Hz" → "hertz"
"L" → "liter"
"mL" → "milliliter"
"g" → "gram"
"kg" → "kilogram"
"s" → "second"
"min" → "minute"
"h" → "hour"
"mi" → "mile"
"yd" → "yard"

# SI prefix expansion
"cm" → "centimeter"
"mm" → "millimeter"
"µm" → "micrometer"
"nm" → "nanometer"
"GHz" → "gigahertz"
"MW" → "megawatt"
```

The alias table is built at compile time from Localize.Unit's known-units data plus a hand-curated abbreviation map.

### Built-in functions

| Function | Description | Example |
|---|---|---|
| `sqrt(x)` | Square root (unit must have even powers) | `sqrt(9 m^2)` → `3 m` |
| `cbrt(x)` | Cube root | `cbrt(27 m^3)` → `3 m` |
| `abs(x)` | Absolute value | `abs(-5 m)` → `5 m` |
| `round(x)` | Round to nearest integer value | `round(3.7 kg)` → `4 kg` |
| `ceil(x)` | Ceiling | `ceil(3.2 m)` → `4 m` |
| `floor(x)` | Floor | `floor(3.7 m)` → `3 m` |

Dimensionless functions (require dimensionless or bare-number input):
| `sin`, `cos`, `tan`, `asin`, `acos`, `atan` | Trig (radians) |
| `ln`, `log`, `log2` | Logarithms |
| `exp` | e^x |

## REPL (interactive mode)

```
$ units
Units v0.1.0 — type "help" for commands, "quit" to exit

> 3 meters to feet
9.84252 feet

> 60 mph to km/h
96.5606 kilometer-per-hour

> 100 kg * 9.8 m/s^2
980 kilogram-meter-per-square-second

> 1 gallon to liters
3.78541 liter

> 12 ft + 3 in
3.7338 meter

> 12 ft + 3 in to ft
12.25 foot

> sqrt(100 m^2)
10 meter

> _ to cm
1000 centimeter

> 1|3 cup to mL
78.8627 milliliter
```

### REPL features

* **`_` (underscore)**: refers to the previous result, enabling chained conversions.
* **`help`**: prints available commands and syntax.
* **`list [category]`**: lists known units, optionally filtered by category.
* **`conformable <unit>`**: lists all units conformable (same dimension) with the given unit.
* **`quit` / `exit` / Ctrl-D**: exits.
* **History**: uses Erlang's built-in `:io.get_line/1` with readline support.
* **Locale-aware output**: respects `Localize.get_locale()` for number formatting in results. `locale <id>` command changes the display locale.

## CLI (non-interactive mode)

```bash
# Single conversion
$ units "3 meters" "feet"
9.84252

# Expression evaluation
$ units "60 mph to km/h"
96.5606 kilometer-per-hour

# Verbose mode
$ units -v "1 gallon" "liters"
1 gallon = 3.78541 liter

# Terse mode (for scripts)
$ units -t "100 celsius" "fahrenheit"
212

# Locale-aware output
$ units --locale de "1234.5 meter to kilometer"
1,2345 Kilometer

# List conformable units
$ units --conformable meter
foot, yard, mile, inch, kilometer, centimeter, ...
```

### CLI options

| Flag | Description |
|---|---|
| `-v`, `--verbose` | Show `from = to` format |
| `-t`, `--terse` | Bare numeric result only |
| `-q`, `--quiet` | Suppress prompts in interactive mode |
| `--locale <id>` | Set the formatting locale |
| `--conformable <unit>` | List all conformable units |
| `--list [category]` | List known units |
| `--version` | Print version |
| `--help` | Print help |

## Error handling

User-facing errors should be clear and actionable:

```
> 3 meters + 5 kilograms
** Conformability error: cannot add "meter" (length) and "kilogram" (mass)

> 3 frobnicators
** Unknown unit: "frobnicators"
   Did you mean: "foot", "furlong", "fahrenheit"?

> sqrt(9 m^3)
** Dimension error: cannot take square root of m^3 (odd power of meter)

> 1|0 meter
** Division by zero in rational number

> 3 meters to
** Parse error: expected unit expression after "to"
```

### Error strategy

* Parse errors: NimbleParsec produces byte offsets; the error module formats them with a caret pointing to the problem position.
* Conformability errors: show both dimensions in human-readable form.
* Unknown units: fuzzy-match against the alias table using `String.jaro_distance/2` to suggest corrections.
* Localize.Unit errors: catch `{:error, exception}` tuples and format with `Exception.message/1`.

## Extensions beyond GNU `units`

### 1. Locale-aware output

All output is formatted through `Localize.Unit.to_string/2` and `Localize.Number.to_string/2`, so the display respects the user's locale:

```
> locale de
Locale set to :de

> 1234.5 meter to kilometer
1,2345 Kilometer

> locale ja
Locale set to :ja

> 1234.5 meter to kilometer
1.2345 キロメートル
```

### 2. Variables

```
> let distance = 42.195 km
> let time = 2 h + 1 min + 39 s
> distance / time
20.8496 kilometer-per-hour
> _ to mph
12.9543 mile-per-hour
```

### 3. Mixed-unit display

```
> 3.756 hours to h;min;s
3 hour, 45 minute, 21.6 second
```

Uses `Localize.List.to_string/2` for locale-aware conjunction.

### 4. Unit information

```
> info meter
meter (length)
  SI base unit
  Aliases: m
  Conformable: foot, yard, mile, inch, kilometer, centimeter, ...

> info mph
mile-per-hour (speed)
  Aliases: mph
  = 0.44704 meter-per-second
```

### 5. Pipe-friendly

```bash
# Read from stdin
echo "3 meters" | units - feet

# Use in scripts
DISTANCE=$(units -t "marathon to miles")
```

## Implementation phases

### Phase 1: Core (MVP)

1. Mix project setup with `localize` dependency.
2. Unit alias table (`aliases.ex`).
3. NimbleParsec expression parser (`parser.ex`) — numbers, unit names, `+`, `-`, `*`, `/`, `^`, `to`/`in`/`->`, parentheses.
4. Interpreter (`interpreter.ex`) — evaluate AST against `Localize.Unit`.
5. Formatter (`formatter.ex`) — terse, verbose, locale-aware output.
6. Basic REPL (`repl.ex`) — interactive loop with `_` history.
7. Tests for parser and interpreter.

### Phase 2: Polish

8. CLI entry point (`cli.ex`) — escript or `mix units` task.
9. Error module with fuzzy suggestions.
10. Built-in functions (`sqrt`, `abs`, `round`, etc.).
11. Rational number syntax (`1|3`).
12. Concatenated exponents (`cm3`).
13. `--conformable` and `--list` commands.
14. `help` and `info` REPL commands.

### Phase 3: Extensions

15. Variables (`let x = ...`).
16. Mixed-unit display (`h;min;s`).
17. Pipe/stdin support.
18. Locale switching in REPL.
19. Hex package and documentation.

## Test plan

* **Parser tests**: one test per grammar production, edge cases (negative exponents, rational numbers, deeply nested parens, operator precedence).
* **Interpreter tests**: unit creation, conversion, arithmetic, conformability errors, function calls.
* **Integration tests**: full expression → formatted output, matching GNU `units` output for a reference set of conversions.
* **Error tests**: every error path produces a user-readable message.
* **REPL tests**: send commands via `StringIO` and assert output.

## Design principles

1. **Localize.Unit is the engine** — no custom conversion tables, no custom unit database. Every unit operation delegates to `Localize.Unit`, `Localize.Unit.Math`, `Localize.Unit.Conversion`. The alias table maps user-friendly names to CLDR unit identifiers.

2. **Parse errors are not crashes** — every user input path returns a structured error that the error module formats into a helpful message. No raw exceptions reach the user.

3. **Locale-awareness is a first-class feature** — not a bolt-on. Output always goes through `Localize.to_string/2`. The REPL has a `locale` command. The CLI has a `--locale` flag.

4. **Composable** — the parser, interpreter, and formatter are separate modules with clean APIs. Library users can embed the expression evaluator in their own applications without the REPL or CLI.

5. **Joy** — the tool should feel delightful to use. Fuzzy suggestions for typos. Colourful REPL output. `_` for chaining. `let` for variables. Mixed-unit display. `info` for exploration.
