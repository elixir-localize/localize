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

    test "parses zh-min-nan as a language with extended language subtags" do
      assert {:ok, fields} = Parser.parse("zh-min-nan")
      assert fields[:language] == "zh"
      assert fields[:language_subtags] == ["min", "nan"]
    end

    test "parses irregular i- grandfathered tags" do
      assert {:ok, [grandfathered: [irregular: "i-klingon"]]} = Parser.parse("i-klingon")
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
      # "sgn-BE-FR" is an irregular grandfathered tag but the ordered
      # grammar choice matches "sgn-BE" as a langtag first, leaving
      # "-FR" unconsumed.
      assert {:error, %Localize.ParseError{} = exception} = Parser.parse("sgn-BE-FR")
      assert exception.input == "sgn-BE-FR"
      assert exception.reason == :unexpected_input
      assert exception.offset == 6
      assert exception.rest == "-FR"
      assert exception.detail =~ "BCP47 language tag"
    end

    test "reports the error position for irregular en-GB-oed" do
      assert {:error, %Localize.ParseError{offset: 5, rest: "-oed"}} = Parser.parse("en-GB-oed")
    end

    test "reports offset 0 for empty input" do
      assert {:error, %Localize.ParseError{} = exception} = Parser.parse("")
      assert exception.offset == 0
      assert exception.rest == ""
      assert exception.detail =~ "grandfathered"
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
end
