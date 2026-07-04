defmodule Localize.Message.Formatter do
  @moduledoc """
  Dispatch module for rendering MF2 highlight tokens.

  Delegates to one of the format-specific formatter modules based on
  the `:format` option:

  * `:plain` — plain text, discards classes. Used internally to
    produce the canonical MF2 string from a token stream.

  * `:html` — HTML with per-token `<span>` wrappers.
    See `Localize.Message.Formatter.HTML`.

  * `:ansi` — ANSI-coloured terminal output.
    See `Localize.Message.Formatter.ANSI`.

  """

  alias Localize.Message.Formatter.{ANSI, HTML, Plain}
  alias Localize.Message.Highlighter

  @type format :: :plain | :html | :ansi

  @doc """
  Renders a token list in the chosen format.

  ### Arguments

  * `tokens` is a list of `t:Highlighter.token/0` tuples.

  * `format` is one of `:plain`, `:html`, or `:ansi`.

  * `options` is a keyword list of format-specific options.

  ### Returns

  * A rendered string.

  """
  @spec render([Highlighter.token()], format(), Keyword.t()) :: String.t()
  def render(tokens, format, options \\ [])

  def render(tokens, :plain, _options), do: Plain.render(tokens)
  def render(tokens, :html, options), do: HTML.render(tokens, options)
  def render(tokens, :ansi, options), do: ANSI.render(tokens, options)
end
