# Plural Rules Guide

This guide explains how to use `Localize.Number.PluralRule` and its `Localize.Number.PluralRule.Cardinal` and `Localize.Number.PluralRule.Ordinal` modules to classify numbers into CLDR plural categories, and how plural selection works inside MessageFormat 2 messages.

## Overview

Languages disagree about how many grammatical forms a counted noun can take. English has two ("1 message", "2 messages"), Japanese has one, Russian has four, Welsh has six, and Arabic uses all six CLDR categories. CLDR models this with a fixed set of plural categories — `:zero`, `:one`, `:two`, `:few`, `:many`, and `:other` — and a per-locale rule set that maps any number to one of them.

`Localize.Number.PluralRule.plural_type/2` is the primary function. It returns the plural category for a number in a locale:

```elixir
iex> Localize.Number.PluralRule.plural_type(1, locale: :en)
:one

iex> Localize.Number.PluralRule.plural_type(2, locale: :en)
:other

iex> Localize.Number.PluralRule.plural_type(1, locale: :ja)
:other

iex> Localize.Number.PluralRule.known_plural_types()
[:zero, :one, :two, :few, :many, :other]
```

Every locale has an `:other` category — it is the mandatory fallback. The remaining categories are only present where the locale's grammar distinguishes them:

```elixir
iex> Localize.Number.PluralRule.plural_type(0, locale: :ar)
:zero

iex> Localize.Number.PluralRule.plural_type(2, locale: :ar)
:two

iex> Localize.Number.PluralRule.plural_type(11, locale: :ar)
:many

iex> Localize.Number.PluralRule.plural_type(2, locale: :cy)
:two

iex> Localize.Number.PluralRule.plural_type(3, locale: :cy)
:few
```

The category names are grammatical, not arithmetic. Russian `:one` covers 21, 31, 41 and so on — any number ending in 1 but not 11:

```elixir
iex> Localize.Number.PluralRule.plural_type(21, locale: :ru)
:one

iex> Localize.Number.PluralRule.plural_type(2, locale: :ru)
:few

iex> Localize.Number.PluralRule.plural_type(5, locale: :ru)
:many
```

## Cardinal vs ordinal

CLDR defines two independent rule sets per locale:

* **Cardinal** rules classify quantities — "1 message", "2 messages". This is the default (`type: :cardinal`).

* **Ordinal** rules classify positions — "1st", "2nd", "3rd", "4th". English cardinal rules have only `:one` and `:other`, but English ordinal rules need four categories to select the right suffix.

```elixir
iex> Localize.Number.PluralRule.plural_type(2, locale: :en)
:other

iex> Localize.Number.PluralRule.plural_type(2, locale: :en, type: :ordinal)
:two

iex> Localize.Number.PluralRule.plural_type(3, locale: :en, type: :ordinal)
:few

iex> Localize.Number.PluralRule.plural_type(11, locale: :en, type: :ordinal)
:other

iex> Localize.Number.PluralRule.plural_type(21, locale: :en, type: :ordinal)
:one
```

The English ordinal categories map to suffixes: `:one` → "st" (1st, 21st), `:two` → "nd" (2nd, 22nd), `:few` → "rd" (3rd, 23rd), `:other` → "th" (4th, 11th).

Not every locale defines ordinal rules — CLDR ships cardinal rules for over 200 languages but ordinal rules for around half that. When a locale has no ordinal rules, `plural_type/2` returns an error rather than guessing.

## The operands intuition — why 1.0 is not 1

Plural rules do not operate on the numeric value alone. They operate on a set of **operands** derived from the number *as it would be displayed*, defined in [TR35](https://unicode.org/reports/tr35/tr35-numbers.html#Operands):

| Operand | Meaning |
|---------|---------|
| `n` | Absolute value of the number. |
| `i` | Integer digits of `n`. |
| `v` | Count of visible fraction digits, with trailing zeros. |
| `w` | Count of visible fraction digits, without trailing zeros. |
| `f` | Visible fraction digits as an integer, with trailing zeros. |
| `t` | Visible fraction digits as an integer, without trailing zeros. |

The English cardinal rule for `:one` is `i = 1 and v = 0` — the integer part is 1 *and there are no visible fraction digits*. So `1` is `:one`, but `1.0` is `:other`, because "1.0 messages" reads as a measured quantity, not a count:

```elixir
iex> Localize.Number.PluralRule.plural_type(1, locale: :en)
:one

iex> Localize.Number.PluralRule.plural_type(1.0, locale: :en)
:other

iex> Localize.Number.PluralRule.plural_type(Decimal.new("1"), locale: :en)
:one

iex> Localize.Number.PluralRule.plural_type(Decimal.new("1.0"), locale: :en)
:other
```

This is why passing a `Decimal` can matter: a `Decimal` carries its own precision, so `Decimal.new("1.00")` has `v = 2` and selects differently from the integer `1`. Floats are considered with their visible fraction digits after default rounding.

Languages weight the operands differently. French `:one` covers everything that rounds to an integer part of 0 or 1, fraction digits included:

```elixir
iex> Localize.Number.PluralRule.plural_type(1.5, locale: :fr)
:one

iex> Localize.Number.PluralRule.plural_type(1.5, locale: :en)
:other
```

## Locale resolution

The locale is validated through `Localize.validate_locale/1`, so aliases resolve and regional variants select region-specific rules. Portugal and Brazil disagree about zero:

```elixir
iex> Localize.Number.PluralRule.Cardinal.plural_rule(0, "pt")
:one

iex> Localize.Number.PluralRule.Cardinal.plural_rule(0, "pt-PT")
:other
```

## The Cardinal and Ordinal modules

`Localize.Number.PluralRule.Cardinal` and `Localize.Number.PluralRule.Ordinal` expose the two rule sets directly with an identical API.

### `plural_rule/2` — classify a number

```elixir
iex> Localize.Number.PluralRule.Cardinal.plural_rule(1, "en")
:one

iex> Localize.Number.PluralRule.Ordinal.plural_rule(3, "en")
:few
```

### `pluralize/3` — select from a substitution map

`pluralize/3` classifies the number and returns the matching value from a map keyed by plural category. An exact-number key takes precedence over the category, and `:other` is the fallback:

```elixir
iex> Localize.Number.PluralRule.Cardinal.pluralize(1, "en", %{one: "message", other: "messages"})
"message"

iex> Localize.Number.PluralRule.Cardinal.pluralize(3, "en", %{one: "message", other: "messages"})
"messages"

iex> Localize.Number.PluralRule.Cardinal.pluralize(0, "en", %{0 => "no messages", one: "message", other: "messages"})
"no messages"
```

Building an English ordinal suffix is the classic ordinal use case:

```elixir
iex> Localize.Number.PluralRule.Ordinal.pluralize(2, "en", %{one: "st", two: "nd", few: "rd", other: "th"})
"nd"

iex> Localize.Number.PluralRule.Ordinal.pluralize(11, "en", %{one: "st", two: "nd", few: "rd", other: "th"})
"th"
```

For fully spelled-out ordinals ("forty-second"), use RBNF instead — see the [Number Formatting](https://hexdocs.pm/localize/number_formatting.html) guide's rule-based formatting section.

### Inspecting the rules

`plural_rules_for/1` returns the parsed rule set for a locale as a keyword list of `{category, rule}` pairs; the categories present tell you which forms the language distinguishes:

```elixir
iex> Localize.Number.PluralRule.Cardinal.plural_rules_for(:en) |> Keyword.keys()
[:one, :other]

iex> Localize.Number.PluralRule.Cardinal.plural_rules_for(:ar) |> Keyword.keys()
[:zero, :one, :two, :few, :many, :other]

iex> Localize.Number.PluralRule.Ordinal.plural_rules_for(:en) |> Keyword.keys()
[:one, :two, :few, :other]
```

`available_locale_names/0` lists the locales for which rules exist, and `plural_rules/0` returns the entire parsed rule map.

## Plural selection in MF2 messages

The same rules drive plural selection in MessageFormat 2 messages via `Localize.Message.format/3`. A `.match` on a `:number`-annotated variable selects the variant whose key matches the value's plural category:

```elixir
iex> message = """
...> .input {$count :number}
...> .match $count
...> one {{You have {$count} message}}
...> *   {{You have {$count} messages}}
...> """
iex> Localize.Message.format(message, %{count: 1}, locale: :en)
{:ok, "You have 1 message"}
iex> Localize.Message.format(message, %{count: 3}, locale: :en)
{:ok, "You have 3 messages"}
```

Exact-value keys beat category keys, mirroring `pluralize/3`:

```elixir
iex> message = """
...> .input {$count :number}
...> .match $count
...> 0   {{No messages}}
...> one {{One message}}
...> *   {{{$count} messages}}
...> """
iex> Localize.Message.format(message, %{count: 0}, locale: :en)
{:ok, "No messages"}
iex> Localize.Message.format(message, %{count: 5}, locale: :en)
{:ok, "5 messages"}
```

Ordinal selection uses the `select=ordinal` function option:

```elixir
iex> message = """
...> .input {$place :number select=ordinal}
...> .match $place
...> one {{{$place}st place}}
...> two {{{$place}nd place}}
...> few {{{$place}rd place}}
...> *   {{{$place}th place}}
...> """
iex> Localize.Message.format(message, %{place: 3}, locale: :en)
{:ok, "3rd place"}
iex> Localize.Message.format(message, %{place: 11}, locale: :en)
{:ok, "11th place"}
```

Because selection runs on the *formatted* value, formatting options that change the visible fraction digits also change the selected category — exactly the `1` vs `1.0` distinction described above. See the [Message Formatting](https://hexdocs.pm/localize/message_formatting.html) guide for the full MF2 syntax.

## Options reference

Options accepted by `Localize.Number.PluralRule.plural_type/2`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:locale` | atom, string, or `LanguageTag` | `Localize.get_locale()` | Locale whose plural rules are used. Validated through `Localize.validate_locale/1`. |
| `:type` | `:cardinal` or `:ordinal` | `:cardinal` | Which rule set to apply. |
| `:backend` | `:elixir` or `:nif` | `:elixir` | When `:nif` and the NIF is compiled, classification is delegated to ICU4C PluralRules. Falls back to Elixir silently when unavailable. |

An unknown locale, or a locale without rules for the requested type, returns `{:error, %Localize.UnknownPluralRulesError{}}`.
