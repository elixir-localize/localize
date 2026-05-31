# Product & clothing sizes in Localize — design plan

## Goal

Add a way to represent, convert, localise, and import **product** information — with **clothing/apparel** (and its sizing) as the first category specialisation. Clothing sizing has many competing regional standards, no single authority, and orthogonal size / colour / style axes; products in general have a globally standardised representation (GS1) that we want to import from.

This document analyses the domain, reviews what `Localize.Unit` gives us to build on, and proposes a **three-layer architecture** (§0): a `Localize.Size` measurement engine, a thin GS1-grounded `Localize.Product` envelope, and a `Localize.Product.Apparel` category module. **It does not implement anything.** Open questions and risks are flagged at the end.

---

## 0. Architecture: product first, clothing as a category

The original draft built clothing sizes directly. Reviewing GS1 changed the shape: GS1 itself models the world as **a general product with category specialisations**, so we mirror that. Three layers, bottom-up:

1. **`Localize.Size`** — the measurement + conversion engine. The genuinely hard, genuinely i18n part: body-measurement-pivoted conversion between regional sizing systems, plural-aware localised formatting. Depends on `Localize.Number`, `Localize.Locale`. *Sections 1–5 below describe this layer.*

2. **`Localize.Product`** — a **thin** GS1-grounded product envelope. Models trade-item *identity* and a layered *attribute bag*, and hosts the import/export adapters. Composes existing Localize subsystems rather than reinventing them: physical measures are `Localize.Unit` values, country-of-origin is `Localize.Territory`, prices are `Localize.Currency`. *Section 0.1–0.2 below.*

3. **`Localize.Product.Apparel`** — the clothing **subject** (category module). Owns the apparel attributes (size, colour, fabric) and wires `Localize.Size` into a `Localize.Product`. *The clothing-specific design in §4 belongs to this layer.*

The discipline that keeps this from ballooning: **`Localize.Product` is an attribute model + adapter layer, not a PIM and not a barcode system.** The GS1 General Specifications is overwhelmingly about identification keys and barcode symbology (SSCC, GLN, AIDC, coupons, assets, EAN/UPC symbols) — **almost all of which is out of Localize's lane.** We adopt only the narrow slice below.

### 0.1 The GS1 identity vocabulary we adopt (and what we ignore)

From the GS1 General Specifications (Release 21, the foundational identification standard), the Product layer adopts exactly these concepts:

* **GTIN (AI 01)** — Global Trade Item Number; identifies a specific sellable item. → `Product.gtin`.
* **GMN (Global Model Number, AI 8013)** — identifies a product *model / family*, distinct from the GTIN of any one sellable variant. This is GS1's native parent/child model: **GMN ≈ the design, GTIN ≈ the specific colour+size SKU.** → `Product.gmn` (the "parent"). This replaces the invented `Variant.parent` from the earlier draft.
* **AI 20 / AI 22 / AI 242** — internal product variant / **consumer product variant** / made-to-order variation. The standard way to express a size/colour variant that shares or specialises a GTIN. → `Product.variant`.
* **Trade measures (AIs 31nn/32nn)** — length, width, height, net weight of the trade item. → expressed as `Localize.Unit` values (this is the `product_measurements` of §4.1).
* **Country of origin (AIs 422/426/427)** — → `Localize.Territory` atoms.
* **Price AIs (39nn)** — → `Localize.Currency` / `Localize.Number`.
* **AI 240/241** — additional/customer product identification → opaque caller strings.

**Explicitly out of scope** (the bulk of the General Specifications): SSCC logistic units, GLN locations/parties, GRAI/GIAI assets, coupons (GCN), GDTI documents, barcode symbology (EAN/UPC/DataMatrix), AIDC validation, symbol placement, healthcare/tobacco regulatory modules. Localize is not a GTIN allocator, not a barcode generator, not a master-data system of record. It *carries* these identifiers when a caller supplies them and *maps* them on import; it does not *issue* or *validate-for-uniqueness* them.

### 0.2 The GS1 attribute layering we mirror

The GS1 **Global Data Model (GDM)** — a separate standard from the General Specifications — defines descriptive product attributes in four layers: **Global Core** (every product) → **Global Category** (e.g. apparel) → **Regional Category** → **Country/Local**. `Localize.Product` mirrors this as an attribute bag keyed by layer, so:

* core attributes (brand, net content, country of origin) live on `Localize.Product`;
* category attributes (size, colour, fabric for apparel) live on the category module (`Localize.Product.Apparel`);
* the import adapters (§4.9) populate whichever layers the source schema expresses.

We do **not** ship the GS1 GDM attribute tables or picklists (they're sold, not freely redistributable — see risk #8). We mirror the *structure* and map against it; the caller brings the GS1 data they hold.

---

## 1. Domain analysis

Clothing sizing is fundamentally unlike units of measure in three ways that shape the whole design.

### 1.1 A "size" is not a scalar

A unit value is one number plus a dimension (`3 meter`). A clothing size is a tuple:

* **garment category** — women's dress, men's shirt (by neck), men's suit (by chest), trousers (waist × inseam), children's (by age or height), footwear, headwear, gloves. Each category measures a *different* body dimension.
* **sizing system** — the regional/national standard the label uses (US, UK, EU-DE/FR/IT, JIS, GB/T, KS, international alpha S/M/L/XL).
* **size value** — the label itself (`10`, `M`, `38`, `13-Y-PP`). Its meaning is only defined *relative to* the system + category.
* **underlying body measurements** — bust/chest, waist, hip, height, neck, inseam, foot length, head circumference, etc. This is the only thing that's actually comparable across systems.

### 1.2 Conversion is lookup-driven, lossy, and approximate

Some systems are formula-derived (`IT womens = bust_cm/2`, `FR = bust_cm/2 − 4`, `DE = bust_cm/2 − 6`; `US womens = bust_in − 28`, `UK = bust_in − 24`), but most cross-system mappings are **tables**, not formulas, and they're approximate. The article's own equivalence tables disagree by a size or two depending on garment. There is no exact `convert(us_10, :eu)`; there's "US 10 maps to the EU size whose body-measurement band overlaps most".

The pivot for conversion is therefore **body measurements**, exactly the way `Localize.Unit` converts everything through a base unit. `size → body measurement band → size` is the clothing analogue of `unit → base unit → unit`. But the round-trip is lossy: `to_eu(to_us(eu_38))` may not be `eu_38`.

### 1.3 No standardisation authority; vanity sizing

Critically — and unlike units, where CLDR is the single source of truth — **there is no clothing-size data in CLDR**, and the published standards (ISO 8559, EN 13402, JIS L 400x, GB/T 1335, KS K 005x) are widely ignored by manufacturers ("vanity sizing"). Two size-10 dresses from the same brand can differ. This has two consequences:

1. Localize can only ship **standard** mappings (what ISO/EN/JIS/GB/KS *say*), clearly labelled as nominal. It cannot promise a real garment matches.
2. Manufacturer-specific size charts must be a **custom-registry** concern (mirroring `Localize.Unit.CustomRegistry`), because that's where the real-world truth lives.

### 1.4 The standards landscape (data sourcing)

From the research, the data we'd encode:

* **ISO 8559-1/-2/-3/-4** (2017–2023) — anthropometric definitions, dimension indicators, body-measurement-table methodology. This is the modern umbrella; defines *how* to express a size in body measurements, not a fixed size table.
* **EN 13402-1..-4** — European, still common for children's wear; -3 gives body measurements and intervals, -4 a coding system.
* **JIS L 4001–4007** — Japan, per garment class (infants/boys/girls/men/women/foundation/hosiery), with height (P/R/T) and fit (Y/A/AB/B) modifiers.
* **GB/T 1335.1/.2/.3** — China men/women/children.
* **KS K 0050/0051/...** — Korea.
* **US**: no mandatory standard; ASTM D5585/D6829/D6240/D6960 voluntary tables.
* Letter sizes (XS–XXXL) map across regions only approximately.

This is a **hand-built dataset**, not an extract from an existing machine-readable source. That is the single biggest cost and risk in the whole feature (see §8).

### 1.5 Footwear is a separate sub-problem

The clothing-sizes article doesn't cover footwear. Shoe sizing (Mondopoint / ISO 9407, US, UK, EU/Paris point, JP) is its own measurement basis (foot length in mm) and its own conversion tables. The design should make footwear *a category within the same framework* (its base measurement is foot length/width in mm), not a special case — but the data is sourced from a different standard (ISO 9407) and would land in a later phase.

---

## 2. What `Localize.Unit` gives us to mirror

`Localize.Unit` is the right template. Its relevant patterns:

* **Minimal struct, rich parse.** `%Localize.Unit{name, parsed, value, usage}` — a canonical name string, an internal parsed AST, the scalar value, and a usage context.
* **Validation gates atom creation.** The parser accepts arbitrary lowercase tokens but base names are validated against a whitelist *before* any `String.to_atom`. This is the atom-DOS hardening we must preserve.
* **Compile-time ETF data layer.** `Localize.Unit.Data` loads one `priv/localize/supplemental_data/unit_data.etf` via `binary_to_term` at compile time; a `Data.Overlay` checks `CustomRegistry` first, then falls back to the bundled data. ETF is generated by a `scripts/extract_*.exs`.
* **Conversion through a base unit.** `Localize.Unit.Conversion` + `Localize.Unit.BaseUnit` decompose to fundamental units, convert via factor/offset, recompose. Special (nonlinear) conversions use `{module, function}` forward/inverse pairs.
* **Locale-aware formatting.** `Localize.Unit.Formatter` resolves plural rules, looks up CLDR patterns per grammatical case/gender, substitutes the formatted number.
* **Preferences by region/usage.** `Localize.Unit.Preference` picks the locale-appropriate unit for a category+usage+territory, with size-based cascades.
* **Custom registry.** `Localize.Unit.CustomRegistry` — persistent_term-backed, regex-validated lowercase names, batch + file loading, `Code.eval_file` gated against `:prod`.

The full module inventory (parser, combinators, helpers, data, overlay, conversion, base_unit, canonical, formatter, preference, custom_registry, math, operators) is the checklist of analogues a `Localize.Size` subsystem might need.

---

## 3. Where the analogy holds — and where it breaks

| Aspect | `Localize.Unit` | `Localize.Size` | Verdict |
|---|---|---|---|
| Core struct | name + parsed + value + usage | system + category + value + measurements | **Holds** (different fields, same shape) |
| Conversion pivot | base unit | body-measurement band | **Holds** (but lossy/approximate, not exact) |
| Data source | CLDR (machine-readable) | hand-built from ISO/EN/JIS/GB/KS | **Breaks** — no upstream; biggest risk |
| Conversion math | exact factor/offset | table lookup + some formulas + interpolation | **Breaks** — ranges, not points |
| Formatting | CLDR plural patterns | localised *display names* of systems/categories; the value is mostly a literal label | **Partially holds** |
| Custom entries | manufacturer rarely needed | manufacturer size charts are the *primary* real-world use | **Inverts** — custom is central, not peripheral |
| Variants (colour/style) | n/a | orthogonal product axes | **New** — not a measurement concern at all |

The two breaks (data source, conversion math) and the inversion (custom is central) are the design's defining constraints.

---

## 4. Proposed design

### 4.1 The `Localize.Size` struct

```elixir
defstruct [
  :system,        # e.g. :us, :uk, :eu_de, :jis, :gb_t, :ks, :intl_alpha
  :category,      # e.g. :womens_dress, :mens_shirt_neck, :mens_suit_chest,
                  #      :trousers, :childrens, :footwear, :headwear, :gloves
  :value,         # the label, scalar OR multi-dimension (see below)
  :size_group,    # :regular | :petite | :tall | :plus | :maternity | :big | :big_and_tall …
                  #   schema.org WearableSizeGroupEnumeration; Amazon height_type/body_type
  :body_measurements,     # %{bust: 91, waist: 79, hip: 104} in cm — the body the garment fits
                          #   (schema.org suggestedMeasurement); the conversion pivot
  :product_measurements,  # %{chest_flat: 52, length: 71} — the garment's own dimensions
                          #   (schema.org hasMeasurement); informational, not the pivot
  :sex,           # :women | :men | :unisex | :children | :infant (schema.org suggestedGender)
  :suggested_age, # %{min: 3, max: 4, unit: :year} for children sized by age; nil otherwise
  :standard       # the source standard, e.g. :iso_8559, :en_13402, :jis_l_4005
]

# A size value is either a single label or a structured multi-dimension
# value. Multi-dimension covers GS1 primary+secondary, men's-shirt
# neck×sleeve, trousers waist×inseam, bra band×cup, and size *ranges*
# (Amazon apparel_size_to / "fits 10–12").
@type value ::
        String.t()
        | number()
        | %{primary: String.t() | number(), secondary: String.t() | number()}
        | %{from: String.t() | number(), to: String.t() | number()}

@type t :: %__MODULE__{
        system: atom(),
        category: atom(),
        value: value(),
        size_group: atom() | nil,
        body_measurements: %{atom() => number()} | nil,
        product_measurements: %{atom() => number()} | nil,
        sex: atom() | nil,
        suggested_age: %{min: number(), max: number(), unit: atom()} | nil,
        standard: atom() | nil
      }
```

`body_measurements` is the analogue of a unit's base-unit representation — the conversion pivot. A size with it populated is "grounded"; a bare label is "ungrounded" and must be grounded via the data tables before conversion. `product_measurements` is informational (the finished-garment dimensions) and never drives conversion; the split mirrors schema.org's `suggestedMeasurement` (body) vs `hasMeasurement` (product), which the Wikipedia research flagged as the "body dimensions vs product dimensions" distinction.

The struct field names are chosen to map cleanly onto `schema.org/SizeSpecification` (see §4.9): `value`↔`name`, `system`↔`sizeSystem`, `size_group`↔`sizeGroup`, `body_measurements`↔`suggestedMeasurement`, `product_measurements`↔`hasMeasurement`, `sex`↔`suggestedGender`, `suggested_age`↔`suggestedAge`.

### 4.2 Systems and categories as closed atom sets

Like unit categories, `system` and `category` are validated against closed sets loaded from the data layer (`Localize.Size.Data.known_systems/0`, `known_categories/0`). Caller-supplied binaries are resolved via `Helpers.existing_atom/1` — never `String.to_atom` — preserving the atom-DOS hardening. (And, per the bug we fixed in 0.33, the size atom collections get eager-interned at app start in `Localize.Supervisor.intern_supplemental_atoms/0`.)

### 4.3 Creation & validation

```elixir
Localize.Size.new(:us, :womens_dress, 10)
Localize.Size.new(:eu_de, :womens_dress, 38, measurements: %{bust: 91})
Localize.Size.new(:intl_alpha, :mens_shirt, "M")
```

Validation pipeline (mirrors Unit):

1. Validate `system` ∈ known systems.
2. Validate `category` ∈ known categories for that system.
3. Validate `value` is a legal label for that (system, category) — e.g. `:us :womens_dress` allows `0,2,4,…`; `:intl_alpha` allows `XXS..XXXL`.
4. If `measurements` supplied, validate keys against the category's measurement schema (bust/waist/hip for dresses; neck for men's shirts; foot_length for footwear).
5. Ground the size: fill `measurements` from the data table if not supplied.

### 4.4 Conversion

```elixir
Localize.Size.convert(size, to_system: :eu_de)         # {:ok, %Size{...}} | {:error, _}
Localize.Size.convert(size, to_system: :uk, strategy: :nearest)
```

Conversion path (the lossy analogue of unit base-unit conversion):

1. Ground the source size → body-measurement band (a range, not a point).
2. Find the target-system size whose band overlaps the source band best.
3. Return it, annotated with a **confidence/approximation marker** — because unlike `Localize.Unit.convert`, the answer is nominal. The struct or the return tuple should carry `approximate: true` and ideally the overlap quality.

A `strategy` option chooses the disambiguation rule (`:nearest`, `:round_up` "size up when between", `:round_down`). Footwear and formula-derived systems (DE/FR/IT) can use the closed-form formula instead of a table when available.

**Explicit non-goal:** exact round-tripping. Document that `convert` is nominal and that real fit depends on the manufacturer.

### 4.5 Formatting / localised display

Two distinct things to localise:

1. **The label itself** is usually rendered verbatim (`"10"`, `"M"`, `"38"`) — but the *system* may need a localised qualifier: "US 10", "EU 38", "Größe 38". CLDR has no clothing data, so these qualifier patterns are a small hand-built set, likely shipped as Gettext msgids (so they translate) rather than CLDR ETF.
2. **System and category display names** — "Women's dress (US)", "Men's shirt (neck)" — localised via Gettext, matching how Localize already handles exception messages (`Localize.Exception.safe_message/3`) and the `Localize.Gettext` backend.

`Localize.Size.to_string/2` produces the rendered label-with-qualifier; `Localize.Size.display_name/2` produces the human category/system name. This mirrors `Localize.Unit.to_string/2` vs `display_name/2`.

### 4.6 Variants (size / colour / style) — now grounded in GS1 GMN/GTIN

This is the part with no `Localize.Unit` analogue, and the layer that **moves up to `Localize.Product`** under the §0 restructure — a variant *is* a product, so it belongs in the product envelope, not hung off a `Size`.

The marketplace driver: **Amazon / Google / any GS1 consumer** treats a sellable product as a model (family) with child variations along a **variation theme** — Size, Color, SizeColor, etc. GS1 already names these two levels: **GMN** (Global Model Number, the family) and **GTIN** (the specific sellable item). We use GS1's terms rather than inventing `parent`:

```elixir
%Localize.Product{
  gmn: "1234567890123",                  # GS1 Global Model Number — the family (AI 8013)
  gtin: "01234567890128",                # GS1 GTIN — this specific item (AI 01)
  variation_theme: [:size, :colour],     # which axes distinguish siblings (Amazon variation_theme)
  variant: %{                            # GS1 consumer product variant (AI 22) values
    size: %Localize.Size{...},
    colour: %{value: "navy", code: "NVY"},
    style: "slim-fit"
  },
  country_of_origin: :VN,                # Localize.Territory (AI 422)
  measures: %{net_weight: Localize.Unit.new!(0.3, "kilogram")},  # AIs 31nn/32nn
  attributes: %{...}                     # GDM core/category/regional/local bag (§0.2)
}
```

Siblings share a `gmn`; each has its own `gtin`. This is the variation matrix, expressed in GS1's own vocabulary, so import from Amazon (parent/child ASIN), Google (`item_group_id`), and GS1/GDSN is a direct mapping.

**Colour is *not* purely free-form.** GS1/NRF publish a standardized colour-code list (the GS1 US Color and Size Codes, ex-NRF), and Amazon/Google carry a `color`/`color_name` field. So Localize offers an **optional** standardized colour-code mapping (`%{value: "navy", code: "NVY"}`) while still accepting a bare free-form string. Localize maps against GS1's codes where the caller supplies them and localises display where CLDR/Gettext colour keywords exist; it does not invent its own colour taxonomy. (This corrects the earlier "colour is opaque" framing.)

**Style remains free-form.** No global style taxonomy is worth importing; `style` stays an opaque caller string Localize can display but not validate.

**Recommendation:** ship `Localize.Size` (the size engine) first and fully. The `Localize.Product` envelope with the GMN/GTIN variation model lands in Phase 3 alongside the import adapters (its primary consumer). Its shape must be fixed before adapters bind to it.

### 4.9 External schema interoperability & import

"Import the data" is a first-class requirement, not a nice-to-have. The adapters live at the **`Localize.Product`** layer (§0) — the source schemas are product schemas first, sizing second. Each maps to a `%Localize.Product{}` (with apparel attributes populated and the size facet built via `Localize.Size`):

* **GS1 / GDSN + General Specifications** — GTIN (AI 01)→`Product.gtin`, GMN (AI 8013)→`Product.gmn`, consumer product variant (AI 22)→`Product.variant`, trade measures (AIs 31nn/32nn)→`Product.measures` as `Localize.Unit` values, country of origin (AI 422)→`Product.country_of_origin`. The **GS1 US Color and Size Codes** give a Primary + Secondary size structure (secondary = waist/neck/rise/cup/petite) → `Size.value.{primary,secondary}`, plus standardized colour codes → `variant.colour.code`. **This is the canonical "global standardized product information schema".**
* **schema.org `Product` + `SizeSpecification`** — `Product` → `Localize.Product`; `SizeSpecification` maps near 1:1 onto the size struct (§4.1): `name`/`sizeSystem`/`sizeGroup`/`suggestedMeasurement`/`hasMeasurement`/`suggestedGender`/`suggestedAge`. JSON-LD on retail pages.
* **Google Merchant / Shopping** — `id`→`Product.gtin`, `item_group_id`→`Product.gmn`, `size`/`size_type`/`size_system`→size facet, `color`/`material`/`pattern`→`variant`.
* **Amazon apparel** — parent ASIN→`Product.gmn`, child ASIN→`Product.gtin`, `variation_theme`→`Product.variation_theme`, `apparel_size_system`/`apparel_size`/`apparel_size_to`/`apparel_size_class`/`apparel_height_type`/`apparel_body_type`→size facet, `color_name`/`style_name`→`variant`.

**Adapter layer.** Each external schema gets a bidirectional adapter so callers can import *and* export:

```elixir
Localize.Product.Import.SchemaOrg.to_product(json_ld_map)    # {:ok, %Product{}} | {:error, _}
Localize.Product.Import.SchemaOrg.from_product(%Product{})   # JSON-LD map
Localize.Product.Import.GS1.to_product(gs1_record)
Localize.Product.Import.GoogleShopping.to_product(feed_row)
Localize.Product.Import.Amazon.to_product(listing_attrs)
```

Adapters are pure mapping functions — no network, no parsing of proprietary file formats beyond what the caller already decoded (the caller hands us a decoded map / row; we map fields). They depend only on `Localize.Size` and `Localize.Size.Variant`. This keeps the proprietary-format knowledge isolated and individually testable, and means new schemas (Shopify, Etsy, …) are additive.

**Round-trip honesty.** Import is exact (external → struct is a field mapping). Export to a *different system than the source* goes through §4.4 conversion and inherits its nominal/approximate nature — `from_size` must carry the `approximate` marker through to the external representation where the schema has somewhere to put it (e.g. schema.org has no confidence field, so the adapter documents the loss).

### 4.7 Data layer

The hard part. Proposed shape, mirroring `Localize.Unit.Data`:

* `priv/localize/supplemental_data/size_data.etf` — bundled, loaded at compile time via `binary_to_term`, **wrapped in a function body** (not a module attribute — per the issue #28 lint we now enforce, `Application.app_dir` must not be frozen into an attribute).
* Generated by `scripts/extract_size_data.exs` from hand-curated source files (YAML/CSV/Elixir) encoding the ISO/EN/JIS/GB/KS tables. There is no upstream to scrape, so these source files are themselves a maintained artefact.
* Structure: `%{ {system, category} => [%{value:, measurements_band: %{bust: {lo, hi}, ...}, modifiers:}] }` plus `formulas: %{ {system, category} => {:formula, fun_ref} }` for the closed-form systems.
* `Localize.Size.Data.Overlay` checks `Localize.Size.CustomRegistry` first (manufacturer charts), then the bundled data — exactly the Unit overlay pattern.

### 4.8 Custom size charts (the central real-world case)

`Localize.Size.CustomRegistry`, modelled on `Localize.Unit.CustomRegistry`:

* persistent_term-backed, regex-validated names, batch + file loading.
* A manufacturer registers a size chart: `{brand, category} => [%{value:, measurements_band:}]`.
* `convert/2` consults the registry first, so "Acme US 10" can map to "Acme EU 38" using Acme's *own* bands rather than the nominal standard.
* Same `Code.eval_file` safety gate as units (`:prod` requires an explicit allow flag).

This inverts the Unit priority: for units, custom registration is a rare convenience; for sizes, it's how you get correct answers, because the standards are nominal.

---

## 5. Module inventory (parallel to `Localize.Unit`)

| Proposed file | Responsibility | Unit analogue |
|---|---|---|
| `lib/localize/size.ex` | Struct, `new/3`, `convert/2`, `to_string/2`, `display_name/2`, introspection | `unit.ex` |
| `lib/localize/size/data.ex` | Compile-time ETF loader; systems, categories, bands, formulas | `unit/data.ex` |
| `lib/localize/size/data/overlay.ex` | Custom-registry-first lookup | `unit/data/overlay.ex` |
| `lib/localize/size/conversion.ex` | Band-overlap conversion + formula systems + strategy | `unit/conversion.ex` |
| `lib/localize/size/measurements.ex` | Body-measurement schema per category; grounding logic | `unit/base_unit.ex` |
| `lib/localize/size/formatter.ex` | Localised label + qualifier rendering | `unit/formatter.ex` |
| `lib/localize/size/preference.ex` | System preferred for a territory (US→US sizing, DE→EU-DE) | `unit/preference.ex` |
| `lib/localize/size/custom_registry.ex` | Manufacturer size charts | `unit/custom_registry.ex` |
| **Product layer (`Localize.Product`)** | | |
| `lib/localize/product.ex` | Struct (gtin, gmn, variation_theme, variant, country_of_origin, measures, attributes), GDM-layered attribute bag | (none) |
| `lib/localize/product/apparel.ex` | Apparel category module — size/colour/fabric attrs; wires `Localize.Size` into a `Product` | (none) |
| `lib/localize/product/import/schema_org.ex` | schema.org `Product`/`SizeSpecification` JSON-LD ↔ `%Product{}` | (none) |
| `lib/localize/product/import/gs1.ex` | GS1 GTIN/GMN/AI-22 + Color & Size Codes ↔ `%Product{}` | (none) |
| `lib/localize/product/import/google_shopping.ex` | Merchant feed row ↔ `%Product{}` | (none) |
| `lib/localize/product/import/amazon.ex` | Amazon apparel attrs ↔ `%Product{}` | (none) |
| `lib/localize/exception/unknown_size_error.ex` etc. | Structured errors w/ `reason_atoms/0` | existing exception pattern |
| `scripts/extract_size_data.exs` | Build the size ETF from curated standard tables | `scripts/extract_unit_data.exs` |

No `parser`/`combinators` analogue is needed initially — size values are simple labels, not compound grammar like `meter-per-second`. (Japanese composite labels like `13-Y-PP` can be handled by a small per-system splitter rather than a NimbleParsec grammar.)

The import adapters are pure field-mapping modules at the Product layer with no shared logic beyond the struct, so they're cheap to add incrementally and individually testable. They're the concrete answer to "can we import the data" — one module per external schema, each producing a `%Localize.Product{}`.

---

## 6. MCP server follow-on

Once `Localize.Size` lands, the `localize_mcp` server gets it almost for free: the `localize_atoms` tool grows `sizing_systems` and `garment_categories` collections, `localize_search`/`browse` pick up the `Localize.Size.*` modules via the existing index, and a `convert_size` / `size` capability is added to `localize_examples`. Worth noting so the size data is shaped to be introspectable from day one.

---

## 7. Phasing

* **Phase 1 — core size axis, alpha + one numeric system.** Full struct (incl. `size_group`, split body/product measurements, multi-dimension value), validation, `intl_alpha` + `us`/`eu_de` women's-dress and men's-shirt categories, grounding, nominal conversion with `:nearest`. Hand-built data for just these. Proves the shape end-to-end. **The struct must be complete in Phase 1** even though most fields are exercised later — the import adapters and `Variant` depend on its shape, and changing a struct after adapters exist is expensive.
* **Phase 2 — more systems + categories.** UK, FR, IT, JIS, GB/T, KS; trousers (waist×inseam, via the multi-dimension value); children's (age/height, via `suggested_age`). Formula-derived systems use closed forms.
* **Phase 3 — import adapters.** `schema.org` and GS1 first (the two "standardized" schemas), then Google Shopping and Amazon (the two marketplace feeds). Bidirectional. This is where "import the data" is delivered; pulling it earlier than Phase 3 risks designing adapters against an unstable struct.
* **Phase 4 — footwear.** ISO 9407 / Mondopoint + US/UK/EU/JP shoe tables as a category; foot-length-mm base.
* **Phase 5 — custom registry + manufacturer charts.** The real-world correctness layer.
* **Phase 6 — variants + localised display + MCP integration.** `Localize.Size.Variant` (variation theme, parent/child, GS1 colour codes), Gettext display names, MCP tools.

Each phase is independently shippable; Phase 1 is the riskiest because it sets the struct + conversion contract that everything downstream — especially the import adapters — binds to.

---

## 8. Open questions & risks

1. **Data sourcing is the whole ballgame.** There is no CLDR-equivalent machine-readable clothing-size dataset. Every band in `size_data.etf` is hand-transcribed from a standard (many of which are paywalled ISO/JIS/GB documents). Who curates and maintains this, and against which edition? This dwarfs the code cost. *Recommendation: start with the freely-documented tables (the Wikipedia equivalence tables, EN 13402-3 children's, JIS public summaries) and treat the dataset as a living, versioned artefact with its own provenance notes.*
2. **Nominal vs. real.** Conversion answers are approximate and vanity sizing makes them unreliable. The API must signal this everywhere (an `approximate: true` marker, doc warnings). Risk: users treat `convert` as authoritative and ship wrong size charts.
3. **Licensing of standards.** ISO/JIS/GB/KS tables may be copyright-encumbered. Transcribing numeric bands is likely fine (facts aren't copyrightable) but the *structure* and any prose must be original. Needs a legal sanity check before shipping the dataset.
4. **Scope of "variant".** Is colour/style genuinely in scope for an i18n library, or is it product-modelling that belongs in the caller's domain? *Recommendation: ship the size axis; provide `Variant` with the variation-theme / parent-child shape that marketplace imports need, map colour against GS1 codes when supplied, and explicitly disclaim **style** standardisation (no global taxonomy exists). Note colour is **not** fully free-form — GS1/NRF colour codes are importable.*

7. **Interop is a stated requirement, and it constrains the struct.** "Import the data" from GS1 / schema.org / Google / Amazon means the struct must carry every field those schemas express — `size_group`, body-vs-product measurements, multi-dimension values, suggested age/gender — or import is lossy from day one. This is why §4.1 was revised to map field-for-field onto `schema.org/SizeSpecification`. *Risk: under-modelling the struct in Phase 1 forces a breaking change once adapters exist. Mitigation: lock the struct shape in Phase 1, even though most fields aren't exercised until Phase 2–3.*

8. **Which GS1 dataset, and its licence.** The GS1 US Color and Size Codes are sold as an Excel file through the GS1 US store / contracted partners — i.e. **not freely redistributable**. We can map *against* GS1 code semantics (the field structure) without shipping their table, but we cannot bundle their colour/size code list. The importer must accept GS1 records the caller already holds, not ship the GS1 tables. *This is a sharper version of risk #3 and applies specifically to GS1.*
5. **Where does this live?** Given the three-layer structure (§0): `Localize.Size` could go in core `:localize` (it's pure-CLDR-adjacent measurement logic, like `Localize.Unit`), but its hand-built, separately-licensed standards dataset argues for keeping it out. *Recommendation: a separate package — provisionally `localize_product` — containing all three layers (`Size`, `Product`, `Product.Apparel`) and depending on `:localize`. This mirrors the `localize_mcp` / `calendrical` / `localize_web` split and keeps the heavyweight standards data and GS1-mapping code out of core.*
6. **Children's sizing by age/weight.** Some systems size infants by age or weight, not body measurement. The `body_measurements` pivot doesn't apply cleanly; `suggested_age` / weight become alternative grounding keys. Handle as a category-specific grounding strategy.
9. **Scope creep into a PIM.** The single biggest risk of the product-first pivot: `Localize.Product` must stay a thin attribute-model + adapter layer. The GS1 General Specifications is 500+ pages of identification keys and barcodes; the GDM is hundreds of attributes. If `Product` starts issuing GTINs, generating barcodes, or becoming a master-data system of record, the feature has lost its way. *Mitigation: the §0.1 allow-list of adopted GS1 concepts is exhaustive; anything not on it is explicitly out of scope.*

---

## Recommendation

Build a **separate `localize_product` package** (risk #5) housing the three layers from §0, depending on `:localize`. Sequence:

1. **`Localize.Size` first and fully** — the measurement engine is the hard i18n core and the part with the most Localize-specific value. Phase 1 validates the struct + lossy-conversion contract on a minimal data set (alpha + US + EU-DE, women's dress + men's shirt).
2. **`Localize.Product` as a thin GS1-grounded envelope** — adopt only the §0.1 identity vocabulary (GTIN, GMN, AI-22 variant, trade measures, country of origin) and the §0.2 GDM attribute layering. Compose `Localize.Unit` / `Territory` / `Currency`; don't reinvent them.
3. **Import adapters at the Product layer** (Phase 3) — schema.org and GS1 first, then Google and Amazon. This delivers "import the data".
4. **`Localize.Product.Apparel`** ties Size into Product as the first category subject; footwear, custom charts, and localised display follow.

Three things now load-bearing that the original clothing-only draft missed:

* **Product-first mirrors GS1's own model** (general product → category specialisation), so imports are structural mappings, not improvisation.
* **GMN/GTIN is GS1's native parent/child variation model** — adopted directly instead of an invented `parent` field.
* **The struct/envelope shape is fixed before adapters bind to it**, and maps field-for-field onto schema.org and the adopted GS1 AIs.

The hard discipline (risk #9): `Localize.Product` is an attribute model + adapter layer, **not** a PIM or barcode system. The `Localize.Unit` architecture remains a sound template for the `Size` engine — except for the data source and conversion exactness, which must be loud in the API.
