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
  end

  describe "error handling" do
    test "returns error for invalid MF2" do
      assert {:error, _reason} = Message.to_tokens("{unclosed")
    end
  end
end
