# Status

**Status:** active, 2026-09-25

**Next release:** 1.5.0
**Blocked on:** CLDR 49 final release, expected 2026-10

Localize 1.5 is built on CLDR 49 and cannot be published until the Unicode Consortium finalises CLDR 49, expected in October 2026. Its work lives on the `cldr-49` branch, which does not merge to `main` until the final beta. Downstream libraries waiting on 1.5 name it in their own STATUS.md.

1.4.0 is an interim release from `main`, still on CLDR 48.2, and is not blocked. It carries month names read through a calendar's `month_of_year/3`, which Calendrical 1.4.0 needs.
