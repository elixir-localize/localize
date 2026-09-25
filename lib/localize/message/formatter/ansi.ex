defmodule Localize.Message.Formatter.ANSI do
  @moduledoc """
  ANSI terminal formatter for MF2 highlight tokens.

  Wraps each token in ANSI colour escape codes suitable for IEx
  output, `mix` task messages, or anywhere a terminal is assumed.
  Colours are chosen for legibility on both light and dark
  backgrounds using ANSI 4-bit colours only (no truecolor).

  """

  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

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

  ### Examples

      iex> {:ok, ast} = Localize.Message.Parser.parse("Hello {$name}!")
      iex> tokens = Localize.Message.Highlighter.to_tokens(ast)
      iex> rendered = Localize.Message.Formatter.ANSI.render(tokens)
      iex> String.contains?(rendered, "$name") and String.contains?(rendered, "\e[")
      true

  """
  @spec render([Highlighter.token()], options()) :: String.t() | {:error, Exception.t()}
  def render(tokens, options \\ [])

  def render(tokens, options) when is_list(tokens) and is_keyword_list(options) do
    with {:ok, palette} <- palette(Keyword.get(options, :palette, %{})) do
      for {class, text} when is_binary(text) <- tokens, into: "" do
        colorize(text, Map.get(palette, class, []))
      end
    end
  end

  def render(_tokens, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  def render(tokens, _options),
    do: {:error, Localize.Utils.Helpers.invalid_value(tokens, "a list of highlighter tokens")}

  defp colorize(text, []), do: text

  # `IO.ANSI.format/2` with `emit? = true` forces the escape
  # sequences to be rendered even when STDOUT isn't a TTY.
  # Without this, ANSI codes would only appear in interactive
  # shells, making the output untestable and unpredictable.
  defp colorize(text, codes) do
    codes
    |> Kernel.++([text, :reset])
    |> IO.ANSI.format(true)
    |> IO.iodata_to_binary()
  end

  # A palette overrides the default codes for some classes. Every code must be
  # one `IO.ANSI` defines, since `IO.ANSI.format/2` raises on any other.
  defp palette(palette) when is_map(palette) do
    case Enum.reject(palette, &ansi_codes?/1) do
      [] -> {:ok, Map.merge(@default_palette, palette)}
      [invalid | _rest] -> {:error, invalid_palette(invalid)}
    end
  end

  defp palette(palette), do: {:error, invalid_palette(palette)}

  defp ansi_codes?({_class, codes}) when is_list(codes), do: Enum.all?(codes, &ansi_code?/1)
  defp ansi_codes?(_entry), do: false

  defp ansi_code?(code) when is_atom(code) do
    Code.ensure_loaded?(IO.ANSI) and function_exported?(IO.ANSI, code, 0)
  end

  defp ansi_code?(_code), do: false

  defp invalid_palette(value) do
    Localize.Utils.Helpers.invalid_value(
      value,
      "a map of token classes to lists of IO.ANSI codes"
    )
  end
end
