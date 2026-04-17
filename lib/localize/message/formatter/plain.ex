defmodule Localize.Message.Formatter.Plain do
  @moduledoc """
  Plain-text formatter for MF2 highlight tokens.

  Concatenates every token's text and discards the class. The output
  equals the canonical MF2 string produced by
  `Localize.Message.Print.to_string/1` — this property is verified
  in the highlighter test suite.

  """

  alias Localize.Message.Highlighter

  @doc """
  Concatenates the text of every token into a single string.

  ### Arguments

  * `tokens` is a list of `t:Highlighter.token/0` tuples.

  ### Returns

  * A plain string — the canonical MF2 message.

  """
  @spec render([Highlighter.token()]) :: String.t()
  def render(tokens) do
    tokens
    |> Enum.map(fn {_class, text} -> text end)
    |> IO.iodata_to_binary()
  end
end
