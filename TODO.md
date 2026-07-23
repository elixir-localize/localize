# TODO

Feature requests from the Intl library (elixir-localize/intl), which maps the JS `Intl` API onto Localize. Each item closes a documented conformance gap in Intl's [compatibility guide](https://hexdocs.pm/intl/compatibility.html).

All items are DONE and published as of localize 1.0.0-rc.3 / intl 1.0.0-rc.0 (July 23, 2026), verified against the published packages: the digit-control options (`:minimum_integer_digits`, `:trailing_zero_display`, `:rounding_priority`), relative time `numeric: :always`, `known_collations/0` / `known_timezones/0`, the `:currency_long` fraction-digits/plural semantics, the MF2 digit-control option mapping, fractional-second skeletons, and the complete structured-parts family — `Number.to_parts/2` (including `:currency_long`), `Number.to_range_parts/3`, `Unit.to_parts/2` and `Unit.to_range_string/3`, `Date`/`Time`/`DateTime` `to_parts/2`, `List.to_parts/2`, `Relative.to_parts/2`, and the per-unit `Duration` display options.

## Known deviation (accepted)

* **Compact affix split.** `Number.to_parts/2` tags the whole compact affix as one `:compact` part (`" million"`, leading space included); JS `Intl` splits the leading space into a separate `:literal` part. Callers needing exact JS part boundaries can split leading/trailing whitespace off the `:compact` part.
