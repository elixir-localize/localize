defmodule Localize.Number.Lexer.CategoriesTest do
  use ExUnit.Case, async: true

  alias Localize.Number.Lexer.Categories

  test "format characters" do
    assert Categories.format?(0x00AD)
    assert Categories.format?(0x200E)
    assert Categories.format?(0xFEFF)
    refute Categories.format?(?a)
    refute Categories.format?(0x00A0)
  end

  test "digits of any number system" do
    assert Categories.digit?(?0)
    assert Categories.digit?(0x0660)
    assert Categories.digit?(0x0966)
    assert Categories.digit?(0xFF15)
    # A superscript two is a number, but no decimal digit.
    refute Categories.digit?(0x00B2)
    refute Categories.digit?(?a)
  end

  test "punctuation marks and final quotation marks, not initial ones" do
    assert Categories.mark?(?.)
    assert Categories.mark?(?,)
    assert Categories.mark?(0x066B)
    assert Categories.mark?(0x2019)
    assert Categories.mark?(0x00BB)
    refute Categories.mark?(0x00AB)
    refute Categories.mark?(0x2018)
    refute Categories.mark?(?()
    refute Categories.mark?(?$)
  end

  test "spaces" do
    assert Categories.space?(0x0020)
    assert Categories.space?(0x00A0)
    assert Categories.space?(0x202F)
    assert Categories.space?(0x3000)
    refute Categories.space?(?\t)
    refute Categories.space?(?\n)
  end

  test "names the Unicode version it was generated from" do
    assert Categories.unicode_version() =~ ~r/\A\d+\.\d+\.\d+\z/
  end
end
