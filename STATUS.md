# Status

**Status:** active, 2026-09-21

**Next release:** 1.4.0
**Blocked on:** CLDR 49 final release, expected 2026-10

Localize 1.4 is built on CLDR 49 and cannot be published until the Unicode Consortium finalises CLDR 49, expected in October 2026. Its work lives on the `cldr-49` branch, which does not merge to `main` until the final beta. Downstream libraries waiting on 1.4 name it in their own STATUS.md.

1.3.0 is a maintenance release and is not blocked — `mix.exs` carries that version and it is ready to tag.
