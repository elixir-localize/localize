defmodule Localize.LanguageTag.ParserTest do
  use ExUnit.Case, async: true

  alias Localize.LanguageTag
  alias Localize.LanguageTag.Parser
  alias Localize.Rfc5646

  describe "Parser.parse/1" do
    test "returns a bare map with normalized string subtags" do
      assert {:ok, map} = Parser.parse("EN-Latn-us")
      assert map.language == "en"
      assert map.script == "Latn"
      assert map.territory == "US"
    end

    test "preserves the requested locale id verbatim" do
      assert {:ok, map} = Parser.parse("EN-us")
      assert map.requested_locale_id == "EN-us"
    end

    test "converts a POSIX locale id before parsing" do
      assert {:ok, map} = Parser.parse("en_US_POSIX")
      assert map.language == "en"
      assert map.territory == "US"
      assert map.language_variants == ["posix"]
    end

    test "defaults optional fields to predictable empty values" do
      assert {:ok, map} = Parser.parse("en")
      assert map.script == nil
      assert map.territory == nil
      assert map.language_variants == []
      assert map.language_subtags == []
      assert map.locale == %{}
      assert map.transform == %{}
      assert map.extensions == %{}
      assert map.private_use == []
    end

    test "sorts and downcases variant subtags" do
      assert {:ok, map} = Parser.parse("en-SCOUSE-FONIPA")
      assert map.language_variants == ["fonipa", "scouse"]
    end

    test "returns a ParseError for invalid input" do
      assert {:error, %Localize.ParseError{}} = Parser.parse("bogus locale")
    end
  end

  describe "Parser.parse!/1" do
    test "returns the bare map on success" do
      assert %{language: "en"} = Parser.parse!("en")
    end

    test "raises a ParseError on invalid input" do
      assert_raise Localize.ParseError, fn -> Parser.parse!("!!") end
    end
  end

  describe "Rfc5646.Parser.parse/2" do
    test "parses with the default language_tag rule" do
      assert {:ok, fields} = Rfc5646.Parser.parse("en-us")
      assert fields[:language] == "en"
      assert fields[:territory] == "us"
    end

    test "parses with an explicit rule name" do
      assert {:ok, _fields} = Rfc5646.Parser.parse(:language_tag, "en-us")
    end

    test "returns a ParseError with position detail on failure" do
      assert {:error, %Localize.ParseError{} = exception} = Rfc5646.Parser.parse("en-gb-oed")
      assert exception.input == "en-gb-oed"
      assert exception.reason == :unexpected_input
      assert exception.rest == "-oed"
      assert exception.offset == 5
      assert exception.detail =~ "BCP47"
    end
  end

  describe "LanguageTag.parse/1 grandfathered and irregular tags" do
    test "redundant grandfathered tags resolve to their modern language" do
      assert {:ok, tag} = LanguageTag.parse("zh-xiang")
      assert tag.language == :hsn

      assert {:ok, tag} = LanguageTag.parse("zh-hakka")
      assert tag.language == :hak

      assert {:ok, tag} = LanguageTag.parse("cel-gaulish")
      assert tag.language == :xtg
    end

    test "regular grandfathered tags with extlang-shaped subtags keep them" do
      assert {:ok, tag} = LanguageTag.parse("zh-min")
      assert tag.language == :zh
      assert tag.language_subtags == ["min"]

      assert {:ok, tag} = LanguageTag.parse("no-bok")
      assert tag.language == :no
      assert tag.language_subtags == ["bok"]
    end

    test "art-lojban validates to its modern replacement" do
      assert {:ok, tag} = Localize.validate_locale("art-lojban")
      assert tag.canonical_locale_id == "jbo"
    end

    test "irregular i- tags parse but carry no language" do
      assert {:ok, tag} = LanguageTag.parse("i-klingon")
      assert tag.language == nil
      assert tag.requested_locale_id == "i-klingon"
    end

    test "unsupported irregular tags return a ParseError" do
      assert {:error, %Localize.ParseError{}} = LanguageTag.parse("en-GB-oed")
      assert {:error, %Localize.ParseError{}} = LanguageTag.parse("sgn-BE-FR")
    end
  end

  describe "LanguageTag.parse/1 malformed input" do
    test "rejects an overlong primary subtag" do
      assert {:error, %Localize.ParseError{}} = LanguageTag.parse("en-abcdefghij")
    end

    test "rejects a repeated territory subtag" do
      assert {:error, %Localize.ParseError{}} = LanguageTag.parse("en-us-us")
    end

    test "rejects a bare private use singleton" do
      assert {:error, %Localize.ParseError{}} = LanguageTag.parse("x-")
    end

    test "keeps the first of two repeated -u- extensions" do
      # RFC 5646 forbids repeated singletons; the grammar currently
      # accepts the tag and the first -u- extension wins.
      assert {:ok, tag} = LanguageTag.parse("en-u-ca-gregory-u-nu-thai")
      assert tag.locale["ca"] == "gregory"
    end
  end
end
