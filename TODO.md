# Post-Merge TODO

Remaining work after merging ex_cldr_collation, ex_cldr_currencies, and
ex_cldr_messages into Localize.

## Collation

Collation is functionally complete. No remaining merge work.

* [ ] Review whether locale-specific tailoring covers all CLDR locales
      (currently loads from `collation/tailoring/locale_defaults.ex`)

## Messages (MF2)

The MF2 parser, interpreter, and NIF are merged. All formatter modules
are implemented and tested. The interpreter dispatches to:

* [x] `Localize.Number.to_string/2` — used by `:number`, `:integer`,
      `:percent`, and `:currency` MF2 functions
* [x] `Localize.Date.to_string/2` — used by `:date` MF2 function
* [x] `Localize.Time.to_string/2` — used by `:time` MF2 function
* [x] `Localize.DateTime.to_string/2` — used by `:datetime` MF2 function
* [x] `Localize.Unit.to_string/2` — used by `:unit` MF2 function

## Currency

Core currency validation, territory mappings, custom currency store,
and locale tag integration are complete. Per-locale currency data
(display names, symbols, plural count names) is loaded on demand
via `Localize.Locale.get/3`.

### Locale data integration

* [x] Load per-locale currency data (display names, symbols, plural
      count names) — loaded lazily from locale provider
* [x] `currency_for_code/2` — return localized currency struct for a
      code and locale
* [x] `currencies_for_locale/3` — return all currency structs for a
      locale with `:all`/`:current`/`:historic`/`:tender`/`:unannotated`
      filtering
* [x] `currency_strings/3` — reverse map of localized strings to
      currency codes (for parsing user input)
* [x] `display_name/2` — localized display name for a currency
* [x] `pluralize/2` — plural-aware currency name
* [x] `strings_for_currency/2` — all strings (name, plurals, symbol)
      that map to a specific currency in a locale
* [x] `currency_filter/3` — filtering by status
* [ ] `currency_history_for_locale/1` — territory lookup works but
      locale-to-territory resolution should use full locale inheritance
      chain, not just `tag.territory`

## Data and performance

* [x] Switch plural rules from compile-time ETF loading to
      `:persistent_term` — supplemental data loads cached on first
      access; `@rules` attribute removed from Cardinal/Ordinal BEAM
* [x] Cache compiled number format metadata in `:persistent_term`
* [x] Cache compiled datetime format tokens in `:persistent_term`
* [ ] Clean up `scripts/convert_currency_data.exs` or integrate the
      JSON-to-ETF conversion into the build process

## Design review

* [ ] Revisit `Localize.Locale.to_locale_id/1` — currently coerces
      `LanguageTag`, atom, and binary inputs to a locale id atom. The
      nil-cldr_locale_id fallback path (`LanguageTag.to_string |>
      String.to_atom`) may produce atoms that don't correspond to known
      CLDR locales. Consider whether this function should validate
      against known locales, return `{:ok, id} | {:error, _}`, or
      remain a best-effort coercion. Also consider whether callers
      that previously had only the 3-clause version (no nil fallback)
      are affected by now inheriting the 4-clause behaviour.

## Cldr public API merge candidates

Functions from the top-level `Cldr` module that should be considered
for merging into `Localize`. Grouped by priority and effort.

### Already merged

* [x] `validate_locale/1` → `Localize.validate_locale/1`
* [x] `validate_currency/1` → `Localize.Currency.validate_currency/1`
* [x] `known_currencies/0` → `Localize.Currency.known_currencies/0`
* [x] `quote/2` → `Localize.quote/2`
* [x] `ellipsis/2` → `Localize.ellipsis/2`
* [x] `known_territories/0` → `Localize.known_territories/0`
* [x] `known_calendars/0` → `Localize.known_calendars/0`
* [x] `known_number_systems/0` → `Localize.known_number_systems/0`
* [x] `all_locale_names/0` → `Localize.all_locale_names/0`
* [x] `available_locale_name?/1` → `Localize.available_locale_name?/1`
* [x] `flag/1` → `Localize.flag/1`
* [x] `the_world/0` → `Localize.the_world/0`
* [x] `validate_territory/1` → `Localize.validate_territory/1`
* [x] `validate_script/1` → `Localize.validate_script/1`
* [x] `validate_calendar/1` → `Localize.validate_calendar/1`
* [x] `validate_number_system/1` → `Localize.validate_number_system/1`
* [x] `validate_territory_subdivision/1` →
      `Localize.validate_territory_subdivision/1`
* [x] `validate_measurement_system/1` →
      `Localize.validate_measurement_system/1`
* [x] `territory_containment/0` → `Localize.territory_containment/0`
* [x] `known_territory_subdivisions/0` →
      `Localize.known_territory_subdivisions/0`
* [x] `known_territory_subdivision_containment/0` →
      `Localize.known_territory_subdivision_containment/0`
* [x] `territory_chain/1` → `Localize.territory_chain/1`
* [x] `default_territory/1` → `Localize.default_territory/1`

### Tier 4 — Process locale management

* [x] `get_locale/0` → `Localize.get_locale/0` — process dictionary.
* [x] `put_locale/1` → `Localize.put_locale/1`
* [x] `with_locale/2` → `Localize.with_locale/2`
* [x] `default_locale/0` → `Localize.default_locale/0` — app env.
* [x] `put_default_locale/1` → `Localize.put_default_locale/1`
* [x] All formatting functions default `:locale` to
      `Localize.get_locale()` instead of `:en`.

### Not recommended for merge

These are backend-specific or configuration-specific and do not
fit the Localize architecture:

* `default_backend!/0`, `validate_backend/1` — Localize has no
  backend concept.
* `known_locale_names/1`, `requested_locale_names/1` — per-backend
  configured locale subsets.
* `known_gettext_locale_names/1`, `validate_gettext_locale/1` —
  Gettext integration is separate.
* `put_gettext_locale/1` — Gettext-specific.
* `known_rbnf_locale_names/1`, `known_rbnf_locale_name?/1` —
  RBNF is internal implementation detail.
