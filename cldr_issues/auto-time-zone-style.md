# TR35: the default time zone style, Auto, has no mapping

The semantic skeleton's time zone style defaults to Auto, but the table that maps a style to a pattern symbol gives Auto no row.

## Text

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`, `docs/ldml/tr35-dates.md`:

* **Lines 2842 to 2850**, "Time Zone Style" — "Default Value: Auto" and "Auto: Choose the best style based on the locale."

* **The semantic-to-standard mapping table** (after "Mapping to Standard Skeletons") has rows for Zone with Generic (`v`, `vvvv`), Specific (`z`, `zzzz`), Location (`VVVV`) and Offset (`O`), and none for Auto.

## Question

What does Auto map to, and where is "the best style based on the locale" found in the data? ICU4X offers no automatic style. Localize maps Auto to Specific until the spec says otherwise.
