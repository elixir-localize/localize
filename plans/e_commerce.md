# E-commerce i18n: gap analysis and roadmap

**Status:** research and planning, last updated 2026-05-15

**Owner:** Localize maintainers

**Companion:** [~/Development/money/money/plans/money_range.md](~/Development/money/money/plans/money_range.md) — money range formatting, identified as the first gap.

## Why this plan exists

`Localize` covers the foundational locale-aware primitives — numbers, dates, units, lists, messages, calendars — and `Money` covers single-currency monetary formatting. Together they are necessary for a localised e-commerce site but they are not sufficient. Real e-commerce surfaces compose those primitives into dozens of higher-level patterns (sale prices, from-pricing, delivery windows, address forms, tax labelling, comparison tables) that every storefront builder ends up reinventing.

This plan catalogues the patterns observed across major international e-commerce sites, classifies each as already-supported / partially-supported / missing, and proposes where the missing work should land — in `Localize` itself, in `Money`, in new sibling libraries, or as documented patterns that don't need library support.

## Research method

Patterns drawn from current public-facing storefronts across major i18n-mature retailers in their *native locale-specific* presentations (not the auto-translated international versions): Amazon (en, fr, de, ja, en-GB, en-IN), Rakuten (ja), Mercado Libre (es-AR, pt-BR), Zalando (de, fr, en-GB), ASOS (en-GB, fr), Apple Store (across regions), IKEA (multi-locale catalogue), AliExpress (multi-locale), Etsy (en, fr, de, ja). Patterns are listed as observed; subjective copywriting choices ("Add to bag" vs "Add to cart") are out of scope — only patterns that need locale-aware *formatting* support are catalogued.

## Gap classification

For each pattern below, the **Support** column indicates:

* **✅ Done** — works end-to-end via existing public API.
* **🟡 Partial** — works for the common case but has known gaps (annotated).
* **❌ Missing** — no library support; users must build it themselves.
* **📝 Translation** — pure copywriting / glossary work, no library code needed.

The **Home** column proposes where the missing work should land:

* `Localize` — the core library.
* `Money` — the currency library.
* `localize_address` — **already shipped** sibling at v0.2.0 (libpostal-based parsing + OpenCageData formatting for 267 territories).
* `localize_phonenumber` — **already shipped** sibling (libphonenumber NIF binding with parse/format/validate/type/territory).
* `localize_commerce` — proposed umbrella for composite e-commerce helpers (does not yet exist).

## Pricing patterns

| # | Pattern | Example | Support | Home |
|---|---------|---------|---------|------|
| P1 | Single price | `$20.00` / `¥1,200` / `20,00 €` | ✅ Done | `Money` |
| P2 | Price range | `$20–40` / `¥20〜40` / `20–40 €` | 🟡 In flight | `Money` (planned [money_range.md](../../money/money/plans/money_range.md)) |
| P3 | Sale / strikethrough pair | `$̶3̶0̶ $20` with savings badge `Save 33%` | ❌ Missing | `Money` |
| P4 | "From" pricing | `From $99` / `À partir de 99 €` / `¥99〜` | ❌ Missing | `Money` |
| P5 | "Starting at / as low as" pricing | `Starting at $50/mo` | ❌ Missing | `Money` |
| P6 | Per-unit price (real CLDR units) | `$0.50/oz` / `€2.99/100g` | ✅ Done | `Localize.Unit` (`curr-USD-per-pound`) |
| P7 | Per-each / per-item pricing | `$1.20 each` / `1,20 € pièce` | 🟡 Partial | `localize_commerce` (English `per item` works via `curr-USD-per-item` but most locales fall back untranslated) |
| P8 | Subscription / per-time pricing | `$9.99/month` / `9,99 €/mois` | ❌ Missing | `Money` (or `localize_commerce`) |
| P9 | Installment plan | `4 payments of $25` / `4×25 € sans frais` / `4回払い` | ❌ Missing | `localize_commerce` |
| P10 | Tax-inclusive label | `$20 (incl. VAT)` / `20 € TTC` / `1,200 円 (税込)` | ❌ Missing | `Money` (with per-territory tax-label data) |
| P11 | Tax-exclusive label | `$20 + tax` / `20 € HT` | ❌ Missing | `Money` (paired with P10) |
| P12 | Approximate / converted price | `$20 (~€18)` with disclosure | ❌ Missing | `Money` (composite formatter) |
| P13 | Bulk-tier pricing | `1: $10, 5+: $8 each` / `5個以上 8ドル` | ❌ Missing | `localize_commerce` |
| P14 | "Free" / "POA" / "Contact for price" | `Free` / `Gratis` / `無料` / `Sur devis` | 📝 Translation | n/a |
| P15 | Superscript-cents display | `$19.⁹⁹` (US retail convention) | ❌ Missing | `Money` (presentation option) |
| P16 | Auction current-bid display | `Current bid: $42.50 · 17 bids` | ❌ Missing | `localize_commerce` |
| P17 | Free-shipping-threshold copy | `$15 to free shipping` / `Spend €5 more for free delivery` | ❌ Missing | `localize_commerce` (depends on Money diff) |
| P18 | Compact percentage-off badge | `−20%` / `20% off` / `20% de remise` | 🟡 Partial | `Localize.Number` (`format: :percent` works; the `−` vs `off` framing is translation) |
| P19 | Amount-off badge | `$5 off` / `−5 €` | 🟡 Partial | translation of "off"; Money formats the amount |
| P20 | Compare across currencies | `From $99 · €92 · ¥14,800` | ❌ Missing | `Money` (multi-currency display helper) |

### Notes on the priority pricing gaps

**P3 (sale/strikethrough)** is the highest-impact missing pattern — every e-commerce site does it. The struct shape is `{original, current, [savings_amount?, savings_percent?]}` and the formatter produces an iolist with markup hints (semantically: "strike this", "emphasise this") that templates can render. Lives naturally in `Money` since it's two `Money` values.

**P4 / P5 ("From" pricing)** are tiny prefix patterns, but the *prefix word* and its placement vary widely: English prefixes (`From $99`), French prefixes (`À partir de 99 €`), Japanese suffixes (`¥99〜`). This is more than a translatable string — the suffix-vs-prefix decision is locale-driven, similar to currency symbol position. Lives in `Money`.

**P10 / P11 (tax labels)** need a per-territory data table: which jurisdictions show tax-inclusive prices (most of EU, Japan, Australia), which show tax-exclusive (US, Canada), what the abbreviation is in each language (`VAT`, `TVA`, `MwSt`, `IVA`, `消費税`, `GST`). This is genuinely missing infrastructure; CLDR doesn't ship it.

## Quantity, packaging, and variant patterns

| # | Pattern | Example | Support | Home |
|---|---------|---------|---------|------|
| Q1 | Pack-of-N | `Pack of 12` / `Lot de 12` / `12er-Pack` / `12個入り` | ❌ Missing | `localize_commerce` |
| Q2 | Quantity selector labels | `Qty: 3` / `Quantité: 3` / `数量: 3` | 📝 Translation | n/a |
| Q3 | Stock level phrases | `In stock` / `Only 3 left` / `Out of stock` / `Backordered` | 📝 Translation | n/a (but template provided) |
| Q4 | Variant labels: size | clothing size systems (US 8 ≠ UK 12 ≠ EU 38 ≠ JP 11) | ❌ Missing | `localize_commerce` (size-system conversion table) |
| Q5 | Variant labels: color | localised color names | ❌ Missing | `localize_commerce` (CLDR ships `colorPattern` and `colors` data — partly usable) |
| Q6 | Variant labels: material | `Cotton` / `Coton` / `綿` | 📝 Translation | n/a |
| Q7 | Product weight / dimensions | `12 oz (340 g)` / `340 g` / `30 × 20 × 5 cm` | 🟡 Partial | `Localize.Unit` (single-value works; the `12 oz (340 g)` dual-display is missing) |
| Q8 | Lot / batch identifiers | `Lot #4521` / `バッチ#4521` | 📝 Translation | n/a |

### Notes

**Q4 (size systems)** is a harder data problem than it looks — CLDR doesn't ship clothing-size conversion tables. Each retailer publishes their own. A helper would need a community-maintained dataset (Wikipedia and ISO 5971 are starting points). High-value if shipped, but data-curation heavy.

**Q5 (color names)** — CLDR's `cldr-misc-modern` package ships `colors.json` per locale (~150 named colors). This data is already pulled in by Localize's normalizers but isn't exposed via a public API. Cheap to expose.

**Q7 (dual-unit display)** is the "show metric and imperial together" pattern. Common on US sites selling internationally. Lives in `Localize.Unit` as a `to_string_with_alternative/3` that takes the alternate measurement system as an option.

## Delivery, dates, and time patterns

| # | Pattern | Example | Support | Home |
|---|---------|---------|---------|------|
| D1 | Delivery date estimate | `Get it by Tue, Nov 5` / `Livraison le mardi 5 nov.` / `11月5日(火)お届け` | 🟡 Partial | `Localize.DateTime` (formats; the "Get it by" framing is translation) |
| D2 | Delivery window | `5–7 business days` / `5〜7営業日` | ❌ Missing | `Localize.Duration` extension |
| D3 | Cutoff time copy | `Order in next 3h 27m for delivery tomorrow` | ❌ Missing | `localize_commerce` (duration + relative date) |
| D4 | Sale countdown | `Sale ends in 2d 4h 18m` / `セール終了まで` | 🟡 Partial | `Localize.Duration` (formats; framing is translation) |
| D5 | Order placed timestamp | `Ordered 2 hours ago` / `il y a 2 heures` / `2時間前` | 🟡 Partial | `Localize.DateTime` (relative format works; CLDR ships `relativeTime` patterns) |
| D6 | Subscription renewal date | `Renews on Nov 15` | 🟡 Partial | `Localize.DateTime` (formats; framing is translation) |
| D7 | Business-day arithmetic | "ship Friday → arrives Tuesday" excludes weekends and locale holidays | ❌ Missing | `Localize.Calendar` (workdays + holidays) |
| D8 | Time-of-arrival window | `Arrives between 2 PM – 6 PM` | 🟡 Partial | `Localize.Time` (formats); range pattern usage is correct but undocumented |
| D9 | Local-timezone reminder in checkout | `Your local time is 3:00 PM EST` | 🟡 Partial | `Localize.DateTime` with explicit `:zone`; copy framing is translation |

### Notes

**D2 / D3** ("5–7 business days", "Order in 3h 27m") are duration *ranges* and duration *countdowns*. Localize has `Localize.Duration.to_string/2` for fixed durations but doesn't have a range form. CLDR's `unitPattern-count-X` for duration units (`day`, `hour`, `minute`) plus the `range` misc-pattern composes naturally — same shape as `Money.to_range_string/3`. Add `Localize.Duration.to_range_string/3`.

**D7 (business-day arithmetic)** is the "calculator" gap, not a formatting gap. Need workday calendar data per territory. CLDR ships `weekData` (which days are weekend per locale) and `weekendStart`/`weekendEnd` — partial. Public holidays are NOT in CLDR; would need a sibling data source like `nx_holidays` or per-territory Holiday packs.

## Address, location, and contact patterns

| # | Pattern | Example | Support | Home |
|---|---------|---------|---------|------|
| A1 | Postal address formatting | US: street/city/state/zip top-down; JP: postal/prefecture/city/street top-down | ✅ Done | `localize_address` (already shipped) |
| A2 | Country picker labels | `United States` / `États-Unis` / `アメリカ合衆国` | ✅ Done | `Localize.Territory.display_name/2` |
| A3 | Region/state picker labels | `California` / `Californie` / `カリフォルニア州` | 🟡 Partial | `Localize.Validity.subdivision` (raw data exposed; display names per locale need a helper); `localize_address` provides state-code lookup but not a picker-list builder |
| A4 | Postal code validation | format rules per country (US: 5 or 5+4; UK: complex; JP: 7 digits) | ❌ Missing | `localize_address` extension (parse exists; explicit regex validation does not) |
| A5 | Phone number formatting | E.164 / national / international forms | ✅ Done | `localize_phonenumber` (already shipped) |
| A6 | Phone country-code chooser | flag + country name + dial code | 🟡 Partial | composable from `localize_phonenumber` (territory + country code) + `Localize.Territory.display_name/2`; not packaged as a single helper |
| A7 | Time zone display | `EST (UTC−5)` / `JST (UTC+9)` | ✅ Done | `Localize.DateTime` (timezone formatting) |
| A8 | Currency-aware shipping eligibility | "We ship to 47 countries" composed UI | 📝 Translation | n/a |

### Notes (post-review of existing siblings)

**`localize_address` exists** (v0.2.0, April 2026) and goes substantially beyond what this plan originally proposed:

* **Parses** unstructured address strings via libpostal NIF — accepts user-typed legacy/freeform input.
* **Formats** structured addresses per-territory using OpenCageData templates (267 countries, 242 at 100% conformance, 98% pass rate on the OpenCageData conformance suite).
* **Address struct** carries the canonical component fields (`house_number`, `road`, `city`, `state`, `postcode`, `territory`, etc.) — same shape libpostal and OpenCageData consume.
* **State-code lookup** (e.g. "California" ↔ "CA") with `Localize.Territory.subdivision_name/2` as fallback.
* **Dependent territory handling** (NL → CW/AW/SX, CN SARs, `use_country` template inheritance for ~40 dependents).
* **Unicode-aware capitalisation** of address text via `Unicode.String`.

What `localize_address` does **not** yet ship that the e-commerce roadmap still wants:

* **Form-input schemas** (which fields are required for territory X; in what visual order should the form fields appear). OpenCageData templates know the *display* order; form *input* order and required-ness is a separate dataset (Google's i18n-libaddressinput is the canonical source — open licence). Worth filing as a follow-up.
* **Explicit postal-code regex validation** (A4). Localize.Address parses freeform; doesn't validate. Easy add — the data lives in CLDR's `postalCodeData.xml` (already in `priv/cldr/`) and Localize.Validity exposes it indirectly. A `Localize.Address.valid_postcode?/2` helper would close the gap.
* **Picker-list builders** for state/province dropdowns by territory (A3) — the data is reachable; a packaged helper isn't.

**`localize_phonenumber` exists** and likewise covers more than the plan proposed:

* **Parses** numbers (national or international form) with locale-driven default territory.
* **Formats** in three styles via `Localize.PhoneNumber.to_string/2` — E.164, international, national.
* **Validates** with `valid?/1`, `valid_for_territory?/2`, `possible?/1`.
* **Type detection** — mobile vs landline vs toll-free vs premium-rate (useful for form UX: "this looks like a landline; can we still text you?").
* **Territory resolution** from a parsed number.
* Wraps Google's libphonenumber via NIF (more complete than the Hex `ex_phone_number` Elixir port the plan originally referenced).

What `localize_phonenumber` does **not** yet ship:

* **Country-code chooser data** (A6) bundled as `Localize.PhoneNumber.country_codes/1` returning a list of `{territory, country_code, display_name}` for picker UIs. Composable from existing Localize APIs but not packaged.
* **As-you-type formatter** for live input formatting (libphonenumber has `AsYouTypeFormatter`; the NIF binding doesn't expose it). Worth filing for the e-commerce checkout UX.

## Tax, regulatory, and trust patterns

| # | Pattern | Example | Support | Home |
|---|---------|---------|---------|------|
| T1 | Tax label per jurisdiction | `incl. VAT` / `TTC` / `税込` / `+ tax` (US) | ❌ Missing | `Money` (or `localize_commerce`) |
| T2 | Customs / import-fee notice | `Includes import fees` / `関税込` | ❌ Missing | `localize_commerce` |
| T3 | Age-restriction badge | `21+` / `18歳以上` / `Mature audiences` | 📝 Translation | n/a |
| T4 | Per-jurisdiction returns policy | `30-day returns` (varies legally per country) | 📝 Translation | n/a |
| T5 | Right-to-cancel / cooling-off | EU 14-day cancellation right wording | 📝 Translation | n/a |
| T6 | Eco / recycling labels | Tidyman, Green Dot, etc. — country-required | 📝 Translation + asset bundles | n/a |
| T7 | GDPR / consent banners | localised legal text | 📝 Translation | n/a |

### Notes

**T1 / T2 (tax labels)** are the only library-shaped items in this group. The data needed is small: per-territory mapping `{territory => {label_key, position, abbreviation_per_locale}}`. The tricky part is which tax label applies (VAT vs sales tax vs GST vs consumption tax) is *legal* not *linguistic* — same locale (e.g. en-AU vs en-US) shows different tax labels. So this is keyed by `:territory`, not `:locale`.

## Trust / social / reviews

| # | Pattern | Example | Support | Home |
|---|---------|---------|---------|------|
| R1 | Star rating display | `4.5 out of 5` / `4,5 sur 5` / `4.5/5` | 🟡 Partial | `Localize.Number` formats the digits; the "out of 5" framing is translation |
| R2 | Review count formatting | `1,234 reviews` / `1.2K reviews` / `1万件のレビュー` | ✅ Done | `Localize.Number` (`format: :short` for compact) |
| R3 | Recency phrases | `Reviewed 2 days ago` / `il y a 2 jours` / `2日前にレビュー` | 🟡 Partial | `Localize.DateTime` relative format; framing is translation |
| R4 | "Verified buyer" / trust badges | localised phrases | 📝 Translation | n/a |
| R5 | Sold-quantity ribbons | `10,000+ sold` / `1万個以上販売` | 🟡 Partial | `Localize.Number` formats the count; the "+ sold" framing is translation |
| R6 | "Bestseller" / "Trending" | localised badge text | 📝 Translation | n/a |

## Cart, checkout, and order patterns

| # | Pattern | Example | Support | Home |
|---|---------|---------|---------|------|
| C1 | Cart line item composite | name + variant + qty + unit price + line total | ❌ Missing | `localize_commerce` (template helper) |
| C2 | Order summary breakdown | subtotal / shipping / tax / total — each formatted as Money | ✅ Done | composition of existing primitives |
| C3 | Currency conversion display | `$20 (~€18)` with rate disclosure | ❌ Missing | `Money` (multi-currency display helper) |
| C4 | Payment-method labels | `Apple Pay` / `WeChat Pay` / `Klarna` / `コンビニ払い` | 📝 Translation | n/a (but per-region availability is data-driven) |
| C5 | Comparison-table currency-as-header | header `USD` / row cells `20.00` (no symbol) | ❌ Missing | `Money` (`to_bare_string/2` already implicit via `currency_symbol: :none`; needs a documented pattern) |
| C6 | Loyalty point display | `100 points = $1` / `100ポイント = ¥100` | ❌ Missing | `localize_commerce` (composite formatter) |
| C7 | Gift recipient pronouns | gendered messages in copy | 📝 Translation | n/a (but this is exactly what MF2 selectors and the new `:grammatical_gender` plumbing are for) |
| C8 | Saved cards display | `Visa ending in 4321` / `4321で終わるVisa` | 📝 Translation | n/a |

### Notes

**C5 (currency-as-header tables)** is partly solved already: a comparison table can render the currency symbol once in the column header and use `Money.to_string(money, currency_symbol: :none)` in each cell. This is documented on `Money.to_range_string/3`'s plan but should also become a worked example in `Money`'s README.

## Search, navigation, and filter patterns

| # | Pattern | Example | Support | Home |
|---|---------|---------|---------|------|
| S1 | Price filter labels | `Under $50` / `$50–$100` / `$100+` | 🟡 Partial | uses Money + the locale's `atMost` / `range` / `atLeast` patterns; needs documented helper |
| S2 | Sort options | `Price: low to high` / `Prix: croissant` | 📝 Translation | n/a |
| S3 | Faceted filter chips | `In stock` `Free shipping` `On sale` | 📝 Translation | n/a |
| S4 | Breadcrumb separators | `Home / Electronics / Phones` (`/` vs `›` vs `>`) | 📝 Translation | n/a |
| S5 | Search-result count | `1,234 results` / `1 234 résultats` / `1,234件` | 🟡 Partial | `Localize.Number` formats; pluralisation handled via MF2 |

### Notes

**S1 (price filters)** is a natural Money composite. CLDR ships `atMost`, `atLeast`, and `range` patterns in `miscPatterns`; combined with Money's currency formatting, the helpers `Money.to_at_most_string/2`, `Money.to_at_least_string/2` (and the existing planned `to_range_string/3`) cover the standard filter set.

## Error and state patterns

| # | Pattern | Example | Support | Home |
|---|---------|---------|---------|------|
| E1 | Out-of-stock variants | `Out of stock` / `Sold out` / `Currently unavailable` / `売り切れ` | 📝 Translation | n/a |
| E2 | Price-changed alert | `Price has increased since you added to cart` | 📝 Translation | n/a |
| E3 | Quantity-limit message | `Limit 5 per customer` / `お一人様5点まで` | 📝 Translation | n/a |
| E4 | Validation errors per locale | `Invalid postal code for US` (depends on A4) | 🟡 Depends | `localize_address` |

## Summary: what we should build

Sorted by impact-to-effort ratio:

### High-value, low-effort (do first)

1. **`Money.to_range_string/3`** — already planned. Covers P2 and indirectly C5/S1.
2. **`Money` sale-pair formatter (P3)** — `Money.to_sale_string(original, current, options)` returns `{:ok, %{original: striked, current: emphasised, savings_amount: …, savings_percent: …}}` or an iolist with markup hints. Highest single-pattern impact.
3. **`Money.to_at_least_string/2` and `to_at_most_string/2`** — trivial wrappers over `Money.to_string/2` + the locale's `atLeast` / `atMost` misc patterns. Covers P4, P5, S1.
4. **`Localize.Duration.to_range_string/3`** — same shape as the Money equivalent. Covers D2, D8.
5. **Expose CLDR color names** (Q5) — data is already ingested; add `Localize.Locale.colors/1` returning the per-locale color map.
6. **`Money.to_per_unit_string/3` for the bare-each case (P7)** — accepts a Money plus a per-unit identifier (real CLDR unit OR the sentinel `:each` / `:item` / `:piece`) and produces locale-correct `"$1.20 each"` / `"1,20 € pièce"` / `"1.20ドル/個"`. Where CLDR has the unit, use it; otherwise consult a small per-locale "counting nouns" table.
7. **Document the currency-as-header table pattern (C5)** in `Money`'s README and possibly as a guide.

Estimate: **2–3 weeks** combined for a competent implementer.

### Medium-value, medium-effort (do next)

8. **Tax-label helper (T1, T2)** — `Money.to_tax_inclusive_string/2` and `to_tax_exclusive_string/2` driven by per-territory data table. Needs the data table built (~50 territories cover 95% of e-commerce).
9. **Subscription / installment pricing (P8, P9)** — `Money.to_per_period_string/3` (`$9.99/month`) and `Money.to_installment_string/3` (`4 payments of $25`). Both compose Money + Duration / count + locale phrasing.
10. **Multi-currency display (P12, P20)** — `Money.to_string_with_alternatives/3` produces `"$20 (~€18)"` for cross-currency contexts. Needs an exchange-rate service contract — define the protocol but don't ship a default service.
11. **Dual-unit display (Q7)** — `Localize.Unit.to_string_with_alternative/3` produces `"12 oz (340 g)"` by formatting in source unit + target measurement system + joining via the locale's parenthetical pattern.
12. **`Localize.Number.compact_format/2`** documented for review counts (R2) — already supported via `format: :short`; just needs better discoverability.

Estimate: **3–4 weeks** combined.

### Address / phone gaps on top of existing libraries (do once Phase 1 lands)

13. **`localize_address` extensions** — A4 postcode regex validation (`Localize.Address.valid_postcode?/2`), A3 subdivision picker-list builder (`Localize.Address.subdivisions_for/2` returning `{code, display_name}` pairs), and a Google i18n-libaddressinput-derived form-schema dataset for "which fields, in what order, with what required-ness, per territory". The first two are 1-week each; the form-schema dataset is the larger piece (~2 weeks including data licence review and ingestion).

14. **`localize_phonenumber` extensions** — A6 country-code chooser bundle (`Localize.PhoneNumber.country_codes/1` returning `[{territory, country_code, display_name}]` for picker UIs); A6 as-you-type formatter (expose libphonenumber's `AsYouTypeFormatter` via the NIF). Each ~1 week.

### High-value, high-effort (next major cycle)

15. **`localize_commerce` umbrella (Q1, Q4, P9, P13, P17, C1, C6)** — composite helpers (cart line items, free-shipping thresholds, bulk pricing, installments, loyalty points, pack-of-N labelling, size-system conversion). Pulls together everything from layers 1 and 2 into ergonomic site-builder helpers. Last to land because it consumes the others.

Estimate: **4–5 weeks** for `localize_commerce`; **~5 weeks** for the address/phone extensions in items 13–14.

### Pure translation / glossary (no library work)

P14, Q2, Q3, Q6, Q8, T3, T4, T5, T6, T7, R4, R6, C4, C8, S2, S3, S4, E1, E2, E3 — these are all genuine i18n needs but they are *translation* problems, not library problems. The MF2 translation pipeline (see [plans/mf2-translate.md](mf2-translate.md)) is the right tool for a maintainer to work through them at scale. A "starter glossary" of the most common e-commerce phrases per locale, shipped as part of `localize_commerce` documentation, would help users avoid solo re-translation of every standard phrase.

## Cross-cutting concerns

### Currency support gaps that block the above

* **Currency-aware exchange rates** — Money has currency *formatting* but no rate-source contract for cross-currency display (P12, P20). Define a behaviour `@callback rate(from, to, options) :: {:ok, decimal} | {:error, _}` and ship a noop default.
* **Currency display in non-currency contexts** — `Money.to_string` with `currency_symbol: :none` is the foundation for tables, ranges, and summaries; document this as the supported pattern, not just an internal trick.

### Data we'd need that CLDR doesn't ship

* Per-territory tax label data (T1, T2) — small table, build it.
* Clothing size systems (Q4) — community-curated; license carefully.
* Postal address form schemas and validation (A1, A4) — Google's `addressformat` data is open; investigate licence for direct ingestion.
* Public holidays per territory (D7) — partial coverage in `nx_holidays` and similar; evaluate.

### Composition pattern across all helpers

Almost every "missing" item composes existing Localize / Money primitives. The right architectural pattern is helpers that take pre-built `Money` / `Localize.Unit` / `Localize.Duration` structs as inputs and emit either formatted strings or `{:ok, structured_iolist}` with markup hints (so templates can render them with proper styling). Avoid string concatenation inside helpers — emit token lists that templates style. This keeps the semantic information available for accessibility / RTL / right-aligned-money columns / etc.

## Open questions

* **Should `localize_commerce` be a single library or several focused ones (`localize_pricing`, `localize_orders`, `localize_address`, `localize_phone`)?** Multiple narrow libraries are easier to adopt selectively and version independently. Trade-off: more namespaces to learn. Recommendation: start with `localize_address` and `localize_phone` as standalone (clear scope), then evaluate whether the smaller helpers want one umbrella or three.

* **Do we ship default tax-label data (T1, T2) or require user configuration?** Defaults handle 95% of cases; the remaining 5% are messy edge cases (US sales tax varies by state and *type of good*; Canadian GST/PST/HST varies by province and good). Recommendation: ship sensible defaults *only for jurisdictions with country-wide consistent rules* (most of EU, UK, Japan, Australia); require explicit configuration for federations (US, CA).

* **Currency conversion (P12, P20) — do we ship a default rate provider or just the protocol?** ECB rates are free and adequate for "approximate" display; live commercial rates need paid APIs. Recommendation: ship the protocol + a `Money.Rates.Static` provider for tests/dev; let users wire in `ex_money_sql` / their FX provider for production.

* **Size-system conversion (Q4) data — community-maintained or curated?** Wikipedia tables are unreliable for retail use (manufacturers vary). Recommendation: ship a small curated dataset from ISO 5971 / EN 13402 with a clear "this is approximate" disclaimer, and let users override per-product.

* **How much of `localize_commerce` should be opinionated UI components vs raw formatters?** A storefront wants the formatter API; a quick-start project wants drop-in components. Recommendation: ship raw formatters first (Phase 1–2); leave components for a separate `localize_phoenix_components` or `localize_liveview` library that depends on the formatters.

## Phasing

| Phase | Scope | Estimate | Blocking |
|-------|-------|----------|----------|
| 1 | Money: range, sale pair, at-least, at-most, per-unit; Duration: range; CLDR colors expose; per-each unit support; documentation of currency-as-header pattern. (Items 1–7 above.) | 2–3 weeks | none |
| 2 | Money: tax labels, subscription, installment, multi-currency display; Localize.Unit: dual-unit display; documented compact-number patterns. (Items 8–12.) | 3–4 weeks | Phase 1 |
| 3 | `localize_address` extensions: postcode regex validation, subdivision picker-list builder, form-schema dataset. (Item 13.) | 3–4 weeks | none (parallel-able) |
| 4 | `localize_phonenumber` extensions: country-code chooser bundle, as-you-type formatter. (Item 14.) | 2 weeks | none (parallel-able) |
| 5 | `localize_commerce` umbrella — composite helpers (cart line items, free-shipping thresholds, bulk pricing, installments, loyalty points, pack-of-N, size systems). (Item 15.) | 4–5 weeks | Phases 1, 2 (and ideally 3, 4 for full address-aware checkout helpers) |

Total: ~14–18 weeks of focused work to close the gap to "build any e-commerce site with locale support without rolling your own primitives". Realistic calendar with one maintainer at typical pace: probably one work-quarter per phase, so the full programme is a year if pursued seriously. Address (`localize_address`) and phone (`localize_phonenumber`) sibling libraries are already shipped and substantially exceed what this plan originally proposed — Phase 3 and 4 are now smaller "extension" scopes rather than greenfield builds.

## Change log for this plan

* 2026-05-15 — Initial draft. Pattern catalogue from current public storefront research; gap matrix and phasing proposed; no items implemented yet.
