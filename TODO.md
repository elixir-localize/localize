# TODO

Feature requests from the Intl library (elixir-localize/intl), which maps the JS `Intl` API onto Localize. Each item closes a documented conformance gap in Intl's [compatibility guide](https://hexdocs.pm/intl/compatibility.html).

All items are DONE and published as of localize 1.0.0-rc.3 / intl 1.0.0-rc.0 (July 23, 2026), verified against the published packages: the digit-control options (`:minimum_integer_digits`, `:trailing_zero_display`, `:rounding_priority`), relative time `numeric: :always`, `known_collations/0` / `known_timezones/0`, the `:currency_long` fraction-digits/plural semantics, the MF2 digit-control option mapping, fractional-second skeletons, and the complete structured-parts family — `Number.to_parts/2` (including `:currency_long`), `Number.to_range_parts/3`, `Unit.to_parts/2` and `Unit.to_range_string/3`, `Date`/`Time`/`DateTime` `to_parts/2`, `List.to_parts/2`, `Relative.to_parts/2`, and the per-unit `Duration` display options.

## Open items

* ~~**`Localize.Unit.parse/2` and `parse_unit_name/2`**~~ DONE July 24 (unreleased): localized unit-string parsing with a per-locale inverted name index, `:only`/`:except` category/name filters, canonical-grammar fallback for compounds, and custom-unit awareness. The migration guide documents the `Cldr.Unit.parse/2` mapping.

* **Hyphenated custom unit names.** `define_unit/2` accepts names containing hyphens ("parse-test-cubit") but `new/2` cannot resolve them — the unit-identifier grammar consumes hyphens as compound separators before the custom registry is consulted. Either reject hyphenated names at registration or check the registry for the full name before grammar parsing.

## Known deviation (accepted)

* **Compact affix split.** `Number.to_parts/2` tags the whole compact affix as one `:compact` part (`" million"`, leading space included); JS `Intl` splits the leading space into a separate `:literal` part. Callers needing exact JS part boundaries can split leading/trailing whitespace off the `:compact` part.
