defmodule Localize.Inflection.Synthesizer.Ur do
  @moduledoc false

  # The Urdu grammar synthesizer, ported from
  # `UrGrammarSynthesizer`: number/gender dictionary lookups over
  # the shared phrase display function.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{GrammemeLookup, PhraseDisplay}

  @locale :ur

  @genders ["masculine", "feminine"]
  @priorities [
    ["noun", "adjective"],
    ["direct", "oblique"],
    ["singular", "plural"],
    @genders
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

  def feature_value("gender", display_value, _constraints) do
    case GrammemeLookup.determine(@locale, display_value.display_string, @genders,
           default: "masculine",
           first_word_determines?: true
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
