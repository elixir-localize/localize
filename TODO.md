# TODO

Feature requests from the Intl library (elixir-localize/intl), which maps the JS `Intl` API onto Localize. Each item closes a documented conformance gap in Intl's [compatibility guide](https://hexdocs.pm/intl/compatibility.html).

All items from the July 22 list are DONE (July 22, 2026, post-rc.0): `:minimum_integer_digits`, `:trailing_zero_display`, `:rounding_priority`, `Localize.Number.to_parts/2`, relative time `numeric: :always`, `known_collations/0` / `known_timezones/0`, plus the `:currency_long` fraction-digits gap found in the same review.

## Remaining follow-ups (post-1.0 candidates)

* **`to_parts/2` for the `:currency_long` formats.** The long plural pattern composes by substitution after formatting, so its parts path needs `Localize.Substitution` to carry parts through. `to_parts/2` returns a clear error for these formats today.

* **`to_parts/2` for units** (`Localize.Unit.to_parts/2`) and **`to_range_parts/3`** (ECMA-402 `formatRangeToParts`).

* **Compact affix split.** `to_parts/2` tags the whole compact affix as one `:compact` part (" million"); `Intl` splits the leading space into a `:literal`. Callers needing exact JS part boundaries should split on leading/trailing whitespace.

* **MF2 option mapping.** TR35 MessageFormat lists `minimumIntegerDigits`, `trailingZeroDisplay` and `roundingPriority` as `:number`/`:currency` function options; the MF2 interpreter does not map them yet. Localize.Number now supports all three natively, so this is a camelCase-to-option mapping in `build_number_options`.
