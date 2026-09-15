defmodule Localize.Message.LiteralCodePointsTest do
  @moduledoc """
  Literals keep their code points, while keys still match in Normalization
  Form C.

  Expected values come from TR35 Part 9, which preserves all of a literal's
  code points, so a quoted or unquoted literal formats unchanged, while its
  NormalizeKey operation and selection with `:string` compare a key and a
  selector's value in Unicode Normalization Form C. D WITH DOT ABOVE
  followed by COMBINING DOT BELOW (U+1E0A U+0323) is not in NFC, whose form
  is D WITH DOT BELOW followed by COMBINING DOT ABOVE (U+1E0C U+0307).

  """

  use ExUnit.Case, async: true

  @decomposed <<0x1E0A::utf8, 0x0323::utf8>>
  @composed <<0x1E0C::utf8, 0x0307::utf8>>

  test "quoted and unquoted literals format with their own code points" do
    assert Localize.Message.format("{|" <> @decomposed <> "|}", %{}, backend: :elixir) ==
             {:ok, @decomposed}

    assert Localize.Message.format("{" <> @decomposed <> "}", %{}, backend: :elixir) ==
             {:ok, @decomposed}
  end

  test "a key matches a selector value that differs from it only in normalization" do
    message = ".input {$x :string} .match $x " <> @composed <> " {{matched}} * {{other}}"

    assert Localize.Message.format(message, %{x: @decomposed}, backend: :elixir) ==
             {:ok, "matched"}
  end
end
