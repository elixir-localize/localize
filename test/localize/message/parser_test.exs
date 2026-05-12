defmodule Localize.Message.ParserTest do
  use ExUnit.Case, async: true

  doctest Localize.Message.Parser

  alias Localize.Message.Parser

  describe "simple messages" do
    test "empty message" do
      assert {:ok, []} = Parser.parse("")
    end

    test "plain text" do
      assert {:ok, [{:text, "Hello, world!"}]} = Parser.parse("Hello, world!")
    end

    test "text with leading whitespace is preserved" do
      assert {:ok, [{:text, "\n hello\t"}]} = Parser.parse("\n hello\t")
    end

    test "escaped characters" do
      assert {:ok, [{:escape, "\\"}, {:escape, "{"}]} = Parser.parse("\\\\\\{")
    end

    test "mixed text and escapes" do
      assert {:ok, [{:text, "Hello "}, {:escape, "{"}, {:text, "world"}, {:escape, "}"}]} =
               Parser.parse("Hello \\{world\\}")
    end
  end

  describe "variable expressions" do
    test "simple variable" do
      assert {:ok, [{:expression, {:variable, "name"}, nil, []}]} = Parser.parse("{$name}")
    end

    test "variable with function" do
      assert {:ok, [{:expression, {:variable, "count"}, {:function, "number", []}, []}]} =
               Parser.parse("{$count :number}")
    end

    test "variable with function and options" do
      assert {:ok,
              [
                {:expression, {:variable, "date"},
                 {:function, "datetime", [{:option, "dateStyle", {:literal, "long"}}]}, []}
              ]} = Parser.parse("{$date :datetime dateStyle=long}")
    end

    test "variable with attribute" do
      assert {:ok, [{:expression, {:variable, "x"}, nil, [{:attribute, "locale", nil}]}]} =
               Parser.parse("{$x @locale}")
    end

    test "variable with attribute and value" do
      assert {:ok,
              [
                {:expression, {:variable, "x"}, nil,
                 [{:attribute, "source", {:literal, "input"}}]}
              ]} = Parser.parse("{$x @source=|input|}")
    end
  end

  describe "literal expressions" do
    test "quoted literal" do
      assert {:ok, [{:expression, {:literal, "hello"}, nil, []}]} = Parser.parse("{|hello|}")
    end

    test "quoted literal with escape" do
      assert {:ok, [{:expression, {:literal, "hel|lo"}, nil, []}]} =
               Parser.parse("{|hel\\|lo|}")
    end

    test "unquoted literal" do
      assert {:ok, [{:expression, {:literal, "world"}, nil, []}]} = Parser.parse("{world}")
    end

    test "number literal" do
      assert {:ok, [{:expression, {:number_literal, "42"}, nil, []}]} = Parser.parse("{42}")
    end

    test "negative number literal" do
      assert {:ok, [{:expression, {:number_literal, "-3.14"}, nil, []}]} =
               Parser.parse("{-3.14}")
    end

    test "literal with function" do
      assert {:ok, [{:expression, {:literal, "hello"}, {:function, "string", []}, []}]} =
               Parser.parse("{|hello| :string}")
    end
  end

  describe "function expressions" do
    test "standalone function" do
      assert {:ok, [{:expression, nil, {:function, "now", []}, []}]} = Parser.parse("{:now}")
    end

    test "namespaced function" do
      assert {:ok,
              [{:expression, {:variable, "x"}, {:function, {:namespace, "ns", "func"}, []}, []}]} =
               Parser.parse("{$x :ns:func}")
    end

    test "function with options" do
      assert {:ok,
              [
                {:expression, nil,
                 {:function, "now",
                  [
                    {:option, "dateStyle", {:literal, "long"}},
                    {:option, "timeStyle", {:literal, "short"}}
                  ]}, []}
              ]} = Parser.parse("{:now dateStyle=long timeStyle=short}")
    end

    test "option with variable value" do
      assert {:ok,
              [
                {:expression, {:variable, "x"},
                 {:function, "number", [{:option, "style", {:variable, "s"}}]}, []}
              ]} = Parser.parse("{$x :number style=$s}")
    end
  end

  describe "markup" do
    test "open markup" do
      assert {:ok, [{:markup_open, "bold", [], []}]} = Parser.parse("{#bold}")
    end

    test "close markup" do
      assert {:ok, [{:markup_close, "bold", [], []}]} = Parser.parse("{/bold}")
    end

    test "standalone markup" do
      assert {:ok, [{:markup_standalone, "br", [], []}]} = Parser.parse("{#br /}")
    end

    test "markup with options" do
      assert {:ok, [{:markup_standalone, "img", [{:option, "src", {:literal, "photo.jpg"}}], []}]} =
               Parser.parse("{#img src=|photo.jpg| /}")
    end

    test "markup with attributes" do
      assert {:ok, [{:markup_open, "div", [], [{:attribute, "translate", nil}]}]} =
               Parser.parse("{#div @translate}")
    end

    test "open and close markup with text" do
      assert {:ok,
              [
                {:markup_open, "bold", [], []},
                {:text, "text"},
                {:markup_close, "bold", [], []}
              ]} = Parser.parse("{#bold}text{/bold}")
    end
  end

  describe "complex messages - declarations" do
    test "input declaration" do
      assert {:ok,
              [
                {:complex,
                 [{:input, {:expression, {:variable, "x"}, {:function, "number", []}, []}}],
                 {:quoted_pattern, [{:expression, {:variable, "x"}, nil, []}]}}
              ]} = Parser.parse(".input {$x :number} {{{$x}}}")
    end

    test "local declaration" do
      assert {:ok,
              [
                {:complex,
                 [
                   {:local, {:variable, "y"},
                    {:expression, {:variable, "x"}, {:function, "number", []}, []}}
                 ], {:quoted_pattern, [{:expression, {:variable, "y"}, nil, []}]}}
              ]} = Parser.parse(".local $y = {$x :number} {{{$y}}}")
    end

    test "multiple declarations" do
      msg = ".input {$x :number}\n.local $y = {$x :number}\n{{result}}"

      assert {:ok,
              [
                {:complex,
                 [
                   {:input, {:expression, {:variable, "x"}, {:function, "number", []}, []}},
                   {:local, {:variable, "y"},
                    {:expression, {:variable, "x"}, {:function, "number", []}, []}}
                 ], {:quoted_pattern, [{:text, "result"}]}}
              ]} = Parser.parse(msg)
    end
  end

  describe "complex messages - matcher" do
    test "simple match" do
      msg = ".input {$count :number}\n.match $count\n1 {{one item}}\n* {{other items}}"

      assert {:ok,
              [
                {:complex,
                 [{:input, {:expression, {:variable, "count"}, {:function, "number", []}, []}}],
                 {:match, [{:variable, "count"}],
                  [
                    {:variant, [{:number_literal, "1"}],
                     {:quoted_pattern, [{:text, "one item"}]}},
                    {:variant, [:catchall], {:quoted_pattern, [{:text, "other items"}]}}
                  ]}}
              ]} = Parser.parse(msg)
    end

    test "match with multiple selectors" do
      msg =
        ".input {$g :string}\n.input {$c :number}\n.match $g $c\nfemale 1 {{she has one}}\n* * {{they have many}}"

      assert {:ok, [{:complex, _, {:match, selectors, variants}}]} = Parser.parse(msg)
      assert length(selectors) == 2
      assert length(variants) == 2

      assert [
               {:variant, [{:literal, "female"}, {:number_literal, "1"}], _},
               {:variant, [:catchall, :catchall], _}
             ] = variants
    end
  end

  describe "complex messages - quoted pattern" do
    test "bare quoted pattern" do
      assert {:ok, [{:complex, [], {:quoted_pattern, [{:text, "hello"}]}}]} =
               Parser.parse("{{hello}}")
    end

    test "empty quoted pattern" do
      assert {:ok, [{:complex, [], {:quoted_pattern, []}}]} = Parser.parse("{{}}")
    end

    test "quoted pattern with expression" do
      assert {:ok,
              [
                {:complex, [],
                 {:quoted_pattern,
                  [{:text, "Hello "}, {:expression, {:variable, "name"}, nil, []}]}}
              ]} = Parser.parse("{{Hello {$name}}}")
    end
  end

  describe "error cases" do
    test "unclosed brace" do
      assert {:error, _} = Parser.parse("{")
    end

    test "empty expression" do
      assert {:error, _} = Parser.parse("{}")
    end

    test "missing end of quoted pattern" do
      assert {:error, _} = Parser.parse("{{missing end brace}")
    end

    test "bare dot" do
      assert {:error, _} = Parser.parse(".")
    end
  end

  describe "error location tracking" do
    test "single-line error reports line 1 and correct column" do
      # The `{` is at byte 6 (0-indexed), so line 1, column 7.
      assert {:error, error} = Parser.parse("Hello {")
      assert %Localize.ParseError{line: 1, column: 7, offset: 6, rest: "{"} = error
      assert error.input == "Hello {"
      assert is_atom(error.reason) and not is_nil(error.reason)
    end

    test "multi-line error reports correct line and column" do
      # After `Hello\n` (6 bytes) comes `world ` (6 chars) then `{`.
      # The `{` is on line 2 at column 7.
      assert {:error, error} = Parser.parse("Hello\nworld {unclosed")
      assert %Localize.ParseError{line: 2, column: 7, offset: 12} = error
    end

    test "error at start of input reports line 1 column 1" do
      assert {:error, %{line: 1, column: 1, offset: 0}} = Parser.parse(".")
    end

    test "error at end of third line reports correct position" do
      # "a\nb\ncd{" — `{` is at offset 6, line 3, column 3.
      assert {:error, %{line: 3, column: 3, offset: 6}} = Parser.parse("a\nb\ncd{")
    end

    test "exception message includes line and column" do
      {:error, error} = Parser.parse("Hello\n{")
      msg = Exception.message(error)
      assert msg =~ "line 2"
      assert msg =~ "column 1"
    end

    test "parse! raises exception with location fields populated" do
      error =
        try do
          Parser.parse!("Hello\n{")
        rescue
          e in Localize.ParseError -> e
        end

      assert %Localize.ParseError{line: 2, column: 1, offset: 6} = error
    end
  end

  describe "ParseError.line_column/2" do
    test "computes positions across various byte offsets" do
      assert {1, 1} = Localize.ParseError.line_column("", 0)
      assert {1, 1} = Localize.ParseError.line_column("abc", 0)
      assert {1, 4} = Localize.ParseError.line_column("abc", 3)
      assert {2, 1} = Localize.ParseError.line_column("a\nb", 2)
      assert {3, 2} = Localize.ParseError.line_column("a\nb\ncd", 5)
    end

    test "handles multibyte characters by column (grapheme count)" do
      # "café" is 5 bytes, 4 graphemes. Offset 5 is column 5 (one past end).
      assert {1, 5} = Localize.ParseError.line_column("café", 5)
    end

    test "clamps out-of-bounds offsets to the end of input" do
      assert {1, 4} = Localize.ParseError.line_column("abc", 999)
    end
  end

  describe "input length cap" do
    test "rejects oversized message without invoking the grammar" do
      cap = Parser.max_message_bytes()
      huge = String.duplicate("a", cap + 1)

      assert {:error, %Localize.ParseError{reason: reason}} = Parser.parse(huge)
      assert reason =~ "exceeds"
    end
  end
end
