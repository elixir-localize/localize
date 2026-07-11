defmodule Localize.Number.Rbnf.Rule do
  @moduledoc false

  # RBNF rule data structure and parser.
  #
  # Each rule has a base_value (the starting number for this rule),
  # a radix (usually 10), a definition string containing the
  # formatting pattern, a range (upper bound), and a divisor.

  defstruct [
    :base_value,
    :radix,
    :definition,
    :range,
    :divisor,
    :fraction_numerator,
    :preceding_rule
  ]

  @type t :: %__MODULE__{
          base_value: integer() | String.t(),
          radix: integer(),
          definition: String.t(),
          range: integer() | String.t(),
          divisor: integer() | nil,
          fraction_numerator: integer() | nil,
          preceding_rule: map() | nil
        }

  # `preceding_rule` is set at `Localize.Number.Rbnf.Processor.process/5`
  # time to the rule immediately before the matched rule in the
  # *source* rule list (NOT the descending-base-value sort used by
  # `find_matching_integer_rule/2`). It is consulted by the integer
  # `:modulo_preceding` clause to implement TR35 §RBNF_Syntax's
  # `>>>` operator: "bypass normal rule selection and apply the
  # rule preceding this one in the rule list".

  # `fraction_numerator` is set only in the fraction-with-rule
  # numerator/denominator algorithm (see
  # `Localize.Number.Rbnf.Processor.format_fraction_via_rule/4`).
  # When a rule is matched against the *denominator* of a
  # fraction (for example ky's `%%z-spellout-fraction` base-10
  # rule firing on `0.5`'s denominator `10`), any `<<` substitution
  # in the rule body must use the *numerator* directly rather
  # than computing `div(denominator, rule.divisor)`. The
  # integer-quotient clause checks this field and short-circuits
  # to the pre-computed numerator.

  # # tokenize/1
  # Tokenizes an RBNF rule definition string.
  #
  # ### Arguments
  # * `definition` is an RBNF rule definition string.
  #
  # ### Returns
  # * `{:ok, tokens, end_line}` or an error.
  @spec tokenize(String.t() | t()) :: {:ok, list(), integer()} | {:error, term(), integer()}
  def tokenize(definition) when is_binary(definition) do
    definition
    |> String.trim_leading("'")
    |> String.to_charlist()
    |> :localize_rbnf_lexer.string()
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
    :localize_rbnf_parser.parse(tokens)
  end
end
