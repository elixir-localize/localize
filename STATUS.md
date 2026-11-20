# Status

**Status:** active, 2026-11-21

Localize 1.8.0 is on hex. It formats MF2 messages with TR35's Default Bidi Strategy by default, as ICU 79 does, sorts in one ICU NIF call, and fixes a crash in concurrent NIF collation that was in 1.7.1. The next release, 1.9.0, adds the string form of a date or time skeleton, `format: {:skeleton, "yMMMd"}`, which `localize_mf1` needs to format ICU's `{d, date, ::yMMMd}`. The work planned next is in `TODO.md`: reading CLDR's JSON in place of its XML wherever the JSON carries the data, and keying the locale display-name data by the parts of a locale, which is a data-version release of its own. Calendrical, Tempo and the other Localize libraries publish against it.
