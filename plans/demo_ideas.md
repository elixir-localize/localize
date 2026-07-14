# Conference demo ideas — Elixir/BEAM conference, 2027

The organizers cultivate a "music festival" mood: light, relaxed, creative, energetic. The brief: a new project with a very cool demo and, ideally, audience participation. Four candidates, with a recommendation at the end.

## 1. Emoji DJ — launch `localize_emoji` on stage

Already on the roadmap ([plans/cldr-49.md](cldr-49.md) item 11): a sibling library for emoji search over CLDR annotations with boolean tag queries. Build it over the winter, launch it at the conference.

**The demo.** A giant screen running a LiveView "emoji mixing desk". Type queries live — `face and (happy or mischievous) and not sad`, `"dark skin tone" and musician` — and the wall fills with results in the audience's languages, because annotations are per-locale. Then the drop: the audience joins by QR code, every phone becomes a search box, and matching emoji rain onto the big screen like festival crowd reactions, tagged with the locale that searched for them.

**Why it fits.** Emoji are inherently light and playful; boolean query parsing is a satisfying little language-design story for a BEAM crowd; and the talk ends having shipped a real hex package the audience can add to a project before the next session. The October `ldml2json_v2` pipeline work is the data prerequisite, so the roadmap already points here.

## 2. The Babel Wall — one app, every locale in the room, live

A festival-themed LiveView app (lineup, set times, ticket prices, distances to stages) where each attendee joins on their phone and the app negotiates their locale from `Accept-Language` — the `best_match` story. The big screen is a wall of every locale currently in the room rendering the same screen: Arabic digits, Buddhist calendar dates, 24-hour vs 12-hour, currency symbol placement, km vs miles.

**The demo moment.** "Let's add Japanese" — add one MF2 translation file live, hot-reload, and thirty phones in the room flip. Zero code change. Then a plural-rules quiz: everyone's phone shows "you have N messages" for their locale and the audience discovers together that Arabic has six plural forms.

**Why it fits.** The strongest pure-Localize showcase — process-per-user locale is a genuinely BEAM-shaped design — and presence + PubSub with hundreds of phones is exactly what LiveView was born for.

## 3. OTP Orchestra — the audience is the instrument

Every phone that joins becomes a voice: a process emitting notes/samples, mixed through PubSub (or Membrane for real audio pipelines) into music played through the PA. Sections of the room get instruments by seating block; a conductor view mutes, solos, and layers the crowd. Latency compensation and back-pressure are the technical meat — GenStage as a rhythm section.

**Why it fits.** Maximum festival energy — the room literally makes music together — and "a thousand processes are playing this song right now" is the most visceral BEAM demo there is. The localization tie is thinner (per-locale phone UI, note names per locale), so this trades maintainer authority for spectacle. Highest on-stage failure risk (live audio).

## 4. The Great Collation Race

Sorting as spectator sport. The audience submits words — names, band names, words from their languages — and the big screen animates the same list re-sorting live under different collations: default UCA, German phonebook, Swedish, zh-pinyin vs zh-stroke, numeric mode, backwards French accents. Bars slide past each other like a horse race; the audience bets on where "Öztürk" lands before each round.

**Why it fits.** Collation is the most underexplained topic in software and the animation makes it instantly visible. Probably a 10-minute segment rather than a whole talk — which is why it composes well with ideas 1 or 2.

## Recommendation

**Superseded (2026-07-12): the chosen direction is Contraption — see [plans/contraption.md](contraption.md)** — a BEAM-native automation platform (IFTTT/Node-RED category) with home/industrial reach, media pipelines, localization-native output, and the Mousetrap audience mechanic. It absorbs the best parts of the ideas below: the Emoji DJ becomes a connector cameo, and the Collation Race spirit lives on in the visible-cascade staging. Original recommendation kept for the record:

### Original recommendation

**Idea 1 (Emoji DJ) as the spine, with idea 4 as a segment.** It is the only option that leaves a real artifact behind — a new library launched on stage, born from the existing roadmap — and emoji provide festival-mood visuals without manufactured whimsy. The participation mechanic is robust (worst case, people search emoji on their phones, which is already fun), whereas live audio has the highest failure risk. A successful talk doubles as `localize_emoji`'s launch day.

## Timeline sketch

* October 2026 — CLDR 49 cycle lands `ldml2json_v2` and the annotations data path (prerequisite).
* Winter 2026/27 — build `localize_emoji` (package skeleton, normalizer, query DSL, LiveView demo shell).
* Spring 2027 — talk outline, demo hardening (offline fallback, capacity test with simulated phones), collation-race segment.
