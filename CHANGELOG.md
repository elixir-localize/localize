# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] — August 16th, 2026

### Changed

* **Breaking.** `Localize.Number.Parser.scan/2` now treats a space as a grouping separator in locales that group with one, so runs of digits that it previously returned separately can come back as a single number. Under `fr`, `"chambres 12 14 16"` was `["chambres ", 12, " ", 14, " ", 16]` and is now `["chambres ", 121416]`; pass `lenient: false` to require exact grouping sizes and get the old result. This is what lets `"1 234,5"` be found as one number, which is the point of the change.

* **Breaking.** `Localize.Number.parse/2` and `scan/2` validate that grouping separators sit in plausible positions, matching ICU, so input that was previously accepted can now fail. Under `fr`, `parse("3 4")` was `{:ok, 34}` and is now an error, because a single digit is not a group in any locale.

* `Localize.Number.parse/2` and `Localize.Number.Parser.scan/2` take a `:lenient` option governing that validation. `true`, the default, requires each group to be at least two digits, which is ICU's lenient rule; `false` requires exactly the locale's grouping size — three for most locales, and the 3-then-2 of `en-IN`.

### Fixed

* Timezone display names use the exemplar city CLDR ships rather than one derived from the IANA identifier. The lookup matched `%{city: _}` where the zone data keys `:exemplar_city`, so it never fired: 48 zones in `en` and 190 in `ja` were named from the identifier instead, losing renames (`America/Godthab` is `"Nuuk"`), accents (`"Córdoba"`), and in non-Latin locales the script entirely.

* Timezone display names resolve three-part identifiers such as `America/Indiana/Knox`, whose leaf CLDR keys by string one level deeper. They were split into two parts, so the lookup sought a city named `"Indiana/Knox"` and fell back to `"Knox"` rather than CLDR's `"Knox, Indiana"`.

* `Localize.Number.Parser.scan/2` finds a grouped number written with an ordinary keyboard space in a locale that formats with U+202F. Under `fr`, `scan("1 234,5")` was `[1, " ", 234.5]` and is now `[1234.5]`.

* `Localize.Number.parse/2` treats every character in `[:Zs:]` as a grouping space, per TR35's loose matching for lenient parsing. It previously accepted only U+0020 and the locale's own separator, so a `fr` number carrying U+00A0 or U+2009 — as copied out of formatted output — failed to parse.

* `Localize.Number.parse/2` ignores every character in `[:Cf:]`, per the same passage's instruction to ignore format characters, "in particular ... any RLM, LRM or ALM used to control BIDI formatting". CLDR writes the minus sign of `ar`, `he`, `fa` and 16 other locales as a BIDI mark followed by the sign, so a negative number copied out of that text previously failed to parse.

* `Localize.Number.parse/2` applies CLDR's `parseLenients` character folds, which were generated into the locale data but never read. The minus, plus, comma and full-stop families now fold to their canonical form, so the 18 locales writing `minusSign` as U+2212 — `fa`, `fi`, `sv` and `no` among them — parse their own negative numbers back. Per TR35 the fold applies to the locale's own separators as well as the input, which is what lets `de-CH` accept both spellings of its apostrophe group separator.

### Added

* `Localize.DateTime.Timezone.exemplar_city/3` returns the localized exemplar city for an IANA timezone identifier. `derive: false` returns an error rather than deriving a name from the identifier, distinguishing a name CLDR vouches for from one this library invented.

## [1.1.1] — August 16th, 2026

### Fixed

* `Localize.Unit.to_string/2` selects the plural category from the rendered digits rather than the input value, as TR35 defines the plural operands over the source number — "the visual appearance of the digits of the result". The float `1.0` renders as `1` and is now `"1 hectare"` rather than `"1 hectares"`, and conversely `1` with `fractional_digits: 2` renders as `1.00` and is now `"1.00 hectares"` rather than `"1.00 hectare"`.

* `Localize.Unit.localize/2` now resolves preferred units whose name is more than one word. It converted the atoms from `Localize.Unit.Preference.preferred_units/2` with `Atom.to_string/1`, yielding `"cubic_inch"` where the parser wants `"cubic-inch"`, so 35 of CLDR's 90 preferred units failed with a `Localize.ParseError` — taking the default usage of speed, volume, area, energy and pressure with them.

### Changed

* The package now declares `Unicode-3.0` alongside `Apache-2.0`, and `LICENSE.md` gains a "Unicode Data" section setting out which CLDR and UCD data is embedded, what it becomes, and reproducing the Unicode copyright and permission notice as that license requires. Modules emitted by `mix localize.unit.gen_conversions` carry the same dual-license SPDX header, so a consumer running `reuse lint` over the generated file no longer needs a `.license` sidecar.

## [1.1.0] — August 11th, 2026

### Fixed

* The `t:Localize.Currency.t/0` type now declares `:iso_digits` as `non_neg_integer() | nil`. Historic currencies (for example `:BGN`) have no ISO 4217 minor-unit definition and carry `nil`, which the module's own `is_nil/1` guards already handle; the previous `non_neg_integer()` type caused false `pattern_match` warnings in downstream code that guards against `nil`.

### Added

* `mix localize.unit.gen_conversions` generates a dependency-free unit conversion module from CLDR data, for embedded targets where compiling Localize costs more than the project itself. There is no unit selection to make: Localize's own parser is inlined into the generated module, so it accepts every identifier `Localize.Unit` accepts — prefixed, powered and `-per-` compound alike — through `to_base/2`, `resolve/1` and a compile-time `~u` sigil.

## [1.0.1] — August 2nd, 2026

### Fixed

* `Localize.LanguageTag.best_match/3` now prefers a territory's own language when candidates are otherwise equidistant, so `sgs` (Samogitian, spoken in Lithuania) matches `lt` rather than `en-LT`. The distance trie scores every candidate sharing the desired script and territory identically, which previously left the winner to depend on the order of the supported list.

* `Localize.ParseError` reports an over-cap input as `reason: :input_too_large` with the byte counts in new `:size` and `:limit` fields, instead of interpolating them into a prose `:reason` string that its own type never allowed. The message, number and unit-identifier parsers all use it, and the oversized input is no longer retained on the exception.

## [1.0.0] — July 31st, 2026

The first stable release. MF2 message validation is separated from parsing: `Localize.Message.Parser.parse/1` checks syntax, `Localize.Message.Validator.validate/1` checks the TR35 data-model rules, and everything that formats or serializes a message runs both. A message like `.local $count = {$count :number}` — a declaration that reads the variable it declares, which is a Duplicate Declaration error rather than a valid annotation of an external variable — is now rejected wherever it appears rather than only when formatted. The construct for annotating an external variable is `.input {$count :number}`.

### Added

* An [ecosystem guide](https://hexdocs.pm/localize/ecosystem.html) sets out the library's shape: a set of structured, locale-aware types, and the four operations — formatting, parsing, ordering and serialization — that apply both to them and to most of Elixir's own types. It tabulates which library provides each operation for each type.

* `Localize.Message.Validator.validate/1` is public, checking a parsed message against the TR35 data-model rules. `Localize.Message.Parser.parse/1` remains syntax-only, so tooling that must accept invalid input — `to_tokens/2` and the highlighters built on it — parses without validating, while everything that formats or serializes composes the two and reports syntax errors before data-model ones.

### Fixed

* **Duplicate Declaration** is now caught wherever a message is used, not only when it is formatted. `.local $count = {$count :number}` reads the variable it declares, so it was rejected by `format/3` but serialized happily by `canonical_message/2` and accepted at compile time as a Gettext msgid. Use `.input {$count :number}` to annotate an external variable.

* Three further TR35 data-model rules are now enforced: **Missing Selector Annotation** (a selector that does not resolve, directly or through a chain of locals, to a declaration carrying a function), **Variant Key Mismatch** (a variant whose key count differs from the selector count), and **Missing Fallback Variant** (no variant with only `*` keys). None was detected previously — the first two were documented as enforced during match evaluation and were not, and all three could be formatted or serialized without error.

* `Localize.Message.canonical_message/2` no longer serializes a message that violates the data-model rules; it previously round-tripped every invalid form, including a `.local` declaration reading the variable it declares. The compile-time Gettext interpolator validates too, so a mis-authored msgid fails the build rather than surfacing at runtime.

* The MF2 working-group `data-model-errors.json` conformance cases now assert the specific error reason rather than merely that some error occurred. The WG cases pass no bindings, so an incidental unbound-variable error satisfied the old assertion — which is how three unimplemented rules stayed green.

* `Localize.validate_territory/1` now accepts integer M49 codes as its typespec and documentation always promised — `validate_territory(1)` returns `{:ok, :"001"}`. An integer previously raised `FunctionClauseError` because the validator's guard omitted `is_integer/1`, even though its normalization already zero-padded integers. Numeric codes may also be given as strings (`"001"`); note that country-level M49 numbers such as `840` are not in CLDR's territory validity set, which uses the alpha-2 code (`"US"`) there.

## [1.0.0-rc.7] — July 28th, 2026

This release settles the `:format` / `:style` option naming across the library. The rule is now uniform: `:format` is how a **value** is rendered, `:style` is which variant of a **name or pattern** you get, and an option that selects something else again — `Localize.Interval`'s choice of which date fields appear — is named for what it selects. Every rename below is a hard break with no alias; each entry names its replacement.

### Changed

* **Breaking:** `Localize.Duration.to_string/2` and `to_parts/2` rename the per-unit width override from `:styles` to `:formats`, so the whole-duration width and its per-unit overrides share one name (`format: :short, formats: [hour: :long]`). The `:styles` key, introduced in 1.0.0-rc.2 and never in a stable release, is now ignored like any other unknown option.

* **Breaking:** `Localize.Calendar.localize/3` returns `{:ok, name}` or `{:error, exception}` instead of a bare string, `nil`, or an error tuple, and gains `localize!/3` for the bare name — the old union meant a template interpolating the result raised `Protocol.UndefinedError` when the locale was invalid. It now derives the part's value and delegates to `display_name/3`, so the two agree: its width option is `:style` (was `:format`), its default width is `:wide` (was `:abbreviated`), and an unknown part returns an error rather than raising `FunctionClauseError`.

* **Breaking:** The calendar part and type names are unified on `:day_of_week` and `:day_period`: `Localize.Calendar.display_name/3` takes `:day_of_week` (was `:day`) and `localize/3` takes `:day_period` (was `:am_pm`). An unknown part or type now returns an error listing the valid names rather than raising `FunctionClauseError`.

* **Breaking:** The day-period variant selector is `day_period: :variant` on `Localize.Calendar.display_name/3` and `localize/3`, and on the date/time formatters that pass it through (`Localize.Time.to_string(~T[15:00:00], format: "h a", day_period: :variant)` renders "3 pm"). The `:am_pm` and `:period` aliases are removed, so every variant option is now named for the part it applies to, as `:era` already was.

* **Breaking:** `Localize.Interval.to_string/3` renames its `:style` option to `:fields`, because it selects *which* date fields appear (`:date`, `:month`, `:month_and_day`, `:year_and_month`) rather than a width — `:format` remains the width axis, and the two are now named for what they do. `Localize.Interval.date_styles/0` becomes `known_fields/0`, and `Localize.DateTimeIntervalFormatError` carries `:fields` with reason `:unknown_fields` in place of `:style` / `:unknown_style`.

### Documentation

* `Localize.DateTime.to_string/2` documents its `:style`, `:date_format`, and `:time_format` options, which were live but absent from the docs. `:style` selects the date/time wrapper (`:at` renders "April 8, 2026 at 12:00:00 PM", and falls back to the standard wrapper for `:medium` and `:short`, which CLDR does not define it for).

### Fixed

* `Localize.Calendar.display_name/3` reports an unusable `:style` as a `:style` error listing the widths the field actually has, instead of blaming the value: `display_name(:month, 3, style: :bogus)` said `value: 3, expected: "1..13"`. `style: :short` now resolves wherever CLDR carries it (the day parts) rather than silently returning `nil`.

* `Localize.Unit.to_string/2` no longer lets a stray `:style` option reach the SI-prefix and custom-unit paths, where it produced "5 MegaJoule" for `style: :short` instead of the correct "5 Megajoule". The option has been ignored since 1.0.0-rc.0 and is now ignored everywhere, as documented.

* `Localize.Duration.to_string/2` and `to_parts/2` join duration parts with CLDR's unit list patterns matched to the format width, per ECMA-402 `Intl.DurationFormat`, instead of the standard "and" conjunction: `:en` now renders "3 days, 2 hr" (was "3 days and 2 hr") and "3d 2h" for `format: :narrow`.

* Per-compound units whose denominator carries a constant keep that count in every width: `curr-usd-per-30-day` renders "$10.00/30 days" for `format: :short`, where the denominator's precomposed `per_unit_pattern` ("{0}/d") previously swallowed the count and gave "$10.00/d". Counted denominators now compose through the locale's `compound.per` pattern, which also stops a numerator whose symbol contains the denominator noun being corrupted (narrow `candela-per-30-day` gave "10c30 d/30 d", now "10cd/30 d").

## [1.0.0-rc.6] — July 27th, 2026

### Fixed

* A cached locale left over from an earlier release is now reported as stale rather than missing: `Localize.LocaleIsStaleError` names both data versions and how to refresh, where the previous `Localize.LocaleNotFoundInCacheError` sent the reader looking for a file that was present all along. A genuinely absent locale still reports as not found.

### Changed

* Metazone data is updated to tzdata 2026c: `Africa/Casablanca` and `Africa/El_Aaiun` resume Western European Time from 2026-09-20, so time zone names for those zones are correct on and after that date.

## [1.0.0-rc.5] — July 27th, 2026

### Fixed

* All sixteen CLDR unit grammar cases are now normalized into the locale data (previously only seven were), so `Localize.Unit.to_string/2` with `grammatical_case:` values like `:prepositional` (ru), `:partitive` (fi), or `:terminative` (hu) formats correctly instead of silently falling back to nominative. The locale data version is bumped to 48.2:2 and all locale data is regenerated.

* Compound unit grammatical-case and gender patterns are now merged deterministically during locale data generation; the previous shallow merge silently dropped case entries, with the surviving subset depending on OTP map iteration order.

* The BCP 47 validity data generator no longer crashes on deprecated timezone codes (those with a preferred replacement, such as `camtr` → `cator`); the generated validity data is unchanged, but it can once again be regenerated from source.

* `Localize.Unit.parse/2` resolves unit symbols that map to compound identifiers — `"1 m/s"` → `meter-per-second`, `"3 kWh"` → `kilowatt-hour` — instead of failing on the internal underscore key form. Closes #42.

* Times-compound units with no precomposed CLDR pattern (`tonne-kilometer`) now format as their localized name (`"5 metric ton-kilometers"`, `"5 t⋅km"`, `"5 tonnes-kilomètres"`) instead of the raw identifier, composed per the CLDR grammatical derivation loaded from `grammaticalFeatures.xml`. Closes #43.

* Per-compound units whose denominator has no per-unit pattern now localize through the locale's `compound.per` pattern (Polish `"5 jardów na milimetr"`) instead of falling back to an English `"per"`.

* `Localize.Unit.define_unit/2` accepts a derived unit as `base_unit` (e.g. `"day"`) and folds it to its fundamental base at registration, so the custom unit is convertible and `compatible?/2` returns `true`. Closes #44.

* Person-duration units (`year-person`, `month-person`, `week-person`, `day-person`) format as their base unit (`"5 years"`), matching ICU, instead of the raw identifier.

* SI-prefixed units with no precomposed CLDR pattern (`megajoule`, `gigajoule`, `nanogram`) now compose their display from the prefix and base unit (`"5 MJ"`, `"5 megajoules"`, with CLDR `combineLowercasing` for capitalising locales) instead of the raw identifier. Closes #46.

### Changed

* Generated locale ETF files and the download-integrity hash manifest are now serialized with the `term_to_binary` `:deterministic` option, making the bytes reproducible across operating systems, architectures, and OTP versions. This lets the manifest generated during development match the data generated in CI and served from the CDN, so runtime download verification succeeds regardless of where each was produced. All bundled supplemental, validity, and collation ETF data is regenerated with the same option.

* Compiling a number format pattern is ~40% faster on a cache miss: the regexes used to analyse the pattern are compiled once at startup rather than recompiled on every call. Formatting is unaffected (compiled patterns are already cached).


## [1.0.0-rc.4] — July 24th, 2026

### Added

* `Localize.Unit.parse/2` and `parse_unit_name/2` (with bang variants) parse strings like "1kg", "2,5 kg" or a localized "2 Tage" into units, matching locale unit names, canonical identifiers and custom units, with `:only`/`:except` filters disambiguating names like "2w" (watt versus week) — the migration path from `Cldr.Unit.parse/2`.

### Fixed

* Custom units with hyphenated names ("double-cubit") resolve everywhere a unit identifier is accepted: registered names match wholesale in the unit parser instead of being split at hyphens by the compound grammar.

## [1.0.0-rc.3] — July 23rd, 2026

### Added

* `Localize.Interval.to_parts/3` and `to_parts!/3` decompose date, time, and datetime intervals into typed parts with ECMA-402 `:source` tagging, across split patterns, fallback patterns, and equal-endpoint collapse. Open intervals (a `nil` endpoint) are not supported in parts form.

* `Localize.Unit.to_range_parts/3` and `to_range_parts!/3` decompose a unit range: the numeric range parts keep their sources and the unit pattern text carries source `:shared`.

* `Localize.Duration.to_parts/2` and `to_parts!/2` decompose a duration into per-field unit parts (numeric segments carry a `:unit` key) joined by `:literal` list separators.

* Date, time, and datetime formatting accept a `:number_system` option: any CLDR numbering system renders all numeric fields ("Mar ๑๕, ๒๐๒๕" with `:thai`), equivalent to a `-u-nu-` locale extension.

## [1.0.0-rc.2] — July 23rd, 2026

### Added

* Date/time skeletons accept fractional seconds (`S`–`SSS`): per TR35 the field is stripped for matching and appended to the resolved pattern's seconds field ("9:30:12.34 AM" for `:hmsSS` in en).

* `Localize.Date.to_parts/2`, `Localize.Time.to_parts/2` and `Localize.DateTime.to_parts/2` (plus bang variants) decompose dates and times into typed field parts per ECMA-402 `formatToParts`, across standard formats, skeletons, pattern strings and combined date+time wrappers.

* `Localize.Number.to_range_parts/3` and `to_range_parts!/3` return typed range parts with ECMA-402 `:source` tagging (`:start_range`, `:end_range`, `:shared`) and `:approximately_sign` handling.

* `Localize.Number.to_parts/2` decomposes the `:currency_long` and `:currency_long_with_symbol` formats; the pluralized currency name is a `:currency` part.

* `Localize.Unit.to_parts/2` and `to_parts!/2` decompose a unit into its number parts plus `:unit` and `:literal` segments per ECMA-402.

* `Localize.Unit.to_range_string/3` and `to_range_string!/3` format two like units as a range ("2–5 kilometers", fr "0–1 jour"), selecting the pattern's plural category from the TR35 plural-range rules.

* `Localize.Number.PluralRule.Range` selects the TR35 plural category for numeric ranges (`plural_rule/3` for categories, `plural_rule_for/3` for numbers).

* `Localize.List.to_parts/2` and `to_parts!/2` return `:element` and `:literal` parts for list formatting per ECMA-402 `Intl.ListFormat` `formatToParts`.

* `Localize.DateTime.Relative.to_parts/2` and `to_parts!/2` return relative-time parts; the number part carries a `:unit` key matching the JS part shape.

* `Localize.Duration.to_string/2` accepts per-unit `:display` (`:auto` / `:always`) and `:styles` (`:long` / `:short` / `:narrow`) overrides, mirroring ECMA-402 `DurationFormat` per-unit options.

### Fixed

* `:rounding_priority` `:auto` (and the unset default) ignores fraction-digit bounds entirely when a significant-digit bound is present, per ECMA-402; previously a binding fraction bound still truncated the significant-digit result.

* The separator between adjacent seconds and fractional-second pattern fields is the locale's decimal separator per TR35 (de renders "09:30:12,34"); previously a period was hardcoded.

## [1.0.0-rc.1] — July 23rd, 2026

### Added

* `Localize.Number.to_parts/2` and `to_parts!/2` format a number into typed segments per ECMA-402 `formatToParts`, covering decimal, currency, percent, scientific, compact and algorithmic-system output.

* `Localize.Number.to_string/2` accepts `:minimum_integer_digits` (zero-pad the integer part, ECMA-402 `minimumIntegerDigits`), `:trailing_zero_display` (`:strip_if_integer` per `trailingZeroDisplay`), and `:rounding_priority` (`:more_precision` / `:less_precision` per `roundingPriority`).

* `Localize.DateTime.Relative.to_string/2` accepts `numeric: :always` to force numeric output ("1 day ago" instead of "yesterday"), per ECMA-402 `RelativeTimeFormat`.

* `Localize.Collation.known_collations/0` and `Localize.DateTime.Timezone.known_timezones/0` (re-exported on `Localize`) return the CLDR collation and canonical IANA time zone inventories for `Intl.supportedValuesOf/1`.

* The MF2 numeric functions accept the TR35 `minimumIntegerDigits`, `minimumSignificantDigits`, `maximumSignificantDigits`, `trailingZeroDisplay` and `roundingPriority` options, mapped onto the corresponding `Localize.Number.to_string/2` options.

### Changed

* The `:currency_long` formats apply the currency's fraction digits and select the plural name from the displayed value per ECMA-402 `currencyDisplay: "name"`: `to_string(1, format: :currency_long, currency: :USD)` renders "1.00 US dollars" (previously "1 US dollar").

* Relative time offsets of zero format with the future pattern ("in 0 days") per ECMA-402 and ICU.

## [1.0.0-rc.0] — July 22nd, 2026

### Added

* `Localize.Number.to_string/2` accepts a `:sign_display` option (`:auto`, `:always`, `:except_zero`, `:negative`, `:never`) mirroring ECMA-402's `signDisplay` across decimal, currency, percent, scientific and compact formats.

### Changed

* `Number.System.system_name_from/2` resolves any CLDR numbering system for any locale instead of returning a `:not_for_locale` error, and `Format.formats_for/2` and `Symbol.number_symbols_for/2` inherit missing data from the locale's default system per CLDR root aliasing.

### Fixed

* The implicit negative subpattern is now the minus sign prefixed to the whole positive pattern per TR35, so `Localize.Number.to_string(-1, currency: :USD)` renders "-$1.00" (previously "$-1.00") matching ICU and `Intl.NumberFormat`.

* `Localize.Number.to_string/2` honours any CLDR numbering system via `-u-nu-` or `:number_system`, per TR35/ICU: `en-u-nu-thai` renders Thai digits instead of an `UnknownRbnfRuleError`, and algorithmic systems (`zh` with `:hans`, `en-u-nu-roman`) format via their RBNF rules.

* The MF2 numeric functions honour an algorithmic `numberingSystem` (`hans`, `roman`, …) via the system's RBNF rules, matching `Localize.Number.to_string/2` and ICU.

* `Localize.Unit.to_string/2` with `backend: :nif` honours the `:format` option: the NIF call now receives the requested width, so `format: :short` renders "100 m" on both backends instead of falling back to the long form.

* `Localize.Duration.to_time_string/2` honours TR35 single-quote literals in patterns, so `format: "h'h' m'm'"` renders "37h 48m" instead of substituting the quoted letters as field symbols.

### Removed

* The deprecated locale-scoped delegates are removed: `Language.available_languages/1` and `known_languages/1` (use `languages_for/1` / `language_names_for/1`), `Script.available_scripts/1` and `known_scripts/1` (use `scripts_for/1` / `script_names_for/1`), `Subdivision.available_subdivisions/1` and `known_subdivisions/1` (use `subdivisions_for/1` / `subdivision_names_for/1`), and `Territory.available_styles/0` (use `known_styles/0`).

* The Currency positional filter forms are removed: `currencies_for_locale/3`, `currencies_for_locale!/3`, `currency_strings/3` and `currency_strings!/3`, along with the positional second argument of the arity-2 forms. Pass the `:only` and `:except` options instead; a positional filter now raises `ArgumentError` so it cannot be silently misread as empty options.

* The deprecated option aliases are removed: `Localize.Duration.to_string/2` `:style` (use `:format`), `Localize.Unit.to_string/2` `:style` (use `:format`), `Localize.quote/2` `:style` (use `:format`), and `Localize.Unit.display_name/2` `:format` (use `:style`). The former alias keys are now ignored like any other unknown option.

## [0.50.0] — July 15th, 2026

### Added

* `Localize.LanguageTag.remove_likely_subtags/2` and `!/2` accept `favor: :script | :region` to select the TR35 removal variant (`zh-Hant-TW` minimizes to "zh-Hant" or "zh-TW"), verified against the full CLDR likely-subtags test data.

* The MessageFormat working group's `:test:function`, `:test:format` and `:test:select` registry functions are implemented, so the WG conformance suite's selection-mechanics and fallback cases now run.

* The MF2 numeric functions accept the `signDisplay` option (`auto`, `always`, `exceptZero`, `negative`, `never`), with the plus sign taken from the locale's number symbols.

* An MF2 pattern expression that re-annotates a declared variable operates on the declaration's original value, and numeric functions inherit unset options from a numeric declaration — `.local $x = {41 :integer signDisplay=always}` rendered with `{$x :offset add=1}` produces "+42".

* The locale download base URL can be overridden with `config :localize, locale_base_url: "..."` for deployments mirroring the locale files; downloads are verified against the bundled hash manifest regardless of source.

### Changed

* An unannotated MF2 placeholder with a numeric operand formats with the locale-aware `:number` default (`{$pi}` renders "3.142" in en and "3,142" in fr), matching the MF2 implicit formatting rules; previously the value was stringified verbatim.

* MessageFormat 2 follows the specification's error semantics: unknown functions are an error (`Localize.FormatError` reason `:unknown_function`) instead of formatting the operand, and data-model validation rejects duplicate declarations, duplicate option names, and duplicate variants (NFC-normalized keys) with dedicated error reasons.

* MessageFormat 2 function validation is strict per TR35: the `select` option must be a literal set directly on the selector expression, digit-size options must be non-negative integers, string operands of numeric functions must match the `number-literal` production, and `:currency`, `:unit`, `:date`, `:time` and `:datetime` are rejected as selectors.

* `Localize.Number.Format.Options` is documented again: `validate_options/2` is the supported way to pre-resolve formatting options for hot loops (as the Performance guide describes), so the module is part of the public API.

* The TR35 conformance guide documents the MessageFormat 2 working-group suite exclusions precisely: unknown-function fallback, duplicate declaration/option validation, select and digit-size option validation, `u:dir`/`u:id` expression options, and the `:isolate` bidi strategy deviation.

### Deprecated

* `Localize.Currency.currencies_for_locale/2,3`, `currencies_for_locale!/2,3`, `currency_strings/2,3` and `currency_strings!/2,3` take the include/exclude filters as `:only` and `:except` options instead of positional arguments. The positional forms still work but are deprecated and will be removed by Localize 1.0 and no later than December 2026.

### Fixed

* Calendar- and provider-module probes in date/datetime formatting (era year, day of era, ISO week and day of year, day of week, CLDR calendar type) and `Localize.Locale.Provider.allow_download?/1` ensure the module is loaded before `function_exported?/3`, so a cold module no longer silently takes the gregorian or default fallback branch.

### Security

* `Localize.Locale.Provider.locale_file_name/1` rejects locale identifiers that do not have the shape of a CLDR locale id, as defense in depth for the cache-path and download-URL interpolations.

## [0.49.0] — July 12th, 2026

### Fixed

* Change the namespaces on the `leex` lexers and `yecc` parsers to avoid module name clash with `ex_cldr` versions. Thanks to @jerryluk for the PR. Closes #40.

* The coverage ignore list follows the renamed lexer/parser modules, restoring measured coverage above the 90% CI threshold; a guard test now fails when an ignore-list entry names a module that no longer exists.

## [0.48.0] — July 8th, 2026

### Added

* `Localize.Unit.to_string/2` accepts `humanize: true` to render any unit in the unit people expect for its magnitude: bit-, byte-, hertz- and watt-based units scale through the `humanize/2` prefix ladder (honouring `system: :si | :iec`) and all other units render through usage-based preferences. An explicit `:usage` option keeps precedence for preference-scaled units.

* `Localize.Unit.humanize/2` and `humanize!/2` also scale hertz- and watt-based units through the SI prefix ladder ("2.5 gigahertz", "3.2 gigawatts") — like bits and bytes, these are locale-invariant quantities that CLDR's unit preferences do not cover. IEC prefixes remain restricted to bit- and byte-based units.

## [0.47.0] — July 7th, 2026

### Added

* `Localize.Unit.humanize/2` and `humanize!/2` convert a byte- or bit-based unit to the prefix that best fits its magnitude, so `1_500_000 byte` formats as "1.5MB" with `format: :narrow`. The `:system` option selects `:si` (powers of 1000, default) or `:iec` (powers of 1024) prefixes.

* `Localize.Number.to_string/2` accepts `format: :short` and `format: :long` as ex_cldr-compatible aliases, resolving to `:decimal_short` / `:decimal_long`, or to `:currency_short` / `:currency_long` when a `:currency` is specified.

* `mix localize.update_cldr` orchestrates the CLDR data-update pipeline (copy sources → generate supplemental → compile gate → generate locales → test gate), with `--check` preflight, `--locales` subsetting, and each step isolated in a fresh VM. The full update process is documented in the consolidated CLDR Update Guide (`CLDR_UPDATE_INTEGRATION.md`).

* A Claude Code skill covering all major subsystems (numbers, dates/times, units, lists, collation, MessageFormat 2, locale validation and configuration), installable via `/plugin marketplace add elixir-localize/localize`. All 300+ skill examples are execution-verified against the library.

### Fixed

* Timezone formatting consults zone-level names before metazone names per TR35, so a UTC `DateTime` renders "UTC" / "Coordinated Universal Time" instead of "GMT" / "Greenwich Mean Time", and Europe/London in summer renders "British Summer Time" instead of "GMT+01:00". Thanks to @gmile for the PR. Closes #37.

* Date and time formatting applies the locale's default numbering system to all numeric fields, so `locale: :mr` renders "१५ मार्च, २०२१" (likewise bn, fa, my and others) matching ICU. Pattern-level `numbers=` and caller `:number_system_overrides` keep precedence. Thanks to @gmile for the PR.

* A `-u-nu-` locale extension overrides the default numbering system in date and time formatting per TR35: `"mr-u-nu-latn"` renders latn digits and `"en-u-nu-deva"` renders deva digits, including when the locale is set with `Localize.put_locale/1`.

* Territory-specific collation tailorings apply from locale data: sorting with `locale: "fr-CA"` now uses French Canadian backwards accent comparison. Previously the lookup used only the bare language, silently dropping fr-CA's `[backwards 2]` override.

* `Localize.Calendar.first_day_for_locale/1` honours the `-u-fw-` extension per TR35: `"en-u-fw-mon"` returns 1 (Monday) instead of the territory default.

## [0.46.0] — July 6th, 2026

### Changed

* Full compile time drops from ~66s to ~3.5s: the RBNF lexer grammar no longer explodes the generated DFA (its generated Erlang shrinks from 891KB to 41KB), and the language/subdivision validity checks compile to a single map lookup instead of thousands of guard clauses. Token streams and validation results are unchanged.

* The collation tailoring table loads at runtime on first use instead of being embedded at compile time, shrinking the library's largest beam from 1.7MB to 44KB.

* Every module that embeds ETF data at compile time now declares the file with `@external_resource`, so a CLDR data regeneration correctly recompiles the timezone, time-preference, validity and script-mapping modules.

## [0.45.0] — July 5th, 2026

A quality release: the codebase now passes `mix credo --strict` with zero findings (enforced in CI), the full MessageFormat 2 working-group conformance suite runs against the formatter, and the documentation gains four new guides. A test-coverage push from 70% toward 90% surfaced — and this release fixes — more than twenty conformance and correctness bugs across date/time, number, unit, collation and language-tag handling.

**Upgrading from 0.42 or earlier?** Version 0.43.0 renamed the inventory functions from the `available_*`/`known_*` names to the uniform `known_*`/`supported_*`/`*_for` scheme and swapped two `:format`/`:style` option names. Every old name still works as a deprecated delegate until Localize 1.0 — see the 0.43.0 entry below for the full list.

### Added

* The complete MessageFormat 2 working-group conformance suite (16 test files including all nine `functions/` suites) now runs against the formatter: 250 cases asserting formatted output and expected errors, with unimplemented features excluded and documented per case.

* Four new guides: plural rules, list formatting, locale validation and matching, and display names. Every example is execution-verified.

* `Localize.Territory.territory_names_for/1` and `territories_for/1` return the localized territory-name inventory for a locale, completing the `*_for` family across languages, scripts, subdivisions and territories.

* CLDR metazone data joins the supplemental-data pipeline: `Localize.DateTime.Timezone.metazone_for/2` returns the metazone for an IANA zone at a given instant, and `zone_for_metazone/2` returns a metazone's representative zone per territory. The `z`/`v` format symbols now draw on the full 191-metazone CLDR mapping instead of a 20-zone builtin table.

* A documentation depth pass adds around 150 execution-verified doctest examples and 40 `### Options` sections across the number, unit, date/time, locale, territory, list, collation and message modules, and corrects stale claims (RBNF number-system conversion, locale defaults, the `validate_locale/1` matching warning).

* A test-coverage push adds around 1,700 tests across exceptions, collation, date/time formatting, MessageFormat 2 tooling, language-tag validity, number/unit internals and the runtime plumbing, raising runtime-library line coverage from 70% to 91%. The 90% threshold is now enforced in CI.

### Changed

* The MF2 `:offset` function follows the specification: it takes exactly one of the `add` or `subtract` options (non-negative integer) and adjusts the operand for both formatting and selection. The previous ICU-style `offset=` option, which only subtracted during selection, is replaced.

* The MF2 `numberingSystem` function option accepts any valid CLDR numbering system, matching Intl/ICU: `{$n :number numberingSystem=thai}` renders Thai digits in any locale. Unknown system names still return an error; the `:number_system` option of `Localize.Number.to_string/2` is unchanged.

* Credo (strict) added to the CI lint stage with a committed `.credo.exs`. Policy: the `Design.AliasUsage` check is disabled (Localize module names such as `List`, `Date` and `String` shadow the stdlib when aliased; aliasing is applied opportunistically where safe), nesting depth stays at the default maximum of 2, and complexity/apply/arity exceptions are documented inline at each site.

* Deeply nested functions across the library were refactored into multi-clause private helpers with pattern matching (~120 helpers). Behavior is unchanged; the full test suite, dialyzer and doc builds gate the refactor.

* Logger configuration for this project's dev/test environments now renders the `domain: :localize` metadata attached to Localize log messages.

### Fixed

* The `U` (cyclic year) and `r` (related Gregorian year) format symbols work: `U` renders the localized sexagesimal name (丙午, "bing-wu") from the calendar's cyclic name sets and `r` the Gregorian year in which the calendar year begins, both probing the date's calendar module per the Calendrical protocol. Previously both rendered the raw year number.

* Date/time skeleton matching compared candidate format fields against the wrong skeleton fields, making format selection nondeterministic across VM runs (`format: :yMdHm` could render "Jul" or "July" run to run). Selection is now deterministic, prefers the exact skeleton, and matches text-field widths by class (`E` ≡ `EEE`) per TR35.

* The "alt" language code (Southern Altai) was unreachable: the data pipeline stored it as the atom `:alt` (a collision with the alt-variant style key), so `Localize.Language.display_name("alt")` returned an error. Fixed at data load; the pipeline fix lands with the next CLDR data regeneration.

* `-t-` extension dates encode with zero padding (`ja-t-it-m0-ungegn-20070315` round-trips exactly); previously single-digit months and days encoded with an embedded space, producing an invalid tag.

* `Localize.validate_locale("en-u-vt-00a4")` no longer raises during canonical-id formatting, and `Localize.LanguageTag.parse("zh-min-nan")` no longer raises `ArgumentError` (the grammar dropped the extended-language tags for multi-subtag forms).

* CLDR `{1}…{0}…` substitution patterns with two literals placed the substituted items in the wrong order.

* Collation `reorder: [..., :others]` places unmentioned scripts at the `:others` position per TR35; previously they kept unremapped weights, producing orderings incomparable with the reordered scripts.

* The collation `max_variable` option takes effect in the Elixir backend: `:space` narrows and `:symbol`/`:currency` widen the shifted range per the UCA. Previously the setting was ignored and shifting was fixed at the punctuation boundary.

* Compound unit identifiers canonicalize in the TR35 unitQuantity order, so `"kilowatt-hour"` keeps its CLDR pattern and renders "2 kilowatt-hours" instead of "2 hour-kilowatt".

* `:currency_long_with_symbol` renders both the symbol-formatted number and the currency name ("$123.00 US dollars"); both long currency formats now derive the currency from the locale when no `:currency` option is given.

* `Localize.Interval.to_string/3` returns an error for mixed endpoint kinds (e.g. a `Date` and a `Time`) instead of rendering malformed output, and equal `Time` endpoints honour the `:time_format` option in the single-time fallback.

* The `Q` and `q` date-format symbols were swapped: `Q` now renders the format-context quarter and `q` the stand-alone quarter per TR35. Visible only in locales whose quarter names differ by context.

* Doubled apostrophes inside quoted date-format text render a literal apostrophe (`'o''clock'` → "o'clock"); previously the escape was dropped.

* Zone format symbols (`Z`, `O`, `v`, `V`, `x`, `X`) render empty for values without a time zone, matching `z`; previously they fabricated a UTC zone.

* `Localize.Duration.new/2` accepts `NaiveDateTime` pairs (previously raised) and rejects reversed `Time` pairs with an error instead of returning a negative duration.

* RBNF plural substitutions (`$(cardinal,…)$`) select the plural category on the quotient of the rule divisor per ICU: Russian 2,000,000 spells out as "два миллиона", not "два миллионов".

* Requesting a spellout ruleset a locale does not have returns `Localize.UnknownRbnfRuleError` — with its `available:` field now populated — instead of silently formatting digits.

* The `:spellout` format resolves to `spellout-numbering` (ICU's default ruleset) deterministically; previously the choice among a locale's gendered rulesets varied across OTP releases (German 1.5 could spell "eine", "ein" or "eins" depending on the VM).

* Numeric collation computes the value of non-ASCII digits from their Unicode block's zero digit: Arabic-Indic "٢" sorts before "١٠" and "٠" compares equal to "0"; previously digit values were computed modulo 10 of the codepoint, wrapping mid-block.

* `:fractional_digits` applies to numbers with a zero integer part: `Number.to_string(0.4, fractional_digits: 0)` returns "0" (previously "0.4"), with float and Decimal inputs rounding identically across all rounding modes.

* `Localize.Utils.Map.extract_strings/2` no longer drops strings that precede a nested list or map, and `underscore_keys(nil)` returns nil instead of raising.

* `Number.to_range_string/3` with `approximate: true` formats the full range ("~3–5"); previously the range end was silently dropped.

* `Number.PluralRule.plural_type/2` returns a bare category atom on both backends; the NIF backend previously returned an `{:ok, atom}` tuple.

* Converting a mixed unit to another mixed unit works (`foot-and-inch` → `yard-and-foot-and-inch`); previously it always returned a `:mixed_units` error.

* Unit plural categories for `Decimal` values honour the visible fraction (Decimal "1" renders "1 meter"), and denominator units keep their SI prefix and power ("per 100 kilometers", not "per 100 meter").

* `Localize.Utils.Math.power/2` with a fractional exponent between 0 and 1 returned the reciprocal (`power(4, 0.5)` gave 0.5); Decimal bases now always return Decimals.

* Locale downloads run in a dedicated `:localize` httpc profile with the proxy set per request, so a configured proxy no longer leaks into later requests or into the host application's default httpc profile.

* Display names of parsed (unvalidated) language tags with `-t-` extensions or multi-part `-u-` values no longer crash or mangle subtags, and multiple `-u-dx-` scripts render translated and list-separated.

* `Localize.Date.to_string/2` no longer overwrites a user-supplied `:number_system_overrides` option.

* Small fixes: `UnknownSubdivisionError` carries the original input instead of nil; `UnknownCurrencyError` for a binary code always carries the binary (previously the atom when it happened to exist); MF2 match results deduplicate their bound-variable lists; `Localize.Utils.Json.decode!/1` raises `ArgumentError` on trailing data instead of a bare `MatchError`.

* Language tags with duplicate singleton subtags (`en-u-ca-gregory-u-nu-thai`) are rejected with a parse error per RFC 5646; previously the second occurrence was silently dropped.

* Grandfathered language tags resolve to their preferred values from the CLDR alias data: `i-klingon` canonicalizes to `tlh` (displaying "Klingon"), `zh-min-nan` to `nan`, `en-GB-oed` to `en-GB-oxendict`, and the sign-language tags to their ISO codes. Previously irregular grandfathered tags parsed to an empty tag.

* The MF2 Elixir backend reports the same errors as the NIF backend: an unbound variable used as a function option value returns a bind error, and an invalid `:locale` option returns a locale error; both were previously silently ignored.

* Per-compound units without a direct CLDR pattern compose from the numerator and the per-pattern: `foot-per-second` renders "2 feet per second" instead of the raw identifier.

* MF2 `:percent` selection multiplies the operand by 100 before plural-category selection, matching the formatted value per the specification.

* An MF2 `.match` on an unbound variable returns an unresolved-variable error instead of silently selecting the fallback variant.

* A duplicated boolean assertion in the message custom-function tests masked half of an intended check; general mechanical cleanups (map_join, empty-enum checks, number underscores, redundant with clauses) applied throughout.

## [0.44.0] — July 4th, 2026

This release closes the TR35 conformance gaps in the date/time formatting layer and fixes locale-fidelity bugs surfaced by newly-wired conformance data.

### Added

* Flexible day periods: the `B` format symbol selects CLDR day periods ("in the morning", "mittags", "noon", "midnight") from the day-period rules now in the supplemental data pipeline, and `b` renders noon/midnight at the exact points. Languages without rules fall back to AM/PM.

* `Localize.LanguageTag.U.parse/1` and `parse!/1` parse a standalone BCP 47 `-u-` extension string (with or without the `u-` singleton) into a validated `Localize.LanguageTag.U` struct, using the same canonicalization as `Localize.validate_locale/1`. `Localize.LanguageTag.U.encode/1` is now a documented public function.

* Downloaded locale files are verified against a SHA-256 hash manifest bundled with the package (`priv/localize/locale_hashes.etf`, generated by `mix localize.generate_locale_hashes` at release time), before any decode or cache write. A mismatch or missing entry fails the download with `Localize.LocaleIntegrityError`; when no manifest is present a one-time warning is logged and verification is skipped.

* The rbnf conformance suite now runs the vendored ICU reference data for `de`, `es` and `fr` in addition to `en`, and the likely-subtags suite asserts the CLDR FAIL rows.

### Fixed

* `Localize.Validity.U.encode/2` emits the preferred BCP 47 spelling instead of a deprecated alias (`:islamic_civil` encodes as "islamic-civil", not "islamicc"), and `decode/2` accepts struct-field atom keys and the canonical hyphenated calendar spellings ("islamic-civil").

* Week fields honour the locale's week configuration: `w` and `Y` compute week-of-year from the locale's first day and minimum days (2023-01-01 is week 1 in en, week 52 of 2022 in de), and `W` computes week-of-month accordingly. Previously all three were ISO-only.

* Multi-replacement territory aliases follow TR35 Annex C: `hy-SU` canonicalizes to `hy-AM` via the likely territory, `uk-SU` to `uk-UA`, `sr-YU` to `sr-RS`; previously the first entry (RU) was always taken.

* RBNF decimal-format substitutions (`=#,##0=`) format with the rule's locale instead of the process locale, so fr digits-ordinal renders "1 141e" and de "1.141." rather than the English "1,141".

* Likely-subtags no longer fabricates mappings for languages without one: private-use languages (`qaa`) pass through unmaximized per the CLDR test data instead of inheriting the `und` mapping.

* Locales whose language has no CLDR match resolve to root (`und`) data instead of the alphabetically nearest wrong language — `tlh` no longer formats with Afar data.

* Compact formats no longer raise on a negative `:fractional_digits` option.

### Changed

* `mix test --cover` now excludes build-time tooling (the data-generation pipeline, mix tasks, compile-time parser generators) from coverage measurement so the number reflects the runtime library.

## [0.43.0] — July 4th, 2026

This release settles the public API naming and error conventions ahead of 1.0. Every renamed function keeps its old name as a deprecated delegate that will be removed by Localize 1.0 and no later than December 2026.

### Deprecated

The naming rule is now uniform: `known_*` is the locale-independent CLDR universe, `supported_*` reflects configuration, and `*_for` is data localized into a display locale. The renamed functions are:

* `Language.available_languages/1` → `Language.languages_for/1`.

* `Language.known_languages/1` → `Language.language_names_for/1`.

* `Script.available_scripts/1` → `Script.scripts_for/1`.

* `Script.known_scripts/1` → `Script.script_names_for/1`.

* `Subdivision.available_subdivisions/1` → `Subdivision.subdivisions_for/1`.

* `Subdivision.known_subdivisions/1` → `Subdivision.subdivision_names_for/1`.

* `Territory.available_styles/0` → `Territory.known_styles/0`.

Two option names are also swapped for consistency; the deprecated keys remain accepted until 1.0:

* The `:style` option of `Localize.Duration.to_string/2` and of `Localize.quote/2` is deprecated in favour of `:format`.

* The `:format` option of `Localize.Unit.display_name/2` is deprecated in favour of `:style`.

### Changed

* `Language.display_name/2` and `Script.display_name/2` return `{:error, %Localize.InvalidValueError{}}` for an invalid `:style` or `:fallback` option instead of raising; the `!` variants raise as before.

* `Localize.quote/2` returns an error for an unknown format instead of silently returning the input string unquoted.

* The `backend: :nif` paths of `Number.to_string/2`, `Number.PluralRule.plural_type/2`, `Unit.to_string/2` and `Message.format/3` now validate the locale through `Localize.validate_locale/1` and pass ICU the canonical BCP 47 string, so both backends resolve aliases and `-u-` extensions identically.

* Internal implementation modules (`Localize.Utils.*`, collation internals, data plumbing) are no longer part of the documented API. The hex package metadata links now point at hexdocs.

### Added

* `Localize.Territory.known_territories/0` returns all CLDR territory codes.

* `Localize.validate_currency/1` delegates to `Localize.Currency.validate_currency/1` so all validators are available on the top module.

* Bang variants: `Number.to_at_least_string!/2`, `Number.to_at_most_string!/2`, `Number.to_approximately_string!/2`, `Calendar.display_name!/3` and `Unit.display_name!/2`.

## [0.42.0] — July 4th, 2026

### Changed

* Compact decimal/currency formats (`:decimal_short`, `:decimal_long`, `:currency_short`) now apply the ECMA-402/ICU default precision of at most two significant digits on the mantissa: `1234` renders "1.2K" (previously "1K"). Pass `:fractional_digits` or `:max_fractional_digits` to override.

* The `json_polyfill` dependency is no longer declared conditionally at publish time. On OTP 26, add `{:json_polyfill, "~> 0.2 or ~> 1.0"}` to your own dependencies; the supervisor raises at application start with instructions if the `:json` module is missing.

### Fixed

* Compact-format plural selection now uses the mantissa as displayed, per TR35, fixing grammatically impossible output such as es "1 millones" for 1,050,000. Exact-match `count="1"` compact patterns (fr 1000 → "mille") are now selected, matching ICU.

* Plural rules for compact values `{mantissa, exponent}` now compute the n/i/v/w/f/t operands after shifting by the exponent per the TR35 operand table, and Decimals with positive exponents (`1e6`) no longer report phantom visible fraction digits.

* BCE years render era-relative for `Calendar.ISO` dates: ISO year -1 formats as "2 BC", year 0 as "1 BC" (previously "-1 BC"/"0 BC").

* Significant-digit rounding no longer forces a trailing fraction digit when the rounded value is integral: 1234.567 at 3 significant digits renders "1,230" (previously "1,230.0"), and minimum significant digits now pad trailing zeros ("1.00" at min 3).

* A corrupt or truncated locale cache file is treated as a cache miss/stale instead of raising, and cache writes are atomic (write-temp-then-rename) so a crash mid-write can no longer tear a cache file.

* Locale downloads no longer follow HTTP redirects — the CDN URL is fully known, so a redirect is always refused.

* An unknown `:usage` option to `Localize.Unit.Preference.preferred_units/2` no longer creates atoms from user input; it falls back to `:default` preferences per TR35.

### Added

* The hex package now includes the NIF sources (`c_src/`), so `LOCALIZE_NIF=true` builds from the published package.

## [0.41.3] — July 1st, 2026

### Changed

* `Localize.LanguageTag`'s `canonical_locale_id` field — and therefore `Localize.LanguageTag.to_string/1` — now holds the *canonical-syntax* form of the requested locale (aliases resolved and subtags ordered, but neither maximized nor minimized), so `"en"` stays `"en"` and `"en-US"` stays `"en-US"` instead of collapsing to the minimal identity form. Locale identity and data lookup are unaffected; they key off `cldr_locale_id`.

* `Localize.Language.display_name/2` now follows the TR35 display-name algorithm, which canonicalizes rather than adds likely subtags: a bare language keeps its own name (`"en"` → `"English"`, `"es"` → `"Spanish"`), while an explicitly supplied region or script still resolves to the region-specific CLDR name (`"en-GB"` → `"British English"`, `"pt-BR"` → `"Brazilian Portuguese"`). A string and an equivalent `Localize.LanguageTag` return the same result.

* `Localize.Language.display_name/2` and `Localize.Locale.LocaleDisplay.display_name/2` both now validate their input through `Localize.validate_locale/1` and drive the display off `canonical_locale_id`, so a string and an equivalent (maximized) `Localize.LanguageTag` render identically and no likely subtags leak into the output (a validated `"en"` tag is `"English"`, not `"English (United States)"`).

### Fixed

* `Localize.Language.display_name/2` and `Localize.Locale.LocaleDisplay.display_name/2` now break the two-subtag candidate tie toward the earlier subtag per TR35, trying `lang-script` before `lang-region`.

* `Localize.validate_locale/1` now accepts a `-u-rg-` region override that uses a subdivision id (e.g. `"en-u-rg-gbeng"`). The subdivision value was being suffixed with the `"zzzz"` region filler and rejected as an unknown locale.

## [0.41.2] — July 1st, 2026

### Fixed

* Plural rules now resolve likely subtags before selecting a rule set. `Localize.Number.PluralRule.Cardinal` and `Ordinal` (`pluralize/3`, `plural_rules_for/1`, `plural_rule/3`) and `Localize.Number.PluralRule.plural_type/2` validate the locale through `Localize.validate_locale/1` instead of a bare parse, so a string and an equivalent `Localize.LanguageTag` select the same category and region-specific rules apply — e.g. `plural_rule(0, "pt-PT")` is now `:other` (Portugal) rather than `:one` (the base `pt`/Brazil rule). This also corrects plural selection in message formatting.

* `Localize.Territory.contains?/2` now validates both arguments, so string and atom territories are equivalent (`contains?("EU", "DK")` matches `contains?(:EU, :DK)`); it returns `false` for an invalid territory instead of silently treating a string as unmatched. It now also accepts territory strings, matching its sibling relationship functions.

* `Localize.Collation.Options.from_locale/1` now canonicalises its input through `Localize.validate_locale/1`, so a string, atom, and equivalent `Localize.LanguageTag` yield identical collation options and legacy aliases resolve correctly (`"iw"` behaves as `"he"`, `"pt_BR"` as `"pt-BR"`).

## [0.41.1] — June 30th, 2026

### Fixed

* `Localize.Language.display_name/2` now normalises its input through `Localize.validate_locale/1`, so a string and an equivalent `Localize.LanguageTag` return the same name (`"en-GB"` and `LanguageTag.new!("en-GB")` both give `"British English"`) and region-specific codes resolve with fallback (`"pt-BR"` → `"Brazilian Portuguese"`, `"ar-SA"` → `"Arabic"` instead of raising). A malformed locale now returns `Localize.InvalidLocaleError` rather than `Localize.UnknownLanguageError`. Thanks to @DVSLabs for the report. Closes #36.

## [0.41.0] — June 3rd, 2026

### Changed

* **Breaking:** `Localize.Number.Format.Compiler` now rejects scientific patterns that contain a grouping separator (e.g. `"#,##0.###E0"`) at compile time. TR35 forbids grouping in scientific patterns; the comma was previously silently ignored at output time. Fix: drop the comma, or use a non-scientific pattern.

### Added

* TR35 engineering notation. Patterns like `"##0.#####E0"` now correctly shift the mantissa so the exponent is a multiple of the pattern's max integer-digit count: `12345 → "12.345E3"`, `123456 → "123.456E3"`. Fixed-width mantissa patterns (`"00.###E0"`) similarly shift to expose `min_integer_digits` integer digits. The shift is exact for `Decimal` (via the `%Decimal{exp: …}` field) and lossless for `Decimal`-promoted floats/integers.

* New `:engineering` format atom resolving to `"##0.######E0"`. CLDR ships no engineering pattern, so this is a Localize-supplied default — pass an explicit pattern string for different mantissa precision.

* Scientific-pattern emission now reads `options.symbols.exponential`, `options.symbols.minus_sign`, and `options.symbols.plus_sign` from the locale's CLDR data instead of hardcoding ASCII `"E"`, `"+"`, `"-"`. `ar/arab` renders `"أس"` with Arabic Letter Mark signs, `fa/arabext` renders the `"×۱۰^"` superscripting form, `ar/latn` wraps signs with U+200E LRM.

* `Localize.Number.Format.Compiler` now normalises `@`-significant scientific patterns per TR35: `"@@###E0"` ≡ `"0.0###E0"`, `"@@@##E0"` ≡ `"0.00##E0"`, etc. The compiler rewrites these to the canonical `0`-prefixed form so the runtime formatter does not need a separate `@`-aware path.

* New `:exponent_style` option on `Localize.Number.to_string/2`. `:e` (the default) emits the standard `1.234E3` form; `:superscript` emits `1.234 × 10³` using CLDR's `superscriptingExponent` symbol and Unicode superscript digits (`⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺`). Ignored for non-scientific patterns.

### Fixed

* `Localize.Utils.Math.round_significant/2` no longer crashes when called with a `Decimal` and `n <= 0` or with a Decimal zero of any sign. Previously these reached `:math.log10/1` deep in the Decimal square-root path and raised `:invalid_operation`; both cases now return the input unchanged.

* `Localize.Number.Format.Compiler.compile/1` propagates compile-time errors from `format_to_metadata/1` instead of crashing with `MatchError`.

## [0.40.0] — June 1st, 2026

### Changed

* **Breaking:** A *bare* relative `:locale_cache_dir` (no `:otp_app` set) is now refused at app start with `Localize.LocaleCacheDirError` — it resolved against the BEAM's CWD, which differs between mix tasks, `mix test`, and a release. Fix: add `:otp_app` to anchor the relative path, or use an absolute path.

### Fixed

* `Localize.Locale.Provider.locale_cache_dir/0` validates its configuration at app start (via `Localize.Supervisor`) and raises `Localize.LocaleCacheDirError` instead of silently reading from the wrong directory at runtime.

* `Localize.Locale.LocaleDisplay.display_name/2` no longer raises `FunctionClauseError` on a BCP 47 generic extension carrying an odd number of subtags (e.g. `cr-s-7b`); the trailing singleton chunk now renders as a bare subtag.

### Added

* New `:otp_app` config key. Three supported forms for the locale cache directory: (1) `:otp_app` only → `Application.app_dir(<otp_app>, "priv/localize/locales")`; (2) `:otp_app` + relative `:locale_cache_dir` → `Application.app_dir(<otp_app>, <relative>)`; (3) absolute `:locale_cache_dir` → used verbatim, `:otp_app` ignored.

## [0.39.0] — May 31st, 2026

### Fixed

* Scope download_locales skip check to the configured cache dir, not the bundled fallback. Thanks to @allenwyma for the issue. Closes #35.

## [0.38.0] — May 23rd, 2026

### Added

* `Localize.Locale.expand_locale_list/2` (and therefore the `:supported_locales` configuration) now accepts a Gettext backend module like `MyApp.Gettext` as an entry; it expands to `Gettext.known_locales/1` with each returned string re-resolved through the existing POSIX-normalisation and likely-subtag canonicalisation path. The check uses `Code.ensure_compiled/1` so the entry is safe to place in either `config.exs` or `runtime.exs`.

## [0.37.0] — May 17th, 2026

### Fixed

* `Localize.DateTime.Formatter` audit: removed remaining `:gregorian` / `Calendar.ISO` hardcoding. The `{0}` / `{1}` date-time placeholders now derive the CLDR calendar from the date instead of always asking for the gregorian pattern, ISO week-of-year (`w` / `Y`) prefers the date's own `iso_week_of_year/3` callback before falling back to converting to `Calendar.ISO`, and `iso_day/1`'s dead silent-fallback clause for unknown calendars was removed.

* `Localize.Date.to_string/2` now honours CLDR `number_system` overrides carried alongside date patterns — Hebrew dates render in Hebrew numerals (`י״ב באייר ה׳תשפ״ד`), Japanese imperial year-1 renders as `元年`, and numeric overrides like `:arab` transliterate per-field via the system's digit set. Algorithmic systems resolve through CLDR's `numberingSystems.json` to the right RBNF rule (`:hebr` → `:hebrew`, `:jpanyear` → `:spellout-numbering-year-latn` under `:ja`).

* `Localize.Date.to_string/2` with a skeleton format (e.g. `:yMMMM`) against a non-Gregorian calendar no longer infinite-loops. `Match.best_match/3` now receives the calendar explicitly and `resolve_skeleton` carries a `seen` set, terminating any residual match cycle.

* `Localize.Date.to_string/2` now honours non-Gregorian calendars carried in the date's `:calendar` field — previously every call hard-coded `:gregorian`. A `Date` built with `Calendrical.Japanese` now formats as `平成12年1月1日` under `:"ja-JP"` instead of `2000/01/01`.

* `Localize.Calendar.localize/3` for `:era` now derives the correct era by delegating to the date's `year_of_era/3` callback. Previously it always returned era 1, producing `白雉` (Hakuchi, AD 650) for every `Calendrical.Japanese` date.

* `Localize.DateTime.Formatter` `y` token now uses the calendar's `calendar_year/3` (or `year_of_era/3` as fallback) for non-`Calendar.ISO` dates, so era-relative year numbering — Heisei 12, Reiwa 6, AH 1420, BE 2543 — renders correctly.

* `Localize.DateTime.Format.resolve_variant/2` now handles the CLDR `%{format: pattern, number_system: ns}` variant shape. Without this, locales whose date patterns carry a `number_system` override (Japanese `jpanyear`, Hebrew `hebr`) silently fell back to Gregorian.

## [0.36.0] — May 15th, 2026

### Fixed

* Fix `currency_symbol: :none` when processing options for `Localize.Number.to_string/2`.

## [0.35.0] — May 14th, 2026

### Fixed

* `Localize.Unit.localize/2` and a list-of-units overload of `Localize.Unit.to_string/2` close the parity gap with `Cldr.Unit.localize/3`: passing `:usage` to `to_string/2` now resolves the locale-preferred unit set (territory derived from `:locale` via `Localize.Territory.territory_from_locale/1`), decomposes the value across it, and joins the parts with the locale's standard list pattern in a single call (e.g. `Localize.Unit.to_string(Localize.Unit.new!(1.83, "meter"), usage: :person_height, locale: "en-US")` returns `{:ok, "6 feet and 0.047 inches"}`).

* `Localize.Unit.Conversion.convert/3` and `Localize.Unit.decompose/2` now preserve `Decimal` precision end-to-end: `Decimal` inputs flow through Decimal arithmetic instead of round-tripping through float.

* `Localize.Unit` gains a `:format_options` struct field that `localize/2` populates from the `skeleton` attribute on CLDR's `unitPreferenceData` (e.g. `[round_nearest: 50]` for `usage: :road` distances of 300 m+ in region 001). `to_string/2` merges these per-unit options with caller-supplied options and forwards them to the number formatter, so a 311 m road distance now renders as `"300 meters"` rather than `"311 meters"`. Caller-supplied options win on conflict; usages whose CLDR preferences carry no skeleton (e.g. `person-height`) are unchanged.

* `Localize.Unit.Math.round/3` now accepts a rounding mode (`:half_up` default, plus `:half_even`, `:half_down`, `:up`, `:down`, `:ceiling`, `:floor`); float values are routed through `Decimal` so every mode produces consistent results. New `Localize.Unit.Math.trunc/1` truncates toward zero with the same Decimal/float/integer dispatch as `floor/1` and `ceil/1`.

* `Localize.Unit.measurement_system_for_territory/2` accepts a category second argument: `:default` (existing behaviour), `:temperature` (e.g. `:US` → `:us` for Fahrenheit), or `:paper_size` (`:US` → `:us_letter`, `:FR` → `:a4`). The category-specific maps in CLDR's `measurementData.json` only enumerate territories whose category system *differs* from their default measurement system, so the lookup falls through to the default for any territory not listed in the category map.

* `Localize.Unit.decompose/3` accepts an optional third `format_options` argument and stamps it on the trailing (smallest) decomposed unit; intermediate units whose integer part rounds to zero are now skipped, matching cldr_units' behaviour. This is what `Localize.Unit.localize/2` uses internally to thread CLDR preference skeletons through to `to_string/2`.

* `Localize.Unit.to_string/2` documents `:grammatical_gender` and `:grammatical_case` as accepted options, matching the naming used by `Cldr.Unit.to_string/3`. `:grammatical_case` selects a case-keyed pattern variant (existing functionality, now documented). `:grammatical_gender` is accepted for cldr_units API parity but only meaningful for compound-unit patterns; for simple units the gender is fixed by CLDR data and the option has no effect on output.

* `Localize.Unit.Preference.preferred_units/2` documents `:scope` and `:alt` as forward-compatible placeholder options accepted but unused, matching `cldr_units` API surface. CLDR 48 ships no `<unitPreference>` carrying these attributes.

## [0.34.0] — May 14th, 2026

### Fixed

* `Localize.Utils.Http` now resolves the HTTPS trust store via `:public_key.cacerts_get/0` before falling back to the existing `cacertfile` chain (configured path → `CAStore` → `:certifi` → well-known Unix paths). `mix localize.download_locales` previously failed on Windows because the resolver only searched Unix file paths even though the OS-native trust store was reachable. Thanks to @LostKobrakai for the report. Closes #30.

* `Localize.Number.System` no longer bakes the build host's absolute ETF path into its compiled BEAM which caused exceptions when the build host and deployment host were different. The lookup now happens at runtime via `Application.app_dir/2` from a function body. Thanks to @neilberkman for the PR. Closes #28.

### Added

* `Localize.Supervisor` is now a publicly documented module that owns the library's runtime supervision tree and runs the one-time post-start work (supplemental-atom interning, `:supported_locales` resolution). Consumers can keep the default OTP auto-start, or mark the dependency `runtime: false` and mount `Localize.Supervisor` directly under their own application supervisor. See the new `guides/supervision.md` for the full pattern.

## [0.33.0] — May 13th, 2026

### Changed

* **Breaking:** `Localize.Message.Sigil` is renamed to `Localize.Message.Sigils` to make room for additional MF2 sigils. Update any `import Localize.Message.Sigil` to `import Localize.Message.Sigils`.

### Added

* `Localize.Message.Sigils` adds a new `~t` sigil for compile-time MF2 translation. Elixir `#{expr}` interpolations are rewritten as MF2 `{$name}` placeholders with bindings derived automatically (`fruit.name → fruit_name`, `String.upcase(x) → string_upcase`, etc.), the canonical msgid is registered with Gettext for translation lookup, and modules opt in via `use Localize.Message.Sigils, backend: MyApp.Gettext`. Requires the backend to use `Localize.Gettext.Interpolation`.

* `Localize.Gettext.Interpolation.skip_interpolation_sentinel/0` — public sentinel used by `Localize.HTML.t/1` (and other markup-aware renderers) to retrieve a translated MF2 source without running the markup-stripping interpolation. Both `runtime_interpolate/2` and `compile_interpolate/3` short-circuit when this sentinel is passed as bindings.

### Fixed

* `Localize.Application.start/2` now eagerly reads every bundled supplemental dataset (languages, scripts, territories, variants, subdivisions, units, currency codes, calendars, timezones, territory subdivisions, locale ids, number systems) so the atoms they reference are interned at app start. The 0.30.0 atom-DOS hardening switched many lookups to `binary_to_existing_atom`, which assumes the legitimate atoms already exist. Without the eager-load, valid input like `numberingSystem=arab` could surface as a bogus "unknown numbering system" error on a fresh BEAM where no prior code path had triggered the relevant `binary_to_term/1` read. Manifested as a transient CI failure in `Localize.Message.NumberOptionsTest`; cause was identical in shape to issue #26.

* `Localize.default_locale/0` no longer hangs when `LANG`/`LC_*` hold values that fail validation (e.g. `POSIX` on minimal CI runners): the resolver pre-seeds the `:persistent_term` cache with `:en` before walking the env-var/app-config chain so a recursive locale lookup during warning formatting short-circuits, and the two warning sites now use a non-localised message to avoid the `Exception.message/1` → Gettext-backend → `get_locale/0` recursion that produced the original 60-second hang in `localize_translate` CI.

## [0.32.0] — May 12th, 2026

### Fixed

* `mix localize.download_locales` no longer evaluates `config/runtime.exs` of the consumer application. Previously the task ran `Mix.Task.run("app.config")`, which transitively evaluated `runtime.exs`, which was not necessary. The task now loads only compile-time config (`config/config.exs` and any imported env-specific file), matching the build-time contract its docstring already advertised. Thanks to @whatyouhide for the PR.

* Hardened two further sites that pattern-matched `{:ok, _} = <fallible Localize call>` and could have surfaced the same `MatchError` class as issue #26: the per-unit format loop in `Localize.Duration.to_string/2` now short-circuits on the first formatter error, and `Localize.Number.Formatter.Decimal`'s digit-transliteration step now uses `with` to fall through to untransliterated digits if either the requested or `:latn` number-system data is unavailable.

* New `Localize.LintTest` source-level lint that scans `lib/` and fails the test suite if any file pattern-matches `{:ok, _} =` against a known-fallible Localize call. The list of fallible calls and an empty allowlist live in the test; future occurrences fail loudly on the offending PR rather than waiting for a runtime regression report.

* New `Localize.Locale.FallbackResilienceTest` exercises the load → store → get pipeline for seven representative regional locales under a provider that only serves `:en`, asserting that the data ends up under the canonicalised requested key and that `provider.get/3` succeeds.

* New `Mix.Tasks.Localize.DownloadLocalesTest` calls `DownloadLocales.banner/2` directly with `default_locale: :"en-ZA"` set, reproducing the exact scenario from issue #26 without invoking the network. `banner/2` is now `@doc false` so the test can reach it.

* New `Localize.AtomInterningTest` exercises the public lookup paths that previously surfaced the supplemental-atom bug — `Localize.Number.System.system_name_from/2` and friends, plus `Localize.Currency.validate_currency/1`, `Localize.validate_calendar/1`, `Localize.validate_territory/1`, `Localize.validate_script/1` — each driven with binary input. A regression in `intern_supplemental_atoms/0` would surface here as a structured error from one of these accessors.

## [0.31.0] — May 12th, 2026

### Fixed

* `Localize.Locale.Loader` now stores fallback locale data under the *requested* locale id rather than the *resolved* fallback id, restoring 0.29 behaviour. The regression introduced in 0.30.0 caused `provider.get(requested_locale, _)` to miss in-memory fallback data and surface as a spurious `ItemNotFoundError` — most visibly crashing `mix localize.download_locales` with a `MatchError` when `default_locale` named an unavailable locale. Locked down with `test/localize/locale/loader_fallback_test.exs`. Closes #26.

* `mix localize.download_locales` no longer pattern-matches on the result of `Localize.Message.format/2` when building its progress banner; if formatting fails for any reason the task falls back to a plain ASCII banner and continues with the actual download.

### Changed

* `Localize.InvalidValueError` gained an `:allowed_values` field and a new `Localize.NoCertificateStoreError` carries the searched paths; previously prose-stuffed `:expected`/`:currency` fields and bare-string `:reason` codes are now structural.

* Eight option-validation sites across `Localize.Language`, `Localize.Script`, `Localize.Collation`, `Localize.Utils.Map`, and `Localize.Utils.Http` now raise structured Localize exceptions rather than `ArgumentError`/`RuntimeError`.

## [0.30.1] — May 12th, 2026

### Fixed

* Revert the `[:safe]` option on `:binary_to_term/2` since we cannot guarantee all the required atoms are materialized at application start. Thanks to @bigardone for the report. Closes #25.

## [0.30.0] — May 12th, 2026

### Security

* `Localize.LanguageTag.parse/1` no longer calls `String.to_atom/1` on raw parser output, closing an atom-table-exhaustion DOS vector on untrusted locale inputs. Atomisation is now gated behind the CLDR validity sets after alias resolution, and unrecognised language/script/territory subtags return `Localize.InvalidSubtagError`.

* `Localize.Locale.to_locale_id/1` renamed to `Localize.Locale.cldr_locale_id_from/1` and now returns `{:ok, atom()} | {:error, Exception.t()}`, gating atom creation behind `Localize.validate_locale/1` and closing a second atom-table-exhaustion vector on locale inputs.

* `Localize.Currency.validate_currency/1`, `territory_currencies/1`, `current_currency_for_territory/1`, and the binary-code branch of `currencies_for_locale/3`'s filter no longer atomise input before checking validity. Unknown currency or territory binaries are rejected via `Helpers.existing_atom/1` and never grow the atom table.

* `Localize.Script.display_name/2` and `Localize.Unit.Formatter` no longer atomise binary input before checking validity. Unknown script codes return `Localize.UnknownScriptError` without growing the atom table; the unit formatter's currency atomisation is gated as defence-in-depth behind the upstream `Localize.Unit.validate_currency_codes/1` check.

* MF2 `:list` function and unit parser no longer atomise user-controlled binaries. The `:list` function's binary `style=` fallthrough now sets a sentinel atom that surfaces as an `InvalidValueError` in `Localize.List`, and SI prefix names are resolved through a compile-time lookup map (`Localize.Unit.Data.si_prefix_atom/1`) rather than `String.to_atom/1` at parse time.

* `Localize.Number.System` (`system_name_from/2`, `number_system_digits/1`, `to_system/2`), `Localize.Number.Symbol.number_symbols_for/2`, and the datetime-formatter's `time_preferences_for/1` no longer atomise user-supplied binary number-system or locale names before validation. Lookups go through `Helpers.existing_atom/1` against pre-atomised CLDR data sets.

* Closed additional Atom DOS vectors in `Localize.Locale.LocaleDisplay.display_name/2` (now routes through `cldr_locale_id_from/1`), `Localize.Territory.Subdivision.display_name/2`, the `-u-co-` and `-u-kr-` extension parsers in `Localize.Collation.Options`, and the redundant `String.to_atom(to_string(...))` round-trip in plural-rule fallback.

* Closed three further atom-DOS sites called out by the security audit's findings 1.4 and 1.5: `LocaleDisplay.U.find_exemplar_city/2` (`-u-tz-` IANA region/city splitter), `LocaleDisplay.T.to_atom_safe/1` (`-t-` extension subtag normalisation), and `Gettext.Interpolation.safe_to_atom/1` (missing-binding name reporting). All three previously fell through to `String.to_atom/1` on a miss, which defeated the helper's name; they now return the original binary unchanged when no atom exists.

* Locale cache files and downloaded ETFs are decoded with `:erlang.binary_to_term(_, [:safe])`. Closes a node-crash vector for any deployment with `:locale_cache_dir` set to a writable directory: a malicious or corrupted cache file can no longer resurrect arbitrary atoms, funs, or refs. Failed safe decodes surface as `LocaleNotFoundInCacheError` (or `LocaleDownloadError` for the download path) and the file is treated as stale.

* Public parser entry points now reject oversized input before invoking the grammar, capping the parser's CPU exposure on hostile input. Defaults are 256 bytes for `Localize.LanguageTag.parse/1` and `Localize.Unit.Parser.parse/1`, 64 KB for `Localize.Message.Parser.parse/1`, and 1 KB for `Localize.Number.Parser.parse/2`. Each cap is configurable via app env (`:max_locale_id_bytes`, `:max_message_bytes`, `:max_unit_bytes`, `:max_number_bytes`). `Number.Parser.parse/2` additionally rejects `Decimal` results whose exponent magnitude exceeds `:max_decimal_exponent` (default ±100) so downstream multiplication or formatting cannot materialise huge mantissas.

* `Localize.FormatCache` ETS table switched from `:public` to `:protected`; writes are routed through the cache GenServer. The size cap (`:format_cache_max_entries`, default 2 000) is now enforced **synchronously on each insert** rather than by a 10-second sweeper, replacing the previous biased-random eviction that could leave the cache oversized. New `Localize.FormatCache.clear/0` and `size/0` helpers added for tests and maintenance.

* NIF (ICU bindings) hardened. All NIF entries except `nif_plural_rule` now run on the dirty CPU scheduler pool (`ERL_NIF_DIRTY_JOB_CPU_BOUND`); the collator pool is sized for `schedulers + dirty_cpu_schedulers` and `reserve_coll` refuses overflow rather than reading past the array end. The reorder-codes branch caps `numCodes` at 256 and checks `enif_alloc` before use; every `std::stoll`/`std::stod`/`std::stoi` is wrapped in `try/catch` so out-of-range C++ exceptions cannot unwind through the NIF boundary; the hand-rolled JSON arg parser guards each access after `skip_ws`; per-call input lengths are capped at the NIF boundary (`MAX_MF2_BYTES = 64 KB`, `MAX_COLLATION_BYTES = 1 MB`, `MAX_NUMBER_STR_BYTES = 1 KB`).

* `Localize.Unit.CustomRegistry.load_file/1` now refuses to evaluate the file in `:prod` (or any environment without a loaded `Mix` module — typical for releases) unless `config :localize, :allow_runtime_unit_files, true` is explicitly set. Outside `:prod` the function works as before. The flag exists so an unintended feature switch in production cannot accidentally surface arbitrary code execution via `Code.eval_file/1`.

* `:localize_locale_cache` ETS table switched from `:public` to `:protected`, owned by `Localize.Locale.Loader`. Writes are routed through the owner via `cast` (so the hot validate path doesn't block and writes triggered from inside the owner's own `handle_call` cannot deadlock). Reads remain direct ETS lookups. Combined with the format cache fix above, both ETS caches are now `:protected` against multi-tenant or other-library interference.

* `Localize.Utils.Http.get/2` and `get_with_headers/2` now reject responses larger than 50 MB by default (configurable via `:max_http_body_bytes` app env or per-call `:max_body_bytes` option). Without the cap a malicious or compromised CDN could feed a multi-gigabyte response and OOM the BEAM. Oversized responses log an error and return `{:error, :response_too_large}`. Additionally, when peer certificate verification has been disabled (via `LOCALIZE_UNSAFE_HTTPS`), a one-time `Logger.warning` is emitted so a misconfigured production deployment cannot silently downgrade TLS without leaving an audit trail.

## [0.29.0] — May 11th, 2026

### Changed

* `Localize.Currency.currency_for_code/2` now returns the new `Localize.CurrencyNotLocalizedError` (instead of `UnknownCurrencyError`) when the currency code is valid but the locale has no display data for it. `UnknownCurrencyError` is now reserved for codes that aren't recognised ISO 4217 or registered custom currencies.

### Added

* `Localize.Currency.currency_for_code/2` accepts a new `:fallback` option which walks the CLDR parent locale chain and the application default locale before failing. Thanks to @neilberkman for the PR.

* `Localize.Locale.get/3` accepts a new `:fallback_to_default` option for a final-step fallback after any `:fallback` parent walk. Accepts `true` (use `Localize.default_locale/0`), or an atom/string/`Localize.LanguageTag` for a specific locale.

* Add `:iso_3166` option to `Localize.Territory.territory_codes/1` to return only ISO 3166 codes (not aggregate territories).

## [0.28.0] — May 9th, 2026

### Changed

* `Localize.Interval.to_string/3` Date intervals (style `:date`, the default) now resolve their skeleton **per-locale** instead of using a hard-coded locale-independent mapping. The interval looks up `Localize.DateTime.Format.date_formats(locale_id)[format]` — the same mapping `Localize.Date.to_string/2` uses — so date intervals follow the same conventions as single dates for the same `:format`. Visible effect on locales whose single-Date skeletons differ from the previous Interval table — most notably:

  - **ja `:medium`** is now numeric (`"2012/01/05～2012/01/06"`), aligning with single Date `:medium` (`"2012/01/05"`); was previously the abbreviated month form `"2012年1月5日～6日"`. The richer Japanese-character form is now `:long` (matching single Date `:long`).
  - **de `:medium`** is now numeric (`"15.01.2022 – 20.03.2022"`); was previously the abbreviated month form. To get `"15. Jan. – 20. März 2022"` request the `:yMMMd` skeleton explicitly.
  - **en `:long`** uses full month name with no weekday (`"January 5, 2012 – January 6, 2012"`); was previously the `:yMMMEd` form `"Thu, Jan 5 – Fri, Jan 6, 2012"`. The weekday now appears at `:full`. Per-locale skeletons that aren't shipped in CLDR's `interval_formats` data fall back to formatting each endpoint with `Localize.Date.to_string/2` and joining via the locale's `interval_format_fallback` template. Non-`:date` styles (`:month`, `:month_and_day`, `:year_and_month`) remain locale-independent — they describe a deliberate field selection unrelated to standard date styles. The static `Localize.Interval.date_styles/0` no longer includes a `:date` entry.

### Fixed

* Strip zone token for NaiveDateTime too in `Localize.Time.to_string/2` since they also do not have a time zone field. Relates to #22.

* Fix `Localize.Interval.to_string/3` silently ignoring the `:date_format` option on Date-only intervals. The option now overrides `:format` on the date axis, mirroring the precedence used for `:time_format` on time intervals. Relates to #22.

* Fix `Localize.Interval.to_string/3` raising `Localize.DateTimeIntervalFormatError` when called with `format: :full` on a Date interval. Relates to #22.

* `Localize.Utils.Math.sqrt/2` now respects the current `Decimal.Context.get/0` precision when called with a `Decimal` — the result is rounded to the configured precision and Newton's-method convergence scales accordingly.

* Added the test suite for `Localize.Utils` that are derived from the `Cldr.Util` equivalents.

## [0.27.0] — May 8th, 2026

### Fixed

* Fix `Localize.Interval.to_string/3` `:short` time-interval format using the wrong hour cycle on 24-hour locales. `:short` now picks `:hm` or `:Hm` per the locale's preferred hour cycle (honouring any `-u-hc-` Unicode-extension override), matching the cycle used by `Localize.Time.to_string/2` `:short`. Thanks to @woylie for the follow-up report. Fixes #22.

* Fix `Localize.Time.to_string/2` silently ignoring the `-u-hc-` Unicode-extension override on the locale. The override now applies to both standard formats (`:short`/`:medium`/`:long`/`:full`) — remapped to the locale's cycle-appropriate `:hm`/`:hms`/`:hmsv` (12-hour, with the locale's AM/PM marker) or `:Hm`/`:Hms`/`:Hmsv` (24-hour) skeleton — and to user-supplied skeleton atoms like `:Hms`, where the hour symbols are substituted.

* Fix zone-field artefacts on `%Time{}` standard formats. A `Time` carries no zone information, so `Localize.Time.to_string/2` now strips zone characters (`z`, `Z`, `O`, `v`, `V`, `x`, `X`) from the resolved skeleton ID before formatting. `Localize.Time.to_string!(~T[21:00:00], format: :long, locale: :ja)` returns `"21:00:00"` (was `"21:00:00 "` — trailing space), and `:es` `:full` returns `"21:00:00"` instead of `"21:00:00 ()"` (parens around the empty zone field).

* Adds support for `Decimal` version 3.0 to address a [CVE](https://github.com/ericmj/decimal/security/advisories/GHSA-rhv4-8758-jx7v). Thanks to @mitchellhenke for the PR.

### Added

* Add `Localize.Time.hour_format_from_locale/1` (and `!/1`) returning the locale's preferred hour cycle (`:h11`/`:h12`/`:h23`/`:h24`), honouring any `-u-hc-` Unicode-extension override.

## [0.26.0] — May 6th, 2026

This release fixes user-reported bug #22 in time interval formatting and a number of RBNF conformance bugs arising from a more complete conformance testing process. The RBNF bugs have been around unreported and undiagnosed for many years.

### Changed

* **Breaking:** The default `Localize.Interval.to_string/3` format output (which is `:medium`) for time-only inputs now includes seconds. `Localize.Interval.to_string!(~T[12:00:00], ~T[14:00:00], locale: :ja)` shifts from `午後0時00分～2時00分` to `12:00:00～14:00:00`. `:en`'s `:medium` shifts from `12:00 – 2:00 PM` to `12:00:00 PM – 2:00:00 PM`. Users who relied on no-seconds output should explicitly pass time_format: `:short`.

### Fixed

* Fix `Localize.Interval.to_string/3` collapsing the `:short`, `:medium`, `:long`, and `:full` time styles to the same `:hm` skeleton on Time inputs. `:short` keeps CLDR's interval-format dispatch (collapsed AM/PM); `:medium` and above route through the locale's per-style time-format pattern, restoring per-style differentiation and including seconds in the default `:medium` output. Thanks to @woylie for the report. Fixes #22.

* Fix `:time_format` being silently ignored on `Localize.Interval.to_string/3` for Time inputs. The option now takes precedence over `:format`, matching the precedence used on datetime intervals. Thanks to @woylie for the report. Fixes #22.

* Fix `Localize.Interval.to_string/3` crashing with `FunctionClauseError` when called with a binary `:format` (or `:time_format`) on Time inputs. Binary patterns are now applied to both endpoints and joined via the locale's interval-format fallback template, matching the behaviour of datetime intervals. Thanks to @woylie for the report. Fixes #22.

* RBNF parser now distinguishes `>>` from `>>>` so CJK locales emit fractional digits without an inter-digit separator — `Localize.Number.Rbnf.to_string(3.14, "spellout-numbering", locale: :zh)` is `三点一四` instead of `三点一 四`.

* RBNF leading and embedded zeros in fractional digits, and very small magnitudes, are now preserved — `0.05 en` is `"zero point zero five"`, `3.04 zh` is `三点〇四`, and `0.000001 en` is `"zero point zero zero zero zero zero one"`.

* RBNF `0.x` special-base rule now matches when the integer part is zero and the value is non-zero, routing ko `0.5 spellout-numbering` through its locale-correct sino-Korean `영점오` instead of the previous `x.x`-fallback `공점공오`.

* RBNF negative floats no longer double their output or silently drop the sign — ko `-0.5 spellout-numbering` is `-영점오` instead of `공점공점오`, and locales that lack a `-x` rule now get an ASCII `-` prefix.

* RBNF integer `<#,##0<` quotient and float `>%name>` / `>#,##0>` / `<%name<` modulo and quotient no longer crash, completing case-clause coverage for every TR35 substitution-argument shape.

* RBNF `$(cardinal,…)` and `$(ordinal,…)` plural-keyed substitutions now use the requested locale's plural rules instead of hard-coding English — fr `Localize.Number.Rbnf.to_string(21, "digits-ordinal-masculine", locale: :fr)` is `"21e"` instead of `"21er"`.

* RBNF fraction-with-rule numerator/denominator algorithm is now spec-correct — ky `1.5 spellout-cardinal` is `бир бүтүн ондон беш` instead of `бир бүтүн беш`.

### Added

* Add `:minimum_significant_digits` and `:maximum_significant_digits` options to `Localize.Number.to_string/2`.

* `Localize.Number.Rbnf.to_string/3` now accepts `Decimal` inputs in addition to native integers and floats, with whole-valued Decimals routed through the integer path with no precision loss.

* RBNF `>>>` integer modulo now applies the source-preceding rule per TR35 §RBNF_Syntax, closing a latent gap; no current CLDR locale exercises this path.

## [0.25.0] — May 1st, 2026

### Fixed

* Fix en-CA :short date crash; teach :prefer about CLDR variant/standard alts. Thanks to @dabaer for the report. Closes #21.

### Changed

* Module refactoring to remove many compile-time cycles.

## [0.24.0] — April 29th, 2026

### Fixed

* `Localize.DateTime.Formatter` stand-alone pattern helpers now pass `context: :stand_alone` to `Localize.Calendar.localize/3` instead of an invalid `type:` option. Thanks to @timpritlove for the PR. Closes #20.

* Rename calendar `:format`/`:stand_alone` typespec and docs from `:type` to `:context`.

* Clarify `Unit.display_name/2` vs `to_string/2` in docs.

## [0.23.0] — April 25th, 2026

### Fixed

* Fix `Cldr.Number.to_string/2` for `Decimal` numbers to produce the correct decimal digits.

* Fix `LOCALIZE_UNSAFE_HTTPS` env-var contract — values like `"FALSE"`, `"nil"`, an empty string, or unset all keep TLS verification on; only a truthy value disables it. Thanks to @rubas for the PR. Closes #15.

* Fix `Localize.Locale.load/2` and `Localize.Locale.get/3` to honor the `:provider` option — `load/2` no longer calls `provider.store/2` with the locale id, and `get/3` now loads through the same provider it reads from. Thanks to @rubas for the PR. Closes #16.

* `Localize.Locale.get/3` now honors the `:fallback` option by walking the CLDR parent locale chain when a key is missing in the requested locale. Fallback is handled in `Localize.Locale` so provider modules stay focused on store-and-fetch semantics. Thanks to @rubas for the PR. Closes #17.

* Public formatters (`Localize.Date`, `Localize.Time`, `Localize.DateTime`, `Localize.DateTime.Relative`, `Localize.Interval`, `Localize.List`, `Localize.Calendar`) now accept raw parsed `Localize.LanguageTag` structs whose `:cldr_locale_id` is not yet populated. The seven per-module locale resolvers collapse to one shared `Localize.Locale.cldr_locale_id_from/1`. Thanks to @rubas for the PR. Closes #18.

* Fix `Localize.available_locale_id?/1`, `Localize.validate_calendar/1`, and `Localize.validate_number_system/1` to never intern caller-supplied strings as new atoms. Lookups now use compile-time string→atom maps for O(1) safe membership. Thanks to @rubas for the PR. Closes #19.

* `Localize.supported_locales/0` now lazily resolves `config :localize, supported_locales: [...]` from the application environment when the `:persistent_term` cache has not yet been populated, instead of falling back to the full CLDR locale list. The cache is populated on application startup, but callers that run before the application has started — notably compile-time macro expansion in dependent applications like `localize_web`'s `~q` sigil — previously saw the full CLDR list during partial recompiles. This caused `Localize.validate_locale/1` to best-match against all CLDR locales rather than the configured subset, producing incorrect `cldr_locale_id` resolutions.

## [0.22.0] — April 22nd, 2026

### Fixed

* Fix Cldr.Number.to_string/2 for Decimal numbers to produce the correct decimal digits.

## [0.21.0] — April 22nd, 2026

### Fixed

* Fix normalizing CLDR locale names to our standard atom format in `Localize.validate_calendar/1`.

* `Localize.Calendar.iso_day_of_week/1` no longer crashes with `MatchError` on non-ISO calendars. The generic branch destructured `calendar.day_of_week/4` as a 2-tuple but the `Calendar` behaviour returns `{day, first, last}`.

* `Localize.Time.to_string/2` with a partial time and a standard format atom (`:short`/`:medium`/`:long`/`:full`) now derives a CLDR skeleton from the fields actually present (`:h`, `:hm`, `:ms`) instead of returning `DateTimeUnresolvedFormatError`.

* `Localize.DateTime.to_string/2` no longer silently drops the hour when given a partial datetime such as `%{year: _, month: _, day: _, hour: _}` without `:minute`. Partial datetimes render via a split date + time path composed with the locale's datetime wrapper.

* `Localize.DateTime.to_string/2` with hour + minute (no second) under `:medium` no longer emits a stray trailing `:` before the AM/PM marker — the partial path derives the `:hm` skeleton instead of using the full `h:mm:ss a` pattern with an empty seconds slot.

* The datetime formatter's AM/PM handler now accepts any map with `:hour`, not just maps that also have `:minute`.

* `Localize.Number.to_string/2` now produces identical output for equivalent `Decimal` and float values. Previously `Decimal.new("1234.56")` rendered as `"1,234.560"` under the standard pattern because `Decimal.round/3` returns a result padded to the requested scale; the formatter now normalizes after rounding so only the digits actually needed are emitted. Currency and other formats with a mandatory minimum scale still pad correctly via `adjust_trailing_zeros/2`.

## [0.20.0] — April 22nd, 2026

### Fixed

* Fixes mapping CLDR calendar types to the implementation module name.

## [0.19.0] — April 19th, 2026

### Fixed

* Restored the support of RBNF locales in `Localize.Number.to_string/2`. They are implemented in `Localize.Number.Rbnf.to_string/1` but the delegation was lost on the `ex_cldr` transition. Thanks to @tangulip for the report. Closes #11.

## [0.18.0] — April 18th, 2026

### Changed

* **Breaking:** MF2 highlighter token class atoms renamed to match the tree-sitter capture taxonomy used by [`mf2_wasm_editor`](https://hex.pm/packages/mf2_wasm_editor), so one stylesheet now styles both server-rendered HTML and the browser editor.

* **Breaking:** `Localize.Message.to_html/2` now emits the new canonical class names with `_` converted to `-` on output (`.mf2-variable`, `.mf2-punctuation-bracket`, `.mf2-string-escape`, `.mf2-constant-builtin`, etc.).

* **Breaking:** `Localize.Message.to_ansi/2` default palette keys renamed to the new atoms.

### Removed

* The `mf2_theme_css/` directory and `scripts/generate_mf2_themes.exs` generator. Themes now live canonically in [`mf2_wasm_editor`](https://hex.pm/packages/mf2_wasm_editor).

### Fixed

* `Localize.Gettext.Interpolation.runtime_interpolate/2` no longer raises `Localize.ParseError` when a translated string is not valid MF2. It now returns the message unchanged and logs a warning, matching gettext's own "fall back to the msgid" behaviour for missing translations. Dev-facing UI copy that happens to contain MF2-like syntax (e.g. `{{…}}` or `.match`) no longer crashes callers.

## [0.17.0] — April 17th, 2026

### Added

* `mix format` plugin `Localize.Message.Formatter.Plugin`. Canonicalises MF2 messages in `~M` sigils and standalone `.mf2` files. Enable by adding the plugin to `.formatter.exs`. See the "`mix format` plugin" section in the [MessageFormat 2 guide](https://hexdocs.pm/localize/message_formatting.html).

## [0.16.0] — April 17th, 2026

### Fixed

* Fix locale download infinite recursion loop. Thanks to @woylie for the report. Closes #10.

## [0.15.0] — April 17th, 2026

### Added

* MF2 syntax highlighter. See `Localize.Message.to_tokens/2`, `Localize.Message.to_html/2` and `Localize.Message.to_ansi/2`.

### Fixed

* Fix the exception and message when formatting a number and specifying a number system that is not valid for the given locale.

## [0.14.0] — April 16th, 2026

### Changed

* **Breaking:** Remove `@derive` for `Jason` since `Jason` is no longer configured or used anywhere in the application.

### Fixed

* Fix locale downloader to ensure it only uses the `:cldr_locale_id` field to construct the download URL.

## [0.13.0] — April 15th, 2026

### Fixed

* `Localize.Interval.to_string/3` now correctly formats datetime intervals — matching `ex_cldr_dates_times` behaviour. Previously any interval between two datetime values was rendered as a date-only range, discarding the time portion. Now same-day intervals render as `"Apr 8, 2026, 12:00 PM – 2:00 PM"` (date once, time range) and different-day intervals render as `"Apr 15, 2026, 12:49 AM – Apr 16, 2026, 1:49 AM"` (full datetime on both sides). Time-only intervals (`Time` values on both sides) use the locale's time-interval patterns.

## [0.12.0] — April 15th, 2026

### Fixed

* Chinese collation tailorings (`zh-u-co-pinyin`, `zh-u-co-stroke`, `zh-u-co-zhuyin`) now produce correct locale-specific ordering for Han characters. .

* Han radical-stroke ordering (UAX #38) under `-u-co-unihan` now applies correctly. The `Localize.Collation.Han` module was previously orphaned — its data was never loaded in consumer apps and the sort path never consulted it. Radical data is now pre-generated in the build pipeline and shipped in `priv/localize/collation_table.etf`; the sort path invokes `Han.collation_elements/1` for CJK codepoints when the `:han_ordering` option is `:radical_stroke` (set automatically for the `-u-co-unihan` collation type).

### Added

* `Localize.Collation.Options.han_ordering` option — `:implicit` (default, UCA codepoint-based) or `:radical_stroke` (UAX #38). Automatically set to `:radical_stroke` for `-u-co-unihan` locales.

* Persistent-term cache for parsed tailorings. First call to `Tailoring.get_tailoring/2` parses the rule string (~70 ms for zh-pinyin); subsequent calls read from persistent_term in microseconds.

* Differential tests for `zh-u-co-pinyin`, `zh-u-co-stroke`, `zh-u-co-zhuyin`, and `ja-u-co-unihan` that assert output differs from root codepoint order for specific character pairs — guards against silent regressions.

### Changed

* `Localize.Collation.Han` is no longer a GenServer. Radical data is loaded alongside the main collation table by `Localize.Collation.Table` (one ETF, one load step).

## [0.11.0] — April 14th, 2026

### Added

* `Localize.Interval.to_string/3` now accepts `nil` for either the `from` or `to` endpoint to format an open interval (e.g. `"Jan 1, 2020 –"` or `"– Jan 1, 2020"`).

* New guide: [Interval and Duration Formatting](https://hexdocs.pm/localize/interval_and_duration_formatting.html) — covers `Localize.Interval` (including open intervals) and `Localize.Duration` (calendar-unit strings and numeric time strings) in one place.

## [0.10.0] — April 14th, 2026

### Changed

* Mix tasks now only do `Mix.Task.run("app.config")` followed by `Application.ensure_all_started(:localize)`, avoiding starting any consumer application. Thanks to @lostkobrakai for the report. Closes #7,

## [0.9.0] — April 14th, 2026

### Changed

* `Localize.Unit.Math.mult/2` and `Localize.Unit.Math.div/2` now factor operands that share the same base dimension.

## [0.8.0] — April 14th, 2026

### Added

* `Localize.Message.format_to_safe_list/3` and `format_to_safe_list!/3` — new MF2 formatting entry points that preserve markup structure instead of stripping it.

## [0.7.0] — April 14th, 2026

### Changed

* Territory subdivision functions are now in the Localize.Territory.Subdivision module. Some functions have been renamed, see `Localize.Territory.Subdivision`.  The translate functions have been removed.

## [0.6.0] — April 13th, 2026

### Added

* Public function wrappers in `Localize.Unit.Math` for all dimensionless functions: `sin/1`, `cos/1`, `tan/1`, `asin/1`, `acos/1`, `atan/1`, `sinh/1`, `cosh/1`, `tanh/1`, `asinh/1`, `acosh/1`, `atanh/1`, `exp/1`, `ln/1`, `log/1`, `log2/1`. Previously these were only accessible via `apply_dimensionless/2`.

### Fixed

* `apply_dimensionless/2` now validates that the unit is actually dimensionless before computing. Previously `sin(1 meter)` would silently return a result; it now returns `{:error, "sin requires a dimensionless value, got unit with base: meter"}`. Units must reduce to `revolution` (angles) or `part` (ratios) to be accepted.

## [0.5.0] — April 13th, 2026

### Added

* `:special` conversion support in `CustomRegistry`. Custom units can now be registered with `factor: :special` plus `:forward` and `:inverse` `{module, function}` tuples for nonlinear conversions. This enables logarithmic scales (decibels), temperature functions, density hydrometers, wire gauges, and other conversions that cannot be expressed as `value * factor + offset`.

* `Conversion.do_convert/3` now uses a generalised `special_unit/1` lookup that checks both `CustomRegistry` and a compiled `@built_in_special` map, replacing the previous hardcoded `:beaufort` pattern match.

## [0.4.0] — April 13th, 2026

### Fixed

* `Localize.all_locale_ids/1` (`:modern`, `:moderate`, `:basic`) now returns the correct expanded list of locales. Thanks to @cw789 for the report.

## [0.3.0] — April 13th, 2026

### Fixed

* Load custom units in a single batch to avoid churning `:persistent_store`

## [0.2.0] — April 13th, 2026

### Fixed

* SI prefix parsing for custom units. Custom units can now be prefixed with SI prefixes and power prefixes.

### Changed

* Custom unit category validation relaxed from a fixed allowlist to any non-empty string. The faciliates importing a broader range of unit definitions such as those from Gnu units.

## [0.1.0] — April 13th, 2026

Initial release.

### Highlights

* Full CLDR v48.2 locale data with lazy runtime loading from ETF files cached in `:persistent_term`. No compile-time backend configuration required.

* Number formatting — integers, decimals, percentages, currencies, ranges, and rule-based number formats (RBNF) including Roman numerals and CJK ideographs.

* Date, time, and datetime formatting using CLDR calendar patterns with `:short`, `:medium`, `:long`, and `:full` styles, custom skeleton patterns, and interval formatting.

* Unit formatting with plural-aware patterns, SI/binary prefixes, compound units, measurement system conversion, custom unit registration, and `Localize.Unit.Operators` for natural arithmetic (`km + m`).

* List formatting with locale-appropriate conjunctions, disjunctions, and unit list styles. Per-element formatting via `Localize.Chars`.

* ICU MessageFormat 2 (MF2) parser and interpreter with custom function registry, offset selection, JSON interchange, and bidirectional text support.

* Gettext integration — `Localize.Gettext.Interpolation` provides MF2-based interpolation for Gettext backends.

* `Localize.Chars` protocol — polymorphic locale-aware formatting with built-in implementations for 14 types and `Any` fallback to `Kernel.to_string/1`.

* Currency metadata, ISO 4217 validation, custom currency registration (private-use and extended codes), and territory-to-currency mapping.

* Display names for territories, languages, scripts, calendars, and full locale display names per the CLDR algorithm.

* Unicode Collation Algorithm (UCA) with CLDR locale-specific tailoring for 97 languages, including digraph expansion and script reordering.

* BCP 47 / RFC 5646 language tag parser with full Unicode extension support (`-u-`, `-t-`), locale distance matching, and parent chain resolution.

* On-disk locale cache with HTTPS download provider, version-based staleness detection, and `mix localize.download_locales` for build-time cache population.

* Optional NIF backend for faster Unicode normalisation and collation sort-key generation.

* Calendar data for all CLDR calendar systems including Buddhist, Hebrew, Islamic (5 variants), ROC, Indian, Persian, Coptic, Ethiopic, Chinese, Japanese, and Dangi.

* All public API functions return a standardized `{:error, exception}` (except bang variants). The exception is a standard Elixir exception struct populated with semantic information about the error. The error message can be returned by `Exception.message(exception)`. The exception messages are all Gettext messages using the MF2 format and can be localized.

See the [README](https://hexdocs.pm/localize/readme.html) for full documentation, configuration options, and usage examples.
