# MessageFormat 2 Guide

This guide explains how to use `Localize.Message` for formatting messages using [Unicode MessageFormat 2](https://unicode.org/reports/tr35/tr35-messageFormat.html) (MF2) syntax. MF2 is the successor to the legacy ICU Message Format and provides a clearer, more extensible syntax with explicit declarations, a function registry, pattern matching, and markup support.

## Overview

`Localize.Message.format/3` formats a message string with variable bindings, producing locale-aware output. Messages can contain plain text, interpolated variables, formatted values (numbers, dates, currencies, units), and plural/gender selection.

```elixir
iex> Localize.Message.format("Hello, {$name}!", %{"name" => "Alice"})
{:ok, "Hello, Alice!"}

iex> Localize.Message.format("You have {$count :number} items.", %{"count" => 1234})
{:ok, "You have 1,234 items."}
```

## Message structure

Every MF2 message is either a **simple message** or a **complex message**.

### Simple messages

A simple message is plain text with optional placeholders. It cannot start with `.` or `{{`.

```
Hello, world!
Hello, {$name}!
Today is {$date :date style=medium}.
```

Simple messages are the most common form. Text is literal; placeholders are enclosed in `{ }`.

### Complex messages

A complex message starts with declarations (`.input`, `.local`) or a body keyword (`.match`, `{{`). The output pattern is always wrapped in `{{ }}` (a quoted pattern) or defined by `.match` variants.

```
.input {$name :string}
{{Hello, {$name}!}}
```

```
.input {$count :number}
.local $greeting = {|Welcome|}
.match $count
  1 {{You have one item, {$greeting}.}}
  * {{You have {$count} items, {$greeting}.}}
```

Complex messages are particularly useful when multiple selectors are combined. The structure makes it clear to translators what combinations exist:

```
.input {$pronoun :string}
.input {$count :number}
.match $pronoun $count
  he one   {{He has {$count} notification.}}
  he *     {{He has {$count} notifications.}}
  she one  {{She has {$count} notification.}}
  she *    {{She has {$count} notifications.}}
  * one    {{They have {$count} notification.}}
  * *      {{They have {$count} notifications.}}
```

## Variables

Variables are prefixed with `$` and refer to values passed as bindings at format time. Variable names are case sensitive.

```elixir
iex> Localize.Message.format("Hello, {$name}!", %{"name" => "World"})
{:ok, "Hello, World!"}
```

Bindings can be provided as a map with string keys or as a keyword list with atom keys:

```elixir
iex> Localize.Message.format("Hello, {$name}!", name: "World")
{:ok, "Hello, World!"}
```

## Literals

### Quoted literals

Quoted literals are enclosed in `| |` and can contain any text. Use `\\` to escape `\` and `\|` to escape `|` within quoted literals.

```
{|Hello, world!|}
{|special chars: \| and \\|}
```

### Number literals

Number literals follow the pattern `[-] digits [. digits] [e [+-] digits]`:

```
{42}
{3.14}
{1.5e3}
```

## Expressions

An expression is enclosed in `{ }` and consists of an optional operand, an optional function annotation, and optional attributes.

```
{$variable}                           Variable reference
{$count :number}                      Variable with function
{|literal text| :string}              Literal with function
{:datetime}                           Function-only (no operand)
{$x :number minimumFractionDigits=2}  Function with options
```

The general form is `{ [operand] [:function [options...]] [@attribute...] }`.

## Functions

Functions transform or format values. They are invoked with `:functionName` syntax inside an expression.

### `:string`

String coercion. Converts the operand to its string representation.

```elixir
iex> Localize.Message.format("{$x :string}", %{"x" => 42})
{:ok, "42"}

iex> Localize.Message.format("{$flag :string}", %{"flag" => true})
{:ok, "true"}
```

### `:number`

Locale-aware number formatting.

```
{$count :number}
{$price :number minimumFractionDigits=2}
{$total :number minimumFractionDigits=1 maximumFractionDigits=4}
{$plain :number useGrouping=never}
```

| Option | Values | Description |
|--------|--------|-------------|
| `minimumFractionDigits` | integer | Minimum decimal places (pads with trailing zeros). |
| `maximumFractionDigits` | integer | Maximum decimal places (rounds beyond this). |
| `useGrouping` | `auto`, `always`, `min2`, `never` | Controls grouping separators. `never` suppresses them. |
| `numberingSystem` | `latn`, `arab`, `deva`, etc. | Selects a numbering system. |
| `select` | `plural`, `ordinal`, `exact` | Controls `.match` key resolution (see Pattern Matching). |

```elixir
iex> Localize.Message.format("{$n :number minimumFractionDigits=2}", %{"n" => 42})
{:ok, "42.00"}

iex> Localize.Message.format("{$n :number maximumFractionDigits=2}", %{"n" => 3.14159})
{:ok, "3.14"}

iex> Localize.Message.format("{$n :number useGrouping=never}", %{"n" => 12345})
{:ok, "12345"}
```

### `:integer`

Formats a number as an integer (truncates the decimal part).

```elixir
iex> Localize.Message.format("{$n :integer}", %{"n" => 4.7})
{:ok, "4"}
```

### `:percent`

Formats a number as a percentage. A value of `0.85` formats as `85%`.

```elixir
iex> Localize.Message.format("{$ratio :percent}", %{"ratio" => 0.85})
{:ok, "85%"}
```

### `:currency`

Formats a number as a currency amount.

```
{$amount :currency currency=USD}
{$amount :currency currency=EUR currencyDisplay=narrowSymbol}
{$amount :currency currency=USD currencySign=accounting}
```

| Option | Values | Description |
|--------|--------|-------------|
| `currency` | ISO 4217 code (e.g., `USD`, `EUR`) | The currency to format with (required). |
| `currencyDisplay` | `symbol`, `narrowSymbol`, `code` | How to display the currency identifier. |
| `currencySign` | `standard`, `accounting` | `accounting` uses parentheses for negative values. |

### `:unit`

Formats a number with a measurement unit.

```
{$distance :unit unit=kilometer}
{$weight :unit unit=kilogram unitDisplay=short}
{$temp :unit unit=fahrenheit unitDisplay=narrow}
```

| Option | Values | Description |
|--------|--------|-------------|
| `unit` | CLDR unit identifier | The unit to format with (required unless binding is a `Localize.Unit`). |
| `unitDisplay` | `long`, `short`, `narrow` | How to display the unit name (default: `long`). |

When the bound value is a `Localize.Unit` struct, the unit and value are derived automatically:

```
{$distance :unit}
```

### `:date`

Formats a date value. Accepts `Date`, `NaiveDateTime`, `DateTime` structs, or ISO 8601 string literals.

```
{$when :date}
{$when :date style=short}
{|2006-01-02| :date style=long}
```

| Option | Values | Description |
|--------|--------|-------------|
| `style` / `length` | `short`, `medium`, `long`, `full` | Date format style (default: `medium`). |

### `:time`

Formats a time value. Accepts `Time`, `NaiveDateTime`, `DateTime` structs, or ISO 8601 datetime string literals.

```
{$when :time}
{$when :time style=short}
```

| Option | Values | Description |
|--------|--------|-------------|
| `style` | `short`, `medium`, `long`, `full` | Time format style (default: `medium`). |
| `precision` | `second`, `minute` | `second` maps to `medium`, `minute` maps to `short`. |

### `:datetime`

Formats a combined date and time value.

```
{$when :datetime}
{$when :datetime dateStyle=long timeStyle=short}
```

| Option | Values | Description |
|--------|--------|-------------|
| `style` | `short`, `medium`, `long`, `full` | Sets both date and time style (default: `medium`). |
| `dateStyle` / `dateLength` | `short`, `medium`, `long`, `full` | Date portion style. |
| `timeStyle` / `timePrecision` | `short`, `medium`, `long`, `full` | Time portion style/precision. |

## Declarations

Declarations appear at the start of a complex message, before the body.

### `.input`

Declares an external variable and optionally applies a function to it:

```
.input {$count :number}
```

This declares that `$count` is expected as input and should be formatted using `:number`. Subsequent references to `$count` in the message body will use the formatted value.

### `.local`

Binds a new local variable to an expression:

```
.local $greeting = {|Welcome|}
.local $doubled = {$count :number minimumFractionDigits=2}
```

Local variables are available in the message body and in subsequent declarations.

## Pattern matching with `.match`

The `.match` statement selects one of several variant patterns based on the runtime value of one or more selector expressions.

### Single selector

```elixir
iex> Localize.Message.format(~S"""
...> .input {$count :number}
...> .match $count
...>   0 {{Your cart is empty.}}
...>   1 {{You have one item in your cart.}}
...>   * {{You have {$count} items in your cart.}}
...> """, %{"count" => 3})
{:ok, "You have 3 items in your cart."}
```

### Multiple selectors

```elixir
iex> Localize.Message.format(~S"""
...> .input {$gender :string}
...> .input {$count :integer}
...> .match $gender $count
...>   male 1 {{He bought one item.}}
...>   female 1 {{She bought one item.}}
...>   * 1 {{They bought one item.}}
...>   male * {{He bought {$count} items.}}
...>   female * {{She bought {$count} items.}}
...>   * * {{They bought {$count} items.}}
...> """, %{"gender" => "female", "count" => 3})
{:ok, "She bought 3 items."}
```

### Variant keys

Each variant has one key per selector. Keys can be:

* **Literal keys**: match when the selector value equals the literal (e.g., `0`, `1`, `male`, `female`).

* **Catchall `*`**: matches any value (lowest priority).

### Matching rules

1. All keys in a variant must match their corresponding selector values.

2. Literal keys are matched by string or numeric equality.

3. Variants are sorted by specificity: fewer `*` keys means more specific.

4. The most specific matching variant is selected.

### Plural category matching

The `:number` and `:integer` functions support plural category matching via the `select` option:

* `select=plural` (default): resolves to CLDR cardinal plural categories (`zero`, `one`, `two`, `few`, `many`, `other`). Exact numeric keys are matched first, then category keys.

* `select=ordinal`: resolves to CLDR ordinal plural categories.

* `select=exact`: matches by literal equality only, no plural category resolution.

## Markup

MF2 supports markup elements for structured output. Markup is typically used to wrap regions of text that should become HTML elements, function components, or other host-format structures at render time.

```
{#link}click here{/link}
{#img src=|photo.jpg| /}
{#button type=|submit|}Click me{/button}
```

Markup elements accept the same option and attribute syntax as expressions.

### `format/3` versus `format_to_safe_list/3`

The standard `Localize.Message.format/3` function returns a string and **strips markup tags** from the output. Open and close tags are removed; their children remain:

```elixir
iex> Localize.Message.format("Click {#link href=|/home|}here{/link}!")
{:ok, "Click here!"}
```

To preserve markup as structure, use `Localize.Message.format_to_safe_list/3`. It returns a nested list of `{:text, String.t()}` and `{:markup, name, options, children}` tuples that a renderer (HEEX component, EEx template, custom HTML builder, etc.) can turn into real output:

```elixir
iex> Localize.Message.format_to_safe_list(
...>   "Hello {$name}, click {#link href=|/home|}here{/link}!",
...>   %{"name" => "Kip"}
...> )
{:ok, [
  {:text, "Hello Kip, click "},
  {:markup, "link", %{"href" => "/home"}, [{:text, "here"}]},
  {:text, "!"}
]}
```

Variable interpolation, plural selection, and all other MF2 features work normally — only the markup tags themselves are preserved as structure instead of being stripped.

Unbalanced markup (an open tag without a close, or a close tag without a matching open) returns `{:error, %Localize.FormatError{}}`.

## Escape sequences

Within pattern text (inside `{{ }}`):

| Sequence | Produces |
|----------|----------|
| `\\` | `\` |
| `\{` | `{` |
| `\}` | `}` |

Within quoted literals (inside `| |`):

| Sequence | Produces |
|----------|----------|
| `\\` | `\` |
| `\|` | `|` |

## Gettext integration

`Localize.Message` integrates with Gettext as a custom interpolation module. When configured, Gettext `.po` files use MF2 syntax for message formatting with full locale-aware interpolation.

Configure Gettext to use MF2 interpolation:

```elixir
use Gettext, otp_app: :my_app, interpolation: Localize.Gettext.Interpolation
```

Messages in `.po` files then use MF2 syntax:

```
msgid "You have {$count :number} items."
msgstr "Sie haben {$count :number} Artikel."
```

## API reference

### `Localize.Message.format/3`

Formats an MF2 message with bindings.

* `message` is an MF2 message string.

* `bindings` is a map with string keys or a keyword list.

* `options` is a keyword list.

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:locale` | atom, string, or `LanguageTag` | `Localize.get_locale()` | Locale for formatting functions. |
| `:trim` | boolean | `false` | Trim leading/trailing whitespace from the message before parsing. |

**Returns:**

* `{:ok, formatted_string}` on success.

* `{:error, exception}` on failure, where the exception is a `Localize.BindError` for unbound variables, a `Localize.FormatError` for formatting failures, or a `Localize.ParseError` for invalid syntax.

### `Localize.Message.format!/3`

Same as `format/3` but returns the string directly or raises on error.

### `Localize.Message.format_to_iolist/3`

Formats an MF2 message into an iolist with binding tracking.

**Returns:**

* `{:ok, iolist, bound_variables, unbound_variables}` on success.

* `{:error, iolist, bound_variables, unbound_variables}` when variables cannot be resolved.

### `Localize.Message.canonical_message/2`

Normalizes a message to its canonical MF2 form.

### `Localize.Message.jaro_distance/3`

Calculates the Jaro distance (0.0 to 1.0) between two messages, useful for detecting near-duplicate translations.

## Complete examples

### Number formatting

```elixir
iex> Localize.Message.format("{$n :number minimumFractionDigits=2}", %{"n" => 42})
{:ok, "42.00"}
```

### Local variable binding

```elixir
iex> Localize.Message.format(~S"""
...> .input {$first :string}
...> .input {$last :string}
...> .local $greeting = {|Welcome|}
...> {{Dear {$first} {$last}, {$greeting}!}}
...> """, %{"first" => "Jane", "last" => "Doe"})
{:ok, "Dear Jane Doe, Welcome!"}
```

### Plural selection

```elixir
iex> Localize.Message.format(~S"""
...> .input {$count :number}
...> .match $count
...>   0 {{Your cart is empty.}}
...>   1 {{You have one item in your cart.}}
...>   * {{You have {$count} items in your cart.}}
...> """, %{"count" => 0})
{:ok, "Your cart is empty."}
```

### Gender and plural selection

```elixir
iex> Localize.Message.format(~S"""
...> .input {$gender :string}
...> .input {$count :integer}
...> .match $gender $count
...>   male 1 {{He bought one item.}}
...>   female 1 {{She bought one item.}}
...>   * 1 {{They bought one item.}}
...>   male * {{He bought {$count} items.}}
...>   female * {{She bought {$count} items.}}
...>   * * {{They bought {$count} items.}}
...> """, %{"gender" => "male", "count" => 5})
{:ok, "He bought 5 items."}
```

## Specification compliance

The Localize MF2 implementation targets the [Unicode MessageFormat 2.0 specification](https://unicode.org/reports/tr35/tr35-messageFormat.html) (part of CLDR Technical Standard #35).

| Area | Status |
|------|--------|
| Simple messages | Fully supported |
| Complex messages (declarations + quoted pattern) | Fully supported |
| `.input` and `.local` declarations | Fully supported |
| `.match` with single and multiple selectors | Fully supported |
| Variant matching with literal keys and `*` catchall | Fully supported |
| Quoted and unquoted literals | Fully supported |
| Number literals (integer, decimal, scientific) | Fully supported |
| Variables with string and atom key lookup | Fully supported |
| Function annotations and options | Fully supported |
| Attributes (`@name`, `@name=value`) | Parsed; not used in formatting |
| Markup (open, close, self-closing) | Parsed; rendered as empty strings |
| Escape sequences | Fully supported |
| BiDi controls and ideographic space | Fully supported |

### Built-in function registry

| Function | Spec Status | Implementation |
|----------|-------------|----------------|
| `:string` | Default | String coercion via `String.Chars` |
| `:number` | Default | Locale-aware via `Localize.Number` |
| `:integer` | Default | Integer format via `Localize.Number` |
| `:date` | Default | Date formatting via `Localize.Date` |
| `:time` | Default | Time formatting via `Localize.Time` |
| `:datetime` | Default | DateTime formatting via `Localize.DateTime` |
| `:percent` | Extended | Percent format via `Localize.Number` |
| `:currency` | Extended | Currency format via `Localize.Number` |
| `:unit` | Extended | Unit format via `Localize.Unit` |
| `:list` | Localize | Locale-aware list join via `Localize.List` |

### `:list` — locale-aware list formatting

`:list` is a Localize-specific extension that takes a list operand and formats it as a localized conjunction or disjunction by delegating to `Localize.List.to_string/2`. Each element of the list is itself formatted via `Localize.Chars`, so a list of dates, numbers, units, currencies, or any other type with a `Localize.Chars` implementation is rendered locale-aware end-to-end with no extra work from the message author.

```elixir
iex> Localize.Message.format("{$items :list}", %{"items" => ["apple", "banana", "cherry"]}, locale: :en)
{:ok, "apple, banana, and cherry"}

iex> Localize.Message.format("{$items :list}", %{"items" => [1234, 5678]}, locale: :de)
{:ok, "1.234 und 5.678"}

iex> Localize.Message.format("{$items :list}", %{"items" => [~D[2025-07-10], ~D[2025-08-15]]}, locale: :en)
{:ok, "Jul 10, 2025 and Aug 15, 2025"}
```

The function accepts a `style` (or `type`) option that maps to a CLDR list style. Recognised values:

| `style` value | CLDR list style | Use |
|---|---|---|
| `"and"` *(default)* | `:standard` | Conjunction with the locale's "and"/"und"/"et" word |
| `"and-short"` | `:standard_short` | Shorter conjunction (e.g. abbreviated "&") |
| `"and-narrow"` | `:standard_narrow` | Narrowest conjunction |
| `"or"` | `:or` | Disjunction with "or"/"oder"/"ou" |
| `"or-short"` | `:or_short` | Shorter disjunction |
| `"or-narrow"` | `:or_narrow` | Narrowest disjunction |
| `"unit"` | `:unit` | Used for unit lists ("3 ft 7 in") |
| `"unit-short"` | `:unit_short` | Shorter unit-list join |
| `"unit-narrow"` | `:unit_narrow` | Narrowest unit-list join |

```elixir
iex> Localize.Message.format(~S({$items :list style=or}), %{"items" => ["red", "green", "blue"]}, locale: :en)
{:ok, "red, green, or blue"}

iex> Localize.Message.format(~S({$items :list style=unit-narrow}), %{"items" => ["3", "ft", "7", "in"]}, locale: :en)
{:ok, "3 ft 7 in"}
```

Embedding `:list` in a larger message is straightforward:

```elixir
iex> Localize.Message.format(
...>   "You have {$items :list} in your cart.",
...>   %{"items" => ["apple", "banana", "cherry"]},
...>   locale: :en
...> )
{:ok, "You have apple, banana, and cherry in your cart."}
```

Passing a non-list operand returns a format error rather than crashing.

### Custom MF2 functions

Any module that implements the `Localize.Message.Function` behaviour can be registered as a custom MF2 function. This lets companion packages (like `localize_person_names`) and end-user code add domain-specific functions without modifying Localize core.

**Registration options:**

1. **Per-call** — pass a `:functions` map in the options:

```elixir
iex> {:ok, name} = Localize.PersonName.new(given_name: "José", surname: "Valim", locale: "pt")
iex> Localize.Message.format(
...>   "Author: {$name :personName format=long formality=formal usage=referring}",
...>   %{"name" => name},
...>   locale: :en,
...>   functions: %{"personName" => Localize.PersonName.MF2}
...> )
```

2. **Application-level** — register once in `config/config.exs`:

```elixir
# config/config.exs
config :localize, :mf2_functions, %{
  "personName" => Localize.PersonName.MF2,
  "money"      => MyApp.MoneyFunction
}
```

Per-call functions take precedence over application-level functions, which take precedence over built-in functions. Unknown function names with no registry entry fall back to `Kernel.to_string/1`.

**Implementing a custom function:**

```elixir
defmodule MyApp.MoneyFunction do
  @behaviour Localize.Message.Function

  @impl true
  def format(%MyApp.Money{amount: amount, currency: currency}, func_opts, options) do
    locale = Keyword.get(options, :locale)
    Localize.Number.to_string(amount, locale: locale, currency: currency)
  end

  def format(value, _func_opts, _options) do
    {:error, "expected a Money struct, got #{inspect(value)}"}
  end
end
```

See `Localize.Message.Function` for the full callback specification.
