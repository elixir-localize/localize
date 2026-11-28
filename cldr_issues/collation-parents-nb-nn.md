# nb and nn are missing from the collations component of parentLocales

**Status:** filed as [CLDR-19935](https://unicode-org.atlassian.net/browse/CLDR-19935), 2026-11-28

**Component:** supplemental data (`parentLocales`), collation.

## Summary

`nb` and `nn` are missing from the `collations` component of `parentLocales`, so under TR35's rule for component parents they take the root's collation instead of the Norwegian tailoring in `no.xml`.

## Details

Checked at `main` 951424004b.

CLDR-14493 (v39) made `nb` and `nn` children of `no` and ships them empty collation files (`common/collation/nb.xml`, `common/collation/nn.xml`), so that they inherit the Norwegian tailoring in `common/collation/no.xml`. The parent link is only in the main `parentLocales` entry: `<parentLocale parent="no" locales="nb nn no_NO"/>`.

CLDR-16253 (v43) then added component-specific parents. The `collations` component lists only the `yue` locales:

```xml
<parentLocales component="collations">
	<parentLocale parent="zh_Hant" locales="yue yue_Hant"/>
	<parentLocale parent="zh_Hans" locales="yue_CN yue_Hans yue_Hans_CN"/>
</parentLocales>
```

TR35's Parent Locales section says two things about how a component's parents relate to the main ones. It first says components "can have their own fallback rules that inherit from the common rules and add additional parents that supplement or override the common rules". Its note then says the component-specific parent locales "are now not merged, but instead are treated as stand-alone". Read by the note, the collation parent of `nb` and `nn` is the root, and Norwegian Bokmål and Nynorsk lose the Norwegian tailoring.

This does not show in CLDR's own tools or in ICU today, because both ignore component parents. ICU's converter applies the main parents to collation and writes `%%Parent{"no"}` into `coll/nb.txt` and `coll/nn.txt` (ICU-22289, which would read component parents, is still open). CLDR-16361, which makes CLDR's tools handle them, is accepted for v50; when it lands, CLDR's own data will give `nb` and `nn` the root collation unless they are listed.

## Proposed fix

Add `<parentLocale parent="no" locales="nb nn"/>` to `<parentLocales component="collations">` in `common/supplemental/supplementalData.xml`, and remove the "inherit from the common rules … supplement or override" wording from TR35, which the note contradicts.

## Localize

Localize adds these two entries to its collation parents in the data pass, as a marked correction (`@collation_parent_corrections` in `data/supplemental.ex`). The data pass fails once CLDR lists either locale, so the correction is removed when this is fixed.
