defmodule Localize.Message.JSONTest do
  use ExUnit.Case, async: true

  alias Localize.Message.JSON
  alias Localize.Message.Parser
  alias Localize.Message.Print

  doctest Localize.Message.JSON

  defp to_json!(message) do
    {:ok, ast} = Parser.parse(message)
    JSON.to_json(ast)
  end

  describe "to_json/2 — patterns" do
    test "simple text message" do
      assert to_json!("Hello, world!") == %{
               "type" => "message",
               "declarations" => [],
               "pattern" => ["Hello, world!"]
             }
    end

    test "quoted pattern message" do
      assert to_json!("{{Hello, world!}}") == %{
               "type" => "message",
               "declarations" => [],
               "pattern" => ["Hello, world!"]
             }
    end

    test "variable expression in a pattern" do
      assert to_json!("Hello {$name}!") == %{
               "type" => "message",
               "declarations" => [],
               "pattern" => [
                 "Hello ",
                 %{"type" => "expression", "arg" => %{"type" => "variable", "name" => "name"}},
                 "!"
               ]
             }
    end

    test "escapes are coalesced into adjacent text" do
      assert to_json!("Escaped \\{brace\\} and \\|bar\\|") == %{
               "type" => "message",
               "declarations" => [],
               "pattern" => ["Escaped {brace} and |bar|"]
             }
    end

    test "literal and number literal operands" do
      assert %{"pattern" => pattern} = to_json!("{|literal|} and {42}")

      assert pattern == [
               %{"type" => "expression", "arg" => %{"type" => "literal", "value" => "literal"}},
               " and ",
               %{"type" => "expression", "arg" => %{"type" => "literal", "value" => "42"}}
             ]
    end

    test "function annotation with options" do
      assert %{"pattern" => [expression]} =
               to_json!("{$v :ns:func opt=$var other=|lit| num=3}")

      assert expression == %{
               "type" => "expression",
               "arg" => %{"type" => "variable", "name" => "v"},
               "function" => %{
                 "type" => "function",
                 "name" => "ns:func",
                 "options" => %{
                   "opt" => %{"type" => "variable", "name" => "var"},
                   "other" => %{"type" => "literal", "value" => "lit"},
                   "num" => %{"type" => "literal", "value" => "3"}
                 }
               }
             }
    end

    test "expression attributes serialize as a map with true for bare attributes" do
      assert %{"pattern" => [expression]} = to_json!("{$x @attr @val=|v|}")

      assert expression["attributes"] == %{
               "attr" => true,
               "val" => %{"type" => "literal", "value" => "v"}
             }
    end
  end

  describe "to_json/2 — declarations" do
    test ".input declaration with function options" do
      json = to_json!(".input {$count :number style=decimal} {{You have {$count} items}}")

      assert json["type"] == "message"

      assert json["declarations"] == [
               %{
                 "type" => "input",
                 "name" => "count",
                 "value" => %{
                   "type" => "expression",
                   "arg" => %{"type" => "variable", "name" => "count"},
                   "function" => %{
                     "type" => "function",
                     "name" => "number",
                     "options" => %{"style" => %{"type" => "literal", "value" => "decimal"}}
                   }
                 }
               }
             ]
    end

    test ".local declaration with a literal operand" do
      json = to_json!(".local $x = {|42| :number} {{Result {$x}}}")

      assert json["declarations"] == [
               %{
                 "type" => "local",
                 "name" => "x",
                 "value" => %{
                   "type" => "expression",
                   "arg" => %{"type" => "literal", "value" => "42"},
                   "function" => %{"type" => "function", "name" => "number"}
                 }
               }
             ]
    end
  end

  describe "to_json/2 — select messages" do
    test "match with declarations, catchall and literal keys" do
      json =
        to_json!(".input {$count :number} .match $count one {{one item}} * {{{$count} items}}")

      assert json["type"] == "select"
      assert [%{"type" => "input", "name" => "count"}] = json["declarations"]
      assert json["selectors"] == [%{"type" => "variable", "name" => "count"}]

      assert json["variants"] == [
               %{
                 "keys" => [%{"type" => "literal", "value" => "one"}],
                 "value" => ["one item"]
               },
               %{
                 "keys" => [%{"type" => "*"}],
                 "value" => [
                   %{"type" => "expression", "arg" => %{"type" => "variable", "name" => "count"}},
                   " items"
                 ]
               }
             ]
    end

    test "match with multiple selectors and multi-key variants" do
      json =
        to_json!(
          ".input {$a :number} .input {$b :number} " <>
            ".match $a $b 0 0 {{none}} 1 * {{a one}} * * {{other}}"
        )

      assert json["type"] == "select"

      assert json["selectors"] == [
               %{"type" => "variable", "name" => "a"},
               %{"type" => "variable", "name" => "b"}
             ]

      assert [
               %{"keys" => [%{"value" => "0"}, %{"value" => "0"}]},
               %{"keys" => [%{"value" => "1"}, %{"type" => "*"}]},
               %{"keys" => [%{"type" => "*"}, %{"type" => "*"}]}
             ] = json["variants"]
    end
  end

  describe "to_json/2 — markup" do
    test "open, close and standalone markup" do
      assert %{"pattern" => pattern} =
               to_json!("Click {#link href=|/home| @translate}here{/link} now {#br/}")

      assert pattern == [
               "Click ",
               %{
                 "type" => "markup",
                 "kind" => "open",
                 "name" => "link",
                 "options" => %{"href" => %{"type" => "literal", "value" => "/home"}},
                 "attributes" => %{"translate" => true}
               },
               "here",
               %{"type" => "markup", "kind" => "close", "name" => "link"},
               " now ",
               %{"type" => "markup", "kind" => "standalone", "name" => "br"}
             ]
    end

    test "namespaced markup names serialize as ns:name" do
      assert %{"pattern" => pattern} = to_json!("{#html:b}x{/html:b}")

      assert [
               %{"type" => "markup", "kind" => "open", "name" => "html:b"},
               "x",
               %{"type" => "markup", "kind" => "close", "name" => "html:b"}
             ] = pattern
    end
  end

  describe "to_json/2 — :encode option" do
    test "returns a JSON string that decodes to the map form" do
      {:ok, ast} = Parser.parse("{{Hello {$name}!}}")

      encoded = JSON.to_json(ast, encode: true)
      assert is_binary(encoded)
      assert :json.decode(encoded) == JSON.to_json(ast)
    end
  end

  describe "from_json/1 — messages" do
    test "message with no declarations produces a quoted pattern AST" do
      json = %{"type" => "message", "declarations" => [], "pattern" => ["Hello!"]}

      assert JSON.from_json(json) == {:ok, [quoted_pattern: [text: "Hello!"]]}
    end

    test "accepts a JSON-encoded string" do
      json = ~s({"type":"message","declarations":[],"pattern":["Hello!"]})

      assert JSON.from_json(json) == {:ok, [quoted_pattern: [text: "Hello!"]]}
    end

    test "message with declarations produces a complex AST" do
      json = %{
        "type" => "message",
        "declarations" => [
          %{
            "type" => "input",
            "name" => "count",
            "value" => %{
              "type" => "expression",
              "arg" => %{"type" => "variable", "name" => "count"},
              "function" => %{"type" => "function", "name" => "number"}
            }
          }
        ],
        "pattern" => [
          %{"type" => "expression", "arg" => %{"type" => "variable", "name" => "count"}}
        ]
      }

      assert JSON.from_json(json) ==
               {:ok,
                [
                  {:complex,
                   [
                     {:input, {:expression, {:variable, "count"}, {:function, "number", []}, []}}
                   ], {:quoted_pattern, [{:expression, {:variable, "count"}, nil, []}]}}
                ]}
    end

    test "local declarations parse back to :local nodes" do
      json = %{
        "type" => "message",
        "declarations" => [
          %{
            "type" => "local",
            "name" => "x",
            "value" => %{
              "type" => "expression",
              "arg" => %{"type" => "literal", "value" => "42"},
              "function" => %{"type" => "function", "name" => "number"}
            }
          }
        ],
        "pattern" => ["done"]
      }

      assert {:ok, [{:complex, [declaration], _pattern}]} = JSON.from_json(json)

      assert declaration ==
               {:local, {:variable, "x"},
                {:expression, {:number_literal, "42"}, {:function, "number", []}, []}}
    end

    test "select with variants parses keys including catchall and numbers" do
      json = %{
        "type" => "select",
        "declarations" => [],
        "selectors" => [%{"type" => "variable", "name" => "count"}],
        "variants" => [
          %{"keys" => [%{"type" => "literal", "value" => "1"}], "value" => ["one"]},
          %{"keys" => [%{"type" => "literal", "value" => "many"}], "value" => ["many"]},
          %{"keys" => [%{"type" => "*"}], "value" => ["other"]}
        ]
      }

      assert JSON.from_json(json) ==
               {:ok,
                [
                  {:match, [{:variable, "count"}],
                   [
                     {:variant, [{:number_literal, "1"}], {:quoted_pattern, [text: "one"]}},
                     {:variant, [{:literal, "many"}], {:quoted_pattern, [text: "many"]}},
                     {:variant, [:catchall], {:quoted_pattern, [text: "other"]}}
                   ]}
                ]}
    end

    test "markup kinds parse back to their AST node shapes" do
      json = %{
        "type" => "message",
        "declarations" => [],
        "pattern" => [
          %{"type" => "markup", "kind" => "open", "name" => "b"},
          "x",
          %{"type" => "markup", "kind" => "close", "name" => "b"},
          %{"type" => "markup", "kind" => "standalone", "name" => "br"}
        ]
      }

      assert JSON.from_json(json) ==
               {:ok,
                [
                  quoted_pattern: [
                    {:markup_open, "b", [], []},
                    {:text, "x"},
                    {:markup_close, "b", [], []},
                    {:markup_standalone, "br", [], []}
                  ]
                ]}
    end

    test "namespaced function names parse back to namespace tuples" do
      json = %{
        "type" => "message",
        "declarations" => [],
        "pattern" => [
          %{
            "type" => "expression",
            "arg" => %{"type" => "variable", "name" => "v"},
            "function" => %{"type" => "function", "name" => "ns:func"}
          }
        ]
      }

      assert {:ok, [quoted_pattern: [expression]]} = JSON.from_json(json)

      assert expression ==
               {:expression, {:variable, "v"}, {:function, {:namespace, "ns", "func"}, []}, []}
    end

    test "attributes parse back with nil for bare attributes" do
      json = %{
        "type" => "message",
        "declarations" => [],
        "pattern" => [
          %{
            "type" => "expression",
            "arg" => %{"type" => "variable", "name" => "x"},
            "attributes" => %{
              "attr" => true,
              "val" => %{"type" => "literal", "value" => "v"}
            }
          }
        ]
      }

      assert {:ok, [quoted_pattern: [{:expression, {:variable, "x"}, nil, attributes}]]} =
               JSON.from_json(json)

      assert Enum.sort(attributes) == [
               {:attribute, "attr", nil},
               {:attribute, "val", {:literal, "v"}}
             ]
    end
  end

  describe "top-level AST shapes produced by from_json/1" do
    test "a bare quoted-pattern AST serializes as a message" do
      assert JSON.to_json([{:quoted_pattern, [text: "Hi"]}]) == %{
               "type" => "message",
               "declarations" => [],
               "pattern" => ["Hi"]
             }
    end

    test "function-only expression serializes without an arg" do
      assert to_json!("{:number}") == %{
               "type" => "message",
               "declarations" => [],
               "pattern" => [
                 %{
                   "type" => "expression",
                   "function" => %{"type" => "function", "name" => "number"}
                 }
               ]
             }
    end

    test "from_json parses a function-only expression with a nil operand" do
      json = %{
        "type" => "message",
        "declarations" => [],
        "pattern" => [
          %{"type" => "expression", "function" => %{"type" => "function", "name" => "number"}}
        ]
      }

      assert JSON.from_json(json) ==
               {:ok, [quoted_pattern: [{:expression, nil, {:function, "number", []}, []}]]}
    end
  end

  describe "top-level match ASTs (no declarations)" do
    # `from_json/1` returns a bare `[{:match, ...}]` AST for a select
    # with no declarations; `to_json/2` accepts that shape back.
    test "to_json and from_json are symmetric for a bare match AST" do
      ast = [
        {:match, [{:variable, "count"}],
         [
           {:variant, [{:number_literal, "1"}], {:quoted_pattern, [text: "a"]}},
           {:variant, [:catchall], {:quoted_pattern, [text: "b"]}}
         ]}
      ]

      json = JSON.to_json(ast)

      assert json == %{
               "type" => "select",
               "declarations" => [],
               "selectors" => [%{"type" => "variable", "name" => "count"}],
               "variants" => [
                 %{"keys" => [%{"type" => "literal", "value" => "1"}], "value" => ["a"]},
                 %{"keys" => [%{"type" => "*"}], "value" => ["b"]}
               ]
             }

      assert JSON.from_json(json) == {:ok, ast}
    end

    test "select with declarations parses to a complex match AST" do
      json = %{
        "type" => "select",
        "declarations" => [
          %{
            "type" => "input",
            "name" => "c",
            "value" => %{
              "type" => "expression",
              "arg" => %{"type" => "variable", "name" => "c"},
              "function" => %{"type" => "function", "name" => "number"}
            }
          }
        ],
        "selectors" => [%{"type" => "variable", "name" => "c"}],
        "variants" => [%{"keys" => [%{"type" => "*"}], "value" => ["x"]}]
      }

      assert JSON.from_json(json) ==
               {:ok,
                [
                  {:complex,
                   [input: {:expression, {:variable, "c"}, {:function, "number", []}, []}],
                   {:match, [variable: "c"],
                    [{:variant, [:catchall], {:quoted_pattern, [text: "x"]}}]}}
                ]}
    end
  end

  describe "from_json/1 — errors" do
    test "invalid JSON string" do
      assert JSON.from_json("{not json") == {:error, "invalid JSON"}
    end

    test "JSON string that is not an object" do
      assert JSON.from_json("[1,2,3]") == {:error, "expected a JSON object"}
    end

    test "map without a recognised type" do
      assert JSON.from_json(%{"foo" => "bar"}) ==
               {:error, "expected a message or select object with type field"}
    end
  end

  describe "round-trips (parse → to_json → from_json)" do
    # Messages whose top-level AST survives the round-trip exactly
    # (complex messages and top-level selects).
    round_trip_exact = [
      ".input {$count :number style=decimal} {{You have {$count} items}}",
      ".input {$count :number} .match $count one {{one item}} * {{{$count} items}}",
      ".input {$a :number} .input {$b :number} .match $a $b 0 0 {{none}} 1 * {{a one}} * * {{other}}"
    ]

    for message <- round_trip_exact do
      test "AST round-trips exactly: #{inspect(message)}" do
        {:ok, ast} = Parser.parse(unquote(message))
        assert {:ok, round_tripped} = ast |> JSON.to_json() |> JSON.from_json()
        assert round_tripped == ast
      end
    end

    # Simple messages round-trip to the quoted-pattern form; the
    # canonical text differs only by the surrounding {{...}}.
    # Function options are serialized as a JSON object, so option
    # order is not preserved and multi-option expressions are not
    # canonically comparable here.
    round_trip_quoted = [
      "Hello {$name}!",
      "{|literal|} and {42}",
      "Click {#link href=|/home| @translate}here{/link} now {#br/}",
      "{$v :ns:func opt=$var}"
    ]

    for message <- round_trip_quoted do
      test "canonical round-trips modulo quoting: #{inspect(message)}" do
        {:ok, ast} = Parser.parse(unquote(message))
        assert {:ok, round_tripped} = ast |> JSON.to_json() |> JSON.from_json()

        assert Print.to_string(round_tripped) == "{{" <> Print.to_string(ast) <> "}}"
      end
    end

    test "formatting output survives the round-trip" do
      message = ".input {$count :number} .match $count one {{one item}} * {{{$count} items}}"
      {:ok, ast} = Parser.parse(message)
      {:ok, round_tripped} = ast |> JSON.to_json() |> JSON.from_json()

      original = Localize.Message.format!(message, %{"count" => 3})
      round_trip_message = Print.to_string(round_tripped)

      assert Localize.Message.format!(round_trip_message, %{"count" => 3}) == original
    end

    test "encoded string round-trips through from_json/1" do
      {:ok, ast} = Parser.parse(".local $x = {1 :number} {{Result {$x}}}")

      assert {:ok, round_tripped} = ast |> JSON.to_json(encode: true) |> JSON.from_json()
      assert round_tripped == ast
    end
  end
end
