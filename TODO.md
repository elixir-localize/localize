# Post-Merge TODO

Remaining work after merging ex_cldr_collation, ex_cldr_currencies, and
ex_cldr_messages into Localize.

## Collation

Collation is functionally complete. No remaining merge work.

* [ ] Review whether locale-specific tailoring covers all CLDR locales
      (currently loads from `collation/tailoring/locale_defaults.ex`)

## Messages (MF2)

The MF2 parser, interpreter, and NIF are merged. The interpreter calls
formatter modules that do not exist yet. These calls compile with
warnings but will raise at runtime when the corresponding MF2 function
annotations are used.

* [ ] `Localize.Number.to_string/2` — used by `:number`, `:integer`,
      `:percent`, and `:currency` MF2 functions
* [ ] `Localize.Date.to_string/2` — used by `:date` MF2 function
* [ ] `Localize.Time.to_string/2` — used by `:time` MF2 function
* [ ] `Localize.DateTime.to_string/2` — used by `:datetime` MF2 function
* [ ] `Localize.Unit.to_string/2` — used by `:unit` MF2 function

## Currency

Core currency validation, territory mappings, custom currency store,
and locale tag integration are complete. Functions that require
per-locale CLDR currency data are stubs returning
`{:error, :not_yet_implemented}`.

### Locale data integration

* [ ] Load per-locale currency data (display names, symbols, plural
      count names) — requires a strategy for the ~307 currencies × ~766
      locales dataset
* [ ] `currency_for_code/2` — return localized currency struct for a
      code and locale
* [ ] `currencies_for_locale/3` — return all currency structs for a
      locale with `:all`/`:current`/`:historic`/`:tender`/`:unannotated`
      filtering
* [ ] `currency_strings/3` — reverse map of localized strings to
      currency codes (for parsing user input)
* [ ] `display_name/2` — localized display name for a currency
* [ ] `pluralize/3` — plural-aware currency name (e.g. "1 US dollar"
      vs "2 US dollars")
* [ ] `strings_for_currency/3` — all strings (name, plurals, symbol)
      that map to a specific currency in a locale
* [ ] `currency_filter/3` — filtering by status works on the struct
      but needs `iso_digits`, `to`, and `name` populated from locale
      data to be meaningful
* [ ] `currency_history_for_locale/1` — territory lookup works but
      locale-to-territory resolution should use full locale inheritance
      chain, not just `tag.territory`

## Data and performance

* [ ] Switch plural rules from compile-time ETF loading to
      `:persistent_term` (user requested, not yet done)
* [ ] Clean up `scripts/convert_currency_data.exs` or integrate the
      JSON-to-ETF conversion into the build process
