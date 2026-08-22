# Does the web honour Accept-Language? A measurement

**Measured 2026-08-22.** 54 sites, 15 header variants, 20 vantage points on five continents, 16,200 observations. Every figure below comes from a query in `LocalizeResearchProbe.Analysis` against the run database, not from a spreadsheet.

The companion document [accept-language-honouring.md](accept-language-honouring.md) surveys what has been *claimed* about `Accept-Language`. This one measures it.

## Summary

The web does not route on `Accept-Language`. It routes on IP address.

Of the 35 commercial sites that could be judged:

* **11.4%** (4 sites) vary their response on `Accept-Language` at all.
* **45.7%** (16 sites) vary on the vantage's IP geolocation — **four times as many**.
* 15 geolocate and ignore the header, 3 honour the header and do not geolocate, 1 does both, and **16 do neither** — serving the same page to every language and every continent.
* **Zero** declare `Vary: Accept-Language`. The only three sites in the study that declare it are controls.
* **0 of 21** vary their *number formatting* on the header, while 7 of 17 vary it on the IP.
* **3 of 36** set `dir="rtl"` when asked for Arabic or Hebrew.
* **3 of 38** distinguish `es-ES` from `es-MX`, and the same 3 distinguish `fr-FR` from `fr-CA`. Regional subtags are, in practice, discarded.

The single clearest illustration is PayPal. Holding the header constant at "no preference" and varying only the vantage:

| Vantage | Landing URL |
|---|---|
| `us-east-1` | `https://www.paypal.com/us/home` |
| `eu-central-1` | `https://www.paypal.com/de/home` |
| `ap-northeast-1` | `https://www.paypal.com/jp/home` |
| `sa-east-1` | `https://www.paypal.com/br/home` |
| `mx-central-1` | `https://www.paypal.com/mx/home` |

Flawless IP-based routing. PayPal is not among the sites that honour `Accept-Language` — the header a user can actually set is ignored, and the one they cannot control decides what they see.

The most direct demonstration is what comes back when the header is unambiguous. Requesting `zh-CN` from twenty vantages, the `html lang` values returned across sites include `de-DE`, `pt-BR`, `pt`, `ja`, `fr`, `es-MX`, `ko-KR`, `sv`, `en-ZA`, `en-IN` and `en-SG`. Exactly **two** sites returned `zh-CN`. The language served tracks the vantage, not the request: ask for Chinese from Frankfurt and get German, from São Paulo and get Portuguese, from Tokyo and get Japanese.

## Method

A probe fetches the landing page of each target once per header variant, from each vantage, and records the status, the `html` element's `lang` and `dir`, the `Content-Language`, `Vary` and `Server` headers, the final URL after redirects, the body length and a body hash.

**Vantages.** AWS Lambda in every region the account can use — 21 requested, 20 reached. Each region invokes asynchronously and writes its own result to S3, so a sweep costs one region's wall-clock rather than twenty-one.

**Header variants.** Fifteen, each carrying a regional subtag because the sharper question is whether a site distinguishes `es-ES` from `es-MX` rather than whether it knows Spanish: no header, `en-US`, `de-DE`, `fr-FR`, `fr-CA`, `es-ES`, `es-MX`, `pl-PL`, `zh-CN`, `ko-KR`, `ru-RU`, `ja-JP`, `ar-EG`, `he-IL`, `th-TH`. The q-values follow what a browser actually sends.

**Targets.** 50 commercial sites stratified by sector — airlines, travel, retail, electronics, software, media, finance, mobility, public bodies — plus 4 controls.

### The two definitions

* A site **honours Accept-Language** if, holding the vantage fixed, its successful responses differ across header variants.
* A site **geolocates** if, holding the header variant fixed, its successful responses differ across vantages.

Difference is measured on `html lang`, `Content-Language` and the final URL together. Body hash is deliberately *excluded*: fifteen sequential requests to one host will differ in CSRF tokens and timestamps, so a hash comparison would report that every site varies on everything.

Both definitions exclude blocked and errored observations, and both require at least two usable observations before a site is judged. A site that could not be measured is excluded, never counted as a failure.

### Controls, and why they are reported separately

Four controls were verified by hand before the run — chosen to honour the header, to answer quickly enough to survive fifteen sequential requests, and not to be bot-defended.

| Control | Honours | Declares `Vary` | Note |
|---|---|---|---|
| `debian.org` | yes, 20/20 vantages | yes | `lang` and `Content-Language` both track the request |
| `mozilla.org` | yes, 20/20 | yes | returns `es-MX` for `es-MX` — regional subtag preserved |
| `torproject.org` | yes, 20/20 | yes | |
| `videolan.org` | yes, 20/20 | **no** | exercises the `Vary`-omission detector |

All four are detected as honouring, which is the evidence that the detector works. `videolan.org` was included specifically because it honours the header and omits `Vary`, so the omission check is exercised rather than assumed.

**Controls are excluded from every headline rate.** They were selected *because* they honour, so counting them alongside the study population would inflate the result — including them raises the honouring rate from 11.4% to 20.5%, which would be an artifact of target selection rather than a finding.

Two controls from an earlier run were dropped. `www.wikipedia.org` is a language-selection portal, so it correctly never varies and demonstrates nothing. `gnu.org` honours the header correctly but is too slow to yield two usable observations in any vantage.

### Reproducibility

The sweep was run three times. The second run swept header variants in a **different order per host**, and every headline figure was identical to the first — evidence the findings are not an artifact of request ordering. The third run is the one reported here, differing only in the control set.

## Findings

### Honouring the header is rare and concentrated

Four commercial sites of 35 judged, three of them media companies:

| Site | Sector | Vantages varying |
|---|---|---|
| `spotify.com` | media | 20 / 20 |
| `youtube.com` | media | 20 / 20 |
| `agoda.com` | travel | 20 / 20 |
| `netflix.com` | media | 13 / 20 |

By sector, of sites judgeable: media 3/5, travel 1/2, and **zero** from airlines (0/2), electronics (0/6), finance (0/5), mobility (0/3), public bodies (0/4), retail (0/4) and software (0/4).

Netflix is a partial case worth naming: it varies for Spanish, redirecting to `/us-es/`, and returns `lang="en"` for every other language including German, French, Japanese and Chinese. It counts as honouring under the definition but honours exactly one language.

`spotify.com` is the one commercial site that does the whole job properly. It returns `es-419` for `es-MX`, `fr-CA` for `fr-CA`, `zh-CN` for `zh-CN` and `ar-EG` for `ar-EG` — the correct handling of regional subtags that almost nobody else manages, and the same behaviour as the controls.

### Geolocation is the dominant strategy

Sixteen commercial sites of 35, and where it happens it is near-total — almost every one varies on 15 of 15 header variants, meaning the vantage decides the response no matter what the user asks for.

`aircanada.com`, `dell.com`, `disneyplus.com`, `hp.com`, `ibm.com`, `lenovo.com`, `lg.com`, `mastercard.com`, `netflix.com`, `nike.com`, `paypal.com`, `salesforce.com`, `samsung.com`, `singaporeair.com`, `uniqlo.com`, `visa.com`.

Only `netflix.com` appears in both lists. The rest do one or the other, and fifteen times out of sixteen the one they do is the one the user cannot control.

### Regional subtags are discarded

Three commercial sites of 38 distinguish `es-ES` from `es-MX`: `agoda.com`, `spotify.com`, `youtube.com`. The same three distinguish `fr-FR` from `fr-CA`. Two controls also distinguish the Spanish pair — `mozilla.org` and `videolan.org` — which is what makes the commercial absence meaningful rather than a limit of the method.

This is the finding with the sharpest practical edge, because the two are not cosmetic variants of each other. `1.234.567,89` in Spain is `1,234,567.89` in Mexico — a figure that reads as a million and a bit in one reads as one-point-two in the other. France groups digits with U+202F NARROW NO-BREAK SPACE and Canada with U+00A0 NO-BREAK SPACE, and `fr-CA` writes dates in ISO order where `fr-FR` does not. A site serving Spain's conventions to Mexico is not "supporting Spanish" in any sense a reader would recognise.

One incidental observation: `videolan.org` returns `lang="es_MX"` — an underscore where BCP 47 requires a hyphen, which is invalid and would fail a strict parser.

### Vary is absent from the commercial web entirely

Three sites in the study declare `Vary: Accept-Language`: `debian.org`, `mozilla.org` and `torproject.org`. All three are controls. **No commercial site declares it**, including the four that vary on the header.

This is a correctness bug rather than a preference. A shared cache in front of such a site is entitled to serve the first language it saw to everyone who follows.

### Right-to-left is barely handled

Of 36 commercial sites answering the Arabic and Hebrew variants, **3** set `dir="rtl"`: `paypal.com`, `spotify.com` and `agoda.com`. Three of the four controls set it. A site that serves Arabic text without `dir="rtl"` renders it in the wrong direction.

`paypal.com` is an interesting case: it sets `dir="rtl"` while not otherwise honouring the header, which suggests it takes the country from the IP and the language from `Accept-Language` — a split strategy the two definitions here do not separately capture.

### Number and date formatting follows the IP, not the header

`lang` says what language a page claims to be in. It says nothing about whether the numbers and dates on it are formatted for the reader — which is the question a localization library actually cares about, and the one that motivated extending the probe to classify the conventions in each page's visible text.

Markup and script bodies are stripped first, then grouped and decimal numbers are classified by which separators they use, distinguishing U+00A0 NO-BREAK SPACE from U+202F NARROW NO-BREAK SPACE. **29.0%** of successful observations expose at least one unambiguously classifiable number.

The result is unambiguous on the header axis:

* **0 of 21** judgeable sites change their number format in response to `Accept-Language`.
* **7 of 17** judgeable sites change it in response to the vantage IP.

Even the four sites that honour the header for *language* do not honour it for *format*. `spotify.com`, which handles language better than anyone else in the study, exposes no server-rendered numbers at all — its prices are rendered client-side, which is precisely the gap an HTTP probe cannot close.

Where formatting does vary by region, it is not reliably *correct*. `lenovo.com` varies across four of the regions measured and matches the local convention in one of them:

| Vantage | Observed | Convention for that country |
|---|---|---|
| `mx-central-1` | `group=comma decimal=dot` | matches |
| `ap-northeast-1` | `group=dot decimal=comma` | Japan uses comma grouping, dot decimals |
| `ap-south-1` | `decimal=comma` | India uses dot decimals |
| `eu-west-3` | `decimal=dot` | France uses comma decimals |

This last table is an illustration rather than a measured error rate. At this depth the probe cannot separate "formatted for the wrong locale" from "showing different products at different prices", and establishing that difference needs a rendering probe that can read a specific labelled price field. It is the clearest single candidate for follow-up work.

Date field order shows the same pattern: `year-first` dominates the observations that can be classified, which reflects ISO dates in machine-readable markup more than anything a reader sees.

### A fifth of the web will not talk to a datacentre

Of 16,200 observations, 68.1% succeeded, **22.4% were blocked**, 7.6% errored and 1.9% returned a non-200 status.

Ten sites were blocked in all 20 regions on all or nearly all variants — `expedia.com` (429), `hm.com`, `lufthansa.com`, `marriott.com`, `oracle.com`, `sony.com`, `zara.com`, `adidas.com` (403), `hertz.com` (an Incapsula challenge page) and `airbnb.com` (an interstitial too small to be a home page).

The blocking is keyed on the ASN, not the country: it is identical in Frankfurt, Virginia and Mexico City.

### Measuring changes what can be measured

The ten blocked sites were re-swept from a residential connection, using the same collector so the comparison would be exact. The result was not the expected one.

* `zara.com` answered all 15 variants from the residential IP while returning 403 to every AWS region. That confirms ASN-keyed blocking for at least one site.
* The other nine were blocked from the residential connection too — including `hertz.com`, which had served HTTP 200 from **the same IP address earlier the same day**.

Between those two measurements the only thing that changed was that the address had been used to probe those sites. Bot defences adapted within hours, and a residential vantage turns out to be a depleting resource rather than a stable one.

This matters for the design as much as for the result. A VPN-based fallback would degrade faster, not slower — a shared commercial exit address is probed by many users continuously, and would be flagged long before a domestic connection. The practical consequence is that the blocked fifth cannot be recovered by changing where the probe runs from.

## Limitations

Stated plainly, because the denominator is the part of a study like this most easily fudged.

* **The blocked fifth is not missing at random.** Sites behind Cloudflare, Akamai and Incapsula are systematically excluded, and they are plausibly the sites with the largest localization budgets. If anything this biases the honouring rate *upward*, so 11.4% should be read as a ceiling rather than a floor. The residential re-sweep above establishes that this exclusion cannot be cheaply removed.
* **Only landing pages.** A site may negotiate language deeper in a booking or checkout flow and not on its home page.
* **`lang`, `Content-Language` and the final URL, not rendered text.** A site that swaps all of its copy while leaving `lang="en"` and the URL unchanged is scored as not honouring. This undercounts, and detecting it needs a rendering probe rather than an HTTP one.
* **Number formatting is measured only where it is server-rendered.** 29% of successful observations expose a classifiable number; the rest render prices client-side or show none. Sites in the second group — `spotify.com` among them — are absent from the formatting result entirely, and they are plausibly the more sophisticated ones.
* **Fifteen sites were never judgeable** for header sensitivity — blocked or too slow to yield two usable observations in any single vantage.
* **No Cyrillic, Hebrew, Thai or Chinese vantage.** AWS has no region in Russia or Poland, and five requested opt-in regions could not be enabled on this account. `ru-RU`, `pl-PL`, `he-IL` and `th-TH` were therefore tested on the header axis only. What is missing is narrowly "what does a Russian IP see", not "does this site honour Russian".
* **One measurement, one day.** Sites change. Runs are keyed and additive, so drift is measurable, but nothing here establishes a trend.
* **`paypal.com` suggests the two definitions are not exhaustive.** A site that takes country from the IP and language from the header satisfies neither cleanly. A future run should separate the two axes rather than treating "varies" as one signal.

## What this means for a localization library

The measurement changes what a library should assume about its environment.

* **The server usually does not know the user's locale.** If 11.4% of commercial sites consult `Accept-Language` and 46% route on IP, then for most applications the locale arriving at the application layer is either absent or wrong. A library that assumes a correct incoming locale is designing for a web that does not exist. Making locale resolution explicit, overridable and inspectable matters more than making it automatic.
* **Regional subtags need first-class handling precisely because the web discards them.** `es-MX` and `fr-CA` differ from `es-ES` and `fr-FR` in separator, grouping character and date order. A library that resolves `es-MX` to "Spanish" reproduces the failure this study measures. This is a resolution question, not an inheritance one: TR35's inheritance chain governs which *data* a missing item falls back to, and is orthogonal to preserving the requested tag's identity.
* **`Vary: Accept-Language` should be emitted by anything that negotiates on the header.** No commercial site in this study emits it. It costs one header, and its absence corrupts every shared cache in front of the application.
* **`dir` is not optional.** Three commercial sites in 36 set it. Any HTML helper should emit `dir` alongside `lang` by construction, rather than leaving it to the caller to remember.

## Reproducing

The harness is the sibling application `localize_research_probe`.

```bash
mix run -e 'LocalizeResearchProbe.Env.load(); LocalizeResearchProbe.Run.sweep()'
```

It provisions a Lambda in every usable AWS region, invokes them concurrently, collects results from S3 and writes them to `priv/runs.db`. A sweep takes about four minutes and costs a few cents of S3; the Lambda usage sits inside the always-free tier by roughly two orders of magnitude.

The report figures are regenerated with:

```bash
mix run priv/report.exs
```

Run `20260822012602` is the basis for every number above, and `residential-blocked-20260822` holds the residential re-sweep. Runs are keyed and additive, so a later sweep can be compared against them rather than replacing them.
