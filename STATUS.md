# Status

**Status:** active, 2026-09-29

**Next release:** 1.4.0
**Blocked on:** CLDR 49 final release, expected 2026-10-16

Localize 1.4.0 is built on CLDR 49 from `main`, which is the only branch: the `cldr-49` branch was merged into it on 2026-09-28. It cannot be published until the Unicode Consortium finalises CLDR 49, scheduled for October 2026 with no date fixed yet. Calendrical, Tempo and the other Localize libraries publish after it.

Decided 2026-09-28: Localize is released once, on CLDR 49. An interim 1.4.0 without it, followed by CLDR 49 as 1.5.0 two weeks later, would put two significant releases, each with breaking changes, in front of users and every downstream library, and no open issue needs the interim release. The decision is reviewed on 2026-10-16, the date on the blocker above.
