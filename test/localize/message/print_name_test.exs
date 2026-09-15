defmodule Localize.Message.PrintNameTest do
  @moduledoc """
  Literals printed back into MessageFormat 2 source by
  `Localize.Message.Print.to_string/2`, unquoted exactly when they are a
  `name`.

  Expected values come from the `unquoted-literal`, `name`, `name-start`
  and `name-char` productions of the MessageFormat 2 ABNF in TR35 Part 9: a
  name begins with a letter, "+", "_" or a character from the listed
  ranges, which omit whitespace such as U+1680 OGHAM SPACE MARK, U+2000 EN
  QUAD, U+2028, U+205F and U+3000, the bidi controls U+200E and U+2066, and
  noncharacters such as U+FDD0 and U+1FFFE; digits, "-" and "." may follow
  but not begin one. The parser implements the same productions, so each
  printed message also parses back to the tree it came from. Characters
  outside ASCII are written as code points.

  """

  use ExUnit.Case, async: true

  # Letters and marks from the name-start ranges: Ä, ARABIC LETTER ALEF,
  # OGHAM LETTER FEARN, HYPHEN, IDEOGRAPHIC NUMBER ZERO, two CJK ideographs,
  # a private-use character, the first character after the U+FDD0–FDEF
  # noncharacters, LINEAR B SYLLABLE B008 A, an emoji and the last name
  # character in plane 16.
  @names [
    "abc",
    "_x",
    "+x",
    "x-1.2",
    <<0xC4::utf8>> <> "rger",
    <<0x627::utf8>>,
    <<0x16A0::utf8>>,
    <<0x2010::utf8>> <> "x",
    <<0x3007::utf8>>,
    <<0x4E2D::utf8, 0x6587::utf8>>,
    <<0xE000::utf8>>,
    <<0xFDF0::utf8>>,
    <<0x10000::utf8>>,
    <<0x1F600::utf8>>,
    <<0x10FFFD::utf8>>
  ]

  @excluded [0x1680, 0x2000, 0x200E, 0x2028, 0x205F, 0x2066, 0x3000, 0xFDD0, 0x1FFFE]

  @not_names ["", "a b", "1x", "-x", ".x"] ++
               Enum.map(@excluded, &("a" <> <<&1::utf8>> <> "b"))

  test "a name prints unquoted and anything else quoted, and both parse back" do
    for {values, quoted?} <- [{@names, false}, {@not_names, true}], value <- values do
      source = "{$x :f option=|" <> value <> "|}"
      assert {:ok, ast} = Localize.Message.Parser.parse(source)

      printed = Localize.Message.Print.to_string(ast)
      expected = if quoted?, do: source, else: "{$x :f option=" <> value <> "}"

      assert {value, printed} == {value, expected}
      assert {value, Localize.Message.Parser.parse(printed)} == {value, {:ok, ast}}
    end
  end
end
