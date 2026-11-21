defmodule Localize.Message.JSON do
  @moduledoc """
  Converts between MF2 ASTs and the interchange data model of
  [TR35 Part 9](https://www.unicode.org/reports/tr35/tr35-messageFormat.html#interchange-data-model),
  in its JSON form (the `message.json` schema).

  ### Purpose

  The data model is the logical form of a message, written as plain
  data rather than as MF2 syntax. TR35 defines it so that a message
  can be passed between implementations and tools without each of
  them parsing and printing the syntax: a translation tool can read
  and write messages, a linter can inspect them, and a message in
  another format, such as ICU MessageFormat 1, can be converted by
  building the model. It is not needed to format a message; for that
  see `Localize.Message`.

  ### Reference

  The format is not Localize's own. It is defined by:

  * [TR35 Part 9, Interchange Data Model](https://www.unicode.org/reports/tr35/tr35-messageFormat.html#interchange-data-model),
    the canonical definition, in TypeScript notation, with a section
    for each of the message, pattern, expression, markup and
    attribute models.

  * [`message.json`](https://github.com/unicode-org/message-format-wg/blob/main/spec/data-model/message.json),
    the MessageFormat working group's JSON Schema for the same model,
    which is the form this module reads and writes. It is also
    reproduced in TR35 under
    [`message.json`](https://www.unicode.org/reports/tr35/tr35-messageFormat.html#messagejson).

  A message is an object whose `"type"` is `"message"` (one pattern)
  or `"select"` (selectors and variants). A pattern is a list of
  strings, expressions and markup:

      iex> {:ok, ast} = Localize.Message.Parser.parse("Hello, {$name}!")
      iex> Localize.Message.JSON.to_json(ast)
      %{
        "type" => "message",
        "declarations" => [],
        "pattern" => [
          "Hello, ",
          %{"type" => "expression", "arg" => %{"type" => "variable", "name" => "name"}},
          "!"
        ]
      }

  ### Functions

  * `to_json/2` — serialize an MF2 AST to a JSON-compatible map
    or encoded string.

  * `from_json/1` — deserialize a JSON map or string back to an
    MF2 AST.

  ### What the model keeps

  The model keeps the meaning of a message, not its spelling: whether
  a literal was quoted, whether a message was written in its simple
  or its complex form, and the order of an expression's options and
  attributes are not kept. A message converted to the model and back
  formats as the original does.

  `from_json/1` checks the structure of what it is given: every
  object's `type`, every name, and that an `.input` declaration's
  value names the declared variable. Fields the model does not
  define are ignored, as TR35 requires, and `declarations`, `options`
  and `attributes` may be left out. It does not check for data model
  errors such as a duplicate declaration or a missing fallback
  variant; `Localize.Message.Validator.validate/1` does.

  """

  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  alias Localize.Message.Parser

  @markup_kinds %{
    "open" => :markup_open,
    "close" => :markup_close,
    "standalone" => :markup_standalone
  }

  # ── Serialization (AST → JSON) ─────────────────────────────────

  @doc """
  Converts a parsed MF2 AST to the JSON interchange data model.

  ### Arguments

  * `ast` is a parsed MF2 message AST as returned by
    `Localize.Message.Parser.parse/1`.

  * `options` is a keyword list of options.

  ### Options

  * `:encode` — when `true`, returns a JSON-encoded string
    instead of a map. The default is `false`.

  ### Returns

  * A map (or string when `:encode` is `true`) representing the
    message in the MF2 JSON data model, or

  * `{:error, exception}` if `ast` is not an MF2 message AST or
    `options` is not a keyword list.

  ### Examples

      iex> {:ok, ast} = Localize.Message.Parser.parse("{{Hello, world!}}")
      iex> Localize.Message.JSON.to_json(ast)
      %{"type" => "message", "declarations" => [], "pattern" => ["Hello, world!"]}

      iex> {:ok, ast} = Localize.Message.Parser.parse("{$n :number u:dir=ltr}")
      iex> Localize.Message.JSON.to_json(ast)["pattern"]
      [
        %{
          "type" => "expression",
          "arg" => %{"type" => "variable", "name" => "n"},
          "function" => %{
            "type" => "function",
            "name" => "number",
            "options" => %{"u:dir" => %{"type" => "literal", "value" => "ltr"}}
          }
        }
      ]

  """
  @spec to_json(list(), Keyword.t()) :: map() | String.t() | {:error, Exception.t()}
  def to_json(ast, options \\ [])

  def to_json(ast, options) when is_list(ast) and is_keyword_list(options) do
    ast
    |> convert_message()
    |> checked_model(ast, options)
  end

  def to_json(_ast, options) when not is_keyword_list(options) do
    {:error, Localize.Utils.Helpers.invalid_options(options)}
  end

  def to_json(ast, _options) do
    {:error, Localize.Utils.Helpers.invalid_value(ast, "an MF2 message AST")}
  end

  # A node the AST should not hold converts to `:invalid`, at the top
  # or anywhere inside the model.
  defp checked_model(%{} = model, ast, options) do
    if json_value?(model) do
      maybe_encode(model, options)
    else
      {:error, Localize.Utils.Helpers.invalid_value(ast, "an MF2 message AST")}
    end
  end

  defp checked_model(:invalid, ast, _options) do
    {:error, Localize.Utils.Helpers.invalid_value(ast, "an MF2 message AST")}
  end

  defp convert_message([{:complex, declarations, body}]) when is_list(declarations) do
    convert_complex(declarations, body)
  end

  defp convert_message([{:match, selectors, variants}]) do
    convert_select([], selectors, variants)
  end

  defp convert_message([{:quoted_pattern, parts}]) do
    convert_pattern_message([], parts)
  end

  defp convert_message(parts) do
    convert_pattern_message([], parts)
  end

  defp convert_complex(declarations, {:quoted_pattern, parts}) do
    convert_pattern_message(declarations, parts)
  end

  defp convert_complex(declarations, {:match, selectors, variants}) do
    convert_select(declarations, selectors, variants)
  end

  defp convert_complex(_declarations, _body) do
    :invalid
  end

  defp convert_pattern_message(declarations, parts) do
    %{
      "type" => "message",
      "declarations" => Enum.map(declarations, &convert_declaration/1),
      "pattern" => convert_pattern(parts)
    }
  end

  defp convert_select(declarations, selectors, variants)
       when is_list(selectors) and is_list(variants) do
    %{
      "type" => "select",
      "declarations" => Enum.map(declarations, &convert_declaration/1),
      "selectors" => Enum.map(selectors, &convert_operand/1),
      "variants" => Enum.map(variants, &convert_variant/1)
    }
  end

  defp convert_select(_declarations, _selectors, _variants) do
    :invalid
  end

  # ── Declarations ────────────────────────────────────────────────

  defp convert_declaration({:input, {:expression, {:variable, name}, function, attributes}}) do
    %{
      "type" => "input",
      "name" => name,
      "value" => convert_expression({:variable, name}, function, attributes)
    }
  end

  defp convert_declaration(
         {:local, {:variable, name}, {:expression, operand, function, attributes}}
       ) do
    %{
      "type" => "local",
      "name" => name,
      "value" => convert_expression(operand, function, attributes)
    }
  end

  defp convert_declaration(_declaration) do
    :invalid
  end

  # ── Pattern ─────────────────────────────────────────────────────

  # Text and escapes are joined into one string, and an empty string
  # is left out: an element of a pattern is a non-empty string.
  defp convert_pattern(parts) when is_list(parts) do
    parts
    |> Enum.map(&convert_pattern_part/1)
    |> coalesce_strings()
    |> Enum.reject(&(&1 == ""))
  end

  defp convert_pattern(_parts) do
    :invalid
  end

  defp convert_pattern_part({:text, text}) when is_binary(text) do
    text
  end

  defp convert_pattern_part({:escape, char}) when is_binary(char) do
    char
  end

  defp convert_pattern_part({:expression, operand, function, attributes}) do
    convert_expression(operand, function, attributes)
  end

  defp convert_pattern_part({:markup_open, name, options, attributes}) do
    convert_markup("open", name, options, attributes)
  end

  defp convert_pattern_part({:markup_close, name, options, attributes}) do
    convert_markup("close", name, options, attributes)
  end

  defp convert_pattern_part({:markup_standalone, name, options, attributes}) do
    convert_markup("standalone", name, options, attributes)
  end

  defp convert_pattern_part(_part) do
    :invalid
  end

  # ── Expressions ─────────────────────────────────────────────────

  defp convert_expression(nil, nil, _attributes) do
    :invalid
  end

  defp convert_expression(operand, function, attributes) do
    %{"type" => "expression"}
    |> put_present("arg", operand, &convert_operand/1)
    |> put_present("function", function, &convert_function/1)
    |> put_members("attributes", attributes, &convert_attribute/1)
  end

  defp convert_operand({:variable, name}) do
    %{"type" => "variable", "name" => name}
  end

  defp convert_operand({:literal, value}) do
    %{"type" => "literal", "value" => value}
  end

  defp convert_operand({:number_literal, value}) do
    %{"type" => "literal", "value" => value}
  end

  defp convert_operand(_operand) do
    :invalid
  end

  defp convert_function({:function, name, options}) do
    %{"type" => "function", "name" => convert_identifier(name)}
    |> put_members("options", options, &convert_option/1)
  end

  defp convert_function(_function) do
    :invalid
  end

  defp convert_option({:option, name, value}) do
    {convert_identifier(name), convert_operand(value)}
  end

  defp convert_option(_option) do
    {:invalid, :invalid}
  end

  defp convert_attribute({:attribute, name, nil}) do
    {convert_identifier(name), true}
  end

  defp convert_attribute({:attribute, name, {:variable, _name}}) do
    {convert_identifier(name), :invalid}
  end

  defp convert_attribute({:attribute, name, value}) do
    {convert_identifier(name), convert_operand(value)}
  end

  defp convert_attribute(_attribute) do
    {:invalid, :invalid}
  end

  defp convert_markup(kind, name, options, attributes) do
    %{"type" => "markup", "kind" => kind, "name" => convert_identifier(name)}
    |> put_members("options", options, &convert_option/1)
    |> put_members("attributes", attributes, &convert_attribute/1)
  end

  # ── Variants ────────────────────────────────────────────────────

  defp convert_variant({:variant, keys, {:quoted_pattern, parts}}) when is_list(keys) do
    %{
      "keys" => Enum.map(keys, &convert_key/1),
      "value" => convert_pattern(parts)
    }
  end

  defp convert_variant(_variant) do
    :invalid
  end

  defp convert_key(:catchall) do
    %{"type" => "*"}
  end

  defp convert_key({:literal, value}) do
    %{"type" => "literal", "value" => value}
  end

  defp convert_key({:number_literal, value}) do
    %{"type" => "literal", "value" => value}
  end

  defp convert_key(_key) do
    :invalid
  end

  # ── Identifiers ─────────────────────────────────────────────────

  # An option, attribute, function or markup name may be namespaced
  # (`u:dir`). The model's `name` is the whole identifier.
  defp convert_identifier({:namespace, namespace, name})
       when is_binary(namespace) and is_binary(name) do
    namespace <> ":" <> name
  end

  defp convert_identifier(name) when is_binary(name) do
    name
  end

  defp convert_identifier(_name) do
    :invalid
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp put_present(map, _key, nil, _convert) do
    map
  end

  defp put_present(map, key, value, convert) do
    Map.put(map, key, convert.(value))
  end

  # Options and attributes are left out when there are none, as the
  # JSON schema allows.
  defp put_members(map, _key, [], _convert) do
    map
  end

  defp put_members(map, key, members, convert) when is_list(members) do
    Map.put(map, key, Map.new(members, convert))
  end

  defp put_members(map, key, _members, _convert) do
    Map.put(map, key, :invalid)
  end

  defp coalesce_strings(parts) do
    parts
    |> Enum.chunk_by(&is_binary/1)
    |> Enum.flat_map(&join_strings/1)
  end

  defp join_strings([first | _rest] = strings) when is_binary(first) do
    [Enum.join(strings)]
  end

  defp join_strings(other) do
    other
  end

  # What a conversion of a well-formed AST produces: strings, `true`,
  # lists, and maps with string keys. Anything else marks a node the
  # AST should not hold.
  defp json_value?(value) when is_binary(value) or value == true do
    true
  end

  defp json_value?(value) when is_list(value) do
    Enum.all?(value, &json_value?/1)
  end

  defp json_value?(value) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, member} -> is_binary(key) and json_value?(member) end)
  end

  defp json_value?(_value) do
    false
  end

  defp maybe_encode(result, options) do
    if Keyword.get(options, :encode, false) do
      result
      |> :json.encode()
      |> IO.iodata_to_binary()
    else
      result
    end
  end

  # ── Deserialization (JSON → AST) ────────────────────────────────

  @doc """
  Converts a JSON interchange data model map (or JSON string) back
  to an MF2 AST.

  ### Arguments

  * `json` is a map conforming to the MF2 JSON data model, or a
    JSON-encoded string.

  ### Returns

  * `{:ok, ast}` where `ast` is the MF2 message AST, or

  * `{:error, exception}` if `json` is not JSON, or is not a
    message of the data model. The exception's `:value` is the
    part that was refused.

  ### Examples

      iex> json = %{"type" => "message", "declarations" => [], "pattern" => ["Hello!"]}
      iex> Localize.Message.JSON.from_json(json)
      {:ok, [quoted_pattern: [text: "Hello!"]]}

      iex> json = %{"type" => "message", "pattern" => [%{"type" => "expression"}]}
      iex> {:error, exception} = Localize.Message.JSON.from_json(json)
      iex> exception.expected
      "an expression with an arg or a function"

  """
  @spec from_json(map() | String.t()) :: {:ok, list()} | {:error, Exception.t()}
  def from_json(json) when is_binary(json) do
    case Localize.Utils.Helpers.run_isolated(fn -> :json.decode(json) end) do
      {:ok, map} when is_map(map) -> from_json(map)
      {:ok, other} -> invalid(other, "a JSON object")
      {:error, exception} -> {:error, not_json(json, exception)}
    end
  end

  def from_json(%{"type" => "message", "pattern" => pattern} = message) do
    with {:ok, declarations} <- declarations(Map.get(message, "declarations", [])),
         {:ok, parts} <- pattern(pattern) do
      {:ok, message_ast(declarations, {:quoted_pattern, parts})}
    end
  end

  def from_json(%{"type" => "select", "selectors" => selectors, "variants" => variants} = message) do
    with {:ok, declarations} <- declarations(Map.get(message, "declarations", [])),
         {:ok, selectors} <- selectors(selectors),
         {:ok, variants} <- variants(variants) do
      {:ok, message_ast(declarations, {:match, selectors, variants})}
    end
  end

  def from_json(json) do
    invalid(json, "a message or select object with a type field")
  end

  defp message_ast([], body) do
    [body]
  end

  defp message_ast(declarations, body) do
    [{:complex, declarations, body}]
  end

  # `:json.decode/1` raises on text that is not JSON, so it runs in a
  # process of its own.
  defp not_json(json, exception) do
    Localize.ParseError.exception(
      input: json,
      reason: :invalid_message_format,
      detail: "it is not JSON",
      cause: exception
    )
  end

  defp invalid(value, expected) do
    {:error,
     Localize.InvalidValueError.exception(
       value: value,
       expected: expected,
       context: __MODULE__
     )}
  end

  # ── Parse declarations ──────────────────────────────────────────

  defp declarations(declarations) when is_list(declarations) do
    map_ok(declarations, &declaration/1)
  end

  defp declarations(other) do
    invalid(other, "a list of declarations")
  end

  # The name of an input declaration MUST be the name of the variable
  # its value refers to.
  defp declaration(%{"type" => "input", "name" => name, "value" => value} = declaration) do
    with {:ok, name} <- name(name),
         {:ok, expression} <- expression(value) do
      input_declaration(declaration, name, expression)
    end
  end

  defp declaration(%{"type" => "local", "name" => name, "value" => value}) do
    with {:ok, name} <- name(name),
         {:ok, expression} <- expression(value) do
      {:ok, {:local, {:variable, name}, expression}}
    end
  end

  defp declaration(other) do
    invalid(other, "an input or local declaration with a name and a value")
  end

  defp input_declaration(_declaration, name, {:expression, {:variable, name}, _, _} = expression) do
    {:ok, {:input, expression}}
  end

  defp input_declaration(declaration, _name, _expression) do
    invalid(declaration, "an input declaration whose value's arg is the variable it names")
  end

  # ── Parse pattern ───────────────────────────────────────────────

  # An empty string is not an element of a pattern; one that arrives
  # is dropped, since it changes nothing.
  defp pattern(parts) when is_list(parts) do
    parts
    |> Enum.reject(&(&1 == ""))
    |> map_ok(&pattern_part/1)
  end

  defp pattern(other) do
    invalid(other, "a pattern, as a list")
  end

  defp pattern_part(text) when is_binary(text) do
    if String.valid?(text) do
      {:ok, {:text, text}}
    else
      invalid(text, "text as a UTF-8 string")
    end
  end

  defp pattern_part(%{"type" => "expression"} = expression) do
    expression(expression)
  end

  defp pattern_part(%{"type" => "markup"} = markup) do
    markup(markup)
  end

  defp pattern_part(other) do
    invalid(other, "a string, an expression or a markup object")
  end

  # ── Parse expressions ───────────────────────────────────────────

  defp expression(%{"type" => "expression"} = expression) do
    with {:ok, operand} <- optional(expression, "arg", &literal_or_variable/1),
         {:ok, function} <- optional(expression, "function", &function/1),
         {:ok, attributes} <- attributes(Map.get(expression, "attributes", %{})) do
      expression_node(expression, operand, function, attributes)
    end
  end

  defp expression(other) do
    invalid(other, "an expression")
  end

  defp expression_node(expression, nil, nil, _attributes) do
    invalid(expression, "an expression with an arg or a function")
  end

  defp expression_node(_expression, operand, function, attributes) do
    {:ok, {:expression, operand, function, attributes}}
  end

  defp optional(map, key, convert) do
    case Map.fetch(map, key) do
      {:ok, value} -> convert.(value)
      :error -> {:ok, nil}
    end
  end

  defp literal_or_variable(%{"type" => "variable"} = variable) do
    variable(variable)
  end

  defp literal_or_variable(other) do
    literal(other)
  end

  defp variable(%{"type" => "variable", "name" => name}) do
    with {:ok, name} <- name(name) do
      {:ok, {:variable, name}}
    end
  end

  defp variable(other) do
    invalid(other, "a variable with a name")
  end

  # The model does not keep whether a literal was quoted. One that
  # matches TR35's `number-literal` production is a number literal, as
  # it is when parsed from the syntax.
  defp literal(%{"type" => "literal", "value" => value} = literal) when is_binary(value) do
    cond do
      not String.valid?(value) -> invalid(literal, "a literal whose value is a UTF-8 string")
      Parser.Helpers.number_literal?(value) -> {:ok, {:number_literal, value}}
      true -> {:ok, {:literal, value}}
    end
  end

  defp literal(other) do
    invalid(other, "a literal with a string value")
  end

  defp function(%{"type" => "function", "name" => name} = function) do
    with {:ok, identifier} <- identifier(name),
         {:ok, options} <- options(Map.get(function, "options", %{})) do
      {:ok, {:function, identifier, options}}
    end
  end

  defp function(other) do
    invalid(other, "a function with a name")
  end

  # A JSON object has no order, so options and attributes are taken in
  # the order of their names.
  defp options(options) when is_map(options) and not is_struct(options) do
    options
    |> Enum.sort()
    |> map_ok(&option/1)
  end

  defp options(other) do
    invalid(other, "options, as an object")
  end

  defp option({name, value}) do
    with {:ok, identifier} <- identifier(name),
         {:ok, value} <- literal_or_variable(value) do
      {:ok, {:option, identifier, value}}
    end
  end

  defp attributes(attributes) when is_map(attributes) and not is_struct(attributes) do
    attributes
    |> Enum.sort()
    |> map_ok(&attribute/1)
  end

  defp attributes(other) do
    invalid(other, "attributes, as an object")
  end

  defp attribute({name, true}) do
    with {:ok, identifier} <- identifier(name) do
      {:ok, {:attribute, identifier, nil}}
    end
  end

  defp attribute({name, value}) do
    with {:ok, identifier} <- identifier(name),
         {:ok, value} <- literal(value) do
      {:ok, {:attribute, identifier, value}}
    end
  end

  # ── Parse markup ────────────────────────────────────────────────

  defp markup(%{"type" => "markup", "kind" => kind, "name" => name} = markup) do
    with {:ok, tag} <- markup_kind(markup, kind),
         {:ok, identifier} <- identifier(name),
         {:ok, options} <- options(Map.get(markup, "options", %{})),
         {:ok, attributes} <- attributes(Map.get(markup, "attributes", %{})) do
      {:ok, {tag, identifier, options, attributes}}
    end
  end

  defp markup(other) do
    invalid(other, "a markup object with a kind and a name")
  end

  defp markup_kind(markup, kind) do
    case Map.fetch(@markup_kinds, kind) do
      {:ok, tag} -> {:ok, tag}
      :error -> invalid(markup, "markup whose kind is open, standalone or close")
    end
  end

  # ── Parse selectors and variants ────────────────────────────────

  defp selectors([_ | _] = selectors) do
    map_ok(selectors, &variable/1)
  end

  defp selectors(other) do
    invalid(other, "a list of one or more selectors")
  end

  defp variants([_ | _] = variants) do
    map_ok(variants, &variant/1)
  end

  defp variants(other) do
    invalid(other, "a list of one or more variants")
  end

  defp variant(%{"keys" => [_ | _] = keys, "value" => pattern}) do
    with {:ok, keys} <- map_ok(keys, &key/1),
         {:ok, parts} <- pattern(pattern) do
      {:ok, {:variant, keys, {:quoted_pattern, parts}}}
    end
  end

  defp variant(other) do
    invalid(other, "a variant with one or more keys and a value")
  end

  # A catch-all key may carry the identifier another format gave it.
  # In MF2 it is always `*`, so the value is not kept.
  defp key(%{"type" => "*"}) do
    {:ok, :catchall}
  end

  defp key(other) do
    literal(other)
  end

  # ── Names ───────────────────────────────────────────────────────

  # A name is checked by the parser itself, as the variable of a
  # placeholder that holds nothing else, so no text that is not a
  # `name` can reach a message printed from the AST.
  defp name(name) when is_binary(name) do
    case parse_placeholder("$", name) do
      {:ok, [{:expression, {:variable, parsed}, nil, []}]} -> {:ok, parsed}
      _other -> invalid(name, "an MF2 name")
    end
  end

  defp name(other) do
    invalid(other, "an MF2 name")
  end

  # An `identifier` is a name with an optional namespace, checked as
  # the function of a placeholder that holds nothing else.
  defp identifier(identifier) when is_binary(identifier) do
    case parse_placeholder(":", identifier) do
      {:ok, [{:expression, nil, {:function, parsed, []}, []}]} -> {:ok, parsed}
      _other -> invalid(identifier, "an MF2 identifier")
    end
  end

  defp identifier(other) do
    invalid(other, "an MF2 identifier")
  end

  defp parse_placeholder(sigil, name) do
    if String.valid?(name) and String.trim(name) == name do
      Parser.parse("{" <> sigil <> name <> "}")
    else
      :error
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp map_ok(items, convert) do
    map_ok(items, convert, [])
  end

  defp map_ok([], _convert, converted) do
    {:ok, Enum.reverse(converted)}
  end

  defp map_ok([item | rest], convert, converted) do
    case convert.(item) do
      {:ok, value} -> map_ok(rest, convert, [value | converted])
      {:error, _exception} = error -> error
    end
  end
end
