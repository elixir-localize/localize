defmodule Localize.Rfc5646.HelpersTest do
  use ExUnit.Case, async: true

  alias Localize.Rfc5646.Helpers

  describe "combine_attributes_and_keywords/1" do
    test "merges attributes into the keyword map" do
      assert Helpers.combine_attributes_and_keywords([
               {:attributes, ["foo"]},
               %{"ca" => "gregory"}
             ]) == %{:attributes => ["foo"], "ca" => "gregory"}
    end

    test "returns a lone map unchanged" do
      assert Helpers.combine_attributes_and_keywords([%{"ca" => "gregory"}]) ==
               %{"ca" => "gregory"}
    end
  end

  describe "collapse_extension/1" do
    test "groups non-type values under the type key" do
      assert Helpers.collapse_extension(
               type: "u",
               attribute: "foo",
               attribute: "bar"
             ) == %{"u" => ["foo", "bar"]}
    end
  end

  describe "merge_langtag_and_transform/1" do
    test "builds a language tag from a keyword list and merges subtags" do
      result = Helpers.merge_langtag_and_transform([[language: :en], %{"m0" => "ungegn"}])

      assert result["m0"] == "ungegn"
      assert %Localize.LanguageTag{language: :en} = result["language"]
    end

    test "wraps a lone keyword list in a language map" do
      result = Helpers.merge_langtag_and_transform([[language: :en]])

      assert %Localize.LanguageTag{language: :en} = result["language"]
    end

    test "returns a lone map unchanged" do
      assert Helpers.merge_langtag_and_transform([%{"h0" => "hybrid"}]) == %{"h0" => "hybrid"}
    end
  end

  describe "collapse_keywords/1 and combine_multiple_types/1" do
    test "pairs keys with types and fills missing types with nil" do
      assert Helpers.collapse_keywords(
               key: "ca",
               type: "gregory",
               key: "nu",
               key: "co",
               type: "phonebk"
             ) == %{"ca" => "gregory", "co" => "phonebk", "nu" => nil}
    end

    test "a trailing key without a type maps to nil" do
      assert Helpers.collapse_keywords(key: "ca") == %{"ca" => nil}
    end

    test "combine_multiple_types folds consecutive types into a list" do
      assert Helpers.combine_multiple_types([{:type, "a"}, {:type, "b"}, {:type, "c"}]) ==
               [type: ["a", "b", "c"]]
    end
  end

  describe "flatten/5" do
    test "flattens nested argument lists" do
      assert Helpers.flatten("rest", [[1, [2]], [3]], %{}, 1, 0) == {"rest", [1, 2, 3], %{}}
    end

    test "returns an error for non-list arguments" do
      assert Helpers.flatten("rest", :nope, %{}, 1, 0) == {:error, "Can't flatten a non-list"}
    end
  end

  describe "collapse_extensions/1" do
    test "an empty list collapses to an empty list" do
      assert Helpers.collapse_extensions([]) == []
    end

    test "merges multiple extensions into one extensions entry" do
      assert Helpers.collapse_extensions([
               {:extension, %{"u" => 1}},
               {:extension, %{"t" => 2}}
             ]) == [extensions: %{"t" => 2, "u" => 1}]
    end
  end

  describe "collapse_variants/1" do
    test "an empty list collapses to an empty list" do
      assert Helpers.collapse_variants([]) == []
    end

    test "folds consecutive variants into a language_variants list" do
      assert Helpers.collapse_variants([
               {:language_variant, "1996"},
               {:language_variant, "fonipa"},
               {:other, 1}
             ]) == [language_variants: ["1996", "fonipa"], other: 1]
    end

    test "a single variant becomes a singleton list" do
      assert Helpers.collapse_variants([{:language_variant, "1996"}]) ==
               [language_variants: ["1996"]]
    end
  end
end
