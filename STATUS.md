# Status

**Status:** active, 2026-11-13

Localize 1.7.1 is prepared for release: a patch that keeps the root locale out of language matching, so `en` and `en-US` resolve to a supported English locale such as `:"en-GB"` and not to `:und`, a regression in 1.5.0 (#71). 1.7.0 is on hex, as is the `localize_mf1` sibling library for ICU MessageFormat 1 at 0.1.0. The work planned next is in `TODO.md`: the string form of a date or time skeleton, which `localize_mf1` needs to format ICU's `{d, date, ::yMMMd}`, reading CLDR's JSON in place of its XML wherever the JSON carries the data, and keying the locale display-name data by the parts of a locale, which is a data-version release of its own. Calendrical, Tempo and the other Localize libraries publish against it.
