defmodule Localize.CollationOptionsTest do
  @moduledoc """
  Collation options carried by a locale's `-u-` extension, locale tailorings,
  and the characters the root collation orders by rule rather than by table.

  Expected orderings come from ICU4C 78.3's `Collator` for each locale tag:
  numeric ordering (`kn`), upper or lower case first (`kf`), shifted
  punctuation (`ka`), strength (`ks`), a case level (`kc`), backwards
  secondary weights (`kb`), script reordering (`kr`), the German phonebook
  collation (`co`), Swedish's tailored ö, Hangul syllables and the jamo they
  decompose to, and the implicit weights of CJK ideographs, private-use and
  unassigned code points.

  """

  use ExUnit.Case, async: true

  @cases [
    {"en", "a2", "a10", :gt},
    {"en-u-kn-true", "a2", "a10", :lt},
    {"en", "a", "A", :lt},
    {"en-u-kf-upper", "a", "A", :gt},
    {"en-u-kf-lower", "a", "A", :lt},
    {"en", "a-b", "ab", :lt},
    {"en-u-ka-shifted", "a-b", "ab", :eq},
    {"en-u-ks-level1", "a", "A", :eq},
    {"en-u-ks-level1", "a", "á", :eq},
    {"en-u-ks-level2", "a", "á", :lt},
    {"en-u-ks-level2", "a", "A", :eq},
    {"en-u-kc-true-ks-level1", "a", "A", :lt},
    {"fr-u-kb-true", "coté", "côte", :gt},
    {"fr", "coté", "côte", :lt},
    {"de-u-co-phonebk", "Müller", "Mueller", :gt},
    {"de", "Müller", "Mueller", :gt},
    {"ko", "가", "각", :lt},
    {"en", "가", "가", :eq},
    {"en", "一", "二", :lt},
    {"en", "", "a", :gt},
    {"en", "͸", "͹", :lt},
    {"en-u-kr-grek-latn", "α", "a", :lt},
    {"en", "α", "a", :gt},
    {"en-u-kr-digit-latn", "1", "a", :lt},
    {"sv", "ö", "z", :gt},
    {"en", "ö", "z", :lt}
  ]

  test "orderings match ICU" do
    for {locale, string_a, string_b, expected} <- @cases do
      assert {locale, string_a, string_b,
              Localize.Collation.compare(string_a, string_b, locale: locale)} ==
               {locale, string_a, string_b, expected}
    end
  end
end
