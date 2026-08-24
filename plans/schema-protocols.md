# Machine-readable output: `Localize.Schema` and `Localize.JsonLd`

**Status:** draft, 2026-08-24

**Owner:** Localize maintainers

**Target:** Localize 1.3 (protocols and core implementations), with `calendrical`, `ex_money` and `localize_web` following

## Why

Localize renders values for people. It has no way to render the same value for a machine, and the measurement work in [research/localization-for-llms.md](../research/localization-for-llms.md) established that this is now a discoverability problem rather than a nicety:

* **No major AI crawler executes JavaScript.** Vercel and MERJ found zero JavaScript execution across more than 500 million GPTBot fetches; the same holds for ClaudeBot, PerplexityBot and others, with Google-Extended the only exception. A value formatted in the browser is not merely mis-formatted for these consumers, it is absent.
* **Retrieval is cross-lingual.** A model reads one language and answers in another, translating the words while copying the *numbers* verbatim. `1,234.56` read from an English page and shown to a German reader states one-point-two.
* **The machine channel is mostly empty.** Of 244 surveyed pages that visibly display a price, **84% publish structured data and 8% publish the price**. Of the sites publishing structured data, the overwhelming majority describe *themselves* — `Organization`, `WebSite`, `ContactPoint` — and not their content. Only 2 of 49 sites publish a machine-readable date.
* **Format is not the obstacle.** Every one of the 19 pages publishing a price used the correct machine format. The barrier is that emitting the second form is a separate, easily-forgotten step.

That last point sets the design goal. This is an **ergonomics** problem, not a correctness one: the machine form has to be as cheap to produce as the human form, from the same call site, or it will keep not being produced.

## Shape

Two protocols in `localize`, mirroring the existing `Localize.Chars`:

```elixir
Localize.Chars.to_string(value, options)    # => {:ok, "1.234,56 €"}    the reader's form
Localize.Schema.to_schema(value, options)   # => {:ok, %{...}}          the vocabulary map
Localize.JsonLd.to_json_ld(value, options)  # => {:ok, %{...}}          a serialisable node
```

Same dispatch, same options, same `{:ok, _} | {:error, Exception.t()}` return, same `@fallback_to_any` treatment. A type that implements `Localize.Chars` can implement these; nothing forces it to.

**One vocabulary — schema.org.** Not JSON Schema, not a neutral intermediate shape. schema.org is what LLM consumers actually read and what the survey measured, and a second vocabulary would double the surface for no demonstrated consumer.

**Two emission formats, because the caller chooses.** `to_schema/2` returns the property map, which serves microdata attributes (`itemprop` / `content`) and HTML `<data>` / `<time>` equally. `to_json_ld/2` returns a node carrying `@context`, ready to encode into `<script type="application/ld+json">`. `JsonLd` derives from `Schema` by default, so an implementer writes one function and gets both; overriding is for types whose linked-data form genuinely differs.

## Type mapping

| Elixir type | schema.org | map |
|---|---|---|
| `Integer` | literal | `%{"value" => 1234567}` |
| `Float` | literal | `%{"value" => 1234567.89}` |
| `Decimal` | literal | `%{"value" => "1234.56"}` |
| `Date` | `Date` | `%{"@type" => "Date", "value" => "2026-03-22"}` |
| `Time` | `Time` | `%{"@type" => "Time", "value" => "14:30:00"}` |
| `DateTime`, `NaiveDateTime` | `DateTime` | `%{"@type" => "DateTime", "value" => "2026-03-22T14:30:00Z"}` |
| `Duration` | `Duration` | `%{"@type" => "Duration", "value" => "P1Y2M3DT4H"}` |
| `Localize.Unit` | `QuantitativeValue` | `%{"@type" => "QuantitativeValue", "value" => 5, "unitText" => "kilometer"}` |
| `Range` | — | see open questions |
| `%Money{}` (ex_money) | `MonetaryAmount` | `%{"@type" => "MonetaryAmount", "value" => "1234.56", "currency" => "EUR"}` |

**Money is always `MonetaryAmount`.** schema.org spells the same data two ways — `price`/`priceCurrency` inside an `Offer`, `value`/`currency` standalone — and a value does not know which context it will be embedded in. `MonetaryAmount` is the standalone form; a caller building an `Offer` remaps two keys.

**Units use `unitText`, not `unitCode`.** schema.org's `unitCode` expects a UN/CEFACT Common Code (`KMT` for kilometre), which CLDR does not carry and which we therefore cannot regenerate from our source data. `unitText` accepts the CLDR unit identifier, which is stable and which we do have. A `:unit_code` option lets a caller supply the UN/CEFACT code where they have it.

## Where implementations live

Each library implements for the types it owns. `localize` defines the protocols; the others depend on it and can `defimpl` without `localize` knowing about them — the pattern `Localize.Chars` already documents with its `MyApp.Money` example.

| library | implements |
|---|---|
| **localize** | `Integer`, `Float`, `Decimal`, `Date`, `Time`, `DateTime`, `NaiveDateTime`, `Duration`, `Localize.Unit`, `Any` fallback |
| **calendrical** | dates in non-ISO calendars — see below |
| **ex_money** | `%Money{}` |
| **localize_web** | consumes both; emits `<data>`, `<time>`, microdata and JSON-LD blocks |

### Why calendrical has to be involved

`Date.to_iso8601/2` documents that it "only supports converting dates which are in the ISO calendar, or other calendars in which the days also start at midnight". Hebrew and Islamic dates start at sunset, so the machine form for those cannot be produced by handing the struct to the stdlib — it needs a calendar conversion first. That is calendrical's competence and nobody else's, which is why the protocol has to be open to it rather than exhaustively implemented in core.

## Known gaps in the source types

Two types have no `String.Chars` implementation today, so `Kernel.to_string/1` raises on them:

* **`Duration`** — but `Duration.to_iso8601/1` yields `"P1Y2M3DT4H"`, which is exactly the machine form and a valid `<time datetime>` value. The implementation calls that.
* **`Localize.Unit`** — and a single string would be the wrong answer anyway, since schema.org wants the value and the unit as separate properties. The struct already carries both (`value: 5`, `name: "kilometer"`, and `"kilometer-per-hour"` for compounds).

Neither needs a `String.Chars` implementation added for this work. Whether `Localize.Unit` should have one for its own sake is a separate question.

## Options

The protocols take the same keyword list as `Localize.Chars.to_string/2`, so a call site can pass one set of options to both:

* `:currency` — as today, promotes a bare number to a monetary amount.
* `:unit_code` — supplies a UN/CEFACT code alongside `unitText`.
* `:context` — the `@context` value for `to_json_ld/2`. Default `"https://schema.org"`.

Locale options are accepted and **ignored** by these protocols. The machine form is locale-independent by definition, and silently accepting `locale:` keeps one option list working for both calls rather than forcing callers to split it.

## Phasing

1. **`Localize.Schema` and `Localize.JsonLd` protocols, plus core implementations.** Self-contained, testable, ships in Localize alone.
2. **`localize_web` helpers.** Pair the human and machine forms at one call site — `<data value="1234567.89">1.234.567,89</data>`, `<time datetime="2026-03-22">22.03.26</time>` — plus a JSON-LD block helper. This is where the ergonomics argument is actually cashed.
3. **`ex_money` implementation.** `%Money{}` → `MonetaryAmount`.
4. **`calendrical` implementation.** Non-ISO calendar dates, converting before emitting.

Steps 3 and 4 are independent of each other and of step 2.

## Testing

* Every core implementation round-trips: the map's `value` parses back to the input, for each type.
* `Decimal` renders without exponent notation for values that would otherwise use it, since a consumer reading `1.0e3` as a price is the failure this exists to prevent.
* The `Any` fallback returns an error rather than a half-populated map, so an unimplemented type is loud.
* `to_json_ld/2` output survives `:json.encode/1` and decodes to the same map.
* Property test: for numeric types, `to_schema/2` output is independent of `:locale`.

## Open questions

1. **`Range`.** Localize renders `1..10` as a localized range string. schema.org has no range literal; the nearest is two properties on an enclosing type (`minValue`/`maxValue` on `QuantitativeValue`). Emit a `QuantitativeValue` with those, or leave `Range` unimplemented and let the caller decide?
2. **Percent and permille.** `Localize.Number.to_string(0.5, format: :percent)` renders `50%`. Is the machine value `0.5` or `50`? schema.org has no percent type; `QuantitativeValue` with `unitText: "PERCENT"` is one reading.
3. **Lists.** `Localize.Chars` implements `List` by recursively formatting elements. The schema equivalent is presumably a plain list of maps, but `ItemList` exists and carries ordering semantics.
4. **Should the `Any` fallback exist at all?** `Localize.Chars` falls back to `Kernel.to_string/1`. There is no equivalent sensible default here, which argues for `@fallback_to_any false` and a `Protocol.UndefinedError` — louder, and arguably right for a protocol whose whole purpose is precision.
