# Status

**Status:** active, 2026-11-09

Localize 1.7.0 is prepared for release: `strptime/3` on `Localize.Date`, `Localize.Time` and `Localize.DateTime` reads text written with a `Calendar.strftime/3` format, `Localize.Inflection` tokenizes a phrase with `unicode_string` when the consumer has it, a German noun phrase and a Hebrew word known only as a verb inflect correctly, and Latin digits read with a locale's own separators. 1.6.1 is on hex, as is the `localize_mf1` sibling library for ICU MessageFormat 1 at 0.1.0. The work planned next is in `TODO.md`: the string form of a date or time skeleton, which `localize_mf1` needs to format ICU's `{d, date, ::yMMMd}`, reading CLDR's JSON in place of its XML wherever the JSON carries the data, and keying the locale display-name data by the parts of a locale, which is a data-version release of its own. Calendrical, Tempo and the other Localize libraries publish against it.
