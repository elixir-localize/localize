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
      assert {:error, %Localize.ParseError{} = exception} = Rfc5646.Parser.parse("en-gb-oxx")
      assert exception.input == "en-gb-oxx"
      assert exception.reason == :unexpected_input
      assert exception.rest == "-oxx"
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

    test "regular grandfathered tags resolve to their preferred language" do
      assert {:ok, tag} = LanguageTag.parse("zh-min")
      assert tag.language == :nan
      assert tag.language_subtags == []

      assert {:ok, tag} = LanguageTag.parse("zh-min-nan")
      assert tag.language == :nan
      assert tag.language_subtags == []

      assert {:ok, tag} = LanguageTag.parse("no-bok")
      assert tag.language == :nb

      assert {:ok, tag} = LanguageTag.parse("no-nyn")
      assert tag.language == :nn
    end

    test "art-lojban validates to its modern replacement" do
      assert {:ok, tag} = Localize.validate_locale("art-lojban")
      assert tag.canonical_locale_id == "jbo"
    end

    test "zh-min-nan validates to its modern replacement" do
      assert {:ok, tag} = Localize.validate_locale("zh-min-nan")
      assert tag.canonical_locale_id == "nan"
    end

    test "irregular i- tags resolve to their preferred language" do
      assert {:ok, tag} = LanguageTag.parse("i-klingon")
      assert tag.language == :tlh
      assert tag.requested_locale_id == "i-klingon"

      assert {:ok, tag} = LanguageTag.parse("i-navajo")
      assert tag.language == :nv

      assert {:ok, tag} = LanguageTag.parse("i-lux")
      assert tag.language == :lb
    end

    test "i-klingon validates to tlh" do
      assert {:ok, tag} = Localize.validate_locale("i-klingon")
      assert tag.canonical_locale_id == "tlh"
      assert tag.requested_locale_id == "i-klingon"
    end

    test "irregular multi-subtag grandfathered tags resolve to their preferred value" do
      assert {:ok, tag} = Localize.validate_locale("en-GB-oed")
      assert tag.canonical_locale_id == "en-GB-oxendict"
      assert tag.language == :en
      assert tag.territory == :GB
      assert tag.language_variants == ["oxendict"]

      assert {:ok, tag} = Localize.validate_locale("sgn-BE-FR")
      assert tag.canonical_locale_id == "sfb"

      assert {:ok, tag} = Localize.validate_locale("sgn-BE-NL")
      assert tag.canonical_locale_id == "vgt"

      assert {:ok, tag} = Localize.validate_locale("sgn-CH-DE")
      assert tag.canonical_locale_id == "sgg"
    end

    test "grandfathered tags with no BCP 47 preferred value follow the CLDR alias" do
      # These four have no preferred value in the BCP 47 registry, but
      # CLDR languageAlias maps them anyway: cel-gaulish -> xtg,
      # i-default -> en, i-enochian -> und, i-mingo -> see.
      assert {:ok, tag} = Localize.validate_locale("cel-gaulish")
      assert tag.canonical_locale_id == "xtg"

      assert {:ok, tag} = Localize.validate_locale("i-default")
      assert tag.canonical_locale_id == "en"

      assert {:ok, tag} = Localize.validate_locale("i-enochian")
      assert tag.canonical_locale_id == "und"

      assert {:ok, tag} = Localize.validate_locale("i-mingo")
      assert tag.canonical_locale_id == "see"
    end

    test "a grandfathered prefix with more subtags is not a grandfathered tag" do
      # "zh-min-nan-x-foo" is not the grandfathered tag "zh-min-nan";
      # it parses via the langtag production with extlang subtags.
      assert {:ok, tag} = LanguageTag.parse("zh-min-nan-x-foo")
      assert tag.language == :zh
      assert tag.language_subtags == ["min", "nan"]
      assert tag.private_use == ["foo"]
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

    test "rejects a repeated -u- singleton" do
      # RFC 5646 section 2.2.6 forbids repeated singleton subtags.
      assert {:error, %Localize.ParseError{} = exception} =
               LanguageTag.parse("en-u-ca-gregory-u-nu-thai")

      assert Exception.message(exception) =~ ~s(duplicate singleton "u")
    end

    test "rejects a repeated -t- singleton" do
      assert {:error, %Localize.ParseError{} = exception} =
               LanguageTag.parse("en-t-de-t-fr")

      assert Exception.message(exception) =~ ~s(duplicate singleton "t")
    end

    test "rejects a repeated generic singleton" do
      assert {:error, %Localize.ParseError{} = exception} =
               LanguageTag.parse("en-a-foo-a-bar")

      assert Exception.message(exception) =~ ~s(duplicate singleton "a")

      assert {:error, %Localize.ParseError{} = exception} =
               LanguageTag.parse("en-b-foo-a-bar-b-baz")

      assert Exception.message(exception) =~ ~s(duplicate singleton "b")
    end

    test "accepts distinct singletons" do
      assert {:ok, tag} = LanguageTag.parse("en-a-foo-b-bar")
      assert tag.extensions == %{"a" => ["foo"], "b" => ["bar"]}

      assert {:ok, tag} = LanguageTag.parse("en-t-de-u-ca-gregory")
      assert tag.locale["ca"] == "gregory"
      assert %{} = tag.transform
    end
  end
end
