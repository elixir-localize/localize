defmodule Localize.Number.Rbnf.Rule do
  @moduledoc false

  # RBNF rule data structure and parser.
  #
  # Each rule has a base_value (the starting number for this rule),
  # a radix (usually 10), a definition string containing the
  # formatting pattern, a range (upper bound), and a divisor.

  defstruct [:base_value, :radix, :definition, :range, :divisor]

  @type t :: %__MODULE__{
          base_value: integer() | String.t(),
          radix: integer(),
          definition: String.t(),
          range: integer() | String.t(),
          divisor: integer() | nil
        }

  # # tokenize/1
  # Tokenizes an RBNF rule definition string.
  #
  # ### Arguments
  # * `definition` is an RBNF rule definition string.
  #
  # ### Returns
  # * `{:ok, tokens, end_line}` or an error.
  @spec tokenize(String.t() | t()) :: {:ok, list(), integer()} | {:error, term()}
  def tokenize(definition) when is_binary(definition) do
    definition
    |> String.trim_leading("'")
    |> String.to_charlist()
    |> :rbnf_lexer.string()
  end

  def tokenize(%__MODULE__{definition: definition}) do
    tokenize(definition)
  end

  # # parse/1
  # Parses an RBNF rule definition into an AST.
  #
  # ### Arguments
  # * `definition` is an RBNF rule definition string or token list.
  #
  # ### Returns
  # * `{:ok, parsed}` where parsed is a list of
  #   `{operation, argument}` tuples.
  @spec parse(String.t() | list()) :: {:ok, list()} | {:error, term()}
  def parse(definition) when is_binary(definition) do
    {:ok, tokens, _end_line} = tokenize(definition)
    parse(tokens)
  end

  def parse([]) do
    {:ok, []}
  end

  def parse(tokens) when is_list(tokens) do
    :rbnf_parser.parse(tokens)
  end
end
