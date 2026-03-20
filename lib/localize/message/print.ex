defmodule Localize.Message.Print do
  @moduledoc """
  Converts a MessageFormat 2 AST back to its canonical string form.

  Used by `Localize.Message.canonical_message/2`.

  """
  import Kernel, except: [to_string: 1]

  @doc """
  Converts a parsed MF2 AST back to a canonical message string.

  ### Arguments

  * `ast` is a parsed MF2 message AST as returned by
    `Localize.Message.Parser.parse/1`.

  * `options` is a keyword list of options (currently unused
    but reserved for future use).

  ### Returns

  * A canonical message string.

  """
  @spec to_string(list() | tuple(), Keyword.t()) :: String.t()

  def to_string(ast, options \\ [])

  def to_string(ast, options) when is_list(options) do
    ast
    |> to_iolist(Map.new(options))
    |> :erlang.iolist_to_binary()
  end

  # ── Top-level ───────────────────────────────────────────────────

  defp to_iolist(parts, options) when is_list(parts) do
    Enum.map(parts, &to_iolist(&1, options))
  end

  defp to_iolist({:complex, declarations, body}, options) do
    decls = Enum.map(declarations, &to_iolist(&1, options))
    body_io = to_iolist(body, options)
    [decls, body_io]
  end

  defp to_iolist({:quoted_pattern, parts}, options) do
    ["{{", Enum.map(parts, &to_iolist(&1, options)), "}}"]
  end

  defp to_iolist({:match, selectors, variants}, options) do
    sel_io = Enum.map(selectors, fn {:variable, name} -> [" $", name] end)
    var_io = Enum.map(variants, &to_iolist(&1, options))
    [".match", sel_io, "\n", Enum.intersperse(var_io, "\n")]
  end

  defp to_iolist({:variant, keys, pattern}, options) do
    keys_io =
      Enum.map(keys, fn
        :catchall -> "*"
        key -> key_to_iolist(key)
      end)
      |> Enum.intersperse(" ")

    [keys_io, " ", to_iolist(pattern, options)]
  end

  # ── Declarations ────────────────────────────────────────────────

  defp to_iolist({:input, expr}, options) do
    [".input ", expression_to_iolist(expr, options), "\n"]
  end

  defp to_iolist({:local, {:variable, name}, expr}, options) do
    [".local $", name, " = ", expression_to_iolist(expr, options), "\n"]
  end

  # ── Pattern parts ───────────────────────────────────────────────

  defp to_iolist({:text, text}, _options) do
    escape_text(text)
  end

  defp to_iolist({:escape, char}, _options) do
    ["\\", char]
  end

  defp to_iolist({:expression, _, _, _} = expr, options) do
    expression_to_iolist(expr, options)
  end

  defp to_iolist({:markup_open, name, options, attrs}, _options) do
    ["{#", identifier_to_iolist(name), options_to_iolist(options), attrs_to_iolist(attrs), "}"]
  end

  defp to_iolist({:markup_close, name, options, attrs}, _options) do
    ["{/", identifier_to_iolist(name), options_to_iolist(options), attrs_to_iolist(attrs), "}"]
  end

  defp to_iolist({:markup_standalone, name, options, attrs}, _options) do
    ["{#", identifier_to_iolist(name), options_to_iolist(options), attrs_to_iolist(attrs), " /}"]
  end

  # ── Expressions ─────────────────────────────────────────────────

  defp expression_to_iolist({:expression, operand, func, attrs}, _options) do
    parts = [
      operand_to_iolist(operand),
      func_to_iolist(func),
      attrs_to_iolist(attrs)
    ]

    ["{", Enum.reject(parts, &(&1 == [])), "}"]
  end

  defp operand_to_iolist(nil), do: []
  defp operand_to_iolist({:variable, name}), do: ["$", name]
  defp operand_to_iolist({:literal, value}), do: ["|", escape_quoted(value), "|"]
  defp operand_to_iolist({:number_literal, value}), do: [value]

  defp func_to_iolist(nil), do: []

  defp func_to_iolist({:function, name, options}) do
    [" :", identifier_to_iolist(name), options_to_iolist(options)]
  end

  defp options_to_iolist([]), do: []

  defp options_to_iolist(options) do
    Enum.map(options, fn {:option, name, value} ->
      [" ", name, "=", value_to_iolist(value)]
    end)
  end

  defp attrs_to_iolist([]), do: []

  defp attrs_to_iolist(attrs) do
    Enum.map(attrs, fn
      {:attribute, name, nil} -> [" @", name]
      {:attribute, name, value} -> [" @", name, "=", value_to_iolist(value)]
    end)
  end

  defp value_to_iolist({:variable, name}), do: ["$", name]
  defp value_to_iolist({:literal, value}), do: literal_to_iolist(value)
  defp value_to_iolist({:number_literal, value}), do: [value]

  defp key_to_iolist({:literal, value}), do: literal_to_iolist(value)
  defp key_to_iolist({:number_literal, value}), do: [value]

  # Emit unquoted form when the value is a valid unquoted-literal
  # (1*name-char per the MF2 ABNF), otherwise quote with |...|.
  defp literal_to_iolist(""), do: ["||"]

  defp literal_to_iolist(value) do
    if unquoted_literal?(value) do
      [value]
    else
      ["|", escape_quoted(value), "|"]
    end
  end

  defp unquoted_literal?(value) do
    value
    |> String.to_charlist()
    |> Enum.all?(&name_char?/1)
  end

  defp name_char?(c) when c in ?0..?9, do: true
  defp name_char?(c) when c == ?- or c == ?., do: true
  defp name_char?(c), do: name_start?(c)

  defp name_start?(c) when c in ?a..?z or c in ?A..?Z, do: true
  defp name_start?(c) when c == ?_ or c == ?+, do: true
  defp name_start?(c) when c in 0xA1..0x61B, do: true
  defp name_start?(c) when c in 0x61D..0xD7FF, do: true
  defp name_start?(c) when c in 0xE000..0xFFFD, do: true
  defp name_start?(c) when c in 0x10000..0x10FFFF, do: true
  defp name_start?(_), do: false

  defp identifier_to_iolist({:namespace, ns, name}), do: [ns, ":", name]
  defp identifier_to_iolist(name) when is_binary(name), do: [name]

  # ── Escaping ────────────────────────────────────────────────────

  defp escape_text(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("{", "\\{")
    |> String.replace("}", "\\}")
  end

  defp escape_quoted(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("|", "\\|")
  end
end
