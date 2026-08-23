# How the web handles locale: a measurement

**Measured 2026-08-22 and 2026-08-23.** Two questions, against the same population of global brands.

* **Negotiation** — does a site adapt to the locale a user asks for? 54 sites, 15 `Accept-Language` variants, 20 AWS vantages on five continents, **16,200 observations**, plus a matching 810-observation sweep from a residential connection in a real browser.
* **Correctness** — where a site publishes a locale-specific variant of itself, is that variant right for the locale it claims? 26 sites declaring **2,317 locale variants**, of which 2,213 were audited in a real browser.

Every figure comes from a query in `LocalizeResearchProbe.Analysis` or from the audit comparison, with `Localize` as the CLDR oracle. The companion document [accept-language-honouring.md](accept-language-honouring.md) surveys what has been *claimed* about `Accept-Language`; this one measures it.

A note on method before any numbers, because it changed the study. An HTTP probe cannot measure bot-defended sites: a fifth of this population refuses a cold HTTP client while serving the same pages to a browser on the same machine, in the same second, from the same address. Several findings in an earlier draft of this document were artifacts of that and have been withdrawn — see [What this measurement got wrong](#what-this-measurement-got-wrong). The results below are browser-collected wherever a browser was needed.

## Summary

**The web routes on IP, not on the header the user controls — and where it does localise, a meaningful share of the result is wrong.**

Negotiation, across the 37 commercial sites judgeable from 20 datacentre vantages:

* **10.8%** (4 sites) vary their response on `Accept-Language` at all.
* **48.6%** (18 sites) vary on the vantage's IP geolocation — four and a half times as many.
* 17 geolocate and ignore the header, 3 honour the header and do not geolocate, 1 does both, and **16 do neither**.
* **Zero** declare `Vary: Accept-Language`. The only three sites in the study that declare it are controls.

The same sweep run from a residential connection in a real browser gives **11.4%** (5 of 44) — a different client, a different vantage, a different set of failure modes, and the same answer.

Correctness, across the variants those sites publish for themselves:

* **136 of 2,213 declared variants (6%) redirect out of their own declared path.** A site publishes `hreflang="ca"` and the URL behind it serves English.
* **3.2%** serve an `html lang` that contradicts the locale they were declared as.
* **23.7%** of variants declared for right-to-left locales set no `dir` attribute.

The clearest illustration of the negotiation result is PayPal. Holding the header constant at "no preference" and varying only the vantage:

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

Four commercial sites of 37 judged from the datacentre sweep — `spotify.com`, `youtube.com` and `agoda.com` at 20 of 20 vantages, `netflix.com` at 13 of 20.

By sector, of sites judgeable: media 3/5, travel 1/2, and **zero** from airlines (0/3), electronics (0/6), finance (0/5), mobility (0/4), public bodies (0/4), retail (0/4) and software (0/4).

Netflix is a partial case worth naming: it varies for Spanish, redirecting to `/us-es/`, and returns `lang="en"` for every other language including German, French, Japanese and Chinese. It counts as honouring under the definition but honours exactly one language.

`spotify.com` is the one commercial site that does the whole job. It returns `es-419` for `es-MX`, `fr-CA` for `fr-CA`, `zh-CN` for `zh-CN` and `ar-EG` for `ar-EG` — correct regional-subtag handling that almost nobody else manages, matching the controls.

### Three more honourers only a browser could see

The browser sweep reached sites that refuse every HTTP client, and two of them turn out to be among the best in the study:

* **`zara.com` honours all fifteen variants.** `lang` tracks `ar`, `de`, `es`, `fr`, `he`, `ja`, `ko`, `pl`, `ru`, `th`, `zh` exactly. It was invisible to the earlier method because it 403s cold HTTP clients, and it would have been recorded as a non-honourer.
* **`sony.com`** honours Japanese only — `ja-JP` redirects to `/ja/`, everything else gets `/en/`. The same shape as Netflix's Spanish-only behaviour.
* **`european-union.europa.eu`** honours `de`, `es`, `fr` and `pl`, falling back to English otherwise. That is correct rather than a defect: those are EU official languages.

This is the part of the earlier draft that was most wrong. The *rate* replicated across both methods; the *membership* did not.

### Geolocation is the dominant strategy

Eighteen commercial sites of 37, and where it happens it is near-total: almost every one varies on 15 of 15 header variants, meaning the vantage decides the response no matter what the user asks for.

`aircanada.com`, `dell.com`, `disneyplus.com`, `hp.com`, `ibm.com`, `lenovo.com`, `lg.com`, `mastercard.com`, `netflix.com`, `nike.com`, `paypal.com`, `salesforce.com`, `samsung.com`, `singaporeair.com`, `uniqlo.com`, `visa.com` and, newly measurable, `hertz.com` and `hm.com`.

`hertz.com` deserves a line of its own, because it is the site the claim that started this investigation was about. Measured in a browser, it returns `lang="en-AU"` to **all fifteen variants** from an Australian address. It localises — to the country it thinks you are in — and ignores the language you asked for completely.

### Vary is absent from the commercial web entirely

Three sites declare `Vary: Accept-Language`: `debian.org`, `mozilla.org` and `torproject.org`. All three are controls. **No commercial site declares it**, including the four that vary on the header — `agoda.com`, `netflix.com`, `spotify.com` and `youtube.com`.

This is a correctness bug rather than a preference. A shared cache in front of such a site is entitled to serve the first language it saw to everyone who follows.

### Regional subtags are discarded

Three commercial sites of 40 distinguish `es-ES` from `es-MX`: `agoda.com`, `spotify.com`, `youtube.com`. The same three distinguish `fr-FR` from `fr-CA`. Two controls also distinguish the Spanish pair, which is what makes the commercial absence meaningful rather than a limit of the method.

The two are not cosmetic variants of each other. `1.234.567,89` in Spain is `1,234,567.89` in Mexico — a figure that reads as a million and a bit in one reads as one-point-two in the other. France groups digits with U+202F NARROW NO-BREAK SPACE and Canada with U+00A0 NO-BREAK SPACE, and `fr-CA` writes dates in ISO order where `fr-FR` does not.

### Right-to-left is barely handled

Of 37 commercial sites answering the Arabic and Hebrew variants from the datacentre sweep, **2** set `dir="rtl"`: `spotify.com` and `agoda.com`. Three of the four controls set it.

The browser sweep adds a sharper case. **`zara.com` gets the language right for all fifteen variants and serves Arabic and Hebrew with `dir="ltr"`.** Getting the language right and the direction wrong is a more specific failure than not localising at all, and it was unreachable to every previous method.

### Datacentre and residential agree

Every negotiation observation initially came from AWS, which raises an obvious objection: sites may suppress personalisation for datacentre traffic, in which case the rate says more about the vantage than the web.

Holding country constant — `ap-southeast-2` in Sydney against a residential connection in the same region, same day, same collector — **7 of 36 sites varied on `Accept-Language` from each**. Across all vantages the rates were 4/32 and 3/32, with one site changing verdict, and that site was `netflix.com`, already the borderline case at 13 of 20.

The objection does not hold. Sites ignore the header for consumers exactly as much as they ignore it for infrastructure.

## Part 2 — Correctness

Part 1 measures a mechanism, not a capability. A site that serves `paypal.com/de/home` to a German address **is** localised, and well; it simply does not consult the header. Conflating the two would be a category error, and the "adapts to neither" group makes that vivid — it contains Apple, IKEA, Microsoft, SAP, the European Union, the UN and the WHO, all of which publish extensively localised sites behind a country selector rather than negotiating on a landing page.

So the second study asks a different question, and takes the sites' own claims as ground truth:

> **You declare that you support `de-AT`, `ja-JP` and `ar-EG`. Do those pages actually behave like `de-AT`, `ja-JP` and `ar-EG`?**

This removes the negotiation confound entirely — each URL is fetched on its own terms with no `Accept-Language` at all — and, run in a browser, it removes the access problem too: **2,213 variants audited, 3 blocked**.

### What the sites declare

Sites publish their locale variants in `<link rel="alternate" hreflang>` and in sitemaps. Discovery reads both and follows one level of same-host links, because most large brands declare nothing on their landing page — PayPal, Samsung, YouTube, Netflix, Nike and Microsoft all declare zero in-page and hundreds in their sitemaps.

**26 sites declare 2,317 locale variants across 825 distinct locale tags.**

| Site | Declared | | Site | Declared |
|---|---|---|---|---|
| `paypal.com` | 274 | | `youtube.com` | 110 |
| `mastercard.com` | 216 | | `europcar.com` | 101 |
| `samsung.com` | 171 | | `airbnb.com` | 96 |
| `apple.com` | 140 | | `lenovo.com` | 95 |
| `singaporeair.com` | 131 | | `netflix.com` | 79 |
| `visa.com` | 125 | | `salesforce.com` | 65 |
| `ikea.com` | 116 | | `nike.com` | 64 |

### The tags themselves are almost always right

All 825 declared tags were validated through `Localize.validate_locale/1`. **99.2% resolve.** Tag correctness is not the story, but the exceptions are specific:

* **`europcar.com`** declares `ar-DB`, `en-DB` and `sq-KS`. `DB` and `KS` are not region codes — Dubai is within `AE`, Kosovo is `XK`.
* **`ikea.com`** declares `es-SP` and `es-CE`. Spain is `ES`; Ceuta is `EA`.
* **`avis.com`** declares `tc`, apparently meaning Traditional Chinese, which is `zh-Hant`.
* **`videolan.org`** uses underscores throughout — `es_MX`, `zh_CN`, `pt_BR` and nine more. Invalid BCP 47.

These brands resolve 99.2% of their identifiers correctly and still misformat a share of the variants those identifiers name. Tag validation is table stakes; formatting is the work.

### Declared variants that do not lead where they claim

**53 of 2,213 audited variants redirect out of their own declared path.** A site publishes `hreflang="ca"` and the URL behind it lands on `/en-US/`.

This is a defect in its own right and a methodological trap: auditing the page such a URL lands on blames Catalan for English formatting. All 53 are excluded from every verdict below.

### The `lang` attribute contradicts the declaration in 3.5%

73 of 2,077 judged variants. Both sides are canonicalised before comparing, so a site declaring `no-no` and serving `nb-no` counts as correct — it has applied CLDR's own canonicalisation and is more correct than its declaration.

| Site | Mismatched | Example |
|---|---|---|
| `paypal.com` | 34 of 273 | declared `en-gf`, serves `lang="fr-GF"` |
| `aircanada.com` | 11 of 48 | declared `es-ar`, serves `lang="en"` |
| `apple.com` | 11 of 139 | declared `en-AM`, serves **no `lang` attribute at all** |
| `youtube.com` | 6 of 107 | declared `ar`, serves `lang="en"` |
| `samsung.com` | 5 of 169 | declared `en-ID`, serves `lang="id-ID"` |
| `sixt.com` | 3 of 54 | declared `de-CH`, serves `lang="fr"` |

Samsung also serves `lang="az_AZ"` on its Azerbaijani site — an underscore where BCP 47 requires a hyphen.

### Right-to-left: rendering mostly works, the markup often does not

Two different questions, and they give different answers.

**Does the text render right-to-left?** Measured in a browser, which resolves the computed direction: **5 of 119 declared RTL variants render left-to-right** — 4.2%. `europcar.com` on both its Arabic variants, plus single cases at `mastercard.com`, `paypal.com` and `who.int`.

**Is the `dir` attribute set?** Measured on the markup: **23 of 97** RTL variants set no `dir` anywhere — 23.7%, and `samsung.com` accounts for 19 of them.

Samsung is the instructive case. Its Arabic pages carry over five thousand Arabic characters, declare `lang="ar-AE"` correctly, set no `dir` attribute anywhere in the document, and still render correctly because direction comes from a stylesheet. `who.int` does the same with `<body class="sf-body right-to-left">`.

So the claim is not that these pages are mirrored. It is that a quarter of declared RTL variants achieve direction through styling rather than the `dir` attribute, which renders but forfeits bidi isolation, the `:dir()` selector and assistive-technology semantics — and that a small number get it wrong outright.

### Number formatting: 13.7% of declared variants are not correct

The result closest to what a localisation library exists to get right, and the one that took the most correction to obtain.

**175 variants judged** — currency-anchored, locale resolvable, not redirected:

| Verdict | Count | Share |
|---|---|---|
| correct | 151 | **86.3%** |
| mixed — both correct and incorrect formatting on one page | 9 | **5.1%** |
| wrong | 15 | **8.6%** |

| Site | Not correct | |
|---|---|---|
| `samsung.com` | 8 of 53 | 6 of them `mixed` |
| `ikea.com` | 5 of 30 | |
| `ibm.com` | 4 of 12 | |
| `dell.com` | 3 of 29 | |
| `microsoft.com` | 2 of 27 | |
| `apple.com` | 1 of 10 | |
| `nike.com`, `paypal.com`, `lenovo.com`, `sixt.com`, `bbc.com` | 0 | |

Four examples, each verifiable against the live page:

* **`dell.com` at `fr-ch`** serves `457.26 CHF`. Swiss French takes a comma decimal and an apostrophe group: `1'234'567,89`.
* **`ikea.com` at `en-CY` and `en-GR`** serves `€691,00` — Greek and Cypriot conventions on variants it declared as **English**, which take a dot decimal.
* **`airbnb.com` at `es-CO`** serves `$1,360,196`. Colombian Spanish groups with dots.
* **`ibm.com` at `en-id`** serves `$1,241.21` where Indonesian conventions invert both separators.

The IKEA case is the most interesting failure mode in the study: not a site that ignores locale, but one that applies the *country's* conventions to a variant it labelled with a different *language*.

## What this measurement got wrong

An earlier draft of this document reported figures that were wrong. They are listed here rather than quietly replaced, because the errors are instructive about measuring the web at all, and because every one of them was found by a check rather than by inspection.

### The block rate measured the probe, not the web

The draft reported that **22.4% of observations were blocked** and built an argument on it: that the blocking was keyed on the ASN, that a residential fallback would help, that bot defences had "adapted within hours" to a probing address, and that the flagship case of the original claim could not be measured at all.

All of it was wrong, and the disproof was simple: a person opening the same sites in a browser on the same machine, on the same connection, at the same moment, reached every one of them. Seven brands recorded as blocking us — Hertz, Marriott, Expedia, Lufthansa, Oracle, H&M, Adidas — answered a human immediately.

The actual mechanism is that these sites refuse a **cold session**, and no HTTP client can present anything else. A hand-driven incognito window is also refused, which rules out automation as the cause; a warmed browser profile is admitted, which identifies it. Blocking is a property of session state and client shape, not of the address. Datacentre and residential addresses both fail an HTTP probe and both succeed in a warm browser.

Measured properly, the rate is **20.0% for an HTTP client, 7.7% for a browser on landing pages, and effectively zero for the browser audit** — one blocked observation in 2,213.

### A detector bug, and a fix that silently did nothing

`hertz.com` returns a complete 172 KB page. It was recorded as blocked in every run from every vantage — **236 observations in a single sweep** — because the string `_incapsula_resource` appears in it. That script path is embedded in ordinary pages served through Incapsula; it is not a challenge marker. The code comment asserting that hard markers "appear only on a challenge page" was simply false.

Worse, the first fix silently failed. A text replacement that matched nothing left `_incapsula_resource` in both the hard and soft lists, the hard match kept winning, and the verification step passed by luck because Hertz's page did not contain the string at that instant. Two further sweeps ran on the broken detector. The fix now rewrites the list structurally and asserts the result by importing the module.

### The number classifier was wrong three times

A first pass reported **36.6%** of declared variants misformatting numbers. Spot-checking the samples showed it was counting dates (`14.06`, `23.07`), version strings (`2.104.2`) and times (`3.30`) as numbers, because the fallback pattern matched any `digits.digits`. Withdrawn.

Anchoring extraction to a currency marker gave **38.1%**, and spot-checking that found two more defects: pages carrying both correct and incorrect formatting were collapsed to whichever appeared more often, turning real inconsistency into an arbitrary verdict; and Indian lakh grouping (`₹1,07,000`) was parsed as a decimal because the pattern assumed three-digit groups, making every Indian-locale judgement unreliable. Withdrawn.

The classifier now reports the **set** of conventions a page demonstrates, names group sizes as CLDR does so `12,34,567.89` is `sizes=3-2`, discards samples that cannot settle a role rather than guessing, and rejects group sizes no locale uses.

### Following a link out of the locale, twice

Auditing a declared variant means following links to pages that price something. Both the HTTP audit and, later, the browser audit verified that a candidate link stayed within the declared locale's path — and neither checked where it actually **landed**. `mozilla.org/ca/products/vpn/` redirects to `/en-US/products/vpn/`, so Catalan was scored against English prices.

Both times the signal was the same: `mozilla.org`, a control chosen because it localises correctly, appeared in the results as a site with a dozen formatting errors. A control that fails is a broken method, not a broken site. After the first fix it scored 1 of 49; the browser audit reintroduced the bug and it reappeared at 9 of 20.

### CLDR version skew is not an error

`apple.com/fr/` groups French with U+00A0 where CLDR specifies U+202F. That is not a defect: CLDR moved French to U+202F recently and has revised the choice more than once — the pinned checkout carries `CLDR-16210 "Revert some changes involving NNBS U+202F"` and `CLDR-17233 "fix 0020+202F in fr.xml"`. A site grouping with U+00A0 is tracking an older ICU. Members of the space family are normalised against each other before comparison, and Apple scores correct.

### What this implies for anyone repeating this

* **An HTTP client cannot measure bot-defended sites.** Not with better headers, not from a residential address, not with a different TLS stack. The population it can reach is selected in a way that correlates with how much a brand invests in its web presence.
* **Controls are load-bearing.** Every substantive error above was caught by a control behaving impossibly, or by hand-checking a sample against the live page. None was caught by reading the code.
* **A verification that can pass by accident is not a verification.** Assert on structure, not on a single observation of live output.

## Method

### Three collectors, one classifier

* **HTTP probe in AWS Lambda**, in every region the account can use — 21 requested, 20 reached. Each region is invoked asynchronously and writes its own result to S3, so a sweep costs one region's wall-clock rather than twenty-one. This is the only way to get the **geolocation axis**: twenty simultaneous vantages on five continents.
* **Browser sweep**, driving Chrome over the DevTools Protocol from a residential connection. One vantage, but it reaches sites no HTTP client can and reads rendered text rather than markup.
* **Browser audit**, the same driver pointed at every locale variant the sites declare for themselves.

All three classify numbers and dates with the **same** code, in `probe.py`. The browser collectors emit rendered `innerText` and attributes; they do not classify. That classifier cost several rounds of correction, and a second implementation would have drifted from it — so the browser path and the HTTP path are directly comparable rather than approximately so.

### Why the browser needs a warm profile

A cold session is what these sites refuse, including a hand-driven incognito window. The careful design — a fresh isolated browser context per observation, so a cookie set under `de-DE` cannot leak into `fr-FR` — guarantees the worst case on every single request.

The profile is therefore persistent and shared, exactly like a person's browser. Each host is visited once to clear any challenge and take the clearance cookie, then all fifteen variants run inside that warmed session. `hm.com` goes from blocked to reachable on its second visit.

The cost is a contamination risk that cannot be eliminated, only detected: each host measures its **first variant again at the end** and compares. Divergence means a language cookie stuck, and the host is flagged rather than trusted.

### The two negotiation definitions

* A site **honours Accept-Language** if, holding the vantage fixed, its successful responses differ across header variants.
* A site **geolocates** if, holding the header variant fixed, its successful responses differ across vantages.

Difference is measured on `html lang`, `Content-Language` and the final URL together. Body hash is deliberately excluded: fifteen sequential requests to one host differ in CSRF tokens and timestamps, so a hash comparison would report that every site varies on everything. Both definitions exclude blocked and errored observations and require at least two usable observations. A site that could not be measured is excluded, never counted as a failure.

### Controls

Four, verified by hand before the run: chosen to honour the header, to answer quickly enough to survive fifteen sequential requests, and not to be bot-defended.

| Control | Honours | Declares `Vary` | Role |
|---|---|---|---|
| `debian.org` | 20/20 vantages | yes | `lang` and `Content-Language` both track the request |
| `mozilla.org` | 20/20 | yes | returns `es-MX` for `es-MX` — regional subtag preserved |
| `torproject.org` | 20/20 | yes | |
| `videolan.org` | 20/20 | **no** | exercises the `Vary`-omission detector |

All four register as honouring, which is the evidence that the detector works — and, twice, a control failing was the evidence that it had stopped working.

**Controls are excluded from every headline rate.** They were selected *because* they honour; including them would raise the negotiation rate from 10.8% to 19.5% as an artifact of target selection.

Two earlier controls were dropped: `www.wikipedia.org` is a language-selection portal, so it correctly never varies and demonstrates nothing, and `gnu.org` honours correctly but is too slow to yield two usable observations in any vantage.

### Number classification

Only visible text is scanned — `<script>` and `<style>` bodies and all markup removed, or in the browser collectors, `innerText` directly. JSON-LD is deliberately **not** read even though it would multiply recall, because machine-format prices are always dot-decimal and counting them would manufacture a large false error rate.

Numbers are judged only where adjacent to a currency marker, which is the strongest available evidence that a value is locale-formatted rather than a date, a version or a rating. The currency vocabulary is not Latin-only: Apple's Japanese store prices in 円 and was scoring as having no numbers at all, which silently excluded exactly the locales whose formatting is most worth checking.

Each page contributes the **set** of conventions it demonstrates, and each observed number is compared only on the properties it actually shows: a price of `21,99` establishes a decimal separator and says nothing about grouping. Group sizes are named as CLDR names them, so Indian grouping is recognised rather than misparsed.

The expectation for each locale is produced by formatting `1234567.89` with `Localize` and parsing the result with the same logic applied to the page, so both sides of the comparison are constructed identically.

## Limitations

Stated plainly, because the denominator is the part of a study like this most easily fudged.

* **175 of 2,213 audited variants carry a judgeable number.** Precision was chosen over recall deliberately, after two earlier attempts produced inflated rates from dates and version strings. The denominator is small; every member of it is verifiable, and several were checked by hand against the live page.
* **Short prices are ambiguous and excluded.** `199,800` could be two hundred thousand or one hundred and ninety-nine point eight. This disproportionately excludes JPY and KRW, which have no minor units and price almost entirely in that form.
* **Twenty-two commercial brands.** Enough to support a claim about the brands that publish the most locale variants, not enough for a prevalence claim about the web at large.
* **One residential vantage.** The browser sweep runs from a single Australian connection. It establishes that the datacentre result is not an artifact of the vantage; it cannot show whether a site honours the header for German consumers but not Australian ones.
* **No Cyrillic, Hebrew, Thai or Chinese vantage.** AWS has no region in Russia or Poland, and five requested opt-in regions could not be enabled. `ru-RU`, `pl-PL`, `he-IL` and `th-TH` were tested on the header axis only.
* **Landing pages and one level below.** A site may format correctly deeper in a checkout flow than on the pages audited.
* **`adidas.com` is genuinely unreachable** — a consistent block page across repeated warmed visits, unlike every other site in the population.
* **One measurement, two days.** Runs are keyed and additive, so drift is measurable. The negotiation figures were reproduced across consecutive days and across two independent collectors; nothing else here establishes a trend.

## What this means for a localisation library

* **The server usually does not know the user's locale.** If 11% of commercial sites consult `Accept-Language` and 49% route on IP, the locale arriving at the application layer is usually absent or wrong. Making locale resolution explicit, overridable and inspectable matters more than making it automatic.
* **Regional subtags need first-class handling precisely because the web discards them.** `es-MX` and `fr-CA` differ from `es-ES` and `fr-FR` in separator, grouping character and date order. This is a resolution question, not an inheritance one: TR35's inheritance chain governs which *data* a missing item falls back to, and is orthogonal to preserving the requested tag's identity.
* **A country is not a language.** IKEA serving `€691,00` on a variant it declared `en-CY` is the whole problem in one value: the country's conventions applied to a page labelled with another language. A library that resolves a full tag rather than guessing from either half avoids it.
* **`Vary: Accept-Language` should be emitted by anything that negotiates on the header.** No commercial site in this study emits it, and its absence corrupts every shared cache in front of the application.
* **`dir` is not optional and should not be left to the caller.** A quarter of declared RTL variants set direction in CSS instead. It renders, and it loses bidi isolation, `:dir()` and assistive-technology semantics.

## Reproducing

The harness is the sibling application `localize_research_probe`.

```bash
mix run -e 'LocalizeResearchProbe.Env.load(); LocalizeResearchProbe.Run.sweep()'
```

```bash
mix run -e 'LocalizeResearchProbe.Env.load(); LocalizeResearchProbe.Run.discover()'
```

The browser collectors need Chrome running with remote debugging on port 9222, and a persistent profile:

```bash
node priv/browser/collect.mjs < targets.json > priv/runs/browser-residential.json
```

```bash
node priv/browser/audit.mjs < audit_jobs.json > priv/runs/browser-audit.json
```

Classification and the CLDR comparison run afterwards, so the browser and HTTP paths are judged by identical code:

```bash
python3 priv/browser/classify.py priv/runs/browser-audit.json audit.tsv
```

The runs behind this document are `20260822233833` (negotiation, 20 vantages), `residential-20260822193607` (the residential comparison), `discover-20260822023833` (declaration) and `browser-audit-final.json` (correctness). Runs are keyed and additive, so a later run can be compared against them rather than replacing them.
