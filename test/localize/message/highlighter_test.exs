defmodule Localize.Message.HighlighterTest do
  use ExUnit.Case, async: true

  alias Localize.Message
  alias Localize.Message.Formatter.Plain
  alias Localize.Message.Highlighter

  describe "token classification" do
    test "plain text produces a single :text token" do
      assert {:ok, [{:text, "Hello"}]} = Message.to_tokens("Hello")
    end

    test "variable expression produces expected class sequence" do
      assert {:ok, tokens} = Message.to_tokens("Hello {$name}!")

      assert Enum.map(tokens, &elem(&1, 0)) == [
               :text,
               :punctuation_bracket,
               :variable,
               :punctuation_bracket,
               :text
             ]

      assert Enum.find_value(tokens, fn
               {:variable, t} -> t
               _ -> nil
             end) == "$name"
    end

    test "function expression classifies the function name" do
      assert {:ok, tokens} = Message.to_tokens("{$count :number}")

      assert [
               {:punctuation_bracket, "{"},
               {:variable, "$count"},
               {:punctuation_bracket, " "},
               {:function, ":number"},
               {:punctuation_bracket, "}"}
             ] = tokens
    end

    test "markup open/close produces :tag tokens" do
      assert {:ok, tokens} = Message.to_tokens("{#bold}text{/bold}")

      classes = Enum.map(tokens, &elem(&1, 0))
      assert :tag in classes
      assert :punctuation_bracket in classes
      assert :text in classes

      # Both the open and close tag names are classified.
      tag_tokens = Enum.filter(tokens, &match?({:tag, _}, &1))
      assert length(tag_tokens) == 2
      assert Enum.all?(tag_tokens, fn {_, t} -> t == "bold" end)
    end

    test "standalone markup produces /} punctuation" do
      assert {:ok, tokens} = Message.to_tokens("before {#br /}after")

      punct_texts =
        for {:punctuation_bracket, text} <- tokens, do: text

      assert "{#" in punct_texts
      assert " /}" in punct_texts
    end

    test "quoted literal is classified as :string" do
      assert {:ok, tokens} = Message.to_tokens("{|hello world|}")

      string_tokens = Enum.filter(tokens, &match?({:string, _}, &1))
      # Both `|` delimiters AND the content show as :string.
      assert string_tokens != []
      # Concatenated string tokens surround the content.
      concat = Enum.map_join(string_tokens, &elem(&1, 1))
      assert concat =~ "hello world"
      assert String.starts_with?(concat, "|")
      assert String.ends_with?(concat, "|")
    end

    test "number literal is classified as :number" do
      assert {:ok, tokens_int} = Message.to_tokens("{42}")
      assert Enum.any?(tokens_int, &match?({:number, "42"}, &1))

      assert {:ok, tokens_float} = Message.to_tokens("{3.14}")
      assert Enum.any?(tokens_float, &match?({:number, "3.14"}, &1))
    end

    test ".input / .local / .match keywords are :keyword" do
      msg =
        ".input {$count :number}\n" <>
          ".local $x = {$count}\n" <>
          ".match $x\n" <>
          "1 {{one}}\n" <>
          "* {{other}}"

      assert {:ok, tokens} = Message.to_tokens(msg)

      builtins = for {:keyword, t} <- tokens, do: t
      assert ".input" in builtins
      assert ".local" in builtins
      assert ".match" in builtins
    end

    test "* catchall key is :constant_builtin" do
      msg = ".input {$x :number}\n.match $x\n1 {{one}}\n* {{other}}"
      assert {:ok, tokens} = Message.to_tokens(msg)
      assert Enum.any?(tokens, &match?({:constant_builtin, "*"}, &1))
    end

    test "option names are :property" do
      assert {:ok, tokens} = Message.to_tokens("{$x :number style=|short|}")
      assert Enum.any?(tokens, &match?({:property, "style"}, &1))
    end

    test "attribute names are :attribute and include @" do
      assert {:ok, tokens} = Message.to_tokens("{$x @translate}")
      assert Enum.any?(tokens, &match?({:attribute, "@translate"}, &1))
    end

    test "text escapes split into :text and :string_escape tokens" do
      assert {:ok, tokens} = Message.to_tokens("plain \\{ escaped")

      # The `{` in text requires escaping; should appear as :string_escape.
      assert Enum.any?(tokens, &match?({:string_escape, "\\{"}, &1))
      # Surrounding text remains :text.
      assert Enum.any?(tokens, &match?({:text, _}, &1))
    end
  end

  describe "round-trip with Plain formatter" do
    # The concatenated text of every token must equal the canonical
    # MF2 string. This is the invariant that lets us safely add
    # formatters — they can never corrupt the original message.

    @sample_messages [
      "Hello",
      "Hello {$name}",
      "Hello {$name :string}",
      "{#bold}text{/bold}",
      "Click {#link href=|/home|}here{/link}",
      "before {#br /}after",
      "{$x @translate @dir=|ltr|}",
      "{42} and {3.14}",
      "{|literal with \\| pipe|}",
      "{|literal with \\\\ backslash|}",
      ".input {$count :number}\n.match $count\n1 {{one}}\n* {{other}}",
      ".local $x = {$count}\n{{Count is {$x}}}",
      "escaped \\{ brace",
      "escaped \\\\ backslash",
      "{$x :ns:func}",
      "{|empty|}"
    ]

    for msg <- @sample_messages do
      test "Plain formatter reproduces canonical: #{inspect(msg)}" do
        msg = unquote(msg)
        {:ok, canonical} = Message.canonical_message(msg)
        {:ok, tokens} = Message.to_tokens(msg)
        assert Plain.render(tokens) == canonical
      end
    end
  end

  describe "Highlighter.to_tokens/1" do
    test "works directly on a parsed AST (bypassing parse)" do
      {:ok, ast} = Localize.Message.Parser.parse("Hello {$name}")
      tokens = Highlighter.to_tokens(ast)
      assert is_list(tokens)
      assert Enum.all?(tokens, fn {c, t} -> is_atom(c) and is_binary(t) end)
    end

    test "empty AST produces an empty token list" do
      assert Highlighter.to_tokens([]) == []
    end

    test "text nodes containing brace characters split out :string_escape tokens" do
      # A parsed AST never contains unescaped braces in :text nodes,
      # but ASTs built programmatically (e.g. via JSON.from_json/1) can.
      assert Highlighter.to_tokens([{:text, "a{b"}]) ==
               [text: "a", string_escape: "\\{", text: "b"]
    end

    test "text node ending on an escapable character flushes cleanly" do
      assert Highlighter.to_tokens([{:text, "a{"}]) == [text: "a", string_escape: "\\{"]
    end

    test "quoted operand literal ending on an escapable character flushes cleanly" do
      assert Highlighter.to_tokens([{:expression, {:literal, "ab|"}, nil, []}]) ==
               [
                 punctuation_bracket: "{",
                 string: "|ab",
                 string_escape: "\\|",
                 string: "|",
                 punctuation_bracket: "}"
               ]
    end
  end

  describe "error handling" do
    test "returns error for invalid MF2" do
      assert {:error, _reason} = Message.to_tokens("{unclosed")
    end
  end

  describe "token classification — namespaces, literals and declarations" do
    test "namespaced function name is one :function token including both colons" do
      assert {:ok, tokens} = Message.to_tokens("{$v :ns:func}")
      assert {:function, ":ns:func"} in tokens
    end

    test "namespaced markup tag splits into tag, colon punctuation, tag" do
      assert {:ok, tokens} = Message.to_tokens("{#html:b}x{/html:b}")

      assert [
               {:punctuation_bracket, "{#"},
               {:tag, "html"},
               {:punctuation_bracket, ":"},
               {:tag, "b"},
               {:punctuation_bracket, "}"},
               {:text, "x"},
               {:punctuation_bracket, "{/"},
               {:tag, "html"},
               {:punctuation_bracket, ":"},
               {:tag, "b"},
               {:punctuation_bracket, "}"}
             ] = tokens
    end

    test "escaped pipe inside a quoted literal is a :string_escape token" do
      assert {:ok, tokens} = Message.to_tokens("{|a\\|b|}")

      assert [
               {:punctuation_bracket, "{"},
               {:string, "|a"},
               {:string_escape, "\\|"},
               {:string, "b|"},
               {:punctuation_bracket, "}"}
             ] = tokens
    end

    test "empty literal is the two-pipe :string token" do
      assert {:ok, tokens} = Message.to_tokens("{||}")
      assert {:string, "||"} in tokens
    end

    test ".local declaration produces keyword, variable and equals tokens" do
      assert {:ok, tokens} = Message.to_tokens(".local $x = {|42| :number} {{Result {$x}}}")

      assert {:keyword, ".local"} in tokens
      assert {:punctuation_bracket, " = {"} in tokens
      assert {:string, "|42|"} in tokens
      assert {:function, ":number"} in tokens
    end

    test "multi-selector match classifies number keys and catchalls" do
      message =
        ".input {$a :number} .input {$b :number} " <>
          ".match $a $b 0 0 {{none}} * * {{other}}"

      assert {:ok, tokens} = Message.to_tokens(message)

      assert Enum.count(tokens, &(&1 == {:keyword, ".input"})) == 2
      assert {:keyword, ".match"} in tokens
      assert Enum.count(tokens, &(&1 == {:number, "0"})) == 2
      assert Enum.count(tokens, &(&1 == {:constant_builtin, "*"})) == 2
    end

    test "function-only expression has no operand tokens" do
      assert Message.to_tokens("{:number}") ==
               {:ok,
                [
                  punctuation_bracket: "{ ",
                  function: ":number",
                  punctuation_bracket: "}"
                ]}
    end

    test "option values classify as variable, number, empty and unquoted literals" do
      assert {:ok, tokens} =
               Message.to_tokens("{$x :number opt=$y min=2 empty=|| dash=v2.0 uni=café}")

      assert {:variable, "$y"} in tokens
      assert {:number, "2"} in tokens
      assert {:string, "||"} in tokens
      # Values made of name characters (including digits, dots and
      # non-ASCII name-start characters) emit unquoted.
      assert {:string, "v2.0"} in tokens
      assert {:string, "café"} in tokens
    end

    test "non-numeric literal variant keys emit as :string" do
      assert {:ok, tokens} =
               Message.to_tokens(".input {$x :number} .match $x one {{a}} * {{b}}")

      assert {:string, "one"} in tokens
    end

    test "unquoted option literal value has no pipe delimiters" do
      assert {:ok, tokens} = Message.to_tokens("{$x :number style=short}")

      assert {:property, "style"} in tokens
      assert {:string, "short"} in tokens
      refute Enum.any?(tokens, &match?({:string, "|" <> _}, &1))
    end

    test "attribute with a quoted literal value" do
      assert {:ok, tokens} = Message.to_tokens("{$x @val=|two words|}")

      assert [
               {:punctuation_bracket, "{"},
               {:variable, "$x"},
               {:punctuation_bracket, " "},
               {:attribute, "@val"},
               {:punctuation_bracket, "="},
               {:string, "|two words|"},
               {:punctuation_bracket, "}"}
             ] = tokens
    end
  end
end
