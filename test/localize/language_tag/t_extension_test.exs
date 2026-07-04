defmodule Localize.LanguageTag.TExtensionTest do
  use ExUnit.Case, async: true

  alias Localize.LanguageTag.T

  describe "validate_locale/1 with a -t- extension" do
    test "populates the transform struct with the source language" do
      {:ok, tag} = Localize.validate_locale("de-t-en")
      assert %T{} = tag.transform
      assert %Localize.LanguageTag{} = tag.transform.language
      assert tag.transform.language.language == "en"
    end

    test "decodes a transform mechanism keyword" do
      {:ok, tag} = Localize.validate_locale("ja-t-it-m0-ungegn")
      assert tag.transform.m0 == :ungegn
      assert tag.transform.language.language == "it"
    end

    test "decodes a mechanism value list with a trailing date" do
      {:ok, tag} = Localize.validate_locale("ja-t-it-m0-ungegn-2007")
      assert tag.transform.m0 == [:ungegn, {2007}]
    end

    test "decodes a full date subtag" do
      {:ok, tag} = Localize.validate_locale("ja-t-it-m0-ungegn-20071125")
      assert tag.transform.m0 == [:ungegn, {2007, 11, 25}]
    end

    test "decodes the hybrid keyword" do
      {:ok, tag} = Localize.validate_locale("en-t-de-h0-hybrid")
      assert tag.transform.h0 == :hybrid
    end

    test "decodes x0 private use subtags as a string list" do
      {:ok, tag} = Localize.validate_locale("en-t-de-x0-custom-stuff")
      assert tag.transform.x0 == ["custom", "stuff"]
    end

    test "decodes keyboard and input method keywords" do
      {:ok, tag} = Localize.validate_locale("en-t-k0-dvorak")
      assert tag.transform.k0 == :dvorak

      {:ok, tag} = Localize.validate_locale("zh-t-i0-pinyin")
      assert tag.transform.i0 == :pinyin
    end

    test "rejects an invalid keyword value" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Localize.validate_locale("en-t-de-m0-bogus")
    end

    test "rejects a mechanism list where the date is not last" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Localize.validate_locale("und-t-ru-m0-2007-ungegn")
    end
  end

  describe "encode/1" do
    test "encodes populated fields as BCP 47 key and value pairs" do
      {:ok, tag} = Localize.validate_locale("ja-t-it-m0-ungegn-2007")
      assert T.encode(tag.transform) == [{"m0", "ungegn-2007"}]
    end

    test "excludes the language field and nil fields" do
      {:ok, tag} = Localize.validate_locale("en-t-de-h0-hybrid")
      assert T.encode(tag.transform) == [{"h0", "hybrid"}]
    end
  end

  describe "to_string/1" do
    test "renders the transform language followed by keywords" do
      {:ok, tag} = Localize.validate_locale("ja-t-it-m0-ungegn")
      assert T.to_string(tag.transform) == "it-m0-ungegn"
    end

    test "renders private use transforms" do
      {:ok, tag} = Localize.validate_locale("en-t-de-x0-custom-stuff")
      assert T.to_string(tag.transform) == "de-x0-custom-stuff"
    end

    test "renders a keyword-only transform without a language" do
      {:ok, tag} = Localize.validate_locale("en-t-k0-dvorak")
      assert T.to_string(tag.transform) == "k0-dvorak"
    end

    test "renders an empty map as an empty string" do
      assert T.to_string(%{}) == ""
    end

    test "round-trips a date subtag with two-digit month and day" do
      {:ok, tag} = Localize.validate_locale("ja-t-it-m0-ungegn-20071125")
      assert T.to_string(tag.transform) == "it-m0-ungegn-20071125"
    end
  end

  describe "canonicalize_transform_keys/1" do
    test "passes a tag with an empty transform through unchanged" do
      {:ok, parsed} = Localize.LanguageTag.parse("en")
      assert {:ok, ^parsed} = T.canonicalize_transform_keys(parsed)
    end

    test "lifts a parsed transform map into the struct" do
      {:ok, parsed} = Localize.LanguageTag.parse("en-t-de-h0-hybrid")
      assert is_map(parsed.transform)
      refute is_struct(parsed.transform)

      {:ok, canonical} = T.canonicalize_transform_keys(parsed)
      assert %T{h0: :hybrid} = canonical.transform
    end

    test "returns an error for an invalid keyword value" do
      {:ok, parsed} = Localize.LanguageTag.parse("en-t-de-m0-bogus")

      assert {:error, %Localize.InvalidSubtagError{key: "m0", value: "bogus"}} =
               T.canonicalize_transform_keys(parsed)
    end
  end
end
