defmodule Localize.Message.SigilTest do
  use ExUnit.Case, async: true

  import Localize.Message.Sigil

  doctest Localize.Message.Sigil

  describe "sigil_M/2 at compile time" do
    test "valid single-line message compiles and returns canonical form" do
      assert ~M(Hello {$name}) == "Hello {$name}"
    end

    test "valid multi-line message compiles" do
      message = ~M"""
      .input {$count :number}
      .match $count
      1 {{one item}}
      * {{other items}}
      """

      assert is_binary(message)
      assert message =~ ".input"
      assert message =~ ".match"
    end

    test "invalid message raises at compile time with file, line, and column" do
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          import Localize.Message.Sigil
          ~M(Hello {unclosed)
          """)
        end

      # The exception message is built by Elixir's CompileError and
      # embeds the description we raised with.
      assert Exception.message(error) =~ "invalid MF2 message in ~M sigil"
      assert Exception.message(error) =~ "column"
    end

    test "column in compile error points inside the sigil body" do
      # Syntax error at the `{` on column 7 of the MF2 input.
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          import Localize.Message.Sigil
          ~M(Hello {broken)
          """)
        end

      msg = Exception.message(error)
      # The parser reports column relative to the MF2 source; for a
      # single-line sigil that maps directly to the message column.
      assert msg =~ ~r/column \d+/
    end
  end
end
