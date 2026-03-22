# Data Sources

This document describes the origin, generation method, and
upstream source for every ETF data file in `priv/cldr/`.

ETF (Erlang Term Format) files are loaded at runtime by
`Localize.SupplementalData` using `:erlang.binary_to_term/1`
and cached in `:persistent_term` on first access.

## Upstream repositories

All data ultimately derives from the Unicode CLDR project.
Two intermediate repositories are used:

* **`../cldr`** — a pre-processed CLDR data repository
  maintained by `ex_cldr`. Contains JSON files derived from
  CLDR XML by the `ex_cldr` build process.

* **`../cldr_repo`** — a checkout of the Unicode CLDR
  repository. Contains the raw XML source files.

## Generation methods

There are three methods used to produce the ETF files:

1. **Extracted from `ex_cldr` at runtime** — an `iex` session
   or one-off script called a `Cldr.Config` function (which
   loads and transforms JSON from the `cldr` repo) and wrote
   the result with `:erlang.term_to_binary/1`. No conversion
   script was saved for these files.

2. **Conversion script (JSON to ETF)** — a reusable script in
   `scripts/` reads JSON from `../cldr/priv/cldr/`, transforms
   the data (atomising keys, parsing dates, restructuring), and
   writes ETF.

3. **Extraction script (XML to ETF)** — a reusable script in
   `scripts/` reads CLDR XML from `../cldr_repo/`, parses it
   with `SweetXml`, and writes ETF.

## File inventory

### `priv/cldr/` (top-level)

| File | Source | Method |
|------|--------|--------|
| `all_locale_names.etf` | `../cldr/priv/cldr/available_locales.json` | Extracted from `Cldr.Config.all_locale_names()` |
| `known_territories.etf` | `../cldr/priv/cldr/territory_containers.json` | Extracted from `Cldr.Config.known_territories()` |
| `unicode_script_to_subtag_mapping.etf` | Internal `ex_cldr` script metadata | Extracted from `Cldr.Config` — maps Unicode script names (e.g., `:hiragana`) to BCP 47 subtags (e.g., `:Hira`) |

### `priv/cldr/supplemental_data/`

| File | Source | Method |
|------|--------|--------|
| `aliases.etf` | `../cldr/priv/cldr/aliases.json` | Extracted from `Cldr.Config.aliases()` |
| `calendar_preferences.etf` | `../cldr/priv/cldr/calendar_preferences.json` | Extracted from `Cldr.Config.calendar_preferences()` |
| `currency_codes.etf` | `../cldr/priv/cldr/currencies.json` | Script: `scripts/convert_currency_data.exs` — reads JSON list of currency code strings, converts to sorted atom list |
| `language_matching.etf` | `../cldr/priv/cldr/language_matching.json` | Extracted from `Cldr.Config.language_matching()` |
| `likely_subtags.etf` | `../cldr/priv/cldr/likely_subtags.json` | Extracted from `Cldr.Config.likely_subtags()` |
| `parent_locales.etf` | `../cldr/priv/cldr/parent_locales.json` | Extracted from `Cldr.Config.parent_locales()` |
| `plural_ranges.etf` | `../cldr/priv/cldr/plural_ranges.json` | Extracted from `Cldr.Config.plural_ranges()` |
| `plural_rules_cardinal.etf` | `../cldr/priv/cldr/plural_rules.json` | Extracted from `Cldr.Config.plural_rules()` — cardinal rules subset, parsed into AST |
| `plural_rules_ordinal.etf` | `../cldr/priv/cldr/plural_rules.json` | Extracted from `Cldr.Config.plural_rules()` — ordinal rules subset, parsed into AST |
| `territories.etf` | `../cldr/priv/cldr/territories.json` | Ad-hoc script (see below) — territory metadata with GDP, population, currency, measurement system, language population |
| `territory_codes.etf` | `../cldr/priv/cldr/territory_codes.json` | Ad-hoc script (see below) — maps Alpha-2 codes to Alpha-3, FIPS 10, numeric |
| `territory_containers.etf` | `../cldr/priv/cldr/territory_containers.json` | Ad-hoc script (see below) — maps container territories to their children |
| `territory_containment.etf` | `../cldr/priv/cldr/territory_containment.json` | Ad-hoc script (see below) — maps each territory to its containment chain |
| `territory_currencies.etf` | `../cldr/priv/cldr/territory_currencies.json` | Script: `scripts/convert_currency_data.exs` — transforms currency history with date parsing |
| `territory_subdivision_containment.etf` | `../cldr/priv/cldr/territory_subdivision_containment.json` | Ad-hoc script (see below) — subdivision containment hierarchy |
| `territory_subdivisions.etf` | `../cldr/priv/cldr/territory_subdivisions.json` | Ad-hoc script (see below) — maps territories to subdivision codes |
| `time_preferences.etf` | `../cldr/priv/cldr/time_preferences.json` | Extracted from `Cldr.Config` or ad-hoc script |
| `number_systems.etf` | `../cldr/priv/cldr/number_systems.json` | Extracted from `Cldr.Config.number_systems()` — maps 97 number system name atoms to definitions containing `:type` (`:numeric` or `:algorithmic`) and either `:digits` (10-character string) or `:rules` (RBNF rule reference). Loaded at runtime by `Localize.Number.System` and cached in `:persistent_term`. |
| `timezones.etf` | `../cldr/priv/cldr/timezones.json` | Extracted from `Cldr.Config.timezones()` |
| `unit_data.etf` | `../cldr_repo/common/supplemental/units.xml` and `../cldr_repo/common/validity/unit.xml` | Script: `scripts/extract_unit_data.exs` — parses XML with `SweetXml`, extracts unit conversions, preferences, quantities, and categories |
| `weeks.etf` | `../cldr/priv/cldr/weeks.json` | Extracted from `Cldr.Config.weeks()` |

### `priv/cldr/validity/`

| File | Source | Method |
|------|--------|--------|
| `validity_languages.etf` | `../cldr/priv/cldr/validity/languages.json` | Extracted from `Cldr.Config.validity(:languages)` |
| `validity_scripts.etf` | `../cldr/priv/cldr/validity/scripts.json` | Extracted from `Cldr.Config.validity(:scripts)` |
| `validity_subdivisions.etf` | `../cldr/priv/cldr/validity/subdivisions.json` | Extracted from `Cldr.Config.validity(:subdivisions)` |
| `validity_t.etf` | BCP 47 T extension data from `ex_cldr` | Extracted from `Cldr.Config.validity(:t)` — no direct JSON equivalent |
| `validity_territories.etf` | `../cldr/priv/cldr/validity/territories.json` | Extracted from `Cldr.Config.validity(:territories)` |
| `validity_u.etf` | BCP 47 U extension data from `ex_cldr` | Extracted from `Cldr.Config.validity(:u)` — no direct JSON equivalent |
| `validity_units.etf` | `../cldr/priv/cldr/validity/units.json` | Extracted from `Cldr.Config.validity(:units)` |
| `validity_variants.etf` | `../cldr/priv/cldr/validity/variants.json` | Extracted from `Cldr.Config.validity(:variants)` |

## Conversion scripts

### `scripts/convert_currency_data.exs`

Converts currency JSON data to ETF. Produces two files:

* `currency_codes.etf` — sorted list of ISO 4217 currency code
  atoms from `currencies.json`.

* `territory_currencies.etf` — map of territory atoms to
  currency keyword lists with parsed `Date` values for `:from`
  and `:to` fields.

Run with:

```bash
mix run scripts/convert_currency_data.exs
```

### `scripts/extract_unit_data.exs`

Extracts unit conversion factors, preferences, quantities, and
categories from CLDR XML source files. Requires the `sweet_xml`
dependency (dev only) and a checkout of the CLDR repository.

Run with:

```bash
mix run scripts/extract_unit_data.exs [path_to_cldr_repo]
```

### Ad-hoc territory data scripts

The following files were generated by ad-hoc `mix run` scripts
during development. The pattern for each is the same — read
JSON from `../cldr/priv/cldr/`, atomise keys, and write ETF:

* `territories.etf` — includes date parsing for currency
  history entries.

* `territory_codes.etf` — simple key atomisation.

* `territory_containers.etf` — atomise territory codes in
  parent-child maps.

* `territory_containment.etf` — atomise territory codes in
  containment chains.

* `territory_subdivision_containment.etf` — atomise subdivision
  codes.

* `territory_subdivisions.etf` — atomise territory and
  subdivision codes.

These should be consolidated into a reusable script (tracked
in `TODO.md`).

## Per-locale data

Per-locale data (territory display names, subdivision names,
number formats, calendar data, currency data, date/time
formats, etc.) is **not** stored as ETF files. It is loaded
at runtime from JSON files in the `ex_cldr` dependency via
`Cldr.Locale.Loader.get_locale/2` and cached in
`:persistent_term` by `Localize.Locale.Provider.PersistentTerm`.

## Updating data

When the Unicode CLDR data is updated:

1. Update the `../cldr` repository (which tracks `ex_cldr`'s
   processed JSON output).

2. Re-run the conversion scripts in `scripts/`.

3. For files extracted from `Cldr.Config`, re-extract them
   using the same `Cldr.Config` calls in an `iex` session
   with the updated `ex_cldr` dependency.

4. Run `mix test` to verify the updated data produces correct
   results.
