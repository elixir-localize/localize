defmodule Localize.Message.Formatter.ANSI do
  @moduledoc """
  ANSI terminal formatter for MF2 highlight tokens.

  Wraps each token in ANSI colour escape codes suitable for IEx
  output, `mix` task messages, or anywhere a terminal is assumed.
  Colours are chosen for legibility on both light and dark
  backgrounds using ANSI 4-bit colours only (no truecolor).

  """

  alias Localize.Message.Highlighter

  @type options :: [palette: %{Highlighter.class() => [atom()]}]

  # Default palette: each class maps to a list of IO.ANSI sequences
  # (applied in order, then the text, then :reset).
  @default_palette %{
    text: [:default_color],
    string_escape: [:light_yellow],
    punctuation_bracket: [:cyan],
    variable: [:green],
    function: [:blue],
    keyword: [:magenta, :bright],
    tag: [:magenta],
    attribute: [:light_magenta],
    property: [:light_blue],
    string: [:yellow],
    number: [:light_red],
    constant_builtin: [:cyan, :bright]
  }

  @doc """
  Renders a token list as an ANSI-coloured string.

  ### Arguments

  * `tokens` is a list of `t:Highlighter.token/0` tuples.

  * `options` is a keyword list.

  ### Options

  * `:palette` — a map `%{class => [ansi_atom]}` overriding the
    default colour for specific classes.

  ### Returns

  * A string containing ANSI escape codes.

  """
  @spec render([Highlighter.token()], options()) :: String.t()
  def render(tokens, options \\ []) do
    palette = Map.merge(@default_palette, Keyword.get(options, :palette, %{}))

    tokens
    |> Enum.map(fn {class, text} ->
      codes = Map.get(palette, class, [])

      case codes do
        [] ->
          text

        codes ->
          # `IO.ANSI.format/2` with `emit? = true` forces the escape
          # sequences to be rendered even when STDOUT isn't a TTY.
          # Without this, ANSI codes would only appear in interactive
          # shells, making the output untestable and unpredictable.
          IO.ANSI.format(codes ++ [text, :reset], true)
      end
    end)
    |> IO.iodata_to_binary()
  end
end
