defmodule Localize.InflectionListConformanceTest do
  # Conformance tests for Localize.Inflection.ConceptList, transcribed from the
  # upstream unicode-org/inflection ListTest.cpp (section 5 of the porting spec).
  # One test per upstream test case; expected strings are byte-for-byte from the
  # upstream REQUIRE assertions.

  use ExUnit.Case, async: false

  alias Localize.Inflection.{Concept, ConceptList, SpeakableString}

  defp concept!(locale, value) do
    {:ok, concept} = Concept.new(locale, value)
    concept
  end

  defp and_list!(locale, items) do
    {:ok, list} = ConceptList.and_list(locale, Enum.map(items, &concept!(locale, &1)))
    list
  end

  defp or_list!(locale, items) do
    {:ok, list} = ConceptList.or_list(locale, Enum.map(items, &concept!(locale, &1)))
    list
  end

  defp and_join(locale, items) do
    ConceptList.to_speakable_string(and_list!(locale, items))
  end

  defp or_join(locale, items) do
    ConceptList.to_speakable_string(or_list!(locale, items))
  end

  defp and_join_with_suffix(locale, items, suffix) do
    locale
    |> and_list!(items)
    |> ConceptList.put_separator(:item_suffix, suffix)
    |> ConceptList.to_speakable_string()
  end

  # Setter bundle from ListTest#testSetters: before_first 1, item_prefix 2,
  # item_suffix 3, after_first 4, item_delimiter 5, before_last 6, after_last 7.
  defp setter_bundle(list) do
    list
    |> ConceptList.put_separator(:before_first, "1")
    |> ConceptList.put_separator(:item_prefix, "2")
    |> ConceptList.put_separator(:item_suffix, "3")
    |> ConceptList.put_separator(:after_first, "4")
    |> ConceptList.put_separator(:item_delimiter, "5")
    |> ConceptList.put_separator(:before_last, "6")
    |> ConceptList.put_separator(:after_last, "7")
  end

  test "5.1 testSemanticFeatures (es)" do
    concepts = Enum.map(["gato", "gata", "gatos", "gatas"], &concept!(:es, &1))
    {:ok, list} = ConceptList.and_list(:es, concepts)

    # 1: plain render
    assert ConceptList.to_speakable_string(list) == "gato, gata, gatos y gatas"

    # 2: grammar category -> first member's value
    assert ConceptList.feature_value(list, "gender") == :masculine

    # 3: non-category feature -> whole-list render under the feature
    assert ConceptList.feature_value(list, "withDePrepArticle") ==
             "del gato, de la gata, de los gatos y de las gatas"

    # 4: constraint propagation to every member
    pair = Enum.map(["gato", "gata"], &concept!(:es, &1))
    {:ok, pair_list} = ConceptList.and_list(:es, pair)
    {:ok, plural_list} = ConceptList.put_constraint(pair_list, "number", "plural")
    assert ConceptList.to_speakable_string(plural_list) == "gatos y gatas"

    # 5: reset() — structs are values, so the pre-constraint list value IS the
    # reset list
    assert ConceptList.to_speakable_string(pair_list) == "gato y gata"

    # 6: putConstraint again after reset
    {:ok, plural_again} = ConceptList.put_constraint(pair_list, "number", "plural")
    assert ConceptList.to_speakable_string(plural_again) == "gatos y gatas"

    # 7: clearConstraintByName("number") — equivalent to the unconstrained value
    assert ConceptList.to_speakable_string(pair_list) == "gato y gata"
  end

  test "5.2 testSetters (en)" do
    list = and_list!(:en, ["a", "b", "c", "d"])

    # 1: default CLDR wiring
    assert ConceptList.to_speakable_string(list) == "a, b, c, and d"

    # 2: all seven setters applied
    configured = setter_bundle(list)
    assert ConceptList.to_speakable_string(configured) == "12a342b352c362d37"

    # 3: UNRESOLVED: toString() debug form `[a, b, c, d]` — ConceptList exposes
    # no debug-string API equivalent to the C++ toString().

    # 4: setting after_first and before_last to "" un-sets them; every gap falls
    # back to the item_delimiter
    unset =
      configured
      |> ConceptList.put_separator(:after_first, "")
      |> ConceptList.put_separator(:before_last, "")

    assert ConceptList.to_speakable_string(unset) == "12a352b352c352d37"

    # 5: isExists()
    assert ConceptList.exists?(configured) == true

    # 6: empty list with every setter configured
    {:ok, empty} = ConceptList.and_list(:en, [])
    empty = setter_bundle(empty)
    assert ConceptList.to_speakable_string(empty) == nil
    assert ConceptList.exists?(empty) == false
    assert ConceptList.feature_value(empty, "number") == nil

    # 7: single item — before_first <> prefix <> item <> suffix <> after_last
    single = setter_bundle(and_list!(:en, ["a"]))
    assert ConceptList.to_speakable_string(single) == "12a37"

    # 8: two items — gap is after_first <> before_last
    double = setter_bundle(and_list!(:en, ["a", "b"]))
    assert ConceptList.to_speakable_string(double) == "12a3462b37"
  end

  test "5.3 testListFromConcepts (en)" do
    concepts = Enum.map(["1", "2", "3", "4"], &concept!(:en, &1))
    {:ok, list} = ConceptList.and_list(:en, concepts)

    # 1: print of the assembled list
    assert SpeakableString.print(ConceptList.to_speakable_string(list)) == "1, 2, 3, and 4"

    # 2: get(1) renders the same as the second input concept's own render
    second = Enum.at(list.concepts, 1)

    assert Concept.to_speakable_string(second) ==
             Concept.to_speakable_string(Enum.at(concepts, 1))
  end

  test "5.4 testListEn (en)" do
    assert and_join(:en, ["1"]) == "1"
    assert and_join(:en, ["1", "2"]) == "1 and 2"
    assert and_join(:en, ["1", "2", "3"]) == "1, 2, and 3"
    assert and_join(:en, ["1", "2", "3", "4"]) == "1, 2, 3, and 4"
    assert and_join(:en, ["1 and 2", "3 and 4", "5 and 6"]) == "1 and 2, 3 and 4, and 5 and 6"

    assert and_join(:en, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane, and Joan"

    assert or_join(:en, ["1"]) == "1"
    assert or_join(:en, ["1", "2"]) == "1 or 2"
    assert or_join(:en, ["1", "2", "3"]) == "1, 2, or 3"
    assert or_join(:en, ["1", "2", "3", "4"]) == "1, 2, 3, or 4"

    assert or_join(:en, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane, or Joan"
  end

  test "5.5 testSpeakAndValueEn / testSpeakOrValueEn (en) — speak channel" do
    items = [{"1", "one"}, {"2", "two"}, {"3", "three"}]

    and_result = ConceptList.to_speakable_string(and_list!(:en, items))
    assert SpeakableString.print(and_result) == "1, 2, and 3"
    assert SpeakableString.speak(and_result) == "one, two, and three"
    assert and_result == {"1, 2, and 3", "one, two, and three"}

    or_result = ConceptList.to_speakable_string(or_list!(:en, items))
    assert SpeakableString.print(or_result) == "1, 2, or 3"
    assert SpeakableString.speak(or_result) == "one, two, or three"
    assert or_result == {"1, 2, or 3", "one, two, or three"}
  end

  test "5.6 testListDe (de)" do
    assert and_join(:de, ["1"]) == "1"
    assert and_join(:de, ["1", "2"]) == "1 und 2"
    assert and_join(:de, ["1", "2", "3"]) == "1, 2 und 3"
    assert and_join(:de, ["1", "2", "3", "4"]) == "1, 2, 3 und 4"

    assert and_join(:de, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane und Joan"

    assert or_join(:de, ["1"]) == "1"
    assert or_join(:de, ["1", "2"]) == "1 oder 2"
    assert or_join(:de, ["1", "2", "3"]) == "1, 2 oder 3"
    assert or_join(:de, ["1", "2", "3", "4"]) == "1, 2, 3 oder 4"

    assert or_join(:de, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane oder Joan"
  end

  test "5.7 testListFr (fr)" do
    assert and_join(:fr, ["1"]) == "1"
    assert and_join(:fr, ["1", "2"]) == "1 et 2"
    assert and_join(:fr, ["1", "2", "3"]) == "1, 2 et 3"
    assert and_join(:fr, ["1", "2", "3", "4"]) == "1, 2, 3 et 4"

    assert and_join(:fr, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane et Joan"

    assert or_join(:fr, ["1"]) == "1"
    assert or_join(:fr, ["1", "2"]) == "1 ou 2"
    assert or_join(:fr, ["1", "2", "3"]) == "1, 2 ou 3"
    assert or_join(:fr, ["1", "2", "3", "4"]) == "1, 2, 3 ou 4"

    assert or_join(:fr, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane ou Joan"
  end

  test "5.8 testListTh (th)" do
    assert and_join(:th, ["1"]) == "1"
    assert and_join(:th, ["1", "2"]) == "1 และ 2"
    assert and_join(:th, ["1", "2", "3"]) == "1, 2 และ 3"
    assert and_join(:th, ["1", "2", "3", "4"]) == "1, 2, 3 และ 4"

    assert and_join(:th, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane และ Joan"

    assert or_join(:th, ["1"]) == "1"
    assert or_join(:th, ["1", "2"]) == "1 หรือ 2"
    assert or_join(:th, ["1", "2", "3"]) == "1, 2 หรือ 3"
    assert or_join(:th, ["1", "2", "3", "4"]) == "1, 2, 3 หรือ 4"

    assert or_join(:th, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane หรือ Joan"
  end

  test "5.9 testListAr (ar)" do
    assert and_join(:ar, ["1"]) == "1"
    assert and_join(:ar, ["1", "2"]) == "1، و2"
    assert and_join(:ar, ["1", "2", "3"]) == "1، و2، و3"
    assert and_join(:ar, ["1", "2", "3", "4"]) == "1، و2، و3، و4"

    assert and_join(:ar, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe، وJohn Junior، وJane، وJoan"

    assert or_join(:ar, ["1"]) == "1"
    assert or_join(:ar, ["1", "2"]) == "1، أو 2"
    assert or_join(:ar, ["1", "2", "3"]) == "1، أو 2، أو 3"
    assert or_join(:ar, ["1", "2", "3", "4"]) == "1، أو 2، أو 3، أو 4"

    assert or_join(:ar, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe، أو John Junior، أو Jane، أو Joan"
  end

  test "5.10 testListHe (he)" do
    assert and_join(:he, ["1"]) == "1"
    assert and_join(:he, ["1", "2"]) == "1 ו-2"
    assert and_join(:he, ["1", "2", "3"]) == "1, 2 ו-3"
    assert and_join(:he, ["1", "2", "3", "4"]) == "1, 2, 3 ו-4"

    assert and_join(:he, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane ו-Joan"

    # Last item in Hebrew script -> vav attaches directly, no hyphen
    assert and_join(:he, ["אחת", "שתיים", "שלוש", "ארבע"]) == "אחת, שתיים, שלוש וארבע"

    # Only the LAST item's script matters
    assert and_join(:he, ["1", "2", "3", "ארבע"]) == "1, 2, 3 וארבע"

    assert or_join(:he, ["1"]) == "1"
    assert or_join(:he, ["1", "2"]) == "1 או 2"
    assert or_join(:he, ["1", "2", "3"]) == "1, 2 או 3"
    assert or_join(:he, ["1", "2", "3", "4"]) == "1, 2, 3 או 4"

    assert or_join(:he, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane או Joan"

    # Or-form is static; unchanged for Hebrew script
    assert or_join(:he, ["אחת", "שתיים", "שלוש", "ארבע"]) == "אחת, שתיים, שלוש או ארבע"
  end

  test "5.11 testListJa (ja)" do
    # 1: empty and-list with honorific suffix — the C++ asserts an empty
    # string; the port renders nil for an empty list (spec section 1.5)
    {:ok, empty} = ConceptList.and_list(:ja, [])
    empty = ConceptList.put_separator(empty, :item_suffix, "さん")
    assert ConceptList.to_speakable_string(empty) == nil

    # 2-6: honorific suffix さん appended to every item
    assert and_join_with_suffix(:ja, ["1"], "さん") == "1さん"
    assert and_join_with_suffix(:ja, ["1", "2"], "さん") == "1さんと2さん"
    assert and_join_with_suffix(:ja, ["1", "2", "3"], "さん") == "1さんと2さん、3さん"
    assert and_join_with_suffix(:ja, ["1", "2", "3", "4"], "さん") == "1さんと2さん、3さん、4さん"

    assert and_join_with_suffix(:ja, ["Joe", "John Junior", "Jane", "Joan"], "さん") ==
             "JoeさんとJohn Juniorさん、Janeさん、Joanさん"

    # 7-11: plain and-lists — first gap と, later gaps 、
    assert and_join(:ja, ["1"]) == "1"
    assert and_join(:ja, ["1", "2"]) == "1と2"
    assert and_join(:ja, ["1", "2", "3"]) == "1と2、3"
    assert and_join(:ja, ["1", "2", "3", "4"]) == "1と2、3、4"

    assert and_join(:ja, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "JoeとJohn Junior、Jane、Joan"

    # 12-16: or-lists — first gap または, later gaps 、
    assert or_join(:ja, ["1"]) == "1"
    assert or_join(:ja, ["1", "2"]) == "1または2"
    assert or_join(:ja, ["1", "2", "3"]) == "1または2、3"
    assert or_join(:ja, ["1", "2", "3", "4"]) == "1または2、3、4"

    assert or_join(:ja, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "JoeまたはJohn Junior、Jane、Joan"

    # 17-23: affix redundancy suppression — さん is not doubled when the item
    # already ends with it
    assert and_join_with_suffix(:ja, ["お母さん"], "さん") == "お母さん"
    assert and_join_with_suffix(:ja, ["太郎"], "さん") == "太郎さん"
    assert and_join_with_suffix(:ja, ["太郎さん"], "さん") == "太郎さん"
    assert and_join_with_suffix(:ja, ["お母さん", "お父さん"], "さん") == "お母さんとお父さん"

    assert and_join_with_suffix(:ja, ["お母さん", "お父さん", "おじいさん"], "さん") ==
             "お母さんとお父さん、おじいさん"

    assert and_join_with_suffix(:ja, ["お母さん", "太郎", "愛子"], "さん") ==
             "お母さんと太郎さん、愛子さん"

    assert and_join_with_suffix(:ja, ["斎藤さん", "工藤", "近藤", "後藤さん"], "さん") ==
             "斎藤さんと工藤さん、近藤さん、後藤さん"
  end

  test "5.12 testListEs (es)" do
    assert and_join(:es, ["1"]) == "1"
    assert and_join(:es, ["1", "2"]) == "1 y 2"
    assert and_join(:es, ["1", "2", "3"]) == "1, 2 y 3"
    assert and_join(:es, ["1", "2", "3", "4"]) == "1, 2, 3 y 4"

    assert and_join(:es, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane y Joan"

    # y -> e before an i-sound (i, í, y, with silent leading h skipped)
    assert and_join(:es, ["Joe", "John Junior", "Jane", "Ivan"]) ==
             "Joe, John Junior, Jane e Ivan"

    assert and_join(:es, ["Joe", "John Junior", "Jane", "Hivan"]) ==
             "Joe, John Junior, Jane e Hivan"

    assert and_join(:es, ["Joe", "John Junior", "Jane", "Ívan"]) ==
             "Joe, John Junior, Jane e Ívan"

    assert and_join(:es, ["Joe", "John Junior", "Jane", "Hívan"]) ==
             "Joe, John Junior, Jane e Hívan"

    assert and_join(:es, ["Joe", "John Junior", "Jane", "Yvan"]) ==
             "Joe, John Junior, Jane e Yvan"

    assert and_join(:es, ["Joe", "John Junior", "Jane", "Hyvan"]) ==
             "Joe, John Junior, Jane e Hyvan"

    # Diphthong exception: i-sound followed by a vowel keeps y
    assert and_join(:es, ["Joe", "John Junior", "Jane", "Hierro"]) ==
             "Joe, John Junior, Jane y Hierro"

    assert and_join(:es, ["Joe", "John Junior", "Jane", "Yeso"]) ==
             "Joe, John Junior, Jane y Yeso"

    assert and_join(:es, ["Joe", "John Junior", "Jane", "Hyeso"]) ==
             "Joe, John Junior, Jane y Hyeso"

    assert or_join(:es, ["1"]) == "1"
    assert or_join(:es, ["1", "2"]) == "1 o 2"
    assert or_join(:es, ["1", "2", "3"]) == "1, 2 o 3"
    assert or_join(:es, ["1", "2", "3", "4"]) == "1, 2, 3 o 4"

    assert or_join(:es, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane o Joan"

    # o -> u before an o-sound (o, ó, leading h skipped)
    assert or_join(:es, ["Joe", "John Junior", "Jane", "Omar"]) ==
             "Joe, John Junior, Jane u Omar"

    assert or_join(:es, ["Joe", "John Junior", "Jane", "Homar"]) ==
             "Joe, John Junior, Jane u Homar"

    assert or_join(:es, ["Joe", "John Junior", "Jane", "Ómar"]) ==
             "Joe, John Junior, Jane u Ómar"

    assert or_join(:es, ["Joe", "John Junior", "Jane", "Hómar"]) ==
             "Joe, John Junior, Jane u Hómar"

    # NO diphthong exception for or-lists
    assert or_join(:es, ["Joe", "John Junior", "Jane", "Oita"]) ==
             "Joe, John Junior, Jane u Oita"
  end

  test "5.13 testListDirectFromCommonConceptFactoryProvider (es-MX)" do
    assert and_join(:"es-MX", ["Jane", "Joan"]) == "Jane y Joan"
    assert and_join(:"es-MX", ["Jane", "Ivan"]) == "Jane e Ivan"
  end

  test "5.14 testListIt (it)" do
    assert and_join(:it, ["1"]) == "1"
    assert and_join(:it, ["1", "2"]) == "1 e 2"
    assert and_join(:it, ["Jane", "Joan"]) == "Jane e Joan"
    assert and_join(:it, ["Jane", "Angela"]) == "Jane e Angela"
    assert and_join(:it, ["1", "2", "3"]) == "1, 2 e 3"
    assert and_join(:it, ["Joe", "Jane", "Joan"]) == "Joe, Jane e Joan"
    assert and_join(:it, ["Joe", "Jane", "Angela"]) == "Joe, Jane e Angela"
    assert and_join(:it, ["1", "2", "3", "4"]) == "1, 2, 3 e 4"

    assert and_join(:it, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane e Joan"

    # e -> ed when the LAST item starts with an e-sound
    assert and_join(:it, ["aereo", "elicottero"]) == "aereo ed elicottero"
    assert and_join(:it, ["elicottero", "aereo"]) == "elicottero e aereo"

    assert or_join(:it, ["1"]) == "1"
    assert or_join(:it, ["1", "2"]) == "1 o 2"
    assert or_join(:it, ["Jane", "Joan"]) == "Jane o Joan"
    assert or_join(:it, ["Jane", "Angela"]) == "Jane o Angela"
    assert or_join(:it, ["1", "2", "3"]) == "1, 2 o 3"
    assert or_join(:it, ["Joe", "Jane", "Joan"]) == "Joe, Jane o Joan"
    assert or_join(:it, ["Joe", "Jane", "Angela"]) == "Joe, Jane o Angela"
    assert or_join(:it, ["1", "2", "3", "4"]) == "1, 2, 3 o 4"

    assert or_join(:it, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane o Joan"

    # Or is static: no o -> od rule
    assert or_join(:it, ["casa", "ostello"]) == "casa o ostello"
    assert or_join(:it, ["ostello", "casa"]) == "ostello o casa"
    assert or_join(:it, ["casa", "hotel"]) == "casa o hotel"
  end

  test "5.15 testListKo (ko)" do
    # 1: empty and-list with honorific suffix — C++ asserts empty; the port
    # renders nil for an empty list (spec section 1.5)
    {:ok, empty} = ConceptList.and_list(:ko, [])
    empty = ConceptList.put_separator(empty, :item_suffix, "님")
    assert ConceptList.to_speakable_string(empty) == nil

    # 2-3: honorific suffix; the 과/와 particle is chosen from the RAW
    # (unsuffixed) penultimate item
    assert and_join_with_suffix(:ko, ["1"], "님") == "1님"
    assert and_join_with_suffix(:ko, ["1", "2"], "님") == "1님과 2님"

    # 4-12: and-lists — 과 after consonant-final, 와 after vowel-final
    assert and_join(:ko, ["1"]) == "1"
    assert and_join(:ko, ["1", "2"]) == "1과 2"
    assert and_join(:ko, ["Angela", "Joan"]) == "Angela와 Joan"
    assert and_join(:ko, ["John", "Joan"]) == "John과 Joan"
    assert and_join(:ko, ["1", "2", "3"]) == "1, 2과 3"
    assert and_join(:ko, ["Joe", "Angela", "Joan"]) == "Joe, Angela와 Joan"
    assert and_join(:ko, ["Joe", "John", "Joan"]) == "Joe, John과 Joan"
    assert and_join(:ko, ["1", "2", "3", "4"]) == "1, 2, 3과 4"

    assert and_join(:ko, ["Joe", "John Junior", "Angela", "Joan"]) ==
             "Joe, John Junior, Angela와 Joan"

    # 13-21: or-lists — static 또는 with no leading space
    assert or_join(:ko, ["1"]) == "1"
    assert or_join(:ko, ["1", "2"]) == "1또는 2"
    assert or_join(:ko, ["Jane", "Joan"]) == "Jane또는 Joan"
    assert or_join(:ko, ["Jane", "Angela"]) == "Jane또는 Angela"
    assert or_join(:ko, ["1", "2", "3"]) == "1, 2또는 3"
    assert or_join(:ko, ["Joe", "Jane", "Joan"]) == "Joe, Jane또는 Joan"
    assert or_join(:ko, ["Joe", "Jane", "Angela"]) == "Joe, Jane또는 Angela"
    assert or_join(:ko, ["1", "2", "3", "4"]) == "1, 2, 3또는 4"

    assert or_join(:ko, ["Joe", "John Junior", "Angela", "Joan"]) ==
             "Joe, John Junior, Angela또는 Joan"
  end

  test "5.16 testListZh (zh)" do
    assert and_join(:zh, ["1"]) == "1"
    assert and_join(:zh, ["1", "2"]) == "1和2"
    assert and_join(:zh, ["1", "2", "3"]) == "1、2和3"
    assert and_join(:zh, ["1", "2", "3", "4"]) == "1、2、3和4"

    assert and_join(:zh, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe、John Junior、Jane和Joan"

    assert or_join(:zh, ["1"]) == "1"
    assert or_join(:zh, ["1", "2"]) == "1或2"
    assert or_join(:zh, ["1", "2", "3"]) == "1、2或3"
    assert or_join(:zh, ["1", "2", "3", "4"]) == "1、2、3或4"

    assert or_join(:zh, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe、John Junior、Jane或Joan"
  end

  test "5.17 testListYue (zh-HK routes to yue)" do
    assert and_join(:"zh-HK", ["1"]) == "1"
    assert and_join(:"zh-HK", ["1", "2"]) == "1同2"
    assert and_join(:"zh-HK", ["1", "2", "3"]) == "1、2同3"
    assert and_join(:"zh-HK", ["1", "2", "3", "4"]) == "1、2、3同4"

    assert and_join(:"zh-HK", ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe、John Junior、Jane同Joan"

    assert or_join(:"zh-HK", ["1"]) == "1"
    assert or_join(:"zh-HK", ["1", "2"]) == "1或2"
    assert or_join(:"zh-HK", ["1", "2", "3"]) == "1、2或3"
    assert or_join(:"zh-HK", ["1", "2", "3", "4"]) == "1、2、3或4"

    assert or_join(:"zh-HK", ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe、John Junior、Jane或Joan"
  end

  test "5.18 testListSv (sv)" do
    assert and_join(:sv, ["1"]) == "1"
    assert and_join(:sv, ["1", "2"]) == "1 och 2"
    assert and_join(:sv, ["1", "2", "3"]) == "1, 2 och 3"
    assert and_join(:sv, ["1", "2", "3", "4"]) == "1, 2, 3 och 4"

    assert and_join(:sv, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane och Joan"

    assert or_join(:sv, ["1"]) == "1"
    assert or_join(:sv, ["1", "2"]) == "1 eller 2"
    assert or_join(:sv, ["1", "2", "3"]) == "1, 2 eller 3"
    assert or_join(:sv, ["1", "2", "3", "4"]) == "1, 2, 3 eller 4"

    assert or_join(:sv, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane eller Joan"
  end

  test "5.18 testListNb (nb)" do
    assert and_join(:nb, ["1"]) == "1"
    assert and_join(:nb, ["1", "2"]) == "1 og 2"
    assert and_join(:nb, ["1", "2", "3"]) == "1, 2 og 3"
    assert and_join(:nb, ["1", "2", "3", "4"]) == "1, 2, 3 og 4"

    assert and_join(:nb, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane og Joan"

    assert or_join(:nb, ["1"]) == "1"
    assert or_join(:nb, ["1", "2"]) == "1 eller 2"
    assert or_join(:nb, ["1", "2", "3"]) == "1, 2 eller 3"
    assert or_join(:nb, ["1", "2", "3", "4"]) == "1, 2, 3 eller 4"

    assert or_join(:nb, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane eller Joan"
  end

  test "5.18 testListDa (da)" do
    assert and_join(:da, ["1"]) == "1"
    assert and_join(:da, ["1", "2"]) == "1 og 2"
    assert and_join(:da, ["1", "2", "3"]) == "1, 2 og 3"
    assert and_join(:da, ["1", "2", "3", "4"]) == "1, 2, 3 og 4"

    assert and_join(:da, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane og Joan"

    assert or_join(:da, ["1"]) == "1"
    assert or_join(:da, ["1", "2"]) == "1 eller 2"
    assert or_join(:da, ["1", "2", "3"]) == "1, 2 eller 3"
    assert or_join(:da, ["1", "2", "3", "4"]) == "1, 2, 3 eller 4"

    assert or_join(:da, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane eller Joan"
  end

  test "5.18 testListPt (pt)" do
    assert and_join(:pt, ["1"]) == "1"
    assert and_join(:pt, ["1", "2"]) == "1 e 2"
    assert and_join(:pt, ["1", "2", "3"]) == "1, 2 e 3"
    assert and_join(:pt, ["1", "2", "3", "4"]) == "1, 2, 3 e 4"

    assert and_join(:pt, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane e Joan"

    assert or_join(:pt, ["1"]) == "1"
    assert or_join(:pt, ["1", "2"]) == "1 ou 2"
    assert or_join(:pt, ["1", "2", "3"]) == "1, 2 ou 3"
    assert or_join(:pt, ["1", "2", "3", "4"]) == "1, 2, 3 ou 4"

    assert or_join(:pt, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane ou Joan"
  end

  test "5.18 testListNl (nl)" do
    assert and_join(:nl, ["1"]) == "1"
    assert and_join(:nl, ["1", "2"]) == "1 en 2"
    assert and_join(:nl, ["1", "2", "3"]) == "1, 2 en 3"
    assert and_join(:nl, ["1", "2", "3", "4"]) == "1, 2, 3 en 4"

    assert and_join(:nl, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane en Joan"

    assert or_join(:nl, ["1"]) == "1"
    assert or_join(:nl, ["1", "2"]) == "1 of 2"
    assert or_join(:nl, ["1", "2", "3"]) == "1, 2 of 3"
    assert or_join(:nl, ["1", "2", "3", "4"]) == "1, 2, 3 of 4"

    assert or_join(:nl, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane of Joan"
  end

  test "5.18 testListMs (ms)" do
    assert and_join(:ms, ["1"]) == "1"
    assert and_join(:ms, ["1", "2"]) == "1 dan 2"
    assert and_join(:ms, ["1", "2", "3"]) == "1, 2 dan 3"
    assert and_join(:ms, ["1", "2", "3", "4"]) == "1, 2, 3 dan 4"

    assert and_join(:ms, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane dan Joan"

    # Or final gap carries the comma (end pattern differs from two pattern)
    assert or_join(:ms, ["1"]) == "1"
    assert or_join(:ms, ["1", "2"]) == "1 atau 2"
    assert or_join(:ms, ["1", "2", "3"]) == "1, 2, atau 3"
    assert or_join(:ms, ["1", "2", "3", "4"]) == "1, 2, 3, atau 4"

    assert or_join(:ms, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane, atau Joan"
  end

  test "5.18 testListId (id)" do
    # Both styles carry the comma in the final gap for 3+ items
    assert and_join(:id, ["1"]) == "1"
    assert and_join(:id, ["1", "2"]) == "1 dan 2"
    assert and_join(:id, ["1", "2", "3"]) == "1, 2, dan 3"
    assert and_join(:id, ["1", "2", "3", "4"]) == "1, 2, 3, dan 4"

    assert and_join(:id, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane, dan Joan"

    assert or_join(:id, ["1"]) == "1"
    assert or_join(:id, ["1", "2"]) == "1 atau 2"
    assert or_join(:id, ["1", "2", "3"]) == "1, 2, atau 3"
    assert or_join(:id, ["1", "2", "3", "4"]) == "1, 2, 3, atau 4"

    assert or_join(:id, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane, atau Joan"
  end

  test "5.18 testListTr (tr)" do
    assert and_join(:tr, ["1"]) == "1"
    assert and_join(:tr, ["1", "2"]) == "1 ve 2"
    assert and_join(:tr, ["1", "2", "3"]) == "1, 2 ve 3"
    assert and_join(:tr, ["1", "2", "3", "4"]) == "1, 2, 3 ve 4"

    assert and_join(:tr, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane ve Joan"

    # Override changes the CLDR word veya -> ya da
    assert or_join(:tr, ["1"]) == "1"
    assert or_join(:tr, ["1", "2"]) == "1 ya da 2"
    assert or_join(:tr, ["1", "2", "3"]) == "1, 2 ya da 3"
    assert or_join(:tr, ["1", "2", "3", "4"]) == "1, 2, 3 ya da 4"

    assert or_join(:tr, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane ya da Joan"
  end

  test "5.18 testListRu (ru)" do
    assert and_join(:ru, ["1"]) == "1"
    assert and_join(:ru, ["1", "2"]) == "1 и 2"
    assert and_join(:ru, ["1", "2", "3"]) == "1, 2 и 3"
    assert and_join(:ru, ["1", "2", "3", "4"]) == "1, 2, 3 и 4"

    assert and_join(:ru, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane и Joan"

    assert or_join(:ru, ["1"]) == "1"
    assert or_join(:ru, ["1", "2"]) == "1 или 2"
    assert or_join(:ru, ["1", "2", "3"]) == "1, 2 или 3"
    assert or_join(:ru, ["1", "2", "3", "4"]) == "1, 2, 3 или 4"

    assert or_join(:ru, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane или Joan"
  end

  test "5.18 testListHi (hi)" do
    # And final gap carries the comma; or final gap does not
    assert and_join(:hi, ["1"]) == "1"
    assert and_join(:hi, ["1", "2"]) == "1 और 2"
    assert and_join(:hi, ["1", "2", "3"]) == "1, 2, और 3"
    assert and_join(:hi, ["1", "2", "3", "4"]) == "1, 2, 3, और 4"

    assert and_join(:hi, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane, और Joan"

    assert or_join(:hi, ["1"]) == "1"
    assert or_join(:hi, ["1", "2"]) == "1 या 2"
    assert or_join(:hi, ["1", "2", "3"]) == "1, 2 या 3"
    assert or_join(:hi, ["1", "2", "3", "4"]) == "1, 2, 3 या 4"

    assert or_join(:hi, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane या Joan"
  end

  test "5.18 testListFi (fi)" do
    assert and_join(:fi, ["1"]) == "1"
    assert and_join(:fi, ["1", "2"]) == "1 ja 2"
    assert and_join(:fi, ["1", "2", "3"]) == "1, 2 ja 3"
    assert and_join(:fi, ["1", "2", "3", "4"]) == "1, 2, 3 ja 4"

    assert and_join(:fi, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane ja Joan"

    assert or_join(:fi, ["1"]) == "1"
    assert or_join(:fi, ["1", "2"]) == "1 tai 2"
    assert or_join(:fi, ["1", "2", "3"]) == "1, 2 tai 3"
    assert or_join(:fi, ["1", "2", "3", "4"]) == "1, 2, 3 tai 4"

    assert or_join(:fi, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane tai Joan"
  end

  test "5.18 testListPl (pl)" do
    assert and_join(:pl, ["1"]) == "1"
    assert and_join(:pl, ["1", "2"]) == "1 i 2"
    assert and_join(:pl, ["1", "2", "3"]) == "1, 2 i 3"
    assert and_join(:pl, ["1", "2", "3", "4"]) == "1, 2, 3 i 4"

    assert and_join(:pl, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane i Joan"

    assert or_join(:pl, ["1"]) == "1"
    assert or_join(:pl, ["1", "2"]) == "1 lub 2"
    assert or_join(:pl, ["1", "2", "3"]) == "1, 2 lub 3"
    assert or_join(:pl, ["1", "2", "3", "4"]) == "1, 2, 3 lub 4"

    assert or_join(:pl, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane lub Joan"
  end

  test "5.18 testListVi (vi)" do
    assert and_join(:vi, ["1"]) == "1"
    assert and_join(:vi, ["1", "2"]) == "1 và 2"
    assert and_join(:vi, ["1", "2", "3"]) == "1, 2 và 3"
    assert and_join(:vi, ["1", "2", "3", "4"]) == "1, 2, 3 và 4"

    assert and_join(:vi, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane và Joan"

    assert or_join(:vi, ["1"]) == "1"
    assert or_join(:vi, ["1", "2"]) == "1 hoặc 2"
    assert or_join(:vi, ["1", "2", "3"]) == "1, 2 hoặc 3"
    assert or_join(:vi, ["1", "2", "3", "4"]) == "1, 2, 3 hoặc 4"

    assert or_join(:vi, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane hoặc Joan"
  end

  test "5.18 testListHiLatn (hi-Latn)" do
    # hi-Latn resolves its own aur/yaa patterns, not hi's
    assert and_join(:"hi-Latn", ["1"]) == "1"
    assert and_join(:"hi-Latn", ["1", "2"]) == "1 aur 2"
    assert and_join(:"hi-Latn", ["1", "2", "3"]) == "1, 2, aur 3"
    assert and_join(:"hi-Latn", ["1", "2", "3", "4"]) == "1, 2, 3, aur 4"

    assert and_join(:"hi-Latn", ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane, aur Joan"

    assert or_join(:"hi-Latn", ["1"]) == "1"
    assert or_join(:"hi-Latn", ["1", "2"]) == "1 yaa 2"
    assert or_join(:"hi-Latn", ["1", "2", "3"]) == "1, 2 yaa 3"
    assert or_join(:"hi-Latn", ["1", "2", "3", "4"]) == "1, 2, 3 yaa 4"

    assert or_join(:"hi-Latn", ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane yaa Joan"
  end

  test "5.18 testListUk (uk)" do
    assert and_join(:uk, ["1"]) == "1"
    assert and_join(:uk, ["1", "2"]) == "1 і 2"
    assert and_join(:uk, ["1", "2", "3"]) == "1, 2 і 3"
    assert and_join(:uk, ["1", "2", "3", "4"]) == "1, 2, 3 і 4"

    assert and_join(:uk, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane і Joan"

    assert or_join(:uk, ["1"]) == "1"
    assert or_join(:uk, ["1", "2"]) == "1 або 2"
    assert or_join(:uk, ["1", "2", "3"]) == "1, 2 або 3"
    assert or_join(:uk, ["1", "2", "3", "4"]) == "1, 2, 3 або 4"

    assert or_join(:uk, ["Joe", "John Junior", "Jane", "Joan"]) ==
             "Joe, John Junior, Jane або Joan"
  end

  # 5.19 testClone is intentionally not transcribed: Elixir structs are values,
  # so clone-equals-original holds by construction. The meaningful residue
  # (constraint propagation and item-prefix rendering) is covered by 5.1 and
  # the setter tests in 5.2.
end
