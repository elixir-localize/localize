# Standard date and time formats whose `datetimeSkeleton` is not the pattern's

TR35 says the `datetimeSkeleton` of a standard date format "contains a skeleton derived from the pattern", and its semantic skeletons take the lengths of the year, the month and the day from it. In 75 locales the skeleton a Gregorian standard date format resolves to gives the year, a numeric month or the day another width than the pattern beside it: 123 of the 2,628 formats (68 short, 17 medium, 20 long and 18 full). Whatever is generated from such a skeleton is written at widths the locale's own date is not. The standard time formats have the same fault in 17 locales, in 14 of which the skeleton names another hour cycle than the pattern; they follow the dates below.

## Data

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`. Three things cause it:

* **The pattern changed and the skeleton did not.** `common/main/id.xml` has the short date "d/M/yy" (line 3155) beside `yyMMdd` (line 3156), and `te.xml` has "d/M/yy" (line 2275) beside `yyMMdd` (line 2276). CLDR 48 had "dd/MM/yy" and "dd-MM-yy" there.

* **The pattern is inherited and the skeleton is the locale's own.** `zu.xml` inherits root's "y-MM-dd" (line 2325) beside its own `yyMd` (line 2326), and `en_NZ.xml` inherits `en_001`'s "dd/MM/y" (line 81) beside its own `yyMMd` (line 82).

* **The skeleton is inherited and the pattern is the locale's own.** `vi.xml` has "d/M/yy" (line 3124) and inherits root's `yMMdd` (line 3125), and `en_CA.xml` has "y-MM-dd" (line 2182) with no skeleton of its own, which the JSON converter resolves to `yyMd`.

## What goes wrong

A semantic skeleton takes its year, month and day lengths from the `datetimeSkeleton`, so in `vi` a short year, month and day asks for `yMMdd`, which `availableFormats` writes "01/04/2023", where the short date itself writes "1/4/23". An interval formatted for a standard format's skeleton is padded, or loses its padding, in the same way: in `en_CA` the short date is "2023-04-01" and its skeleton asks for a two-digit year and an unpadded month and day.

## Suggested fix

Regenerate each `datetimeSkeleton` from the pattern it resolves beside, and have the tooling check that the two agree in the widths of their numeric fields, so that a change to a pattern, or to what a locale inherits, cannot leave the skeleton behind.

## The formats

The resolved pattern and skeleton of each Gregorian standard date format in which the width of `y`, of a numeric `M` or of `d` differs. A regional locale mostly inherits both from its parent, so the cause is in the parent's file.

| Length | Pattern | `datetimeSkeleton` | Locales |
|---|---|---|---|
| short | `d/M/yy` | `yMMdd` | `bal_Latn`, `ga`, `ga_GB`, `kek`, `ks_Deva`, `kxv`, `kxv_Deva`, `kxv_Latn`, `kxv_Orya`, `kxv_Telu`, `qu`, `qu_BO`, `qu_EC`, `quc`, `scn`, `vi`, `xnr` |
| short | `d-M-y` | `yMMdd` | `ff_Adlm`, `ff_Adlm_BF`, `ff_Adlm_CM`, `ff_Adlm_GH`, `ff_Adlm_GM`, `ff_Adlm_GW`, `ff_Adlm_LR`, `ff_Adlm_MR`, `ff_Adlm_NE`, `ff_Adlm_NG`, `ff_Adlm_SL`, `ff_Adlm_SN` |
| short | `d. M. y.` | `yyMd` | `sr`, `sr_Cyrl`, `sr_Cyrl_BA`, `sr_Cyrl_ME`, `sr_Cyrl_XK`, `sr_Latn`, `sr_Latn_BA`, `sr_Latn_ME`, `sr_Latn_XK` |
| short | `M/d/yy` | `yyMMdd` | `om`, `om_KE`, `ti`, `ti_ER` |
| short | `d/M/yy` | `yyMMdd` | `ak`, `id`, `my`, `te` |
| short | `M/d/yy` | `yMMdd` | `cop`, `xh` |
| short | `d-MM-y` | `yMMdd` | `syr`, `syr_SY` |
| short | `d.M.y` | `yMMdd` | `sv_AX`, `sv_FI` |
| short | `dd/MM/yy` | `yMMdd` | `lij`, `vec` |
| short | `y-MM-dd` | `yyMd` | `en_CA`, `zu` |
| short | `M/d/y` | `yMMdd` | `blo` |
| short | `d-M-yy` | `yMMdd` | `kok_Latn` |
| short | `d. M. y` | `yyMMd` | `sl` |
| short | `d.M.yy` | `yMMdd` | `ie` |
| short | `d.M.y 'г'.` | `yyMd` | `mk` |
| short | `d.MM.y` | `yMMdd` | `pl` |
| short | `dd-MM-y` | `yyMd` | `brx` |
| short | `dd.MM.yy` | `yMMdd` | `lld` |
| short | `dd.MM.yy` | `yyMd` | `ky` |
| short | `dd/MM/y` | `yyMMd` | `en_NZ` |
| short | `y-MM-dd` | `yyMMdd` | `eo` |
| short | `y/MM/dd` | `yMd` | `en_JP` |
| medium | `d. M. y.` | `yMMdd` | `sr`, `sr_Cyrl`, `sr_Cyrl_BA`, `sr_Cyrl_ME`, `sr_Cyrl_XK`, `sr_Latn`, `sr_Latn_BA`, `sr_Latn_ME`, `sr_Latn_XK` |
| medium | `MMM d, y` | `yMMMdd` | `om`, `om_KE`, `ti`, `ti_ER` |
| medium | `d MMM y` | `yMMMdd` | `en_IN`, `eo` |
| medium | `y MMM d` | `yMMdd` | `as` |
| medium | `y թ. MMM d` | `yMMMdd` | `hy` |
| long | `d. MMMM y.` | `yMMMMdd` | `sr`, `sr_Cyrl`, `sr_Cyrl_BA`, `sr_Cyrl_ME`, `sr_Cyrl_XK`, `sr_Latn`, `sr_Latn_BA`, `sr_Latn_ME`, `sr_Latn_XK` |
| long | `MMMM d, y` | `yMMMMdd` | `om`, `om_KE`, `so`, `so_DJ`, `so_ET`, `so_KE`, `ti`, `ti_ER` |
| long | `d MMMM y` | `yMMMMdd` | `eo` |
| long | `d. MMMM y` | `yMMMMdd` | `sl` |
| long | `y թ. MMMM d` | `yMMMMdd` | `hy` |
| full | `EEEE, d. MMMM y.` | `yMMMMEEEEdd` | `sr`, `sr_Cyrl`, `sr_Cyrl_BA`, `sr_Cyrl_ME`, `sr_Cyrl_XK`, `sr_Latn`, `sr_Latn_BA`, `sr_Latn_ME`, `sr_Latn_XK` |
| full | `EEEE, MMMM d, y` | `yMMMMEEEEdd` | `so`, `so_DJ`, `so_ET`, `so_KE` |
| full | `EEEE፣ d MMMM y` | `GyMMMMEEEEdd` | `ti`, `ti_ER` |
| full | `EEE, d, MMMM, y` | `yMMMMEEEEdd` | `ak` |
| full | `EEEE, d. MMMM y` | `yMMMMEEEEdd` | `sl` |
| full | `dd,MM,y` | `yMMMMEEEEd` | `bal_Latn` |

## Time formats

The standard time formats have the same fault, and there it changes the clock: in 14 locales the skeleton names another hour cycle than the pattern, 56 of the 61 formats in 17 locales whose skeleton differs from its pattern in the hour cycle or in the width of the hour or the minute.

* **The pattern is the locale's own and the skeleton is inherited.** `common/main/cop.xml` has the short time "h:mm a" (line 1365) and no skeleton, so it resolves to root's `HHmm`.

* **The skeleton is a draft the resolved data drops.** `syr.xml` has "h:mm a" (line 1123) beside `<datetimeSkeleton draft="unconfirmed">ahmm</datetimeSkeleton>` (line 1124), so it too resolves to root's `HHmm`.

* **The pattern is inherited and the skeleton is the locale's own.** `bo.xml` inherits root's "HH:mm" (line 514) beside its own `ahmm` (line 515).

Whatever takes the skeleton for the pattern writes a 24-hour time where the locale's own is 12-hour with its day period, or the reverse: a time with no zone at a long style, formatted from the skeleton's fields without its zone as ECMA-402 specifies, is one case.

| Length | Pattern | `datetimeSkeleton` | Locales |
|---|---|---|---|
| short | `h:mm a` | `HHmm` | `cop`, `kxv`, `kxv_Latn`, `yrl_CO`, `yrl_VE` |
| short | `HH:mm` | `ahmm` | `bo`, `ii`, `ug` |
| short | `h:mm a` | `HHmm` | `syr`, `syr_SY`, `xnr` |
| short | `H.mm` | `HHmm` | `sv_FI` |
| short | `a h:mm` | `HHmm` | `ks_Deva` |
| short | `a h:mm` | `HHmm` | `kok_Latn` |
| short | `hh:mm a` | `HHmm` | `bal_Latn` |
| medium | `h:mm:ss a` | `HHmmss` | `cop`, `kxv`, `kxv_Latn`, `yrl_CO`, `yrl_VE` |
| medium | `HH:mm:ss` | `ahmmss` | `bo`, `ii`, `ug` |
| medium | `h:mm:ss a` | `HHmmss` | `syr`, `syr_SY`, `xnr` |
| medium | `H.mm.ss` | `HHmmss` | `sv_FI` |
| medium | `H:mm:ss` | `HHmmss` | `my` |
| medium | `a h:mm:ss` | `HHmmss` | `ks_Deva` |
| medium | `a h:mm:ss` | `HHmmss` | `kok_Latn` |
| medium | `hh:mm:ss a` | `HHmmss` | `bal_Latn` |
| long | `h:mm:ss a z` | `HHmmssz` | `cop`, `kxv`, `kxv_Latn`, `yrl_CO`, `yrl_VE` |
| long | `HH:mm:ss z` | `ahmmssz` | `bo`, `ii`, `ug` |
| long | `h:mm:ss a z` | `HHmmssz` | `syr`, `syr_SY`, `xnr` |
| long | `H.mm.ss z` | `HHmmssz` | `sv_FI` |
| long | `a h:mm:ss z` | `HHmmssz` | `ks_Deva` |
| long | `a h:mm:ss z` | `HHmmssz` | `kok_Latn` |
| long | `hh:mm:ss a zzz` | `HHmmssz` | `bal_Latn` |
| full | `h:mm:ss a zzzz` | `HHmmsszzzz` | `cop`, `kxv`, `kxv_Latn`, `yrl_CO`, `yrl_VE` |
| full | `HH:mm:ss zzzz` | `ahmmsszzzz` | `bo`, `ii`, `ug` |
| full | `h:mm:ss a zzzz` | `HHmmsszzzz` | `syr`, `syr_SY`, `xnr` |
| full | `HH:mm:ss zzzz` | `Hmsszzzz` | `eo` |
| full | `a h:mm:ss zzzz` | `HHmmsszzzz` | `ks_Deva` |
| full | `a h:mm:ss zzzz` | `HHmmsszzzz` | `kok_Latn` |
| full | `hh:mm:ss a zzzz` | `HHmmsszzzz` | `bal_Latn` |
