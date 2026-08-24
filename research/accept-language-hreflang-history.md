# What `Accept-Language` and `hreflang` were for

**Researched 2026-08-24.** Background to [web-localization-measurement.md](web-localization-measurement.md), which measured that roughly 11% of major commercial sites honour `Accept-Language`, and to [why-sites-geolocate.md](why-sites-geolocate.md), which explains why. This document asks what the two mechanisms were originally *for*, because the distance between the design and the practice turns out to be the most instructive part of the story.

The short version: **both were built to serve the reader, and both now address a crawler.** And the specification that introduced `Accept-Language` named, in 1999, every one of the four reasons the industry would go on to abandon it.

## `Accept-Language`: the spec predicted its own failure

`Accept-Language` is part of HTTP's *server-driven content negotiation* — the idea that one URL identifies a resource which may have several representations, and the server picks the one that best suits the requester. The reader states a preference once, in their user agent, and every server they visit honours it.

[RFC 2616 §12](https://www.w3.org/Protocols/rfc2616/rfc2616-sec12.html) sets out when this is a good idea: server-driven negotiation is advantageous "when the algorithm for selecting from among the available representations is difficult to describe to the user agent, or when the server desires to send its 'best guess'" and so avoid a round trip.

Then it lists the disadvantages. All four are worth quoting, because each one became a reason sites stopped doing it.

> **"It is impossible for the server to accurately determine what might be 'best' for any given user, since that would require complete knowledge of both the capabilities of the user agent and the intended use for the response."**

The header reports the browser's UI language, not a considered preference. A Spanish speaker on a machine that shipped with `en-US` sends `en-US`. The spec conceded the point before the practice existed.

> **"Having the user agent describe its capabilities in every request can be both very inefficient (given that only a small percentage of responses have multiple representations) and a potential violation of the user's privacy."**

This is, precisely, [Chrome's Accept-Language reduction](https://github.com/explainers-by-googlers/reduce-accept-language) — a project to cut the header to a single language because it "contains a lot of entropy" that servers can "passively capture without the user's awareness". Twenty-five years between the warning and the mitigation.

> **"It complicates the implementation of an origin server and the algorithms for generating responses to a request."**

Correct matching is [RFC 4647](https://www.rfc-editor.org/rfc/rfc4647.html) — priority lists, quality weights, basic filtering versus lookup, prefix matching. Mature libraries still ship bugs in it.

> **"It may limit a public cache's ability to use the same response for multiple user's requests."**

This is CDN cache fragmentation. `Vary: Accept-Language` makes the cache key include the header, and browsers send many distinct values, so one page becomes dozens of cached objects. It is the reason **no commercial site in our survey emits `Vary: Accept-Language`** — including the four that vary on the header.

Four disadvantages, four causes of death. The specification was not naive about the mechanism; the industry simply resolved every trade-off the same way.

### The alternative nobody took

RFC 2616 also describes *agent-driven* negotiation, where the server returns a list of available representations and the **client** chooses. The spec recommends it "when the response would vary over commonly-used dimensions (such as type, language, or encoding), when the origin server is unable to determine a user agent's capabilities," and where public caches are involved — which is to say, in exactly the circumstances that defeated the server-driven form.

It never happened. The elaborated version, Transparent Content Negotiation, was published as an Experimental RFC and went nowhere. Hold that thought.

## `hreflang`: an advisory hint for the reader's software

`hreflang` is older than the use it is now put to, and was designed for something else entirely.

[HTML 4.0](https://www.w3.org/TR/1998/REC-html40-19980424/struct/links.html), December 1997, defines it in one sentence:

> "This attribute specifies the base language of the resource designated by href and may only be used when href is specified."

It is an attribute of a *link* — `<a>` and `<link>` — and it is **advisory**. It describes what is at the other end of a hyperlink, before you follow it. The specification is explicit about who benefits and why:

> "Armed with this additional knowledge, user agents should be able to avoid presenting 'garbage' to the user. Instead, they may either locate resources necessary for the correct presentation of the document or, if they cannot locate the resources, they should at least warn the user that the document will be unreadable and explain the cause."

The intended consumer is **the reader's own software**. A browser that knows a link leads to Japanese can load the font, or say plainly that it cannot render it. The mechanism serves the person about to click.

### 2010: repurposed for a crawler

In September 2010 Google introduced [`rel="alternate" hreflang="x"`](https://searchengineland.com/google-adds-a-new-webmaster-annotation-for-multilingual-multinational-sites-155134) as a page-level annotation. The problem it addressed was Google's, not the reader's: near-duplicate pages across language variants confusing the index. The stated benefit was that Google could "display the correctly localized variant of your URL to our international users" — English speakers get `en.example.com`, French speakers `fr.example.com`.

Annotations for clusters followed in December 2011, and sitemap-based annotation in May 2012.

The attribute did not change. Its audience did. `hreflang` stopped being a hint from an author to a reader's browser and became a declaration from a site to a search engine — and, per our measurement, the large brands now publish it almost exclusively in **sitemaps**, a channel no browser reads at all. PayPal declares 274 locale variants and not one of them in a page a person might load.

## How far we have moved

| | designed for | consumed by, in practice |
|---|---|---|
| `Accept-Language` | the reader's stated preference reaching every server | ~11% of commercial sites; browsers now reducing it for privacy |
| `hreflang` | the reader's browser, deciding how to render a link | search-engine crawlers, largely via sitemaps |

Both mechanisms were addressed to the person using the web. Both are now addressed to machinery that indexes it. The reader's preference, which `Accept-Language` exists to carry, is discarded by roughly nine sites in ten — and where a site does adapt, it adapts to the reader's **IP address**, a signal the reader cannot set, cannot see, and frequently cannot correct.

The measurement puts numbers on the drift: **48.6% of commercial sites vary on IP and 10.8% on the header**, and of the sites that publish `hreflang`, **6% of declarations point at a URL that redirects out of its own declared locale** — an annotation maintained for a crawler, not verified by anyone, and wrong.

## The alternatives were proposed. Twice. Both stalled.

The obvious repair — keep locale negotiation, remove the passive fingerprinting surface — has been attempted, and the attempts are instructive because they failed in different ways.

### `Sec-CH-Lang`: make it opt-in

[WICG/lang-client-hint](https://github.com/WICG/lang-client-hint), titled "Wouldn't it be nice if `Accept-Language` was a client hint?", states the problem in the same terms RFC 2616 did: the header "exposes quite a bit of entropy to the web at large, even though a small subset of sites I visit will actually use the information."

Its proposal is to invert the default. A `Sec-CH-Lang` header would be sent only to servers that ask for it via `Accept-CH`, over secure transport only, with browsers deprecating and eventually **removing** `Accept-Language` — locking it to a generic geolocation-derived value as an intermediate step. Preferences stay off the wire for every site that has not declared a use for them.

It did not advance. The author describes it as "not a proposal that's well thought out" but "a collection of interesting ideas for discussion", and **the repository was archived on 21 February 2023**.

### HTTP `Variants`: make it cacheable

[draft-ietf-httpbis-variants](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-variants), worked on between 2017 and 2019, addresses the fourth of RFC 2616's disadvantages directly: it makes proactive negotiation cache-friendly by having the origin enumerate the representations available for a resource in a `Variants` response header, with a companion `Variant-Key` naming the one selected.

Look at what that is. The server publishes **a list of available representations** and the cache — or the client — selects among them. That is RFC 2616's *agent-driven* negotiation, the alternative the specification recommended and the web declined, resurfacing twenty years later under a different name. It has not shipped either.

### `locale-extensions`: everything language is not

[ben-allen/locale-extensions](https://github.com/ben-allen/locale-extensions) is the most interesting of the three, because it concerns preferences `Accept-Language` was never able to carry: **numbering system, hour cycle, first day of week, calendar system and temperature unit**. Its motivating examples are a Dutch person in the United States who wants a 24-hour clock, and an English speaker who wants Celsius — readers whose language is one thing and whose formatting preferences are another, which is precisely the population the language header cannot serve.

Those five are the CLDR `-u-` extension subtags `nu`, `hc`, `fw`, `ca` and `mu`, which Localize already parses into `Localize.LanguageTag.U`.

Its privacy design is worth noting because it is the sharpest answer yet to the 1999 warning: preferences are exposed one at a time rather than as a block, values are restricted to common defaults consistent with the user's `Accept-Language`, headers carry the `Sec-` prefix so scripts cannot read them, and a server requesting a preference it has no use for becomes **detectable** rather than passively harvested.

### What about putting the locale in the URL?

A query parameter — `?locale=de-AT`, supplied by the browser — would answer the caching objection outright, since the URL is already the cache key and no `Vary` is required. It would also be visible to the reader, correctable by them, and shareable.

No such proposal appears to exist, and the client-hint document does not consider URL-based approaches at all. The reasons are not hard to guess: a browser rewriting URLs breaks URL identity and anything that signs or verifies them; the parameter would leak into referrers, server logs and shared links, which is arguably a worse privacy position than the header; it does nothing for subresources; and it manufactures the duplicate-URL problem that `canonical` and `hreflang` exist to resolve.

**But the web adopted the idea regardless — as a path segment, chosen by the site rather than the browser.** `/de-at/`, `/befr/`, `/us-es/` are the locale in the URL. Cache-friendly, visible, shareable, and carrying no fingerprinting surface at all. Everything the parameter would have achieved, arrived at from the other end.

What is missing is only the half a browser could supply: a way for the reader's stated preference to *select* among the variants a site publishes, without a header that follows them everywhere. That is `Variants`. That is agent-driven negotiation. That is the thing the specification recommended in 1999, proposed again in 2017, and still nobody has shipped.

## The turn that might close the loop

There is one genuinely hopeful reading, and it comes from the alternative RFC 2616 offered and the web declined.

**Agent-driven negotiation is what an LLM agent does.** A retrieval agent fetching on a reader's behalf is exactly the client the spec imagined: it can be handed a list of available representations and choose among them, on behalf of a user whose language it actually knows. And the list already exists — `hreflang` *is* a machine-readable enumeration of a resource's representations, which is what agent-driven negotiation requires and what the server-driven form never provided.

The pieces are in place and pointed the right way for the first time since 1997 — and, as the section above records, the protocol machinery for it has been specified twice. What is missing is that the agents do not yet use any of it: as measured in [localization-for-llms.md](localization-for-llms.md), one major agent sends no `Accept-Language` at all and another sends a fixed `en-US,en;q=0.9`, and none is known to follow `hreflang` to select a variant.

So the position is that the mechanism designed for the reader, abandoned for the crawler, could plausibly return to serving the reader — through the annotation that was itself repurposed away from them. Whether it does is not something a localisation library controls. What a library can do is make sure that when an agent looks, the declarations are correct, complete, and machine-readable — which is the argument the rest of this research arrives at from a different direction.

## Sources

* [RFC 2616 §12: Content Negotiation](https://www.w3.org/Protocols/rfc2616/rfc2616-sec12.html)
* [HTML 4.0 Specification, §12 Links](https://www.w3.org/TR/1998/REC-html40-19980424/struct/links.html)
* [Google Adds A New Webmaster Annotation For Multilingual & Multinational Sites — Search Engine Land, 2010](https://searchengineland.com/google-adds-a-new-webmaster-annotation-for-multilingual-multinational-sites-155134)
* [Multilingual and multinational site annotations in Sitemaps — Google, 2012](https://developers.google.com/search/blog/2012/05/multilingual-and-multinational-site)
* [Reduce fingerprinting in the Accept-Language header](https://github.com/explainers-by-googlers/reduce-accept-language)
* [RFC 4647: Matching of Language Tags](https://www.rfc-editor.org/rfc/rfc4647.html)
* [RFC 3282: Content Language Headers](https://datatracker.ietf.org/doc/rfc3282/)
* [RFC 2295: Transparent Content Negotiation in HTTP](https://www.rfc-editor.org/rfc/rfc2295)
* [WICG/lang-client-hint — `Sec-CH-Lang`](https://github.com/WICG/lang-client-hint) (archived 2023)
* [draft-ietf-httpbis-variants: HTTP Representation Variants](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-variants)
* [ben-allen/locale-extensions](https://github.com/ben-allen/locale-extensions)
