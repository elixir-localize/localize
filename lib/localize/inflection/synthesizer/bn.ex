defmodule Localize.Inflection.Synthesizer.Bn do
  @moduledoc false

  # The Bengali grammar synthesizer, ported from
  # `BnGrammarSynthesizer`: a number lookup over the shared
  # phrase display function.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{GrammemeLookup, PhraseDisplay}

  @locale :bn

  @priorities [
    ["noun", "adjective"],
    ["singular", "plural"]
  ]

  @impl true
  def feature_value(feature, display_value, constraints)

  def feature_value("number", display_value, _constraints) do
    case GrammemeLookup.determine(@locale, display_value.display_string, ["singular", "plural"],
           disambiguation: ["noun"]
         ) do
      "" -> nil
      value -> value
    end
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  @impl true
  def display_value(display_data, constraints, _guess?) do
    PhraseDisplay.display_value(@locale, display_data, constraints, priorities: @priorities)
  end
end
