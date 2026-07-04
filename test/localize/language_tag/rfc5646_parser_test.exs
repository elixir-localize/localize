defmodule Localize.Rfc5646.ParserTest do
  use ExUnit.Case, async: true

  alias Localize.Rfc5646.Parser

  describe "parse/2 top-level grammar choices" do
    test "parses a private-use-only tag" do
      assert {:ok, [private_use: ["abc"]]} = Parser.parse("x-abc")
    end

    test "parses a private-use-only tag with multiple subtags" do
      assert {:ok, [private_use: ["abc", "def12345"]]} = Parser.parse("x-abc-def12345")
    end

    test "parses zh-min-nan as a regular grandfathered tag" do
      assert {:ok, [grandfathered: [regular: "zh-min-nan"]]} = Parser.parse("zh-min-nan")
    end

    test "parses zh-min as a regular grandfathered tag, not a prefix of zh-min-nan" do
      assert {:ok, [grandfathered: [regular: "zh-min"]]} = Parser.parse("zh-min")
    end

    test "parses irregular i- grandfathered tags" do
      assert {:ok, [grandfathered: [irregular: "i-klingon"]]} = Parser.parse("i-klingon")
    end

    test "parses multi-subtag irregular grandfathered tags in downcased form" do
      # The public entry point (`Localize.LanguageTag.Parser`) downcases
      # input before this grammar runs, so the grammar matches the
      # downcased spellings of the registry-cased irregular tags.
      assert {:ok, [grandfathered: [irregular: "en-gb-oed"]]} = Parser.parse("en-gb-oed")
      assert {:ok, [grandfathered: [irregular: "sgn-be-fr"]]} = Parser.parse("sgn-be-fr")
      assert {:ok, [grandfathered: [irregular: "sgn-be-nl"]]} = Parser.parse("sgn-be-nl")
      assert {:ok, [grandfathered: [irregular: "sgn-ch-de"]]} = Parser.parse("sgn-ch-de")
    end

    test "a grandfathered prefix followed by more subtags parses as a langtag" do
      assert {:ok, fields} = Parser.parse("zh-min-nan-x-foo")
      assert fields[:language] == "zh"
      assert fields[:language_subtags] == ["min", "nan"]
      assert fields[:private_use] == ["foo"]
    end

    test "parses a langtag with extension and private use sections" do
      assert {:ok, fields} = Parser.parse("en-a-bbb-x-cc")
      assert fields[:language] == "en"
      assert fields[:extensions] == %{"a" => ["bbb"]}
      assert fields[:private_use] == ["cc"]
    end

    test "preserves the input case of subtags" do
      assert {:ok, fields} = Parser.parse("EN-gb")
      assert fields[:language] == "EN"
      assert fields[:territory] == "gb"
    end
  end

  describe "parse/2 error formatting" do
    test "reports offset and rest when a langtag prefix consumes the input" do
      # This grammar layer is case-sensitive (the public entry point
      # downcases first), so the registry-cased "sgn-BE-FR" does not
      # match the downcased grandfathered strings; the langtag
      # production matches "sgn-BE" and leaves "-FR" unconsumed.
      assert {:error, %Localize.ParseError{} = exception} = Parser.parse("sgn-BE-FR")
      assert exception.input == "sgn-BE-FR"
      assert exception.reason == :unexpected_input
      assert exception.offset == 6
      assert exception.rest == "-FR"
      assert exception.detail =~ "BCP47 language tag"
    end

    test "reports the error position for registry-cased en-GB-oed" do
      assert {:error, %Localize.ParseError{offset: 5, rest: "-oed"}} = Parser.parse("en-GB-oed")
    end

    test "reports offset 0 for empty input" do
      assert {:error, %Localize.ParseError{} = exception} = Parser.parse("")
      assert exception.offset == 0
      assert exception.rest == ""
      assert exception.detail =~ "BCP47 language tag"
    end

    test "reports the offset where invalid characters begin" do
      assert {:error, %Localize.ParseError{} = exception} = Parser.parse("not a tag")
      assert exception.offset == 3
      assert exception.rest == " a tag"
    end

    test "rejects a trailing hyphen" do
      assert {:error, %Localize.ParseError{offset: 2, rest: "-"}} = Parser.parse("en-")
    end

    test "produces a renderable exception message" do
      assert {:error, exception} = Parser.parse("en-")
      message = Exception.message(exception)
      assert is_binary(message)
      assert message != ""
    end
  end

  describe "parse/2 duplicate singleton subtags" do
    test "rejects a repeated -u- singleton" do
      assert {:error, %Localize.ParseError{} = exception} =
               Parser.parse("en-u-ca-gregory-u-nu-thai")

      assert exception.reason == :unexpected_input
      assert exception.detail =~ ~s(duplicate singleton "u")
    end

    test "rejects a repeated -t- singleton" do
      assert {:error, %Localize.ParseError{} = exception} = Parser.parse("en-t-de-t-fr")
      assert exception.detail =~ ~s(duplicate singleton "t")
    end

    test "rejects a repeated generic singleton" do
      assert {:error, %Localize.ParseError{} = exception} = Parser.parse("en-a-foo-a-bar")
      assert exception.detail =~ ~s(duplicate singleton "a")
    end

    test "rejects a repeated generic singleton separated by another extension" do
      assert {:error, %Localize.ParseError{} = exception} =
               Parser.parse("en-b-foo-a-bar-b-baz")

      assert exception.detail =~ ~s(duplicate singleton "b")
    end

    test "accepts distinct singletons" do
      assert {:ok, fields} = Parser.parse("en-a-foo-b-bar")
      assert fields[:extensions] == %{"a" => ["foo"], "b" => ["bar"]}

      assert {:ok, fields} = Parser.parse("en-t-de-u-nu-thai")
      assert Keyword.has_key?(fields, :transform)
      assert Keyword.has_key?(fields, :locale)
    end
  end
end
