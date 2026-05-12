defmodule Localize.Message.Sigil do
  @moduledoc """
  Implements sigil `~M` to canonicalize an ICU MessageFormat 2 message.

  ICU messages allow for whitespace to be used to format the message
  for developer and translator readability. At the same time, `gettext`
  uses the message string as a key when resolving translations.

  Therefore a developer or translator that modifies the message for
  readability may unintentionally create a new message rather than
  replace the old one simply because the message strings don't match
  exactly.

  The sigil `~M` therefore introduces a way for the developer to ensure
  the message is in a canonical format during compilation and therefore
  both error check the message format and ensure the message is in a
  canonical form irrespective of developer formatting.

  ## Compile-time validation

  `~M` parses the message at compile time. A syntax error fails
  compilation and the raised `CompileError` points at the exact line
  and column of the error *inside the sigil body*, adjusted to the
  sigil's source location so editors can jump directly to the
  offending character (including inside multi-line heredoc sigils).

  """

  @doc ~S"""
  Handles the sigil `~M` for ICU MessageFormat 2 message strings.

  It returns a canonically formatted string without interpolations and
  without escape characters, except for the escaping of the closing
  sigil character itself.

  A canonically formatted string is pretty-printed by default returning
  a potentially multi-line string. This is intended to produce a result
  which is easier to comprehend for translators.

  ### Modifiers

  * `p` (default) — pretty-print the message with indentation.

  * `u` — return a non-pretty-printed (compact) string.

  ### Examples

      iex> import Localize.Message.Sigil
      iex> ~M(An ICU message)
      "An ICU message"

  """
  defmacro sigil_M({:<<>>, meta, [message]}, modifiers) when is_binary(message) do
    options = Localize.Message.Sigil.options(modifiers)

    canonical_message =
      compile_time_parse_or_raise!(message, options, __CALLER__, meta)

    quote do
      unquote(canonical_message)
    end
  end

  @doc false
  defmacro sigil_m({:<<>>, meta, [message]}, modifiers) when is_binary(message) do
    options = Localize.Message.Sigil.options(modifiers)
    message = Macro.unescape_string(message)

    canonical_message =
      compile_time_parse_or_raise!(message, options, __CALLER__, meta)

    quote do
      unquote(canonical_message)
    end
  end

  defmacro sigil_m({:<<>>, meta, pieces}, modifiers) do
    options = Localize.Message.Sigil.options(modifiers)
    message = {:<<>>, meta, unescape_tokens(pieces)}

    quote do
      Localize.Message.canonical_message!(unquote(message), unquote(options))
    end
  end

  @doc false
  def options([pretty]) when pretty in [?u, ?U] do
    [pretty: false]
  end

  def options(_modifiers) do
    [pretty: true]
  end

  # Parse + canonicalise at compile time. On success, return the
  # canonical string. On failure, raise a `CompileError` whose `:line`
  # points at the actual error location inside the sigil body (sigil
  # start line + MF2 error line - 1) so IDEs jump to the right spot.
  @doc false
  def compile_time_parse_or_raise!(message, options, caller, meta) do
    try do
      Localize.Message.canonical_message!(message, options)
    rescue
      error in Localize.ParseError -> reraise_as_compile_error(error, caller, meta)
    end
  end

  @spec reraise_as_compile_error(Localize.ParseError.t(), Macro.Env.t(), keyword()) :: no_return()
  defp reraise_as_compile_error(%Localize.ParseError{} = error, caller, meta) do
    sigil_line = Keyword.get(meta, :line, caller.line)

    error_line =
      case error.line do
        nil -> sigil_line
        n when is_integer(n) -> sigil_line + n - 1
      end

    column = error.column || 1

    raise CompileError,
      file: caller.file,
      line: error_line,
      description:
        "invalid MF2 message in ~M sigil at column #{column}: #{Exception.message(error)}"
  end

  defp unescape_tokens(tokens) do
    Enum.map(tokens, fn
      token when is_binary(token) -> Macro.unescape_string(token)
      other -> other
    end)
  end
end
