# Status

**Status:** active, 2026-11-01

Localize 1.6.0 is prepared for release: a calendar may name its own eras through `era_names/1`, which Calendrical 2.5's Bangla calendar needs, since CLDR names no Bangla era. 1.5.0 (currency amount parsing) is on hex. The `localize_mf1` sibling library for ICU MessageFormat 1 is complete and not yet released. The work planned after it is in `TODO.md`: the string form of a date or time skeleton, which `localize_mf1` needs to format ICU's `{d, date, ::yMMMd}`, and reading CLDR's JSON in place of its XML wherever the JSON carries the data. Calendrical, Tempo and the other Localize libraries publish against it.
