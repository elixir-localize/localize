# nb and nn are missing from the collations component of parentLocales

**Status:** draft, not filed, 2026-11-28

**Component:** supplemental data (`parentLocales`), collation.

## Summary

`nb` and `nn` are missing from the `collations` component of `parentLocales`, so under TR35's rule for component parents they take the root's collation instead of the Norwegian tailoring in `no.xml`.

## Details

CLDR-14493 made `nb` and `nn` children of `no` and ships them empty collation files (`common/collation/nb.xml`, `common/collation/nn.xml`), so that they inherit the Norwegian tailoring in `common/collation/no.xml`. The parent link is only in the main `parentLocales` entry: `<parentLocale parent="no" locales="nb nn no_NO"/>`.

CLDR-16253 then added component-specific parents. TR35 says these "are now not merged, but instead are treated as stand-alone". The `collations` component lists only the `yue` locales:

```xml
<parentLocales component="collations">
	<parentLocale parent="zh_Hant" locales="yue yue_Hant"/>
	<parentLocale parent="zh_Hans" locales="yue_CN yue_Hans yue_Hans_CN"/>
</parentLocales>
```

Read as specified, the collation parent of `nb` and `nn` is the root, and Norwegian Bokmål and Nynorsk lose the Norwegian tailoring.

Today this does not show in CLDR's own tools or in ICU, because both ignore component parents (CLDR-16361, ICU-22289). ICU's converter applies the main parents to collation and writes `%%Parent{"no"}` into `coll/nb.txt` and `coll/nn.txt`. Any implementation that follows TR35 as written gets the root.

## Proposed fix

Add `<parentLocale parent="no" locales="nb nn"/>` to `<parentLocales component="collations">` in `common/supplemental/supplementalData.xml`.

## Localize

Localize adds these two entries to its collation parents in the data pass, as a marked correction (`@collation_parent_corrections` in `data/supplemental.ex`). The data pass fails once CLDR lists either locale, so the correction is removed when this is fixed.
