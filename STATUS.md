# Status

**Status:** active, 2026-11-23

Localize 1.9.0 is on hex. It adds the string form of a date or time skeleton, `format: {:skeleton, "yMMMd"}`, which `localize_mf1` needs to format ICU's `{d, date, ::yMMMd}`, brings `Localize.Message.JSON` in line with TR35's Interchange Data Model, and reads an MF2 unquoted literal as TR35's `1*name-char`. The work planned next is in `TODO.md`: reading CLDR's JSON in place of its XML wherever the JSON carries the data, and keying the locale display-name data by the parts of a locale, which is a data-version release of its own. Calendrical, Tempo and the other Localize libraries publish against it.
