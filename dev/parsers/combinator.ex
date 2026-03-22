defmodule Localize.Message.Parser.Combinator do
  @moduledoc false

  import NimbleParsec

  # ── Whitespace & Bidi ──────────────────────────────────────────────

  # ws = SP / HTAB / CR / LF / %x3000
  def ws do
    utf8_char([?\s, ?\t, ?\r, ?\n, 0x3000])
  end

  # bidi = %x061C / %x200E / %x200F / %x2066-2069
  def bidi do
    utf8_char([0x061C, 0x200E, 0x200F, 0x2066..0x2069])
  end

  # o = *(ws / bidi)
  def o do
    repeat(choice([ws(), bidi()]))
    |> ignore()
  end

  # s = *bidi ws o  (required whitespace)
  def s do
    repeat(bidi())
    |> concat(ws())
    |> concat(o())
    |> ignore()
  end

  # ── Escapes ────────────────────────────────────────────────────────

  # escaped-char = backslash ( backslash / "{" / "|" / "}" )
  def escaped_char do
    ignore(string("\\"))
    |> choice([
      string("\\"),
      string("{"),
      string("|"),
      string("}")
    ])
    |> reduce(:wrap_escape)
  end

  def wrap_escape([char]), do: {:escape, char}

  # ── Character classes ──────────────────────────────────────────────

  # text-char: omit NULL, \, {, }
  def text_char do
    utf8_char([
      # omit NULL (%x00) and \ (%x5C)
      0x01..0x5B,
      # omit { (%x7B)
      0x5D..0x7A,
      # include |
      0x7C,
      # omit } (%x7D)
      0x7E..0x10FFFF
    ])
  end

  # simple-start-char: omit NULL, HTAB, LF, CR, SP, ., \, {, }
  def simple_start_char do
    utf8_char([
      0x01..0x08,
      0x0B..0x0C,
      0x0E..0x1F,
      # omit . (%x2E)
      0x21..0x2D,
      # omit \ (%x5C)
      0x2F..0x5B,
      # omit { (%x7B)
      0x5D..0x7A,
      # include |
      0x7C,
      # omit } (%x7D)
      0x7E..0x2FFF,
      # omit ideographic space (%x3000)
      0x3001..0x10FFFF
    ])
  end

  # quoted-char: omit NULL, \, |
  def quoted_char do
    utf8_char([
      # omit NULL and \
      0x01..0x5B,
      # omit | (%x7C)
      0x5D..0x7B,
      0x7D..0x10FFFF
    ])
  end

  # ── Names & Identifiers ───────────────────────────────────────────

  # name-start = ALPHA / _ / + / <extended unicode>
  def name_start do
    utf8_char([
      ?A..?Z,
      ?a..?z,
      # _
      0x5F,
      # +
      0x2B,
      0xA1..0x61B,
      0x61D..0x167F,
      0x1681..0x1FFF,
      0x200B..0x200D,
      0x2010..0x2027,
      0x2030..0x205E,
      0x2060..0x2065,
      0x206A..0x2FFF,
      0x3001..0xD7FF,
      0xE000..0xFDCF,
      0xFDF0..0xFFFD,
      0x10000..0x1FFFD,
      0x20000..0x2FFFD,
      0x30000..0x3FFFD,
      0x40000..0x4FFFD,
      0x50000..0x5FFFD,
      0x60000..0x6FFFD,
      0x70000..0x7FFFD,
      0x80000..0x8FFFD,
      0x90000..0x9FFFD,
      0xA0000..0xAFFFD,
      0xB0000..0xBFFFD,
      0xC0000..0xCFFFD,
      0xD0000..0xDFFFD,
      0xE0000..0xEFFFD,
      0xF0000..0xFFFFD,
      0x100000..0x10FFFD
    ])
  end

  # name-char = name-start / DIGIT / "-" / "."
  def name_char do
    choice([
      name_start(),
      utf8_char([?0..?9, ?-, ?.])
    ])
  end

  # name = [bidi] name-start *name-char [bidi]
  def name do
    optional(ignore(bidi()))
    |> concat(name_start())
    |> repeat(name_char())
    |> optional(ignore(bidi()))
    |> reduce(:to_nfc_string)
  end

  @doc false
  def to_nfc_string(chars) do
    chars |> List.to_string() |> :unicode.characters_to_nfc_binary()
  end

  # identifier = [namespace ":"] name
  def identifier do
    name()
    |> optional(
      ignore(string(":"))
      |> concat(name())
    )
    |> reduce(:wrap_identifier)
  end

  def wrap_identifier([name]), do: name
  def wrap_identifier([namespace, name]), do: {:namespace, namespace, name}

  # ── Literals ───────────────────────────────────────────────────────

  # quoted-literal = "|" *(quoted-char / escaped-char) "|"
  def quoted_literal do
    ignore(string("|"))
    |> repeat(
      choice([
        escaped_char(),
        quoted_char() |> reduce({List, :to_string, []})
      ])
    )
    |> ignore(string("|"))
    |> reduce(:wrap_quoted_literal)
  end

  def wrap_quoted_literal(parts) do
    text =
      parts
      |> Enum.map_join(fn
        {:escape, c} -> c
        s when is_binary(s) -> s
      end)
      |> :unicode.characters_to_nfc_binary()

    {:literal, text}
  end

  # unquoted-literal = name / number-literal
  # number-literal = ["-"] (%x30 / (%x31-39 *DIGIT)) ["." 1*DIGIT] [%i"e" ["-" / "+"] 1*DIGIT]
  def number_literal do
    optional(string("-"))
    |> choice([
      string("0"),
      ascii_char([?1..?9]) |> repeat(ascii_char([?0..?9])) |> reduce({List, :to_string, []})
    ])
    |> optional(
      string(".")
      |> times(ascii_char([?0..?9]), min: 1)
      |> reduce({List, :to_string, []})
    )
    |> optional(
      ascii_string([?e, ?E], 1)
      |> optional(ascii_string([?+, ?-], 1))
      |> times(ascii_char([?0..?9]), min: 1)
      |> reduce({List, :to_string, []})
    )
    |> reduce(:wrap_number_literal)
  end

  def wrap_number_literal(parts) do
    text = Enum.join(parts)
    {:number_literal, text}
  end

  # unquoted-literal = name-char+ (but disambiguated: try number first, then name)
  def unquoted_literal do
    choice([
      number_literal(),
      times(name_char(), min: 1)
      |> reduce(:to_nfc_string)
      |> unwrap_and_tag(:literal)
    ])
  end

  # literal = quoted-literal / unquoted-literal
  def literal do
    choice([quoted_literal(), unquoted_literal()])
  end

  # ── Variables ──────────────────────────────────────────────────────

  # variable = "$" name
  def variable do
    ignore(string("$"))
    |> concat(name())
    |> unwrap_and_tag(:variable)
  end

  # ── Functions, Options, Attributes ─────────────────────────────────

  # option = identifier o "=" o (literal / variable)
  def option do
    identifier()
    |> concat(o())
    |> ignore(string("="))
    |> concat(o())
    |> concat(choice([literal(), variable()]))
    |> reduce(:wrap_option)
  end

  def wrap_option([name, value]), do: {:option, name, value}

  # attribute = "@" identifier [o "=" o literal]
  def attribute do
    ignore(string("@"))
    |> concat(identifier())
    |> optional(
      concat(o(), ignore(string("=")))
      |> concat(o())
      |> concat(literal())
    )
    |> reduce(:wrap_attribute)
  end

  def wrap_attribute([name]), do: {:attribute, name, nil}
  def wrap_attribute([name, value]), do: {:attribute, name, value}

  # function = ":" identifier *(s option)
  def function do
    ignore(string(":"))
    |> concat(identifier())
    |> repeat(s() |> concat(option()))
    |> reduce(:wrap_function)
  end

  def wrap_function([name | options]), do: {:function, name, options}

  # ── Expressions ────────────────────────────────────────────────────

  # literal-expression = "{" o literal [s function] *(s attribute) o "}"
  def literal_expression do
    ignore(string("{"))
    |> concat(o())
    |> concat(literal())
    |> optional(s() |> concat(function()))
    |> repeat(s() |> concat(attribute()))
    |> concat(o())
    |> ignore(string("}"))
    |> reduce(:wrap_expression)
  end

  # variable-expression = "{" o variable [s function] *(s attribute) o "}"
  def variable_expression do
    ignore(string("{"))
    |> concat(o())
    |> concat(variable())
    |> optional(s() |> concat(function()))
    |> repeat(s() |> concat(attribute()))
    |> concat(o())
    |> ignore(string("}"))
    |> reduce(:wrap_expression)
  end

  # function-expression = "{" o function *(s attribute) o "}"
  def function_expression do
    ignore(string("{"))
    |> concat(o())
    |> concat(function())
    |> repeat(s() |> concat(attribute()))
    |> concat(o())
    |> ignore(string("}"))
    |> reduce(:wrap_expression)
  end

  def wrap_expression(parts) do
    {operand, rest} =
      case parts do
        [{tag, _} = op | rest] when tag in [:variable, :literal, :number_literal] -> {op, rest}
        rest -> {nil, rest}
      end

    {func, rest} =
      case rest do
        [{:function, _, _} = f | rest] -> {f, rest}
        rest -> {nil, rest}
      end

    attributes = Enum.filter(rest, &match?({:attribute, _, _}, &1))
    {:expression, operand, func, attributes}
  end

  # expression = literal-expression / variable-expression / function-expression
  def expression do
    choice([
      literal_expression(),
      variable_expression(),
      function_expression()
    ])
  end

  # ── Markup ─────────────────────────────────────────────────────────

  # markup open/standalone = "{" o "#" identifier *(s option) *(s attribute) o ["/"] "}"
  def markup_open_or_standalone do
    ignore(string("{"))
    |> concat(o())
    |> ignore(string("#"))
    |> concat(identifier())
    |> repeat(s() |> concat(option()))
    |> repeat(s() |> concat(attribute()))
    |> concat(o())
    |> choice([
      ignore(string("/")) |> concat(o()) |> ignore(string("}")) |> replace(:standalone),
      ignore(string("}")) |> replace(:open)
    ])
    |> reduce(:wrap_markup_open)
  end

  def wrap_markup_open(parts) do
    [kind | rest] = Enum.reverse(parts)
    [name | opts_and_attrs] = Enum.reverse(rest)
    {options, attributes} = Enum.split_with(opts_and_attrs, &match?({:option, _, _}, &1))

    case kind do
      :standalone -> {:markup_standalone, name, options, attributes}
      :open -> {:markup_open, name, options, attributes}
    end
  end

  # markup close = "{" o "/" identifier *(s option) *(s attribute) o "}"
  def markup_close do
    ignore(string("{"))
    |> concat(o())
    |> ignore(string("/"))
    |> concat(identifier())
    |> repeat(s() |> concat(option()))
    |> repeat(s() |> concat(attribute()))
    |> concat(o())
    |> ignore(string("}"))
    |> reduce(:wrap_markup_close)
  end

  def wrap_markup_close([name | opts_and_attrs]) do
    {options, attributes} = Enum.split_with(opts_and_attrs, &match?({:option, _, _}, &1))
    {:markup_close, name, options, attributes}
  end

  # markup = open/standalone / close
  def markup do
    choice([markup_open_or_standalone(), markup_close()])
  end

  # placeholder = expression / markup
  def placeholder do
    choice([expression(), markup()])
  end

  # ── Pattern ────────────────────────────────────────────────────────

  # pattern = *(text-char / escaped-char / placeholder)
  def pattern do
    repeat(
      choice([
        escaped_char(),
        placeholder(),
        times(text_char(), min: 1)
        |> reduce(:wrap_text)
      ])
    )
  end

  def wrap_text(chars), do: {:text, List.to_string(chars)}

  # quoted-pattern = "{{" pattern "}}"
  def quoted_pattern do
    ignore(string("{{"))
    |> concat(pattern())
    |> ignore(string("}}"))
    |> reduce(:wrap_quoted_pattern)
  end

  def wrap_quoted_pattern(parts), do: {:quoted_pattern, parts}

  # ── Declarations ───────────────────────────────────────────────────

  # input-declaration = input o variable-expression
  def input_declaration do
    ignore(string(".input"))
    |> concat(o())
    |> concat(variable_expression())
    |> reduce(:wrap_input)
  end

  def wrap_input([expr]), do: {:input, expr}

  # local-declaration = local s variable o "=" o expression
  def local_declaration do
    ignore(string(".local"))
    |> concat(s())
    |> concat(variable())
    |> concat(o())
    |> ignore(string("="))
    |> concat(o())
    |> concat(expression())
    |> reduce(:wrap_local)
  end

  def wrap_local([var, expr]), do: {:local, var, expr}

  # declaration = input-declaration / local-declaration
  def declaration do
    choice([input_declaration(), local_declaration()])
  end

  # ── Matcher ────────────────────────────────────────────────────────

  # selector = variable
  def selector, do: variable()

  # key = literal / "*"
  def key do
    choice([
      string("*") |> replace(:catchall),
      literal()
    ])
  end

  # variant = key *(s key) o quoted-pattern
  def variant do
    key()
    |> repeat(s() |> concat(key()))
    |> concat(o())
    |> concat(quoted_pattern())
    |> reduce(:wrap_variant)
  end

  def wrap_variant(parts) do
    {pattern, keys} = List.pop_at(parts, -1)
    {:variant, keys, pattern}
  end

  # match-statement = match 1*(s selector)
  def match_statement do
    ignore(string(".match"))
    |> times(s() |> concat(selector()), min: 1)
  end

  # matcher = match-statement s variant *(o variant)
  def matcher do
    match_statement()
    |> concat(s())
    |> concat(variant())
    |> repeat(o() |> concat(variant()))
    |> reduce(:wrap_matcher)
  end

  def wrap_matcher(parts) do
    {selectors, variants} =
      Enum.split_with(parts, fn
        {:variable, _} -> true
        {:variant, _, _} -> false
      end)

    {:match, selectors, variants}
  end

  # ── Top-level ──────────────────────────────────────────────────────

  # complex-body = quoted-pattern / matcher
  def complex_body do
    choice([quoted_pattern(), matcher()])
  end

  # complex-message = o *(declaration o) complex-body o
  def complex_message do
    o()
    |> repeat(declaration() |> concat(o()))
    |> concat(complex_body())
    |> concat(o())
    |> reduce(:wrap_complex)
  end

  def wrap_complex(parts) do
    {declarations, [body]} =
      Enum.split_with(parts, fn
        {:input, _} -> true
        {:local, _, _} -> true
        _ -> false
      end)

    {:complex, declarations, body}
  end

  # simple-message = o [simple-start pattern]
  # simple-start = simple-start-char / escaped-char / placeholder
  #
  # Leading whitespace in a simple message is significant and part of
  # the message content per the spec, so we capture it as text rather
  # than ignoring it.
  def simple_message do
    repeat(choice([ws(), bidi()]))
    |> post_traverse(:maybe_wrap_leading_ws)
    |> optional(
      choice([
        escaped_char(),
        placeholder(),
        times(simple_start_char(), min: 1)
        |> reduce(:wrap_text)
      ])
      |> concat(pattern())
    )
    |> post_traverse(:coalesce_text)
  end

  def maybe_wrap_leading_ws(rest, [], context, _line, _offset), do: {rest, [], context}

  def maybe_wrap_leading_ws(rest, chars, context, _line, _offset) do
    text = chars |> Enum.reverse() |> List.to_string()
    {rest, [{:text, text}], context}
  end

  # message = simple-message / complex-message
  def message do
    choice([complex_message(), simple_message()])
    |> eos()
    |> label("an MF2 message")
  end

  # Coalesce adjacent {:text, _} nodes into a single node.
  # post_traverse receives (rest, acc, context).
  # The accumulator is in reverse parse order (most recent first).
  # We reverse to forward order, coalesce, then reverse back.
  def coalesce_text(rest, acc, context, _line, _offset) do
    coalesced =
      acc
      |> Enum.reverse()
      |> coalesce_text_forward([])

    {rest, coalesced, context}
  end

  # Process in forward order, build result in reverse (which is what
  # NimbleParsec expects as accumulator)
  defp coalesce_text_forward([], result), do: result

  defp coalesce_text_forward([{:text, t1}, {:text, t2} | rest], result) do
    coalesce_text_forward([{:text, t1 <> t2} | rest], result)
  end

  defp coalesce_text_forward([head | rest], result) do
    coalesce_text_forward(rest, [head | result])
  end
end
