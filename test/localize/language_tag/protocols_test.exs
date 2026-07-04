defmodule Localize.LanguageTag.ProtocolsTest do
  use ExUnit.Case, async: true

  alias Localize.LanguageTag

  # Protocol implementations attached to `Localize.LanguageTag` and its
  # extension structs: `Inspect`, `String.Chars`, and the internal
  # `Localize.LanguageTag.Chars` protocol used when reassembling
  # canonical locale names from tag components.

  describe "Inspect for Localize.LanguageTag" do
    test "validated tag renders as a new!/1 call" do
      language_tag = LanguageTag.new!("en-US")
      assert inspect(language_tag) == ~s[Localize.LanguageTag.new!("en-US")]
    end

    test "validated tag with extensions round-trips the canonical form" do
      language_tag = LanguageTag.new!("en-US-u-ca-buddhist-t-en-h0-hybrid")
      rendered = inspect(language_tag)
      assert rendered =~ "Localize.LanguageTag.new!("
      assert rendered =~ "en-US-t-en-h0-hybrid-u-ca-buddhist"
    end

    test "parsed tag renders with the [parsed] marker" do
      {:ok, language_tag} = LanguageTag.parse("en-US")
      assert inspect(language_tag) == "#Localize.LanguageTag<en-US [parsed]>"
    end

    test "canonicalized tag renders with the [canonical] marker" do
      {:ok, parsed} = LanguageTag.parse("en-US")
      {:ok, canonical} = LanguageTag.canonicalize(parsed)
      assert inspect(canonical) == "#Localize.LanguageTag<en-US [canonical]>"
    end

    test "tokenized tag renders with the [tokenized] marker" do
      tokenized = %LanguageTag{language: :fr, script: :Latn, territory: :FR}
      assert inspect(tokenized) == "#Localize.LanguageTag<fr-Latn-FR [tokenized]>"
    end
  end

  describe "String.Chars for Localize.LanguageTag" do
    test "to_string/1 returns the canonical locale identifier" do
      language_tag = LanguageTag.new!("en-US")
      assert to_string(language_tag) == "en-US"
      assert to_string(language_tag) == language_tag.canonical_locale_id
    end

    test "to_string/1 includes canonicalized extensions" do
      language_tag = LanguageTag.new!("en-US-u-ca-buddhist-t-en-h0-hybrid")
      assert to_string(language_tag) == "en-US-t-en-h0-hybrid-u-ca-buddhist"
    end

    test "string interpolation renders the canonical form" do
      language_tag = LanguageTag.new!("zh-Hant-TW")
      assert "#{language_tag}" == "zh-Hant-TW"
    end
  end

  describe "String.Chars for Localize.LanguageTag.T" do
    test "to_string/1 renders the transform source language and fields" do
      language_tag = LanguageTag.new!("en-US-t-de-h0-hybrid")
      assert to_string(language_tag.transform) == "de-h0-hybrid"
    end

    test "to_string/1 of an empty transform struct is empty" do
      assert to_string(%LanguageTag.T{}) == ""
    end
  end

  describe "String.Chars for Localize.LanguageTag.U" do
    test "to_string/1 renders sorted key-value pairs" do
      language_tag = LanguageTag.new!("en-u-nu-thai-ca-buddhist")
      assert to_string(language_tag.locale) == "ca-buddhist-nu-thai"
    end
  end

  describe "Localize.LanguageTag.Chars for Atom" do
    test "nil converts to the empty string" do
      assert LanguageTag.Chars.to_string(nil) == ""
    end

    test "an atom converts to its string form" do
      assert LanguageTag.Chars.to_string(:Latn) == "Latn"
    end
  end

  describe "Localize.LanguageTag.Chars for BitString" do
    test "a string passes through unchanged" do
      assert LanguageTag.Chars.to_string("en-US") == "en-US"
    end

    test "the empty string passes through unchanged" do
      assert LanguageTag.Chars.to_string("") == ""
    end
  end

  describe "Localize.LanguageTag.Chars for List" do
    test "an empty list converts to the empty string" do
      assert LanguageTag.Chars.to_string([]) == ""
    end

    test "a list of variants is sorted and hyphen-joined" do
      assert LanguageTag.Chars.to_string(["valencia", "1994"]) == "1994-valencia"
    end
  end

  describe "Localize.LanguageTag.Chars for Map" do
    test "an empty map converts to the empty string" do
      assert LanguageTag.Chars.to_string(%{}) == ""
    end
  end

  describe "Localize.LanguageTag.Chars for Tuple" do
    test "a pair converts its value and preserves the key" do
      assert LanguageTag.Chars.to_string({"nu", :thai}) == {"nu", "thai"}
    end

    test "a pair with a nil value converts to an empty string value" do
      assert LanguageTag.Chars.to_string({"ca", nil}) == {"ca", ""}
    end
  end

  describe "Localize.LanguageTag.Chars for extension structs" do
    test "a U extension struct renders its key-value pairs" do
      language_tag = LanguageTag.new!("en-u-ca-buddhist-nu-thai")
      assert LanguageTag.Chars.to_string(language_tag.locale) == "ca-buddhist-nu-thai"
    end

    test "a T extension struct renders its source language and fields" do
      language_tag = LanguageTag.new!("en-US-t-de-h0-hybrid")
      assert LanguageTag.Chars.to_string(language_tag.transform) == "de-h0-hybrid"
    end
  end
end
