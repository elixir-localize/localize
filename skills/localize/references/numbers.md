# Numbers, currencies, and plural rules

Most common calls:

| Task | Call |
|------|------|
| Format a number | `Localize.Number.to_string(1234.5)` → `{:ok, "1,234.5"}` |
| Format money | `Localize.Number.to_string(amount, currency: :EUR)` |
| Percent | `Localize.Number.to_string(0.456, format: :percent)` → `{:ok, "46%"}` |
| Compact ("1.2M") | `Localize.Number.to_string(n, format: :decimal_short)` |
| Plural category | `Localize.Number.PluralRule.plural_type(n, locale: :en)` → `:one` / `:other` |
| Parse localized input | `Localize.Number.parse("1.234,56", locale: :de)` → `{:ok, 1234.56}` |

All functions accept integer, float, or `Decimal` values and return `{:ok, string}` or `{:error, exception}`; each has a `!` variant. `Decimal` input is formatted without float round-tripping, so prefer it for money.

## Format styles

The `:format` option takes a style atom, an RBNF rule name atom, or a CLDR pattern string.

```elixir
Localize.Number.to_string(1234567.89)                                      # :standard is the default
#=> {:ok, "1,234,567.89"}
Localize.Number.to_string(1234.5, format: :currency, currency: :USD)
#=> {:ok, "$1,234.50"}
Localize.Number.to_string(-1234.56, format: :accounting, currency: :USD)   # negatives in parens
#=> {:ok, "($1,234.56)"}
Localize.Number.to_string(1234, format: :currency_long, currency: :USD)
#=> {:ok, "1,234 US dollars"}
Localize.Number.to_string(1234, format: :currency_long_with_symbol, currency: :USD)
#=> {:ok, "$1,234.00 US dollars"}
Localize.Number.to_string(0.456, format: :percent)                         # multiplies by 100
#=> {:ok, "46%"}
Localize.Number.to_string(1234567.89, format: :scientific)
#=> {:ok, "1.23456789E6"}
Localize.Number.to_string(1_234_000, format: :decimal_short)
#=> {:ok, "1.2M"}
Localize.Number.to_string(1_234_000, format: :decimal_long)
#=> {:ok, "1.2 million"}
Localize.Number.to_string(1_234_000, format: :currency_short, currency: :USD)
#=> {:ok, "$1.2M"}
```

`:short` and `:long` are accepted as aliases (ex_cldr compatibility): they resolve to `:decimal_short` / `:decimal_long`, or to `:currency_short` / `:currency_long` when `currency:` is given.

There is no `:permille` style atom — use a pattern with the `‰` symbol (multiplies by 1000):

```elixir
Localize.Number.to_string(0.456, format: "#,##0.0‰")
#=> {:ok, "456.0‰"}
```

RBNF (rule-based) styles spell numbers out algorithmically. `:spellout` and `:ordinal` resolve to the best rule for the locale; specific rule names (`:spellout_cardinal`, `:spellout_ordinal`, `:digits_ordinal`, `:roman_upper`, ...) are also accepted. Discover a locale's rules with `Localize.Number.Rbnf.rule_names_for_locale/1`. Roman numerals and other universal rules live in the root locale `:und`.

```elixir
Localize.Number.to_string(123, format: :spellout)
#=> {:ok, "one hundred twenty-three"}
Localize.Number.to_string(42, format: :spellout_ordinal)
#=> {:ok, "forty-second"}
Localize.Number.to_string(42, format: :ordinal)
#=> {:ok, "42nd"}
Localize.Number.to_string(1, format: :ordinal, locale: :fr)
#=> {:ok, "1er"}
Localize.Number.to_string(2024, format: :roman_upper, locale: :und)         # :roman alone is not a rule name
#=> {:ok, "MMXXIV"}
Localize.Number.to_string(2024, format: :roman)                              # error lists the locale's actual rules
#=> {:error, %Localize.UnknownRbnfRuleError{rule_name: :roman, locale: :en, available: ["digits_ordinal", "spellout_cardinal", "spellout_cardinal_verbose", "spellout_numbering", "spellout_numbering_verbose", "spellout_numbering_year", "spellout_ordinal", "spellout_ordinal_verbose"]}}
```

## Currency options

Setting `:currency` automatically switches the format to `:currency` — no need to pass both. With no `:currency`, `format: :currency` uses the locale's territory-default currency (or a `-u-cu-` extension).

```elixir
Localize.Number.to_string(1234.5, currency: :EUR, locale: :de)               # inspect shows NBSP as \u00A0
#=> {:ok, "1.234,50\u00A0€"}
Localize.Number.to_string(1234.56, currency: :JPY, locale: :ja)              # JPY has 0 decimal places
#=> {:ok, "￥1,235"}
Localize.Number.to_string(100, format: :currency, locale: "en-u-cu-eur")     # currency from -u-cu-
#=> {:ok, "€100.00"}
```

`:currency_symbol` controls how the symbol renders — `:standard` (default), `:iso`, `:narrow`, `:none`, or any literal string:

```elixir
Localize.Number.to_string(1234.5, currency: :USD, currency_symbol: :iso)     # NBSP after USD
#=> {:ok, "USD\u00A01,234.50"}
Localize.Number.to_string(1234.5, currency: :AUD)                            # default symbol disambiguates
#=> {:ok, "A$1,234.50"}
Localize.Number.to_string(1234.5, currency: :AUD, currency_symbol: :narrow)  # narrow assumes context
#=> {:ok, "$1,234.50"}
Localize.Number.to_string(1234.5, currency: :USD, currency_symbol: :none)
#=> {:ok, "1,234.50"}
```

`currency_digits: :cash` uses cash rounding where a currency defines it (CHF cash rounds to 0.05; the default `:accounting` does not):

```elixir
Localize.Number.to_string(1234.63, currency: :CHF, currency_digits: :cash, locale: :en)
#=> {:ok, "CHF\u00A01,234.65"}
```

## Digit and rounding control

```elixir
Localize.Number.to_string(1234.5, fractional_digits: 4)                      # sets min and max together
#=> {:ok, "1,234.5000"}
Localize.Number.to_string(1234.56789, max_fractional_digits: 2)              # rounds
#=> {:ok, "1,234.57"}
Localize.Number.to_string(1234.5, min_fractional_digits: 3)                  # pads with zeros
#=> {:ok, "1,234.500"}
Localize.Number.to_string(1237, round_nearest: 5)                            # nearest increment
#=> {:ok, "1,235"}
Localize.Number.to_string(1234.567, maximum_significant_digits: 3)
#=> {:ok, "1,230"}
Localize.Number.to_string(2.5, fractional_digits: 0, rounding_mode: :half_even)  # banker's rounding is the default
#=> {:ok, "2"}
Localize.Number.to_string(2.5, fractional_digits: 0, rounding_mode: :half_up)
#=> {:ok, "3"}
```

Rounding modes: `:half_even` (default), `:half_up`, `:half_down`, `:up`, `:down`, `:ceiling`, `:floor`.

`:minimum_grouping_digits` suppresses grouping unless the leading group has at least that many digits — some locales (Spanish, Polish) set this to 2 in CLDR, so "1234" but "12.345":

```elixir
Localize.Number.to_string(1234, minimum_grouping_digits: 2)
#=> {:ok, "1234"}
Localize.Number.to_string(12345, minimum_grouping_digits: 2)
#=> {:ok, "12,345"}
Localize.Number.to_string(1234, locale: :es)                                 # Spanish CLDR default
#=> {:ok, "1234"}
```

## Pattern strings

Pass a CLDR pattern directly as `:format`. Key symbols: `0` digit (always shown), `#` digit (omitted if zero), `.` decimal, `,` grouping, `%` percent, `‰` permille, `¤` currency symbol, `¤¤` ISO code, `E` exponent, `;` separates positive;negative subpatterns, `@` significant digit.

```elixir
Localize.Number.to_string(1234.5, format: "#,##0.00")
#=> {:ok, "1,234.50"}
Localize.Number.to_string(42, format: "000")
#=> {:ok, "042"}
Localize.Number.to_string(12.3456, format: "@@##")                           # 2-4 significant digits
#=> {:ok, "12.35"}
Localize.Number.to_string(0.00123456, format: "@@##")                        # significant digits float with magnitude
#=> {:ok, "0.001235"}
```

The `.` and `,` in patterns are placeholders — the locale substitutes its own separators, so one pattern serves every locale.

## Number systems

`:number_system` takes a system name (`:latn`, `:arab`, `:thai`, ...) or a type (`:default`, `:native`). A system must be valid for the locale — `:thai` digits with an English locale is an error. The `-u-nu-` locale extension does the same thing and travels with the locale.

```elixir
Localize.Number.to_string(1234, number_system: :thai, locale: :th)
#=> {:ok, "๑,๒๓๔"}
Localize.Number.to_string(1234, locale: "ar-u-nu-arab")                      # plain :ar defaults to latn digits
#=> {:ok, "١٬٢٣٤"}
Localize.Number.to_string(1234, number_system: :thai)
#=> {:error, %Localize.UnknownNumberSystemError{number_system: :thai, locale: :en, reason: :not_for_locale}}
```

## Per-locale differences

Same number, different locales — separators, grouping size, and compact words all change:

```elixir
Localize.Number.to_string(1234567.89, locale: :de)                           # . groups, , decimal
#=> {:ok, "1.234.567,89"}
Localize.Number.to_string(1234567.89, locale: :fr)                           # narrow no-break space (U+202F) groups
#=> {:ok, "1 234 567,89"}
Localize.Number.to_string(1234567.89, locale: :hi)                           # Indian 3-then-2 grouping
#=> {:ok, "12,34,567.89"}
Localize.Number.to_string(1_234_000, format: :decimal_short, locale: :de)    # NBSP before Mio.
#=> {:ok, "1,2\u00A0Mio."}
Localize.Number.to_string(1_234_000, format: :decimal_short, locale: :ja)    # 万 = ten-thousands
#=> {:ok, "123万"}
```

This is why formatted output must never be assembled by hand — the separators, symbol placement, and even grouping arithmetic are locale data.

## Ranges and approximations

```elixir
Localize.Number.to_range_string(3, 5)                                        # en dash (U+2013), also accepts a Range
#=> {:ok, "3–5"}
Localize.Number.to_range_string(10, 20, currency: :USD)
#=> {:ok, "$10.00–$20.00"}
Localize.Number.to_at_least_string(100)
#=> {:ok, "100+"}
Localize.Number.to_at_most_string(50)                                        # ≤ is U+2264
#=> {:ok, "≤50"}
Localize.Number.to_approximately_string(42)
#=> {:ok, "~42"}
Localize.Number.to_approximately_string(42, locale: :de)                     # approximation sign is locale data too
#=> {:ok, "≈42"}
```

## Parsing and scanning

`parse/2` converts a localized string back to a number; `scan/2` pulls numbers out of prose; `resolve_currencies/2` and `resolve_pers/2` post-process scan output into currency atoms and `:percent`/`:permille` markers.

```elixir
Localize.Number.parse("1,234.56")
#=> {:ok, 1234.56}
Localize.Number.parse("1.234,56", locale: :de)
#=> {:ok, 1234.56}
Localize.Number.parse("1234", number: :integer)
#=> {:ok, 1234}
Localize.Number.parse("abc")
#=> {:error, %Localize.InvalidValueError{value: "abc", expected: "a parseable number string", allowed_values: nil, context: "Localize.Number.Parser"}}
Localize.Number.scan("Take 2 tablets every 4 hours", number: :integer)
#=> ["Take ", 2, " tablets every ", 4, " hours"]
Localize.Number.scan("$100") |> Localize.Number.resolve_currencies()
#=> [:USD, 100]
Localize.Number.scan("50% of users") |> Localize.Number.resolve_pers()
#=> [50, :percent, " of users"]
```

## Plural rules

`plural_type/2` returns the CLDR plural category for a number — the key to choosing between word forms. English has `:one`/`:other`; Arabic uses all six categories. Never write `if count == 1` — that hardcodes English.

```elixir
Localize.Number.PluralRule.plural_type(1, locale: :en)
#=> :one
Localize.Number.PluralRule.plural_type(0, locale: :ar)
#=> :zero
Localize.Number.PluralRule.plural_type(2, locale: :ar)
#=> :two
Localize.Number.PluralRule.plural_type(11, locale: :ar)
#=> :many
Localize.Number.PluralRule.plural_type(42, locale: :en, type: :ordinal)      # 42nd → :two ("nd")
#=> :two
Localize.Number.PluralRule.plural_type(Decimal.new("1.0"), locale: :en)      # visible fraction digits matter: "1.0 files"
#=> :other
```

`Cardinal.pluralize/3` and `Ordinal.pluralize/3` select from a substitutions map. Integer keys are exact matches and win over categories; `:other` is the required fallback:

```elixir
Localize.Number.PluralRule.Cardinal.pluralize(1, :en, %{one: "file", other: "files"})
#=> "file"
Localize.Number.PluralRule.Cardinal.pluralize(0, :en, %{0 => "no files", one: "file", other: "files"})  # exact 0 beats category :other
#=> "no files"
Localize.Number.PluralRule.Ordinal.pluralize(2, :en, %{one: "st", two: "nd", few: "rd", other: "th"})
#=> "nd"
```

For whole sentences, prefer an MF2 message (see message-format.md) — it keeps the plural logic in the translatable string.

## Errors

Invalid input returns tagged exception structs whose `Exception.message/1` is presentable:

```elixir
Localize.Number.to_string(100, currency: :XYZ)
#=> {:error, %Localize.UnknownCurrencyError{currency: :XYZ}}
{:error, error} = Localize.Number.to_string(100, currency: "notreal")
Exception.message(error)
#=> "The currency \"notreal\" is not known."
Localize.Number.to_string(100, locale: "zz-INVALID!")
#=> {:error, %Localize.InvalidLocaleError{locale_id: "zz-INVALID!"}}
Localize.Number.to_string("100")                                             # strings are not parsed implicitly
#=> {:error, %Localize.InvalidValueError{value: "100", expected: "a number (integer, float, or Decimal)", allowed_values: nil, context: nil}}
```

## Performance

For hot loops (tables, batch exports), pre-validate options once with `Localize.Number.Format.Options.validate_options(0, options)` and pass the resulting struct to `to_string/2` — ~3x faster for decimals, ~50x for currency, because currency metadata resolution dominates the per-call cost.
