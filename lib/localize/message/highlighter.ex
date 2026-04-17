defmodule Localize.Message.Highlighter do
  @moduledoc """
  Produces a classified token stream from an MF2 AST for syntax
  highlighting.

  The output is a flat list of `{class :: atom, text :: String.t()}`
  tuples. Each tuple represents one syntactic region of the canonical
  message — punctuation, a variable reference, a function name, a
  literal, plain text, etc. Formatters (`Localize.Message.Formatter.HTML`,
  `Localize.Message.Formatter.ANSI`, `Localize.Message.Formatter.Plain`)
  consume the token stream and produce rendered output.

  Concatenating every token's text field yields the canonical MF2
  message (the same output as `Localize.Message.Print.to_string/1`) —
  the `Plain` formatter does exactly that. This property is verified
  by the test suite.

  ### Token classes

  Classes follow a Pygments-inspired taxonomy. The formatters map
  classes to CSS classes / ANSI colours.

  * `:punctuation` — `{`, `}`, `{{`, `}}`, `:`, `=`, `/`, `*`,
    whitespace inside expressions and similar structural characters.

  * `:name_variable` — `$name` (entire token including `$`).

  * `:name_function` — `:number`, `:date`, custom function names
    (entire token including `:`).

  * `:name_builtin` — `.input`, `.local`, `.match` keywords.

  * `:name_tag` — markup tag names (`bold` in `{#bold}`).

  * `:name_attribute` — attribute names (`@translate`).

  * `:name_label` — option names (`style` in `style=|short|`).

  * `:string` — quoted literal content including the `|` delimiters.

  * `:number_integer` / `:number_float` — numeric literals.

  * `:text` — pattern text (plain message content).

  * `:escape` — `\\{`, `\\|`, `\\\\` escape sequences.

  * `:keyword_constant` — `*` (catchall variant key).

  """

  @type class ::
          :punctuation
          | :name_variable
          | :name_function
          | :name_builtin
          | :name_tag
          | :name_attribute
          | :name_label
          | :string
          | :number_integer
          | :number_float
          | :text
          | :escape
          | :keyword_constant

  @type token :: {class(), String.t()}

  @doc """
  Walks the AST and returns a list of classified tokens.

  ### Arguments

  * `ast` is a parsed MF2 AST as returned by
    `Localize.Message.Parser.parse/1`.

  ### Returns

  * A list of `{class, text}` tuples.

  """
  @spec to_tokens(list() | tuple()) :: [token()]
  def to_tokens(ast) do
    ast
    |> walk()
    |> List.flatten()
    |> merge_adjacent()
  end

  # ── AST walkers (one clause per node shape, mirroring Print) ───

  defp walk(parts) when is_list(parts) do
    Enum.map(parts, &walk/1)
  end

  defp walk({:complex, declarations, body}) do
    [Enum.map(declarations, &walk/1), walk(body)]
  end

  defp walk({:quoted_pattern, parts}) do
    [
      tok(:punctuation, "{{"),
      Enum.map(parts, &walk/1),
      tok(:punctuation, "}}")
    ]
  end

  defp walk({:match, selectors, variants}) do
    sel_tokens =
      Enum.map(selectors, fn {:variable, name} ->
        [tok(:punctuation, " "), variable_tokens(name)]
      end)

    var_tokens =
      variants
      |> Enum.map(&walk/1)
      |> Enum.intersperse(tok(:text, "\n"))

    [
      tok(:name_builtin, ".match"),
      sel_tokens,
      tok(:text, "\n"),
      var_tokens
    ]
  end

  defp walk({:variant, keys, pattern}) do
    key_tokens =
      keys
      |> Enum.map(&key_tokens/1)
      |> Enum.intersperse(tok(:punctuation, " "))

    [key_tokens, tok(:punctuation, " "), walk(pattern)]
  end

  # ── Declarations ───────────────────────────────────────────────

  defp walk({:input, expr}) do
    [
      tok(:name_builtin, ".input"),
      tok(:punctuation, " "),
      expression_tokens(expr),
      tok(:text, "\n")
    ]
  end

  defp walk({:local, {:variable, name}, expr}) do
    [
      tok(:name_builtin, ".local"),
      tok(:punctuation, " "),
      variable_tokens(name),
      tok(:punctuation, " = "),
      expression_tokens(expr),
      tok(:text, "\n")
    ]
  end

  # ── Pattern parts ──────────────────────────────────────────────

  defp walk({:text, text}) do
    # `escape_text/1` inserts backslashes before `{`, `}`, `\`. We need
    # to emit the backslashes as :escape tokens and the plain parts as
    # :text so highlighters colour escapes distinctly.
    text
    |> split_text_escapes()
  end

  defp walk({:escape, char}) do
    [tok(:escape, "\\" <> char)]
  end

  defp walk({:expression, _, _, _} = expr) do
    expression_tokens(expr)
  end

  defp walk({:markup_open, name, options, attrs}) do
    [
      tok(:punctuation, "{#"),
      identifier_tokens(name, :name_tag),
      options_tokens(options),
      attrs_tokens(attrs),
      tok(:punctuation, "}")
    ]
  end

  defp walk({:markup_close, name, options, attrs}) do
    [
      tok(:punctuation, "{/"),
      identifier_tokens(name, :name_tag),
      options_tokens(options),
      attrs_tokens(attrs),
      tok(:punctuation, "}")
    ]
  end

  defp walk({:markup_standalone, name, options, attrs}) do
    [
      tok(:punctuation, "{#"),
      identifier_tokens(name, :name_tag),
      options_tokens(options),
      attrs_tokens(attrs),
      tok(:punctuation, " /}")
    ]
  end

  # ── Expressions ────────────────────────────────────────────────

  defp expression_tokens({:expression, operand, func, attrs}) do
    inner =
      [operand_tokens(operand), func_tokens(func), attrs_tokens(attrs)]
      |> Enum.reject(&(&1 == []))

    [tok(:punctuation, "{"), inner, tok(:punctuation, "}")]
  end

  defp operand_tokens(nil), do: []
  defp operand_tokens({:variable, name}), do: variable_tokens(name)
  defp operand_tokens({:literal, value}), do: literal_tokens(value, :quoted)
  defp operand_tokens({:number_literal, value}), do: [number_token(value)]

  defp func_tokens(nil), do: []

  defp func_tokens({:function, name, options}) do
    [
      tok(:punctuation, " "),
      function_identifier_tokens(name),
      options_tokens(options)
    ]
  end

  defp options_tokens([]), do: []

  defp options_tokens(options) do
    Enum.map(options, fn {:option, name, value} ->
      [
        tok(:punctuation, " "),
        tok(:name_label, name),
        tok(:punctuation, "="),
        value_tokens(value)
      ]
    end)
  end

  defp attrs_tokens([]), do: []

  defp attrs_tokens(attrs) do
    Enum.map(attrs, fn
      {:attribute, name, nil} ->
        [tok(:punctuation, " "), tok(:name_attribute, "@" <> name)]

      {:attribute, name, value} ->
        [
          tok(:punctuation, " "),
          tok(:name_attribute, "@" <> name),
          tok(:punctuation, "="),
          value_tokens(value)
        ]
    end)
  end

  defp value_tokens({:variable, name}), do: variable_tokens(name)
  defp value_tokens({:literal, value}), do: literal_tokens(value, :optional)
  defp value_tokens({:number_literal, value}), do: [number_token(value)]

  # Variant keys
  defp key_tokens(:catchall), do: [tok(:keyword_constant, "*")]
  defp key_tokens({:literal, value}), do: literal_tokens(value, :optional)
  defp key_tokens({:number_literal, value}), do: [number_token(value)]

  # ── Literal emission ───────────────────────────────────────────

  # Variant, option value, and attribute value literals may be
  # emitted unquoted if they're a valid name. Operand literals are
  # always quoted.
  defp literal_tokens("", :optional), do: [tok(:string, "||")]
  defp literal_tokens("", :quoted), do: [tok(:string, "||")]

  defp literal_tokens(value, :optional) do
    if unquoted_literal?(value) do
      [tok(:string, value)]
    else
      quoted_literal_tokens(value)
    end
  end

  defp literal_tokens(value, :quoted) do
    quoted_literal_tokens(value)
  end

  defp quoted_literal_tokens(value) do
    # Escape `\` and `|` inside the literal. Emit backslash-escapes
    # separately so the highlighter colours them as :escape.
    escaped = split_quoted_escapes(value)
    [tok(:string, "|"), escaped, tok(:string, "|")]
  end

  defp number_token(value) do
    if String.contains?(value, ".") do
      tok(:number_float, value)
    else
      tok(:number_integer, value)
    end
  end

  # ── Identifiers ────────────────────────────────────────────────

  # Function identifiers emit the leading `:` as part of the name,
  # matching the canonical syntax `:number`.
  defp function_identifier_tokens({:namespace, ns, name}) do
    [tok(:name_function, ":" <> ns <> ":" <> name)]
  end

  defp function_identifier_tokens(name) when is_binary(name) do
    [tok(:name_function, ":" <> name)]
  end

  # Markup tag identifiers do NOT include their leading `#` / `/` —
  # those are emitted by the markup walker as :punctuation.
  defp identifier_tokens({:namespace, ns, name}, class) do
    [tok(class, ns), tok(:punctuation, ":"), tok(class, name)]
  end

  defp identifier_tokens(name, class) when is_binary(name) do
    [tok(class, name)]
  end

  defp variable_tokens(name) do
    [tok(:name_variable, "$" <> name)]
  end

  # ── Text escape splitting ─────────────────────────────────────

  # When a `:text` node contains characters that need escaping in the
  # canonical form (`\`, `{`, `}`), we split them out so the `\`
  # prefix is classed as :escape and the rest stays as :text. The
  # concatenation of all tokens is identical to the output of
  # `Print.escape_text/1` — verified by round-trip tests.
  defp split_text_escapes(text) do
    text
    |> :binary.bin_to_list()
    |> split_text_chars([], [])
  end

  defp split_text_chars([], [], acc), do: Enum.reverse(acc)
  defp split_text_chars([], buf, acc), do: Enum.reverse([flush(:text, buf) | acc])

  defp split_text_chars([c | rest], buf, acc) when c in [?\\, ?{, ?}] do
    acc = if buf == [], do: acc, else: [flush(:text, buf) | acc]
    escape = tok(:escape, <<?\\, c>>)
    split_text_chars(rest, [], [escape | acc])
  end

  defp split_text_chars([c | rest], buf, acc) do
    split_text_chars(rest, [c | buf], acc)
  end

  defp flush(class, buf) do
    text = buf |> Enum.reverse() |> :binary.list_to_bin()
    tok(class, text)
  end

  # Same as above for quoted-literal escapes (`\` and `|`).
  defp split_quoted_escapes(text) do
    text
    |> :binary.bin_to_list()
    |> split_quoted_chars([], [])
  end

  defp split_quoted_chars([], [], acc), do: Enum.reverse(acc)
  defp split_quoted_chars([], buf, acc), do: Enum.reverse([flush(:string, buf) | acc])

  defp split_quoted_chars([c | rest], buf, acc) when c in [?\\, ?|] do
    acc = if buf == [], do: acc, else: [flush(:string, buf) | acc]
    escape = tok(:escape, <<?\\, c>>)
    split_quoted_chars(rest, [], [escape | acc])
  end

  defp split_quoted_chars([c | rest], buf, acc) do
    split_quoted_chars(rest, [c | buf], acc)
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp tok(class, text), do: {class, text}

  # Collapse adjacent tokens of the same class into one. Simplifies
  # downstream rendering and keeps the token list compact.
  defp merge_adjacent([]), do: []

  defp merge_adjacent([head | rest]) do
    Enum.reduce(rest, [head], fn
      {class, text}, [{class, prev_text} | acc] -> [{class, prev_text <> text} | acc]
      token, acc -> [token | acc]
    end)
    |> Enum.reverse()
  end

  # Name validation — duplicated from Print to keep modules independent.
  defp unquoted_literal?(""), do: false

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
end
