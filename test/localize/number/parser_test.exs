defmodule Localize.Number.ParserTest do
  use ExUnit.Case, async: true

  doctest Localize.Number.Parser

  alias Localize.Number.Parser

  describe "parse/2" do
    test "parses an integer string" do
      assert {:ok, 1234} = Parser.parse("1234")
    end

    test "parses a float string" do
      assert {:ok, 1234.56} = Parser.parse("1234.56")
    end

    test "parses a negative number" do
      assert {:ok, -1_000_000.34} = Parser.parse("-1_000_000.34")
    end

    test "returns error for non-numeric string" do
      {:error, _} = Parser.parse("not a number")
    end
  end

  # TR35's loose matching for lenient parsing ignores every character in
  # `[:Zs:]`, and separately normalizes to NFKC, which maps the whole space
  # category onto U+0020. Either way a grouping space is a grouping space,
  # whichever one the user's keyboard or clipboard produced.
  describe "parse/2 with grouping spaces" do
    # U+202F is what `fr` actually groups with, so the others are the
    # interesting cases: U+0020 off a keyboard, U+00A0 and U+2009 out of
    # formatted output that was copied and pasted back in.
    @spaces %{
      "U+0020 SPACE" => " ",
      "U+00A0 NO-BREAK SPACE" => " ",
      "U+2007 FIGURE SPACE" => " ",
      "U+2009 THIN SPACE" => " ",
      "U+202F NARROW NO-BREAK SPACE" => " ",
      "U+205F MEDIUM MATHEMATICAL SPACE" => " ",
      "U+3000 IDEOGRAPHIC SPACE" => "　"
    }

    test "any space groups under a locale that groups with a space" do
      for {name, space} <- @spaces do
        assert {:ok, 1234.5} = Parser.parse("1#{space}234,5", locale: "fr"),
               "#{name} did not group in fr"
      end
    end

    test "any space groups under a locale that groups with a comma" do
      for {name, space} <- @spaces do
        assert {:ok, 1234.5} = Parser.parse("1#{space}234.5", locale: "en"),
               "#{name} did not group in en"
      end
    end

    test "any space groups under a locale that groups with a period" do
      for {name, space} <- @spaces do
        assert {:ok, 1234.5} = Parser.parse("1#{space}234,5", locale: "de"),
               "#{name} did not group in de"
      end
    end

    test "the locale's own separators still work" do
      assert {:ok, 1234.5} = Parser.parse("1,234.5", locale: "en")
      assert {:ok, 1234.5} = Parser.parse("1.234,5", locale: "de")
    end

    test "a string that is not a number is still rejected" do
      # Stripping spaces must not turn prose into a number.
      assert {:error, _} = Parser.parse("1 2 3 apples", locale: "fr")
      assert {:error, _} = Parser.parse("   ", locale: "fr")
    end

    test "superscripts are not folded into digits" do
      # `[:Zs:]` rather than a full NFKC fold, which maps U+00B2 onto "2" and
      # would read this as 52.
      assert {:error, _} = Parser.parse("5²", locale: "en")
    end
  end

  # TR35's loose matching also ignores all format characters, "in particular ...
  # any RLM, LRM or ALM used to control BIDI formatting". CLDR embeds those
  # marks in the number symbols of 19 locales, so they arrive in real input
  # rather than only in contrived input.
  describe "parse/2 with format characters" do
    # Written as codepoints: Elixir refuses unescaped bidi characters in source.
    @marks %{
      "U+200E LEFT-TO-RIGHT MARK" => 0x200E,
      "U+200F RIGHT-TO-LEFT MARK" => 0x200F,
      "U+061C ARABIC LETTER MARK" => 0x061C,
      "U+200B ZERO WIDTH SPACE" => 0x200B,
      "U+FEFF ZERO WIDTH NO-BREAK SPACE" => 0xFEFF,
      "U+00AD SOFT HYPHEN" => 0x00AD,
      "U+2066 LEFT-TO-RIGHT ISOLATE" => 0x2066,
      "U+202B RIGHT-TO-LEFT EMBEDDING" => 0x202B
    }

    test "a format character inside the digits is ignored" do
      for {name, codepoint} <- @marks do
        assert {:ok, 1234.5} = Parser.parse("1#{<<codepoint::utf8>>}234.5", locale: "en"),
               "#{name} was not ignored"
      end
    end

    test "a leading BIDI mark is ignored, as CLDR's own minus sign carries one" do
      # `ar` and `he` both write minusSign as LRM followed by "-", so this is
      # the shape a negative number copied out of that text actually has.
      for locale <- ~w(ar he), codepoint <- [0x200E, 0x200F, 0x061C] do
        assert {:ok, -1234.5} =
                 Parser.parse("#{<<codepoint::utf8>>}-1234.5", locale: locale),
               "U+#{Integer.to_string(codepoint, 16)} was not ignored in #{locale}"
      end
    end

    test "combines with the space handling" do
      mark = <<0x200E::utf8>>
      nbsp = <<0x00A0::utf8>>

      assert {:ok, 1234.5} = Parser.parse("#{mark}1#{nbsp}234,5", locale: "fr")
    end

    test "the percent and per-mille signs still resolve" do
      # Those symbols do carry BIDI marks in CLDR, but `resolve_per/2` matches
      # them against the raw string rather than through the number
      # normalization, so stripping there must not reach them.
      assert ["50", :percent] = Parser.resolve_per("50%", locale: "en")

      {:ok, symbols} = Localize.Number.Symbol.number_symbols_for("ar")

      assert ["50", :percent] =
               Parser.resolve_per("50" <> symbols.latn.percent_sign, locale: "ar")
    end
  end

  # CLDR ships `parseLenients` data naming the characters a lenient parse should
  # treat as equivalent. It was generated into the locale data but never read,
  # so none of it applied.
  describe "parse/2 with lenient character folding" do
    test "a locale's own minus sign round-trips" do
      # 18 locales write minusSign as U+2212 MINUS SIGN rather than the ASCII
      # hyphen, so their own formatted output did not parse back.
      minus = <<0x2212::utf8>>

      assert {:ok, -1234.5} = Parser.parse("#{minus}1234,5", locale: "fi")
      assert {:ok, -1234.5} = Parser.parse("#{minus}1234,5", locale: "sv")
      assert {:ok, -1234.5} = Parser.parse("#{minus}1234.5", locale: "fa")
    end

    test "minus and plus variants fold to the ASCII signs" do
      for codepoint <- [0x2212, 0x2010, 0xFF0D, 0x207B, 0x2796] do
        assert {:ok, -1234.5} = Parser.parse("#{<<codepoint::utf8>>}1234.5", locale: "en"),
               "U+#{Integer.to_string(codepoint, 16)} did not fold to minus"
      end

      for codepoint <- [0xFF0B, 0xFE62, 0x207A, 0x2795] do
        assert {:ok, 1234.5} = Parser.parse("#{<<codepoint::utf8>>}1234.5", locale: "en"),
               "U+#{Integer.to_string(codepoint, 16)} did not fold to plus"
      end
    end

    test "comma and full stop variants fold to the separators" do
      assert {:ok, 1234.5} = Parser.parse("1#{<<0xFF0C::utf8>>}234.5", locale: "en")
      assert {:ok, 1234.5} = Parser.parse("1234#{<<0xFF0E::utf8>>}5", locale: "en")
    end

    test "the folding applies to the locale's separators too, not only the input" do
      # `de-CH` groups with an ASCII apostrophe, which the general scope folds
      # onto U+2019. Folding only the input would leave the separator unmatched
      # and break a locale that parsed correctly before.
      assert {:ok, 1234.5} = Parser.parse("1'234.5", locale: "de-CH")
      assert {:ok, 1234.5} = Parser.parse("1#{<<0x2019::utf8>>}234.5", locale: "de-CH")

      # `ar`'s arab decimal separator U+066B is itself in the comma set.
      digits = <<0x661::utf8>> <> <<0x66C::utf8>> <> <<0x662::utf8>>
      digits = digits <> <<0x663::utf8>> <> <<0x664::utf8>> <> <<0x66B::utf8>> <> <<0x665::utf8>>

      assert {:ok, 1234.5} = Parser.parse(digits, locale: "ar", number_system: :arab)
    end

    test "the sets are locale-specific" do
      # `en` folds U+2013 EN DASH onto minus; `de` does not.
      dash = <<0x2013::utf8>>

      assert {:ok, -1234.5} = Parser.parse("#{dash}1234.5", locale: "en")
      assert {:error, _} = Parser.parse("#{dash}1234,5", locale: "de")
    end

    test "Elixir's numeric literal separator still works" do
      # The minus fold uses "_" as its placeholder, so a literal "_" in the
      # input has to be dealt with before the fold rather than after.
      assert {:ok, -1_000_000.34} = Parser.parse("-1_000_000.34")
      assert {:ok, 1_000_000} = Parser.parse("1_000_000")
    end
  end

  # ICU validates grouping positions in both of its parse modes, differing only
  # in how strict "plausible" is: strict wants exactly the locale's grouping
  # size, lenient wants at least two digits. Every expectation below was taken
  # from ICU 78.3 directly rather than from the specification.
  describe "grouping shape" do
    test "lenient, the default, requires groups of at least two digits" do
      assert {:ok, 1234.5} = Parser.parse("1 234,5", locale: "fr")
      assert {:ok, 1_234_567.5} = Parser.parse("1 234 567,5", locale: "fr")
      assert {:ok, 12_345.5} = Parser.parse("12 345,5", locale: "fr")
      assert {:ok, 123.5} = Parser.parse("1 23,5", locale: "fr")

      # A single digit after the separator is not a group in any locale, which
      # is what stops "3 4 5" reading as 345.
      assert {:error, _} = Parser.parse("3 4", locale: "fr")
      assert {:error, _} = Parser.parse("1 2", locale: "fr")
    end

    test "strict requires exactly the locale's grouping size" do
      assert {:ok, 1234.5} = Parser.parse("1 234,5", locale: "fr", lenient: false)
      assert {:ok, 12_345.5} = Parser.parse("12 345,5", locale: "fr", lenient: false)

      assert {:error, _} = Parser.parse("1 23,5", locale: "fr", lenient: false)
      assert {:error, _} = Parser.parse("1234 567,5", locale: "fr", lenient: false)
      assert {:error, _} = Parser.parse("1,23", locale: "en", lenient: false)
    end

    test "the grouping size comes from the locale, not a constant" do
      # `en-IN` groups 12,34,567 — a primary run of three and a secondary of
      # two — so the western shape is the one that fails there.
      assert {:ok, 1_234_567} = Parser.parse("12,34,567", locale: "en-IN", lenient: false)
      assert {:error, _} = Parser.parse("1,234,567", locale: "en-IN", lenient: false)

      assert {:ok, 12_345_678} = Parser.parse("12,345,678", locale: "en", lenient: false)
    end

    test "an ungrouped number is accepted in either mode" do
      for lenient <- [true, false] do
        assert {:ok, 1234.5} = Parser.parse("1234,5", locale: "fr", lenient: lenient)
        assert {:ok, 1234.5} = Parser.parse("1234.5", locale: "en", lenient: lenient)
      end
    end
  end

  describe "scan/2 grouping" do
    test "finds a grouped number written with an ordinary space" do
      # The reported case: `fr` formats with U+202F, but people type U+0020.
      assert [1234.5] = Parser.scan("1 234,5", locale: "fr")
      assert [1_234_567.5] = Parser.scan("1 234 567,5", locale: "fr")
      assert [2000, " et ", 3000] = Parser.scan("2 000 et 3 000", locale: "fr")
    end

    test "does not join unrelated single-digit numbers" do
      assert ["j'ai ", 3, " ", 4, " ", 5, " pommes"] =
               Parser.scan("j'ai 3 4 5 pommes", locale: "fr")
    end

    test "strict declines the two-digit runs that lenient joins" do
      # Room numbers and phone numbers are the realistic false positives, and
      # they are what `lenient: false` exists for in a scanning context.
      assert ["chambres ", 121_416] = Parser.scan("chambres 12 14 16", locale: "fr")

      assert ["chambres ", 12, " ", 14, " ", 16] =
               Parser.scan("chambres 12 14 16", locale: "fr", lenient: false)
    end
  end

  describe "scan/2" do
    test "scans a string with a number" do
      result = Parser.scan("The prize is 23")
      assert ["The prize is ", 23] = result
    end

    test "scans a number followed by text" do
      result = Parser.scan("1kg")
      assert [1, "kg"] = result
    end
  end

  describe "resolve_per/2" do
    test "resolves percent symbol" do
      result = Parser.resolve_per("11%")
      assert ["11", :percent] = result
    end
  end

  describe "input length cap" do
    test "rejects oversized number string" do
      cap = Parser.max_number_bytes()
      huge = String.duplicate("1", cap + 1)

      assert {:error, %Localize.ParseError{} = exception} = Parser.parse(huge)
      assert exception.reason == :input_too_large
      assert exception.size == byte_size(huge)
      assert exception.limit == cap
    end

    test "rejects Decimal with exponent magnitude above the cap" do
      max = Parser.max_decimal_exponent()
      # `parse/2` defaults to integer/float; force Decimal parsing so
      # the exponent guard fires. Anything above `max_decimal_exponent`
      # must be rejected so downstream multiplication or formatting
      # does not materialise huge mantissas.
      assert {:error, %Localize.InvalidValueError{value: msg}} =
               Parser.parse("1e#{max + 1}", number: :decimal)

      assert msg =~ "exponent"
      assert {:ok, _} = Parser.parse("1e#{max}", number: :decimal)
    end
  end
end
