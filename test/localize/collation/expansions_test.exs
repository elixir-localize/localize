defmodule Localize.Collation.ExpansionsTest do
  # TR35 "Expansions": in `&a<z/e` the first elements of z are placed after
  # the current position, as for any relation, and the elements of the
  # extension e are appended unchanged; only the regular elements are the
  # position for the next relation. A reset is mapped by the rules applied
  # so far, so `&cs<<<ccs/cs` resets to the Hungarian letter cs.
  #
  # Every expected order here is ICU's, the reference implementation.
  use ExUnit.Case, async: true

  alias Localize.Collation

  @thorn "þ"
  @capital_thorn "Þ"

  setup_all do
    Collation.ensure_loaded()
    :ok
  end

  describe "Chinese pinyin" do
    test "sorts 重庆 (Chongqing) as chóng, after 虫 and before 崇" do
      for prefer <- [:standard, :short] do
        assert Collation.sort(["北京", "上海", "广州", "天津", "重庆"], locale: "zh", prefer: prefer) ==
                 ["北京", "重庆", "广州", "上海", "天津"]

        # After every string that begins with 虫, and before 崇; 重 alone is zhòng.
        assert Collation.sort(["崇", "重庆", "虫", "虫子", "充", "重"], locale: "zh", prefer: prefer) ==
                 ["充", "虫", "虫子", "重庆", "崇", "重"]
      end
    end

    test "sorts 沈阳 (Shenyang) as shěn" do
      assert Collation.sort(["肾", "婶", "审", "沈", "沈阳"], locale: "zh") ==
               ["沈阳", "沈", "审", "婶", "肾"]
    end
  end

  describe "þ as a variant of th" do
    test "in Swedish, Faroese and Norwegian" do
      words = ["ti", @thorn, "th", "ta", @capital_thorn, "Th"]

      for locale <- ["sv", "fo"] do
        assert {locale, Collation.sort(words, locale: locale)} ==
                 {locale, ["ta", "th", @thorn, "Th", @capital_thorn, "ti"]}
      end

      # Norwegian sorts uppercase first.
      assert Collation.sort(["TH" | words], locale: "no") ==
               ["ta", "TH", @capital_thorn, "Th", "th", @thorn, "ti"]
    end

    test "in a chain of relations, in traditional Finnish" do
      # `&T<<þ/h<<<Þ/h`: the second relation is placed after þ's regular
      # elements, not after its extension.
      assert Collation.sort(["ti", @capital_thorn, @thorn, "th", "ta", "Th"],
               locale: "fi-u-co-trad"
             ) ==
               ["ta", "th", "Th", @thorn, @capital_thorn, "ti"]
    end
  end

  describe "Hungarian double consonants" do
    test "ccs is cs doubled, a tertiary variant of cscs" do
      assert Collation.sort(["csd", "ccs", "cscs", "cse", "cs", "cz", "Ccs", "CCS"], locale: "hu") ==
               ["cz", "cs", "cscs", "ccs", "Ccs", "CCS", "csd", "cse"]
    end

    test "ddz and ggy likewise" do
      assert Collation.sort(["ggy", "gygy", "gy", "gz", "ddz", "dzdz", "dz"], locale: "hu") ==
               ["dz", "dzdz", "ddz", "gz", "gy", "gygy", "ggy"]
    end
  end

  describe "rules without expansions" do
    test "are unchanged" do
      assert Collation.sort(["o", "ñ", "nz", "oa"], locale: "es") == ["nz", "ñ", "o", "oa"]

      assert Collation.sort(["ch", "cz", "cH", "d", "ll", "lz"], locale: "es-u-co-trad") ==
               ["cH", "cz", "ch", "d", "lz", "ll"]
    end
  end
end
