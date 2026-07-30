defmodule Localize.Message.ValidatorTest do
  use ExUnit.Case, async: true

  doctest Localize.Message.Validator

  alias Localize.Message.{Parser, Validator}

  defp validate(message) do
    {:ok, ast} = Parser.parse(message)
    Validator.validate(ast)
  end

  describe "valid messages" do
    test "a simple pattern has nothing to validate" do
      assert validate("{{Hello {$name}}}") == :ok
    end

    test "an annotated selector with a catch-all variant" do
      assert validate(".input {$n :number}\n.match $n\none {{one}}\n* {{other}}") == :ok
    end

    test "a selector annotated through a chain of locals" do
      message =
        ".input {$b :number}\n.local $mid = {$b}\n.local $sel = {$mid}\n.match $sel\n* {{ok}}"

      assert validate(message) == :ok
    end

    test "multiple selectors with a matching catch-all arity" do
      message =
        ".input {$a :string}\n.input {$b :string}\n.match $a $b\nx y {{xy}}\n* * {{fallback}}"

      assert validate(message) == :ok
    end
  end

  describe "duplicate declaration" do
    test "a local that reads the variable it declares" do
      assert validate(".local $n = {$n :number}\n.match $n\n* {{x}}") ==
               {:error, {:duplicate_declaration, "n"}}
    end

    test "the same variable declared twice" do
      assert validate(".input {$n :number}\n.input {$n :number}\n.match $n\n* {{x}}") ==
               {:error, {:duplicate_declaration, "n"}}
    end

    test "declaring a variable already referenced by an earlier declaration" do
      message = ".local $a = {$n :number}\n.input {$n :number}\n.match $a\n* {{x}}"

      assert validate(message) == {:error, {:duplicate_declaration, "n"}}
    end
  end

  describe "missing selector annotation" do
    test "a declared but unannotated selector" do
      assert validate(".input {$foo}\n.match $foo\none {{one}}\n* {{other}}") ==
               {:error, {:missing_selector_annotation, "foo"}}
    end

    test "a selector with no declaration at all" do
      assert validate(".match $foo\n* {{other}}") ==
               {:error, {:missing_selector_annotation, "foo"}}
    end

    test "a local chain that never reaches an annotation" do
      assert validate(".input {$b}\n.local $sel = {$b}\n.match $sel\n* {{x}}") ==
               {:error, {:missing_selector_annotation, "sel"}}
    end
  end

  describe "variant key mismatch" do
    test "fewer keys than selectors" do
      message = ".input {$a :string}\n.input {$b :string}\n.match $a $b\nx {{one}}\n* * {{f}}"

      assert validate(message) == {:error, {:variant_key_mismatch, "x"}}
    end

    test "more keys than selectors" do
      assert validate(".input {$a :string}\n.match $a\nx y {{two}}\n* {{f}}") ==
               {:error, {:variant_key_mismatch, "x y"}}
    end
  end

  describe "missing fallback variant" do
    test "no variant has only catch-all keys" do
      assert validate(".input {$n :number}\n.match $n\none {{one}}\ntwo {{two}}") ==
               {:error, {:missing_fallback_variant, "*"}}
    end

    test "a partially catch-all variant is not a fallback" do
      # `feminine *` still constrains the first selector, so it cannot
      # serve as the all-catch-all fallback the spec requires.
      message =
        ".input {$g :string}\n.input {$n :number}\n.match $g $n\n" <>
          "feminine * {{she}}\nmasculine * {{he}}"

      assert validate(message) == {:error, {:missing_fallback_variant, "*"}}
    end
  end

  describe "duplicate variant and option name" do
    test "the same key list twice" do
      assert validate(".input {$n :number}\n.match $n\none {{a}}\none {{b}}\n* {{c}}") ==
               {:error, {:duplicate_variant, "one"}}
    end

    test "the same option twice in one expression" do
      assert validate("{{ {$n :number style=decimal style=percent} }}") ==
               {:error, {:duplicate_option_name, "style"}}
    end
  end

  describe "parse and validate are separate passes" do
    test "a syntactically valid but semantically invalid message parses" do
      # This is the split the public API depends on: tooling that must
      # accept invalid input parses without validating.
      assert {:ok, _ast} = Parser.parse(".local $n = {$n :number}\n.match $n\n* {{x}}")
    end

    test "format/3 runs both and reports the data-model error" do
      assert {:error, %Localize.FormatError{reason: :duplicate_declaration, detail: "n"}} =
               Localize.Message.format(".local $n = {$n :number}\n.match $n\n* {{x}}", %{n: 1})
    end

    test "canonical_message/2 refuses to serialize an invalid message" do
      assert {:error, %Localize.FormatError{reason: :duplicate_declaration}} =
               Localize.Message.canonical_message(".local $n = {$n :number}\n.match $n\n* {{x}}")
    end

    test "to_tokens/2 still tokenizes an invalid message for highlighting" do
      assert {:ok, tokens} =
               Localize.Message.to_tokens(".local $n = {$n :number}\n.match $n\n* {{x}}")

      assert is_list(tokens) and tokens != []
    end
  end
end
