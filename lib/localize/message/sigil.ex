defmodule Localize.Message.Sigil do
  @moduledoc """
  Implements sigil `~M` to canonicalize an ICU message.

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

  """

  @doc ~S"""
  Handles the sigil `~M` for ICU message strings.

  It returns a canonically formatted string without
  interpolations and without escape characters, except
  for the escaping of the closing sigil character itself.

  A canonically formatted string is pretty-printed by
  default returning a potentially multi-line string. This
  is intended to produce a result which is easier to
  comprehend for translators.

  The modifier `u` can be applied to return a
  non-pretty-printed string.

  ### Modifiers

  * `p` (default) — pretty-print the message with indentation.

  * `u` — return a non-pretty-printed (compact) string.

  ### Examples

      iex> import Localize.Message.Sigil
      iex> ~M(An ICU message)
      "An ICU message"

  """
  defmacro sigil_M({:<<>>, _meta, [message]}, modifiers) when is_binary(message) do
    options = Localize.Message.Sigil.options(modifiers)
    canonical_message = Localize.Message.canonical_message!(message, options)

    quote do
      unquote(canonical_message)
    end
  end

  @doc false
  defmacro sigil_m({:<<>>, _meta, [message]}, modifiers) when is_binary(message) do
    options = Localize.Message.Sigil.options(modifiers)
    message = Macro.unescape_string(message)
    canonical_message = Localize.Message.canonical_message!(message, options)

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

  @doc false
  defp unescape_tokens(tokens) do
    Enum.map(tokens, fn
      token when is_binary(token) -> Macro.unescape_string(token)
      other -> other
    end)
  end
end
