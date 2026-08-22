# How the web handles locale: a measurement

**Measured 2026-08-22.** Two studies against the same target population of global brands, from twenty vantage points on five continents.

* **Negotiation** — does a site adapt to the locale a user asks for? 54 sites, 15 `Accept-Language` variants, 20 vantages, **16,200 observations**.
* **Correctness** — where a site publishes a locale-specific variant of itself, is that variant actually correct for the locale it claims? 26 sites declaring **2,317 locale variants**, of which 2,213 were audited.

Every figure comes from a query in `LocalizeResearchProbe.Analysis` or from the audit comparison, not from a spreadsheet. The companion document [accept-language-honouring.md](accept-language-honouring.md) surveys what has been *claimed* about `Accept-Language`; this one measures it.

## Summary

**The web routes on IP, not on the header the user controls — and where it does localize, roughly a quarter of the result is wrong.**

Negotiation, across the 35 commercial sites that could be judged:

* **11.4%** (4 sites) vary their response on `Accept-Language` at all.
* **45.7%** (16 sites) vary on the vantage's IP geolocation — four times as many.
* **16 of 35 do neither**, serving the same page to every language and every continent.
* **Zero** declare `Vary: Accept-Language`. The only three sites in the study that declare it are controls.

Correctness, across the variants those sites publish for themselves:

* **24.0%** of judged variants do not format numbers correctly for the locale they claim — 13.2% wrong outright, 10.7% carrying both correct and incorrect formatting on the same page.
* **23.7%** of variants declared for right-to-left locales do not set the `dir` attribute.
* **3.2%** serve an `html lang` that contradicts the locale they were declared as.
* **136 variants — 6% of everything discovered — redirect out of their own declared path**, so the URL a site publishes as its Catalan or Acholi page lands somewhere else entirely.

The single clearest illustration of the negotiation result is PayPal. Holding the header constant at "no preference" and varying only the vantage:

| Vantage | Landing URL |
|---|---|
| `us-east-1` | `https://www.paypal.com/us/home` |
| `eu-central-1` | `https://www.paypal.com/de/home` |
| `ap-northeast-1` | `https://www.paypal.com/jp/home` |
| `sa-east-1` | `https://www.paypal.com/br/home` |
| `mx-central-1` | `https://www.paypal.com/mx/home` |

Flawless IP-based routing. PayPal is not among the sites that honour `Accept-Language` — the header a user can set is ignored, and the one they cannot control decides what they see.

The most direct demonstration is what comes back when the header is unambiguous. Requesting `zh-CN` from twenty vantages, the `html lang` values returned across sites include `de-DE`, `pt-BR`, `ja`, `fr`, `es-MX`, `ko-KR`, `sv`, `en-ZA` and `en-SG`. Exactly **two** sites returned `zh-CN`. Ask for Chinese from Frankfurt and get German, from São Paulo and get Portuguese, from Tokyo and get Japanese.

## Part 1 — Negotiation

### Honouring the header is rare and concentrated

Four commercial sites of 35 judged, three of them media companies: `spotify.com` and `youtube.com` (20 of 20 vantages), `agoda.com` (20 of 20), `netflix.com` (13 of 20).

By sector, of sites judgeable: media 3/5, travel 1/2, and **zero** from airlines (0/2), electronics (0/6), finance (0/5), mobility (0/3), public bodies (0/4), retail (0/4) and software (0/4).

Netflix is a partial case worth naming: it varies for Spanish, redirecting to `/us-es/`, and returns `lang="en"` for every other language including German, French, Japanese and Chinese. It counts as honouring under the definition but honours exactly one language.

`spotify.com` is the one commercial site that does the whole job. It returns `es-419` for `es-MX`, `fr-CA` for `fr-CA`, `zh-CN` for `zh-CN` and `ar-EG` for `ar-EG` — correct regional-subtag handling that almost nobody else manages, matching the controls.

### Geolocation is the dominant strategy

Sixteen commercial sites of 35, and where it happens it is near-total: almost every one varies on 15 of 15 header variants, meaning the vantage decides the response no matter what the user asks for.

`aircanada.com`, `dell.com`, `disneyplus.com`, `hp.com`, `ibm.com`, `lenovo.com`, `lg.com`, `mastercard.com`, `netflix.com`, `nike.com`, `paypal.com`, `salesforce.com`, `samsung.com`, `singaporeair.com`, `uniqlo.com`, `visa.com`.

Only `netflix.com` appears in both lists. Of the 38 judgeable sites, 15 geolocate and ignore the header, 4 honour the header and do not geolocate, 1 does both, and 18 do neither.

### Vary is absent from the commercial web entirely

Three sites declare `Vary: Accept-Language`: `debian.org`, `mozilla.org` and `torproject.org`. All three are controls. **No commercial site declares it**, including the four that vary on the header.

This is a correctness bug rather than a preference. A shared cache in front of such a site is entitled to serve the first language it saw to everyone who follows.

### A fifth of the web will not talk to a datacentre

Of 16,200 observations, 68.1% succeeded, **22.4% were blocked**, 7.6% errored and 1.9% returned a non-200 status. Ten sites were blocked in all 20 regions — `expedia.com` (429), `hm.com`, `lufthansa.com`, `marriott.com`, `oracle.com`, `sony.com`, `zara.com`, `adidas.com` (403), `hertz.com` (an Incapsula challenge) and `airbnb.com` (an interstitial too small to be a home page). The blocking is keyed on the ASN, not the country: identical in Frankfurt, Virginia and Mexico City.

### Measuring changes what can be measured

The ten blocked sites were re-swept from a residential connection using the same collector. `zara.com` answered all 15 variants there while returning 403 to every AWS region, confirming ASN-keyed blocking. But nine were blocked from the residential connection too — including `hertz.com`, which had served HTTP 200 from **the same IP address earlier the same day**.

Between those two measurements the only thing that changed was that the address had been used to probe those sites. Bot defences adapted within hours, and a residential vantage is a depleting resource rather than a stable one. A VPN-based fallback would degrade faster, not slower: a shared commercial exit is probed continuously by many users. The blocked fifth cannot be recovered by changing where the probe runs from.

## Part 2 — Correctness

Part 1 measures a mechanism, not a capability. A site that serves `paypal.com/de/home` to a German address **is** localized, and well; it simply does not consult the header. Conflating the two would be a category error, and the "adapts to neither" group makes that vivid — it contains Apple, IKEA, Microsoft, SAP, the European Union, the UN and the WHO, all of which publish extensively localized sites behind a country selector rather than negotiating on a landing page.

So the second study asks a different question, and takes the sites' own claims as ground truth:

> **You declare that you support `de-AT`, `ja-JP` and `ar-EG`. Do those pages actually format like `de-AT`, `ja-JP` and `ar-EG`?**

This has three advantages over inferring anything from negotiation. There is no negotiation confound, since each URL is fetched on its own terms with no `Accept-Language` at all. There is no dependence on the blocked fifth, since we fetch the URLs the sites advertise. And the ground truth is self-declared rather than assumed.

### What the sites declare

Sites publish their locale variants in `<link rel="alternate" hreflang>` and in sitemaps. Discovery reads both, and follows one level of same-host links, because most large brands declare nothing on their landing page — PayPal, Samsung, YouTube, Netflix, Nike and Microsoft all declare zero in-page and hundreds in their sitemaps.

**26 sites declare 2,317 locale variants across 825 distinct locale tags.**

| Site | Variants declared | | Site | Variants declared |
|---|---|---|---|---|
| `paypal.com` | 274 | | `youtube.com` | 110 |
| `mastercard.com` | 216 | | `europcar.com` | 101 |
| `samsung.com` | 171 | | `airbnb.com` | 96 |
| `apple.com` | 140 | | `lenovo.com` | 95 |
| `singaporeair.com` | 131 | | `netflix.com` | 79 |
| `visa.com` | 125 | | `salesforce.com` | 65 |
| `ikea.com` | 116 | | `nike.com` | 64 |

Twenty-eight sites declare nothing. Eleven of those are blocked and five error, so the ceiling on this study is the same datacentre blocking measured in Part 1, not the discovery method. Only twelve genuinely publish no `hreflang` anywhere.

### The tags themselves are almost always right

All 825 declared tags were validated through `Localize.validate_locale/1`. **99.2% resolve.** Tag correctness is not the story, but the exceptions are specific and real:

* **`europcar.com`** declares `ar-DB`, `en-DB` and `sq-KS`. `DB` and `KS` are not region codes — Dubai is within `AE`, Kosovo is `XK`.
* **`ikea.com`** declares `es-SP` and `es-CE`. Spain is `ES`; Ceuta is `EA`.
* **`avis.com`** declares `tc`, apparently meaning Traditional Chinese, which is `zh-Hant`.
* **`videolan.org`** uses underscores throughout — `es_MX`, `zh_CN`, `pt_BR` and nine more. Invalid BCP 47; a strict parser rejects all twelve.

### One in sixteen declared variants does not lead where it claims

**136 of 2,213 audited variants — 6% — redirect out of their own declared path.** `mozilla.org/ca/products/vpn/` lands on `/en-US/products/vpn/`. A site publishes `hreflang="ca"` and the URL behind it serves English.

This is a defect in its own right, and it is also a methodological trap: auditing the page such a URL lands on would blame Catalan for English formatting. All 136 are excluded from every verdict below and reported here instead.

### The `lang` attribute contradicts the declaration in 3.2%

57 of 1,764 judged variants. Both sides are canonicalized before comparing, so a site declaring `no-no` and serving `nb-no` counts as correct — it has applied CLDR's own canonicalization and is more correct than its declaration.

| Site | Mismatched | Example |
|---|---|---|
| `aircanada.com` | 22 of 48 | declared `de-ch`, serves `lang="en"` |
| `apple.com` | 11 of 139 | declared `en-AM`, serves **no `lang` attribute at all** |
| `paypal.com` | 9 of 273 | declared `en-gf`, serves `lang="fr-GF"` |
| `youtube.com` | 6 of 107 | declared `ar`, serves `lang="en"` |
| `samsung.com` | 5 of 170 | declared `en-ID`, serves `lang="id-ID"` |
| `disneyplus.com` | 1 of 31 | declared `it`, serves `lang="eng"` — not a valid tag |

Samsung also serves `lang="az_AZ"` on its Azerbaijani site — an underscore where BCP 47 requires a hyphen.

### Right-to-left: 23.7% of RTL variants set no direction

Of 97 variants declared for right-to-left locales, **23 set no `dir` attribute**. `samsung.com` accounts for 19 of them — every Arabic variant it publishes.

This was checked by hand rather than trusted, because `dir` on `<html>` is not the only way to get the behaviour:

* `samsung.com/ae_ar/` carries **5,442 Arabic characters**, a bare `<body>`, no `dir` attribute anywhere in the document, and no inline `direction: rtl`.
* `who.int/ar` carries 3,025 Arabic characters and `<body class="sf-body right-to-left">` — direction by CSS class.

So the accurate claim is not that these pages render mirrored. It is that they set direction through styling rather than the `dir` attribute, which still renders but forfeits bidi isolation, the `:dir()` selector and assistive-technology semantics.

### Number formatting: 24% of declared variants are not correct

The headline correctness result, and the one closest to what a localization library exists to get right.

Numbers are extracted from each variant's **visible text only** — markup and script bodies removed — and only where a number is adjacent to a currency marker, which is the strongest available evidence that the value is locale-formatted rather than a date, a version string or a rating. Each page contributes the **set** of conventions it demonstrates, not a single verdict, and each observed number is compared only on the properties it actually shows: a price of `21,99` establishes a decimal separator and says nothing about grouping.

**242 variants judged:**

| Verdict | Count | Share |
|---|---|---|
| correct | 184 | **76.0%** |
| mixed — both correct and incorrect formatting on one page | 26 | **10.7%** |
| wrong | 32 | **13.2%** |

By site, worst first:

| Site | Not correct | Detail |
|---|---|---|
| `lenovo.com` | 17 of 26 | 14 wrong. Serves `kr299.99` on its Danish site, where Danish takes a comma decimal |
| `disneyplus.com` | 19 of 29 | 18 **mixed** — `21,99 $` and `$4.99` side by side on one page |
| `paypal.com` | 6 of 16 | |
| `europcar.com` | 4 of 14 | `€0.30` on `de-DE`, where German takes a comma decimal |
| `singaporeair.com` | 3 of 3 | |
| `airbnb.com` | 2 of 6 | `$1,209,630` on `es-CL` and `es-CO`, which group with dots |
| `apple.com` | 0 of 21 | |
| `nike.com` | 0 of 8 | |
| `mozilla.org` | 1 of 49 | |

Two results deserve emphasis for opposite reasons. **Apple is clean across 21 audited variants**, including its French site, which groups with U+00A0 — see the note on CLDR skew below. And **Disney+'s failures are overwhelmingly `mixed` rather than wrong**: the pages are not formatted for the wrong locale, they are formatted for two locales at once.

### CLDR version skew is not an error

CLDR changed French grouping to U+202F NARROW NO-BREAK SPACE, and has revised that choice more than once — the pinned CLDR checkout carries `CLDR-16210 "Revert some changes involving NNBS U+202F"` and `CLDR-17233 "fix 0020+202F in fr.xml"`. A site grouping French with U+00A0 is therefore tracking an older ICU, not making an error.

`apple.com/fr/` serves `634 574 115 €` with U+00A0. Members of the space family are normalised against each other before comparison, so this scores **correct**. Counting it as a defect would blame sites for a moving target.

## Method

### Vantages

AWS Lambda in every region the account can use — 21 requested, 20 reached. Each region is invoked asynchronously and writes its own result to S3, so a sweep costs one region's wall-clock rather than twenty-one. The audit shards its work list across regions round-robin, which spreads each host's load over twenty addresses as well as parallelising it.

### The two negotiation definitions

* A site **honours Accept-Language** if, holding the vantage fixed, its successful responses differ across header variants.
* A site **geolocates** if, holding the header variant fixed, its successful responses differ across vantages.

Difference is measured on `html lang`, `Content-Language` and the final URL together. Body hash is deliberately excluded: fifteen sequential requests to one host differ in CSRF tokens and timestamps, so a hash comparison would report that every site varies on everything. Both definitions exclude blocked and errored observations and require at least two usable observations. A site that could not be measured is excluded, never counted as a failure.

### Controls

Four controls were verified by hand before the run, chosen to honour the header, to answer quickly enough to survive fifteen sequential requests, and not to be bot-defended.

| Control | Honours | Declares `Vary` | Role |
|---|---|---|---|
| `debian.org` | 20/20 vantages | yes | `lang` and `Content-Language` both track the request |
| `mozilla.org` | 20/20 | yes | returns `es-MX` for `es-MX` — regional subtag preserved |
| `torproject.org` | 20/20 | yes | |
| `videolan.org` | 20/20 | **no** | exercises the `Vary`-omission detector |

All four are detected as honouring, which is the evidence that the detector works. **Controls are excluded from every headline rate** — they were selected *because* they honour, and including them would raise the negotiation rate from 11.4% to 20.5% as an artifact of target selection.

Controls served a second time in the correctness study, as a check on the number classifier: an early version scored `mozilla.org` at 13 wrong, which turned out to be the audit following links out of the declared locale. After the fix it scores 1 of 49. A control failing was the signal that the method was broken, not the sites.

### Number classification

Only the visible text is scanned; `<script>` and `<style>` bodies and all markup are removed first. JSON-LD is deliberately **not** read even though it would triple recall, because machine-format prices are always dot-decimal and counting them would manufacture a large false error rate.

Group sizes are reported as CLDR names them, so Indian grouping is recognised rather than misparsed: `12,34,567.89` is `sizes=3-2`, `1,234,567.89` is `sizes=3-3`. Samples that cannot settle a role are discarded rather than guessed — `1,234` is a thousand in one convention and one-point-two-three-four in another. Group sizes no locale uses are rejected outright, which is what separates a version string like `2.104.2` from a number.

The expectation for each locale is produced by formatting `1234567.89` with Localize and parsing the result with the same logic applied to the page, so both sides of the comparison are constructed identically.

## Limitations

Stated plainly, because the denominator is the part of a study like this most easily fudged.

* **The blocked fifth is not missing at random.** Sites behind Cloudflare, Akamai and Incapsula are systematically excluded from both studies, and they are plausibly the sites with the largest localization budgets. This biases the negotiation rate upward, so 11.4% is a ceiling. The residential re-sweep establishes that the exclusion cannot be cheaply removed.
* **242 of 2,213 audited variants carry a judgeable number.** Prices are client-side rendered on many sites — IKEA's category pages carry a single `€` in their HTML — and precision was chosen over recall deliberately after two earlier attempts produced inflated rates from dates and version strings. The denominator is small; every member of it is verifiable.
* **Short prices are ambiguous and excluded.** `199,800` could be two hundred thousand or one hundred and ninety-nine point eight. This disproportionately excludes JPY and KRW, which have no minor units and therefore price almost entirely in this form.
* **Landing pages and one level below.** A site may format correctly deeper in a checkout flow than on the pages audited.
* **Twenty-two commercial brands.** Enough to support a claim about the brands that publish the most locale variants; not enough for a prevalence claim about the web at large.
* **No Cyrillic, Hebrew, Thai or Chinese vantage.** AWS has no region in Russia or Poland, and five requested opt-in regions could not be enabled. `ru-RU`, `pl-PL`, `he-IL` and `th-TH` were tested on the header axis only.
* **One measurement, one day.** Runs are keyed and additive, so drift is measurable, but nothing here establishes a trend.

## What this means for a localization library

* **The server usually does not know the user's locale.** If 11.4% of commercial sites consult `Accept-Language` and 46% route on IP, the locale arriving at the application layer is usually absent or wrong. Making locale resolution explicit, overridable and inspectable matters more than making it automatic.
* **Getting the tag right is not getting the locale right.** These brands resolve 99.2% of their locale identifiers correctly and still misformat a quarter of the variants those identifiers name. Tag validation is table stakes; formatting is the work.
* **Regional subtags need first-class handling precisely because the web discards them.** `es-MX` and `fr-CA` differ from `es-ES` and `fr-FR` in separator, grouping character and date order. This is a resolution question, not an inheritance one: TR35's inheritance chain governs which *data* a missing item falls back to, and is orthogonal to preserving the requested tag's identity.
* **`Vary: Accept-Language` should be emitted by anything that negotiates on the header.** No commercial site in this study emits it, and its absence corrupts every shared cache in front of the application.
* **`dir` is not optional and should not be left to the caller.** Nearly a quarter of declared RTL variants omit it, including every Arabic page one of the world's largest electronics brands publishes.

## Reproducing

The harness is the sibling application `localize_research_probe`.

```bash
mix run -e 'LocalizeResearchProbe.Env.load(); LocalizeResearchProbe.Run.sweep()'
```

```bash
mix run -e 'LocalizeResearchProbe.Env.load(); LocalizeResearchProbe.Run.discover()'
```

```bash
mix run -e 'LocalizeResearchProbe.Env.load(); LocalizeResearchProbe.Run.audit()'
```

Each provisions a Lambda in every usable AWS region, invokes them concurrently, collects results from S3 and writes them to `priv/runs.db`. A sweep takes about four minutes; the Lambda usage sits inside the always-free tier by roughly two orders of magnitude.

The runs behind this document are `20260822012602` (negotiation), `discover-20260822023833` (declaration) and `audit-20260822031348` (correctness), with `residential-blocked-20260822` holding the residential re-sweep. Runs are keyed and additive, so a later run can be compared against them rather than replacing them.
