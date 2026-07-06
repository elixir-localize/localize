# MessageFormat 2 (translatable messages)

Most common calls:

| Task | Call |
|------|------|
| Format a message | `Localize.Message.format(msg, %{"name" => "Ana"})` |
| Raise on error | `Localize.Message.format!(msg, bindings)` |
| Phoenix-safe markup | `Localize.Message.format_to_safe_list(msg, bindings)` |
| Normalize for storage | `Localize.Message.canonical_message(msg)` |
| Compile-time validate | `~M"Hello {$name}!"` (import `Localize.Message.Sigils`) |

MF2 puts plural/gender/select logic inside the (translatable) message instead of Elixir conditionals — translators can restructure the whole sentence per locale. Reach for it whenever a user-visible sentence contains a value.

## Syntax essentials

* Placeholders: `{$variable}`; with a function: `{$count :number}`; function options: `{$n :number minimumFractionDigits=2}`.
* Quoted literals: `{|verbatim text|}` (escape `\|` and `\\` inside); number literals: `{42 :number}`.
* A message starting with `.` or `{{` is complex: `.input` / `.local` declarations first, then a `{{...}}` pattern or `.match` variants.
* Escapes in pattern text: `\{`, `\}`, `\\`.
* Markup: `{#b}bold{/b}`, self-closing `{#img src=|x.jpg| /}` — carried as structure, never interpreted.

```elixir
Localize.Message.format("Hello, {$name}!", %{"name" => "Alice"})
#=> {:ok, "Hello, Alice!"}
Localize.Message.format("Hello, {$name}!", name: "Alice")                     # keyword bindings work too
#=> {:ok, "Hello, Alice!"}
Localize.Message.format("{{Hello {$name}!}}", %{"name" => "World"})           # quoted pattern
#=> {:ok, "Hello World!"}
Localize.Message.format("Literal \\{brace\\} and {$x}", %{"x" => 1})
#=> {:ok, "Literal {brace} and 1"}
Localize.Message.format(".local $g = {|Welcome|}\n{{Dear {$name}, {$g}!}}", %{"name" => "Jane"})
#=> {:ok, "Dear Jane, Welcome!"}
```

## format/3 options

`:locale` (drives every formatting function inside the message), `:trim` (strip surrounding whitespace before parsing, default false), `:backend` (`:elixir` default, `:nif` uses ICU when compiled in), `:functions` (per-call custom function map, see below).

Errors are structured: unbound variables → `Localize.BindError`; bad syntax → `Localize.ParseError` (with line/column); formatting failures → `Localize.FormatError`.

```elixir
Localize.Message.format("Hello {$name}!")
#=> {:error, %Localize.BindError{unbound: ["name"]}}
{:error, error} = Localize.Message.format("Hello {$name}!")
Exception.message(error)
#=> "No binding was found for [\"name\"]"
Localize.Message.format("{$amt :currency}", %{"amt" => 10})                   # missing required option
#=> {:error, %Localize.FormatError{value: "{$amt :currency}", function: :format, reason: :formatter_failed, detail: "currency option is required for :currency format", cause: nil}}
```

Duplicated function options do not error — the last occurrence wins.

## Built-in functions

```elixir
Localize.Message.format("{$n :number}", %{"n" => 1234.5}, locale: :de)
#=> {:ok, "1.234,5"}
Localize.Message.format("{$n :number minimumFractionDigits=2}", %{"n" => 42})
#=> {:ok, "42.00"}
Localize.Message.format("{$n :number maximumFractionDigits=2}", %{"n" => 3.14159})
#=> {:ok, "3.14"}
Localize.Message.format("{$n :number useGrouping=never}", %{"n" => 12345})
#=> {:ok, "12345"}
Localize.Message.format("{$n :number numberingSystem=thai}", %{"n" => 1234})  # any valid system name
#=> {:ok, "๑,๒๓๔"}
Localize.Message.format("{$n :integer}", %{"n" => 4.7})                       # truncates
#=> {:ok, "4"}
Localize.Message.format("{$ratio :percent}", %{"ratio" => 0.85})              # use :percent, not a style option
#=> {:ok, "85%"}
Localize.Message.format("{$amt :currency currency=EUR}", %{"amt" => 42.5}, locale: :de)
#=> {:ok, "42,50\u00A0€"}
Localize.Message.format("{$amt :currency currency=USD currencySign=accounting}", %{"amt" => -50})
#=> {:ok, "($50.00)"}
Localize.Message.format("{$d :unit unit=kilometer}", %{"d" => 5})
#=> {:ok, "5 kilometers"}
Localize.Message.format("{$d :unit unit=kilogram unitDisplay=short}", %{"d" => 2.5})
#=> {:ok, "2.5 kg"}
Localize.Message.format("{$d :unit}", %{"d" => Localize.Unit.new!(5, "mile")})  # Localize.Unit carries its own unit
#=> {:ok, "5 miles"}
Localize.Message.format("{$when :date style=full}", %{"when" => ~D[2026-07-06]})
#=> {:ok, "Monday, July 6, 2026"}
Localize.Message.format("{|2026-07-06| :date style=long}")                    # ISO literals parse
#=> {:ok, "July 6, 2026"}
Localize.Message.format("{$dt :datetime dateStyle=long timeStyle=short}", %{"dt" => ~N[2026-07-06 14:30:00]})
#=> {:ok, "July 6, 2026, 2:30 PM"}
Localize.Message.format("{$x :string}", %{"x" => 42})                         # String.Chars coercion
#=> {:ok, "42"}
Localize.Message.format("{$n :offset add=1}", %{"n" => 5})                    # also subtract=
#=> {:ok, "6"}
Localize.Message.format("{$items :list}", %{"items" => ["apple", "banana", "cherry"]})
#=> {:ok, "apple, banana, and cherry"}
Localize.Message.format("{$items :list style=or}", %{"items" => ["red", "green", "blue"]})
#=> {:ok, "red, green, or blue"}
Localize.Message.format("{$items :list}", %{"items" => [1234, 5678]}, locale: :de)  # elements format locale-aware
#=> {:ok, "1.234 und 5.678"}
```

Function option summary: `:number`/`:integer`/`:offset` take `minimumFractionDigits`, `maximumFractionDigits`, `useGrouping` (`auto`/`always`/`min2`/`never`), `numberingSystem`, `select`; `:currency` requires `currency=`, plus `currencyDisplay` (`symbol`/`narrowSymbol`/`code`) and `currencySign` (`standard`/`accounting`); `:unit` takes `unit=` (unless the operand is a `Localize.Unit`) and `unitDisplay` (`long`/`short`/`narrow`); `:date`/`:time` take `style=` (`short`/`medium`/`long`/`full`); `:datetime` takes `style=`, `dateStyle=`, `timeStyle=`; `:list` takes `style=` (`and`, `or`, `unit`, each with `-short`/`-narrow` variants). The datetime output uses the locale's Unicode variant (a U+202F before AM/PM in English).

## Plural and select matching

`.match` selects the most specific variant (fewest `*` keys). For `:number`/`:integer` selectors, an exact numeric key beats the CLDR plural category, which beats `*` — so `0` can have a dedicated "empty" message even though English lumps 0 into `:other`:

```elixir
message = """
.input {$count :number}
.match $count
0 {{Your cart is empty.}}
one {{You have {$count} item.}}
* {{You have {$count} items.}}
"""
Localize.Message.format(message, %{"count" => 0})
#=> {:ok, "Your cart is empty."}
Localize.Message.format(message, %{"count" => 1})
#=> {:ok, "You have 1 item."}
Localize.Message.format(message, %{"count" => 3})
#=> {:ok, "You have 3 items."}
Localize.Message.format(".input {$n :number}\n.match $n\n1 {{exactly one}}\none {{category one}}\n* {{other}}", %{"n" => 1})
#=> {:ok, "exactly one"}
```

`select=ordinal` switches to ordinal categories; `select=exact` disables category matching entirely:

```elixir
Localize.Message.format(".input {$n :number select=ordinal}\n.match $n\none {{{$n}st}}\ntwo {{{$n}nd}}\nfew {{{$n}rd}}\n* {{{$n}th}}", %{"n" => 42})
#=> {:ok, "42nd"}
Localize.Message.format(".input {$n :number select=exact}\n.match $n\none {{one!}}\n* {{other}}", %{"n" => 1})
#=> {:ok, "other"}
```

Multiple selectors express gender × plural combinations declaratively — every combination visible to the translator:

```elixir
Localize.Message.format("""
.input {$gender :string}
.input {$count :integer}
.match $gender $count
female one {{She has {$count} item.}}
female * {{She has {$count} items.}}
* * {{They have {$count} items.}}
""", %{"gender" => "female", "count" => 3})
#=> {:ok, "She has 3 items."}
```

Selectors must be declared with `.input` or `.local` — `.match {$count :number}` (inline annotation) is not valid MF2 and returns a `ParseError`.

## Markup

`format/3` strips markup tags (children remain). For rendering markup as HTML/HEEx components, `format_to_safe_list/3` returns `{:text, string}` and `{:markup, name, options, children}` tuples; unbalanced markup is an error:

```elixir
Localize.Message.format("Click {#link href=|/home|}here{/link}!")
#=> {:ok, "Click here!"}
Localize.Message.format_to_safe_list("Hello {$name}, click {#b}here{/b}!", %{"name" => "Kip"})
#=> {:ok, [{:text, "Hello Kip, click "}, {:markup, "b", %{}, [text: "here"]}, {:text, "!"}]}
Localize.Message.format_to_safe_list("{#b}oops")
#=> {:error, %Localize.FormatError{value: "{#b}oops", function: :format, reason: :unbalanced_markup, detail: nil, cause: nil}}
```

## Custom functions

Implement `Localize.Message.Function` (a `format/3` callback returning `{:ok, string}` or `{:error, reason}`) and register per-call with `functions:` or globally with `config :localize, :mf2_functions, %{"name" => Module}`. Per-call beats config beats built-ins; an unknown function name silently falls back to `to_string/1`.

```elixir
defmodule Shout do
  @behaviour Localize.Message.Function
  @impl true
  def format(value, _function_options, _options), do: {:ok, String.upcase(to_string(value))}
end
Localize.Message.format("{$name :shout}", %{"name" => "alice"}, functions: %{"shout" => Shout})
#=> {:ok, "ALICE"}
Localize.Message.format("{$name :nosuch}", %{"name" => "alice"})              # unknown fn = to_string passthrough
#=> {:ok, "alice"}
```

## Sigils and canonical form

`import Localize.Message.Sigils` provides `~M` (compile-time parse + canonicalize — a syntax error fails compilation at the exact line/column) and `~m` (same but allows `#{}` interpolation, validated at runtime). Both yield the canonical message string. `canonical_message/2` normalizes whitespace/annotations at runtime — use it before storing messages as translation-table keys so equivalent spellings compare equal:

```elixir
import Localize.Message.Sigils
~m"Hello {$name}!"
#=> "Hello {$name}!"
Localize.Message.canonical_message(".input {$count :number}\n.match $count\n1   {{one}}\n*    {{other}}")
#=> {:ok, ".input {$count :number}\n.match $count\n1 {{one}}\n* {{other}}"}
```

There is also `~t` (via `use Localize.Message.Sigils, backend: MyApp.Gettext`), which turns `~t"Hello, #{@user.name}!"` into a Gettext lookup whose msgid is canonical MF2 with `{$user_name}` placeholders. `jaro_distance/3` scores message similarity for near-duplicate detection.

## MF2 vs Gettext

* **Plain Gettext** fits static strings and simple `%{name}` interpolation with an established translator workflow (.po files, `mix gettext.extract`).
* **MF2** fits anything with plural/gender/select logic, formatted values (money, dates, units), or markup — the logic travels with the translation instead of living in Elixir.
* **Both together**: configure `use Gettext, otp_app: :my_app, interpolation: Localize.Gettext.Interpolation` and write MF2 syntax inside .po msgstrs — Gettext supplies the translation store, MF2 the formatting. The `~t` sigil is the ergonomic front end for this.

A `mix format` plugin (`Localize.Message.Formatter.Plugin`) canonicalizes `~M` sigils and `.mf2` files; `Localize.Message.to_html/2` and `to_ansi/2` render syntax-highlighted messages for docs and tooling.
