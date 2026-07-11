defmodule Localize.Number.PluralRule.Compiler do
  @moduledoc false

  # Compiles CLDR plural rule definitions into Elixir AST.
  #
  # Uses the Erlang leex lexer (`:localize_plural_rules_lexer`) and yecc parser
  # (`:localize_plural_rules_parser`) to tokenize and parse rule definitions
  # from the ICU/CLDR plural rules syntax.

  @doc """
  Tokenize a plural rule definition.

  Uses the leex lexer to tokenize a CLDR plural rule definition
  string into a list of tokens.

  ### Arguments

  * `definition` is a CLDR plural rule definition string.

  ### Returns

  * `{:ok, tokens, end_line}` on success.

  * `{:error, reason}` on failure.

  """
  def tokenize(definition) when is_binary(definition) do
    definition
    |> String.to_charlist()
    |> :localize_plural_rules_lexer.string()
  end

  @doc """
  Parse a plural rule definition.

  Using the yecc parser, parse a rule definition into an Elixir
  AST that can then be `unquoted` into a function definition.

  ### Arguments

  * `tokens` is a list of tokens from `tokenize/1`, or a binary
    rule definition string.

  ### Returns

  * `{:ok, ast}` on success.

  * `{:error, reason}` on failure.

  """
  def parse(tokens) when is_list(tokens) do
    :localize_plural_rules_parser.parse(tokens)
  end

  def parse(definition) when is_binary(definition) do
    {:ok, tokens, _end_line} = tokenize(definition)
    :localize_plural_rules_parser.parse(tokens)
  end
end
