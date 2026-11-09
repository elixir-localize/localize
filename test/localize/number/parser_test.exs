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

    # A number is digits joined by the locale's separators, so where the
    # locale does not group with a space, a space parts two numbers, as
    # `scan/2` reads them (user, 2026-10-28). Until then such a space was
    # deleted, so `en` "1 2" read as 12.
    test "no space groups under a locale that groups with a comma" do
      for {name, space} <- @spaces do
        assert {:error, _} = Parser.parse("1#{space}234.5", locale: "en"),
               "#{name} grouped in en"
      end

      assert {:error, _} = Parser.parse("1 2", locale: "en")
      assert {:error, _} = Parser.parse("1, 234", locale: "en")
    end

    test "no space groups under a locale that groups with a period" do
      for {name, space} <- @spaces do
        assert {:error, _} = Parser.parse("1#{space}234,5", locale: "de"),
               "#{name} grouped in de"
      end
    end

    test "a space before or after a number, or beside its sign, is not inside it" do
      assert {:ok, 100} = Parser.parse(" 100 ", locale: "en")
      assert {:ok, -100} = Parser.parse("- 100", locale: "en")
      assert {:ok, 5} = Parser.parse("+ 5", locale: "en")
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

  describe "Latin digits in a locale whose digits are not" do
    test "are read with the locale's Latin separators" do
      assert {:ok, 10_000} = Parser.parse("100,00", locale: "ar-EG")
      assert {:ok, 1234.56} = Parser.parse("1,234.56", locale: "ar-EG")
      assert {:ok, 1234.56} = Parser.parse("1,234.56", locale: "fa")
      assert [1234.56, " EGP"] = Parser.scan("1,234.56 EGP", locale: "ar-EG")
    end

    test "while the locale's own digits keep its separators" do
      assert {:ok, 1234.56} = Parser.parse("١٬٢٣٤٫٥٦", locale: "ar-EG")
      assert {:ok, 100.0} = Parser.parse("100,00", locale: "ar-EG", number_system: :arab)
    end

    test "are read with the locale's own separators where the text uses them" do
      assert {:ok, 1234.56} = Parser.parse("1٬234٫56", locale: "ar-EG")
      assert {:ok, -1234.5} = Parser.parse("−1٬234٫5", locale: "fa")
      assert {:ok, -1234.5} = Parser.parse("-1٬234٫5", locale: "ckb")
      assert {:ok, -1234.5} = Parser.parse("-1٬234.5", locale: "sd")
      assert {:ok, -1234.5} = Parser.parse("-1٬234٫5", locale: "ps")
      assert {:ok, 1234} = Parser.parse("1٬234", locale: "ur-IN")
      assert {:ok, 1234.5} = Parser.parse("1234.5", locale: "sd")
    end
  end

  describe "a grouping separator after the decimal mark" do
    test "is not a number" do
      for {string, locale} <- [
            {"1,234.56", "de"},
            {"1.234,56", "en"},
            {"1,5 6", "fr"},
            {"1.234,5.6", "de"},
            {"1,234.5,6", "en"}
          ],
          lenient <- [true, false] do
        assert {:error, _} =
                 Parser.parse(string, locale: locale, number: :decimal, lenient: lenient),
               "#{locale} #{inspect(string)} lenient: #{lenient}"
      end
    end
  end

  describe "grouping: :sizes" do
    test "refuses a group the locale does not write" do
      for {string, locale} <- [{"1.23", "de"}, {"1,23", "en"}, {"1 23", "fr"}, {"1,23", "en-IN"}] do
        assert {:error, _} = Parser.parse(string, locale: locale, grouping: :sizes),
               "#{locale} #{inspect(string)}"
      end
    end

    test "takes the groups the locale writes, in either Indian or Western form" do
      assert {:ok, 1234} = Parser.parse("1.234", locale: "de", grouping: :sizes)
      assert {:ok, 12_345_678} = Parser.parse("12.345.678", locale: "de", grouping: :sizes)
      assert {:ok, 1_234_567} = Parser.parse("1,234,567", locale: "en-IN", grouping: :sizes)
      assert {:ok, 1_234_567} = Parser.parse("12,34,567", locale: "en-IN", grouping: :sizes)
      assert {:ok, 5} = Parser.parse("5.–", locale: "de-CH", grouping: :sizes)
    end

    test "is an option with one value" do
      assert {:error, %Localize.InvalidValueError{}} = Parser.parse("1", grouping: :nope)
    end
  end

  describe "parse/2 with root_separators: true" do
    test "reads what either the locale or the root locale reads" do
      options = [locale: "de", number: :decimal, grouping: :sizes, root_separators: true]
      assert {:ok, %Decimal{} = d1} = Parser.parse("1234.56", options)
      assert Decimal.equal?(d1, "1234.56")
      assert {:ok, %Decimal{} = d2} = Parser.parse("1,5", options)
      assert Decimal.equal?(d2, "1.5")
      assert {:error, %Localize.ParseError{detail: detail}} = Parser.parse("1.234", options)
      assert detail =~ "ambiguous"
    end

    test "changes nothing where the locale reads as the root does" do
      assert {:ok, 1234.56} = Parser.parse("1,234.56", locale: "en", root_separators: true)
    end
  end

  # `de-AT` and `fr-CH` write a currency amount with other separators than a
  # plain number. Either may be typed, so both are read.
  describe "parse/2 with :currency in a locale whose currency separators differ" do
    defp amount_of(string, locale, currency) do
      Parser.parse(string, locale: locale, currency: currency, number: :decimal, grouping: :sizes)
    end

    test "reads what either set reads" do
      assert {:ok, %Decimal{} = d1} = amount_of("1.234,56", "de-AT", :EUR)
      assert Decimal.equal?(d1, "1234.56")
      assert {:ok, %Decimal{} = d2} = amount_of("1\u00A0234,56", "de-AT", :EUR)
      assert Decimal.equal?(d2, "1234.56")
      assert {:ok, %Decimal{} = d4} = amount_of("1'234,56", "fr-CH", :CHF)
      assert Decimal.equal?(d4, "1234.56")
      assert {:ok, %Decimal{} = d5} = amount_of("1'234.56", "fr-CH", :CHF)
      assert Decimal.equal?(d5, "1234.56")
    end

    # Both of `de-AT`'s sets mark the fraction with a comma, and the euro's
    # groups with a period, so a period is never its decimal point: "100.00"
    # is a malformed group, as in `de`.
    test "reads a period as de-AT's currency group, never as a decimal point" do
      assert {:ok, %Decimal{} = amount} = amount_of("1.234", "de-AT", :EUR)
      assert Decimal.equal?(amount, "1234")
      assert {:error, _} = amount_of("100.00", "de-AT", :EUR)
      assert {:error, _} = amount_of("1.23", "de-AT", :EUR)
      assert {:error, _} = amount_of("1.234,5.6", "de-AT", :EUR)
    end

    test "reads fr-CH's whole-franc price with the franc's decimal mark" do
      assert {:ok, %Decimal{} = amount} = amount_of("5.–", "fr-CH", :CHF)
      assert Decimal.equal?(amount, "5")
      assert {:ok, %Decimal{} = amount} = amount_of("5.-", "fr-CH", :CHF)
      assert Decimal.equal?(amount, "5")
    end
  end

  # The number is handed to Elixir with "." as its decimal point, so a
  # period the locale does not write is read as one only where it can be
  # nothing else.
  describe "a period that is neither of the locale's separators" do
    test "is refused where it could group thousands, or is not between digits" do
      for locale <- ["fr", "sv", "pl", "ru", "cs", "fr-CH"],
          string <- ["1.234", "12.345", "1.000.000", "5.", ".5", "5.-", "1,5.3"],
          options <- [[], [number: :decimal], [grouping: :sizes]] do
        assert {:error, _} = Parser.parse(string, [locale: locale] ++ options),
               inspect({locale, string, options})
      end
    end

    test "is the decimal point where it can be nothing else" do
      for locale <- ["fr", "sv", "pl", "ru", "cs"],
          {string, expected} <- [
            {"100.00", "100.00"},
            {"0.5", "0.5"},
            {"1234.56", "1234.56"},
            {"1234.567", "1234.567"},
            {"-100.00", "-100.00"},
            {"(0.5)", "-0.5"}
          ] do
        assert {:ok, %Decimal{} = value} = Parser.parse(string, locale: locale, number: :decimal),
               inspect({locale, string})

        assert Decimal.equal?(value, expected), inspect({locale, string})
      end
    end

    test "is read where it is one of them" do
      assert {:ok, 1.5} = Parser.parse("1,5", locale: "fr")
      assert {:ok, 1.5} = Parser.parse("1.5", locale: "en")
      assert {:ok, 1234} = Parser.parse("1.234", locale: "de")
      assert {:ok, 1.234} = Parser.parse("1.234", locale: "fr", root_separators: true)
      assert {:ok, 1.234} = Parser.parse("1.234", locale: "fr-CH", currency: :CHF)
    end
  end

  describe "lenient grouping" do
    test "refuses a group longer than the locale's longest" do
      # A separator after four digits is no grouping any locale writes, and
      # reading it as one turned "1234.56" into 123456.
      assert {:error, _} = Parser.parse("1234.56", locale: "de", number: :decimal)
      assert {:error, _} = Parser.parse("1.2345", locale: "de", number: :decimal)
      assert {:error, _} = Parser.parse("1234,567", locale: "en", number: :decimal)
    end

    test "still takes short groups and either grouping in en-IN" do
      assert {:ok, 1234} = Parser.parse("1.234", locale: "de")
      assert {:ok, 123} = Parser.parse("1 23", locale: "fr")
      assert {:ok, 1_234_567} = Parser.parse("1,234,567", locale: "en-IN")
      assert {:ok, 1_234_567} = Parser.parse("12,34,567", locale: "en-IN")
      assert {:ok, 12_345.67} = Parser.parse("12345.67", locale: "en")
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

  describe "scan/2 lenient folds" do
    # `parse/2` folds with CLDR's `parseLenients` sets, so whatever it would
    # read as one number, the scanner must not split.
    test "a group separator folded onto the locale's" do
      assert ["CHF ", 1234.56] = Parser.scan("CHF 1’234.56", locale: "de-CH")
      assert ["CHF ", 1234.56] = Parser.scan("CHF 1'234.56", locale: "de-CH")
      assert [1234.56] = Parser.scan("1．234,56", locale: "de")
    end

    test "a group separator folded onto the currency's" do
      assert [1234.56, " CHF"] = Parser.scan("1’234.56 CHF", locale: "fr-CH", currency: :CHF)
    end

    test "a decimal separator folded onto the locale's" do
      assert [1234.56] = Parser.scan("1,234﹒56", locale: "en")
    end

    test "a minus sign folded onto the locale's" do
      assert [-1234.56, " kr"] = Parser.scan("−1 234,56 kr", locale: "sv")
      assert [-1234.56, " kr"] = Parser.scan("-1 234,56 kr", locale: "sv")
      assert [-1234.56] = Parser.scan("−1,234.56", locale: "en")
    end

    test "a plus sign folded onto ASCII" do
      assert [1234.56] = Parser.scan("＋1,234.56", locale: "en")
    end

    test "folds apply whether or not the scan is lenient" do
      assert [-1234.56] = Parser.scan("−1 234,56", locale: "sv", lenient: false)
    end

    test "text around a number is returned as written" do
      assert ["v", 1.2, ".", 3, " and ", 4, ",", 5] =
               Parser.scan("v1.2.3 and 4,5", locale: "en")

      assert ["_", 5] = Parser.scan("_5", locale: "en")
    end
  end

  describe "scan/2 bidi controls" do
    test "a mark between a sign and its digits keeps the sign" do
      assert [-1234.56, " ج.م.‏"] =
               Parser.scan("؜-‏١٬٢٣٤٫٥٦ ج.م.‏", locale: "ar-EG")

      assert [-5] = Parser.scan("-‎5", locale: "en")
    end

    test "marks before a number are part of it" do
      assert [-1234.56, " ج.م.‏"] =
               Parser.scan("‏‎-1,234.56 ج.م.‏", locale: "ar")

      assert [1234.56, " ج.م.‏"] =
               Parser.scan("‏1,234.56 ج.م.‏", locale: "ar")
    end

    test "marks and joiners elsewhere stay in the text" do
      assert ["abc‏def ", 5] = Parser.scan("abc‏def 5", locale: "en")
      assert ["👨‍👩 ", 2] = Parser.scan("👨‍👩 2", locale: "en")
      assert ["‏"] = Parser.scan("‏", locale: "ar")
    end
  end

  describe "resolve_currencies/2 closing periods" do
    defp scan_currency(string, locale) do
      string
      |> Parser.scan(locale: locale, number: :decimal)
      |> Parser.resolve_currencies(locale: locale)
    end

    test "a symbol CLDR writes with a closing period is matched whole" do
      assert [%Decimal{}, :DKK] = scan_currency("1.234,56 kr.", "da")
      assert [:DKK, " ", %Decimal{}] = scan_currency("kr. 5", "da")
      assert [:DKK] = Parser.resolve_currency("kr.", locale: "da")
    end

    test "with the bidi controls that close it" do
      assert [%Decimal{}, :EGP] = scan_currency("‏1,234.56 ج.م.‏", "ar")
      assert [%Decimal{}, :MAD] = scan_currency("1.234,56 د.م.‏", "ar-MA")

      assert ["(", %Decimal{}, :EGP, ")"] =
               scan_currency("(؜1,234.56 ج.م.‏)", "ar")
    end

    test "a period after any other currency is left as text" do
      assert [%Decimal{}, :USD, "."] = scan_currency("100 USD.", "en")
      assert [:USD, ". ", %Decimal{}] = scan_currency("USD. 100", "en")
    end
  end

  # TR35's heuristics take a sign as a prefix or a suffix, and CLDR's
  # accounting formats write a negative amount in parentheses.
  describe "parse/2 signs and accounting parentheses" do
    test "a sign before or after the digits, with or without a space" do
      for string <- ["-5", "5-", "- 5", "5 -"] do
        assert {:ok, -5} = Parser.parse(string, locale: "en"), inspect(string)
      end

      assert {:ok, 5} = Parser.parse("+5", locale: "en")
      assert {:ok, -127.54} = Parser.parse("127,54-", locale: "nl")
    end

    test "parentheses negate what they hold" do
      assert {:ok, -5} = Parser.parse("(5)", locale: "en")
      assert {:ok, -5} = Parser.parse("( 5 )", locale: "en")
      assert {:ok, -1234.56} = Parser.parse("(1 234,56)", locale: "fr")
      assert {:ok, -5} = Parser.parse("(5.–)", locale: "de-CH")
    end

    test "two signs, or a parenthesis without its pair, are refused" do
      for string <- ["--5", "-5-", "+-5", "(5", "5)", "((5))", ")5(", "-", "()"] do
        assert {:error, _} = Parser.parse(string, locale: "en"), inspect(string)
      end
    end

    # Swiss "–.15" and Dutch "-,50" write a dash for the zero, so a minus
    # before a decimal mark with no digit ahead of it could be either.
    test "a minus before a bare decimal mark is refused" do
      for {string, locale} <- [{"-.5", "en"}, {"\u2212.5", "en"}, {"- .5", "en"}, {"-,5", "nl"}],
          options <- [[], [number: :decimal], [number: :float]] do
        assert {:error, _} = Parser.parse(string, [locale: locale] ++ options),
               inspect({locale, string, options})
      end
    end

    test "a decimal mark that opens or closes a number reads the same for every number type" do
      assert {:ok, 0.5} = Parser.parse(".5", locale: "en")
      assert {:ok, 0.5} = Parser.parse(".5", locale: "en", number: :float)
      assert {:ok, %Decimal{} = half} = Parser.parse(".5", locale: "en", number: :decimal)
      assert Decimal.equal?(half, "0.5")
      assert {:ok, 5} = Parser.parse("5.", locale: "en")
      assert {:ok, 5} = Parser.parse("5.", locale: "en", number: :integer)
      assert {:ok, -0.5} = Parser.parse(".5-", locale: "en")
      assert {:ok, -0.5} = Parser.parse("(.5)", locale: "en")
      assert {:ok, 0.5} = Parser.parse(",5", locale: "nl")

      for string <- [".", "-.", "..5", "5.."] do
        assert {:error, _} = Parser.parse(string, locale: "en"), inspect(string)
      end
    end

    # Some read "(-5)" as -5, a negative marked twice, and others as 5.
    test "a sign and parentheses together are refused" do
      for string <- ["(-5)", "-(5)", "(5-)", "(5)-", "(+5)", "+(5)", "(\u22125)"] do
        assert {:error, _} = Parser.parse(string, locale: "en"), inspect(string)
        assert {:error, _} = Parser.parse(string, locale: "en", number: :decimal), inspect(string)
      end
    end
  end

  describe "zero fraction written as a dash" do
    test "parse/2 reads it as a whole amount" do
      assert {:ok, 5} = Parser.parse("5.–", locale: "de-CH")
      assert {:ok, 5} = Parser.parse("5.—", locale: "de-CH")
      assert {:ok, 5} = Parser.parse("5.--", locale: "de-CH")
      assert {:ok, 5} = Parser.parse("5,-", locale: "nl")
      assert {:ok, 1234} = Parser.parse("1.234,-", locale: "nl")
      assert {:ok, -5} = Parser.parse("-5.–", locale: "de-CH")
    end

    test "parse/2 reads it only leniently, and only after digits" do
      assert {:error, _} = Parser.parse("5.–", locale: "de-CH", lenient: false)
      assert {:error, _} = Parser.parse(".–", locale: "de-CH")
      assert {:error, _} = Parser.parse("5.---", locale: "de-CH")
      # A dash after the digits with no decimal mark is a trailing minus.
      assert {:ok, -5} = Parser.parse("5-", locale: "en")
    end

    test "scan/2 reads it as part of the number" do
      assert ["CHF ", 5] = Parser.scan("CHF 5.–", locale: "de-CH")
      assert ["€ ", 5, " en ", 6] = Parser.scan("€ 5,- en 6,-", locale: "nl")
      assert ["CHF ", 5, ".–"] = Parser.scan("CHF 5.–", locale: "de-CH", lenient: false)
      assert [1, ".", -2] = Parser.scan("1.-2", locale: "en")
      assert ["€ ", 127.54, "-"] = Parser.scan("€ 127,54-", locale: "nl")
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
