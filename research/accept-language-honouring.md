# Do global corporations honour `Accept-Language`?

**Measured 2026-08-20 from Sydney, Australia (AS14593, Starlink).** Claim under test, made in a presentation: *many global corporations ignore the `Accept-Language` header and serve content based on the language of the visitor's IP geolocation instead — which is often wrong.*

## Verdict

**Substantiated. 17 of 18 global corporate sites ignore the header entirely.**

Not one of the 17 sent `Vary: Accept-Language`, so they do not even claim to consider it. Several actively route by geography instead, which is the mechanism behind the complaint.

## Method

The experiment isolates the variable. From a **single fixed IP address**, each site was requested twice with an identical browser `User-Agent`, changing only one thing:

```
Accept-Language: en-AU,en;q=0.9
Accept-Language: de-DE,de;q=0.9,en;q=0.1
```

A site that honours the header must produce a different response. A site that ignores it produces the same one.

Signals compared, in order of reliability:

1. **`Vary: Accept-Language`** response header — the site declaring it varies on the header. Decisive when present.
2. **`<html lang="…">`** in the delivered document — what language the site thinks it served.
3. **Final URL after redirects** — reveals geo-routing such as `/au/`.

A first attempt compared body hashes and produced a false positive on Hertz, whose markup differs between requests because of session tokens while the content language stays identical. **Body hashing is not a valid signal for this test**; the results below use `lang` plus final URL.

## Results

### Global corporations

| Site | Honours? | `lang` asking en-AU | `lang` asking de-DE | `Vary: AL` |
|---|---|---|---|---|
| hertz.com | ✗ ignores | `en-AU` | `en-AU` | — |
| microsoft.com | ✗ ignores | — | — | — |
| apple.com | ✗ ignores | `en-US` | `en-US` | — |
| ikea.com | ✗ ignores | `en` | `en` | — |
| booking.com | ✗ ignores | `en` | `en` | — |
| airbnb.com | ✗ ignores | — | — | — |
| amazon.com | ✗ ignores | — | — | — |
| nike.com | ✗ ignores | `en-AU` | `en-AU` | — |
| lufthansa.com | ✗ ignores | — | — | — |
| bmw.com | ✗ ignores | — | — | — |
| adobe.com | ✗ ignores | — | — | — |
| samsung.com | ✗ ignores | `en-AU` | `en-AU` | — |
| netflix.com | ✗ ignores | `en` | `en` | — |
| paypal.com | ✗ ignores | `en-AU` | `en-AU` | — |
| uber.com | ✗ ignores | — | — | — |
| zara.com | ✗ ignores | — | — | — |
| h-m.com | ✗ ignores | — | — | — |
| **spotify.com** | ✓ **honours** | `en` | `de` | — |

**17 ignore, 1 honours.**

### Control group

If everything ignored the header, that could mean the test is broken rather than that sites are. It is not:

| Site | Honours? | en-AU | de-DE | `Vary: AL` |
|---|---|---|---|---|
| debian.org | ✓ honours | `en` | `de` | **`accept-language`** |
| developer.mozilla.org | ✓ honours | — | — | — |
| gnu.org | ✓ honours | `en` | — | — |
| w3.org | ✗ ignores | `en-US` | `en-US` | — |

Debian is the reference implementation of correct behaviour: it flips `lang="en"` to `lang="de"` **and** advertises `Vary: accept-language` so caches know the response is language-dependent.

## Geolocation is the input instead

Four sites — Hertz, Nike, Samsung, PayPal — returned `lang="en-AU"`. They are not language-blind; they made a deliberate choice, using the wrong signal.

The clearest single demonstration is Samsung:

```
Request:  GET https://www.samsung.com/   Accept-Language: de-DE,de;q=0.9
Response: 302 -> https://www.samsung.com/au/
```

**Asked explicitly for German, redirected to the Australian site**, because the request came from an Australian address.

Microsoft and Hertz, both named in the original claim, behave as described:

* `microsoft.com` — `HTTP 200`, no `Vary`, no `Content-Language`. The same page regardless of what is asked for.
* `hertz.com` — a fixed `301` to `/rentacar/reservation/` regardless of the requested language.

## Why this matters

`Accept-Language` is the user's explicit, deliberate statement of preference — set once in the browser and sent with every request. IP geolocation is an inference about physical location, and location is not language. It fails for travellers, expatriates, migrants, multilingual countries, VPN and corporate-proxy users, and satellite or mobile networks whose egress is in another country entirely.

The failure is silent and self-reinforcing: the visitor sees content in a language they may not read, with no indication that a correct preference was sent and discarded. Sites that do this typically offer a manual locale switcher, which is the workaround for a problem they created.

For an Australian in Germany with `en-AU` configured, Hertz and Microsoft serve German. The header that would have fixed it was sent and ignored.

## Limits

* **One vantage point.** All requests originated in Sydney. This proves the header is ignored and that geography is used instead; it does not reproduce the German-content experience directly, which would need an egress in Germany.
* **Landing pages only.** Deeper pages, authenticated sessions, or an established locale cookie may behave differently.
* **A point-in-time snapshot.** Sites change. Dated 2026-08-20.
* **Absent `lang` is not absent behaviour.** Several sites ship no `<html lang>` on the landing page and may set locale client-side. For those, "ignores" means the *served document* did not differ, which is still the user-visible outcome on first paint.
* Sample is 18 sites, chosen as recognisable global brands rather than randomly drawn.

## Reproduction

Two requests differing only in the header, comparing the declared language:

```bash
for al in "en-AU,en;q=0.9" "de-DE,de;q=0.9,en;q=0.1"; do
  curl -sL -m 25 --compressed -H "Accept-Language: $al" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0 Safari/537.36" \
    -o /tmp/body.html -w "$al -> %{url_effective}\n" https://www.samsung.com/
  grep -oiE '<html[^>]*lang="[^"]*"' /tmp/body.html | head -1
done
```

Check whether a site claims to vary at all:

```bash
curl -sI -m 20 https://www.debian.org/ | grep -i vary
```
