defmodule Localize.Message.JSONDataModelTest do
  @moduledoc """
  Checks `Localize.Message.JSON` against TR35's Interchange Data Model.

  The oracle is the `message.json` schema of TR35 Part 9, written here
  as `schema?/1`, and the working group's conformance messages: every
  one that parses is converted to the model, checked against the
  schema, and converted back.

  """
  use ExUnit.Case, async: true

  alias Localize.Message.{Highlighter, JSON, Parser, Print}

  @conformance_dir Path.expand("../../support/data/mf2_conformance", __DIR__)

  @sources @conformance_dir
           |> Path.join("**/*.json")
           |> Path.wildcard()
           |> Enum.flat_map(fn file ->
             file
             |> File.read!()
             |> :json.decode()
             |> Map.get("tests", [])
             |> Enum.map(&Map.get(&1, "src"))
           end)
           |> Enum.filter(&is_binary/1)
           |> Enum.uniq()

  @variable %{"type" => "variable", "name" => "x"}

  # What `from_json/1` must refuse, with an error and without raising.
  @malformed [
    %{"type" => "message", "declarations" => [], "pattern" => "x"},
    %{"type" => "message", "declarations" => nil, "pattern" => []},
    %{"type" => "message", "declarations" => [%{"type" => "bogus"}], "pattern" => []},
    %{"type" => "message", "pattern" => [1]},
    %{"type" => "message", "pattern" => [nil]},
    %{"type" => "message", "pattern" => [%{"type" => "junk"}]},
    %{"type" => "message", "pattern" => [%{"type" => "markup", "kind" => "x", "name" => "b"}]},
    %{"type" => "message", "pattern" => [%{"type" => "markup", "kind" => "open"}]},
    %{"type" => "message", "pattern" => [%{"type" => "expression"}]},
    %{"type" => "message", "pattern" => [%{"type" => "expression", "arg" => nil}]},
    %{
      "type" => "message",
      "pattern" => [%{"type" => "expression", "arg" => %{"type" => "literal", "value" => 1}}]
    },
    %{
      "type" => "message",
      "pattern" => [%{"type" => "expression", "arg" => @variable, "attributes" => []}]
    },
    %{
      "type" => "message",
      "pattern" => [%{"type" => "expression", "arg" => @variable, "attributes" => %{"a" => 1}}]
    },
    %{
      "type" => "message",
      "pattern" => [
        %{"type" => "expression", "arg" => @variable, "attributes" => %{"a" => @variable}}
      ]
    },
    %{
      "type" => "message",
      "pattern" => [
        %{
          "type" => "expression",
          "function" => %{"type" => "function", "name" => "f", "options" => %{"a" => "b"}}
        }
      ]
    },
    %{
      "type" => "message",
      "pattern" => [%{"type" => "expression", "function" => %{"type" => "function"}}]
    },
    %{"type" => "select", "declarations" => [], "selectors" => [], "variants" => []},
    %{
      "type" => "select",
      "selectors" => [%{"type" => "literal", "value" => "x"}],
      "variants" => [%{"keys" => [%{"type" => "*"}], "value" => []}]
    },
    %{"type" => "select", "selectors" => [@variable], "variants" => []},
    %{"type" => "select", "selectors" => [@variable], "variants" => [%{"keys" => []}]},
    %{
      "type" => "select",
      "selectors" => [@variable],
      "variants" => [%{"keys" => [%{"type" => "bogus"}], "value" => []}]
    },
    %{"type" => "other", "pattern" => []},
    %{},
    :atom,
    nil,
    [],
    42
  ]

  # Text that is not a name. If one were taken as a name, the message
  # printed from the AST would be another message.
  @not_names ["", "a b", " a", "a ", "1a", "a}} {$b", "a :number", "a|b", "$a", "a\n", "a=b"]

  describe "to_json/2 against the message.json schema" do
    test "every conformance message that parses converts to a schema-valid model" do
      parsed = parsed_sources()
      assert Enum.count_until(parsed, 301) == 301

      for {source, ast} <- parsed do
        json = JSON.to_json(ast)
        assert schema?(json), "not schema-valid: #{inspect(source)} gave #{inspect(json)}"
      end
    end

    test "namespaced option and attribute names are identifier strings" do
      {:ok, ast} = Parser.parse("{$n :number u:dir=ltr ns:opt=$v @u:id=x @ns:flag}")
      [expression] = JSON.to_json(ast)["pattern"]

      assert expression["function"]["options"] == %{
               "u:dir" => %{"type" => "literal", "value" => "ltr"},
               "ns:opt" => %{"type" => "variable", "name" => "v"}
             }

      assert expression["attributes"] == %{
               "u:id" => %{"type" => "literal", "value" => "x"},
               "ns:flag" => true
             }
    end

    test "namespaced markup options and attributes are identifier strings" do
      {:ok, ast} = Parser.parse("{#ns:tag u:id=x @ns:a}c{/ns:tag}")
      [open, "c", close] = JSON.to_json(ast)["pattern"]

      assert open == %{
               "type" => "markup",
               "kind" => "open",
               "name" => "ns:tag",
               "options" => %{"u:id" => %{"type" => "literal", "value" => "x"}},
               "attributes" => %{"ns:a" => true}
             }

      assert close == %{"type" => "markup", "kind" => "close", "name" => "ns:tag"}
    end

    test "a namespaced option encodes as JSON" do
      {:ok, ast} = Parser.parse("{$n :number u:dir=ltr}")
      encoded = JSON.to_json(ast, encode: true)

      assert is_binary(encoded)
      assert :json.decode(encoded) == JSON.to_json(ast)
    end

    test "escapes are cooked and a pattern holds no empty string" do
      {:ok, ast} = Parser.parse("{{a \\{ b \\} \\\\ \\| c}}")
      assert JSON.to_json(ast)["pattern"] == ["a { b } \\ | c"]

      assert JSON.to_json([{:text, ""}])["pattern"] == []
      assert JSON.to_json([])["pattern"] == []
    end

    test "a literal's value is cooked and its quoting is not kept" do
      {:ok, quoted} = Parser.parse("{|a\\|b| :string opt=|1|}")
      {:ok, unquoted} = Parser.parse("{1 :string opt=1}")
      [quoted_expression] = JSON.to_json(quoted)["pattern"]
      [unquoted_expression] = JSON.to_json(unquoted)["pattern"]

      assert quoted_expression["arg"] == %{"type" => "literal", "value" => "a|b"}
      assert quoted_expression["function"] == unquoted_expression["function"]
    end

    test "an AST that is not a message is an error, not a raise" do
      for ast <- [
            [{:bogus, 1}],
            [{:expression, nil, nil, []}],
            [{:expression, {:variable, 1}, nil, []}],
            [{:expression, {:variable, "x"}, {:function, :f, []}, []}],
            [{:markup_open, "b", [{:option, "a", :b}], []}],
            [{:complex, [:bogus], {:quoted_pattern, []}}],
            [{:match, [{:variable, "x"}], [:bogus]}],
            :x,
            nil
          ] do
        assert {:error, %Localize.InvalidValueError{}} = JSON.to_json(ast)
      end
    end
  end

  describe "round trips through the model" do
    test "every conformance message converts back to an equal model" do
      for {source, ast} <- parsed_sources() do
        json = JSON.to_json(ast)
        encoded = JSON.to_json(ast, encode: true)

        assert {:ok, from_json} = JSON.from_json(encoded), "refused: #{inspect(source)}"

        printed = Print.to_string(from_json)

        assert {:ok, reparsed} = Parser.parse(printed),
               "#{inspect(source)} printed as #{inspect(printed)}, which does not parse"

        assert JSON.to_json(reparsed) == json, "#{inspect(source)} changed in the round trip"
      end
    end

    test "a message formats the same after the round trip" do
      cases = [
        {"Hello, {$name}!", %{"name" => "Kip"}},
        {".input {$count :number}\n.match $count\none {{one item}}\n* {{{$count} items}}",
         %{"count" => 3}},
        {".input {$count :number}\n.match $count\n1 {{exactly one}}\n* {{{$count} items}}",
         %{"count" => 1}},
        {".local $x = {|01| :string}\n{{{$x} and {1.50 :number minimumFractionDigits=2}}}", %{}},
        {"{$n :number u:dir=ltr} and {|a\\|b|}", %{"n" => 12}}
      ]

      for {message, bindings} <- cases do
        {:ok, ast} = Parser.parse(message)
        {:ok, from_json} = ast |> JSON.to_json() |> JSON.from_json()
        round_tripped = Print.to_string(from_json)

        assert Localize.Message.format(round_tripped, bindings) ==
                 Localize.Message.format(message, bindings)
      end
    end
  end

  describe "from_json/1" do
    test "declarations, options and attributes may be left out" do
      json = %{
        "type" => "message",
        "pattern" => [
          %{
            "type" => "expression",
            "arg" => @variable,
            "function" => %{"type" => "function", "name" => "number"}
          },
          %{"type" => "markup", "kind" => "standalone", "name" => "br"}
        ]
      }

      assert JSON.from_json(json) ==
               {:ok,
                [
                  quoted_pattern: [
                    {:expression, {:variable, "x"}, {:function, "number", []}, []},
                    {:markup_standalone, "br", [], []}
                  ]
                ]}
    end

    test "fields the model does not define are ignored" do
      json = %{
        "type" => "message",
        "declarations" => [],
        "span" => [0, 5],
        "pattern" => [
          %{"type" => "expression", "arg" => Map.put(@variable, "span", 1), "comment" => "x"}
        ]
      }

      assert JSON.from_json(json) ==
               {:ok, [quoted_pattern: [{:expression, {:variable, "x"}, nil, []}]]}
    end

    test "a catch-all key may carry a value, which MF2 does not keep" do
      json = %{
        "type" => "select",
        "declarations" => [
          %{
            "type" => "input",
            "name" => "x",
            "value" => %{
              "type" => "expression",
              "arg" => @variable,
              "function" => %{"type" => "function", "name" => "number"}
            }
          }
        ],
        "selectors" => [@variable],
        "variants" => [%{"keys" => [%{"type" => "*", "value" => "other"}], "value" => ["x"]}]
      }

      assert {:ok, ast} = JSON.from_json(json)
      assert Print.to_string(ast) == ".input {$x :number}\n.match $x\n* {{x}}"
    end

    test "an empty string in a pattern is dropped" do
      json = %{"type" => "message", "pattern" => ["", "a", "", "b"]}
      assert JSON.from_json(json) == {:ok, [quoted_pattern: [text: "a", text: "b"]]}
    end

    test "options and attributes are taken in the order of their names" do
      json = %{
        "type" => "message",
        "pattern" => [
          %{
            "type" => "expression",
            "arg" => @variable,
            "function" => %{
              "type" => "function",
              "name" => "f",
              "options" => %{
                "b" => %{"type" => "literal", "value" => "2"},
                "a" => @variable,
                "u:dir" => %{"type" => "literal", "value" => "ltr"}
              }
            },
            "attributes" => %{"z" => true, "ns:y" => %{"type" => "literal", "value" => "v"}}
          }
        ]
      }

      assert {:ok, ast} = JSON.from_json(json)
      assert Print.to_string(ast) == "{{{$x :f a=$x b=2 u:dir=ltr @ns:y=v @z}}}"
    end

    test "a literal is a number literal only when it matches TR35's number-literal" do
      numbers = ["0", "1", "-1", "1.5", "-0.5", "1e5", "1E+5", "-1.5e-3", "10"]
      not_numbers = ["01", "+1", "1.", ".5", "1e", "0x10", " 1", "1_000", "", "-", "١"]

      for value <- numbers do
        assert {:ok, [quoted_pattern: [{:expression, {:number_literal, ^value}, nil, []}]]} =
                 JSON.from_json(literal_message(value))
      end

      for value <- not_numbers do
        assert {:ok, [quoted_pattern: [{:expression, {:literal, ^value}, nil, []}]]} =
                 JSON.from_json(literal_message(value))
      end
    end

    test "any literal value survives printing and parsing" do
      values = ["01", "+1", "1.", "", "a b", "|", "\\", "{", "}", "a:b", "٣", "\n", "$x", ":f"]

      for value <- values do
        json = literal_message(value)
        {:ok, ast} = JSON.from_json(json)
        assert {:ok, reparsed} = ast |> Print.to_string() |> Parser.parse()
        assert JSON.to_json(reparsed) == Map.put(json, "declarations", [])
      end
    end

    test "an input declaration must name the variable its value refers to" do
      declaration = fn arg ->
        %{
          "type" => "message",
          "declarations" => [
            %{
              "type" => "input",
              "name" => "a",
              "value" => %{"type" => "expression", "arg" => arg}
            }
          ],
          "pattern" => []
        }
      end

      assert {:ok, [{:complex, [input: {:expression, {:variable, "a"}, nil, []}], _body}]} =
               JSON.from_json(declaration.(%{"type" => "variable", "name" => "a"}))

      for arg <- [
            %{"type" => "variable", "name" => "b"},
            %{"type" => "literal", "value" => "a"}
          ] do
        assert {:error, %Localize.InvalidValueError{expected: expected}} =
                 JSON.from_json(declaration.(arg))

        assert expected =~ "input declaration"
      end
    end

    test "text that is not a name is refused wherever a name goes" do
      for text <- @not_names do
        models = [
          %{"type" => "expression", "arg" => %{"type" => "variable", "name" => text}},
          %{"type" => "expression", "function" => %{"type" => "function", "name" => text}},
          %{"type" => "markup", "kind" => "open", "name" => text},
          %{
            "type" => "expression",
            "function" => %{
              "type" => "function",
              "name" => "f",
              "options" => %{text => @variable}
            }
          },
          %{"type" => "expression", "arg" => @variable, "attributes" => %{text => true}}
        ]

        for model <- models do
          assert {:error, %Localize.InvalidValueError{}} =
                   JSON.from_json(%{"type" => "message", "pattern" => [model]}),
                 "accepted #{inspect(text)} in #{inspect(model)}"
        end

        local = %{
          "type" => "local",
          "name" => text,
          "value" => %{"type" => "expression", "arg" => @variable}
        }

        assert {:error, %Localize.InvalidValueError{}} =
                 JSON.from_json(%{
                   "type" => "message",
                   "declarations" => [local],
                   "pattern" => []
                 })
      end
    end

    test "a malformed model is an error, never a raise" do
      for model <- @malformed do
        assert {:error, %Localize.InvalidValueError{context: JSON}} = JSON.from_json(model),
               "accepted or mis-reported #{inspect(model)}"
      end
    end

    test "a malformed model given as JSON text is an error" do
      for model <- @malformed, is_map(model) do
        encoded =
          model
          |> :json.encode(&encode_nil/2)
          |> IO.iodata_to_binary()

        assert {:error, %Localize.InvalidValueError{}} = JSON.from_json(encoded)
      end

      assert {:error, %Localize.ParseError{}} = JSON.from_json("{not json")
      assert {:error, %Localize.InvalidValueError{}} = JSON.from_json("[1, 2]")
      assert {:error, %Localize.InvalidValueError{}} = JSON.from_json("null")
    end
  end

  describe "the parser's unquoted literal (TR35: unquoted-literal = 1*name-char)" do
    test "a run of name characters that is not a number is a literal" do
      for text <- ["01", "1.", ".5", "1e", "0x10", "-", "1x", "+1", "1.2.3", "00"] do
        assert Parser.parse("{" <> text <> "}") ==
                 {:ok, [{:expression, {:literal, text}, nil, []}]}
      end
    end

    test "a run that matches number-literal is a number literal" do
      for text <- ["0", "1", "-1", "1.5", "1e5", "1E+5", "-1.5e-3"] do
        assert Parser.parse("{" <> text <> "}") ==
                 {:ok, [{:expression, {:number_literal, text}, nil, []}]}
      end
    end

    test "as an option value and as a variant key" do
      assert {:ok,
              [{:expression, _, {:function, "number", [{:option, "o", {:literal, "01"}}]}, _}]} =
               Parser.parse("{$x :number o=01}")

      assert {:ok, [{:complex, _, {:match, _, [{:variant, [literal: "01"], _}, _]}}]} =
               Parser.parse(".input {$x :number}\n.match $x\n01 {{a}}\n* {{b}}")
    end
  end

  describe "printing and highlighting namespaced names" do
    test "the canonical message keeps namespaced options and attributes" do
      for message <- [
            "{$n :number u:dir=ltr @u:id=x @ns:flag}",
            "{#tag u:id=x @ns:a}c{/tag}"
          ] do
        assert Localize.Message.canonical_message(message) == {:ok, message}
      end
    end

    test "the highlighter's tokens spell the message" do
      message = "{$n :number u:dir=ltr @u:id=x @ns:flag}{#tag u:id=x @ns:a}c{/tag}"
      {:ok, ast} = Parser.parse(message)

      text =
        ast
        |> Highlighter.to_tokens()
        |> Enum.map_join(fn {_class, text} -> text end)

      assert text == message
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp parsed_sources do
    for source <- @sources, {:ok, ast} <- [Parser.parse(source)] do
      {source, ast}
    end
  end

  defp literal_message(value) do
    %{
      "type" => "message",
      "pattern" => [%{"type" => "expression", "arg" => %{"type" => "literal", "value" => value}}]
    }
  end

  defp encode_nil(nil, _encode) do
    "null"
  end

  defp encode_nil(other, encode) do
    :json.encode_value(other, encode)
  end

  # ── TR35's message.json, as predicates ──────────────────────────

  defp schema?(%{"type" => "message", "declarations" => declarations, "pattern" => pattern}) do
    is_list(declarations) and Enum.all?(declarations, &declaration?/1) and pattern?(pattern)
  end

  defp schema?(%{"type" => "select", "declarations" => declarations} = select) do
    %{"selectors" => selectors, "variants" => variants} = select

    is_list(declarations) and Enum.all?(declarations, &declaration?/1) and
      is_list(selectors) and Enum.all?(selectors, &variable?/1) and
      is_list(variants) and Enum.all?(variants, &variant?/1)
  end

  defp schema?(_other) do
    false
  end

  # The data model: an input declaration's name is its value's variable.
  defp declaration?(%{"type" => "input", "name" => name, "value" => value}) do
    is_binary(name) and expression?(value) and
      value["arg"] == %{"type" => "variable", "name" => name}
  end

  defp declaration?(%{"type" => "local", "name" => name, "value" => value}) do
    is_binary(name) and expression?(value)
  end

  defp declaration?(_other) do
    false
  end

  defp pattern?(pattern) do
    is_list(pattern) and Enum.all?(pattern, &pattern_part?/1)
  end

  # The data model: a string in a pattern is non-empty.
  defp pattern_part?(part) when is_binary(part) do
    part != ""
  end

  defp pattern_part?(%{"type" => "expression"} = expression) do
    expression?(expression)
  end

  defp pattern_part?(%{"type" => "markup", "kind" => kind, "name" => name} = markup) do
    kind in ["open", "standalone", "close"] and is_binary(name) and
      options?(Map.get(markup, "options", %{})) and
      attributes?(Map.get(markup, "attributes", %{}))
  end

  defp pattern_part?(_other) do
    false
  end

  defp expression?(%{"type" => "expression"} = expression) do
    (Map.has_key?(expression, "arg") or Map.has_key?(expression, "function")) and
      member?(expression, "arg", &literal_or_variable?/1) and
      member?(expression, "function", &function?/1) and
      attributes?(Map.get(expression, "attributes", %{}))
  end

  defp expression?(_other) do
    false
  end

  defp member?(map, key, check) do
    not Map.has_key?(map, key) or check.(Map.fetch!(map, key))
  end

  defp function?(%{"type" => "function", "name" => name} = function) do
    is_binary(name) and options?(Map.get(function, "options", %{}))
  end

  defp function?(_other) do
    false
  end

  defp options?(options) do
    is_map(options) and
      Enum.all?(options, fn {name, value} -> is_binary(name) and literal_or_variable?(value) end)
  end

  defp attributes?(attributes) do
    is_map(attributes) and
      Enum.all?(attributes, fn {name, value} ->
        is_binary(name) and (value == true or literal?(value))
      end)
  end

  defp literal_or_variable?(value) do
    literal?(value) or variable?(value)
  end

  defp literal?(%{"type" => "literal", "value" => value}) do
    is_binary(value)
  end

  defp literal?(_other) do
    false
  end

  defp variable?(%{"type" => "variable", "name" => name}) do
    is_binary(name)
  end

  defp variable?(_other) do
    false
  end

  defp variant?(%{"keys" => keys, "value" => value}) do
    is_list(keys) and Enum.all?(keys, &key?/1) and pattern?(value)
  end

  defp variant?(_other) do
    false
  end

  defp key?(%{"type" => "*"} = key) do
    member?(key, "value", &is_binary/1)
  end

  defp key?(other) do
    literal?(other)
  end
end
