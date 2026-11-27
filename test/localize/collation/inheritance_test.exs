defmodule Localize.Collation.InheritanceTest do
  # Collation data inherits along its own chain (TR35): the `collations`
  # component of `parentLocales`, stand-alone, then truncation. The main
  # component's entries and its `nonlikelyScript` rule do not apply. The
  # component carries `nb` and `nn` → `no`, a marked correction of a CLDR
  # data gap. A locale's default collation type is the `defaultCollation`
  # of the first locale on that chain that declares one.
  use ExUnit.Case, async: true

  alias Localize.Collation
  alias Localize.Collation.Tailoring
  alias Localize.Collation.Tailoring.LocaleDefaults

  # Pinyin: bei, guang, shang, tian. Stroke count: 上 3, 广 3, 天 4, 北 5.
  @cities ["北京", "上海", "广州", "天津"]
  @by_pinyin ["北京", "广州", "上海", "天津"]
  @by_stroke ["上海", "广州", "天津", "北京"]

  setup_all do
    Collation.ensure_loaded()
    :ok
  end

  defp chain(locale) do
    {:ok, tag} = Localize.validate_locale(locale)
    Tailoring.collation_chain(tag)
  end

  describe "the default collation type" do
    test "is CLDR's defaultCollation, inherited along the collation chain" do
      for {locale, type} <- [
            {"zh", :pinyin},
            {"zh-Hans", :pinyin},
            {"zh-Hans-SG", :pinyin},
            {"zh-Hant", :stroke},
            {"zh-TW", :stroke},
            {"zh-Hant-HK", :stroke},
            {"zh-Hant-MO", :stroke},
            {"yue", :stroke},
            {"yue-Hans", :pinyin}
          ] do
        assert {locale, LocaleDefaults.default_type(locale)} == {locale, type}
      end
    end

    test "is :standard for a locale that declares none, and for one that does not validate" do
      for locale <- ["de", "es", "fr-CA", "sv", "en", "ja", "not a locale!"] do
        assert {locale, LocaleDefaults.default_type(locale)} == {locale, :standard}
      end
    end
  end

  describe "the collation chain" do
    test "takes zh-Hant to zh, though its main parent is the root" do
      assert chain("zh-Hant") == [:"zh-Hant", :zh, :und]
      assert chain("zh-Hant-HK") == [:"zh-Hant", :zh, :und]
    end

    test "follows the collations component of parentLocales" do
      assert chain("yue") == [:"zh-Hant", :zh, :und]
      assert chain("yue-Hans") == [:zh, :und]
    end

    test "does not follow the main component's entries" do
      # Main parents: `hi-Latn` → `en-IN`, `es-AR` → `es-419`.
      assert chain("hi-Latn") == [:hi, :und]
      assert chain("es-AR") == [:es, :und]
    end

    test "takes Norwegian Bokmål and Nynorsk to no, by the marked correction" do
      assert chain("nb") == [:no, :und]
      assert chain("nb-SJ") == [:no, :und]
      assert chain("nn") == [:no, :und]
    end

    test "ends with the root, and is only the root for a locale with no collation data" do
      assert chain("en") == [:und]
      assert chain("fr-CA") == [:"fr-CA", :und]
    end
  end

  describe "the collation option defaults" do
    test "are found along the collation chain" do
      for locale <- ["da", "da-GL", "nb", "nb-SJ", "nn", "no", "mt", "cu"] do
        assert {locale, LocaleDefaults.options_for(locale)} == {locale, [case_first: :upper]}
      end
    end

    test "are empty where nothing on the chain has any" do
      for locale <- ["en", "hi-Latn", "sv", "und", "not a locale!"] do
        assert {locale, LocaleDefaults.options_for(locale)} == {locale, []}
      end
    end
  end

  describe "a tailoring found along the chain" do
    test "zh-Hant takes zh's stroke tailoring, and yue too" do
      {:ok, zh} = Localize.validate_locale("zh")
      zh_stroke = Tailoring.get_tailoring(zh, :stroke)

      refute is_nil(zh_stroke)
      assert Tailoring.get_tailoring("zh-Hant", :stroke) == zh_stroke
      assert Tailoring.get_tailoring("yue", :stroke) == zh_stroke
    end
  end

  describe "sorting with the default collation" do
    test "zh sorts by pinyin and zh-Hant by stroke count, unlike the root" do
      assert Collation.sort(@cities, locale: "zh") == @by_pinyin
      assert Collation.sort(@cities, locale: "zh-Hant") == @by_stroke
      assert Collation.sort(@cities, locale: "zh-TW") == @by_stroke
      assert Collation.sort(@cities, locale: "yue") == @by_stroke

      refute Collation.sort(@cities, locale: :root) == @by_pinyin
      refute Collation.sort(@cities, locale: :root) == @by_stroke
    end

    test "hi-Latn sorts as hi, as ICU does" do
      words = ["a", "क", "ॐ", "Z"]
      assert Collation.sort(words, locale: "hi-Latn") == Collation.sort(words, locale: "hi")
      refute Collation.sort(words, locale: "hi-Latn") == Collation.sort(words, locale: :root)
    end

    test "a -u-co- keyword still chooses the type" do
      assert Collation.sort(@cities, locale: "zh-u-co-stroke") == @by_stroke
      assert Collation.sort(@cities, locale: "zh-Hant-u-co-pinyin") == @by_pinyin
    end

    test "a :type option still chooses the type" do
      assert Collation.sort(@cities, locale: "zh", type: :stroke) == @by_stroke
    end
  end
end
