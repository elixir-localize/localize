# Does the web honour Accept-Language? A measurement

**Measured 2026-08-22.** 53 sites, 15 header variants, 20 vantage points on five continents, 15,900 observations. Every figure below comes from a query in `LocalizeResearchProbe.Analysis` against the run database, not from a spreadsheet.

The companion document [accept-language-honouring.md](accept-language-honouring.md) surveys what has been *claimed* about `Accept-Language`. This one measures it.

## Summary

The web does not route on `Accept-Language`. It routes on IP address.

* **13.5%** of judgeable sites (5 of 37) vary their response on `Accept-Language` at all.
* **42.1%** (16 of 38) vary on the vantage's IP geolocation — **three times as many**.
* **2 of 53** sites declare `Vary: Accept-Language`. Four of the five sites that *do* honour the header fail to declare it.
* **3 of 36** sites distinguish `es-ES` from `es-MX`, and the same 3 distinguish `fr-FR` from `fr-CA`. Regional subtags are, in practice, discarded.
* **3 of 38** sites set `dir="rtl"` when asked for Arabic or Hebrew.
* Asking 38 sites for German (`de-DE`) returns `lang="en"` from **22** of them.

The single clearest illustration is PayPal. Holding the header constant at "no preference" and varying only the vantage:

| Vantage | Landing URL |
|---|---|
| `us-east-1` | `https://www.paypal.com/us/home` |
| `eu-central-1` | `https://www.paypal.com/de/home` |
| `ap-northeast-1` | `https://www.paypal.com/jp/home` |
| `sa-east-1` | `https://www.paypal.com/br/home` |
| `mx-central-1` | `https://www.paypal.com/mx/home` |

Flawless IP-based routing. PayPal does not appear in the list of sites that honour `Accept-Language` at all — the header a user can actually set is ignored, and the one they cannot control decides what they see.

The most direct demonstration is what comes back when the header is unambiguous. Requesting `zh-CN` from twenty vantages, the `html lang` values returned across sites include `de-DE`, `pt-BR`, `pt`, `ja`, `fr`, `es-MX`, `ko-KR`, `sv`, `en-ZA`, `en-IN` and `en-SG`. Exactly **two** sites returned `zh-CN`. The language served tracks the vantage, not the request: ask for Chinese from Frankfurt and get German, from São Paulo and get Portuguese, from Tokyo and get Japanese.

## Method

A probe fetches the landing page of each target once per header variant, from each vantage, and records the status, the `html` element's `lang` and `dir`, the `Content-Language` and `Vary` headers, the `Server` header, the final URL after redirects, the body length and a body hash.

**Vantages.** AWS Lambda in every region the account can use — 21 requested, 20 reached. Each region invokes asynchronously and writes its own result to S3, so a sweep costs one region's wall-clock rather than twenty-one.

**Header variants.** Fifteen, each carrying a regional subtag because the sharper question is whether a site distinguishes `es-ES` from `es-MX` rather than whether it knows Spanish: no header, `en-US`, `de-DE`, `fr-FR`, `fr-CA`, `es-ES`, `es-MX`, `pl-PL`, `zh-CN`, `ko-KR`, `ru-RU`, `ja-JP`, `ar-EG`, `he-IL`, `th-TH`. The q-values follow what a browser actually sends.

**Targets.** 53 sites stratified by sector — airlines, travel, retail, electronics, software, media, finance, mobility, public bodies — plus three controls chosen because they are known to honour the header and are not bot-defended.

### The two definitions

* A site **honours Accept-Language** if, holding the vantage fixed, its successful responses differ across header variants.
* A site **geolocates** if, holding the header variant fixed, its successful responses differ across vantages.

Difference is measured on `html lang`, `Content-Language` and the final URL together. Body hash is deliberately *excluded*: fifteen sequential requests to one host will differ in CSRF tokens and timestamps, so a hash comparison would report that every site varies on everything.

Both definitions exclude blocked and errored observations, and both require at least two usable observations before a site is judged. A site that could not be measured is excluded, never counted as a failure.

### Validity check

`debian.org` was included precisely to test whether the detector works. It returns `lang` and `Content-Language` matching the request across all fifteen variants — `ar`, `de`, `es`, `fr`, `ko`, `pl`, `ru`, `zh-CN` — and declares `Vary: Accept-Language` on every one. The detector flags it as honouring, in 20 of 20 vantages. `spotify.com` behaves the same way and additionally returns `es-419` for `es-MX` and `fr-CA` for `fr-CA`, which is the correct handling almost nobody else manages.

The sweep was run twice with the header variants swept in a **different order per host** on the second run. Every headline figure was identical across both runs, which is evidence the findings are not an artifact of request ordering.

## Findings

### Honouring the header is rare and concentrated

Five sites of 37 judged. Four of the five are media companies:

| Site | Sector | Vantages varying |
|---|---|---|
| `spotify.com` | media | 20 / 20 |
| `youtube.com` | media | 20 / 20 |
| `agoda.com` | travel | 20 / 20 |
| `debian.org` | control | 20 / 20 |
| `netflix.com` | media | 13 / 20 |

By sector, of sites judgeable: media 3/5, travel 1/2, control 1/2, and **zero** from airlines (0/2), electronics (0/6), finance (0/5), mobility (0/3), public bodies (0/4), retail (0/4) and software (0/4).

Netflix is a partial case worth naming: it varies for Spanish, redirecting to `/us-es/`, and returns `lang="en"` for every other language including German, French, Japanese and Chinese. It counts as honouring under the definition but honours exactly one language.

### Geolocation is the dominant strategy

Sixteen sites of 38, and where it happens it is near-total — almost every one varies on 15 of 15 header variants, meaning the vantage decides the response no matter what the user asks for.

`aircanada.com`, `dell.com`, `disneyplus.com`, `hp.com`, `ibm.com`, `lenovo.com`, `lg.com`, `mastercard.com`, `netflix.com`, `nike.com`, `paypal.com`, `salesforce.com`, `samsung.com`, `singaporeair.com`, `uniqlo.com`, `visa.com`.

Only `netflix.com` appears in both lists. Of the 38 judgeable sites, 15 geolocate and do not honour the header, 4 honour the header and do not geolocate, 1 does both, and **18 do neither** — serving the same page to every language and every continent.

### Regional subtags are discarded

Three sites of 36 distinguish `es-ES` from `es-MX`: `agoda.com`, `spotify.com`, `youtube.com`. The same three distinguish `fr-FR` from `fr-CA`.

This is the finding with the sharpest practical edge, because the two are not cosmetic variants of each other. `1.234.567,89` in Spain is `1,234,567.89` in Mexico — a figure that reads as a million and a bit in one reads as one-point-two in the other. France groups digits with U+202F NARROW NO-BREAK SPACE and Canada with U+00A0 NO-BREAK SPACE, and `fr-CA` writes dates in ISO order where `fr-FR` does not. A site serving Spain's conventions to Mexico is not "supporting Spanish" in any sense a reader would recognise.

### Vary is essentially absent

Two sites of 53 declare `Vary: Accept-Language` anywhere in the run: `debian.org` and `gnu.org`. Four of the five sites that vary on the header — `agoda.com`, `netflix.com`, `spotify.com`, `youtube.com` — do not declare it.

This is a correctness bug rather than a preference. A shared cache in front of such a site is entitled to serve the first language it saw to everyone who follows.

### Right-to-left is barely handled

Of 38 sites answering the `ar-EG` variant, 3 set `dir="rtl"` and 4 return a `lang` beginning `ar`. The `he-IL` variant gives 3 and 3. A site that serves Arabic text without `dir="rtl"` renders it in the wrong direction.

### A fifth of the web will not talk to a datacentre

Of 15,900 observations, 65.8% succeeded, **22.7% were blocked**, 9.6% errored and 1.9% returned a non-200 status.

The blocking is not incidental. Ten sites were blocked in all 20 regions on all or nearly all variants — `expedia.com` (429), `hm.com`, `lufthansa.com`, `marriott.com`, `oracle.com`, `sony.com`, `zara.com`, `adidas.com` (all 403), `hertz.com` (an Incapsula challenge page) and `airbnb.com` (an interstitial too small to be a home page).

The same probe run from a residential connection blocked **zero of 30** observations against a ten-site subset that included Hertz and Zara. The block is keyed on the ASN — identical in Frankfurt, Virginia and Mexico City — not on the country or the headers.

This matters beyond the arithmetic. The sites that block are disproportionately the bot-defended global brands the question is *about*, so the surviving sample is skewed toward the less-defended. See the limitations below.

## Limitations

Stated plainly, because the denominator is the part of a study like this most easily fudged.

* **The blocked fifth is not missing at random.** Sites behind Cloudflare, Akamai and Incapsula are systematically excluded, and they are plausibly the sites with the largest localization budgets. If anything this biases the honouring rate *upward*, so 13.5% should be read as a ceiling rather than a floor.
* **Only landing pages.** A site may negotiate language deeper in a booking or checkout flow and not on its home page.
* **`lang`, `Content-Language` and the final URL, not rendered text.** A site that swaps all of its copy while leaving `lang="en"` and the URL unchanged is scored as not honouring. This undercounts. Detecting it needs the rendering probe described in the plan, not the HTTP probe used here.
* **Sixteen sites were never judgeable** for header sensitivity — blocked or too slow to yield two usable observations in any single vantage. `gnu.org` is one: it honours the header correctly where it answers, but timed out too often under load to be judged, so it is excluded rather than counted either way.
* **No Cyrillic, Hebrew, Thai or Chinese vantage.** AWS has no region in Russia or Poland, and five requested opt-in regions could not be enabled on this account. `ru-RU`, `pl-PL`, `he-IL` and `th-TH` were therefore tested on the header axis only. What is missing is narrowly "what does a Russian IP see", not "does this site honour Russian".
* **One measurement, one day.** Sites change. The run is reproducible and the database keyed by run, so drift is measurable, but nothing here establishes a trend.
* **`www.wikipedia.org` was a poor control.** It is a language-selection portal, so it correctly does not vary. It should be replaced with a language-specific Wikipedia host in a future run.

## What this means for Localize

The measurement changes what a localization library should assume about its environment.

* **The server usually does not know the user's locale.** If 13.5% of sites consult `Accept-Language` and 42% route on IP, then for most applications the locale arriving at the application layer is either absent or wrong. A library that assumes a correct incoming locale is designing for a web that does not exist. Making locale resolution explicit, overridable and inspectable matters more than making it automatic.
* **Regional subtags need first-class handling precisely because the web discards them.** `es-MX` and `fr-CA` differ from `es-ES` and `fr-FR` in separator, grouping character and date order. A library that resolves `es-MX` to "Spanish" reproduces the failure this study measures. Localize resolves the full tag, and the `es-419` that Spotify returns for `es-MX` is exactly the right answer.
* **`Vary: Accept-Language` should be emitted by anything Localize helps build.** Two sites in 53 get this right. It costs one header and its absence corrupts every shared cache in front of the application.
* **`dir` is not optional.** Three sites in 38 set it. Any Localize-adjacent HTML helper should emit `dir` alongside `lang` by construction, rather than leaving it to the caller to remember.

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

Run `20260822005214` is the basis for every number above. Runs are keyed and additive, so a later sweep can be compared against it rather than replacing it.
