defmodule Localize.Message.Formatter.HTML do
  @moduledoc """
  HTML formatter for MF2 highlight tokens.

  Wraps each token in a `<span class="mf2-<class>">...</span>`
  element with the token text HTML-escaped. Optionally wraps the
  whole output in `<pre class="mf2-highlight"><code>...</code></pre>`
  for standalone display.

  The `mf2-` CSS class prefix avoids conflicts with other syntax
  highlighters on the same page (e.g. `makeup`). Users supply their
  own CSS to style the classes.

  """

  alias Localize.Message.Highlighter

  @type options :: [
          standalone: boolean(),
          wrapper_tag: String.t(),
          wrapper_class: String.t(),
          span_tag: String.t(),
          class_prefix: String.t()
        ]

  @default_wrapper_tag "pre"
  @default_wrapper_class "mf2-highlight"
  @default_span_tag "span"
  @default_class_prefix "mf2-"

  @doc """
  Renders a token list as HTML.

  ### Arguments

  * `tokens` is a list of `t:Highlighter.token/0` tuples.

  * `options` is a keyword list.

  ### Options

  * `:standalone` — when `true`, wraps the output in a `<pre><code>`
    block. Default `false` (produces a fragment suitable for inline
    embedding).

  * `:wrapper_tag` — tag used for the standalone wrapper. Default
    `"pre"`.

  * `:wrapper_class` — CSS class for the wrapper. Default
    `"mf2-highlight"`.

  * `:span_tag` — tag used per token. Default `"span"`.

  * `:class_prefix` — prefix for per-token CSS classes. Default
    `"mf2-"` (produces e.g. `mf2-name_variable`).

  ### Returns

  * An HTML string.

  """
  @spec render([Highlighter.token()], options()) :: String.t()
  def render(tokens, options \\ []) do
    span_tag = Keyword.get(options, :span_tag, @default_span_tag)
    class_prefix = Keyword.get(options, :class_prefix, @default_class_prefix)

    inner =
      tokens
      |> Enum.map(fn {class, text} ->
        [
          "<",
          span_tag,
          ~s( class="),
          class_prefix,
          Atom.to_string(class),
          ~s(">),
          escape(text),
          "</",
          span_tag,
          ">"
        ]
      end)

    output =
      if Keyword.get(options, :standalone, false) do
        wrapper_tag = Keyword.get(options, :wrapper_tag, @default_wrapper_tag)
        wrapper_class = Keyword.get(options, :wrapper_class, @default_wrapper_class)

        [
          "<",
          wrapper_tag,
          ~s( class="),
          wrapper_class,
          ~s("><code>),
          inner,
          "</code></",
          wrapper_tag,
          ">"
        ]
      else
        inner
      end

    IO.iodata_to_binary(output)
  end

  # HTML-escape the five reserved characters. We don't escape single
  # quotes because we use double-quoted attributes.
  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
