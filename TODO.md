# TODO

Feature requests from the Intl library (elixir-localize/intl), which maps the JS `Intl` API onto Localize. Each item closes a documented conformance gap in Intl's [compatibility guide](https://hexdocs.pm/intl/compatibility.html).

All items from the July 22 list are DONE (July 22, 2026, post-rc.0): `:minimum_integer_digits`, `:trailing_zero_display`, `:rounding_priority`, `Localize.Number.to_parts/2`, relative time `numeric: :always`, `known_collations/0` / `known_timezones/0`, plus the `:currency_long` fraction-digits gap found in the same review. The July 23 follow-ups are also DONE (1.0.0-rc.2): fractional seconds in skeleton matching with the locale decimal separator, and the ECMA-402 `:rounding_priority` `:auto` fix.

## Remaining follow-ups (post-1.0 candidates)

The dominant theme is structured format parts (ECMA-402 `formatToParts`) beyond `Localize.Number.to_parts/2`:

* **`to_parts/2` for the `:currency_long` formats.** The long plural pattern composes by substitution after formatting, so its parts path needs `Localize.Substitution` to carry parts through. `to_parts/2` returns a clear error for these formats today.

* **`to_parts/2` for units** (`Localize.Unit.to_parts/2`) — also unblocks Intl `format_to_parts/2` for `style: :unit`.

* **`Localize.Number.to_range_parts/3`** (ECMA-402 `formatRangeToParts`).

* **Date/time parts** — `Localize.Date` / `Localize.Time` / `Localize.DateTime` `to_parts/2` and interval parts, for Intl `DateTimeFormat.formatToParts` / `formatRangeToParts`. The formatter's per-symbol functions are a natural tagging point.

* **List parts** — `Localize.List.to_parts/2` for Intl `ListFormat.formatToParts` (element vs literal segments).

* **Relative time parts** — for Intl `RelativeTimeFormat.formatToParts`.

Beyond parts:

* **Unit ranges** — `Localize.Unit.to_range_string/3`, for Intl `NumberFormat.formatRange` with `style: :unit` ("2–5 kilometers" with the unit applied once per CLDR range patterns).

* **Per-unit duration display options** — `Localize.Duration.to_string/2` control per field (JS `hoursDisplay: "always"`, `fractionalDigits`, per-unit styles), for Intl `DurationFormat`.

* **Compact affix split.** `to_parts/2` tags the whole compact affix as one `:compact` part (" million"); `Intl` splits the leading space into a `:literal`. Callers needing exact JS part boundaries should split on leading/trailing whitespace.

* ~~**MF2 option mapping.**~~ DONE July 22: the MF2 `:number`/`:integer`/`:currency` functions map `minimumIntegerDigits`, `minimumSignificantDigits`, `maximumSignificantDigits`, `trailingZeroDisplay` and `roundingPriority` onto the corresponding `Localize.Number` options.
