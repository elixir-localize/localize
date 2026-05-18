# Japanese eras — validation and curation plan

**Status:** first-pass research complete; last updated 2026-05-17

**Owner:** Localize maintainers

**Target release:** Localize 0.38+ (lands alongside the CLDR 49 base data refresh)

**Triggered by:** CLDR 49 is dropping era data for every Japanese era before Meiji (era index `< 232` in our supplemental data). Modern usage relies on era 232–236 (Meiji through Reiwa); ancient eras are an editorial trim, not a correctness fix. We want to keep them because they're load-bearing for any consumer formatting historical Japanese dates — academic publishing, museum cataloguing, genealogical software, calendar conversion utilities — and CLDR has been the canonical machine-readable source for the full set.

Keeping the data is the easy part. **Curating it correctly is the work** — CLDR's pre-Meiji era start dates have known ambiguities, and this plan describes the methodology, sources, and tracking table for validating each one before we publish the snapshot we'll maintain ourselves going forward.

---

## Scope

This plan covers:

1. Background on why CLDR is removing the data and what Localize will ship instead.
2. The **calendar ambiguity** in the existing CLDR data: a given `[year, month, day]` triple may be Gregorian, proleptic Gregorian, Julian, or a Japanese lunisolar date that was converted to one of the above by an unknown party at an unknown time.
3. A validation methodology grounded in Japanese primary sources (`日本書紀`, `続日本紀`, `日本紀略`, the `本朝世紀`, and the modern compilations of the National Diet Library and the National Archives of Japan).
4. A tracking table with the canonical CLDR raw date, its presumed source calendar, the proleptic Gregorian start we'll publish, and the citation for each row.
5. The validation workflow: how a contributor proves a single row, how a row gets marked **verified** vs **provisional** vs **disputed**, and how we ship the curated set.

Out of scope:

* Mainland Chinese era data (separate problem with a separate primary-source corpus).
* Republic of China (ROC) eras — already gregorian-aligned post-1912 and not affected by CLDR 49.
* Astronomical recomputation of Japanese lunisolar dates from first principles (NASA JPL Horizons, etc.) — useful as a tie-break, but not the primary methodology.

---

## Background — why CLDR 49 is dropping pre-Meiji eras

The CLDR-TC has been visibly uncomfortable with pre-Meiji era data for several releases:

1. The dates come with no provenance — each release reproduces whatever was in the previous release without a citation back to a primary source. When an entry is wrong, fixing it requires re-deriving the date from scratch.

2. The dates have inconsistent calendar bases. Some entries appear to be Julian (the historically prevailing Western calendar of the era), some are proleptic Gregorian (the Western calendar projected backwards), and some are direct Western-renderings of the original Japanese lunisolar dates without any conversion at all. There is no field flagging which is which.

3. Pre-Meiji eras are not used in modern Japanese government output. The Japanese government's official era (元号, *gengō*) machinery starts at Meiji 1 (1868-10-23 Gregorian). Pre-Meiji eras are scholarly / historical.

4. The maintenance cost is concentrated in one volunteer — the only people who reliably correct these entries are the same handful of historical-calendar specialists. The CLDR-TC has chosen to step back rather than ship data they can't validate.

Localize's position is the inverse: **the use cases (academic publishing, genealogy, museum cataloguing, calendar conversion) need the data**, so we keep shipping it — but we own the validation, with citations, and we publish corrections promptly when sources contradict our entries.

---

## The calendar ambiguity problem

A pre-Meiji era proclamation looks like this in CLDR (and currently in Localize's `priv/localize/supplemental_data/calendars.etf`):

```elixir
[24, %{start: [898, 4, 26]}]   # era 24 — 昌泰 (Shōtai)
```

What does `[898, 4, 26]` actually mean? **There are three plausible readings, and CLDR data doesn't say which applies:**

1. **Proleptic Gregorian.** Year 898, month 4, day 26 in the Gregorian calendar projected backwards. The Gregorian calendar did not exist until 1582; "proleptic" means we apply its rules retroactively as if it had. Modern computer libraries — including Elixir's `Calendar.ISO` — use proleptic Gregorian, so this is the convenient encoding.

2. **Julian.** Year 898, month 4, day 26 in the Julian calendar (the contemporary Western calendar at the time). Julian and Gregorian drift apart over centuries — by 898 CE the offset is +4 days (Julian is 4 days earlier than the equivalent Gregorian moment). So `Julian 898-04-26` = `Proleptic Gregorian 898-04-30`.

3. **Direct rendering of the original lunisolar date.** The original `Nihongi`/`Shoku Nihongi`-style entry for the era proclamation would be something like *昌泰元年四月二十六日* — "Shōtai era 1, fourth month, 26th day". A naive transcriber might copy `4, 26` into the Western fields without converting the lunisolar month/day to its Western equivalent. The lunisolar 4th month of `仁和` 4 (the year that became `昌泰` 1, equivalent to AD 898) ran approximately May 18 – June 17 Proleptic Gregorian — so the 26th day of the lunisolar 4th month would be roughly **June 12, 898 Proleptic Gregorian**.

The three readings produce dates that differ by **up to ~7 weeks** for a single era. The disagreement is not a rounding issue; it's a fundamental "which calendar are we in" question.

**Heuristics for guessing the source calendar of an existing CLDR entry:**

* If the month is in the 4-10 range and the day is in the 14-30 range, it's plausibly an unconverted lunisolar reading (the lunisolar month-day numbers tend to fall in these ranges for spring/summer era changes, which is when most Japanese era changes happened).

* If the year/month/day round-trip through a Julian-to-Gregorian conversion lands within ±5 days of an authoritative source, the original encoding was probably Julian.

* If the year/month/day matches an authoritative source directly, the encoding was Gregorian/proleptic-Gregorian.

These are not reliable individually — the actual proof has to come from primary-source comparison.

---

## Validation methodology

For each era, we want three pieces of information:

1. **The lunisolar date of the era proclamation as recorded in primary sources** (year, month, day in the Japanese lunisolar calendar in use at the time). This is the "true" date in the sense that it's what the imperial court actually proclaimed.

2. **The proleptic Gregorian equivalent of that lunisolar date.** Established via published lunisolar-Gregorian conversion tables — the workhorse references are Tsuchihashi (1952) and Naitō (1992); they have been digitised and are available through the NDL Digital Collection. For dates from Meiji onwards, the Japanese government's `太政官布告` (Daijō-kan proclamations) provides Gregorian dates directly.

3. **The proleptic Gregorian equivalent of any *secondary* readings** — the Julian-converted form, the unconverted Western-numerals form, and any alternative dates from regional calendars (the Japanese court used a slightly different lunisolar system from the Chinese one used in Korea and Vietnam).

For a row to be marked **verified** in the table below, all three pieces must agree on a single proleptic Gregorian date OR we must explicitly note which interpretation we've chosen and why.

The proleptic Gregorian date is what we ship in `priv/localize/supplemental_data/calendars.etf`. We do **not** ship the lunisolar date as a separate field — that's an enhancement for a future release once the validation pass is complete.

### Resolution priority when sources disagree

1. The proclamation entry in the official chronicle of the period — `日本書紀` for the earliest eras, `続日本紀` / `日本後紀` / `続日本後紀` / `日本文徳天皇実録` / `日本三代実録` (the *Rikkokushi* — the six official histories — covering through 887), then the `日本紀略` / `本朝世紀` / `百錬抄` / `吾妻鏡` / `玉葉` / `明月記` for the eras between the *Rikkokushi* and the Tokugawa.

2. The Tokugawa-shogunate-period entry in `通航一覧` or `武家事紀` — for the late Heian / Kamakura / Muromachi / Sengoku eras these are more reliable than later compilations.

3. The modern compilations: `国史大辞典` (Kokushi Daijiten, 1979-97, Yoshikawa Kōbunkan), `日本史広辞典` (Yamakawa, 2000), and the National Diet Library's online era list at <https://www.ndl.go.jp/jp/data/era_list.html>.

4. The astronomical reconstruction in Tsuchihashi, Paul Yachita, *Japanese Chronological Tables from 601 to 1872* (Sophia University, 1952) — the standard Western-language reference.

5. The astronomical reconstruction in Naitō, Akira, *Japanese Calendar Tables, Liber Annales* (Maruzen, 1992) — the standard Japanese reference, supersedes Tsuchihashi for the eras where they disagree.

6. Only if 1-5 cannot resolve the date do we accept Wikipedia (Japanese-language, citing primary sources) or the SHEKEL/GENGOU databases.

---

## Sources

| Reference | Coverage | Primary use |
| --- | --- | --- |
| `日本書紀` (Nihon Shoki, completed 720) | Era 0 (大化) through era 3 (朱鳥) | Era proclamations of the earliest eras |
| `続日本紀` (Shoku Nihongi, completed 797) | Eras 4-22 (大宝–延暦) | Nara-period eras |
| `日本後紀` (Nihon Kōki, completed 840) | Eras 18-22 (延暦–大同) | Some Heian-period overlap |
| `続日本後紀` (Shoku Nihon Kōki, completed 869) | Eras 23-28 | Mid-Heian eras |
| `日本文徳天皇実録` (Montoku Jitsuroku, completed 879) | Eras 29-31 | |
| `日本三代実録` (Sandai Jitsuroku, completed 901) | Eras 32-38 (through 仁和) | Last of the *Rikkokushi* |
| `日本紀略` (Nihon Kiryaku, c. 1036) | Eras 39-90 | Mid-Heian to early Insei eras |
| `本朝世紀` (Honchō Seiki, c. 1150-59) | Eras 80-115 | Insei period eras |
| `百錬抄` (Hyakurensho, c. 1259) | Eras 90-155 | Late Heian to early Kamakura |
| `吾妻鏡` (Azuma Kagami, c. 1300) | Eras 100-160 | Kamakura-shogunate official record |
| `玉葉` (Gyokuyō, journal of Kujō Kanezane, 1164-1200) | Eras 95-115 | Eyewitness for late Heian eras |
| `明月記` (Meigetsuki, journal of Fujiwara no Teika, 1180-1235) | Eras 100-140 | Eyewitness for Kamakura-period eras |
| `太政官布告` (Daijō-kan proclamations, 1868-1885) | Eras 232+ (Meiji onwards) | Gregorian-dated, definitive |
| Tsuchihashi (1952) | All eras 0-236 | Western-language standard reference for the proleptic Gregorian equivalent of any lunisolar date |
| Naitō (1992) | All eras 0-236 | Japanese-language standard; supersedes Tsuchihashi where they disagree |
| `国史大辞典` (1979-97) | All eras | Modern Japanese-academic compilation |
| NDL era list, <https://www.ndl.go.jp/jp/data/era_list.html> | All eras | Convenient online check; not a primary source |

A `bibliography.bib` file with full citations should land alongside this plan once the first round of validation begins.

---

## Research results — first pass (2026-05-17)

A full first-pass validation has been completed for all 237 CLDR entries and is published at [plans/japanese_eras_research.json](japanese_eras_research.json) (271 KB, 237 era entries + 42 bibliography entries). The schema is documented in the **JSON research dataset** section below. Headline findings:

### Confirmed LU-passthrough hypothesis

The hypothesis from the previous section is confirmed: **every pre-Meiji CLDR entry has the lunisolar `年月日` numerals copied into the Western fields with no calendar conversion**. This holds for all 232 pre-Meiji rows that matched against a Japanese-Wikipedia entry. For the 6 unmatched/special cases, see the dedicated subsection below.

This means the bulk validation pass is mechanical for the vast majority of rows: feed `(west_Y - 644, lunar_M, lunar_D)` to `Calendrical.LunarJapanese`, then `Date.convert/2` to `Calendar.ISO`, and you have the proleptic Gregorian equivalent of the proclamation date.

### Two PG sources, ~one third disagreement

For each row two PG values are computed:

* `wiki_pg` — derived from ja.wikipedia's Western date (Julian for entries before Tenshō-end ≈ 1583, Gregorian after) via `Calendrical.Julian` → `Calendar.ISO`. This reflects the **historical Japanese imperial calendar** actually in use at the time (宣明暦 862–1684, 貞享暦 1685–1754, 宝暦暦 1755–1797, 寛政暦 1798–1843, 天保暦 1844–1872), with the intercalary placements the imperial court astronomers recorded.
* `calendrical_pg` — derived independently from the lunisolar `(year=west_Y-644, month, day)` via `Calendrical.LunarJapanese` → `Calendar.ISO`. This is an astronomical reconstruction using the modern East-Asian no-zhongqi intercalary rule.

The two agree for **150 / 237 rows** in the as-published JSON (provisional+verified). They differ on 80 rows. Investigation traced **36 of those 80** to a caller-side issue, not to Calendrical itself: the research script built dates via `Date.new(year, month, day, Calendrical.LunarJapanese)`, which the standard `Calendar` behaviour expects to be **ordinal** months (1..13, with the intercalary at whatever position the no-zhongqi rule assigns it), while the inputs from Japanese chronicles were **traditional** months (1..12, with the intercalary written separately as `閏N月`). After the intercalary in leap years the two conventions differ by exactly one month — hence the Δ-30d signal.

A Calendrical patch (on the `fix/lunisolar-traditional-month-bug` branch) clarifies the ordinal-vs-traditional distinction, repairs a latent bug in the traditional-month validator (`{m, :leap}` tuples were previously rejected with `:invalid_date`), and adds `traditional_leap_month/1` as a companion to `leap_month/1`. With the research script switched to call `Calendrical.LunarJapanese.new/3` (which has always been traditional-month semantics) those 36 rows agree. The remaining **~44 disagreements** are real divergences between Calendrical's modern astronomical reconstruction and the historical Japanese imperial calendar — almost all Δ-1d — and `wiki_pg` is canonical for them because it reflects the calendar the imperial court actually used.

After the JSON is regenerated against the patched Calendrical the projected stats are ~186 agreeing / ~44 disagreeing (~80 % agreement, up from ~65 %). The numbers below still reflect the as-published JSON; they will be refreshed when the regeneration lands.

### Status distribution

Numbers below reflect the as-published JSON. After the Calendrical patch lands and the JSON is regenerated, ~36 currently-Disputed rows will reclassify as Provisional (see the *Two PG sources, ~one third disagreement* section).

| Status | Count (as-published) | Count (after regen, projected) | Meaning |
| ---: | ---: | ---: | --- |
| ✅ Verified | 15 | 15 | Primary chronicle entry or government proclamation cited directly |
| 🔶 Provisional | 138 | ~174 | ja.wikipedia and Calendrical agree on the PG date, no primary-source check yet |
| ⚠️ Disputed | 80 | ~44 | The two PG sources differ; `wiki_pg` preferred (historical-vs-astronomical lunar calendar) |
| ❓ Needs research | 4 | 4 | Data-quality issues: unmatched, missing day, or 私年号 placeholder |

The 15 ✅ rows are: the 4 earliest eras (大化, 白雉, 朱鳥, 大宝) attested in `日本書紀` / `続日本紀`; six additional Nara-Heian eras (慶雲, 和銅, 天平, 延暦, 嘉永, 安政) with chronicle or `徳川実紀` citations; and all 5 modern eras (明治–令和) with the original government proclamations cited.

### Court distribution

CLDR's pre-Meiji set turns out to include **both** the Northern (北朝) and Southern (南朝) Court eras of the Nanboku-chō period (1336–1392) — not just Northern as previously assumed. The breakdown:

| Court | Count | Eras |
| --- | ---: | --- |
| Unified (pre-1336, post-1392) | 212 | All eras outside the Nanboku-chō schism |
| Northern (北朝, 持明院統) | 16 | 暦応 through 明徳 |
| Southern (南朝, 大覚寺統) | 9 | 元弘, 延元, 興国, 正平, 建徳, 文中, 天授, 弘和, 元中 |

Open question 2 below is updated accordingly — the existing CLDR data already covers both courts; the gap is documentation, not data.

### Three confirmed CLDR data errors

Three CLDR entries are wrong with high confidence (ja.wikipedia individual-era articles disagree with CLDR's lunisolar M/D):

| Idx | Era | Current CLDR | Recommended | Diff | Source for correction |
| ---: | --- | --- | --- | --- | --- |
| 166 | 嘉慶 (Kakei) | `[1387, 8, 22]` | `[1387, 8, 23]` | +1 day | ja.wikipedia 嘉慶_(日本) records 至徳4年8月23日 (epidemic) |
| 181 | 応仁 (Ōnin) | `[1467, 3, 3]` | `[1467, 3, 5]` | +2 days | ja.wikipedia 応仁 records 文正2年3月5日 |
| 183 | 長享 (Chōkyō) | `[1487, 7, 29]` | `[1487, 7, 20]` | −9 days | ja.wikipedia 長享 records 文明19年7月20日 (likely 20↔29 transposition) |

Once primary-source verification is in (Tsuchihashi / Naitō / the relevant `Hyakurensho` / `Azuma Kagami` entries), these should be patched in `priv/localize/supplemental_data/calendars.etf`.

### Two convention questions surfaced

1. **大化 (Taika, idx 0)**: `日本書紀` 巻25 records the era proclamation on 皇極天皇4年6月19日 (lunisolar) = PG 645-07-20. ja.wikipedia's main 元号一覧 article instead lists 7月1日 (= PG 645-08-01) as the *implementation* date — the first day documents began to be dated with the new era. CLDR's `[645, 6, 19]` follows the proclamation convention. Recommendation: **keep proclamation date** for consistency with the chronicle entry and with how the rest of the set is dated.

2. **白鳳 (Hakuhō, idx 2)**: This is a 私年号 (folk / private era), not officially proclaimed by the imperial court and not recorded in any of the *Rikkokushi*. It appears in 12th-century 『二中歴』 (placing it 661–683) and in medieval temple-shrine origin documents (placing it 672–685). CLDR's `[672, 1, 1]` is a placeholder; both year and month/day are editorial. Recommendation: **keep with `private_era: true` and `status: :disputed`** so consumers can opt out.

---

## Validation table

**Legend for `Status`:**

* ✅ **Verified** — at least one primary source AND one modern compilation agree on the proleptic Gregorian date in column "Best Gregorian".
* 🔶 **Provisional** — only one source available, or sources differ by ≤1 day and we've picked one with justification.
* ❓ **Needs research** — no validation pass yet; CLDR's raw date is reproduced as-is.
* ⚠️ **Disputed** — primary sources disagree by more than 1 day; we've made an editorial call documented in the source column.

**Legend for `Raw calendar`:** which calendar the existing CLDR `[Y, M, D]` triple appears to be encoded in. PG = proleptic Gregorian. JD = Julian. LU = lunisolar (Western field numbers copied without conversion). `?` = not yet determined.

The table starts with the **modern eras** (Meiji onwards — all ✅, easy) followed by representative **pre-Meiji** entries. The complete 237-row dataset lives in [plans/japanese_eras_research.json](japanese_eras_research.json) (see the *JSON research dataset* section below); the tables here serve as the methodology demonstrator and a quick reference for the most-cited rows.

### Modern eras (Meiji onwards) — verified

| Idx | Era | Rōmaji | CLDR raw | Raw cal | Best PG | Status | Source |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 232 | 明治 | Meiji | `[1868, 10, 23]` | PG | `1868-10-23` | ✅ | `太政官布告第768号` of 慶応4年9月8日 (lunisolar) = 1868-10-23 Gregorian; established the 一世一元 (one-emperor-one-era) system, retroactive to 慶応4年1月1日 |
| 233 | 大正 | Taishō | `[1912, 7, 30]` | PG | `1912-07-30` | ✅ | `勅令第十八号` of 明治45年7月30日 — same day as Emperor Mutsuhito's death |
| 234 | 昭和 | Shōwa | `[1926, 12, 25]` | PG | `1926-12-25` | ✅ | `勅令第三百二号` of 大正15年12月25日 — same day as Emperor Yoshihito's death |
| 235 | 平成 | Heisei | `[1989, 1, 8]` | PG | `1989-01-08` | ✅ | `元号を改める政令` (昭和64年政令第1号, signed 1989-01-07) — begins midnight 1989-01-08, day after Emperor Hirohito's death. Etymology: 『史記』五帝本紀「内平外成」+『書経』大禹謨「地平天成」 |
| 236 | 令和 | Reiwa | `[2019, 5, 1]` | PG | `2019-05-01` | ✅ | `元号を改める政令` (平成31年政令第143号, 2019-04-01) — begins 2019-05-01 on Emperor Akihito's abdication and Emperor Naruhito's accession (first non-death era change in modern times). Etymology: 『万葉集』巻5 梅花の歌三十二首并序「初春令月、気淑風和」 |

These five rows establish the **format and verification standard** we want every other row to meet.

### Late pre-Meiji (Edo-period) eras — first pass complete

These are recent enough that the Japanese chronology is well-documented in Tokugawa-shogunate records, but old enough that the lunisolar-vs-Gregorian ambiguity bites. The Edo period (1603–1868) ran on the lunisolar calendar, so CLDR's `[Y, M, D]` triple was *converted* from the original `元号-年-月-日` proclamation date — but by whom, and from which calendar to which calendar, is not annotated. The first pass confirms the LU-passthrough hypothesis for every row.

| Idx | Era | Rōmaji | CLDR raw | Raw cal | Best PG | Status | Source / notes |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 226 | 嘉永 | Kaei | `[1848, 2, 28]` | LU | `1848-04-01` | ✅ | Proclamation: 弘化5年2月28日 (lunisolar). Wiki Gregorian and Calendrical agree on **1848-04-01**. Citations: `徳川実紀`, ja.wikipedia 嘉永, etymology 『宋書』. 孝明天皇代始改元. |
| 227 | 安政 | Ansei | `[1854, 11, 27]` | LU | `1855-01-15` | ✅ | Proclamation: 嘉永7年11月27日 (lunisolar). Wiki Gregorian **1855-01-15**, Calendrical 1856-01-04 (≠ 30 days; intercalary placement differs). Citations: `徳川実紀`, ja.wikipedia 安政, etymology 『群書治要』. 内裏火災・地震・黒船来航等の災異による改元. |
| 228 | 万延 | Man'en | `[1860, 3, 18]` | LU | `1860-04-08` | 🔶 | Proclamation: 安政7年3月18日 (lunisolar). Wiki and Calendrical both **1860-04-08**. |
| 229 | 文久 | Bunkyū | `[1861, 2, 19]` | LU | `1861-03-29` | 🔶 | Proclamation: 万延2年2月19日 (lunisolar). Wiki and Calendrical both **1861-03-29**. |
| 230 | 元治 | Genji | `[1864, 2, 20]` | LU | `1864-03-27` | 🔶 | Proclamation: 文久4年2月20日 (lunisolar). Wiki and Calendrical both **1864-03-27**. |
| 231 | 慶応 | Keiō | `[1865, 4, 7]` | LU | `1865-05-01` | 🔶 | Proclamation: 元治2年4月7日 (lunisolar). Wiki and Calendrical both **1865-05-01**. |

All six entries confirmed LU-passthrough and need correction in the published data. The corrections are mechanical via `Calendrical.LunarJapanese` for the rows where `wiki_pg` and `calendrical_pg` agree (idx 226, 228–231); the Ansei row (idx 227) is the one Edo-period case where the intercalary placement diverges, so `wiki_pg = 1855-01-15` is the historically-faithful value to ship.

### Ancient eras — primary-source attested

The earliest few eras are well-attested in `日本書紀` (the official chronicle of 720 CE, covering events from mythological times through 697) and `続日本紀` (797). These dates are unusually scrutinised by historians and have multiple modern reconstructions in print.

**Important note on the previous version of this table:** earlier drafts of this plan listed "Tsuchihashi → 645-07-17" and similar values as the **proleptic Gregorian** for the early eras. Those values are actually **Julian-calendar** dates; converting them to PG requires adding the Julian→Gregorian offset for the year in question (+3 days for 7th-century CE, growing over time). The values below have been corrected to true proleptic Gregorian.

| Idx | Era | Rōmaji | CLDR raw | Raw cal | Best PG | Status | Source / notes |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 0 | 大化 | Taika | `[645, 6, 19]` | LU | `645-07-20` | ✅ | `日本書紀` 巻25 孝徳天皇紀: 「改天豐財重日足姬天皇四年、爲大化元年」 (lunisolar 皇極4年6月19日). PG **645-07-20** (Julian 645-07-17 + 3-day offset). Wikipedia's main 元号一覧 cites the *implementation* date 7月1日 (PG 645-08-01); we use proclamation date. |
| 1 | 白雉 | Hakuchi | `[650, 2, 15]` | LU | `650-03-25` | ✅ | `日本書紀` 巻25 白雉元年二月十五日条: 「大赦天下、改元白雉」 (穴戸国司獻白雉の祥瑞). PG **650-03-25** (Julian 650-03-22 + 3 days). |
| 2 | 白鳳 | Hakuhō | `[672, 1, 1]` | (placeholder) | (`672-02-08`) | ❓ | 私年号 (folk/private era) — not officially proclaimed, not in `日本書紀`. Appears in 12th-c `二中歴` and medieval 寺社縁起. CLDR's `01-01` is a placeholder; the date emitted by Calendrical for that placeholder is 672-02-08 PG but no proclamation event corresponds to it. Recommend: keep with `private_era: true`. |
| 3 | 朱鳥 | Shuchō | `[686, 7, 20]` | LU | `686-08-17` | ✅ | `日本書紀` 巻29 天武天皇下 朱鳥元年七月二十日条: 「改元曰朱鳥元年。〈朱鳥。此云阿訶美苔利。〉」. PG **686-08-17** (Julian 686-08-14 + 3 days). |
| 4 | 大宝 | Taihō | `[701, 3, 21]` | LU | `701-05-07` | ✅ | `続日本紀` 巻2 文武天皇五年三月二十一日条: 「対馬島貢金。建元為大宝元年」. PG **701-05-07** (Julian 701-05-03 + 4 days). The earlier hypothesis that this might be Julian-converted is rejected — it's LU-passthrough like the rest. |
| 5 | 慶雲 | Keiun | `[704, 5, 10]` | LU | `704-06-20` | ✅ | `続日本紀` 巻3 文武天皇三 慶雲元年五月十日条: 「改元為慶雲元年」. PG **704-06-20** (Julian 704-06-16 + 4 days). |
| 10 | 天平 | Tenpyō | `[729, 8, 5]` | LU | `729-09-06` | ✅ | `続日本紀` 神亀6年8月5日条; 瑞亀献上による改元. PG **729-09-06** (Julian 729-09-02 + 4 days). |
| 18 | 延暦 | Enryaku | `[782, 8, 19]` | LU | `782-10-04` | ✅ | `続日本紀` / `日本後紀` 巻1; 天応2年8月19日改元、桓武天皇治世下. PG **782-10-04** (Julian 782-09-30 + 4 days). Etymology: 『後漢書』巻52 「雖延暦之術 非傷寒之理」. Note: `calendrical_pg` differs from `wiki_pg` by 29 days here due to intercalary-month placement; `wiki_pg` preferred. |
| 31 | 昌泰 | Shōtai | `[898, 4, 26]` | LU | `898-05-24` | 🔶 | `日本紀略`; 寛平10年4月26日改元. PG **898-05-24** (Julian 898-05-20 + 4 days). The earlier draft of this plan placed Shōtai at idx 24 — that is in fact 仁寿 (Ninju, 851). Shōtai is idx 31. |

**Pattern observation (confirmed):** every ancient era now cross-checked against ja.wikipedia and `Calendrical.LunarJapanese` shows a **systematic LU-passthrough error** in the CLDR data. The lunisolar `年/月/日` numerals were copied into the Western fields. The actual Gregorian dates run anywhere from 25 days to 6 weeks later than the CLDR raw triple, depending on which lunar month boundary the proclamation falls near.

The bulk validation pass is therefore **mechanical**: for each pre-Meiji era, call `Calendrical.LunarJapanese.new(west_Y - 644, lunar_M, lunar_D)` (which takes a traditional lunar-month number, with `{m, :leap}` for an intercalary) and then `Date.convert/2` to `Calendar.ISO`. Where the result agrees with ja.wikipedia's published Western date (after Julian→PG shift for pre-Tenshō entries), the row is 🔶 Provisional. Where they disagree (the residual ±1d in years with astronomical-vs-historical lunar-day differences), `wiki_pg` is the historically-faithful value to ship and the row is ⚠️ Disputed pending direct Tsuchihashi / Naitō verification.

> **Note on tooling.** Earlier versions of this plan and the as-published JSON used `Date.new(year, month, day, Calendrical.LunarJapanese)` instead of `Calendrical.LunarJapanese.new/3`. The former takes **ordinal** months (1..13, with the intercalary at whatever position the no-zhongqi rule places it); the latter takes **traditional** months (1..12, with the intercalary written separately as `{m, :leap}`). Inputs lifted from Japanese chronicles are traditional, so feeding them through `Date.new/4` produces dates one full lunar month off whenever the month is past the intercalary in a leap year. A Calendrical patch (branch `fix/lunisolar-traditional-month-bug`) documents the distinction prominently and fixes a latent validator bug that previously rejected `{m, :leap}` outright. Use `Calendrical.LunarJapanese.new/3` for chronicle-derived dates.

### Middle eras — bulk pass complete (🔶 Provisional)

The bulk validation pass has been run across all 232 pre-Meiji rows. The complete results live in [plans/japanese_eras_research.json](japanese_eras_research.json). At the time of writing the as-published numbers (before the Calendrical patch and JSON regeneration) are:

* **138 rows** are 🔶 Provisional — ja.wikipedia and `Calendrical.LunarJapanese` agree on the PG date; no primary-chronicle text has been quoted directly yet, but the math is consistent.
* **80 rows** are ⚠️ Disputed — the two PG sources differ. Of these, **~36 are caller-side bugs** in the research script (ordinal-vs-traditional month confusion via `Date.new/4`); they resolve as 🔶 Provisional once the JSON is regenerated against the patched Calendrical. The remaining **~44 are genuine** differences between Calendrical's astronomical reconstruction and the historical Japanese imperial calendar — almost all Δ-1d — for which `wiki_pg` is canonical and the row stays ⚠️ Disputed pending Tsuchihashi/Naitō verification.
* **15 rows** are ✅ Verified — direct primary-chronicle text or government proclamation cited (the 4 earliest eras from `日本書紀`/`続日本紀`, 慶雲/和銅/天平/延暦 with `続日本紀`/`日本後紀` citations, 嘉永/安政 with `徳川実紀` citations, and the 5 modern eras with `太政官布告`/`勅令`/`政令`).
* **4 rows** are ❓ Needs research — 白鳳 (私年号) plus three data-quality issues (see the *Three confirmed CLDR data errors* table above).

After JSON regeneration the projected distribution is roughly **138 + 36 = 174 🔶 Provisional**, **~44 ⚠️ Disputed**, **15 ✅ Verified**, **4 ❓ Needs research**. The remaining work to lift more rows to ✅ Verified is to consult Tsuchihashi (1952) and Naitō (1992) directly for the residual Disputed rows — the JSON file marks each one with its `pg_disagreement_days` and the `wiki_pg` candidate, so the verification is mechanical.

---

## Workflow for validating one row

After the first-pass research, every row already has a candidate `best_pg` in [plans/japanese_eras_research.json](japanese_eras_research.json). The per-row workflow below is for taking a 🔶 Provisional or ⚠️ Disputed row to ✅ Verified, or for correcting a row when a reader reports an error.

1. **Look up the row in the JSON.** `jq '.eras[] | select(.idx == N)' plans/japanese_eras_research.json` returns the current entry with its `lunisolar`, `western`, `calendrical_pg`, `best_pg`, `status`, `confidence`, and existing `citations`.

2. **Find the original lunisolar date in the period chronicle.** Use the `lunisolar.display` field to look up the proclamation entry. For Asuka–Nara eras the entry is in the *Rikkokushi*; for Heian–Kamakura in `日本紀略` / `本朝世紀` / `百錬抄` / `吾妻鏡`; for Edo in `徳川実紀`.

3. **Find the Tsuchihashi entry.** Tsuchihashi (1952) is page-indexed by Japanese year (regnal year of the contemporary emperor); each Japanese year has a lunisolar-to-Julian-to-Gregorian conversion line for every day. Add the Julian→PG offset for the year if Tsuchihashi gives Julian.

4. **Cross-check with Naitō.** Naitō (1992) is organised the same way; disagreements between Tsuchihashi and Naitō are confined to a handful of disputed days, usually intercalary-month-boundary cases.

5. **Decide.** If Tsuchihashi and Naitō agree with `western.pg`, the row's `best_pg` is correct — promote to ✅ Verified and add citations. If they disagree with `western.pg` (rare), document both candidates and ship the more-cited one with status ⚠️ Disputed and `confidence: "medium"`.

6. **Cite the primary source.** Add a new entry to `citations` with `key` resolving into the bibliography (extending the bibliography if needed). Include the original-language `quote` when available, plus a `note` and `source_url`.

7. **Update the row.** Re-run the JSON generation script (see *Regeneration* in the JSON dataset section above); `status` flips from 🔶/⚠️ to ✅ and `confidence` from medium-high to high.

8. **Update the `.etf` file.** Run `mix localize.update_japanese_era <idx> <year> <month> <day>` (helper task to be written; see Implementation plan below).

Disputed rows go through code review by at least one maintainer with reading knowledge of the relevant period chronicle. Disagreements where no source clearly wins get marked ⚠️ Disputed with both candidates documented; we ship the more-cited candidate and leave a TODO note.

---

## JSON research dataset — `plans/japanese_eras_research.json`

The full research dataset is published as a structured JSON file. Every CLDR era index (0–236) is one entry, with cross-references into a shared bibliography.

### Top-level structure

```jsonc
{
  "metadata":      { … generation date, version, stats, known errors, open questions, field reference … },
  "bibliography":  { "<key>": { … } },     // 42 entries; primary chronicles, government proclamations, classical etymology refs, modern compilations, online sources, algorithmic
  "eras":          [ { … }, … ]            // 237 entries, ordered by idx
}
```

### `metadata`

| Field | Type | Description |
| --- | --- | --- |
| `generated` | string | ISO date of generation (currently `"2026-05-17"`) |
| `version` | integer | Schema version of the dataset, incremented on breaking changes |
| `schema_version` | integer | Internal schema-format version |
| `methodology` | string | Path to this plan (`"plans/japanese_eras.md"`) |
| `description` | string | One-paragraph human summary |
| `methodology_summary` | string | Algorithmic summary of how each row was produced |
| `stats` | object | `{ total, by_status, by_confidence, by_court }` aggregated counts |
| `known_cldr_errors` | array | Confirmed CLDR data errors with current/recommended triples (currently 3 entries: idx 166, 181, 183) |
| `open_questions` | array | Conventional questions (currently 2: 大化 proclamation-vs-implementation; 白鳳 inclusion) |
| `field_reference` | object | Field-by-field human description |

### `bibliography`

Map of citation `key` → reference object. Each reference has at least `title` and `type`; optional fields include `english`, `author`, `publisher`, `date`, `url`, `parent` (for chronicle-volume entries that roll up to a parent chronicle), `accessed_via`, `description`. Citation `type` values:

* `primary_chronicle` — the *Rikkokushi* and successor official records (`nihon_shoki`, `shoku_nihongi`, `azuma_kagami`, `tokugawa_jikki`, etc.) and their specific volumes (`nihon_shoki_v25`, etc.)
* `government_proclamation` — `daijokan_1868`, `chokurei_1912`, `chokurei_1926`, `seirei_1989`, `seirei_2019`
* `classical_chinese` / `classical_japanese` — etymology references (`shiki_5`, `shokyo_dai_u_bo`, `manyoshu_5`, `go_kanjo_52`, `song_shu`, `qun_shu_zhi_yao`)
* `scholarly_modern` — `tsuchihashi_1952`, `naito_1992`, `kokushi_daijiten`
* `online_encyclopedia` — `wiki` (ja.wikipedia main 元号一覧 article), plus individual-era articles `wiki_<era>` like `wiki_taika`, `wiki_kakei`, `wiki_chokyo`
* `online_archive` / `online_authority` / `online_transcription` / `online_database` — `ndl`, `naoj`, `seisaku_bz`, `inoh`
* `algorithmic` — `calendrical` (the sibling Elixir library)

### `eras[i]` schema

Every era row has the same shape. Optional fields are present only when applicable.

| Field | Type | Description |
| --- | --- | --- |
| `idx` | integer | CLDR era index (0–236) |
| `era` | string | Era name in kanji (元号) |
| `reading` | string | Hiragana reading |
| `romaji` | string \| null | Romanized reading (modern Hepburn); only populated for entries I've explicitly verified |
| `lunisolar` | object | `{ prev_era, prev_year, month, day, leap_month, display }`. `prev_era` is the era reckoning the chronicle uses for the proclamation date — for the first era of a reign or for posthumous-era cases, this can be a reign-name like `"皇極天皇"`. `display` is the canonical `元号N年M月D日` string. |
| `western` | object \| null | `{ date, calendar, pg }` — the ja.wikipedia Western date, with `calendar` ∈ `"julian"` \| `"gregorian"`, and `pg` is its proleptic-Gregorian equivalent |
| `calendrical_pg` | string \| null | PG date derived independently from `lunisolar` via `Calendrical.LunarJapanese` → `Calendar.ISO`. Use to detect intercalary-placement discrepancies. |
| `cldr_raw` | `[Y, M, D]` | The current CLDR entry as it appears in `priv/localize/supplemental_data/calendars.etf` |
| `best_pg` | string \| null | ★ The recommended PG date for Localize to publish. Equals `western.pg` where available (it reflects the historical Japanese calendar); falls back to `calendrical_pg` otherwise. |
| `court` | string | `"northern"` (北朝, 持明院統) \| `"southern"` (南朝, 大覚寺統) \| `"unified"` (pre-1336 and post-1392) |
| `status` | string | `"verified"` \| `"provisional"` \| `"disputed"` \| `"needs_research"` |
| `confidence` | string | `"high"` \| `"medium-high"` \| `"medium"` \| `"low"` \| `"unknown"` |
| `citations` | array | List of citation objects: `[{ key, quote?, note?, source_url? }, …]`. The `key` resolves into `bibliography`. `quote` is the original-language text excerpt (where I have it). `note` is a human gloss. `source_url` is a direct online link when available. |
| `notes` | string | Per-row commentary; especially important for `disputed` and `needs_research` rows |
| `recommended_cldr_correction` | `[Y, M, D]` (optional) | Present only on the 3 rows where CLDR's current triple is wrong with high confidence (idx 166, 181, 183) |
| `pg_disagreement_days` | integer (optional) | Days between `western.pg` and `calendrical_pg`; present only when they disagree |
| `private_era` | boolean (optional) | Present and `true` only on idx 2 白鳳 (the 私年号 placeholder) |

### Example row (idx 4 大宝)

```jsonc
{
  "idx": 4,
  "era": "大宝",
  "reading": "たいほう",
  "romaji": null,
  "lunisolar": {
    "prev_era": "文武天皇",
    "prev_year": 5,
    "month": 3,
    "day": 21,
    "leap_month": false,
    "display": "文武天皇5年3月21日"
  },
  "western":        { "date": "701-05-03", "calendar": "julian", "pg": "701-05-07" },
  "calendrical_pg": "701-05-07",
  "cldr_raw":       [701, 3, 21],
  "best_pg":        "701-05-07",
  "court":          "unified",
  "status":         "verified",
  "confidence":     "high",
  "citations": [
    { "key": "shoku_nihongi_v2", "quote": "対馬島貢金。建元為大宝元年" },
    { "key": "wiki",        "note": "ja.wikipedia entry for 大宝 (section: 飛鳥時代)" },
    { "key": "calendrical", "note": "Calendrical.LunarJapanese Y57 M3 D21 → PG 701-05-07" }
  ],
  "notes": ""
}
```

### Example row with a confirmed CLDR error (idx 166 嘉慶)

```jsonc
{
  "idx": 166,
  "era": "嘉慶",
  "reading": "かけい",
  "romaji": "Kakei",
  "lunisolar":      { "prev_era": "至徳", "prev_year": 4, "month": 8, "day": 23, "leap_month": false, "display": "至徳4年8月23日" },
  "western":        { "date": "1387-10-05", "calendar": "julian", "pg": "1387-10-13" },
  "calendrical_pg": "1387-09-13",
  "cldr_raw":       [1387, 8, 22],
  "best_pg":        "1387-10-13",
  "court":          "northern",
  "status":         "disputed",
  "confidence":     "medium",
  "citations": [
    { "key": "wiki_kakei",  "note": "ja.wikipedia 嘉慶_(日本) article records 至徳4年8月23日" },
    { "key": "wiki",        "note": "ja.wikipedia entry for 嘉慶 (section: 北朝（持明院統）)" },
    { "key": "calendrical", "note": "Calendrical.LunarJapanese Y743 M8 D23 → PG 1387-09-13" }
  ],
  "notes": "★ CLDR has lunar 8/22 but ja.wikipedia 嘉慶_(日本) records 至徳4年8月23日 … RECOMMENDED CORRECTION: CLDR [1387, 8, 22] → [1387, 8, 23].",
  "recommended_cldr_correction": [1387, 8, 23],
  "pg_disagreement_days": -30
}
```

### Querying the JSON

Useful one-liners (from the project root):

```bash
# Count rows by status
jq -r '.eras | group_by(.status) | map({(.[0].status): length}) | add' plans/japanese_eras_research.json

# All rows needing primary-source verification
jq '.eras[] | select(.status == "disputed") | {idx, era, best_pg, pg_disagreement_days}' plans/japanese_eras_research.json

# All Southern Court eras
jq '.eras[] | select(.court == "southern") | {idx, era, best_pg}' plans/japanese_eras_research.json

# Confirmed CLDR errors
jq '.metadata.known_cldr_errors' plans/japanese_eras_research.json

# Look up a specific era by idx
jq '.eras[] | select(.idx == 4)' plans/japanese_eras_research.json
```

### Regeneration

The JSON is regenerated by an Elixir script that reads `priv/localize/supplemental_data/calendars.etf` (for `cldr_raw`) and a scraped copy of the ja.wikipedia 元号一覧 article (for `lunisolar` + `western`), applies the hand-coded overrides and primary-source citations, and runs the lunisolar→PG conversion via `Calendrical.LunarJapanese`. The script is not yet checked in; once it is, regeneration will be `mix localize.japanese_eras.research` and CI can enforce that the JSON stays in sync with the underlying data.

---

## Implementation plan

The data itself lives in `priv/localize/supplemental_data/calendars.etf` under `[:japanese, :eras]`. CLDR generates this file at consolidation time from `common/supplemental/supplementalData.xml`'s `<eraData>` block.

### Step 1 — Pin the current snapshot

Before CLDR 49 ships and removes the pre-Meiji entries, freeze a copy of the current CLDR-48-derived data at `priv/localize/supplemental_data/japanese_eras_snapshot_cldr48.etf`. This is the starting point — every correction in the validation pass updates the *active* `calendars.etf` while the snapshot is preserved for diffing.

### Step 2 — Pipeline change

The `Localize.Data.Locale` consolidator currently inherits `<eraData>` from CLDR. After CLDR 49, the Japanese eras block in `supplementalData.xml` will only contain Meiji through Reiwa (5 entries). Add a build-time **merge step** that:

1. Reads the upstream CLDR 49 data (5 modern eras).
2. Reads the Localize-curated pre-Meiji eras from `priv/localize/supplemental_data/japanese_eras_curated.etf` (the file maintained per this plan).
3. Concatenates them in index order to produce the final `[:japanese, :eras]` list.

This way each CLDR refresh picks up upstream changes to Meiji-onwards (unlikely but possible — proclamations get amended occasionally) while the pre-Meiji curation is owned entirely by Localize.

### Step 3 — Validation tooling

Two Mix tasks to land alongside the data work:

* `mix localize.japanese_eras.audit` — walks the current curated set, prints any row that's ❓ or ⚠️ with the source citation, exits non-zero if any rows are still ❓ at release time. Wired into CI.

* `mix localize.japanese_eras.diff_cldr` — diffs the current curated set against the latest upstream CLDR data, flagging entries where the two disagree. Useful when CLDR pushes an upstream correction we should merge.

### Step 4 — Provenance in the runtime data

Add a `:provenance` field to each era entry:

```elixir
[24, %{
  start: [898, 5, 20],
  source: :tsuchihashi_1952,
  lunisolar: [898, 4, 26],
  status: :provisional
}]
```

Old consumers that only look at `:start` keep working. New consumers (genealogy software, calendar conversion tools) can inspect `:source` and `:status` to surface uncertainty in their UIs.

### Step 5 — Documentation

* `guides/japanese_calendar.md` (new) — overview of the Japanese era machinery, what consumers can expect from the data, what the `:status` and `:source` fields mean.

* CHANGELOG entry for the release that lands this work.

---

## Open questions

1. **Should `白鳳` (Hakuhō, era index 2) be removed?** It's a 私年号 (folk/private era) not officially proclaimed by the imperial court and not recorded in any of the *Rikkokushi*. It appears in 12th-century `二中歴` (placing it 661–683) and in medieval temple-shrine origin documents (placing it 672–685). CLDR's `[672, 1, 1]` is a placeholder; both year and month/day are editorial. **Recommend: keep with `private_era: true` and `status: :disputed`** so genealogy / historical-document consumers can opt out by filtering on the flag.

2. **~~How do we handle "Northern" vs "Southern" Court eras during the Nanboku-chō period?~~** Resolved by the first research pass: CLDR's existing data already contains **both** courts woven together — 16 Northern Court eras (暦応 through 明徳) and 8 Southern Court eras (延元, 興国, 正平, 建徳, 文中, 天授, 弘和, 元中), plus 元弘 (大覚寺統 lineage, pre-split). The earlier assumption that CLDR followed only the Northern Court was wrong. **Recommend: keep the existing interleaved sequence** and surface the `court` field (per the JSON schema above) so consumers can filter to one court if needed. No data is missing.

3. **Convention for 大化 (Taika): proclamation date or implementation date?** `日本書紀` 巻25 records the era proclamation on 皇極天皇4年6月19日 (PG 645-07-20). ja.wikipedia's main 元号一覧 instead uses 7月1日 (PG 645-08-01) as the *implementation* date — when documents began to be dated with the new era. CLDR follows the proclamation convention. **Recommend: keep proclamation date** for consistency with primary chronicles and with the rest of the set.

4. **What's the right cadence for the validation pass?** 232 entries, ~5 minutes each for the Tsuchihashi + Naitō cross-check, is ~20 hours of expert work. The first-pass automated validation (now complete) reduces this: the 138 🔶 Provisional rows where `wiki_pg` and `calendrical_pg` agree can be confirmed in bulk, and only the 80 ⚠️ Disputed rows need individual Tsuchihashi/Naitō lookup. Recommend front-loading the remaining ~80 rows into one focused push and shipping the 138 Provisional rows immediately under their current status — incremental drift between releases is a constant maintenance burden and the Provisional set is already higher-quality than the existing CLDR data.

5. The remaining ~44 disputes are real differences between Calendrical's modern astronomical reconstruction and the historical Japanese imperial calendar (Senmyō → Tenpō reki). A future enhancement to Calendrical that loaded the historical 宣明暦/貞享暦/寛政暦/天保暦 intercalary tables would close that gap, but it is a substantial undertaking and out of scope for this plan. For Localize's purposes the residual is benign because `wiki_pg` is the canonical value we ship, and it already reflects the historical calendar.

---

## Review cadence

* **Now → CLDR 49 GA (Oct 2026):** complete the methodology (this document) and pin the CLDR-48 snapshot. No data corrections yet — we're documenting the work, not doing it.

* **CLDR 49 GA + 1 month:** implement Step 2 (pipeline merge) so the runtime doesn't regress when we ingest CLDR 49.

* **CLDR 49 GA + 3 months:** complete the bulk validation pass (Step 1 + Step 4 + Step 3 tooling). Ship as part of the Localize release after CLDR-49 integration.

* **Ongoing:** when a contributor or user reports an incorrect era date, run the same one-row workflow against the cited primary source; update the entry and credit the reporter in CHANGELOG.

---

## Acknowledgements

This methodology is patterned on the work of the CLDR-TC's Japanese-eras subgroup, the National Diet Library's `元号` documentation, and the prior art at <https://github.com/google/cldr/tree/main/common/supplemental> (era data in tools/cldr-code where pre-Meiji corrections have been discussed in bug reports). All errors are Localize's responsibility, not theirs.



