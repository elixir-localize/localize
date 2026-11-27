# TR35: the location format of a zone with no region contradicts itself

The spec says two different things about the location format (`VVVV`) of a time zone with no region, such as `PST8PDT` and `Etc/GMT+5`.

## Text

At CLDR `6198cae999ceb4847b25ddc0815835f07fced411`, `docs/ldml/tr35-dates.md`:

* **Line 1873** — "time zones that do not have a region … such as "Etc/GMT+5" and "PST8PDT", do not. For these time zones, this format falls back to the localized offset format."

* **Line 2086**, an example of the same algorithm — "PST8PDT, generic → "Unknown Location Time" // non-location time zone", two lines after "Etc/UTC-3, standard → "UTC+3" // non-location time zone", which does fall back to the offset.

## Question

Which is intended: the localized offset format for every zone with no region, or "Unknown Location Time" (the `Etc/Unknown` exemplar city in the region format) for some? The conformance data has no case for either. Localize follows line 1873 and writes the offset.
