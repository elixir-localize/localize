defmodule Localize.Number.ParserDifferentialTest do
  @moduledoc """
  Compares `Localize.Number.Parser` with `Localize.Number.ReferenceParser`,
  the parser as it stood when the lexer-based rewrite began
  (`plans/number-parser-grammar.md`), on every input
  `Localize.Number.ParserDifferential` generates.

  Excluded by default. Run it with `mix test --include differential`, and
  across every installed locale with
  `LOCALIZE_DIFFERENTIAL_LOCALES=all ERL_FLAGS="+MIscs 8192"`.

  """

  use ExUnit.Case, async: false

  alias Localize.Number.ParserDifferential, as: Differential

  @moduletag :differential
  @moduletag timeout: :infinity

  test "parse_currency_amount/2 reads every amount as the reference does" do
    inputs = Differential.amount_inputs(Differential.locales())
    differences = Differential.differences(inputs)

    IO.puts("\n#{length(inputs)} amount inputs, #{length(differences)} differences")
    assert differences == [], Differential.report(differences)
  end

  test "parse/2 reads every number as the reference does" do
    inputs = Differential.number_inputs(Differential.locales())
    differences = Differential.differences(inputs)

    IO.puts("\n#{length(inputs)} number inputs, #{length(differences)} differences")
    assert differences == [], Differential.report(differences)
  end
end
