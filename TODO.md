# TODO

Feature requests from the Intl library (elixir-localize/intl), which maps the JS `Intl` API onto Localize. Each item closes a documented conformance gap in Intl's [compatibility guide](https://hexdocs.pm/intl/compatibility.html).

## Number formatting

* **`:minimum_integer_digits` option for `Localize.Number.to_string/2`.** Zero-pads the integer part to the given width (ECMA-402 `minimumIntegerDigits`, 1..21). CLDR patterns express this as leading `0` digits (`00,000.###`); the option should synthesize that on top of the resolved format pattern.

* **`:trailing_zero_display` option (`:auto` | `:strip_if_integer`).** ECMA-402 `trailingZeroDisplay`: `:strip_if_integer` drops fraction digits when the rounded value is an integer, even when `:min_fractional_digits` would otherwise pad them (JS: 1000 with minimumFractionDigits 2 and stripIfInteger renders "1,000", 1000.5 renders "1,000.50").

* **`:rounding_priority` option (`:auto` | `:more_precision` | `:less_precision`).** ECMA-402 `roundingPriority` resolves conflicts when both fraction-digit and significant-digit bounds are given. Current behavior (significant digits win) matches `:auto`; `:more_precision`/`:less_precision` pick the bound that yields more/fewer digits per the spec algorithm.

* **Structured format parts (`to_parts/2`).** A parts pipeline for number formatting returning typed segments (integer, group, decimal, fraction, currency, unit, sign, …) per ECMA-402 `formatToParts`. This is the largest remaining Intl gap and also blocks `formatRangeToParts`. Likely a variant of the decimal formatter's reassembly stage that tags instead of concatenates.

## Other

* **Force numeric output in relative time formatting.** `Localize.DateTime.Relative.to_string/2` always auto-selects named forms ("yesterday", "tomorrow"); ECMA-402 `numeric: "always"` needs an option to force "1 day ago" / "in 1 day".

* **Collation and time zone inventories.** `known_collations/0` and `known_timezones/0` (the full IANA zone list backing the metazone data), so `Intl.supported_values_of/1` can support `:collation` and `:time_zone`.
