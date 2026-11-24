defmodule Localize.Collation.AltFormsTest do
  # CLDR gives `zh` an `alt="short"` form of its pinyin, stroke and zhuyin
  # collations beside the full ones. Both are kept, and `:prefer` chooses
  # between them, as `alt` forms are chosen elsewhere in Localize. Draft
  # collations below `contributed`, and `alt="proposed"` ones, are left out,
  # as the JSON build leaves them out of the locale data.
  use ExUnit.Case, async: true

  alias Localize.Collation
  alias Localize.Collation.Tailoring

  setup_all do
    Collation.ensure_loaded()
    :ok
  end

  defp overlay(locale, type, prefer) do
    {:ok, tag} = Localize.validate_locale(locale)
    {overlay, _options} = Tailoring.get_tailoring(tag, type, prefer)
    overlay
  end

  describe "the full and short forms" do
    test "zh's pinyin, stroke and zhuyin have both, and the full form orders more characters" do
      for type <- [:pinyin, :stroke, :zhuyin] do
        full = overlay("zh", type, :standard)
        short = overlay("zh", type, :short)

        assert {type, map_size(full) > map_size(short)} == {type, true}
      end
    end

    test "the full form is the default and :prefer chooses the short one" do
      # The full pinyin rules place 𠱧 under zhòng, before 重; the short
      # rules do not name it, so it takes its implicit weight, after every
      # tailored character.
      assert Collation.sort(["重", "𠱧"], locale: "zh") == ["𠱧", "重"]
      assert Collation.sort(["重", "𠱧"], locale: "zh", prefer: :standard) == ["𠱧", "重"]
      assert Collation.sort(["重", "𠱧"], locale: "zh", prefer: :short) == ["重", "𠱧"]
    end

    test "both forms put the same common characters in the same order" do
      cities = ["北京", "上海", "广州", "天津"]

      for prefer <- [:standard, :short] do
        assert Collation.sort(cities, locale: "zh", prefer: prefer) == ["北京", "广州", "上海", "天津"]

        assert Collation.sort(cities, locale: "zh-Hant", prefer: prefer) == [
                 "上海",
                 "广州",
                 "天津",
                 "北京"
               ]
      end
    end

    test "a type with no short form uses its standard form" do
      words = ["ch", "cz", "d", "ll", "lz"]

      assert Collation.sort(words, locale: "es-u-co-trad", prefer: :short) ==
               Collation.sort(words, locale: "es-u-co-trad")
    end

    test "a :prefer that is not a form returns an error" do
      for prefer <- [:long, :variant, 42, "short", nil] do
        assert {:error, %Localize.InvalidValueError{}} =
                 Collation.sort(["a", "b"], prefer: prefer)

        assert {:error, %Localize.InvalidValueError{}} =
                 Collation.compare("a", "b", prefer: prefer)
      end
    end
  end

  describe "the weights of a large tailoring" do
    test "fit 16 bits, as a lead and a trail between the regular and the implicit weights" do
      for type <- [:pinyin, :stroke, :zhuyin], prefer <- [:standard, :short] do
        primaries =
          "zh"
          |> overlay(type, prefer)
          |> Map.values()
          |> List.flatten()
          |> Enum.map(&elem(&1, 0))

        assert {type, prefer, Enum.max(primaries) <= 0xFFFF} == {type, prefer, true}
      end
    end

    test "sort tailored Han after every regular character and before untailored Han" do
      # Latin, katakana, a Han character the pinyin rules name, and one in
      # Extension B that they do not.
      assert Collation.sort(["𠀀", "北", "ア", "a"], locale: "zh") == ["a", "ア", "北", "𠀀"]
    end
  end

  describe "draft collations" do
    test "below contributed are left out" do
      supported = Tailoring.supported_locales()

      for draft <- [{:dz, :standard}, {:wae, :standard}, {:de, :eor}, {:cs, :"digits-after"}] do
        refute draft in supported, inspect(draft)
      end

      assert Collation.sort(["ä", "a", "b", "ae"], locale: "de-u-co-eor") ==
               Collation.sort(["ä", "a", "b", "ae"], locale: "de")
    end

    test "an approved collation is not replaced by an unconfirmed proposal" do
      # The approved Spanish traditional rules make ch a letter after c; the
      # proposal also made cH one. Under the approved rules cH is c then H.
      assert Collation.sort(["ch", "cz", "cH", "d"], locale: "es-u-co-trad") == [
               "cH",
               "cz",
               "ch",
               "d"
             ]
    end
  end
end
