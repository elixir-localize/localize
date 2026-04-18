defmodule Localize.Message.Formatter.HTML do
  @moduledoc """
  HTML formatter for MF2 highlight tokens.

  Wraps each token in a `<span class="mf2-<class>">...</span>`
  element with the token text HTML-escaped. Optionally wraps the
  whole output in `<pre class="mf2-highlight"><code>...</code></pre>`
  for standalone display.

  Class names use the same taxonomy as the tree-sitter highlight
  captures consumed by [`mf2_wasm_editor`](https://hex.pm/packages/mf2_wasm_editor)
  — `.mf2-variable`, `.mf2-punctuation-bracket`, `.mf2-string-escape`,
  etc. — so a single stylesheet styles both the server-rendered HTML
  produced here and the browser-side editor. Ready-made themes for
  both are shipped with `mf2_wasm_editor` under its `priv/themes/`
  directory.

  Atoms from the highlighter carry underscores (`:punctuation_bracket`)
  and are converted to hyphenated CSS classes (`.mf2-punctuation-bracket`)
  on emission. The `mf2-` prefix avoids conflicts with other
  highlighters on the same page (e.g. `makeup`).

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
    `"mf2-"` (produces e.g. `mf2-variable`, `mf2-punctuation-bracket`).

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
          class_name(class),
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

  # Turn a class atom into its CSS-class form: underscores become
  # hyphens so `:punctuation_bracket` emits `punctuation-bracket`,
  # matching the tree-sitter capture taxonomy used by the browser
  # editor's highlights.scm.
  defp class_name(class) do
    class
    |> Atom.to_string()
    |> String.replace("_", "-")
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
