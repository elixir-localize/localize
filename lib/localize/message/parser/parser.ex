defmodule Localize.Message.Parser do
  @moduledoc """
  Implements a parser for
  [ICU MessageFormat 2](https://unicode.org/reports/tr35/tr35-messageFormat.html).

  """

  import Localize.Message.Parser.Helpers

  @doc """
  Parses a MessageFormat 2 message string.

  ### Arguments

  * `input` is a MF2 message string.

  ### Returns

  * `{:ok, ast}` where `ast` is the parsed message AST.

  * `{:error, reason}` if the message cannot be parsed.

  ### Examples

      iex> Localize.Message.Parser.parse("{{Hello, world!}}")
      {:ok, [{:complex, [], {:quoted_pattern, [{:text, "Hello, world!"}]}}]}

  """
  @spec parse(String.t()) :: {:ok, list()} | {:error, Localize.ParseError.t()}

  def parse(input) when is_binary(input) do
    cap = max_message_bytes()

    if byte_size(input) > cap do
      {:error,
       Localize.ParseError.exception(
         reason: :input_too_large,
         detail: "message",
         size: byte_size(input),
         limit: cap
       )}
    else
      do_parse(input)
    end
  end

  # Maximum byte length accepted by `parse/1` and `parse!/1`. Caps the
  # parser's CPU exposure on hostile or accidentally-huge messages.
  # Override with `config :localize, :max_message_bytes, n` (default
  # 65 536 — generous for any human-authored message).
  @default_max_message_bytes 65_536

  @doc false
  def max_message_bytes do
    Application.get_env(:localize, :max_message_bytes, @default_max_message_bytes)
  end

  defp do_parse(input) do
    case message(input) do
      {:ok, result, "", _, _, _} ->
        {:ok, result}

      {:ok, _result, rest, _, _, offset} ->
        {:error,
         Localize.ParseError.exception(
           input: input,
           reason: :unexpected_trailing_input,
           offset: offset,
           rest: rest
         )}

      {:error, detail, rest, _, _, offset} ->
        {:error,
         Localize.ParseError.exception(
           input: input,
           reason: :unexpected_input,
           detail: detail,
           offset: offset,
           rest: rest
         )}
    end
  end

  @doc """
  Parses a MessageFormat 2 message string, raising on error.

  Same as `parse/1` but returns the AST directly or raises
  `Localize.ParseError`.

  ### Arguments

  * `input` is a MF2 message string.

  ### Returns

  * The parsed message AST.

  ### Examples

      iex> Localize.Message.Parser.parse!("{{Hello, world!}}")
      [{:complex, [], {:quoted_pattern, [{:text, "Hello, world!"}]}}]

  """
  @spec parse!(String.t()) :: list() | no_return

  def parse!(input) when is_binary(input) do
    case parse(input) do
      {:ok, parsed} -> parsed
      {:error, error} -> raise error
    end
  end

  # parsec:Localize.Message.Parser

  import NimbleParsec

  import Localize.Message.Parser.Combinator,
    except: [
      wrap_escape: 1,
      to_nfc_string: 1,
      wrap_identifier: 1,
      wrap_quoted_literal: 1,
      wrap_number_literal: 1,
      wrap_option: 1,
      wrap_attribute: 1,
      wrap_function: 1,
      wrap_expression: 1,
      wrap_markup_open: 1,
      wrap_markup_close: 1,
      wrap_text: 1,
      wrap_quoted_pattern: 1,
      wrap_input: 1,
      wrap_local: 1,
      wrap_variant: 1,
      wrap_matcher: 1,
      wrap_complex: 1,
      maybe_wrap_leading_ws: 5,
      coalesce_text: 5
    ]

  # ── Compile-time optimization ──────────────────────────────────
  # Break out the most deeply nested combinators to prevent
  # NimbleParsec from inlining 33 UTF-8 ranges at every call site.
  defparsecp(:name_p, name())

  # Rebuild identifier/variable/literal to use name_p, then
  # break those out too since they're each used 4-6 times.
  identifier_v =
    parsec(:name_p)
    |> optional(ignore(string(":")) |> concat(parsec(:name_p)))
    |> reduce(:wrap_identifier)

  defparsecp(:identifier_p, identifier_v)

  variable_v =
    ignore(string("$"))
    |> concat(parsec(:name_p))
    |> unwrap_and_tag(:variable)

  defparsecp(:variable_p, variable_v)

  unquoted_literal_v =
    choice([
      number_literal(),
      times(name_char(), min: 1)
      |> reduce(:to_nfc_string)
      |> unwrap_and_tag(:literal)
    ])

  literal_v = choice([quoted_literal(), unquoted_literal_v])
  defparsecp(:literal_p, literal_v)

  # Rebuild option/attribute/function using the parsec references
  option_v =
    parsec(:identifier_p)
    |> concat(o())
    |> ignore(string("="))
    |> concat(o())
    |> concat(choice([parsec(:literal_p), parsec(:variable_p)]))
    |> reduce(:wrap_option)

  attribute_v =
    ignore(string("@"))
    |> concat(parsec(:identifier_p))
    |> optional(concat(o(), ignore(string("="))) |> concat(o()) |> concat(parsec(:literal_p)))
    |> reduce(:wrap_attribute)

  function_v =
    ignore(string(":"))
    |> concat(parsec(:identifier_p))
    |> repeat(s() |> concat(option_v))
    |> reduce(:wrap_function)

  # Rebuild expressions
  literal_expression_v =
    ignore(string("{"))
    |> concat(o())
    |> concat(parsec(:literal_p))
    |> optional(s() |> concat(function_v))
    |> repeat(s() |> concat(attribute_v))
    |> concat(o())
    |> ignore(string("}"))
    |> reduce(:wrap_expression)

  variable_expression_v =
    ignore(string("{"))
    |> concat(o())
    |> concat(parsec(:variable_p))
    |> optional(s() |> concat(function_v))
    |> repeat(s() |> concat(attribute_v))
    |> concat(o())
    |> ignore(string("}"))
    |> reduce(:wrap_expression)

  function_expression_v =
    ignore(string("{"))
    |> concat(o())
    |> concat(function_v)
    |> repeat(s() |> concat(attribute_v))
    |> concat(o())
    |> ignore(string("}"))
    |> reduce(:wrap_expression)

  expression_v =
    choice([literal_expression_v, variable_expression_v, function_expression_v])

  defparsecp(:expression_p, expression_v)

  # Rebuild markup using parsec references
  markup_open_v =
    ignore(string("{"))
    |> concat(o())
    |> ignore(string("#"))
    |> concat(parsec(:identifier_p))
    |> repeat(s() |> concat(option_v))
    |> repeat(s() |> concat(attribute_v))
    |> concat(o())
    |> choice([
      ignore(string("/")) |> concat(o()) |> ignore(string("}")) |> replace(:standalone),
      ignore(string("}")) |> replace(:open)
    ])
    |> reduce(:wrap_markup_open)

  markup_close_v =
    ignore(string("{"))
    |> concat(o())
    |> ignore(string("/"))
    |> concat(parsec(:identifier_p))
    |> repeat(s() |> concat(option_v))
    |> repeat(s() |> concat(attribute_v))
    |> concat(o())
    |> ignore(string("}"))
    |> reduce(:wrap_markup_close)

  markup_v = choice([markup_open_v, markup_close_v])
  placeholder_v = choice([parsec(:expression_p), markup_v])

  # Rebuild pattern/quoted_pattern
  pattern_v =
    repeat(
      choice([
        escaped_char(),
        placeholder_v,
        times(text_char(), min: 1) |> reduce(:wrap_text)
      ])
    )

  quoted_pattern_v =
    ignore(string("{{"))
    |> concat(pattern_v)
    |> ignore(string("}}"))
    |> reduce(:wrap_quoted_pattern)

  # Rebuild declarations
  input_declaration_v =
    ignore(string(".input"))
    |> concat(o())
    |> concat(parsec(:expression_p))
    |> reduce(:wrap_input)

  local_declaration_v =
    ignore(string(".local"))
    |> concat(s())
    |> concat(parsec(:variable_p))
    |> concat(o())
    |> ignore(string("="))
    |> concat(o())
    |> concat(parsec(:expression_p))
    |> reduce(:wrap_local)

  declaration_v = choice([input_declaration_v, local_declaration_v])

  # Rebuild match/complex
  key_v = choice([parsec(:literal_p), string("*") |> replace(:catchall)])

  # variant = key *(s key) o quoted-pattern
  #
  # The `s` between successive keys is *required whitespace*, not
  # optional. Using `o()` here (as we used to) made the parser
  # accept adjacent-key inputs like `**` that the spec explicitly
  # rejects as syntax errors — caught by the MF2 WG conformance
  # suite at test/localize/message/conformance_test.exs.
  variant_v =
    key_v
    |> repeat(s() |> concat(key_v))
    |> concat(o())
    |> concat(quoted_pattern_v)
    |> reduce(:wrap_variant)

  matcher_v =
    ignore(string(".match"))
    |> times(s() |> concat(parsec(:variable_p)), min: 1)
    |> concat(s())
    |> concat(variant_v)
    |> repeat(o() |> concat(variant_v))
    |> reduce(:wrap_matcher)

  complex_body_v = choice([matcher_v, quoted_pattern_v])

  complex_message_v =
    o()
    |> repeat(declaration_v |> concat(o()))
    |> concat(complex_body_v)
    |> concat(o())
    |> reduce(:wrap_complex)

  # Rebuild simple message
  simple_message_v =
    repeat(choice([ws(), bidi()]))
    |> post_traverse(:maybe_wrap_leading_ws)
    |> optional(
      choice([
        escaped_char(),
        placeholder_v,
        times(simple_start_char(), min: 1) |> reduce(:wrap_text)
      ])
      |> concat(pattern_v)
    )
    |> post_traverse(:coalesce_text)

  # Top-level
  message_v =
    choice([complex_message_v, simple_message_v])
    |> eos()
    |> label("an MF2 message")

  defparsec(:message, message_v)

  # parsec:Localize.Message.Parser
end
