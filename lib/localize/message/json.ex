defmodule Localize.Message.JSON do
  @moduledoc """
  Converts between MF2 ASTs and the JSON interchange data model
  defined in [TR35 §8](https://www.unicode.org/reports/tr35/tr35-messageFormat.html).

  The JSON data model enables portable serialization of MF2
  messages for tooling interoperability. Two functions are
  provided:

  * `to_json/2` — serialize an MF2 AST to a JSON-compatible map
    or encoded string.

  * `from_json/1` — deserialize a JSON map or string back to an
    MF2 AST.

  """

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
    message in the MF2 JSON data model.

  ### Examples

      iex> {:ok, ast} = Localize.Message.Parser.parse("{{Hello, world!}}")
      iex> Localize.Message.JSON.to_json(ast)
      %{"type" => "message", "declarations" => [], "pattern" => ["Hello, world!"]}

  """
  @spec to_json(list(), Keyword.t()) :: map() | String.t()
  def to_json(ast, options \\ [])

  def to_json([{:complex, declarations, body}], options) do
    result = convert_complex(declarations, body)
    maybe_encode(result, options)
  end

  def to_json([{:match, selectors, variants}], options) do
    result = convert_select([], selectors, variants)
    maybe_encode(result, options)
  end

  def to_json([{:quoted_pattern, parts}], options) do
    result = %{
      "type" => "message",
      "declarations" => [],
      "pattern" => convert_pattern(parts)
    }

    maybe_encode(result, options)
  end

  def to_json(parts, options) when is_list(parts) do
    result = %{
      "type" => "message",
      "declarations" => [],
      "pattern" => convert_pattern(parts)
    }

    maybe_encode(result, options)
  end

  defp convert_complex(declarations, {:quoted_pattern, parts}) do
    %{
      "type" => "message",
      "declarations" => Enum.map(declarations, &convert_declaration/1),
      "pattern" => convert_pattern(parts)
    }
  end

  defp convert_complex(declarations, {:match, selectors, variants}) do
    convert_select(declarations, selectors, variants)
  end

  defp convert_select(declarations, selectors, variants) do
    %{
      "type" => "select",
      "declarations" => Enum.map(declarations, &convert_declaration/1),
      "selectors" => Enum.map(selectors, &convert_operand/1),
      "variants" => Enum.map(variants, &convert_variant/1)
    }
  end

  # ── Declarations ────────────────────────────────────────────────

  defp convert_declaration({:input, {:expression, {:variable, name}, func, attrs}}) do
    %{
      "type" => "input",
      "name" => name,
      "value" => convert_expression_body({:variable, name}, func, attrs)
    }
  end

  defp convert_declaration({:local, {:variable, name}, {:expression, operand, func, attrs}}) do
    %{
      "type" => "local",
      "name" => name,
      "value" => convert_expression_body(operand, func, attrs)
    }
  end

  # ── Pattern ─────────────────────────────────────────────────────

  defp convert_pattern(parts) do
    parts
    |> Enum.map(&convert_pattern_part/1)
    |> coalesce_strings()
  end

  defp convert_pattern_part({:text, text}), do: text
  defp convert_pattern_part({:escape, char}), do: char

  defp convert_pattern_part({:expression, operand, func, attrs}) do
    convert_expression_body(operand, func, attrs)
  end

  defp convert_pattern_part({:markup_open, name, opts, attrs}) do
    convert_markup("open", name, opts, attrs)
  end

  defp convert_pattern_part({:markup_close, name, opts, attrs}) do
    convert_markup("close", name, opts, attrs)
  end

  defp convert_pattern_part({:markup_standalone, name, opts, attrs}) do
    convert_markup("standalone", name, opts, attrs)
  end

  # ── Expressions ─────────────────────────────────────────────────

  defp convert_expression_body(operand, func, attrs) do
    map = %{"type" => "expression"}

    map =
      case operand do
        nil -> map
        op -> Map.put(map, "arg", convert_operand(op))
      end

    map =
      case func do
        nil -> map
        f -> Map.put(map, "function", convert_function(f))
      end

    case attrs do
      [] -> map
      _ -> Map.put(map, "attributes", convert_attributes(attrs))
    end
  end

  defp convert_operand({:variable, name}), do: %{"type" => "variable", "name" => name}
  defp convert_operand({:literal, value}), do: %{"type" => "literal", "value" => value}
  defp convert_operand({:number_literal, value}), do: %{"type" => "literal", "value" => value}

  defp convert_function({:function, name, opts}) do
    map = %{"type" => "function", "name" => convert_identifier(name)}

    case opts do
      [] -> map
      _ -> Map.put(map, "options", convert_options(opts))
    end
  end

  defp convert_options(opts) do
    Map.new(opts, fn {:option, name, value} ->
      {name, convert_operand(value)}
    end)
  end

  defp convert_attributes(attrs) do
    Map.new(attrs, fn
      {:attribute, name, nil} -> {name, true}
      {:attribute, name, value} -> {name, convert_operand(value)}
    end)
  end

  defp convert_markup(kind, name, opts, attrs) do
    map = %{"type" => "markup", "kind" => kind, "name" => convert_identifier(name)}

    map =
      case opts do
        [] -> map
        _ -> Map.put(map, "options", convert_options(opts))
      end

    case attrs do
      [] -> map
      _ -> Map.put(map, "attributes", convert_attributes(attrs))
    end
  end

  # ── Variants ────────────────────────────────────────────────────

  defp convert_variant({:variant, keys, {:quoted_pattern, parts}}) do
    %{
      "keys" => Enum.map(keys, &convert_key/1),
      "value" => convert_pattern(parts)
    }
  end

  defp convert_key(:catchall), do: %{"type" => "*"}
  defp convert_key({:literal, value}), do: %{"type" => "literal", "value" => value}
  defp convert_key({:number_literal, value}), do: %{"type" => "literal", "value" => value}

  # ── Identifiers ─────────────────────────────────────────────────

  defp convert_identifier({:namespace, ns, name}), do: "#{ns}:#{name}"
  defp convert_identifier(name) when is_binary(name), do: name

  # ── Helpers ─────────────────────────────────────────────────────

  defp coalesce_strings(parts) do
    parts
    |> Enum.chunk_by(&is_binary/1)
    |> Enum.flat_map(fn
      [s | _] = strings when is_binary(s) -> [Enum.join(strings)]
      other -> other
    end)
  end

  defp maybe_encode(result, options) do
    if Keyword.get(options, :encode, false) do
      :json.encode(result) |> IO.iodata_to_binary()
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

  * `{:ok, ast}` where `ast` is the MF2 message AST.

  * `{:error, reason}` if the JSON structure is invalid.

  ### Examples

      iex> json = %{"type" => "message", "declarations" => [], "pattern" => ["Hello!"]}
      iex> Localize.Message.JSON.from_json(json)
      {:ok, [quoted_pattern: [text: "Hello!"]]}

  """
  @spec from_json(map() | String.t()) :: {:ok, list()} | {:error, String.t()}
  def from_json(json) when is_binary(json) do
    case :json.decode(json) do
      map when is_map(map) -> from_json(map)
      _ -> {:error, "expected a JSON object"}
    end
  rescue
    _ -> {:error, "invalid JSON"}
  end

  def from_json(%{"type" => "message", "declarations" => decls, "pattern" => pattern}) do
    declarations = Enum.map(decls, &parse_declaration/1)
    parts = parse_pattern(pattern)

    ast =
      case declarations do
        [] -> [{:quoted_pattern, parts}]
        _ -> [{:complex, declarations, {:quoted_pattern, parts}}]
      end

    {:ok, ast}
  end

  def from_json(%{
        "type" => "select",
        "declarations" => decls,
        "selectors" => sels,
        "variants" => vars
      }) do
    declarations = Enum.map(decls, &parse_declaration/1)
    selectors = Enum.map(sels, &parse_selector/1)
    variants = Enum.map(vars, &parse_variant/1)

    ast =
      case declarations do
        [] -> [{:match, selectors, variants}]
        _ -> [{:complex, declarations, {:match, selectors, variants}}]
      end

    {:ok, ast}
  end

  def from_json(_), do: {:error, "expected a message or select object with type field"}

  # ── Parse declarations ──────────────────────────────────────────

  defp parse_declaration(%{"type" => "input", "name" => name, "value" => expr}) do
    {:expression, _operand, func, attrs} = parse_expression(expr)
    {:input, {:expression, {:variable, name}, func, attrs}}
  end

  defp parse_declaration(%{"type" => "local", "name" => name, "value" => expr}) do
    {:local, {:variable, name}, parse_expression(expr)}
  end

  # ── Parse pattern ───────────────────────────────────────────────

  defp parse_pattern(parts) when is_list(parts) do
    Enum.map(parts, &parse_pattern_part/1)
  end

  defp parse_pattern_part(text) when is_binary(text), do: {:text, text}

  defp parse_pattern_part(%{"type" => "expression"} = expr) do
    parse_expression(expr)
  end

  defp parse_pattern_part(%{"type" => "markup"} = markup) do
    parse_markup(markup)
  end

  # ── Parse expressions ───────────────────────────────────────────

  defp parse_expression(%{"type" => "expression"} = expr) do
    operand = parse_arg(Map.get(expr, "arg"))
    func = parse_func(Map.get(expr, "function"))
    attrs = parse_attrs(Map.get(expr, "attributes"))
    {:expression, operand, func, attrs}
  end

  defp parse_arg(nil), do: nil
  defp parse_arg(%{"type" => "variable", "name" => name}), do: {:variable, name}

  defp parse_arg(%{"type" => "literal", "value" => value}) do
    if numeric_literal?(value), do: {:number_literal, value}, else: {:literal, value}
  end

  defp parse_func(nil), do: nil

  defp parse_func(%{"type" => "function", "name" => name} = func) do
    opts = parse_options(Map.get(func, "options"))
    {:function, parse_identifier(name), opts}
  end

  defp parse_options(nil), do: []

  defp parse_options(opts) when is_map(opts) do
    Enum.map(opts, fn {name, value} ->
      {:option, name, parse_operand_value(value)}
    end)
  end

  defp parse_operand_value(%{"type" => "variable", "name" => name}), do: {:variable, name}

  defp parse_operand_value(%{"type" => "literal", "value" => value}) do
    if numeric_literal?(value), do: {:number_literal, value}, else: {:literal, value}
  end

  defp parse_attrs(nil), do: []

  defp parse_attrs(attrs) when is_map(attrs) do
    Enum.map(attrs, fn
      {name, true} -> {:attribute, name, nil}
      {name, value} -> {:attribute, name, parse_operand_value(value)}
    end)
  end

  # ── Parse markup ────────────────────────────────────────────────

  defp parse_markup(%{"type" => "markup", "kind" => kind, "name" => name} = markup) do
    opts = parse_options(Map.get(markup, "options"))
    attrs = parse_attrs(Map.get(markup, "attributes"))
    tag = parse_identifier(name)

    case kind do
      "open" -> {:markup_open, tag, opts, attrs}
      "close" -> {:markup_close, tag, opts, attrs}
      "standalone" -> {:markup_standalone, tag, opts, attrs}
    end
  end

  # ── Parse selectors and variants ────────────────────────────────

  defp parse_selector(%{"type" => "variable", "name" => name}), do: {:variable, name}

  defp parse_variant(%{"keys" => keys, "value" => pattern}) do
    parsed_keys = Enum.map(keys, &parse_key/1)
    parts = parse_pattern(pattern)
    {:variant, parsed_keys, {:quoted_pattern, parts}}
  end

  defp parse_key(%{"type" => "*"}), do: :catchall

  defp parse_key(%{"type" => "literal", "value" => value}) do
    if numeric_literal?(value), do: {:number_literal, value}, else: {:literal, value}
  end

  # ── Identifiers ─────────────────────────────────────────────────

  defp parse_identifier(name) when is_binary(name) do
    case String.split(name, ":", parts: 2) do
      [ns, local] -> {:namespace, ns, local}
      [simple] -> simple
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp numeric_literal?(value) when is_binary(value) do
    case Float.parse(value) do
      {_, ""} -> true
      _ -> false
    end
  end

  defp numeric_literal?(_), do: false
end
