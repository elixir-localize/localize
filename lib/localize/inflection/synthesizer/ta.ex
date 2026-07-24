defmodule Localize.Inflection.Synthesizer.Ta do
  @moduledoc false

  # The Tamil grammar synthesizer, ported from
  # `TaGrammarSynthesizer`: a number lookup over the shared
  # phrase display function.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{GrammemeLookup, PhraseDisplay}

  @locale :ta

  @priorities [
    ["noun"],
    ["animate", "inanimate"],
    [
      "nominative",
      "accusative",
      "dative",
      "genitive",
      "instrumental",
      "ablative",
      "locative",
      "sociative",
      "benefactive",
      "vocative"
    ],
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
