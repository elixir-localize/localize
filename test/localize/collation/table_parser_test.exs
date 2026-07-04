defmodule Localize.Collation.Table.ParserTest do
  use ExUnit.Case, async: true

  alias Localize.Collation.Table.Parser

  doctest Localize.Collation.Table.Parser

  @moduletag :tmp_dir

  describe "parse_fractional_entry/1" do
    test "parses a single-codepoint entry with allkeys weights" do
      line = "0041; [2B, 05, 9C]\t# Latn Lu\t[23EC.0020.0008]\t* LATIN CAPITAL LETTER A"

      assert {:ok, [0x0041], [{0x23EC, 0x0020, 0x0008, false}]} =
               Parser.parse_fractional_entry(line)
    end

    test "parses a multi-collation-element entry" do
      line =
        "00E9; [33, 05, 05][, 88, 05]\t# Latn Ll\t" <>
          "[2453.0020.0002][0000.0024.0002]\t* LATIN SMALL LETTER E WITH ACUTE"

      assert {:ok, [0x00E9], elements} = Parser.parse_fractional_entry(line)
      assert [{0x2453, 0x0020, 0x0002, false}, {0x0000, 0x0024, 0x0002, false}] = elements
    end

    test "parses a multi-codepoint contraction entry" do
      line = "0063 0068; [2D, 05, 05]\t# Latn Ll\t[23EE.0020.0002]\t* LATIN SMALL CH"

      assert {:ok, [0x0063, 0x0068], [{0x23EE, 0x0020, 0x0002, false}]} =
               Parser.parse_fractional_entry(line)
    end

    test "parses a context entry into a context tuple" do
      line = "004C | 00B7; [, FB B6, 05]\t# Zyyy Po\t[0000.011F.0002]\t* MIDDLE DOT"

      assert {:context, 0x004C, 0x00B7, [{0x0000, 0x011F, 0x0002, false}]} =
               Parser.parse_fractional_entry(line)
    end

    test "maps the special LOWEST fractional weight to primary 0x0001" do
      line = "FFFE;\t[02, 05, 05]\t# Special LOWEST primary, for merge/interleaving"

      assert {:ok, [0xFFFE], [{0x0001, 0x0020, 0x0002, false}]} =
               Parser.parse_fractional_entry(line)
    end

    test "maps the special HIGHEST fractional weight to primary 0xFFFE" do
      line = "FFFF;\t[EF FF, 05, 05]\t# Special HIGHEST primary, for ranges"

      assert {:ok, [0xFFFF], [{0xFFFE, 0x0020, 0x0002, false}]} =
               Parser.parse_fractional_entry(line)
    end

    test "skips a line without a semicolon" do
      assert :skip = Parser.parse_fractional_entry("this is not an entry")
    end

    test "skips an entry with no recognizable weights" do
      assert :skip = Parser.parse_fractional_entry("0041; [ZZ]\t# no weights here")
    end

    test "skips a context entry with no recognizable weights" do
      assert :skip = Parser.parse_fractional_entry("004C | 00B7; [ZZ]\t# no weights")
    end
  end

  describe "parse_elements/1" do
    test "parses variable-flagged elements" do
      assert [{0x0269, 0x0020, 0x0002, true}] = Parser.parse_elements("[*0269.0020.0002]")
    end

    test "parses multiple elements in sequence" do
      elements = Parser.parse_elements("[.2453.0020.0002][.0000.0024.0002]")
      assert length(elements) == 2
    end

    test "returns an empty list for input with no weight groups" do
      assert [] = Parser.parse_elements("no weights at all")
    end
  end

  describe "parse/1" do
    @fixture """
    # Fractional UCA fixture for parser tests
    # comment lines and blank lines are ignored

    [UCA version = 17.0.0]
    [Unified_Ideograph 4E00..9FFF]
    [first variable [03 04, 05, 05]] # allkeys [0209.0020.0002]
    [last variable [0B 8E 64, 05, 05]] # allkeys [04E0.0020.0002]
    [top_byte\t03\tSPACE PUNCTUATION ]
    FDD0 0041; [, FB, 05]\t# contraction starter marker line, always skipped
    0020; [03 05, 05, 05]\t# Zyyy Zs\t[0209.0020.0002]\t* SPACE
    0041; [2B, 05, 9C]\t# Latn Lu\t[23EC.0020.0008]\t* LATIN CAPITAL LETTER A
    004C; [41, 05, 9C]\t# Latn Lu\t[2528.0020.0008]\t* LATIN CAPITAL LETTER L
    00E9; [33, 05, 05][, 88, 05]\t# Latn Ll\t[2453.0020.0002][0000.0024.0002]\t* E ACUTE
    0063 0068; [2D, 05, 05]\t# Latn Ll\t[23EE.0020.0002]\t* CH CONTRACTION
    004C | 00B7; [, FB B6, 05]\t# Zyyy Po\t[0000.011F.0002]\t* MIDDLE DOT
    0058 | 0059; [, FB B7, 05]\t# Zyyy Po\t[0000.0120.0002]\t* ORPHAN CONTEXT
    """

    setup %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "fractional_uca_fixture.txt")
      File.write!(path, @fixture)
      {:ok, parsed: Parser.parse(path)}
    end

    test "extracts the UCA version from the header", %{parsed: parsed} do
      assert parsed.version == "17.0.0"
    end

    test "parses single codepoint entries", %{parsed: parsed} do
      assert [{0x23EC, 0x0020, 0x0008, false}] = parsed.entries[0x0041]
    end

    test "parses multi-element entries", %{parsed: parsed} do
      assert [{0x2453, 0x0020, 0x0002, false}, {0x0000, 0x0024, 0x0002, false}] =
               parsed.entries[0x00E9]
    end

    test "stores contractions under tuple keys", %{parsed: parsed} do
      assert [{0x23EE, 0x0020, 0x0002, false}] = parsed.entries[{0x0063, 0x0068}]
    end

    test "flags entries within the variable range as variable", %{parsed: parsed} do
      assert [{0x0209, 0x0020, 0x0002, true}] = parsed.entries[0x0020]
    end

    test "resolves context entries into contractions prefixed by the context", %{parsed: parsed} do
      context_elements = parsed.entries[0x004C]
      contraction = parsed.entries[{0x004C, 0x00B7}]

      assert contraction == context_elements ++ [{0x0000, 0x011F, 0x0002, false}]
    end

    test "drops context entries whose context codepoint has no entry", %{parsed: parsed} do
      refute Map.has_key?(parsed.entries, {0x0058, 0x0059})
    end

    test "skips FDD-prefixed and bracketed directive lines", %{parsed: parsed} do
      refute Map.has_key?(parsed.entries, {0xFDD0, 0x0041})
    end
  end

  describe "parse/1 variable boundary headers in the vendored format" do
    # The header and data lines below are literal lines from
    # priv/cldr/FractionalUCA.txt (UCA 17.0.0). The boundary headers carry
    # fractional byte weights, not dotted allkeys triples, and appear after
    # the data lines — exactly as in the vendored file.
    @vendored_fixture """
    [UCA version = 17.0.0]
    0009; [03 04, 05, 05]\t# Zyyy Cc\t[0201.0020.0002]\t* <CHARACTER TABULATION>
    0021; [07 5A, 05, 05]\t# Zyyy Po\t[0269.0020.0002]\t* EXCLAMATION MARK
    1E5FF; [0B 8E 64, 05, 05]\t# Onao Po\t[04E0.0020.0002]\t* OL ONAL ABBREVIATION SIGN
    0060; [0C 04, 05, 05]\t# Zyyy Sk\t[04E1.0020.0002]\t* GRAVE ACCENT
    0041; [2B, 05, 9C]\t# Latn Lu\t[23EC.0020.0008]\t* LATIN CAPITAL LETTER A
    [first variable [03 04, 05, 05]] # U+0009 <CHARACTER TABULATION>
    [last variable [0B 8E 64, 05, 05]] # U+1E5FF OL ONAL ABBREVIATION SIGN
    [variable top = 0B FF FF FF]
    """

    setup %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "fractional_uca_vendored.txt")
      File.write!(path, @vendored_fixture)
      {:ok, parsed: Parser.parse(path)}
    end

    test "flags the first variable boundary character (lead 0x03)", %{parsed: parsed} do
      assert [{0x0201, 0x0020, 0x0002, true}] = parsed.entries[0x0009]
    end

    test "flags the last variable boundary character (lead 0x0B)", %{parsed: parsed} do
      assert [{0x04E0, 0x0020, 0x0002, true}] = parsed.entries[0x1E5FF]
    end

    test "flags characters between the boundary leads", %{parsed: parsed} do
      assert [{0x0269, 0x0020, 0x0002, true}] = parsed.entries[0x0021]
    end

    test "does not flag the first regular character just above the range", %{parsed: parsed} do
      # GRAVE ACCENT has allkeys primary 0x04E1 (one above the last variable
      # 0x04E0) and fractional lead 0x0C (one above the last variable lead).
      assert [{0x04E1, 0x0020, 0x0002, false}] = parsed.entries[0x0060]
    end

    test "does not flag ordinary letters", %{parsed: parsed} do
      assert [{0x23EC, 0x0020, 0x0008, false}] = parsed.entries[0x0041]
    end

    test "derives the range from the headers rather than the defaults", %{tmp_dir: tmp_dir} do
      # Narrow the last variable lead to 0x07: EXCLAMATION MARK (lead 0x07)
      # stays variable but U+1E5FF (lead 0x0B) no longer is.
      narrowed =
        String.replace(
          @vendored_fixture,
          "[last variable [0B 8E 64, 05, 05]] # U+1E5FF OL ONAL ABBREVIATION SIGN",
          "[last variable [07 5A, 05, 05]] # U+0021 EXCLAMATION MARK"
        )

      path = Path.join(tmp_dir, "fractional_uca_narrowed.txt")
      File.write!(path, narrowed)
      parsed = Parser.parse(path)

      assert [{0x0201, 0x0020, 0x0002, true}] = parsed.entries[0x0009]
      assert [{0x0269, 0x0020, 0x0002, true}] = parsed.entries[0x0021]
      assert [{0x04E0, 0x0020, 0x0002, false}] = parsed.entries[0x1E5FF]
    end
  end

  describe "parse/1 without variable boundary headers" do
    test "falls back to the default variable range", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "fractional_uca_defaults.txt")

      File.write!(path, """
      0020; [03 05, 05, 05]\t# Zyyy Zs\t[0209.0020.0002]\t* SPACE
      0041; [2B, 05, 9C]\t# Latn Lu\t[23EC.0020.0008]\t* LATIN CAPITAL LETTER A
      """)

      parsed = Parser.parse(path)

      # 0x0209 is inside the default variable range 0x0201..0x04E0
      assert [{0x0209, 0x0020, 0x0002, true}] = parsed.entries[0x0020]
      assert [{0x23EC, 0x0020, 0x0008, false}] = parsed.entries[0x0041]
      assert parsed.version == nil
    end
  end
end
