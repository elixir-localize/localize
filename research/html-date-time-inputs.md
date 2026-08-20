# Can `<input type="date">` and `<input type="time">` do the job?

**Measured 2026-08-21** against Chromium 148 (Electron 42.9.2) on macOS 15.6.1, browser UI locale `en-GB`, system locale `en-AU`. Cross-browser support figures are from published compatibility data, not measured here — see [§Limits](#limits).

## Verdict

**Widely supported, and not locale-controllable.** The native pickers are available almost everywhere, but the page cannot influence how they render, they follow the *browser's* locale rather than the document's or the user's stated preference, and they have no concept of a non-Gregorian calendar.

Three findings, in order of how much they matter:

1. **`lang` is ignored entirely.** Six inputs carrying six different `lang` values rendered identically. There is no markup, attribute or CSS that changes the display format.
2. **No calendar support.** `lang="th-TH-u-ca-buddhist"` rendered a Gregorian date. The platform *has* Buddhist, Japanese, Islamic and Persian calendars — `Intl` formats all four correctly in the same browser — the widget simply does not use them.
3. **`input=time` does not even match its own browser's locale data.** For `en-GB`, `Intl` says `14:30`; the widget renders `02:30 pm`.

## Part 1 — support

Published compatibility data puts `date`, `time` and `datetime-local` at **96.39% global support**.

| Browser | `date` / `time` | `month` / `week` |
|---|---|---|
| Chrome 25+, Edge 13+, Opera | full | full |
| Safari iOS 18.2+ | full | full |
| Safari desktop 14.1+ | supported | **falls back to `text`** |
| Firefox 57+ | supported | **falls back to `text`** |
| Opera Mini | none | none |
| IE 11 and earlier | none | none |

The "partial support" both Firefox and Safari desktop carry is `month` and `week` degrading to a plain text field, which pushes the user into typing a value by hand in the exact format the server expects. Feature-detect by setting `type` and reading it back: an unsupported type reports `"text"`.

Verified in Chromium: all five of `date`, `time`, `month`, `week` and `datetime-local` report their own type.

**For `date` and `time` specifically, availability is not the problem.**

## Part 2 — the page cannot control the locale

Six date inputs and six time inputs, identical values, differing only in `lang`:

```html
<input type="date" value="2026-03-22">
<input type="date" lang="de-DE" value="2026-03-22">
<input type="date" lang="en-US" value="2026-03-22">
<input type="date" lang="ja-JP" value="2026-03-22">
<input type="date" lang="ar-SA" value="2026-03-22">
<input type="date" lang="th-TH-u-ca-buddhist" value="2026-03-22">
```

**Every one rendered `22/03/2026`. Every time input rendered `02:30 pm`.**

For comparison, `Intl.DateTimeFormat` in the same browser, same instant:

| locale | `Intl` date | `Intl` time | the widget |
|---|---|---|---|
| `de-DE` | `22.03.26` | `14:30` | `22/03/2026` · `02:30 pm` |
| `en-US` | `3/22/26` | `2:30 PM` | `22/03/2026` · `02:30 pm` |
| `ja-JP` | `2026/03/22` | `14:30` | `22/03/2026` · `02:30 pm` |
| `ar-SA` | `٢٢‏/٣‏/٢٠٢٦` | `٢:٣٠ م` | `22/03/2026` · `02:30 pm` |

The format comes from the **browser UI locale** — here `en-GB`, which is neither the document's `lang` nor the system locale (`en-AU`) nor anything the server sent. It is a setting inside the browser, invisible to the page and unreadable by it.

The [wire value is unaffected](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/input/date) and always ISO 8601 — `"2026-03-22"`, `"14:30"`, `"2026-W12"` — which is the one part of this that is well specified and dependable.

A [Blink intent to make form controls respect `lang`](https://groups.google.com/a/chromium.org/g/blink-dev/c/QpEoCwU0Ttg/m/DVHHm28IKVYJ) has been open for years. It has not shipped: this measurement is Chromium 148.

## Part 3 — no calendar systems

`lang="th-TH-u-ca-buddhist"` renders a Gregorian date. So would `-u-ca-japanese`, `-u-ca-islamic` or `-u-ca-persian`; there is no attribute for it and no mechanism to add one.

This is not a data problem. The same browser, same instant, through `Intl`:

| calendar | rendered |
|---|---|
| Thai Buddhist | `22 มีนาคม 2569` |
| Japanese imperial | `令和8年3月22日` |
| Islamic | `٣ شوال ١٤٤٧ هـ` |
| Persian | `۲ فروردین ۱۴۰۵` |

The Buddhist year is **2569** against Gregorian 2026 — a 543-year difference. Persian is 1405, Islamic 1447. A user who reads dates in one of these sees a number that is not merely formatted differently but is a different year entirely.

Every one of those calendars ships in the browser. The native picker reaches none of them.

## Part 4 — `input=time` disagrees with its own browser

The sharpest single finding. With the browser UI locale at `en-GB`:

```
navigator.language                                    "en-GB"
Intl.DateTimeFormat("en-GB", {timeStyle: "short"})    "14:30"
Intl resolved hourCycle                               "h23"

<input type="time" value="14:30">  renders             02:30 pm
```

The date agrees — `Intl` and the widget both give `22/03/2026`. **The time does not.** `Intl` reports a 24-hour cycle for this locale and formats accordingly; the widget renders a 12-hour clock with a lowercase `pm` that matches no CLDR convention for `en-GB`.

So `input=time` is not "locale-aware but uncontrollable". It is inconsistent with the locale data the same browser exposes one API call away.

## What this means

Use the native input when the audience is one locale, the calendar is Gregorian, and the exact rendering does not matter. It is free, accessible, and the mobile pickers are good.

Reach for a server-rendered, locale-aware component when any of the following is true — and each of these is a routine requirement, not an exotic one:

* **The rendering must match the rest of the page.** A form showing `22/03/2026` in the picker and `22 March 2026` in the summary beside it is the default outcome, not an edge case.
* **The locale is chosen by the application**, from a user profile, an `Accept-Language` header, or a URL segment. The native picker will ignore all three and follow a browser setting instead.
* **The user does not read Gregorian dates.** No amount of markup will help.
* **Time is displayed at all**, given Part 4.
* **`month` or `week` is needed** on Firefox or Safari desktop, where it is a bare text field.

That is the case for `localize_datetime_inputs`, and it is stronger than "the native control is ugly": the native control cannot be made correct.

## Limits

* **One browser measured.** Chromium 148 via Electron. Firefox and Safari were not tested directly; their rows in Part 1 come from published compatibility data. Their `lang` behaviour is very likely the same — no engine implements the proposal — but that is inference, not measurement here.
* **One vantage point.** Browser UI locale `en-GB`, system locale `en-AU`. A different browser locale changes what the widget renders but not the finding, which is that the *page* cannot influence it.
* **Point in time.** The Blink intent could ship; if it does, Part 2 needs revisiting. Parts 3 and 4 are not addressed by that proposal.
* Rendering was read from a screenshot of the running widget, which is what a user sees, rather than from an internal API — there is no API that reports the displayed format.

## Reproduction

Save as an HTML file and open it. No server needed.

```html
<input type="date" value="2026-03-22">
<input type="date" lang="de-DE" value="2026-03-22">
<input type="date" lang="ja-JP" value="2026-03-22">
<input type="date" lang="th-TH-u-ca-buddhist" value="2026-03-22">
<input type="time" value="14:30">
<script>
  const d = new Date(2026, 2, 22, 14, 30);
  console.log(navigator.language,
    new Intl.DateTimeFormat(navigator.language, {timeStyle: "short"}).format(d),
    new Intl.DateTimeFormat("th-TH-u-ca-buddhist", {dateStyle: "long"}).format(d));
</script>
```

Compare what the four date inputs display against each other, and what the time input displays against the `Intl` output logged beside it.
