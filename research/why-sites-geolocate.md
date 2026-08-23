# Why sites geolocate instead of honouring Accept-Language

**Researched 2026-08-23.** A companion to [web-localization-measurement.md](web-localization-measurement.md), which measured that roughly 11% of major commercial sites vary on `Accept-Language` while roughly 49% route on IP geolocation. This document asks why, and what a localisation library can do about it.

## The short answer

**Mostly, they are doing what Google tells them to do.**

The single strongest incentive is not ignorance, laziness or internal politics. It is that Googlebot does not send `Accept-Language`, crawls from US addresses, and Google's own documentation warns that content negotiated on the header may not be crawled, indexed or ranked. A site that negotiates language on the header is invisible in every non-English market. A site that publishes `/de-at/` as a distinct URL is not.

Three further forces reinforce it — the header is expensive to honour at the CDN edge, it is being deliberately degraded by browsers for privacy reasons, and it is genuinely ambiguous as a signal. Organisational structure matters too, but the evidence for it is weaker than the technical case and should not be overstated.

The practical consequence for a localisation library is that **the battle over negotiation is already lost and was probably the wrong battle.** Sites do localise; they route by URL. What they get wrong is what happens *after* the locale is known — which is exactly where a library has leverage.

## 1. Search visibility — the dominant reason

Google's [documentation on locale-adaptive pages](https://developers.google.com/search/docs/specialty/international/locale-adaptive-pages) states plainly that the crawler "sends HTTP requests without setting `Accept-Language` in the request header", and that because "the default IP addresses of the Googlebot crawler appear to be based in the USA", Google "might not crawl, index, or rank all your content for different locales."

Its recommendation is unambiguous: use "separate locale URL configurations and annotating them with `rel="alternate"` hreflang annotations."

This is decisive in a way the other reasons are not. Content negotiation on a single URL means one indexable document. Separate URLs mean one indexable document per market, each rankable in its own language. For any business whose customers arrive through search, header negotiation is not a neutral technical choice — it forfeits the non-English half of its addressable market.

Our measurement is consistent with sites having followed this advice. The 26 sites that declare `hreflang` publish 2,317 locale-specific URLs between them. That is not the behaviour of organisations indifferent to localisation. It is the behaviour of organisations that localised the way the dominant search engine asked them to.

Note the asymmetry this creates, though. Google recommends separate URLs **and** advises against automatic redirection between language versions, suggesting instead that sites "show links on all pages for users to select their region and/or language". Many sites adopted the first half and ignored the second: they publish per-locale URLs *and* bounce arrivals by IP. That is where the user harm concentrates, and it is not what the guidance says to do.

## 2. Caching economics

`Vary: Accept-Language` tells a CDN that the response depends on the header, so the cache key becomes URL + header value. Because real browsers send a wide variety of header values, [this fragments the cache](https://developers.cloudflare.com/cache/concepts/vary/): one page becomes dozens of cached variants and the hit ratio collapses.

This is a real cost, paid continuously, in exchange for a benefit most site owners cannot measure. It also explains a finding from the measurement that otherwise looks like pure carelessness: **no commercial site in the study emits `Vary: Accept-Language`, including the four that vary on the header.** Emitting it correctly is what makes the caching problem appear. Omitting it keeps the CDN fast and quietly corrupts the cache for everyone behind it.

CDNs offer header normalisation to mitigate this, which helps, but it is configuration a team has to know to reach for.

## 3. The signal is being deliberately degraded

The header is worth less every year, by design.

Chrome's [Accept-Language reduction](https://github.com/explainers-by-googlers/reduce-accept-language) exists to cut passive fingerprinting: the header "is shared by default on every HTTP request", carries "a lot of entropy about the user", and can be "passively captured without the user's awareness". The proposal is to send **only the single most-preferred language**. Safari already sends one language, as does Chrome in incognito.

So the rich preference list that `Accept-Language` was designed to carry — `fr-CA` before `fr` before `en`, with quality weights — is being flattened to a single tag on privacy grounds. A team that invests in careful RFC 4647 negotiation is building on a signal its own browser vendors are actively simplifying.

## 4. The signal was never as good as the spec implies

Even at full fidelity, the header reports the **browser or OS UI language**, not a considered preference. Most users never open the setting; [as practitioners note](https://borretti.me/article/uselessness-accept-language-header), it defaults to whatever the device shipped with, so a Spanish speaker in the United States very often sends `en-US`.

The counter-argument is that geolocation is worse, and [it is](https://vitonsky.net/blog/2025/05/17/language-detection/): country is not language. Belgium has three official languages, Switzerland four, India twenty-two, Canada two. VPNs, travellers and diaspora all break it. Our measurement caught exactly this — request `zh-CN` from Frankfurt and get German.

But "both signals are bad" does not resolve to "use the header". It resolves to "use an explicit URL and let the user choose", which is what the sites did.

## 5. Implementation cost

Correct matching is [RFC 4647](https://www.rfc-editor.org/rfc/rfc4647.html) — language priority lists, quality weights, basic filtering versus lookup, prefix matching where `de` must match `de-DE`. It is easy to get subtly wrong, and mature libraries have shipped bugs in exactly that prefix case.

By comparison, mapping an IP to a country and redirecting is a few lines and a database. The effort asymmetry is large and it points the wrong way.

## 6. Organisational structure — plausible, weakly evidenced

The hypothesis that regional teams own regional content, and that per-country URLs mirror that ownership, is plausible and matches the shape of what we measured. The localisation-industry literature describes [decentralised governance models](https://translated.com/resources/governance-models-for-global-localization-organizational-structure) in which "each region, country, or business unit controls their own localization activities", and notes the resulting fragmentation: "different regions can develop different terminology, quality standards, and brand interpretations."

A per-market URL is a natural boundary for that: it maps to a team, a budget, an analytics property and an approval chain. Header negotiation cuts across all of them.

**But I found no direct evidence** that organisations chose geolocation *because* of team structure. The governance literature is about translation quality and workflow, not locale detection. This should be treated as a hypothesis consistent with the evidence, not a finding. It would be straightforward to test by asking practitioners directly, and that has apparently not been done.

## 7. What the economic evidence actually supports

### Language: well evidenced

The [CSA Research "Can't Read, Won't Buy"](https://www.marioncaris.com/wp-content/uploads/2011/10/Cant-read-wont-buy_2007.pdf) line of work established that consumers avoid buying in languages they do not read. More recent survey work reports that [four in five consumers will not buy from a brand without local-language support](https://www.businesswire.com/news/home/20230510005083/en/Four-in-Five-Consumers-Won%E2%80%99t-Buy-From-a-Brand-That-Doesn%E2%80%99t-Offer-Local-Language-Support), that 89% believe they should be able to deal with a company in their preferred language, and that 44% are frustrated by the dominance of English online.

This evidence is about **language presence** — whether a localised version exists at all. It is routinely cited as though it also covers formatting. It does not.

### Formats: barely evidenced at all

This is the gap. I could find no study quantifying the commercial impact of serving correct language with wrong number, date or currency conventions.

What exists is indirect. Date ambiguity between `MM/DD` and `DD/MM` is [genuinely costly in aggregate](https://www.w3.org/International/questions/qa-date-format) — roughly 132 dates a year are ambiguous, and the resulting confusion shows up in contract disputes, medical records and shipping — but no one has attributed a figure to it. On the commerce side, [Baymard's meta-analysis](https://www.swell.is/content/custom-checkout-statistics) puts cart abandonment at 70.22%, with 39% of stated abandonments citing unexpected cost and 14% inability to see the total — both categories where a misread price plausibly contributes, and neither isolating format.

Academically, [Alameer and Halfond's empirical study of 449 internationalised websites](https://viterbi-web.usc.edu/~halfond/papers/alameer16icsme.pdf) found internationalisation failures common, but focused on *presentation* failures — layout breakage from text expansion — rather than data-format correctness.

**So the position is:** the case for localising language is strong and quantified; the case for localising formats correctly is intuitively obvious, structurally similar, and essentially unmeasured. Our own measurement — 13.7% of self-declared locale variants misformatting numbers — is the first quantification of the *failure rate* I am aware of, though not of its cost.

## What this means for the Localize family

The reframing matters. If sites ignored localisation, the job would be advocacy. They do not ignore it: they publish thousands of locale-specific URLs and route users to them. **The failure is downstream of the routing decision**, at the point where a page already knows which locale it is, and still gets the details wrong.

That is squarely a library problem, and it suggests five things.

**1. Make "locale from the URL" a first-class, one-line operation.** Sites overwhelmingly encode locale in the path — `/de-at/`, `/befr/`, `/puertorico/es/`, `/us-es/`. That is the input a library actually receives in production, and the observed failures include serving Greek conventions on a page declared `en-CY`. A resolver that turns a path segment into a validated, canonical locale — and refuses ambiguous ones rather than guessing — addresses the real entry point.

**2. Provide an explicit precedence chain, not an automatic one.** Path, then cookie, then `Accept-Language`, then geolocation, with each step visible and overridable. The measurement shows the industry has settled on geolocation-first; the literature shows that is wrong for language and right for currency and legal jurisdiction. A library should let a team express "country from IP, language from anything but IP" because that is the correct answer and it is currently hard to say.

**3. Emit `lang` and `dir` together, by construction.** A quarter of declared RTL variants set direction in CSS and omit the `dir` attribute — it renders, and it loses bidi isolation, `:dir()` and assistive-technology semantics. No caller should have to remember this; it belongs in whatever emits the document element. This is `localize_web`'s surface.

**4. Make `Vary: Accept-Language` the default when negotiation happens, and say why.** No commercial site in the study emits it. The reason is cache economics, so the guidance has to acknowledge the cost and point at header normalisation rather than simply insisting.

**5. Treat regional subtags as load-bearing.** `es-MX` is not `es`; `fr-CA` is not `fr`; `en-CY` is not `el-CY`. The most interesting failure in the measurement was a site applying a *country's* conventions to a page labelled with another *language*. Resolving the full tag rather than either half is the fix, and Localize already does it.

### The research gap worth filling

Nobody has measured what wrong formats cost. The language case has twenty years of survey evidence behind it; the format case has none, despite being cheaper to fix and easier to get right. The measurement in the companion document establishes a failure rate. Pairing that with even a modest conversion or comprehension study would be novel, and would give teams the argument they currently lack when formatting loses to a sprint deadline.

## Sources

* [How Google Crawls Locale-Adaptive Pages — Google Search Central](https://developers.google.com/search/docs/specialty/international/locale-adaptive-pages)
* [Managing Multi-Regional and Multilingual Sites — Google Search Central](https://developers.google.com/search/docs/specialty/international/managing-multi-regional-sites)
* [Vary — Cloudflare Cache docs](https://developers.cloudflare.com/cache/concepts/vary/)
* [Reduce fingerprinting in the Accept-Language header — explainers-by-googlers](https://github.com/explainers-by-googlers/reduce-accept-language)
* [Origin trial for Accept-Language Reduction — Privacy Sandbox](https://developers.google.com/privacy-sandbox/blog/origin-trial-for-accept-language-reduction)
* [The Uselessness of the Accept-Language Header — Fernando Borretti](https://borretti.me/article/uselessness-accept-language-header)
* [Don't Guess My Language — vitonsky.net](https://vitonsky.net/blog/2025/05/17/language-detection/)
* [RFC 4647: Matching of Language Tags](https://www.rfc-editor.org/rfc/rfc4647.html)
* [Language Tags and Locale Identifiers for the World Wide Web — W3C](https://www.w3.org/TR/ltli/)
* [Date formats — W3C Internationalization](https://www.w3.org/International/questions/qa-date-format)
* [Governance Models for Global Localization — Translated](https://translated.com/resources/governance-models-for-global-localization-organizational-structure)
* [Can't Read, Won't Buy — Common Sense Advisory](https://www.marioncaris.com/wp-content/uploads/2011/10/Cant-read-wont-buy_2007.pdf)
* [Four in Five Consumers Won't Buy From a Brand That Doesn't Offer Local Language Support — RWS via BusinessWire](https://www.businesswire.com/news/home/20230510005083/en/Four-in-Five-Consumers-Won%E2%80%99t-Buy-From-a-Brand-That-Doesn%E2%80%99t-Offer-Local-Language-Support)
* [An Empirical Study of Internationalization Failures in the Web — Alameer & Halfond](https://viterbi-web.usc.edu/~halfond/papers/alameer16icsme.pdf)
* [Custom Checkout Statistics 2025 (Baymard meta-analysis) — Swell](https://www.swell.is/content/custom-checkout-statistics)
