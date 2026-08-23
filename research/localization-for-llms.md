# Writing localized applications that LLMs can read

**Researched 2026-08-23.** A companion to [why-sites-geolocate.md](why-sites-geolocate.md), which concluded that search incentives had settled the question of how sites route locale. Agentic and LLM-mediated discovery changes the incentives, so this document asks what those systems actually do, and what follows for anyone building a localized application.

Where a claim is verified by direct observation it says so. Where it comes from a third party it is attributed.

## The short answer

**Agents do not negotiate. They read.**

Nothing in the LLM stack sends a meaningful `Accept-Language` on a reader's behalf, so the header is no more useful here than it was for search. What changes is everything downstream of that:

* **No major AI crawler executes JavaScript.** Client-rendered content is simply absent from what they see. This is the single largest difference from Googlebot, and it invalidates a decade of "Google renders JS, so we're fine".
* **Retrieval is cross-lingual.** A model can answer a French reader from an English page, so serving the right *language* matters less than it did — while the *data* on the page, which the model copies rather than translates, matters more.
* **Declarations beat negotiation.** `hreflang`, `lang`, `dir` and structured data are read as facts. They are the only channel by which an agent can know a locale variant exists.

For a localisation library the practical consequence is narrow and useful: **render locale-formatted values server-side, and publish a machine-readable form alongside the human one.**

## What each system actually does

| | Crawls JS | Language behaviour | Sends `Accept-Language` |
|---|---|---|---|
| **ChatGPT** (GPTBot, OAI-SearchBot, ChatGPT-User) | no | strong English bias in retrieval | yes — `en-US,en;q=0.9` observed |
| **Claude** (ClaudeBot, Claude-SearchBot, Claude-User) | no | not separately measured | **no** — verified directly |
| **Gemini** (Google-Extended) | **yes** | slightly favours local language | inherits Googlebot, which sends none |
| **Copilot** (Bing index) | via Bingbot | essentially neutral | n/a |
| **Grok** (xAI) | undocumented | undocumented | undocumented |

Two of those rows I checked myself rather than taking on trust.

**Claude sends no `Accept-Language` at all.** Fetching a header-echo endpoint through the agent I am running as returns exactly five headers — `Accept`, `Accept-Encoding`, `Host`, `User-Agent` (`Claude-User (claude-code/…)`), and an AWS trace id. There is no language preference in the request, so a site negotiating on the header serves this agent its default locale, whoever the reader is.

**ChatGPT's agent does send one**, per a [captured header dump](https://simonwillison.net/2025/Aug/4/chatgpt-agents-user-agent/): `Accept-Language: en-US,en;q=0.9`, alongside `Signature-Agent: https://chatgpt.com` and RFC 9421 message signatures. But note the value. It is the stock Chrome default, not evidence that a Japanese user's preference reaches the origin. Treating it as a real signal would be a mistake.

So the header is a dead end in both directions: absent from one major agent, and a fixed string in the other.

## The finding that matters most: no JavaScript

Joint analysis by [Vercel and MERJ](https://vercel.com/blog/the-rise-of-the-ai-crawler) across **more than 500 million GPTBot fetches found zero evidence of JavaScript execution**. The same holds for ClaudeBot, PerplexityBot, Bytespider and Meta's crawler. They will sometimes *download* JavaScript — ChatGPT in 11.5% of requests, Claude in 23.8% — and never run it. The only major exception is Google-Extended, which renders because it inherits Googlebot's infrastructure.

The volumes make this consequential rather than academic: GPTBot generated 569 million requests across Vercel's network in a month, Claude 370 million.

This connects directly to something the [measurement study](web-localization-measurement.md) found. IKEA's category pages carry a **single `€` character** in their served HTML; every price is written by JavaScript. Our browser-based probe could read them, and an HTTP probe could not. That is exactly the boundary an AI crawler sits on.

**IKEA's prices are invisible to every AI crawler except Gemini's.** Not mis-formatted — absent. The same is true of any site that formats its numbers, dates and currencies in the browser, which is the default for most modern component libraries.

A library that formats on the server and one that formats in the client are not equivalent choices any more.

## Cross-lingual retrieval changes what "localized" has to mean

AI systems retrieve and answer across languages, so the reader's language and the page's language are decoupled in a way they never were for search. Measured behaviour differs sharply by system: an analysis reported by [Search Engine Land](https://searchengineland.com/multilingual-websites-english-pages-ai-visibility-484251) found ChatGPT's retrieval fetches English pages **65–79% of the time** and cites English content about **2.6× more** than search demand would predict, while Copilot is essentially neutral and Google AI slightly favours local languages — the difference being that Copilot and Google AI inherit search indexes that have understood `hreflang` for years, whereas ChatGPT retrieves live into an English-centred model.

The same analysis found that adding an English version to a non-English site raised citations by 122% in ChatGPT, 52% in Copilot and 28% in Google AI.

Crawlers do fetch localized variants: GPTBot crawled all eleven language versions of an article in 61.5% of cases, PerplexityBot in 52.9%.

The consequence is not "stop localizing". It is that **the model will often read one language and answer in another**, and when it does, it carries the *numbers* across verbatim while translating the words around them. A price rendered `1,234.56` on an English page can be reported unchanged to a German reader for whom that string means one-point-two. Formatting errors that a human reader would catch and mentally correct are propagated by a model that has no reason to doubt them.

That is a genuinely new failure mode, and it raises the value of getting formats right rather than lowering it.

## Publish both forms: human and machine

There is an established mechanism for this and it is worth using deliberately.

Schema.org's [`price` documentation](https://schema.org/price) is explicit: use `.` as the decimal point, **"avoid using these symbols as a readability separator"**, use `priceCurrency` with an ISO 4217 code **"instead of including ambiguous symbols such as '$'"**, and use standard Unicode digits. It also shows the intended pattern — display `1,000.00` to the reader while `content="1000.00"` carries the unambiguous value.

So the two channels want opposite things, and both are correct:

| | Human-visible text | Machine-readable attribute |
|---|---|---|
| number | `1.234.567,89` (de-DE) | `1234567.89` |
| currency | `1 234,56 €` (fr-FR) | `content="1234.56"` + `priceCurrency="EUR"` |
| date | `22.03.26` (de-DE) | `<time datetime="2026-03-22">` |

This resolves the tension cleanly. Locale-correct presentation for the reader; unambiguous machine form for the parser. A page that publishes only the formatted string forces every consumer to guess a locale; one that publishes only the machine form is not localized at all.

It also explains a decision made during the measurement study: our number classifier deliberately **ignores JSON-LD**, because machine-format prices are always dot-decimal and counting them would have manufactured a large false error rate. The same property that makes structured data good for machines makes it useless as evidence of localisation quality.

## What the surveyed sites actually publish

The 54 sites from the measurement study were re-inspected in a browser to see what structured data they carry. A browser rather than an HTTP fetch, because JSON-LD lives in `<script>` tags — which `innerText` excludes, so the earlier runs never captured it — and because markup injected by JavaScript is invisible to a plain fetch.

Five of the 54 served challenge screens and are excluded. Of the **49 pages that genuinely loaded**:

| | sites | |
|---|---|---|
| JSON-LD present | **29** | 59% |
| microdata (`itemscope`) | 4 | |
| RDFa | 0 | |
| JSON-LD that fails to parse | **0** | |

Adoption is real, and the markup is well-formed. But look at *what* is described:

| schema.org type | sites |
|---|---|
| `Organization` | 17 |
| `WebSite` | 12 |
| `WebPage` | 11 |
| `SearchAction` | 7 |
| `ContactPoint`, `PostalAddress`, `BreadcrumbList` | 6 each |

That is **identity markup**. It tells a machine who the company is, where its offices are, and how to search the site. Almost none of it describes the meaning of a value on the page.

The machine-readable partner of a formatted value is close to absent:

| | sites | who |
|---|---|---|
| `<time datetime>` | **2 / 49** | `european-union.europa.eu`, `debian.org` |
| schema `inLanguage` | **6 / 49** | Samsung, Disney+, HSBC, PayPal, Avis, worldbank.org |
| `priceCurrency` | **1 / 49** | Salesforce |

The two sites publishing machine-readable dates are a public institution and a volunteer Linux distribution. No commercial brand in the survey does it.

**One caveat, stated because it matters:** these are landing pages, and landing pages rarely price anything, so `priceCurrency` at 1 of 49 understates commercial adoption — product pages would score better. `<time datetime>` and `inLanguage` carry no such excuse: both apply to any page, and both are near-zero.

So the picture is not that sites reject structured data. 59% publish it, and none of it is malformed. They publish it about **themselves** and not about **their content** — which means the values an LLM would most benefit from disambiguating are exactly the ones left as formatted strings, to be interpreted by guesswork.

### Measured again, fairly, on pages that do show a price

Landing pages rarely price anything, so the survey was repeated against the **244 pages the audit had already found displaying a price** — selected precisely because a human can see a number on them. All 244 loaded cleanly.

| | pages | |
|---|---|---|
| JSON-LD present | 204 / 244 | **84%** |
| `Offer` markup | 19 / 244 | **8%** |
| `priceCurrency` | 19 / 244 | **8%** |
| a published price value | 19 / 244 | **8%** |

Eighty-four per cent of these pages publish structured data. Eight per cent publish the price that is visibly printed on them. The gap is not adoption — it is *what* gets described.

| site | pages showing a price | of those, publishing it |
|---|---|---|
| `samsung.com` | 41 | 4 |
| `airbnb.com` | 33 | **0** |
| `ikea.com` | 33 | 1 |
| `apple.com` | 27 | 7 |
| `microsoft.com` | 25 | 1 |
| `dell.com` | 24 | **0** |
| `ibm.com` | 7 | 5 |

Airbnb publishes JSON-LD on all 33 and a price on none. Dell, 23 of 24 and none.

### A hypothesis that turned out to be wrong

The obvious failure mode to look for was locale formatting leaking into the structured data — a site writing `"price": "1.234,56"` where schema.org requires `1234.56`, which a parser would read as one-point-two. It is exactly the mistake a single shared formatter would cause.

**It did not happen once.** Of the 19 pages publishing a price, all 19 use the machine format correctly, across EUR, NZD, SGD, BRL, INR, USD, IDR and CNY:

| site | published | currency |
|---|---|---|
| `apple.com` | `1399`, `4763.98` | EUR |
| `apple.com` | `15999`, `47698.8` | BRL |
| `lenovo.com` | `143991.00` | INR |
| `samsung.com` | `2479`, `2679` | EUR |
| `ikea.com` | `6.99` | EUR |

That is a useful negative result. **Teams that publish machine-readable prices get the format right**; the schema.org guidance is clear enough and the tooling evidently follows it. The problem is not corruption of the machine channel, it is that the channel is mostly empty.

It also sharpens what a library should offer. A dual-output helper is not needed to *prevent* a formatting mistake — that mistake is not being made. It is needed to make the machine form cheap enough that the other 92% emit it at all.

## Guidance

Seven items, in rough order of impact.

**1. Render locale-formatted values on the server.** Client-side formatting is invisible to every AI crawler except Gemini's. This is the highest-impact item and it is not primarily a localisation decision — but localisation is where it bites hardest, because prices, dates and quantities are exactly what gets formatted late.

**2. Publish `hreflang`, and publish it correctly.** It is the only way an agent learns that a locale variant exists, and it is consumed as a declaration rather than negotiated. The [measurement study](web-localization-measurement.md) found real brands shipping `es-SP`, `sq-KS`, `tc` and `es_MX`; each is silently ignored, so the site reads as having no variants at all.

**3. Emit both forms.** Locale-formatted text for the reader, machine-readable attributes for the parser — `<time datetime>`, `content=` on prices, `priceCurrency` in ISO 4217. This is the widest open gap measured: of 244 pages visibly showing a price, 84% publish structured data and 8% publish the price. Those that do publish it get the format right, so the barrier is effort, not knowledge.

**4. Set `lang` correctly, and `dir` with it.** A model reading a page needs to know what language it is reading; `lang` is how it is told. The study found 3.5% of self-declared variants serving a `lang` that contradicts their own declaration, and nearly a quarter of right-to-left variants setting direction in CSS where a parser cannot see it.

**5. Do not rely on `Accept-Language`.** One major agent sends none; the other sends a constant. This was already true for search crawlers and remains true.

**6. Do not auto-redirect by IP.** Google has long advised against it, and it is worse with agents: a crawler arriving from a US datacentre gets bounced to the US variant and never sees the others. The study found 53 declared variants that redirect out of their own declared path — those declarations are worthless to a crawler that follows them.

**7. If you publish `llms.txt`, publish one per locale.** The emerging convention is `/en/llms.txt`, `/de/llms.txt`, because the file contains URLs and those differ per variant. Note that the LLM-era convention has reproduced per-locale URLs rather than negotiation — the same shape search arrived at.

## What this means for the Localize family

The earlier conclusion — that the negotiation battle was lost and the leverage lay downstream of routing — survives this research and is sharpened by it.

* **Server-side formatting is now a discoverability feature, not only a correctness one.** Localize formats on the server by construction. That is worth saying plainly in the guides, because the alternative silently removes a site's numbers from every AI crawler but one.
* **`hreflang` correctness is higher-value than it looked.** Validated, canonical annotations are how an agent discovers variants at all. This is implemented in `Localize.HTML.Hreflang`.
* **A dual-output story is missing, and nobody else has one either.** Of 244 pages showing a price, 8% publish it machine-readably — and every one that does gets the format right. The barrier is that emitting the second form is a separate, easily-forgotten step. Localize renders the human form well. It has no first-class way to emit the machine-readable partner — a formatted price and its `content="1234.56"`, a formatted date and its `datetime="2026-03-22"`. That is a concrete gap, it sits naturally in `localize_web`, and schema.org has already specified what the machine form should look like.
* **`lang` and `dir` belong together in whatever emits the document element**, for the same reason as before, with the added one that a parser reads them.

The dual-output helpers are the clearest new work this research suggests: everything else is either already done or already recommended.

## Sources

* [The rise of the AI crawler — Vercel](https://vercel.com/blog/the-rise-of-the-ai-crawler)
* [ChatGPT agent's user-agent — Simon Willison](https://simonwillison.net/2025/Aug/4/chatgpt-agents-user-agent/)
* [Should multilingual websites add English pages for AI visibility? — Search Engine Land](https://searchengineland.com/multilingual-websites-english-pages-ai-visibility-484251)
* [schema.org `price`](https://schema.org/price)
* [Anthropic clarifies what its three web crawlers do — PPC Land](https://ppc.land/anthropic-clarifies-what-its-three-web-crawlers-do-and-how-to-block-them/)
* [Anthropic's Claude Bots Make Robots.txt Decisions More Granular — Search Engine Journal](https://www.searchenginejournal.com/anthropics-claude-bots-make-robots-txt-decisions-more-granular/568253/)
* [Meet llms.txt, a proposed standard for AI website content crawling — Search Engine Land](https://searchengineland.com/llms-txt-proposed-standard-453676)
* [Creating a Scalable International llms.txt Structure — Rebelytics](https://www.rebelytics.com/creating-a-scalable-international-llms-txt-structure-step-by-step/)
* [Grok Crawlers Explained — Menra](https://www.menra.ai/guides/grok-crawler-guide)
* [How Google Crawls Locale-Adaptive Pages — Google Search Central](https://developers.google.com/search/docs/specialty/international/locale-adaptive-pages)
