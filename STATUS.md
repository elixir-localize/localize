# Status

**Status:** active, 2026-09-28

**Next release:** 1.4.0
**Blocked on:** CLDR 49 final release, expected 2026-10-16

Localize 1.4.0 is built on CLDR 49 from the `cldr-49` branch, which already carries everything on `main`. It cannot be published until the Unicode Consortium finalises CLDR 49, scheduled for October 2026 with no date fixed yet. Calendrical, Tempo and the other Localize libraries publish after it.

Decided 2026-09-28: `main` is not released on its own. An interim 1.4.0 from `main` followed by CLDR 49 as 1.5.0 two weeks later would put two significant releases, each with breaking changes, in front of users and every downstream library, and no open issue needs `main` sooner. The decision is reviewed on 2026-10-16, the date on the blocker above: if cldr-json has not published 49.0.0 by then, `main` is released as 1.4.0 and the CLDR 49 work follows as 1.5.0.
