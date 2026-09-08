defmodule Localize.Inflection.Synthesizer.Ro do
  @moduledoc false

  # The Romanian grammar synthesizer, ported from
  # `RoGrammarSynthesizer`: pure configuration over the shared
  # machinery. The definite article is an enclitic handled by the
  # dictionary inflection patterns via the definiteness constraint.

  @behaviour Localize.Inflection.Synthesizer

  alias Localize.Inflection.{Lookup, PrefixedDisplay}

  @locale :ro

  @priorities [
    ["noun", "adjective"],
    ["nominative", "genitive"],
    ["singular", "plural"],
    ["masculine", "feminine", "neuter"]
  ]

  @lookups %{
    "gender" => ["masculine", "feminine", "neuter"],
    "number" => ["singular", "plural"],
    "case" => ~w(nominative genitive dative accusative instrumental locative vocative),
    "definiteness" => ["definite", "indefinite"]
  }

  @impl true
  def feature_value(feature, display_value, _constraints) when is_map_key(@lookups, feature) do
    case Lookup.determine(@locale, display_value.display_string, Map.fetch!(@lookups, feature)) do
      "" -> nil
      value -> value
    end
  end

  def feature_value(_feature, _display_value, _constraints), do: nil

  @impl true
  def display_value(display_data, constraints, _guess?) do
    PrefixedDisplay.display_value(@locale, display_data, constraints,
      priorities: @priorities,
      extra_feature: "definiteness"
    )
  end
end
