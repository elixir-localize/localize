# `localize_research_probe` — a repeatable global localization probe

**Status: plan, for review. Nothing built.** Drafted 2026-08-21.

## What this is for

[The Accept-Language study](../research/accept-language-honouring.md) found 17 of 18 global brands ignoring the header, but from **one vantage point** — Sydney. It could prove the header is ignored; it could not prove what those sites serve to someone in Germany, or Japan, or Israel, because the request never came from there.

This harness closes that gap: the same probe, run from many countries at once, so IP geolocation and `Accept-Language` can be varied independently and their effects separated.

### Research questions

1. **Does the site honour `Accept-Language`?** Same IP, different header — does the response change?
2. **Does it geolocate instead?** Same header, different country — does the response change?
3. **When the two conflict, which wins?** A German IP asking for `en-AU` is the case that motivated the original claim.
4. **Does it advertise `Vary: Accept-Language`?** If it varies but does not say so, CDNs will serve one visitor's language to another.
5. **What conventions does the delivered page actually use?** Not just *which language* — the number grouping, decimal separator, date order, time cycle, and digit set in the rendered page.

Question 5 is the one no existing study answers, and the one closest to what Localize is for.

## Provider: AWS Lambda

Checked rather than assumed, on 2026-08-21:

| Option | Regions | Free tier | Verdict |
|---|---|---|---|
| **AWS Lambda** | **42** | **1M requests + 400K GB-s/month, permanent, every region** | **chosen** |
| Fly.io | 17 | **none** — free allowances removed in 2024 | rejected |
| Google Cloud Run | ~40 | free tier is **us-central1/us-east1/us-west1 only** | rejected |
| Cloudflare Workers | 300+ PoPs | generous | rejected — a Worker cannot be pinned to a region, so egress geography is not controllable |

Fly is the incumbent and the lowest-friction, but 17 regions cover only about six non-English language areas, and there is no longer a free tier to prefer it for. Cloud Run's free tier is US-only, which defeats the purpose. Cloudflare has the most PoPs and the least control — the thing this experiment needs most.

Lambda's always-free allowance is **per month, in every region, permanently**, and a full probe run is a few thousand requests. The expected bill is **$0**.

### Language coverage this buys

Commercial regions, excluding the GovCloud and China partitions which need separate accounts:

| Language area | Region | Why it matters here |
|---|---|---|
| Japanese | `ap-northeast-1` (Tokyo) | era-capable calendar, distinct date order |
| Korean | `ap-northeast-2` (Seoul) | |
| Chinese (Traditional) | `ap-east-1` (Hong Kong) | |
| Thai | `ap-southeast-7` | **Buddhist calendar — year 2569, not 2026** |
| Hebrew | `il-central-1` (Tel Aviv) | **RTL, Hebrew calendar** |
| Arabic | `me-central-1` (UAE), `me-south-1` (Bahrain) | **RTL, Arabic-Indic digits** |
| Hindi | `ap-south-1` (Mumbai) | Indian digit grouping (12,34,567) |
| Indonesian / Malay | `ap-southeast-3`, `ap-southeast-5` | |
| German | `eu-central-1` (Frankfurt) | the original Hertz/Microsoft claim |
| French | `eu-west-3` (Paris), `ca-central-1` (Montreal) | fr-FR vs fr-CA divergence |
| Spanish | `eu-south-2` (Spain), `mx-central-1` (Mexico) | es-ES vs es-MX divergence |
| Italian | `eu-south-1` (Milan) | |
| Swedish | `eu-north-1` (Stockholm) | |
| Portuguese | `sa-east-1` (São Paulo) | |
| English variants | `us-east-1`, `eu-west-2` (London), `eu-west-1` (Ireland), `ap-southeast-2` (Sydney), `af-south-1` (Cape Town) | en-US / en-GB / en-IE / en-AU / en-ZA |

Roughly **20 language areas against Fly's 6**, and it includes the three calendar systems and two RTL scripts that make the strongest case for the library.

Many of these are **opt-in regions** that must be enabled per account — see setup.

## Architecture

Deliberately boring. Three pieces, no server to keep running.

```
  localize_research_probe/            an Elixir escript + a Lambda payload
  ├── probe/                          the code that runs IN each region
  ├── lib/                            orchestration, run from Kip's laptop
  ├── priv/targets/*.exs              target lists, versioned
  └── priv/runs.sqlite3               results, one row per observation
```

**The probe** is a single self-contained Lambda function, identical in every region. It takes a list of targets and header variants, makes the requests, and returns structured observations as JSON. It holds no state and writes nothing.

**The orchestrator** is an Elixir escript on the laptop. It deploys the function to N regions, invokes them in parallel, collects the JSON, and writes to SQLite. One command, no dashboard, no queue.

**Storage** is a local SQLite file, committed or not as we choose. Every run is timestamped and every observation carries the run id, so runs are comparable over time and nothing is overwritten.

### Why not a persistent service

Nothing needs to be listening. A run is: create, invoke, collect, delete. Between runs the AWS footprint is a handful of Lambda functions costing nothing, or nothing at all if we tear them down. That is what makes "repeatable" cheap.

## What each probe measures

For every (target × region × header variant):

| Field | How |
|---|---|
| final URL after redirects | follow, record the chain |
| HTTP status | |
| `Content-Language` | response header |
| `Vary` contains `accept-language` | response header |
| `<html lang="…">` | parsed from the body |
| declared charset, `dir="rtl"` | parsed |
| **number formatting found in the page** | regex for grouped numerals; record the separator **codepoints**, since U+202F and U+00A0 are visually identical and locale-distinguishing |
| **date formatting found** | regex for common date shapes; record order and separator |
| **digit set** | detect Arabic-Indic, Devanagari, Thai digits vs Latin |
| currency symbol / code present | |
| body hash | to detect change without storing pages |
| response time | |
| probe region, egress IP, and its geolocation | so the *observed* country is recorded, not assumed |

That last row matters: we record what the target *could* have seen, rather than trusting that a Frankfurt Lambda looks German to a GeoIP database.

### Header variants per target

At minimum: `en-AU`, `de-DE`, `ja-JP`, `ar-SA`, and **no header at all**. The no-header case is the control that isolates pure geolocation.

## Data model

One table for runs, one for observations, one for targets. Denormalised enough to query without joins for the common questions.

```sql
CREATE TABLE runs (
  id INTEGER PRIMARY KEY,
  started_at TEXT NOT NULL,      -- ISO 8601 UTC
  finished_at TEXT,
  target_set TEXT NOT NULL,      -- filename + git sha of the target list
  probe_version TEXT NOT NULL,   -- so a probe change is visible in the data
  notes TEXT
);

CREATE TABLE observations (
  id INTEGER PRIMARY KEY,
  run_id INTEGER NOT NULL REFERENCES runs(id),
  target TEXT NOT NULL,          -- "www.hertz.com"
  region TEXT NOT NULL,          -- "eu-central-1"
  egress_ip TEXT,
  egress_country TEXT,           -- resolved, not assumed
  accept_language TEXT,          -- NULL for the no-header control
  status INTEGER,
  final_url TEXT,
  content_language TEXT,
  vary_accept_language INTEGER,  -- 0/1
  html_lang TEXT,
  dir TEXT,
  digit_set TEXT,                -- latn | arab | deva | thai | …
  number_sample TEXT,            -- the first grouped number found, verbatim
  date_sample TEXT,
  currency_sample TEXT,
  body_sha256 TEXT,
  elapsed_ms INTEGER,
  error TEXT
);
```

The questions then answer themselves in SQL: *honours the header* is "same region, different `accept_language`, different `html_lang`"; *geolocates* is "same `accept_language`, different `region`, different `html_lang`".

## Autonomous run lifecycle

One command, `mix probe.run`, doing:

1. **Provision** — ensure the IAM execution role exists; deploy or update the function in each configured region. Idempotent: a second run redeploys only what changed.
2. **Invoke** — call every region in parallel, passing the target list and header variants.
3. **Collect** — gather JSON responses; retry a region once on failure, then record the failure rather than losing the run.
4. **Store** — write one `runs` row and N `observations` rows.
5. **Teardown** (optional, `--teardown`) — delete the functions. Off by default, since redeploying is slower than leaving them idle at zero cost.

`mix probe.report` then answers the research questions from SQLite, and `mix probe.diff <run_a> <run_b>` shows what changed between runs.

## Targets

Versioned in `priv/targets/`, so a run records which list it used. Starting set, to be finalised:

* **Travel / hospitality** — Hertz, Booking.com, Airbnb, Lufthansa, Marriott
* **Retail / e-commerce** — Amazon, IKEA, Zara, H&M, Nike, Samsung
* **SaaS / platform** — Microsoft, Adobe, Atlassian, Shopify, Stripe, Salesforce, Zoom
* **Media / streaming** — Netflix, Spotify
* **Controls** — Debian, MDN, GNU. Known to honour the header; if they stop varying, the harness is broken, not the world.

The controls are not optional. Without them, "everything ignores the header" is indistinguishable from a bug in the probe.

## Validity threats

Stated up front, because they bound what the results can claim.

* **Cloud IPs are not residential IPs.** A site may geolocate an AWS range correctly and still treat it differently — bot rules, CAPTCHA, or a generic edge response. Mitigation: record status codes and detect challenge pages explicitly; treat a challenged response as *no observation*, not as evidence.
* **Opt-in regions must be enabled** or the run silently covers less ground. The orchestrator should verify enabled regions at start and refuse to run partially without saying so.
* **Politeness.** A handful of requests per target per run, sequential within a region, with a delay. This is comparable to a person browsing, not a crawl. Respect `robots.txt` for anything beyond the landing page.
* **Landing pages only.** Deeper pages may behave differently; the study should not generalise beyond what it fetched.
* **Point-in-time.** Sites change. Every observation is timestamped and the report says so.

## Cost

Lambda: within the permanent free allowance. A run of 25 targets × 20 regions × 5 header variants is 2,500 invocations against a monthly allowance of 1,000,000.

Data transfer out of Lambda is the only line that could bill, and it is a few MB per run. **Expected: $0** for the HTTP-only tier. Adding rendering brings a container registry and object storage — see [§Screenshots](#screenshots-and-rendered-pages) — which lands at **a dollar or two a month**. A budget alarm is part of setup regardless.

## What Kip needs to do

Detailed separately. In short: create an AWS account choosing the **Paid Plan** (not the "Free Plan", which auto-closes the account after six months), enable the opt-in regions, create a least-privilege IAM user, and drop its keys in `.env`.

## Screenshots and rendered pages

**Feasible, and worth doing — but for a methodological reason, not a visual one.**

### Why it matters more than it looks

The existing study carries a stated limitation: *"Several sites ship no `<html lang>` on the landing page and may set locale client-side."* A `curl`-based probe cannot see that. A site that fetches its locale in JavaScript, or re-renders after hydration, looks identical to one that ignores the header — and would be recorded as "ignores" when it may honour it perfectly well in a browser.

That is a real threat to the *existing* findings, not a cosmetic gap. Rendering the page closes it: whatever the user would see is what gets measured. Screenshots are then a by-product of the thing that fixes the methodology.

They are also the most persuasive artefact available. The HTML input study turned on a single screenshot showing six `lang` values rendering identically; nothing in a table carried the same weight.

### What it costs

Headless Chromium does not fit a zip-packaged Lambda, so this needs a **container image** — which changes three things:

| | HTTP-only probe | Rendering probe |
|---|---|---|
| Packaging | zip, a few hundred KB | container image, ~700 MB |
| Memory | 128 MB | 1536 MB |
| Per page | ~0.5 s | ~4 s warm, ~8 s cold |
| Registry | none | **ECR repository per region** |
| Screenshot transport | n/a | **S3** — Lambda's synchronous response caps at 6 MB |

Arithmetic for a 25-target × 20-region × 5-variant run, batching each region into one invocation:

* **Compute**: 20 × 500 s × 1.5 GB = **15,000 GB-s**. The free allowance is 400,000 GB-s per month *aggregated across all regions*, so roughly **26 full rendering runs per month at no charge**.
* **ECR storage**: at ten Tier 2 regions, ~7 GB at $0.10/GB/month ≈ **$0.70/month**. Twenty would be ~$1.40.
* **S3**: 2,500 screenshots per run at ~150 KB ≈ 375 MB. Storage and PUTs together are **cents per run**.

So the honest figure is **a dollar or two a month**, not $0 — the container registry is the line item, and it is charged whether or not a run happens. Tearing down between studies removes it.

### Recommended shape: two tiers

Do not make every probe a browser.

* **Tier 1 — HTTP probe, every region, every run.** Zip-packaged, 128 MB, genuinely free. Answers the header/geolocation/`Vary` questions at full breadth, fast.
* **Tier 2 — rendering probe, a chosen subset.** Container image, capturing a screenshot plus the *post-JavaScript* DOM: `html lang`, `dir`, digit set, and the rendered number and date samples.

### Tier 2 regions

Chosen for script and calendar diversity rather than population, since script drives digit set, direction and calendar — the things Localize exists to get right.

| Language | Region | Script | Why this one |
|---|---|---|---|
| English (control) | `us-east-1` | Latin | baseline; the locale most sites default to |
| German | `eu-central-1` Frankfurt | Latin | the original Hertz/Microsoft claim |
| French | `eu-west-3` Paris | Latin | `fr-FR` vs `fr-CA` divergence |
| Spanish | `eu-south-2` Spain | Latin | `es-ES` vs `es-MX` divergence |
| Japanese | `ap-northeast-1` Tokyo | Kana/Kanji | era calendar |
| Korean | `ap-northeast-2` Seoul | Hangul | |
| Chinese | `ap-east-1` Hong Kong | Han (Traditional) | see caveat below |
| Thai | `ap-southeast-7` | Thai | **Buddhist calendar, Thai digits** |
| Hebrew | `il-central-1` Tel Aviv | Hebrew | **RTL, Hebrew calendar** |
| Arabic | `me-central-1` UAE | Arabic | **RTL, Arabic-Indic digits** |
| Spanish (MX) | `mx-central-1` Mexico | Latin | pairs with Spain — see below |
| French (CA) | `ca-central-1` Montreal | Latin | pairs with Paris — see below |

Twelve regions. ECR storage lands around **$0.84/month**.

#### The two divergence pairs

`es-ES`/`es-MX` and `fr-FR`/`fr-CA` are the sharpest test in the whole design, because they hold language constant and vary only region. A site can plausibly claim it "supports Spanish" while serving `es-ES` conventions to Mexico, and the difference is not cosmetic:

All values below are `Localize` output for `1234567.89` and `2026-03-22`, executed rather than recalled.

| | `es-ES` | `es-MX` |
|---|---|---|
| number | `1.234.567,89` | `1,234,567.89` |
| short date | `22/3/26` | `22/03/26` |
| currency | `1.234.567,89 €` (U+00A0 before €) | `$1,234,567.89` |

| | `fr-FR` | `fr-CA` |
|---|---|---|
| number | `1␣234␣567,89` — grouping is **U+202F** | `1␣234␣567,89` — grouping is **U+00A0** |
| short date | `22/03/2026` | `2026-03-22` |
| currency | `1␣234␣567,89 €` | `1␣234␣567,89 $` |

Spanish inverts the **decimal separator**: `1.234.567,89` in Spain is `1,234,567.89` in Mexico, so a figure reading as a million and a bit in one reads as one-point-two in the other if the separators are taken at face value. It also differs in day zero-padding.

French-Canadian keeps the same separators as France but flips the **date to ISO order** and moves the currency symbol — and, more subtly, uses a **different grouping space**: France groups with U+202F NARROW NO-BREAK SPACE, Canada with U+00A0 NO-BREAK SPACE. Two characters that look identical and are not, which is precisely why the probe records separator codepoints rather than rendering them.

Because the pair members share a language, they also isolate the question cleanly: if a site serves identical output to Madrid and Mexico City with identical headers, it is geolocating to *language* and not to *locale* — a finer-grained failure than the one the original study measured, and one nobody has quantified.

### Two requested locales have no AWS region

Verified against the published AWS IP ranges on 2026-08-21, not assumed:

* **Polish — no AWS region exists.** AWS's entire European footprint is Ireland, London, Paris, Frankfurt, Zurich, Milan, Spain, Stockholm and the EU Sovereign Cloud in Germany. There is an edge location in Warsaw but no region to run compute in.
* **Russian — no AWS region exists**, and no major Western cloud has one.

* **Chinese is partial.** `cn-north-1` and `cn-northwest-1` exist but sit in the **China partition**: a separate account, a Chinese legal entity and an ICP licence. Effectively out of reach. `ap-east-1` (Hong Kong) gives a China-adjacent IP and Traditional Chinese, which is not the same thing as a mainland Simplified-Chinese vantage point, and the report must say so.

### The gap is narrower than it looks

The two dimensions separate cleanly:

* **The header axis needs no matching IP.** `Accept-Language: ru-RU` and `pl-PL` can be sent from any region, so "does this site honour Russian?" is fully testable. Add both to the header variants regardless.
* **Only the geolocation axis needs a local IP.** What is lost is narrowly "what does a *Russian or Polish IP* get" — worth stating as a limitation, not worth redesigning around.

**Decided: AWS only.** Google Cloud has `europe-central2` in Warsaw and could cover Polish geolocation, but a second provider adapter for one locale is not worth the complexity. Recorded here so the option is known rather than overlooked; Russia has no equivalent answer on any provider.

### Does this cover the world's language groupings?

Close, with one real hole. By **script family**, which is the axis that matters for formatting:

| Script | Covered? |
|---|---|
| Latin | ✓ many |
| Han | ✓ Traditional (HK); Simplified header-only |
| Kana/Kanji, Hangul, Thai, Devanagari | ✓ |
| Arabic, Hebrew | ✓ both RTL |
| **Cyrillic** | **✗ — no region on any usable provider** |

**Cyrillic is the one script family with no vantage point at all** — Russian, Ukrainian, Bulgarian, Serbian. Beyond script, the notable absentees by speaker count are Bengali, Urdu, Vietnamese and Turkish, none of which has a region either.

So the honest claim for a write-up is: *every major script family except Cyrillic, from a local IP, plus every language on the header axis.* That is a stronger and more defensible sentence than "most of the world".

Tier 2 both supplies the visual evidence and acts as a **check on Tier 1**: any target where the HTTP probe says "ignores the header" and the rendering probe disagrees is a site doing client-side locale selection, which is a finding in itself and one nobody has quantified.

### Extra fields Tier 2 records

Added to `observations`, null for Tier 1 rows:

```sql
ALTER TABLE observations ADD COLUMN rendered INTEGER;        -- 0/1, which tier
ALTER TABLE observations ADD COLUMN screenshot_key TEXT;     -- S3 object key
ALTER TABLE observations ADD COLUMN rendered_html_lang TEXT; -- after JS
ALTER TABLE observations ADD COLUMN client_side_locale INTEGER; -- lang changed post-JS
```

`client_side_locale` is the column that answers the question the current study had to leave open.

### Open question added

### Settled

* **Tier 2 is twelve regions**, including `mx-central-1` and `ca-central-1` so `es-MX`/`es-ES` and `fr-CA`/`fr-FR` are tested from local IPs rather than by header alone.
* **AWS only.** No second provider. Polish and Russian are tested on the header axis and recorded as geolocation-axis gaps, alongside Cyrillic generally.

## Considered: a single probe behind a VPN

**Workable. Probably not better as the primary, and valuable as a secondary.** Investigated 2026-08-21.

The idea: one probe on one machine, cycling through VPN gateways to present a local IP per country. Mullvad in particular publishes a server-list API and WireGuard configurations, and community tooling to drive it programmatically already exists, so the mechanics are not the obstacle.

### What it would win

* **Country coverage AWS cannot match.** Consumer VPNs list 60–100 countries against roughly 30 usable AWS regions. It would close the **Cyrillic gap outright** — Russia, Poland, Ukraine, Bulgaria — plus Turkey, Vietnam, Greece and others with no AWS presence. That is the single biggest limitation in the AWS design.
* **Radically less infrastructure.** No container images, no ECR repository per region, no IAM role, no S3, no per-region deployment. Screenshots become a local headless browser rather than a 700 MB Lambda image with an object-storage round trip.
* **Comparable cost.** A subscription is a few dollars a month against roughly $0.84 of ECR.

### The finding that decides it

Commercial VPN exit addresses are **not residential addresses**. They are datacentre addresses that additionally sit on curated VPN blocklists — a specifically-detected category rather than merely an untrusted one. Cloudflare sells blocking "IP addresses associated with public VPNs" as a product feature, and Akamai integrates a proxy database whose stated purpose is spotting the shift from residential to VPN datacentre IPs.

Reported success rates make the consequence concrete: datacentre and VPN ranges see **60–90% success against unprotected sites, falling to 20–40% against Cloudflare Bot Management or Akamai Bot Manager**, where ASN classification fires before the request is read.

Our target list is close to a worst case for this. Hertz, Microsoft, Netflix, Booking, Nike, Zara and Adobe are exactly the population that runs those products.

For a *measurement* study this is worse than inconvenient. A blocked or challenged response looks like "serves the same thing everywhere" when it is really "no observation", and **the sites most likely to block are not a random sample** — they are the largest and best-defended, which is to say the ones the study is about. Silent, non-random loss is the one failure mode that can invert a conclusion rather than merely weaken it.

AWS Lambda ranges are datacentre ranges too and carry their own risk. They are not, however, on VPN blocklists.

### Recommendation: primary AWS, VPN as a reach extension

1. **AWS stays primary** for the twelve Tier 2 regions and the full Tier 1 sweep: stable addresses, parallel invocation, unattended operation, no VPN flag.
2. **Add a VPN adapter for countries AWS cannot reach** — Russia, Poland, Turkey, Vietnam — accepting a higher block rate there and recording it rather than hiding it. Partial evidence about Cyrillic beats none.
3. **Record blocks explicitly.** `observations` already captures status and a challenge-page check. Add a `blocked` flag so every report can state its own denominator, and never let a block masquerade as a null result.

### Step 0: measure the block rate instead of assuming it

Before either design is trusted, run the same small target set from three vantage points and compare:

| Vantage | Available now |
|---|---|
| Residential-ish consumer | this laptop, Starlink AS14593 |
| Cloud datacentre | an AWS Lambda, or an existing Fly machine in `iad` |
| VPN exit | a Mullvad endpoint |

Compare status codes, challenge pages, body hashes and `html lang`. That converts the central validity threat from a vendor blog claim into a measured property of *our* target list, and it decides how much VPN data is worth collecting. It is an afternoon's work and it should precede the build.

If the three vantage points return equivalent content, much of the caution above is unnecessary and the VPN design becomes far more attractive on simplicity alone. If they diverge, the divergence is itself a publishable finding: *what the web serves depends on what kind of address you arrive from*, which is adjacent to the original thesis and has the same shape.

## Open questions for review

1. **Target list** — the set above is a starting point; which sectors matter most for the argument?
2. **Region set** — all ~20 language areas every run, or a core set with an opt-in `--all`? More regions is more evidence and more setup.
3. **Header variants** — is five enough? Adding `zh-CN`, `he-IL`, `hi-IN` triples some cells but tests RTL and non-Latin digits directly.
4. **Content extraction depth** — regex for numbers and dates is crude but robust. Anything smarter (a real parser, or rendering in a headless browser) is much more expensive and much more fragile. Recommend starting crude.
5. **Publish?** The Accept-Language findings are already interesting; a multi-region version with 20 language areas is a conference talk on its own. If it is going to be published, the politeness and disclosure story needs to be right from the first run, not retrofitted.
6. **Repo or subdirectory?** Plan assumes a sibling repo `localize_research_probe`. It could equally live under `localize/research/probe/`.

---

## Step 0 results — executed 2026-08-22

Step 0 asked one question before committing to a design: **how much of the target population refuses a datacentre IP?** The answer changes which design is viable, so it was measured rather than assumed.

The same probe — identical targets, header variants, block markers and interstitial threshold — was run from a residential connection and from four AWS regions. The Elixir original (`priv/probe.exs`) and the Lambda port (`priv/aws/lambda/probe.py`) produce the same record shape deliberately; they must stay in step or the vantages are not comparable, which is the entire point.

### Block rate by vantage

| Vantage | Egress | Blocked | Errored | Clean |
|---|---|---|---|---|
| Laptop, Starlink AU | `65.181.14.195` AU, AS14593 SpaceX | **0 / 30** | 6 | 24 |
| AWS `eu-central-1` | `63.177.88.54` DE, AS16509 | **6 / 30** | 3 | 21 |
| AWS `us-east-1` | `100.30.206.165` US, AS16509 | **6 / 30** | — | — |
| AWS `mx-central-1` | `78.12.143.250` MX, AS16509 | **6 / 30** | — | — |

### What blocks, and where

Two of the ten targets refuse AWS, in **every region tried, on all three header variants**:

* **`hertz.com`** — Incapsula challenge page (`_incapsula_resource`), served instead of the home page.
* **`zara.com`** — flat `HTTP 403`.

The block is identical in Frankfurt, Virginia and Mexico City, so it is keyed on the **ASN**, not the country. Enabling more regions will not move it.

Nothing blocked the residential connection. The failures there were different in kind: `gnu.org` timed out from Starlink but answered AWS instantly, and `adobe.com` failed from both. So the vantages are not ordered — each sees things the other cannot — but only the datacentre vantage loses whole *sites*.

### Why this matters more than 20% suggests

`hertz.com` is **the site the original study's claim is about**. An AWS-only design cannot measure the flagship case at all, and `zara.com` is a second global retailer of exactly the kind the study population is meant to represent. The 20% figure understates the damage because the sites that block are not a random fifth — they are disproportionately the bot-defended global brands the research targets. The controls (`debian.org`, `gnu.org`) and the less-defended brands answer fine, so an AWS-only run would produce a **clean-looking dataset that had quietly dropped the hardest and most interesting cases**.

### Consequence for the design

AWS alone is not sufficient. It remains the right *breadth* layer — 21 usable regions, genuinely free, fully autonomous, and it answers the header/`Vary`/geolocation questions for the 80% that do answer. What it cannot do is speak for the defended brands.

**Recommended shape, revised:**

1. **AWS Lambda, all usable regions** — the breadth layer, as planned. Records `blocked_reason` per observation so the denominator stays defensible.
2. **A residential-egress layer for the blocked subset only** — the two sites here, and however many more appear as the target list grows. This is where the VPN idea earns its place: not as the primary transport, but as the fallback for observations AWS cannot obtain.
3. **Never silently drop a blocked observation.** A site that blocks from a vantage is itself a finding, and the reason is already recorded.

### Operational notes

* Five requested opt-in regions could not be enabled: `eu-south-2` (Spain), `ap-east-1` (Hong Kong), `ap-southeast-7` (Thailand), `il-central-1` (Israel), `me-central-1` (UAE). All are recent regions; AWS gates those on a support case for young accounts. Three opt-ins did succeed — `me-south-1`, `mx-central-1`, `af-south-1`.
* **Arabic is still covered** by `me-south-1` (Bahrain) and **`es-MX` by `mx-central-1`**, so the two highest-value gaps closed anyway. Hebrew has no vantage and is header-axis only; Chinese and Thai fall back to `ap-southeast-1` (Singapore).
* `me-south-1` resolves but **TCP 443 is filtered from this Starlink connection**, so Bahrain could not be driven from here. The endpoint is reachable in principle; the harness must record a vantage it cannot reach rather than treating it as a block.
* The probe needed a **run-level budget**, not just a per-fetch timeout. `urllib`'s timeout bounds each socket operation, so a server that trickles bytes or redirects in a loop resets the clock forever — one such target cost the entire first Frankfurt run. `RUN_BUDGET` now caps the whole invocation and records unfinished work as `run_budget_exceeded`.
* The IAM policy needs two additions for log retrieval: `logs:DescribeLogStreams` and `logs:GetLogEvents`.

---

## Outcome and follow-up recommendations — 2026-08-22

The harness is built and a full sweep has run. `research/accept-language-field-measurement.md` is the report: 53 sites, 15 header variants, 20 vantages, 15,900 observations, every figure traceable to a function in `LocalizeResearchProbe.Analysis`.

The headline is that the web routes on IP, not on `Accept-Language`: 13.5% of judgeable sites honour the header, 42.1% geolocate, and 18 of 38 do neither.

### Recommendations, in priority order

**1. Replace the two weak controls before any further run.** `www.wikipedia.org` is a language-selection portal, so it correctly never varies and tells us nothing; use `en.wikipedia.org` or a per-language host instead. `gnu.org` honours the header correctly but is too slow to survive fifteen sequential requests and was excluded from every vantage. Two working controls out of three is thin for a study whose credibility rests on the detector being demonstrably correct. This is cheap and it strengthens everything else.

**2. Do not chase the blocked fifth with a VPN yet.** 22.7% of observations are blocked and the blocking is ASN-keyed, so a residential egress would recover them. But the finding stands without it — the honouring rate is a *ceiling* precisely because the excluded sites are the well-resourced ones, and that argument is stronger than a partial VPN sample would be. Revisit only if a reviewer challenges the exclusion, and if so, run the blocked subset from a residential connection rather than adding a VPN adapter.

**3. Add the rendering probe only for a specific question.** The current measure — `lang`, `Content-Language`, final URL — undercounts sites that swap copy without changing any of them. That is a real gap, but a container-based headless-Chromium tier costs roughly $1/month in ECR storage and considerably more complexity. Worth it only to answer "does the rendered *number and date formatting* change", which is the question closest to Localize's actual subject and which no HTTP probe can reach. Frame it that way or skip it.

**4. Re-run monthly and keep the runs.** The schema is keyed by run and additive, so drift is measurable at no design cost. A second data point in a month turns a snapshot into a trend, and the sweep is four minutes.

**5. Feed the findings back.** Three of these belong to `localize_web` rather than to Localize, which owns the HTML surface where `lang`, `dir` and `Vary` are emitted. The fourth was checked and needs no work.

* Emit `dir` alongside `lang` by construction in any HTML helper. Three sites in 38 get this right unaided, which is the definition of a footgun worth removing.
* Keep regional subtags first-class through resolution. **Checked 2026-08-22: Localize already does this and it does not conflict with TR35, so no change is needed.** `es-MX` formats `1,234,567.89` against `es-ES`'s `1.234.567,89`; `fr-FR` groups with U+202F and `fr-CA` with U+00A0; `en-IN` groups by lakh; and `canonical_locale_id` preserves `es-MX` rather than collapsing it. TR35's inheritance chain (tr35.md:1809) governs *data lookup* — `es-MX` inherits missing items from `es-419` then `es` then root — which is orthogonal to preserving the requested tag's identity. The two are not in tension.
* Document `Vary: Accept-Language` wherever Localize touches content negotiation. Two sites in 53 emit it; its absence corrupts every shared cache downstream.
* Treat an incoming locale as untrusted by default. If most sites resolve locale wrongly, a library that assumes the locale arriving at the application layer is correct is designing for a web that does not exist.

### Known gaps, carried forward

* `me-south-1` is enabled but unreachable from this network — TCP 443 filtered on the Starlink path. Recorded as unreachable each run rather than silently dropped.
* Five opt-in regions could not be enabled: `eu-south-2`, `ap-east-1`, `ap-southeast-7`, `il-central-1`, `me-central-1`. All are newer regions gated behind a support case for young accounts. Hebrew and Thai therefore have no vantage; Chinese falls back to Singapore.
* No Cyrillic vantage exists on AWS at all. `ru-RU` and `pl-PL` are header-axis only, which is a stated limitation rather than something to redesign around.


---

## Status — 2026-08-22, end of session

All five follow-up recommendations above were acted on, and three of them changed the study rather than merely extending it.

**(1) Controls replaced.** `www.wikipedia.org` (a language portal that correctly never varies) and `gnu.org` (too slow to yield two usable observations) were dropped for `mozilla.org`, `torproject.org` and `videolan.org`, all verified by hand first. All four controls now register, which is the evidence the detector works. `videolan.org` was chosen specifically because it honours the header and omits `Vary`, exercising that detector too.

**(2) VPN fallback not built — and the evidence now supports that more strongly.** Re-sweeping the ten blocked sites from a residential connection found `hertz.com` blocked from **the same IP that had served it HTTP 200 earlier the same day**. Bot defences adapt within hours, so a residential vantage is a depleting resource and a shared VPN exit would degrade faster still.

**(3) Rendering probe not built; the question it was for was answered another way.** Docker was unavailable and ECR is per-region, so a ~700 MB Chromium image was not viable. Instead the HTTP probe learned to classify number and date conventions from visible text. That answers the framed question for server-rendered content and leaves client-side pricing as the stated gap.

**(5) Regional subtags: checked, no change needed.** Recorded above.

### The second study

The measurement pivoted mid-session after the negotiation result turned out not to support a claim about localization *quality* — the "adapts to neither" group contains Apple, IKEA, Microsoft, the UN and the WHO, all extensively localized behind country selectors. Taking each site's own `hreflang` declarations as ground truth removed the confound entirely: 26 sites declaring 2,317 locale variants, 2,213 audited, judged against CLDR with Localize as the oracle.

Both studies are written up in `research/web-localization-measurement.md`, which replaces the earlier `accept-language-field-measurement.md`.

### What is still open

* **Recall on number formatting** — 242 of 2,213 variants carry a judgeable number. Client-side pricing is the binding constraint; a rendering probe is the only way past it, and is now scoped to one specific question rather than being a general capability.
* **Twenty-two commercial brands** is enough for a claim about brands that publish many locale variants, not for a prevalence claim about the web.
* **Date formatting** was extracted but not analysed. `year-first` dominates the classifiable observations, which reflects ISO dates in machine-readable markup more than anything a reader sees; separating rendered dates from markup dates needs the same treatment numbers got.
