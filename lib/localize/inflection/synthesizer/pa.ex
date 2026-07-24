defmodule Localize.Inflection.Synthesizer.Pa do
  @moduledoc false

  # The Punjabi grammar synthesizer, ported from
  # `PaGrammarSynthesizer`: number/gender dictionary lookups over
  # the shared phrase display function.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{GrammemeLookup, PhraseDisplay}

  @locale :pa

  @genders ["masculine", "feminine"]
  @priorities [
    ["noun", "adjective"],
    ["direct", "oblique", "vocative"],
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
