defmodule Localize.Collation.LocaleTest do
  use ExUnit.Case, async: true

  # ===================================================================
  # Locale defaults tests
  # ===================================================================

  describe "locale defaults" do
    test "Danish sets case_first to upper" do
      opts = Localize.Collation.Options.from_locale("da")
      assert opts.case_first == :upper
    end

    test "BCP47 keys override locale defaults" do
      opts = Localize.Collation.Options.from_locale("da-u-kf-lower")
      assert opts.case_first == :lower
    end

    test "unknown locale returns default options with no tailoring" do
      opts = Localize.Collation.Options.from_locale("en")
      assert opts.tailoring == nil
    end
  end

  # ===================================================================
  # ICU4C decoll.cpp / ICU4J CollationGermanTest — Standard German
  # All 12 pairs use standard de_DE collation (NOT phonebook).
  # Source: unicode-org/icu CollationGermanTest.java
  # ===================================================================

  describe "ICU German standard (de) - from CollationGermanTest.java" do
    test "Groesse < Grossist at primary" do
      assert Localize.Collation.compare("Gr\u00F6\u00DFe", "Grossist", strength: :primary) == :lt
    end

    test "Groesse < Grossist at tertiary" do
      assert Localize.Collation.compare("Gr\u00F6\u00DFe", "Grossist", strength: :tertiary) == :lt
    end

    test "abc = a+combining-diaeresis+bc at primary" do
      assert Localize.Collation.compare("abc", "a\u0308bc", strength: :primary) == :eq
    end

    test "abc < a+combining-diaeresis+bc at tertiary" do
      assert Localize.Collation.compare("abc", "a\u0308bc", strength: :tertiary) == :lt
    end

    test "Toene > Ton at primary" do
      assert Localize.Collation.compare("T\u00F6ne", "Ton", strength: :primary) == :gt
    end

    test "Toene > Ton at tertiary" do
      assert Localize.Collation.compare("T\u00F6ne", "Ton", strength: :tertiary) == :gt
    end

    test "Toene > Tod at primary" do
      assert Localize.Collation.compare("T\u00F6ne", "Tod", strength: :primary) == :gt
    end

    test "Toene > Tofu at primary" do
      assert Localize.Collation.compare("T\u00F6ne", "Tofu", strength: :primary) == :gt
    end

    test "a+diaeresis+bc = A+diaeresis+bc at primary" do
      assert Localize.Collation.compare("a\u0308bc", "A\u0308bc", strength: :primary) == :eq
    end

    test "a+diaeresis+bc < A+diaeresis+bc at tertiary" do
      assert Localize.Collation.compare("a\u0308bc", "A\u0308bc", strength: :tertiary) == :lt
    end

    test "a-umlaut-bc = a+combining-diaeresis+bc at primary" do
      assert Localize.Collation.compare("\u00E4bc", "a\u0308bc", strength: :primary) == :eq
    end

    test "a-umlaut-bc = a+combining-diaeresis+bc at tertiary" do
      assert Localize.Collation.compare("\u00E4bc", "a\u0308bc", strength: :tertiary) == :eq
    end

    test "a-umlaut-bc < aebc at primary (standard)" do
      assert Localize.Collation.compare("\u00E4bc", "aebc", strength: :primary) == :lt
    end

    test "a-umlaut-bc < aebc at tertiary" do
      assert Localize.Collation.compare("\u00E4bc", "aebc", strength: :tertiary) == :lt
    end

    test "Strasse-eszett = Strasse at primary" do
      assert Localize.Collation.compare("Stra\u00DFe", "Strasse", strength: :primary) == :eq
    end

    test "Strasse-eszett > Strasse at tertiary" do
      assert Localize.Collation.compare("Stra\u00DFe", "Strasse", strength: :tertiary) == :gt
    end

    test "efg = efg at primary" do
      assert Localize.Collation.compare("efg", "efg", strength: :primary) == :eq
    end

    test "efg = efg at tertiary" do
      assert Localize.Collation.compare("efg", "efg", strength: :tertiary) == :eq
    end

    test "a-umlaut-bc < aebc at primary (pair 10)" do
      assert Localize.Collation.compare("\u00E4bc", "aebc", strength: :primary) == :lt
    end

    test "Strasse-eszett > Strasse at tertiary (pair 11)" do
      assert Localize.Collation.compare("Stra\u00DFe", "Strasse", strength: :tertiary) == :gt
    end
  end

  # ===================================================================
  # ICU4C escoll.cpp / ICU4J CollationSpanishTest — Spanish traditional
  # ===================================================================

  describe "ICU Spanish traditional (es-u-co-trad) - from escoll.cpp" do
    @trad_locale "es-u-co-trad"

    test "alias < allias at tertiary (traditional ch/ll)" do
      assert Localize.Collation.compare("alias", "allias", locale: @trad_locale) == :lt
    end

    test "Elliot < Emiot at tertiary (traditional)" do
      assert Localize.Collation.compare("Elliot", "Emiot", locale: @trad_locale) == :lt
    end

    test "Hello > hellO at tertiary (traditional)" do
      assert Localize.Collation.compare("Hello", "hellO", locale: @trad_locale) == :gt
    end

    test "acHc < aCHc at tertiary (traditional, CH is a letter)" do
      assert Localize.Collation.compare("acHc", "aCHc", locale: @trad_locale) == :lt
    end

    test "acc < aCHc at tertiary (traditional, CH after C)" do
      assert Localize.Collation.compare("acc", "aCHc", locale: @trad_locale) == :lt
    end

    test "alias < allias at primary (standard es)" do
      assert Localize.Collation.compare("alias", "allias", locale: "es", strength: :primary) ==
               :lt
    end

    test "Hello = hellO at primary (standard es)" do
      assert Localize.Collation.compare("Hello", "hellO", locale: "es", strength: :primary) == :eq
    end
  end

  # ===================================================================
  # ICU4C ficoll.cpp / ICU4J CollationFinnishTest — Finnish
  # ===================================================================

  describe "ICU Finnish (fi) - from ficoll.cpp" do
    @fi_locale "fi"

    test "wat > vat at tertiary (w after v)" do
      assert Localize.Collation.compare("wat", "vat", locale: @fi_locale) == :gt
    end

    test "vat < way at tertiary" do
      assert Localize.Collation.compare("vat", "way", locale: @fi_locale) == :lt
    end

    test "a-u-umlaut-beck > axbeck at tertiary (u-umlaut after x)" do
      assert Localize.Collation.compare("a\u00FCbeck", "axbeck", locale: @fi_locale) == :gt
    end

    test "L-a-ring-vi < L-a-umlaut-we at tertiary (a-ring before a-umlaut)" do
      assert Localize.Collation.compare("L\u00E5vi", "L\u00E4we", locale: @fi_locale) == :lt
    end

    test "wat > vat at primary (v < w per cldrbug 6615)" do
      assert Localize.Collation.compare("wat", "vat", locale: @fi_locale, strength: :primary) ==
               :gt
    end
  end

  # ===================================================================
  # ICU4C trcoll.cpp / ICU4J CollationTurkishTest — Turkish
  # ===================================================================

  describe "ICU Turkish (tr) - from trcoll.cpp" do
    @tr_locale "tr"

    test "old < O-umlaut-ay at tertiary (o-umlaut after o)" do
      assert Localize.Collation.compare("old", "\u00D6ay", locale: @tr_locale) == :lt
    end

    test "u-umlaut-oid < void at tertiary (u-umlaut after u, before v)" do
      assert Localize.Collation.compare("\u00FCoid", "void", locale: @tr_locale) == :lt
    end

    test "u-umlaut-oid < void at primary" do
      assert Localize.Collation.compare("\u00FCoid", "void",
               locale: @tr_locale,
               strength: :primary
             ) ==
               :lt
    end
  end

  # ===================================================================
  # Danish sort order — adapted from ICU4C / collationtest.txt
  # ===================================================================

  describe "ICU Danish (da) sort order - from collationtest.txt" do
    @da_locale "da"

    test "ae oe-slash a-ring sort after z" do
      assert Localize.Collation.compare("\u00E6", "z", locale: @da_locale) == :gt
      assert Localize.Collation.compare("\u00F8", "z", locale: @da_locale) == :gt
      assert Localize.Collation.compare("\u00E5", "z", locale: @da_locale) == :gt
    end

    test "sort order: ae before oe-slash before a-ring" do
      assert Localize.Collation.compare("\u00E6", "\u00F8", locale: @da_locale) == :lt
      assert Localize.Collation.compare("\u00F8", "\u00E5", locale: @da_locale) == :lt
    end

    test "a-umlaut is secondary variant of ae" do
      assert Localize.Collation.compare("\u00E4", "\u00E6", locale: @da_locale) == :gt
    end

    test "o-umlaut is secondary variant of oe-slash" do
      assert Localize.Collation.compare("\u00F6", "\u00F8", locale: @da_locale) == :gt
    end

    test "AE-BLE < A-umlaut-BLE (ae before a-umlaut in Danish)" do
      assert Localize.Collation.compare("\u00C6BLE", "\u00C4BLE", locale: @da_locale) == :lt
    end

    test "OE-BERG < O-umlaut-BERG (oe before o-umlaut in Danish)" do
      assert Localize.Collation.compare("\u00D8BERG", "\u00D6BERG", locale: @da_locale) == :lt
    end

    test "large Danish sort order from ICU test data" do
      sorted_pairs = [
        {"CA", "\u00C7A"},
        {"DA", "\u00D0A"},
        {"HAAG", "H\u00C5NDBOG"},
        {"STORM PETERSEN", "STORMLY"},
        {"VESTERG\u00C5RD, A", "VESTERGAARD, A"},
        {"\u00C6BLE", "\u00C4BLE"},
        {"\u00D8BERG", "\u00D6BERG"}
      ]

      for {a, b} <- sorted_pairs do
        result = Localize.Collation.compare(a, b, locale: @da_locale)

        assert result == :lt,
               "Expected #{inspect(a)} < #{inspect(b)} in Danish, got #{inspect(result)}"
      end
    end
  end

  # ===================================================================
  # Swedish
  # ===================================================================

  describe "Swedish (sv) locale integration" do
    test "a-ring a-umlaut o-umlaut sort after z" do
      assert Localize.Collation.compare("\u00E5", "z", locale: "sv") == :gt
      assert Localize.Collation.compare("\u00E4", "z", locale: "sv") == :gt
      assert Localize.Collation.compare("\u00F6", "z", locale: "sv") == :gt
    end

    test "a-ring sorts before a-umlaut which sorts before o-umlaut" do
      assert Localize.Collation.compare("\u00E5", "\u00E4", locale: "sv") == :lt
      assert Localize.Collation.compare("\u00E4", "\u00F6", locale: "sv") == :lt
    end

    test "sort Swedish letters" do
      result = Localize.Collation.sort(["\u00F6l", "\u00E5l", "\u00E4l", "zl"], locale: "sv")
      assert result == ["zl", "\u00E5l", "\u00E4l", "\u00F6l"]
    end

    test "ae is secondary variant of a-umlaut in Swedish" do
      assert Localize.Collation.compare("\u00E4", "\u00E6", locale: "sv") == :lt
    end

    test "oe-slash is secondary variant of o-umlaut in Swedish" do
      assert Localize.Collation.compare("\u00F6", "\u00F8", locale: "sv") == :lt
    end

    test "d-stroke sorts as secondary variant of d" do
      assert Localize.Collation.compare("\u0111", "d", locale: "sv") == :gt
      assert Localize.Collation.compare("\u0111", "e", locale: "sv") == :lt
    end

    test "u-umlaut sorts as secondary variant of y" do
      assert Localize.Collation.compare("\u00FC", "y", locale: "sv") == :gt
      assert Localize.Collation.compare("\u00FC", "z", locale: "sv") == :lt
    end
  end

  # ===================================================================
  # Polish — full alphabet tests
  # ===================================================================

  describe "Polish (pl) locale integration" do
    test "a-ogonek sorts after a, before b" do
      assert Localize.Collation.compare("\u0105", "a", locale: "pl") == :gt
      assert Localize.Collation.compare("\u0105", "b", locale: "pl") == :lt
    end

    test "c-acute sorts after c, before d" do
      assert Localize.Collation.compare("\u0107", "c", locale: "pl") == :gt
      assert Localize.Collation.compare("\u0107", "d", locale: "pl") == :lt
    end

    test "e-ogonek sorts after e, before f" do
      assert Localize.Collation.compare("\u0119", "e", locale: "pl") == :gt
      assert Localize.Collation.compare("\u0119", "f", locale: "pl") == :lt
    end

    test "l-stroke sorts after l, before m" do
      assert Localize.Collation.compare("\u0142", "l", locale: "pl") == :gt
      assert Localize.Collation.compare("\u0142", "m", locale: "pl") == :lt
    end

    test "n-acute sorts after n, before o" do
      assert Localize.Collation.compare("\u0144", "n", locale: "pl") == :gt
      assert Localize.Collation.compare("\u0144", "o", locale: "pl") == :lt
    end

    test "o-acute sorts after o, before p" do
      assert Localize.Collation.compare("\u00F3", "o", locale: "pl") == :gt
      assert Localize.Collation.compare("\u00F3", "p", locale: "pl") == :lt
    end

    test "s-acute sorts after s, before t" do
      assert Localize.Collation.compare("\u015B", "s", locale: "pl") == :gt
      assert Localize.Collation.compare("\u015B", "t", locale: "pl") == :lt
    end

    test "z-acute and z-dot sort after z" do
      assert Localize.Collation.compare("\u017A", "z", locale: "pl") == :gt
      assert Localize.Collation.compare("\u017C", "z", locale: "pl") == :gt
      assert Localize.Collation.compare("\u017A", "\u017C", locale: "pl") == :lt
    end

    test "full Polish sort order" do
      input = [
        "\u017Car",
        "\u017Ale",
        "zupa",
        "\u015Bwit",
        "sam",
        "tata",
        "\u0142\u00F3d\u017A",
        "las",
        "mama"
      ]

      result = Localize.Collation.sort(input, locale: "pl")

      assert result == [
               "las",
               "\u0142\u00F3d\u017A",
               "mama",
               "sam",
               "\u015Bwit",
               "tata",
               "zupa",
               "\u017Ale",
               "\u017Car"
             ]
    end
  end

  # ===================================================================
  # Croatian — digraph contractions
  # ===================================================================

  describe "Croatian (hr) locale integration" do
    test "c-caron sorts after c, before c-acute" do
      assert Localize.Collation.compare("\u010D", "c", locale: "hr") == :gt
      assert Localize.Collation.compare("\u010D", "\u0107", locale: "hr") == :lt
    end

    test "c-acute sorts after c-caron, before d" do
      assert Localize.Collation.compare("\u0107", "\u010D", locale: "hr") == :gt
      assert Localize.Collation.compare("\u0107", "d", locale: "hr") == :lt
    end

    test "dz-caron digraph sorts after d, before d-stroke" do
      assert Localize.Collation.compare("d\u017E", "d", locale: "hr") == :gt
      assert Localize.Collation.compare("d\u017E", "\u0111", locale: "hr") == :lt
    end

    test "d-stroke sorts after dz-caron, before e" do
      assert Localize.Collation.compare("\u0111", "d\u017E", locale: "hr") == :gt
      assert Localize.Collation.compare("\u0111", "e", locale: "hr") == :lt
    end

    test "lj digraph sorts after l, before m" do
      assert Localize.Collation.compare("lj", "l", locale: "hr") == :gt
      assert Localize.Collation.compare("lj", "m", locale: "hr") == :lt
    end

    test "nj digraph sorts after n, before o" do
      assert Localize.Collation.compare("nj", "n", locale: "hr") == :gt
      assert Localize.Collation.compare("nj", "o", locale: "hr") == :lt
    end

    test "s-caron sorts after s, before t" do
      assert Localize.Collation.compare("\u0161", "s", locale: "hr") == :gt
      assert Localize.Collation.compare("\u0161", "t", locale: "hr") == :lt
    end

    test "z-caron sorts after z" do
      assert Localize.Collation.compare("\u017E", "z", locale: "hr") == :gt
    end

    test "Croatian digraph case variants" do
      assert Localize.Collation.compare("d\u017E", "D\u017E", locale: "hr") == :lt
      assert Localize.Collation.compare("D\u017E", "D\u017D", locale: "hr") == :lt
    end
  end

  # ===================================================================
  # Spanish standard (es)
  # ===================================================================

  describe "Spanish standard (es) locale integration" do
    test "n-tilde sorts after n, before o" do
      assert Localize.Collation.compare("\u00F1", "n", locale: "es") == :gt
      assert Localize.Collation.compare("\u00F1", "o", locale: "es") == :lt
    end

    test "sort with n-tilde" do
      result = Localize.Collation.sort(["obra", "\u00F1o\u00F1o", "nube"], locale: "es")
      assert result == ["nube", "\u00F1o\u00F1o", "obra"]
    end
  end

  # ===================================================================
  # Spanish traditional — ch and ll contractions
  # ===================================================================

  describe "Spanish traditional (es-u-co-trad) locale integration" do
    test "ch sorts after c, before d" do
      assert Localize.Collation.compare("ch", "c", locale: "es-u-co-trad") == :gt
      assert Localize.Collation.compare("ch", "d", locale: "es-u-co-trad") == :lt
    end

    test "ll sorts after l, before m" do
      assert Localize.Collation.compare("ll", "l", locale: "es-u-co-trad") == :gt
      assert Localize.Collation.compare("ll", "m", locale: "es-u-co-trad") == :lt
    end
  end

  # ===================================================================
  # Norwegian (nb/nn) — same rules as Danish
  # ===================================================================

  describe "Norwegian Bokmal (nb) locale" do
    test "ae oe-slash a-ring sort after z" do
      assert Localize.Collation.compare("\u00E6", "z", locale: "nb") == :gt
      assert Localize.Collation.compare("\u00F8", "z", locale: "nb") == :gt
      assert Localize.Collation.compare("\u00E5", "z", locale: "nb") == :gt
    end

    test "sort order matches Danish: ae < oe-slash < a-ring" do
      assert Localize.Collation.compare("\u00E6", "\u00F8", locale: "nb") == :lt
      assert Localize.Collation.compare("\u00F8", "\u00E5", locale: "nb") == :lt
    end

    test "Norwegian Bokmal sets case_first to upper" do
      opts = Localize.Collation.Options.from_locale("nb")
      assert opts.case_first == :upper
    end
  end

  describe "Norwegian Nynorsk (nn) locale" do
    test "ae oe-slash a-ring sort after z (same as Bokmal)" do
      assert Localize.Collation.compare("\u00E6", "z", locale: "nn") == :gt
      assert Localize.Collation.compare("\u00F8", "z", locale: "nn") == :gt
      assert Localize.Collation.compare("\u00E5", "z", locale: "nn") == :gt
    end

    test "Norwegian Nynorsk sets case_first to upper" do
      opts = Localize.Collation.Options.from_locale("nn")
      assert opts.case_first == :upper
    end
  end

  # ===================================================================
  # German phonebook — expansion behavior tests
  # ===================================================================

  describe "German phonebook expansion behavior" do
    @phonebk_locale "de-u-co-phonebk"

    test "a-umlaut sorts near ae, before af" do
      assert Localize.Collation.compare("\u00E4", "af", locale: @phonebk_locale) == :lt
    end

    test "o-umlaut sorts before of" do
      assert Localize.Collation.compare("\u00F6", "of", locale: @phonebk_locale) == :lt
    end

    test "u-umlaut sorts before uf" do
      assert Localize.Collation.compare("\u00FC", "uf", locale: @phonebk_locale) == :lt
    end
  end
end
